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
# The archive contains secrets (.env, API keys) and is written with mode 600.
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

# Exclude large, regenerable caches/temp so backups stay small.
declare -a EXCLUDES=(
    --exclude='data/jellyfin/cache'
    --exclude='data/tdarr/temp'
    --exclude='data/tdarr/logs'
    --exclude='*.log'
)

echo "[1/2] Creating archive..."
echo "      Contents: ${ITEMS[*]}"
# Create with restrictive perms from the start (archive holds secrets).
( umask 077 && tar czf "$ARCHIVE" "${EXCLUDES[@]}" "${ITEMS[@]}" )
chmod 600 "$ARCHIVE"

echo ""
echo "[2/2] Done."
SIZE="$(du -h "$ARCHIVE" | cut -f1)"
echo ""
echo "[✓] Backup written: $ARCHIVE ($SIZE)"
echo "    Restore with: ./scripts/utilities/restore.sh \"$ARCHIVE\""
