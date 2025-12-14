#!/usr/bin/env bash
set -euo pipefail

echo "[*] Homelab Cleanup Script"
echo "=========================="
echo ""

# Clean Docker system
echo "[1/4] Cleaning Docker build cache and unused images..."
docker system prune -af --filter "until=72h"

echo ""
echo "[2/4] Cleaning old completed downloads (older than 14 days)..."
if [ -d /mnt/media/downloads/complete ]; then
  find /mnt/media/downloads/complete -type f -mtime +14 -delete 2>/dev/null || true
  echo "  [✓] Cleaned old downloads"
else
  echo "  [!] /mnt/media/downloads/complete not found, skipping"
fi

echo ""
echo "[3/4] Cleaning Tdarr temp files (older than 1 day)..."
if [ -d /tmp/tdarr ]; then
  find /tmp/tdarr -type f -mtime +1 -delete 2>/dev/null || true
  echo "  [✓] Cleaned Tdarr temp files"
else
  echo "  [!] /tmp/tdarr not found, skipping"
fi

echo ""
echo "[4/4] Cleaning Docker logs (if any are too large)..."
# Clean logs larger than 50MB
find /var/lib/docker/containers -name "*.log" -size +50M -delete 2>/dev/null || true

echo ""
echo "[✓] Cleanup complete!"
echo ""
echo "Disk usage:"
df -h /opt /mnt/media 2>/dev/null || df -h /
