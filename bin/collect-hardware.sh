#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd "$CMD_DATE" "$CMD_HOSTNAME" "$CMD_AWK" "$CMD_DF" "$CMD_FREE" "$CMD_IP" "$CMD_SS" || die "Missing required commands"

if ! acquire_lock "collect-hardware"; then
  log "WARN" "collect-hardware already running, exiting"
  exit 0
fi

HARDWARE_HEADER='id,timestamp_utc,client_id,site_name,hostname,loadavg_1,loadavg_5,loadavg_15,cpu_usage_pct,cpu_temp_c,mem_total_mb,mem_used_mb,mem_free_mb,mem_available_mb,disk_root_total_mb,disk_root_used_mb,disk_root_free_mb,disk_root_used_pct,uptime_seconds,lan_ips,dhcp_ips,public_ip,default_iface,default_gateway,iface_operstate,iface_carrier,rx_bytes,tx_bytes,rx_packets,tx_packets,rx_errors,tx_errors,rx_dropped,tx_dropped,process_count,tcp_connections'

read_loadavg() {
  awk '{print $1 "," $2 "," $3}' /proc/loadavg
}

read_cpu_usage_pct() {
  local user1 nice1 sys1 idle1 iowait1 irq1 softirq1 steal1
  local user2 nice2 sys2 idle2 iowait2 irq2 softirq2 steal2
  local total1 total2 idle_total1 idle_total2 delta_total delta_idle

  read -r _ user1 nice1 sys1 idle1 iowait1 irq1 softirq1 steal1 _ _ < /proc/stat
  sleep 1
  read -r _ user2 nice2 sys2 idle2 iowait2 irq2 softirq2 steal2 _ _ < /proc/stat

  total1=$(( user1 + nice1 + sys1 + idle1 + iowait1 + irq1 + softirq1 + steal1 ))
  total2=$(( user2 + nice2 + sys2 + idle2 + iowait2 + irq2 + softirq2 + steal2 ))
  idle_total1=$(( idle1 + iowait1 ))
  idle_total2=$(( idle2 + iowait2 ))

  delta_total=$(( total2 - total1 ))
  delta_idle=$(( idle_total2 - idle_total1 ))

  if (( delta_total <= 0 )); then
    printf '0'
    return 0
  fi

  awk -v dt="$delta_total" -v di="$delta_idle" 'BEGIN { printf "%.1f", ((dt-di)*100)/dt }'
}

read_memory_mb() {
  local total used free available

  total="$("$CMD_FREE" -m | awk '/^Mem:/ {print $2}')"
  used="$("$CMD_FREE" -m | awk '/^Mem:/ {print $3}')"
  free="$("$CMD_FREE" -m | awk '/^Mem:/ {print $4}')"
  available="$("$CMD_FREE" -m | awk '/^Mem:/ {print $7}')"

  printf '%s,%s,%s,%s\n' \
    "$(normalize_int "$total")" \
    "$(normalize_int "$used")" \
    "$(normalize_int "$free")" \
    "$(normalize_int "$available")"
}

read_disk_root_mb() {
  local total used free used_pct

  total="$("$CMD_DF" -Pm / | awk 'NR==2 {print $2}')"
  used="$("$CMD_DF" -Pm / | awk 'NR==2 {print $3}')"
  free="$("$CMD_DF" -Pm / | awk 'NR==2 {print $4}')"
  used_pct="$("$CMD_DF" -Pm / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

  printf '%s,%s,%s,%s\n' \
    "$(normalize_int "$total")" \
    "$(normalize_int "$used")" \
    "$(normalize_int "$free")" \
    "$(normalize_float "$used_pct")"
}

read_uptime_seconds() {
  awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || printf '0'
}

read_iface_operstate() {
  local iface="${1:-}"
  [[ -n "$iface" && -r "/sys/class/net/$iface/operstate" ]] || { printf ''; return 0; }
  cat "/sys/class/net/$iface/operstate" 2>/dev/null || printf ''
}

read_iface_carrier() {
  local iface="${1:-}"
  [[ -n "$iface" && -r "/sys/class/net/$iface/carrier" ]] || { printf '0'; return 0; }
  cat "/sys/class/net/$iface/carrier" 2>/dev/null || printf '0'
}

read_iface_stat() {
  local iface="${1:-}"
  local name="${2:-}"
  local path="/sys/class/net/$iface/statistics/$name"

  [[ -n "$iface" && -r "$path" ]] || { printf '0'; return 0; }
  cat "$path" 2>/dev/null || printf '0'
}

read_process_count() {
  ps -e --no-headers 2>/dev/null | wc -l | awk '{print $1}'
}

read_tcp_connections() {
  "$CMD_SS" -tan 2>/dev/null | awk 'NR>1 {count++} END {print count+0}'
}

