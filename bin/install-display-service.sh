#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SERVICE_FILE="/etc/systemd/system/speedmon-display.service"

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=SpeedMon OLED Display Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/speedmon
ExecStartPre=/bin/bash /opt/speedmon/bin/update-display-state.sh init
ExecStart=/usr/bin/python3 /opt/speedmon/bin/display-daemon.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable --now speedmon-display.service

echo "Installed and started: $SERVICE_FILE"
