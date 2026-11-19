#!/bin/bash
#
# migrate.sh - Idempotent fix-ups for on-disk service config that a compose
# change makes necessary on EXISTING installs. Fresh installs get the same
# values from setup/configure; these helpers exist so update.sh (which runs
# unattended from the systemd timer and never runs setup/configure) can bring an
# older install in line before recreating containers.
#
# Self-contained (no other lib deps) so standalone utilities can source it
# directly.
#

# Prevent multiple sourcing
[[ -n "${_MEDIALAB_MIGRATE_LOADED:-}" ]] && return 0
_MEDIALAB_MIGRATE_LOADED=1

# Seerr's image runs as its built-in `node` user and ignores PUID/PGID, so its
# config dir must be owned by this UID/GID whatever PUID the host uses.
SEERR_UID=1000
SEERR_GID=1000

# arm_migrate_media_paths <arm.yaml>
#
# ARM's working dirs used to be a separate ${MEDIA_ROOT}/arm:/home/arm/media
# mount, which made the post-rip move a cross-mount copy. They now live under
# the library mount at /home/arm/movies/arm (same host dir, ${MEDIA_ROOT}/arm).
# Rewrites ARM's upstream default paths to the new layout; values a user has
# customised are left alone. Prints each key it changed, one per line.
# Returns 1 if the file does not exist.
arm_migrate_media_paths() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local entry key old new
    for entry in \
        'RAW_PATH|/home/arm/media/raw/|/home/arm/movies/arm/raw/' \
        'TRANSCODE_PATH|/home/arm/media/transcode/|/home/arm/movies/arm/transcode/' \
        'COMPLETED_PATH|/home/arm/media/completed/|/home/arm/movies/'; do
        IFS='|' read -r key old new <<< "$entry"
        if grep -q "^${key}: \"${old}\"\$" "$file"; then
            sed -i "s|^${key}: \"${old}\"\$|${key}: \"${new}\"|" "$file"
            echo "$key"
        fi
    done
    return 0
}

# ensure_seerr_config_owner <dir>
#
# chown -R the Seerr config dir to SEERR_UID:SEERR_GID if anything in it is
# owned by another user. Only the owning UID decides whether Seerr can write, so
# a different group alone is left as-is (avoids a spurious warning on every
# unprivileged update run). No-op (rc 0) when already correct or the dir is
# missing; returns non-zero if the chown fails (e.g. not running as root).
ensure_seerr_config_owner() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    if [[ -z "$(find "$dir" ! -uid "$SEERR_UID" -print -quit 2>/dev/null)" ]]; then
        return 0
    fi
    chown -R "${SEERR_UID}:${SEERR_GID}" "$dir" 2>/dev/null
}
