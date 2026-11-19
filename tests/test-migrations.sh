#!/bin/bash
#
# Unit tests for the on-disk config migrations in scripts/lib/migrate.sh.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/migrate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- arm_migrate_media_paths: upstream defaults are rewritten -----------------
cat > "$TMP/arm.yaml" <<'EOF'
# Path to raw MakeMKV directory
RAW_PATH: "/home/arm/media/raw/"
TRANSCODE_PATH: "/home/arm/media/transcode/"
COMPLETED_PATH: "/home/arm/media/completed/"
LOGPATH: "/home/arm/logs/"
EOF

out=$(arm_migrate_media_paths "$TMP/arm.yaml"); rc=$?
assert_rc 0 "$rc" "migrate defaults: rc 0"
assert_eq 'RAW_PATH: "/home/arm/movies/arm/raw/"' "$(grep '^RAW_PATH:' "$TMP/arm.yaml")" "RAW_PATH moved under /home/arm/movies/arm"
assert_eq 'TRANSCODE_PATH: "/home/arm/movies/arm/transcode/"' "$(grep '^TRANSCODE_PATH:' "$TMP/arm.yaml")" "TRANSCODE_PATH moved under /home/arm/movies/arm"
assert_eq 'COMPLETED_PATH: "/home/arm/movies/"' "$(grep '^COMPLETED_PATH:' "$TMP/arm.yaml")" "COMPLETED_PATH points at library root"
assert_eq 'LOGPATH: "/home/arm/logs/"' "$(grep '^LOGPATH:' "$TMP/arm.yaml")" "unrelated keys untouched"
assert_eq "# Path to raw MakeMKV directory" "$(head -1 "$TMP/arm.yaml")" "comments untouched"
assert_eq $'RAW_PATH\nTRANSCODE_PATH\nCOMPLETED_PATH' "$out" "reports each migrated key"

# --- idempotent: a second run changes nothing and reports nothing -------------
before=$(cat "$TMP/arm.yaml")
out=$(arm_migrate_media_paths "$TMP/arm.yaml"); rc=$?
assert_rc 0 "$rc" "re-run: rc 0"
assert_eq "" "$out" "re-run reports nothing"
assert_eq "$before" "$(cat "$TMP/arm.yaml")" "re-run leaves file unchanged"

# --- user-customised paths are left alone ------------------------------------
cat > "$TMP/custom.yaml" <<'EOF'
RAW_PATH: "/home/arm/movies/scratch/raw/"
TRANSCODE_PATH: "/home/arm/media/transcode/"
COMPLETED_PATH: "/home/arm/movies/rips/"
EOF
out=$(arm_migrate_media_paths "$TMP/custom.yaml")
assert_eq 'RAW_PATH: "/home/arm/movies/scratch/raw/"' "$(grep '^RAW_PATH:' "$TMP/custom.yaml")" "custom RAW_PATH preserved"
assert_eq 'COMPLETED_PATH: "/home/arm/movies/rips/"' "$(grep '^COMPLETED_PATH:' "$TMP/custom.yaml")" "custom COMPLETED_PATH preserved"
assert_eq 'TRANSCODE_PATH: "/home/arm/movies/arm/transcode/"' "$(grep '^TRANSCODE_PATH:' "$TMP/custom.yaml")" "default TRANSCODE_PATH still migrated"
assert_eq "TRANSCODE_PATH" "$out" "reports only the key it changed"

# --- missing file is an error, not a silent no-op ----------------------------
arm_migrate_media_paths "$TMP/does-not-exist.yaml" >/dev/null 2>&1; rc=$?
assert_rc 1 "$rc" "missing file: rc 1"

# --- Seerr runs as a fixed UID regardless of PUID ----------------------------
assert_eq "1000" "$SEERR_UID" "SEERR_UID is the image's node user"
assert_eq "1000" "$SEERR_GID" "SEERR_GID is the image's node group"

finish_tests
