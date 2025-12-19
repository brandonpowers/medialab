#!/usr/bin/env bash
set -euo pipefail

echo "[*] Homelab Cleanup Script"
echo "=========================="
echo ""

# Clean Docker system
echo "[1/6] Cleaning Docker build cache and unused images..."
docker system prune -af --filter "until=72h"

echo ""
echo "[2/6] Cleaning old completed downloads (older than 14 days)..."
if [ -d /mnt/media/downloads/complete ]; then
  find /mnt/media/downloads/complete -type f -mtime +14 -delete 2>/dev/null || true
  echo "  [✓] Cleaned old downloads"
else
  echo "  [!] /mnt/media/downloads/complete not found, skipping"
fi

echo ""
echo "[3/6] Cleaning Tdarr temp files (older than 1 day)..."
if [ -d /tmp/tdarr ]; then
  find /tmp/tdarr -type f -mtime +1 -delete 2>/dev/null || true
  echo "  [✓] Cleaned Tdarr temp files"
else
  echo "  [!] /tmp/tdarr not found, skipping"
fi

echo ""
echo "[4/6] Cleaning ARM empty transcode directories..."
if [ -d /mnt/media/arm/transcode ]; then
  empty_count=$(find /mnt/media/arm/transcode -type d -empty 2>/dev/null | wc -l)
  if [ "$empty_count" -gt 0 ]; then
    find /mnt/media/arm/transcode -type d -empty -delete 2>/dev/null || true
    echo "  [✓] Removed $empty_count empty transcode directories"
  else
    echo "  [✓] No empty transcode directories"
  fi
else
  echo "  [!] /mnt/media/arm/transcode not found, skipping"
fi

echo ""
echo "[5/6] Checking ARM raw directory for stuck files (older than 7 days)..."
if [ -d /mnt/media/arm/raw ]; then
  stuck_files=$(find /mnt/media/arm/raw -type f -mtime +7 2>/dev/null | wc -l)
  if [ "$stuck_files" -gt 0 ]; then
    echo "  [!] Found $stuck_files files older than 7 days in raw directory"
    echo "      These may be stuck rips - review manually:"
    find /mnt/media/arm/raw -type f -mtime +7 -exec ls -lh {} \; 2>/dev/null | head -10
  else
    echo "  [✓] No stuck files in raw directory"
  fi
else
  echo "  [!] /mnt/media/arm/raw not found, skipping"
fi

echo ""
echo "[6/6] Cleaning Docker logs (if any are too large)..."
# Clean logs larger than 50MB
find /var/lib/docker/containers -name "*.log" -size +50M -delete 2>/dev/null || true

echo ""
echo "[✓] Cleanup complete!"
echo ""
echo "Disk usage:"
df -h /opt /mnt/media 2>/dev/null || df -h /
