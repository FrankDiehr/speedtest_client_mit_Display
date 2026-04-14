#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

BASE_DIR="/opt/speedmon/spool/pending"
LOG_FILE="/opt/speedmon/log/cron.log"

log() {
  printf '%s [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG_FILE"
}

main() {
  if [[ ! -d "$BASE_DIR" ]]; then
    log "Pending spool directory not found: $BASE_DIR"
    exit 0
  fi

  find "$BASE_DIR" -type f -name '*.csv' -delete
  log "Cleared pending spool CSV files on boot"
}

main "$@"
