#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

TARGET_DIR="/opt/speedmon"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root: sudo $0"
    exit 1
  fi
}

create_directories() {
  mkdir -p \
    "$TARGET_DIR" \
    "$TARGET_DIR/bin" \
    "$TARGET_DIR/etc" \
    "$TARGET_DIR/lib" \
    "$TARGET_DIR/log" \
    "$TARGET_DIR/run" \
    "$TARGET_DIR/tmp" \
    "$TARGET_DIR/spool" \
    "$TARGET_DIR/spool/pending" \
    "$TARGET_DIR/spool/pending/ping" \
    "$TARGET_DIR/spool/pending/dns" \
    "$TARGET_DIR/spool/pending/speedtest" \
    "$TARGET_DIR/spool/pending/hardware" \
    "$TARGET_DIR/spool/pending/traceroute" \
    "$TARGET_DIR/spool/pending/delivery" \
    "$TARGET_DIR/spool/sent" \
    "$TARGET_DIR/spool/sent/ping" \
    "$TARGET_DIR/spool/sent/dns" \
    "$TARGET_DIR/spool/sent/speedtest" \
    "$TARGET_DIR/spool/sent/hardware" \
    "$TARGET_DIR/spool/sent/traceroute" \
    "$TARGET_DIR/spool/sent/delivery" \
    "$TARGET_DIR/spool/failed" \
    "$TARGET_DIR/spool/failed/ping" \
    "$TARGET_DIR/spool/failed/dns" \
    "$TARGET_DIR/spool/failed/speedtest" \
    "$TARGET_DIR/spool/failed/hardware" \
    "$TARGET_DIR/spool/failed/traceroute" \
    "$TARGET_DIR/spool/failed/delivery" \
    /etc/speedmon
}

set_permissions() {
  chown -R root:root "$TARGET_DIR"
  chown root:root /etc/speedmon

  chmod 755 "$TARGET_DIR"
  chmod 755 "$TARGET_DIR/bin" "$TARGET_DIR/etc" "$TARGET_DIR/lib" "$TARGET_DIR/log" "$TARGET_DIR/run" "$TARGET_DIR/tmp"
  chmod 755 "$TARGET_DIR/spool" "$TARGET_DIR/spool/pending" "$TARGET_DIR/spool/sent" "$TARGET_DIR/spool/failed"

  find "$TARGET_DIR/spool" -type d -exec chmod 755 {} +
  find "$TARGET_DIR/bin" -type f -name '*.sh' -exec chmod 755 {} + 2>/dev/null || true
  find "$TARGET_DIR/bin" -type f -name '*.py' -exec chmod 755 {} + 2>/dev/null || true
  find "$TARGET_DIR/lib" -type f -name '*.sh' -exec chmod 755 {} + 2>/dev/null || true
  find "$TARGET_DIR/etc" -type f -name '*.sh' -exec chmod 644 {} + 2>/dev/null || true

  chmod 700 /etc/speedmon
  if [[ -f /etc/speedmon/secret.env ]]; then
    chmod 600 /etc/speedmon/secret.env
    chown root:root /etc/speedmon/secret.env
  fi
}

run_post_installers() {
  local cron_installer="$TARGET_DIR/bin/install-cron.sh"
  local display_installer="$TARGET_DIR/bin/install-display-service.sh"

  if [[ -x "$cron_installer" ]]; then
    echo "Installing cron jobs ..."
    "$cron_installer"
  else
    echo "WARN: $cron_installer not found or not executable"
  fi

  if [[ -x "$display_installer" ]]; then
    echo "Installing display service ..."
    "$display_installer"
  else
    echo "WARN: $display_installer not found or not executable"
  fi
}

print_summary() {
  echo
  echo "Prepared runtime structure under $TARGET_DIR"
  echo
  echo "Verified/created:"
  echo "  $TARGET_DIR/bin"
  echo "  $TARGET_DIR/etc"
  echo "  $TARGET_DIR/lib"
  echo "  $TARGET_DIR/log"
  echo "  $TARGET_DIR/run"
  echo "  $TARGET_DIR/tmp"
  echo "  $TARGET_DIR/spool/pending"
  echo "  $TARGET_DIR/spool/sent"
  echo "  $TARGET_DIR/spool/failed"
  echo "  /etc/speedmon"
  echo
  echo "Post-install steps attempted:"
  echo "  - cron installation"
  echo "  - display service installation"
}

main() {
  require_root
  create_directories
  set_permissions
  run_post_installers
  print_summary
}

main "$@"
