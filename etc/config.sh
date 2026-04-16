#!/usr/bin/env bash
# shellcheck shell=bash

#############################################
# SpeedMon client configuration
# Everything is intended to be adjustable here.
#############################################

# Identity
CLIENT_ID="${CLIENT_ID:-$(hostname -s 2>/dev/null || echo speedmon-unknown)}"
SITE_NAME="speedlens"

# Paths
BASE_DIR="/opt/speedmon"
BIN_DIR="$BASE_DIR/bin"
ETC_DIR="$BASE_DIR/etc"
LIB_DIR="$BASE_DIR/lib"
SPOOL_DIR="$BASE_DIR/spool"
LOG_DIR="$BASE_DIR/log"
RUN_DIR="$BASE_DIR/run"
TMP_DIR="$BASE_DIR/tmp"

# External secret / local override files
SECRET_ENV_FILE="/etc/speedmon/secret.env"
LOCAL_OVERRIDE_FILE="/etc/speedmon/config.local.sh"

# Network / interface
NETWORK_INTERFACE="eth0"
PING_TARGET_PRIMARY="1.1.1.1"
PING_TARGET_SECONDARY="8.8.8.8"
DNS_TEST_HOSTS=("google.de" "microsoft.com")
DNS_SERVERS=("1.1.1.1" "8.8.8.8" "185.90.156.222" "185.90.157.222")
TRACEROUTE_TARGET="1.1.1.1"
PUBLIC_IP_URLS=(
  "https://api.ipify.org"
  "https://ifconfig.me/ip"
)

# LibreSpeed backend selection (primary -> secondary fallback)
LIBRESPEED_CLI_BIN="/usr/local/bin/librespeed-cli"
LIBRESPEED_TIMEOUT_SEC="120"
LIBRESPEED_SERVER_JSON="$ETC_DIR/librespeed-servers.json"
# optional flags, e.g. --no-upload / --secure
LIBRESPEED_EXTRA_ARGS="--concurrent 4"

# Delivery API
API_BASE_URL="https://37.27.13.254/api/v1"
API_CONNECT_TIMEOUT_SEC="10"
API_MAX_TIME_SEC="45"
DELIVERY_BATCH_SIZE="20"
DELIVERY_INTERVAL_SEC="120"
DELIVERY_RAW_BODY_CONTENT_TYPE="text/csv"

# Retention / cleanup
PENDING_RETENTION_HOURS="12"
SENT_RETENTION_HOURS="2"
FAILED_RETENTION_HOURS="12"
TMP_RETENTION_HOURS="6"

# CSV cleanup / queue limits
MAX_PENDING_FILES_PER_METRIC="5000"
MAX_SENT_FILES_PER_METRIC="2000"
MAX_FAILED_FILES_PER_METRIC="2000"

# Log cleanup
MAX_LOG_SIZE_MB="10"

# Endpoints are composed as: ${API_BASE_URL}/ingest/<metric>
# Expected headers:
#   Authorization: Bearer <token>
#   X-Client-Id: <CLIENT_ID>
#   X-Site-Name: <SITE_NAME>
#   X-Queue-File: <filename>

# Scheduling (cron-friendly)
PING_LOOP_ENABLED="1"
PING_LOOP_INTERVAL_SEC="1"
DNS_CHECK_INTERVAL_MIN="5"
SPEEDTEST_INTERVAL_MIN="10"
TRACEROUTE_INTERVAL_MIN="60"
WATCHDOG_INTERVAL_MIN="5"
HARDWARE_INTERVAL_MIN="2"
FIRST_SPEEDTEST_DELAY_SEC="40"

# Self-healing / watchdog
WATCHDOG_ENABLED="1"
PUBLIC_IP_MISSING_ACTION_AFTER_SEC="600"        # 10 min
PUBLIC_IP_MISSING_REBOOT_AFTER_SEC="3600"       # 1 hour
PUBLIC_IP_MISSING_REBOOT_REPEAT_SEC="21600"     # 6 hours
INTERFACE_BOUNCE_ENABLED="1"
REBOOT_ENABLED="1"
SERVER_REACHABILITY_CHECK_ENABLED="1"
DELIVERY_STALENESS_ALERT_SEC="900"              # 15 min without successful delivery

# Reachability checks for watchdog
WATCHDOG_REACHABILITY_TARGETS=(
  "1.1.1.1"
  "8.8.8.8"
)
WATCHDOG_HTTP_TARGETS=(
  "https://api.ipify.org"
)

# Logging
LOG_LEVEL="INFO"
LOG_TO_STDERR="1"

# Command paths (override if needed)
CMD_CURL="$(command -v curl 2>/dev/null || echo /usr/bin/curl)"
CMD_DIG="$(command -v dig 2>/dev/null || echo /usr/bin/dig)"
CMD_PING="$(command -v ping 2>/dev/null || echo /bin/ping)"
CMD_TIMEOUT="$(command -v timeout 2>/dev/null || echo /usr/bin/timeout)"
CMD_IP="$(command -v ip 2>/dev/null || echo /sbin/ip)"
CMD_AWK="$(command -v awk 2>/dev/null || echo /usr/bin/awk)"
CMD_SED="$(command -v sed 2>/dev/null || echo /usr/bin/sed)"
CMD_GREP="$(command -v grep 2>/dev/null || echo /usr/bin/grep)"
CMD_DATE="$(command -v date 2>/dev/null || echo /bin/date)"
CMD_HOSTNAME="$(command -v hostname 2>/dev/null || echo /bin/hostname)"
CMD_TRACEROUTE="$(command -v traceroute 2>/dev/null || command -v tracepath 2>/dev/null || echo /usr/bin/traceroute)"
CMD_FREE="$(command -v free 2>/dev/null || echo /usr/bin/free)"
CMD_DF="$(command -v df 2>/dev/null || echo /bin/df)"
CMD_UPTIME="$(command -v uptime 2>/dev/null || echo /usr/bin/uptime)"
CMD_VMSTAT="$(command -v vmstat 2>/dev/null || echo /usr/bin/vmstat)"
CMD_SS="$(command -v ss 2>/dev/null || echo /usr/bin/ss)"
CMD_JQ="$(command -v jq 2>/dev/null || echo /usr/bin/jq)"
CMD_FLOCK="$(command -v flock 2>/dev/null || echo /usr/bin/flock)"
CMD_SYSTEMCTL="$(command -v systemctl 2>/dev/null || echo /usr/bin/systemctl)"

#############################################
# Load secrets and optional local overrides
#############################################

if [[ -f "${SECRET_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${SECRET_ENV_FILE}"
fi

if [[ -f "${LOCAL_OVERRIDE_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${LOCAL_OVERRIDE_FILE}"
fi

#############################################
# Required values validation
#############################################

: "${API_BASE_URL:?ERROR: API_BASE_URL is not set}"
: "${API_TOKEN:?ERROR: API_TOKEN is not set. Please create /etc/speedmon/secret.env}"
: "${CLIENT_ID:?ERROR: CLIENT_ID is not set}"
