#!/usr/bin/env bash
set -euo pipefail

# Resolve the repo root from this script's location so the tool works whether
# Medialab is installed at /opt/medialab or cloned anywhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Read MEDIA_ROOT from .env so cleanup targets the user's actual media drive
# (not a hardcoded /mnt/media). Falls back to the project default.
MEDIA_ROOT="$(grep -E '^MEDIA_ROOT=' "$REPO_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "\"'" || true)"
MEDIA_ROOT="${MEDIA_ROOT:-/mnt/media}"

# Configuration
ARM_DB="$REPO_ROOT/data/arm/home/db/arm.db"
STUCK_JOB_HOURS=24  # Jobs running longer than this are considered stuck
RAW_SIZE_LIMIT_GB=100  # Raw folders larger than this likely indicate copy protection issues

cd "$REPO_ROOT"

echo "[*] Medialab Cleanup Script"
echo "=========================="
echo "    Media root: $MEDIA_ROOT"
echo ""

# Clean Docker system
echo "[1/10] Cleaning Docker build cache and unused images..."
docker system prune -af --filter "until=72h"

echo ""
echo "[2/10] Cleaning old completed downloads (older than 14 days)..."
if [ -d "$MEDIA_ROOT/downloads/complete" ]; then
  find "$MEDIA_ROOT/downloads/complete" -type f -mtime +14 -delete 2>/dev/null || true
  echo "  [✓] Cleaned old downloads"
else
  echo "  [!] $MEDIA_ROOT/downloads/complete not found, skipping"
fi

echo ""
echo "[3/10] Cleaning Tdarr temp files (older than 1 day)..."
if [ -d /tmp/tdarr ]; then
  find /tmp/tdarr -type f -mtime +1 -delete 2>/dev/null || true
  echo "  [✓] Cleaned Tdarr temp files"
else
  echo "  [!] /tmp/tdarr not found, skipping"
fi

echo ""
echo "[4/10] Cleaning ARM empty transcode directories..."
if [ -d "$MEDIA_ROOT/arm/transcode" ]; then
  empty_count=$(find "$MEDIA_ROOT/arm/transcode" -type d -empty 2>/dev/null | wc -l)
  if [ "$empty_count" -gt 0 ]; then
    find "$MEDIA_ROOT/arm/transcode" -type d -empty -delete 2>/dev/null || true
    echo "  [✓] Removed $empty_count empty transcode directories"
  else
    echo "  [✓] No empty transcode directories"
  fi
else
  echo "  [!] $MEDIA_ROOT/arm/transcode not found, skipping"
fi

echo ""
echo "[5/10] Checking ARM raw directory for stuck files (older than 7 days)..."
if [ -d "$MEDIA_ROOT/arm/raw" ]; then
  stuck_files=$(find "$MEDIA_ROOT/arm/raw" -type f -mtime +7 2>/dev/null | wc -l)
  if [ "$stuck_files" -gt 0 ]; then
    echo "  [!] Found $stuck_files files older than 7 days in raw directory"
    echo "      These may be stuck rips - review manually:"
    find "$MEDIA_ROOT/arm/raw" -type f -mtime +7 -exec ls -lh {} \; 2>/dev/null | head -10
  else
    echo "  [✓] No stuck files in raw directory"
  fi
else
  echo "  [!] $MEDIA_ROOT/arm/raw not found, skipping"
fi

