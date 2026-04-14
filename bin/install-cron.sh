#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../etc/config.sh"

CRON_FILE="/etc/cron.d/speedmon"

cron_every() {
  local minutes="$1"
  if [[ "$minutes" == "60" ]]; then
    printf '0 * * * *'
  else
    printf '*/%s * * * *' "$minutes"
  fi
}

cat > "$CRON_FILE" <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

@reboot root /opt/speedmon/bin/clear-pending-spool-on-boot.sh >> /opt/speedmon/log/cron.log 2>&1
@reboot root /opt/speedmon/bin/collect-ping.sh >> /opt/speedmon/log/ping-loop.log 2>&1
@reboot root sleep 30 && /opt/speedmon/bin/run-speedtest-after-boot.sh >> /opt/speedmon/log/cron.log 2>&1
$(cron_every "$DNS_CHECK_INTERVAL_MIN") root /opt/speedmon/bin/collect-dns.sh >> /opt/speedmon/log/cron.log 2>&1
$(cron_every "$HARDWARE_INTERVAL_MIN") root /opt/speedmon/bin/collect-hardware.sh >> /opt/speedmon/log/cron.log 2>&1
$(cron_every "$SPEEDTEST_INTERVAL_MIN") root /opt/speedmon/bin/run-speedtest.sh >> /opt/speedmon/log/cron.log 2>&1
$(cron_every "$TRACEROUTE_INTERVAL_MIN") root /opt/speedmon/bin/collect-traceroute.sh >> /opt/speedmon/log/cron.log 2>&1
$(cron_every $(( DELIVERY_INTERVAL_SEC / 60 ))) root /opt/speedmon/bin/send-spool.sh >> /opt/speedmon/log/cron.log 2>&1
$(cron_every "$WATCHDOG_INTERVAL_MIN") root /opt/speedmon/bin/watchdog.sh >> /opt/speedmon/log/cron.log 2>&1
CRON

chmod 0644 "$CRON_FILE"
service cron reload 2>/dev/null || systemctl reload cron 2>/dev/null || systemctl restart cron 2>/dev/null || true
printf 'Installed cron file at %s\n' "$CRON_FILE"
