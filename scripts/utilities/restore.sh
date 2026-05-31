#!/usr/bin/env bash
#
# restore.sh - Restore a Medialab configuration snapshot created by backup.sh.
# Extracts the archived .env, compose files, config/, and data/ back into the
# repo root, overwriting current files.
#
# Usage:
#   ./scripts/utilities/restore.sh ARCHIVE.tar.gz [--force]
#
#   --force   Skip the confirmation prompt (for non-interactive use).
#
# This overwrites your current configuration. Stop the stack first
# (docker compose down) so services aren't running against half-restored state.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ARCHIVE=""
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        *)       ARCHIVE="$arg" ;;
    esac
done

echo "[*] Medialab Restore"
echo "===================="
echo ""

if [[ -z "$ARCHIVE" ]]; then
    echo "[✗] Usage: $0 ARCHIVE.tar.gz [--force]"
    exit 1
fi
if [[ ! -f "$ARCHIVE" ]]; then
    echo "[✗] Archive not found: $ARCHIVE"
    exit 1
fi

# Sanity check: does this look like a Medialab backup?
if ! tar tzf "$ARCHIVE" 2>/dev/null | grep -qE '^(\./)?(\.env|docker-compose\.yml|data/|config/)'; then
    echo "[✗] '$ARCHIVE' does not look like a Medialab backup (no .env / compose / data / config)."
    exit 1
fi

echo "Archive:  $ARCHIVE"
echo "Restore into: $REPO_ROOT"
echo ""
echo "[!] This will OVERWRITE current .env, compose files, config/, and data/."

if ! $FORCE; then
    if [[ -t 0 ]]; then
        read -r -p "Continue? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    else
        echo "[✗] Refusing to restore non-interactively without --force."
        exit 1
    fi
fi

echo ""
echo "[1/1] Extracting..."
tar xzf "$ARCHIVE" -C "$REPO_ROOT"

# .env may have been restored with loose perms depending on the archive; lock it.
[[ -f "$REPO_ROOT/.env" ]] && chmod 600 "$REPO_ROOT/.env"

echo ""
echo "[✓] Restore complete."
echo "    Bring the stack back up with: docker compose up -d"
