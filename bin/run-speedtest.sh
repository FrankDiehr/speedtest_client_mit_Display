#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

DISPLAY_STATE_SCRIPT="/opt/speedmon/bin/update-display-state.sh"

require_cmd "$CMD_JQ" "$CMD_TIMEOUT" || die "Missing required commands"
[[ -f "$DISPLAY_STATE_SCRIPT" ]] || die "Display state script not found: $DISPLAY_STATE_SCRIPT"
[[ -x "$LIBRESPEED_CLI_BIN" ]] || die "librespeed-cli not found at $LIBRESPEED_CLI_BIN"
[[ -r "$LIBRESPEED_SERVER_JSON" ]] || die "LibreSpeed server JSON not found: $LIBRESPEED_SERVER_JSON"

normalize_float_local() {
  local value="${1:-}"
  if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s\n' "$value"
  else
    printf '0\n'
  fi
}

header='id,timestamp_utc,client_id,site_name,selected_server_id,selected_server_name,selected_server_url,status,download_bps,upload_bps,ping_ms,jitter_ms,public_ip,external_ip_reported,lan_ips,default_iface,raw_json'
file="$(queue_file_path speedtest)"
ts="$(log_ts)"
public_ip="$(get_public_ip 2>/dev/null || true)"
lan_ips="$(get_lan_ips 2>/dev/null || true)"
iface="$(get_default_iface 2>/dev/null || true)"

mapfile -t server_ids < <("$CMD_JQ" -r '.[].id' "$LIBRESPEED_SERVER_JSON")
[[ ${#server_ids[@]} -gt 0 ]] || die "No servers found in $LIBRESPEED_SERVER_JSON"

status="failed"
selected_id=""
selected_name=""
selected_url=""
download_bps="0"
upload_bps="0"
ping_ms="0"
jitter_ms="0"
external_ip_reported=""
raw_json=""
display_state_written="0"

cleanup_display_state() {
  local rc=$?

  if [[ "${display_state_written:-0}" != "1" ]]; then
    bash "$DISPLAY_STATE_SCRIPT" finish \
      "$status" \
      "$download_bps" \
      "$upload_bps" \
      "$ping_ms" \
      "$jitter_ms" \
      "$ts" \
      "$selected_name" >/dev/null 2>&1 || true
  fi

  exit "$rc"
}

trap cleanup_display_state EXIT

if ! acquire_lock "run-speedtest"; then
  log "WARN" "run-speedtest already running, exiting"
  exit 0
fi

bash "$DISPLAY_STATE_SCRIPT" start >/dev/null 2>&1 || true

for sid in "${server_ids[@]}"; do
  selected_id="$sid"
  selected_name="$("$CMD_JQ" -r --argjson sid "$sid" '.[] | select(.id == $sid) | .name' "$LIBRESPEED_SERVER_JSON" | head -n1)"
  selected_url="$("$CMD_JQ" -r --argjson sid "$sid" '.[] | select(.id == $sid) | .server' "$LIBRESPEED_SERVER_JSON" | head -n1)"

  tmp_out="$TMP_DIR/librespeed-${sid}-$$.log"
  set +e
  "$CMD_TIMEOUT" "$LIBRESPEED_TIMEOUT_SEC" \
    "$LIBRESPEED_CLI_BIN" \
    --json \
    --telemetry-level disabled \
    --local-json "$LIBRESPEED_SERVER_JSON" \
    --server "$sid" \
    --no-icmp \
    ${LIBRESPEED_EXTRA_ARGS} >"$tmp_out" 2>&1
  rc=$?
  set -e

  json_line="$(grep -Eo '\{.*\}' "$tmp_out" | tail -n1 || true)"
  if [[ $rc -eq 0 && -n "$json_line" ]]; then
    raw_json="$json_line"
    download_bps="$(printf '%s' "$json_line" | "$CMD_JQ" -r '.download // .dlSpeed // empty')"
    upload_bps="$(printf '%s' "$json_line" | "$CMD_JQ" -r '.upload // .ulSpeed // empty')"
    ping_ms="$(printf '%s' "$json_line" | "$CMD_JQ" -r '.ping // .latency // empty')"
    jitter_ms="$(printf '%s' "$json_line" | "$CMD_JQ" -r '.jitter // empty')"
    external_ip_reported="$(printf '%s' "$json_line" | "$CMD_JQ" -r '.server.ip // .client.publicIp // .ip // empty')"

    download_bps="$(normalize_float_local "$download_bps")"
    upload_bps="$(normalize_float_local "$upload_bps")"
    ping_ms="$(normalize_float_local "$ping_ms")"
    jitter_ms="$(normalize_float_local "$jitter_ms")"

    status="ok"
    rm -f -- "$tmp_out"
    break
  fi

  log "WARN" "Speedtest failed on server id=$sid name=$selected_name rc=$rc"
  raw_json="$(tr -d '\000' < "$tmp_out" | tail -c 2000)"
  rm -f -- "$tmp_out"
  status="failed_server_${sid}"
  download_bps="0"
  upload_bps="0"
  ping_ms="0"
  jitter_ms="0"
done

{
  printf '%s\n' "$header"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(csv_escape "$(make_id)")" \
    "$(csv_escape "$ts")" \
    "$(csv_escape "$CLIENT_ID")" \
    "$(csv_escape "$SITE_NAME")" \
    "$(csv_escape "$selected_id")" \
    "$(csv_escape "$selected_name")" \
    "$(csv_escape "$selected_url")" \
    "$(csv_escape "$status")" \
    "$(csv_escape "$download_bps")" \
    "$(csv_escape "$upload_bps")" \
    "$(csv_escape "$ping_ms")" \
    "$(csv_escape "$jitter_ms")" \
    "$(csv_escape "$public_ip")" \
    "$(csv_escape "$external_ip_reported")" \
    "$(csv_escape "$lan_ips")" \
    "$(csv_escape "$iface")" \
    "$(csv_escape "$raw_json")"
} > "$file"

prune_excess_pending_files "speedtest"
log "INFO" "Speedtest result written: $file"

bash "$DISPLAY_STATE_SCRIPT" finish \
  "$status" \
  "$download_bps" \
  "$upload_bps" \
  "$ping_ms" \
  "$jitter_ms" \
  "$ts" \
  "$selected_name" >/dev/null 2>&1 || true

display_state_written="1"
