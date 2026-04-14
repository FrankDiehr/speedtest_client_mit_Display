#!/usr/bin/env bash
# shellcheck shell=bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../etc/config.sh"

ensure_runtime_dirs() {
  mkdir -p \
    "$BIN_DIR" \
    "$ETC_DIR" \
    "$LIB_DIR" \
    "$LOG_DIR" \
    "$RUN_DIR" \
    "$TMP_DIR" \
    "$SPOOL_DIR/pending/ping" \
    "$SPOOL_DIR/pending/dns" \
    "$SPOOL_DIR/pending/speedtest" \
    "$SPOOL_DIR/pending/hardware" \
    "$SPOOL_DIR/pending/traceroute" \
    "$SPOOL_DIR/pending/delivery" \
    "$SPOOL_DIR/sent/ping" \
    "$SPOOL_DIR/sent/dns" \
    "$SPOOL_DIR/sent/speedtest" \
    "$SPOOL_DIR/sent/hardware" \
    "$SPOOL_DIR/sent/traceroute" \
    "$SPOOL_DIR/sent/delivery" \
    "$SPOOL_DIR/failed/ping" \
    "$SPOOL_DIR/failed/dns" \
    "$SPOOL_DIR/failed/speedtest" \
    "$SPOOL_DIR/failed/hardware" \
    "$SPOOL_DIR/failed/traceroute" \
    "$SPOOL_DIR/failed/delivery"
}

log_ts() {
  "$CMD_DATE" -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  local level="$1"
  shift
  local msg="$*"
  local line
  line="$(log_ts) [$level] $msg"
  printf '%s\n' "$line" >> "$LOG_DIR/speedmon.log"
  if [[ "${LOG_TO_STDERR:-0}" == "1" ]]; then
    printf '%s\n' "$line" >&2
  fi
}

die() {
  log "ERROR" "$*"
  exit 1
}

require_cmd() {
  local missing=0
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "ERROR" "Required command not found: $cmd"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]]
}

csv_escape() {
  local val="${1:-}"
  val="${val//$'\r'/ }"
  val="${val//$'\n'/ }"
  val="${val//\"/\"\"}"
  printf '"%s"' "$val"
}

now_epoch() {
  "$CMD_DATE" +%s
}

ensure_header() {
  local file="$1"
  local header="$2"
  if [[ ! -f "$file" ]]; then
    printf '%s\n' "$header" > "$file"
  fi
}

make_id() {
  printf '%s-%s-%s\n' "$CLIENT_ID" "$(now_epoch)" "$RANDOM"
}

queue_file_path() {
  local metric="$1"
  local ts id
  ts="$("$CMD_DATE" -u +%Y%m%dT%H%M%SZ)"
  id="$(make_id)"
  printf '%s/pending/%s/%s__%s.csv\n' "$SPOOL_DIR" "$metric" "$ts" "$id"
}

