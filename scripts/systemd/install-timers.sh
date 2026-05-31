#!/usr/bin/env bash
#
# Install medialab systemd timers
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve the repo root from this script's location so the installed unit points
# at the real install path, whether that's /opt/medialab or a clone elsewhere.
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "[*] Installing Medialab systemd timers..."
echo "    Install path: $REPO_ROOT"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "[!] This script must be run as root (use sudo)"
   exit 1
fi

# Install services (substituting the real repo path) and timers.
echo "[1/3] Installing systemd unit files..."
sed "s|__MEDIALAB_ROOT__|$REPO_ROOT|g" "$SCRIPT_DIR/medialab-cleanup.service" \
    > /etc/systemd/system/medialab-cleanup.service
cp "$SCRIPT_DIR/medialab-cleanup.timer" /etc/systemd/system/
echo "  [✓] Installed cleanup units (cleanup path: $REPO_ROOT/scripts/utilities/cleanup.sh)"
sed "s|__MEDIALAB_ROOT__|$REPO_ROOT|g" "$SCRIPT_DIR/medialab-update.service" \
    > /etc/systemd/system/medialab-update.service
cp "$SCRIPT_DIR/medialab-update.timer" /etc/systemd/system/
echo "  [✓] Installed update units (update path: $REPO_ROOT/scripts/utilities/update.sh)"

# Reload systemd
echo "[2/3] Reloading systemd daemon..."
systemctl daemon-reload
echo "  [✓] Daemon reloaded"

# Enable and start timers
echo "[3/3] Enabling and starting timers..."
systemctl enable medialab-cleanup.timer
systemctl start medialab-cleanup.timer
systemctl enable medialab-update.timer
systemctl start medialab-update.timer
echo "  [✓] Timers enabled and started"

echo ""
echo "[✓] Installation complete!"
echo ""
echo "Timer status:"
systemctl status medialab-cleanup.timer medialab-update.timer --no-pager
echo ""
echo "Next scheduled runs:"
systemctl list-timers medialab-cleanup.timer medialab-update.timer --no-pager
