#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd "$CMD_PING" "$CMD_DATE" "$CMD_FLOCK" "$CMD_SED" "$CMD_GREP" || die "Missing required commands"

if ! acquire_lock "collect-ping"; then
  log "WARN" "collect-ping already running, exiting"
  exit 0
fi

PING_HEADER='id,timestamp_utc,client_id,site_name,target,status,latency_ms,packet_loss_percent,public_ip,lan_ips,default_iface'

stop_requested=0

on_exit() {
  stop_requested=1
  log "INFO" "collect-ping stopping"
}

trap on_exit INT TERM

ping_minute_file() {
  local ts_min
  ts_min="$("$CMD_DATE" -u +%Y%m%dT%H%M)"
  printf '%s/pending/ping/%s.csv\n' "$SPOOL_DIR" "$ts_min"
}

extract_latency_ms() {
  local text="$1"
  printf '%s\n' "$text" \
    | "$CMD_SED" -nE 's/.*time=([0-9.]+)[[:space:]]*ms.*/\1/p' \
    | head -n 1
}

extract_packet_loss_percent() {
  local text="$1"
  printf '%s\n' "$text" \
    | "$CMD_SED" -nE 's/.* ([0-9.]+)% packet loss.*/\1/p' \
    | head -n 1
}

normalize_float() {
  local value="${1:-}"
  if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s\n' "$value"
  else
    printf '0\n'
  fi
}

write_ping_row() {
  local file="$1"
  local row="$2"

  exec 201>>"$file"
  "$CMD_FLOCK" -x 201

  if [[ ! -s "$file" ]]; then
    printf '%s\n' "$PING_HEADER" >&201
  fi

  printf '%s\n' "$row" >&201

  "$CMD_FLOCK" -u 201
  exec 201>&-
}

main_loop() {
  local target output rc timestamp_utc file row latency_ms packet_loss public_ip lan_ips default_iface status id

  while (( stop_requested == 0 )); do
    target="$PING_TARGET_PRIMARY"
    timestamp_utc="$(log_ts)"
    file="$(ping_minute_file)"
    id="ping-$(now_epoch)-$RANDOM"

    output="$("$CMD_PING" -n -c 1 -W 1 "$target" 2>&1 || true)"

    rc=0
    if printf '%s\n' "$output" | "$CMD_GREP" -q '1 received'; then
      rc=0
    elif printf '%s\n' "$output" | "$CMD_GREP" -q '1 packets transmitted, 1 packets received'; then
      rc=0
    elif printf '%s\n' "$output" | "$CMD_GREP" -q '1 packets transmitted, 1 received'; then
      rc=0
    else
      rc=1
    fi

    latency_ms="$(extract_latency_ms "$output")"
    packet_loss="$(extract_packet_loss_percent "$output")"

    if [[ -z "$packet_loss" ]]; then
      if [[ "$rc" -eq 0 ]]; then
        packet_loss="0"
      else
        packet_loss="100"
      fi
    fi

    if [[ "$rc" -eq 0 ]]; then
      status="ok"
      latency_ms="$(normalize_float "$latency_ms")"
      packet_loss="$(normalize_float "$packet_loss")"
    else
      status="fail"
      latency_ms="0"
      packet_loss="100"
    fi

    public_ip="$(get_public_ip || true)"
    lan_ips="$(get_lan_ips || true)"
    default_iface="$(get_default_iface || true)"

    row="$(
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$id")" \
        "$(csv_escape "$timestamp_utc")" \
        "$(csv_escape "$CLIENT_ID")" \
        "$(csv_escape "$SITE_NAME")" \
        "$(csv_escape "$target")" \
        "$(csv_escape "$status")" \
        "$(csv_escape "$latency_ms")" \
        "$(csv_escape "$packet_loss")" \
        "$(csv_escape "$public_ip")" \
        "$(csv_escape "$lan_ips")" \
        "$(csv_escape "$default_iface")"
    )"

    write_ping_row "$file" "$row"

    prune_excess_pending_files "ping"

    sleep "$PING_LOOP_INTERVAL_SEC"
  done
}

log "INFO" "collect-ping started"
main_loop
