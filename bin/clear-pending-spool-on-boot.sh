#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

PENDING_DIR="/opt/speedmon/spool/pending"
RUN_DIR="/opt/speedmon/run"
TMP_DIR="/opt/speedmon/tmp"
LOG_FILE="/opt/speedmon/log/cron.log"

log() {
  printf '%s [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG_FILE"
}

main() {
  if [[ -d "$PENDING_DIR" ]]; then
    find "$PENDING_DIR" -type f -name '*.csv' -delete
    log "Cleared pending spool CSV files on boot"
  fi

  if [[ -d "$RUN_DIR" ]]; then
    find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type f -delete
    log "Cleared run state files on boot"
  fi

  if [[ -d "$TMP_DIR" ]]; then
    find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type f -delete
    log "Cleared temporary files on boot"
  fi
}

main "$@"