is_valid_float() {
  local value="${1:-}"
  [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

is_valid_int() {
  local value="${1:-}"
  [[ "$value" =~ ^-?[0-9]+$ ]]
}

normalize_float() {
  local value="${1:-}"
  local fallback="${2:-0}"

  value="$(printf '%s' "$value" | tr ',' '.' | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  if is_valid_float "$value"; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

normalize_int() {
  local value="${1:-}"
  local fallback="${2:-0}"

  value="$(printf '%s' "$value" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  if is_valid_int "$value"; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

extract_first_float() {
  local value="${1:-}"
  printf '%s\n' "$value" \
    | sed -nE 's/.*(-?[0-9]+([.][0-9]+)?).*/\1/p' \
    | head -n1
}

cleanup_old_files() {
  local base_dir="$1"
  local max_age_sec="$2"
  local pattern="${3:-*.csv}"
  local now mtime age

  [[ -d "$base_dir" ]] || return 0

  now="$(now_epoch)"

  find "$base_dir" -type f -name "$pattern" 2>/dev/null | while read -r file; do
    mtime="$(stat -c '%Y' "$file" 2>/dev/null || echo 0)"
    age=$(( now - mtime ))

    if (( age > max_age_sec )); then
      rm -f -- "$file"
      log "INFO" "Deleted old file: $file"
    fi
  done
}

truncate_log_if_too_large() {
  local file="$1"
  local max_mb="$2"
  local max_bytes size

  [[ -f "$file" ]] || return 0

  max_bytes=$(( max_mb * 1024 * 1024 ))
  size="$(stat -c '%s' "$file" 2>/dev/null || echo 0)"

  if (( size >= max_bytes )); then
    : > "$file"
    log "WARN" "Truncated oversized log: $file"
  fi
}

prune_excess_pending_files() {
  local metric="$1"
  local dir="$SPOOL_DIR/pending/$metric"
  local count

  count="$(find "$dir" -maxdepth 1 -type f -name '*.csv' 2>/dev/null | wc -l)"

  if (( count > MAX_PENDING_FILES_PER_METRIC )); then
    find "$dir" -maxdepth 1 -type f -name '*.csv' -printf '%T@ %p\n' 2>/dev/null \
      | sort -n \
      | head -n $(( count - MAX_PENDING_FILES_PER_METRIC )) \
      | cut -d' ' -f2- \
      | while read -r victim; do
          rm -f -- "$victim"
          log "WARN" "Pruned excess pending file: $victim"
        done
  fi
}

prune_excess_files_in_dir() {
  local dir="$1"
  local max_files="$2"
  local pattern="${3:-*.csv}"
  local count

  [[ -d "$dir" ]] || return 0

  count="$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)"

  if (( count > max_files )); then
    find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
      | sort -n \
      | head -n $(( count - max_files )) \
      | cut -d' ' -f2- \
      | while read -r victim; do
          rm -f -- "$victim"
          log "WARN" "Pruned excess file: $victim"
        done
  fi
}

get_public_ip() {
  local url ip
  for url in "${PUBLIC_IP_URLS[@]}"; do
    ip="$("$CMD_CURL" -fsS --connect-timeout 5 --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  return 1
}

get_default_gateway() {
  "$CMD_IP" route 2>/dev/null | "$CMD_AWK" '/default/ {print $3; exit}'
}

get_default_iface() {
  "$CMD_IP" route 2>/dev/null | "$CMD_AWK" '/default/ {print $5; exit}'
}

get_lan_ips() {
  "$CMD_IP" -4 addr show scope global 2>/dev/null \
    | "$CMD_AWK" '/inet / {print $2}' \
    | cut -d/ -f1 \
    | paste -sd ';' -
}

get_dhcp_lease_ips() {
  local candidates=(
    "/var/lib/dhcp/dhclient.leases"
    "/var/lib/dhcpcd5/dhcpcd-*.lease"
    "/var/lib/NetworkManager/*.lease"
    "/run/systemd/netif/leases/*"
  )

  grep -hE 'fixed-address|ADDRESS=' "${candidates[@]}" 2>/dev/null \
    | sed -E 's/.*(fixed-address|ADDRESS=)[[:space:]]*//; s/;//' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | paste -sd ';' -
}

get_cpu_temp_c() {
  local raw temp

  if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    raw="$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || true)"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
      awk -v t="$raw" 'BEGIN { printf "%.1f", t/1000 }'
      return 0
    fi
  fi

  if command -v vcgencmd >/dev/null 2>&1; then
    raw="$(vcgencmd measure_temp 2>/dev/null || true)"
    temp="$(extract_first_float "$raw")"
    temp="$(normalize_float "$temp" "")"
    if [[ -n "$temp" ]]; then
      printf '%s' "$temp"
      return 0
    fi
  fi

  printf ''
}

acquire_lock() {
  local name="$1"
  local fd=200
  eval "exec ${fd}>\"$RUN_DIR/${name}.lock\""
  "$CMD_FLOCK" -n "$fd"
}

update_state() {
  local key="$1"
  local value="$2"
  printf '%s\n' "$value" > "$RUN_DIR/${key}.state"
}

read_state() {
  local key="$1"
  [[ -f "$RUN_DIR/${key}.state" ]] && cat "$RUN_DIR/${key}.state"
}

build_api_headers() {
  local queue_file="${1:-}"
  local headers=()

  headers+=( -H "Authorization: Bearer $API_TOKEN" )
  headers+=( -H "X-Client-Id: $CLIENT_ID" )
  headers+=( -H "X-Site-Name: $SITE_NAME" )

  if [[ -n "$queue_file" ]]; then
    headers+=( -H "X-Queue-File: $queue_file" )
  fi

  headers+=( -H "Content-Type: $DELIVERY_RAW_BODY_CONTENT_TYPE" )

  printf '%s\n' "${headers[@]}"
}

move_to_sent() {
  local metric="$1"
  local src="$2"
  local dst="$SPOOL_DIR/sent/$metric/$(basename "$src")"
  mv -f -- "$src" "$dst"
}

move_to_failed() {
  local metric="$1"
  local src="$2"
  local dst="$SPOOL_DIR/failed/$metric/$(basename "$src")"
  mv -f -- "$src" "$dst"
}

write_kv_csv_file() {
  local metric="$1"
  local header="$2"
  local row="$3"
  local file

  file="$(queue_file_path "$metric")"
  {
    printf '%s\n' "$header"
    printf '%s\n' "$row"
  } > "$file"

  prune_excess_pending_files "$metric"
  printf '%s\n' "$file"
}

ensure_runtime_dirs
