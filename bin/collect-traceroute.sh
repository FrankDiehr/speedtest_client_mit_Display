#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd "$CMD_TIMEOUT" || die "Missing required commands"

if ! acquire_lock "collect-traceroute"; then
  log "WARN" "collect-traceroute already running, exiting"
  exit 0
fi

header='id,timestamp_utc,client_id,site_name,target,status,hops_raw,public_ip'

normalize_traceroute_output() {
  local text="${1:-}"

  printf '%s\n' "$text" \
    | tr -d '\r' \
    | awk '
      BEGIN { first = 1 }
      {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        gsub(/[[:space:]]+/, " ", $0)

        if ($0 == "") next

        # Kopfzeile wie "traceroute to ..." oder " 1?: [LOCALHOST] ..."
        # bei tracepath/traceroute nicht komplett verlieren, aber klassische
        # traceroute-Header überspringen.
        if ($0 ~ /^(traceroute to|tracepath to)/) next

        if (first == 0) {
          printf " | "
        }
        printf "%s", $0
        first = 0
      }
      END { printf "\n" }
    '
}

main() {
  local file ts public_ip status output rc hops_raw

  file="$(queue_file_path traceroute)"
  ts="$(log_ts)"
  public_ip="$(get_public_ip 2>/dev/null || true)"
  status="ok"
  output=""
  rc=0

  if command -v traceroute >/dev/null 2>&1; then
    set +e
    output="$("$CMD_TIMEOUT" 60 traceroute -n -w 1 -q 1 "$TRACEROUTE_TARGET" 2>&1)"
    rc=$?
    set -e
  elif command -v tracepath >/dev/null 2>&1; then
    set +e
    output="$("$CMD_TIMEOUT" 60 tracepath -n "$TRACEROUTE_TARGET" 2>&1)"
    rc=$?
    set -e
  else
    output="traceroute command not found"
    status="missing_command"
  fi

  if [[ -z "$output" ]]; then
    status="empty_output"
    hops_raw=""
  else
    hops_raw="$(normalize_traceroute_output "$output")"
    hops_raw="${hops_raw%$'\n'}"

    if [[ -z "$hops_raw" ]]; then
      hops_raw="$output"
    fi
  fi

  if [[ "$status" == "ok" && $rc -ne 0 ]]; then
    status="error"
  fi

  {
    printf '%s\n' "$header"
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$(csv_escape "$(make_id)")" \
      "$(csv_escape "$ts")" \
      "$(csv_escape "$CLIENT_ID")" \
      "$(csv_escape "$SITE_NAME")" \
      "$(csv_escape "$TRACEROUTE_TARGET")" \
      "$(csv_escape "$status")" \
      "$(csv_escape "$hops_raw")" \
      "$(csv_escape "$public_ip")"
  } > "$file"

  prune_excess_pending_files "traceroute"
  log "INFO" "Traceroute metrics written: $file"
}

main "$@"
