#!/usr/bin/env bash
# shellcheck shell=bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

acquire_lock "watchdog" || exit 0

check_ping_loop() {
  local pid_file="$RUN_DIR/ping-loop.pid"
  if [[ "$PING_LOOP_ENABLED" != "1" ]]; then
    return 0
  fi
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  nohup "$BIN_DIR/collect-ping.sh" >> "$LOG_DIR/ping-loop.log" 2>&1 &
  echo $! > "$pid_file"
  log "WARN" "Restarted ping loop with pid $(cat "$pid_file")"
}

any_connectivity() {
  local host
  for host in "${WATCHDOG_REACHABILITY_TARGETS[@]}"; do
    if "$CMD_PING" -n -c 1 -W 2 "$host" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

collector_reachable() {
  local endpoint="${API_BASE_URL%/}/health"
  "$CMD_CURL" -fsS --connect-timeout 5 --max-time 10 "$endpoint" >/dev/null 2>&1
}

bounce_interface() {
  [[ "$INTERFACE_BOUNCE_ENABLED" == "1" ]] || return 0
  log "WARN" "Bouncing interface $NETWORK_INTERFACE"
  if command -v ifdown >/dev/null 2>&1 && command -v ifup >/dev/null 2>&1; then
    ifdown "$NETWORK_INTERFACE" || true
    sleep 5
    ifup "$NETWORK_INTERFACE" || true
  else
    "$CMD_IP" link set "$NETWORK_INTERFACE" down || true
    sleep 5
    "$CMD_IP" link set "$NETWORK_INTERFACE" up || true
  fi
  update_state last_interface_bounce_epoch "$(now_epoch)"
}

maybe_reboot() {
  [[ "$REBOOT_ENABLED" == "1" ]] || return 0
  log "ERROR" "Watchdog requested reboot"
  sync || true
  reboot
}

main() {
  check_ping_loop

  now="$(now_epoch)"
  public_ip="$(get_public_ip 2>/dev/null || true)"
  delivery_ok_epoch="$(read_state last_delivery_ok_epoch || echo 0)"
  public_ip_missing_since="$(read_state public_ip_missing_since_epoch || echo 0)"
  last_interface_bounce_epoch="$(read_state last_interface_bounce_epoch || echo 0)"
  last_reboot_request_epoch="$(read_state last_reboot_request_epoch || echo 0)"

  if [[ -n "$public_ip" ]]; then
    update_state public_ip_missing_since_epoch 0
  else
    if [[ "$public_ip_missing_since" == "0" || -z "$public_ip_missing_since" ]]; then
      update_state public_ip_missing_since_epoch "$now"
      public_ip_missing_since="$now"
    fi
    missing_for=$(( now - public_ip_missing_since ))
    log "WARN" "No public IP detected for ${missing_for}s"

    if (( missing_for >= PUBLIC_IP_MISSING_ACTION_AFTER_SEC )); then
      if (( now - last_interface_bounce_epoch >= PUBLIC_IP_MISSING_ACTION_AFTER_SEC )); then
        bounce_interface
      fi
    fi

    if (( missing_for >= PUBLIC_IP_MISSING_REBOOT_AFTER_SEC )); then
      if (( last_reboot_request_epoch == 0 || now - last_reboot_request_epoch >= PUBLIC_IP_MISSING_REBOOT_REPEAT_SEC )); then
        update_state last_reboot_request_epoch "$now"
        maybe_reboot
      fi
    fi
  fi

  if any_connectivity; then
    update_state connectivity_ok_epoch "$now"
  else
    log "WARN" "No ICMP connectivity to watchdog targets"
  fi

  if [[ "$SERVER_REACHABILITY_CHECK_ENABLED" == "1" ]]; then
    if collector_reachable; then
      update_state collector_reachable_epoch "$now"
    else
      log "WARN" "Collector health endpoint not reachable"
    fi
  fi

  if [[ -n "$delivery_ok_epoch" && "$delivery_ok_epoch" != "0" ]]; then
    stale_for=$(( now - delivery_ok_epoch ))
    if (( stale_for > DELIVERY_STALENESS_ALERT_SEC )); then
      log "WARN" "No successful delivery for ${stale_for}s"
    fi
  fi
}

main "$@"
