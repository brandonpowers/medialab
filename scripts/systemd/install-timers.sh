#!/usr/bin/env bash
#
# Install medialab systemd timers
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Installing Medialab systemd timers..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "[!] This script must be run as root (use sudo)"
   exit 1
fi

# Copy service and timer files
echo "[1/3] Copying systemd unit files..."
cp "$SCRIPT_DIR/medialab-cleanup.service" /etc/systemd/system/
cp "$SCRIPT_DIR/medialab-cleanup.timer" /etc/systemd/system/
echo "  [✓] Copied to /etc/systemd/system/"

# Reload systemd
echo "[2/3] Reloading systemd daemon..."
systemctl daemon-reload
echo "  [✓] Daemon reloaded"

# Enable and start timer
echo "[3/3] Enabling and starting cleanup timer..."
systemctl enable medialab-cleanup.timer
systemctl start medialab-cleanup.timer
echo "  [✓] Timer enabled and started"

echo ""
echo "[✓] Installation complete!"
echo ""
echo "Timer status:"
systemctl status medialab-cleanup.timer --no-pager
echo ""
echo "Next scheduled runs:"
systemctl list-timers medialab-cleanup.timer --no-pager