main() {
  local id timestamp_utc hostname
  local loadavg_1 loadavg_5 loadavg_15
  local cpu_usage_pct cpu_temp_c
  local mem_total_mb mem_used_mb mem_free_mb mem_available_mb
  local disk_root_total_mb disk_root_used_mb disk_root_free_mb disk_root_used_pct
  local uptime_seconds lan_ips dhcp_ips public_ip default_iface default_gateway
  local iface_operstate iface_carrier
  local rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped
  local process_count tcp_connections
  local row file

  id="$(make_id)"
  timestamp_utc="$(log_ts)"
  hostname="$("$CMD_HOSTNAME" -s 2>/dev/null || echo unknown)"

  IFS=',' read -r loadavg_1 loadavg_5 loadavg_15 <<< "$(read_loadavg)"
  cpu_usage_pct="$(read_cpu_usage_pct || true)"
  cpu_temp_c="$(get_cpu_temp_c || true)"

  IFS=',' read -r mem_total_mb mem_used_mb mem_free_mb mem_available_mb <<< "$(read_memory_mb)"
  IFS=',' read -r disk_root_total_mb disk_root_used_mb disk_root_free_mb disk_root_used_pct <<< "$(read_disk_root_mb)"

  uptime_seconds="$(read_uptime_seconds || true)"
  lan_ips="$(get_lan_ips || true)"
  dhcp_ips="$(get_dhcp_lease_ips || true)"
  public_ip="$(get_public_ip || true)"
  default_iface="$(get_default_iface || true)"
  default_gateway="$(get_default_gateway || true)"

  iface_operstate="$(read_iface_operstate "$default_iface" || true)"
  iface_carrier="$(read_iface_carrier "$default_iface" || true)"

  rx_bytes="$(read_iface_stat "$default_iface" rx_bytes || true)"
  tx_bytes="$(read_iface_stat "$default_iface" tx_bytes || true)"
  rx_packets="$(read_iface_stat "$default_iface" rx_packets || true)"
  tx_packets="$(read_iface_stat "$default_iface" tx_packets || true)"
  rx_errors="$(read_iface_stat "$default_iface" rx_errors || true)"
  tx_errors="$(read_iface_stat "$default_iface" tx_errors || true)"
  rx_dropped="$(read_iface_stat "$default_iface" rx_dropped || true)"
  tx_dropped="$(read_iface_stat "$default_iface" tx_dropped || true)"

  process_count="$(read_process_count || true)"
  tcp_connections="$(read_tcp_connections || true)"

  # Numerische Felder zentral hart normalisieren
  loadavg_1="$(normalize_float "$loadavg_1")"
  loadavg_5="$(normalize_float "$loadavg_5")"
  loadavg_15="$(normalize_float "$loadavg_15")"
  cpu_usage_pct="$(normalize_float "$cpu_usage_pct")"
  cpu_temp_c="$(normalize_float "$cpu_temp_c")"

  mem_total_mb="$(normalize_int "$mem_total_mb")"
  mem_used_mb="$(normalize_int "$mem_used_mb")"
  mem_free_mb="$(normalize_int "$mem_free_mb")"
  mem_available_mb="$(normalize_int "$mem_available_mb")"

  disk_root_total_mb="$(normalize_int "$disk_root_total_mb")"
  disk_root_used_mb="$(normalize_int "$disk_root_used_mb")"
  disk_root_free_mb="$(normalize_int "$disk_root_free_mb")"
  disk_root_used_pct="$(normalize_float "$disk_root_used_pct")"

  uptime_seconds="$(normalize_int "$uptime_seconds")"
  iface_carrier="$(normalize_int "$iface_carrier")"

  rx_bytes="$(normalize_int "$rx_bytes")"
  tx_bytes="$(normalize_int "$tx_bytes")"
  rx_packets="$(normalize_int "$rx_packets")"
  tx_packets="$(normalize_int "$tx_packets")"
  rx_errors="$(normalize_int "$rx_errors")"
  tx_errors="$(normalize_int "$tx_errors")"
  rx_dropped="$(normalize_int "$rx_dropped")"
  tx_dropped="$(normalize_int "$tx_dropped")"

  process_count="$(normalize_int "$process_count")"
  tcp_connections="$(normalize_int "$tcp_connections")"

  row="$(
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$(csv_escape "$id")" \
      "$(csv_escape "$timestamp_utc")" \
      "$(csv_escape "$CLIENT_ID")" \
      "$(csv_escape "$SITE_NAME")" \
      "$(csv_escape "$hostname")" \
      "$(csv_escape "$loadavg_1")" \
      "$(csv_escape "$loadavg_5")" \
      "$(csv_escape "$loadavg_15")" \
      "$(csv_escape "$cpu_usage_pct")" \
      "$(csv_escape "$cpu_temp_c")" \
      "$(csv_escape "$mem_total_mb")" \
      "$(csv_escape "$mem_used_mb")" \
      "$(csv_escape "$mem_free_mb")" \
      "$(csv_escape "$mem_available_mb")" \
      "$(csv_escape "$disk_root_total_mb")" \
      "$(csv_escape "$disk_root_used_mb")" \
      "$(csv_escape "$disk_root_free_mb")" \
      "$(csv_escape "$disk_root_used_pct")" \
      "$(csv_escape "$uptime_seconds")" \
      "$(csv_escape "$lan_ips")" \
      "$(csv_escape "$dhcp_ips")" \
      "$(csv_escape "$public_ip")" \
      "$(csv_escape "$default_iface")" \
      "$(csv_escape "$default_gateway")" \
      "$(csv_escape "$iface_operstate")" \
      "$(csv_escape "$iface_carrier")" \
      "$(csv_escape "$rx_bytes")" \
      "$(csv_escape "$tx_bytes")" \
      "$(csv_escape "$rx_packets")" \
      "$(csv_escape "$tx_packets")" \
      "$(csv_escape "$rx_errors")" \
      "$(csv_escape "$tx_errors")" \
      "$(csv_escape "$rx_dropped")" \
      "$(csv_escape "$tx_dropped")" \
      "$(csv_escape "$process_count")" \
      "$(csv_escape "$tcp_connections")"
  )"

  file="$(write_kv_csv_file "hardware" "$HARDWARE_HEADER" "$row")"
  log "INFO" "Hardware metrics written: $file"
}

main "$@"
