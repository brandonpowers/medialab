#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="${SRC_DIR}/homelab.service"
UNIT_DST="/etc/systemd/system/homelab.service"

need_copy=true
if [ -f "$UNIT_DST" ]; then
  if cmp -s "$UNIT_SRC" "$UNIT_DST"; then
    need_copy=false
    echo "[*] homelab.service already up-to-date."
  fi
fi

if $need_copy; then
  cp "$UNIT_SRC" "$UNIT_DST"
  echo "[*] Installed/updated homelab.service."
fi

systemctl daemon-reload
systemctl enable homelab.service
systemctl restart homelab.service
systemctl --no-pager --full status homelab.service || true
echo "[✓] homelab.service enabled and running."