echo ""
echo "[6/10] Checking for oversized ARM raw folders (copy protection)..."
if [ -d "$MEDIA_ROOT/arm/raw" ]; then
  oversized_found=false
  while IFS= read -r dir; do
    if [ -n "$dir" ]; then
      # Get size in GB
      size_bytes=$(du -sb "$dir" 2>/dev/null | cut -f1)
      size_gb=$((size_bytes / 1073741824))
      dirname=$(basename "$dir")

      if [ "$size_gb" -ge "$RAW_SIZE_LIMIT_GB" ]; then
        oversized_found=true
        file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
        echo "  [!] $dirname: ${size_gb}GB with $file_count files - likely copy protection"
        echo "      Run: rm -rf \"$dir\" to clean up"
      fi
    fi
  done < <(find "$MEDIA_ROOT/arm/raw" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

  if ! $oversized_found; then
    echo "  [✓] No oversized raw folders found"
  fi
else
  echo "  [!] $MEDIA_ROOT/arm/raw not found, skipping"
fi

echo ""
echo "[7/10] Cleaning Docker logs (if any are too large)..."
# Clean logs larger than 50MB
find /var/lib/docker/containers -name "*.log" -size +50M -delete 2>/dev/null || true

echo ""
echo "[8/10] Checking ARM database for stuck jobs..."
if [ -f "$ARM_DB" ]; then
  # Find jobs stuck in 'ripping' status for longer than STUCK_JOB_HOURS
  stuck_jobs=$(sqlite3 "$ARM_DB" "
    SELECT job_id, title, devpath, start_time
    FROM job
    WHERE status = 'ripping'
      AND start_time < datetime('now', '-${STUCK_JOB_HOURS} hours')
  " 2>/dev/null || echo "")

  if [ -n "$stuck_jobs" ]; then
    echo "  [!] Found stuck jobs (running >${STUCK_JOB_HOURS}h):"
    echo "$stuck_jobs" | while IFS='|' read -r job_id title devpath start_time; do
      echo "      Job #$job_id: $title ($devpath) started $start_time"
    done

    # Auto-fail stuck jobs and clear drive locks
    echo "  [*] Auto-failing stuck jobs..."
    sqlite3 "$ARM_DB" "
      -- Mark stuck jobs as failed
      UPDATE job SET
        status = 'fail',
        stop_time = datetime('now'),
        ejected = 1,
        pid = 0
      WHERE status = 'ripping'
        AND start_time < datetime('now', '-${STUCK_JOB_HOURS} hours');

      -- Clear drive locks for any drives pointing to failed jobs
      UPDATE system_drives SET job_id_current = NULL
      WHERE job_id_current IN (
        SELECT job_id FROM job
        WHERE status = 'fail'
          AND stop_time > datetime('now', '-1 minute')
      );
    " 2>/dev/null && echo "  [✓] Stuck jobs marked as failed and drive locks cleared" \
                  || echo "  [✗] Failed to update ARM database"
  else
    echo "  [✓] No stuck jobs found"
  fi
else
  echo "  [!] ARM database not found at $ARM_DB, skipping"
fi

echo ""
echo "[9/10] Cleaning ARM empty raw directories (from failed rips)..."
if [ -d "$MEDIA_ROOT/arm/raw" ]; then
  empty_count=$(find "$MEDIA_ROOT/arm/raw" -maxdepth 1 -type d -empty 2>/dev/null | wc -l)
  if [ "$empty_count" -gt 0 ]; then
    find "$MEDIA_ROOT/arm/raw" -maxdepth 1 -type d -empty -delete 2>/dev/null || true
    echo "  [✓] Removed $empty_count empty raw directories"
  else
    echo "  [✓] No empty raw directories"
  fi
else
  echo "  [!] $MEDIA_ROOT/arm/raw not found, skipping"
fi

echo ""
echo "[10/10] Cleaning ARM failed jobs from database..."
if [ -f "$ARM_DB" ]; then
  failed_count=$(sqlite3 "$ARM_DB" "SELECT COUNT(*) FROM job WHERE status = 'fail'" 2>/dev/null || echo "0")
  if [ "$failed_count" -gt 0 ]; then
    sqlite3 "$ARM_DB" "DELETE FROM job WHERE status = 'fail'" 2>/dev/null || true
    echo "  [✓] Removed $failed_count failed jobs from ARM database"
  else
    echo "  [✓] No failed jobs in ARM database"
  fi
else
  echo "  [!] ARM database not found at $ARM_DB, skipping"
fi

echo ""
echo "[✓] Cleanup complete!"
echo ""
echo "Disk usage:"
df -h "$REPO_ROOT" "$MEDIA_ROOT" 2>/dev/null || df -h /
