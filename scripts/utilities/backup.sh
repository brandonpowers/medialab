#!/usr/bin/env bash
#
# backup.sh - Snapshot the Medialab configuration so a bad update or a wiped
# host can be recovered. Archives service configs (./data), the .env file, and
# the compose/recyclarr config — NOT your media library (that lives under
# MEDIA_ROOT and is far too large to tar).
#
# Usage:
#   ./scripts/utilities/backup.sh [DESTINATION_DIR]
#
#   DESTINATION_DIR   Where to write the archive (default: $REPO_ROOT/backups,
#                     or $MEDIALAB_BACKUP_DIR if set).
#
#   MEDIALAB_BACKUP_KEEP  How many archives to keep in DESTINATION_DIR; older
#                         ones are deleted after a successful backup
#                         (default 4, 0 = keep all).
#
# The archive contains secrets (.env, API keys) and is written with mode 600.
#
# For a consistent snapshot, stop the stack first (update.sh does this). On a
# running stack the archive is still written, but live SQLite databases may be
# captured mid-write.
#
set -euo pipefail

# Resolve the repo root from this script's location so the tool works whether
# Medialab is installed at /opt/medialab or cloned anywhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEST_DIR="${1:-${MEDIALAB_BACKUP_DIR:-$REPO_ROOT/backups}}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$DEST_DIR/medialab-backup-$TIMESTAMP.tar.gz"

echo "[*] Medialab Backup"
echo "==================="
echo ""

cd "$REPO_ROOT"

# Build the list of things to archive (only those that exist).
declare -a ITEMS=()
[[ -f .env ]]                        && ITEMS+=(".env")
[[ -f docker-compose.yml ]]          && ITEMS+=("docker-compose.yml")
[[ -f docker-compose.override.yml ]] && ITEMS+=("docker-compose.override.yml")
[[ -f docker-compose.web.yml ]]      && ITEMS+=("docker-compose.web.yml")
[[ -d config ]]                      && ITEMS+=("config")
[[ -d data ]]                        && ITEMS+=("data")

if [[ ${#ITEMS[@]} -eq 0 ]]; then
    echo "[✗] Nothing to back up (no .env, compose files, config/, or data/ found in $REPO_ROOT)"
    exit 1
fi

mkdir -p "$DEST_DIR"

# Exclude large, regenerable caches/temp/logs so backups stay small.
declare -a EXCLUDES=(
    --exclude='data/jellyfin/cache'
    --exclude='data/tdarr/temp'
    --exclude='data/tdarr/logs'
    --exclude='data/*/config/logs'
    --exclude='*.log'
)

echo "[1/2] Creating archive..."
echo "      Contents: ${ITEMS[*]}"
# Create with restrictive perms from the start (archive holds secrets).
# GNU tar exits 1 when a file changed while it was read (expected on a running
# stack: the archive is complete, just not a point-in-time snapshot) and 2 on a
# real error. Only the latter is a failed backup. Sockets (e.g. qBittorrent's
# IPC socket) can't be archived and are skipped quietly.
tar_rc=0
( umask 077 && tar czf "$ARCHIVE" --warning=no-file-ignored "${EXCLUDES[@]}" "${ITEMS[@]}" ) || tar_rc=$?
if [[ "$tar_rc" -ge 2 ]]; then
    rm -f "$ARCHIVE"
    echo "[✗] tar failed (exit $tar_rc); no backup written."
    exit 1
fi
chmod 600 "$ARCHIVE"
if [[ "$tar_rc" -eq 1 ]]; then
    echo "[!] Some files changed while being archived (services are running)."
    echo "    The archive is complete, but live databases may be inconsistent."
    echo "    For a clean snapshot, stop the stack first: docker compose stop"
fi

# Retention: keep the newest $KEEP archives.
KEEP="${MEDIALAB_BACKUP_KEEP:-4}"
if [[ "$KEEP" =~ ^[0-9]+$ ]] && [[ "$KEEP" -gt 0 ]]; then
    mapfile -t OLD < <(ls -1t "$DEST_DIR"/medialab-backup-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)))
    for f in "${OLD[@]}"; do
        rm -f -- "$f" && echo "      Pruned old backup: $(basename "$f")"
    done
fi

echo ""
echo "[2/2] Done."
SIZE="$(du -h "$ARCHIVE" | cut -f1)"
echo ""
echo "[✓] Backup written: $ARCHIVE ($SIZE)"
echo "    Restore with: ./scripts/utilities/restore.sh \"$ARCHIVE\""
