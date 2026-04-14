#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

STATE_FILE="$RUN_DIR/display-state.json"

require_cmd "$CMD_JQ" || die "jq is required for update-display-state.sh"
mkdir -p "$RUN_DIR"

FIRST_SPEEDTEST_DELAY_SEC="${FIRST_SPEEDTEST_DELAY_SEC:-}"

read_json_string() {
  local key="$1"
  if [[ -f "$STATE_FILE" ]]; then
    "$CMD_JQ" -r --arg k "$key" '.[$k] // empty' "$STATE_FILE" 2>/dev/null || true
  fi
}

read_json_number() {
  local key="$1"
  if [[ -f "$STATE_FILE" ]]; then
    "$CMD_JQ" -r --arg k "$key" '.[$k] // 0' "$STATE_FILE" 2>/dev/null || true
  else
    printf '0\n'
  fi
}

resolve_first_run_delay_sec() {
  if [[ -n "${FIRST_SPEEDTEST_DELAY_SEC:-}" && "$FIRST_SPEEDTEST_DELAY_SEC" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$FIRST_SPEEDTEST_DELAY_SEC"
  else
    printf '%s\n' $(( SPEEDTEST_INTERVAL_MIN * 60 ))
  fi
}

write_state() {
  local running="$1"
  local last_status="$2"
  local last_download_mbps="$3"
  local last_upload_mbps="$4"
  local last_ping_ms="$5"
  local last_jitter_ms="$6"
  local last_result_ts="$7"
  local last_server_name="$8"
  local next_run_epoch="$9"
  local awaiting_first_speedtest="${10}"

  local tmp_file
  tmp_file="$(mktemp "$RUN_DIR/display-state.XXXXXX.tmp")"

  "$CMD_JQ" -n \
    --argjson speedtest_running "$running" \
    --arg last_status "$last_status" \
    --arg last_result_ts "$last_result_ts" \
    --arg last_server_name "$last_server_name" \
    --argjson last_download_mbps "$last_download_mbps" \
    --argjson last_upload_mbps "$last_upload_mbps" \
    --argjson last_ping_ms "$last_ping_ms" \
    --argjson last_jitter_ms "$last_jitter_ms" \
    --argjson next_run_epoch "$next_run_epoch" \
    --argjson speedtest_interval_min "$SPEEDTEST_INTERVAL_MIN" \
    --argjson updated_epoch "$(now_epoch)" \
    --argjson boot_epoch "$(now_epoch)" \
    --argjson awaiting_first_speedtest "$awaiting_first_speedtest" \
    '{
      speedtest_running: $speedtest_running,
      last_status: $last_status,
      last_download_mbps: $last_download_mbps,
      last_upload_mbps: $last_upload_mbps,
      last_ping_ms: $last_ping_ms,
      last_jitter_ms: $last_jitter_ms,
      last_result_ts: $last_result_ts,
      last_server_name: $last_server_name,
      next_run_epoch: $next_run_epoch,
      speedtest_interval_min: $speedtest_interval_min,
      updated_epoch: $updated_epoch,
      boot_epoch: $boot_epoch,
      awaiting_first_speedtest: $awaiting_first_speedtest
    }' > "$tmp_file"

  mv -f "$tmp_file" "$STATE_FILE"
}

cmd="${1:-}"

case "$cmd" in
  init)
    now="$(now_epoch)"
    first_delay_sec="$(resolve_first_run_delay_sec)"
    next_run_epoch=$(( now + first_delay_sec ))

    last_status="$(read_json_string "last_status")"
    [[ -n "$last_status" ]] || last_status="no_data"

    last_download_mbps="$(normalize_float "$(read_json_number "last_download_mbps")" "0")"
    last_upload_mbps="$(normalize_float "$(read_json_number "last_upload_mbps")" "0")"
    last_ping_ms="$(normalize_float "$(read_json_number "last_ping_ms")" "0")"
    last_jitter_ms="$(normalize_float "$(read_json_number "last_jitter_ms")" "0")"
    last_result_ts="$(read_json_string "last_result_ts")"
    last_server_name="$(read_json_string "last_server_name")"

    write_state \
      false \
      "$last_status" \
      "$last_download_mbps" \
      "$last_upload_mbps" \
      "$last_ping_ms" \
      "$last_jitter_ms" \
      "$last_result_ts" \
      "$last_server_name" \
      "$next_run_epoch" \
      true
    ;;

  start)
    last_status="$(read_json_string "last_status")"
    [[ -n "$last_status" ]] || last_status="running"

    last_download_mbps="$(normalize_float "$(read_json_number "last_download_mbps")" "0")"
    last_upload_mbps="$(normalize_float "$(read_json_number "last_upload_mbps")" "0")"
    last_ping_ms="$(normalize_float "$(read_json_number "last_ping_ms")" "0")"
    last_jitter_ms="$(normalize_float "$(read_json_number "last_jitter_ms")" "0")"
    last_result_ts="$(read_json_string "last_result_ts")"
    last_server_name="$(read_json_string "last_server_name")"

    awaiting_first_speedtest_raw="$(read_json_string "awaiting_first_speedtest")"
    if [[ "$awaiting_first_speedtest_raw" == "false" ]]; then
      awaiting_first_speedtest=false
    else
      awaiting_first_speedtest=true
    fi

    write_state \
      true \
      "$last_status" \
      "$last_download_mbps" \
      "$last_upload_mbps" \
      "$last_ping_ms" \
      "$last_jitter_ms" \
      "$last_result_ts" \
      "$last_server_name" \
      0 \
      "$awaiting_first_speedtest"
    ;;

  finish)
    status="${2:-unknown}"
    download_mbps="$(normalize_float "${3:-0}" "0")"
    upload_mbps="$(normalize_float "${4:-0}" "0")"
    ping_ms="$(normalize_float "${5:-0}" "0")"
    jitter_ms="$(normalize_float "${6:-0}" "0")"
    result_ts="${7:-$(log_ts)}"
    server_name="${8:-}"

    next_run_epoch=$(( $(now_epoch) + SPEEDTEST_INTERVAL_MIN * 60 ))

    write_state \
      false \
      "$status" \
      "$download_mbps" \
      "$upload_mbps" \
      "$ping_ms" \
      "$jitter_ms" \
      "$result_ts" \
      "$server_name" \
      "$next_run_epoch" \
      false
    ;;

  *)
    cat >&2 <<'EOF'
Usage:
  update-display-state.sh init
  update-display-state.sh start
  update-display-state.sh finish <status> <download_mbps> <upload_mbps> <ping_ms> <jitter_ms> [result_ts] [server_name]
EOF
    exit 1
    ;;
esac
