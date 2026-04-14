#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd "$CMD_DIG" "$CMD_AWK" || die "Missing required commands"

if ! acquire_lock "collect-dns"; then
  log "WARN" "collect-dns already running, exiting"
  exit 0
fi

csv() {
  local v="${1:-}"
  v="${v//$'\r'/ }"
  v="${v//$'\n'/ }"
  v="${v//\"/\"\"}"
  printf '"%s"' "$v"
}

normalize_float() {
  local value="${1:-}"
  if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s\n' "$value"
  else
    printf '0\n'
  fi
}

header='id,timestamp_utc,client_id,site_name,dns_server,query_name,status,query_time_ms,answer_ips,public_ip'
file="$(queue_file_path dns)"
ts="$(log_ts)"
public_ip="$(get_public_ip 2>/dev/null || true)"

dns_servers=()
dns_hosts=()

if declare -p DNS_SERVERS >/dev/null 2>&1; then
  dns_servers=("${DNS_SERVERS[@]}")
elif [[ -n "${DNS_SERVER:-}" ]]; then
  dns_servers=("$DNS_SERVER")
fi

if declare -p DNS_TEST_HOSTS >/dev/null 2>&1; then
  dns_hosts=("${DNS_TEST_HOSTS[@]}")
elif [[ -n "${DNS_TEST_HOST:-}" ]]; then
  dns_hosts=("$DNS_TEST_HOST")
fi

[[ ${#dns_servers[@]} -gt 0 ]] || die "No DNS servers configured"
[[ ${#dns_hosts[@]} -gt 0 ]] || die "No DNS test hosts configured"

{
  printf '%s\n' "$header"

  for dns_server in "${dns_servers[@]}"; do
    for dns_host in "${dns_hosts[@]}"; do
      output="$("$CMD_DIG" @"$dns_server" "$dns_host" +time=2 +tries=1 +stats 2>&1 || true)"
      rc=0

      if printf '%s\n' "$output" | grep -qiE 'connection timed out|no servers could be reached|communications error|network is unreachable|timed out'; then
        rc=1
      elif printf '%s\n' "$output" | grep -q 'Query time:'; then
        rc=0
      else
        rc=1
      fi

      status="ok"
      query_time="0"
      answer_ips=""

      if [[ $rc -ne 0 ]]; then
        status="error"
      else
        query_time="$(printf '%s\n' "$output" | awk -F': ' '/Query time:/ {print $2}' | awk '{print $1}' | head -n1)"
        answer_ips="$(printf '%s\n' "$output" | awk '/^[^;].*[[:space:]]IN[[:space:]]A[[:space:]]/ {print $NF}' | paste -sd ';' -)"

        if [[ -z "$query_time" ]]; then
          status="no_stats"
          query_time="0"
        else
          query_time="$(normalize_float "$query_time")"
        fi
      fi

      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv "$(make_id)")" \
        "$(csv "$ts")" \
        "$(csv "$CLIENT_ID")" \
        "$(csv "$SITE_NAME")" \
        "$(csv "$dns_server")" \
        "$(csv "$dns_host")" \
        "$(csv "$status")" \
        "$(csv "$query_time")" \
        "$(csv "$answer_ips")" \
        "$(csv "$public_ip")"
    done
  done
} > "$file"

prune_excess_pending_files "dns"
log "INFO" "DNS metrics written: $file"
