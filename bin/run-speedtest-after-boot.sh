#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

MAX_WAIT_SEC=180
SLEEP_STEP_SEC=5

have_default_route() {
  ip route | grep -q '^default '
}

have_ipv4_addr() {
  ip -4 addr show scope global | grep -q 'inet '
}

dns_works() {
  getent hosts de5.backend.librespeed.org >/dev/null 2>&1
}

main() {
  waited=0

  while (( waited < MAX_WAIT_SEC )); do
    if have_ipv4_addr && have_default_route && dns_works; then
      exec /opt/speedmon/bin/run-speedtest.sh
    fi

    sleep "$SLEEP_STEP_SEC"
    waited=$(( waited + SLEEP_STEP_SEC ))
  done

  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [WARN] Boot speedtest skipped: network not ready after ${MAX_WAIT_SEC}s" >> /opt/speedmon/log/cron.log
  exit 1
}

main "$@"
