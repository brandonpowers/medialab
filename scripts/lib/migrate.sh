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

# _widget_ensure_field <file> <widget-type> <field> <value>
#
# For every Homepage widget block whose `type:` line is exactly <widget-type>,
# add `<field>: <value>` at the widget's indentation if the block lacks that
# field. A block runs from its `type:` line until a blank line or a line
# indented less than `type:`. Prints the file's new content to stdout and
# returns 0 if anything was added, 1 if not.
_widget_ensure_field() {
    awk -v typ="$2" -v field="$3" -v val="$4" '
        function close_block() {
            if (pending && !has) { print ind field ": " val; added = 1 }
            pending = 0
        }
        {
            if (pending) {
                match($0, /^ */)
                if ($0 ~ /^ *$/ || RLENGTH < length(ind)) close_block()
                else if (substr($0, 1, length(ind) + length(field) + 1) == ind field ":") has = 1
            }
            if (!pending && $0 ~ ("^ *type: " typ " *$")) {
                match($0, /^ */); ind = substr($0, 1, RLENGTH); pending = 1; has = 0
            }
            print
        }
        END { close_block(); exit(added ? 0 : 1) }
    ' "$1"
}

# homepage_migrate_services <services.yaml>
#
# Homepage config is generated once at setup, so existing installs need these
# widget fields added for current upstream versions:
#   - Jellyfin 12 removed the /emby routes and api_key auth that Homepage's
#     default (version 1) Jellyfin widget uses; `version: 2` switches it over.
#   - Tdarr 3 runs with auth on, so its widget needs the API key.
# Prints `<widget>.<field>` for each change. Returns 1 if the file is missing.
homepage_migrate_services() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local spec typ field val tmp
    tmp="$(mktemp)"
    for spec in \
        'jellyfin|version|2' \
        'tdarr|key|{{HOMEPAGE_VAR_TDARR_API_KEY}}'; do
        IFS='|' read -r typ field val <<< "$spec"
        if _widget_ensure_field "$file" "$typ" "$field" "$val" > "$tmp"; then
            cat "$tmp" > "$file"   # keep the file's inode, owner and mode
            echo "${typ}.${field}"
        fi
    done
    rm -f "$tmp"
    return 0
}

# recyclarr_migrate_config <recyclarr.yml>
#
# The config is copied from config/recyclarr.yml once at configure time, so
# existing installs keep the old template's problems:
#   - `replace_existing_custom_formats` was removed in Recyclarr v8.
#   - Five TRaSH custom-format IDs pointed at the wrong formats (e.g. the
#     "AMZN" line was actually "HD Bluray Tier 01").
# Only exact template lines (ID plus its comment) are rewritten, so the same ID
# used on purpose elsewhere is left alone. Prints one line per change.
# Returns 1 if the file is missing.
recyclarr_migrate_config() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    if grep -q '^ *replace_existing_custom_formats:' "$file"; then
        sed -i '/^ *replace_existing_custom_formats:/d' "$file"
        echo "removed replace_existing_custom_formats"
    fi

    local entry old new comment
    for entry in \
        'd6819cba26b1a6508138d25fb5e32293|d660701077794679fd59e8bdf4ce3a29|# AMZN (Amazon)' \
        '77a7b25585c18af08f60b1547bb9b4fb|f67c9ca88f463a48346062e8ad07713f|# ATVP (Apple TV+)' \
        'a880d6abc21e7c16884f3ae393f84179|f6cce30f1733d5c8194222a7507909bb|# HULU' \
        '3ac5d84fce98bab1b531393e9c82f467|0ac24a2a68a9700bcb7eeca8e5cd644c|# iT (iTunes)' \
        '0f12c086e289cf966fa5948eac571f44|e9001909a4c88013a359d0b9920d7bea|# Theatrical Cut'; do
        IFS='|' read -r old new comment <<< "$entry"
        # Patterns contain only hex, spaces, '#', letters, '+', '(' and ')',
        # which are literal in sed's basic regex.
        if grep -q -- "- ${old}  ${comment}\$" "$file"; then
            sed -i "s|- ${old}  ${comment}\$|- ${new}  ${comment}|" "$file"
            echo "fixed trash_id for ${comment#\# }"
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
