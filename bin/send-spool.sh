#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd "$CMD_CURL" "$CMD_DATE" "$CMD_FLOCK" || die "Missing required commands"

if ! acquire_lock "send-spool"; then
  log "WARN" "send-spool already running, exiting"
  exit 0
fi

METRICS=(
  ping
  dns
  speedtest
  hardware
  traceroute
)

MIN_FILE_AGE_SEC="90"

file_age_sec() {
  local file="$1"
  local now mtime
  now="$(now_epoch)"
  mtime="$(stat -c '%Y' "$file" 2>/dev/null || echo 0)"
  echo $(( now - mtime ))
}

is_current_ping_minute_file() {
  local file="$1"
  local current_file
  current_file="$SPOOL_DIR/pending/ping/$("$CMD_DATE" -u +%Y%m%dT%H%M).csv"
  [[ "$file" == "$current_file" ]]
}

should_skip_file() {
  local metric="$1"
  local file="$2"
  local age

  [[ -f "$file" ]] || return 0

  age="$(file_age_sec "$file")"

  if (( age < MIN_FILE_AGE_SEC )); then
    log "INFO" "Skipping too-fresh file: $file (age=${age}s)"
    return 0
  fi

  if [[ "$metric" == "ping" ]] && is_current_ping_minute_file "$file"; then
    log "INFO" "Skipping active ping minute file: $file"
    return 0
  fi

  return 1
}

cleanup_spool() {
  local metric

  cleanup_old_files "$SPOOL_DIR/pending" $(( PENDING_RETENTION_HOURS * 3600 )) '*.csv'
  cleanup_old_files "$SPOOL_DIR/sent" $(( SENT_RETENTION_HOURS * 3600 )) '*.csv'
  cleanup_old_files "$SPOOL_DIR/failed" $(( FAILED_RETENTION_HOURS * 3600 )) '*.csv'
  cleanup_old_files "$TMP_DIR" $(( TMP_RETENTION_HOURS * 3600 )) '*'

  truncate_log_if_too_large "$LOG_DIR/speedmon.log" "$MAX_LOG_SIZE_MB"
  truncate_log_if_too_large "$LOG_DIR/ping-loop.log" "$MAX_LOG_SIZE_MB"
  truncate_log_if_too_large "$LOG_DIR/cron.log" "$MAX_LOG_SIZE_MB"
  truncate_log_if_too_large "$LOG_DIR/send-spool.log" "$MAX_LOG_SIZE_MB"

  for metric in "${METRICS[@]}"; do
    prune_excess_files_in_dir "$SPOOL_DIR/sent/$metric" "$MAX_SENT_FILES_PER_METRIC" '*.csv'
    prune_excess_files_in_dir "$SPOOL_DIR/failed/$metric" "$MAX_FAILED_FILES_PER_METRIC" '*.csv'
  done
}

send_one_file() {
  local metric="$1"
  local file="$2"
  local filename http_code url
  local curl_args=()

  filename="$(basename "$file")"
  url="${API_BASE_URL}/ingest/${metric}"

  curl_args+=(
    -fsS
    --connect-timeout "$API_CONNECT_TIMEOUT_SEC"
    --max-time "$API_MAX_TIME_SEC"
    -o /dev/null
    -w '%{http_code}'
    -X POST
    -H "Authorization: Bearer $API_TOKEN"
    -H "X-Client-Id: $CLIENT_ID"
    -H "X-Site-Name: $SITE_NAME"
    -H "X-Queue-File: $filename"
    -H "Content-Type: $DELIVERY_RAW_BODY_CONTENT_TYPE"
    --data-binary "@${file}"
    "$url"
  )

  http_code="$("$CMD_CURL" "${curl_args[@]}" 2>>"$LOG_DIR/send-spool.log" || true)"

  case "$http_code" in
    200|201|202|204)
      move_to_sent "$metric" "$file"
      log "INFO" "Delivered ${metric} file successfully: ${filename} (HTTP ${http_code})"
      update_state "last_delivery_epoch" "$(now_epoch)"
      update_state "last_delivery_ok_epoch" "$(now_epoch)"
      update_state "last_delivery_metric" "$metric"
      update_state "last_delivery_file" "$filename"
      return 0
      ;;
    *)
      log "WARN" "Delivery failed for ${metric} file: ${filename} (HTTP ${http_code:-curl_error})"
      return 1
      ;;
  esac
}

collect_metric_files() {
  local metric="$1"
  local dir="$SPOOL_DIR/pending/$metric"

  [[ -d "$dir" ]] || return 0

  find "$dir" -maxdepth 1 -type f -name '*.csv' | sort
}

main() {
  local metric delivered_total=0 attempted_total=0
  local file
  local batch_limit

  batch_limit="${DELIVERY_BATCH_SIZE}"

  cleanup_spool

  for metric in "${METRICS[@]}"; do
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue

      if (( delivered_total >= batch_limit )); then
        log "INFO" "Batch limit reached (${batch_limit}), stopping send run"
        return 0
      fi

      if should_skip_file "$metric" "$file"; then
        continue
      fi

      attempted_total=$(( attempted_total + 1 ))

      if send_one_file "$metric" "$file"; then
        delivered_total=$(( delivered_total + 1 ))
      fi
    done < <(collect_metric_files "$metric")
  done

  log "INFO" "send-spool finished: delivered=${delivered_total}, attempted=${attempted_total}"
}

main "$@"
