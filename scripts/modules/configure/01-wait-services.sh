#!/bin/bash
#
# 01-wait-services.sh - Wait for critical services to be ready
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Wait for Services"
MODULE_STEP=1
MODULE_TOTAL=12

# ============================================
# HELPERS
# ============================================

# Provision a Homepage-named API key in Jellyfin's ApiKeys table by writing the
# SQLite database directly. Jellyfin is briefly stopped (~5s) to avoid lock
# contention. Idempotent: existing "Homepage" rows are replaced.
#
# Returns 0 on success, 1 on any failure. The token is persisted to .env as
# JELLYFIN_API_KEY and exported.
sync_jellyfin_widget_key() {
    local project_root="$1"
    local db_path="$project_root/data/jellyfin/config/data/jellyfin.db"

    if [[ ! -f "$db_path" ]]; then
        report_log "warning" "Jellyfin DB not found at $db_path — skipping widget key provisioning"
        return 1
    fi

    # Skip if existing key already works (idempotency for re-runs)
    local current_key
    current_key=$(get_env_value "JELLYFIN_API_KEY" "$project_root/.env")
    if [[ -n "$current_key" ]]; then
        local http
        http=$(curl -s -o /dev/null -w '%{http_code}' \
            -H "X-Emby-Token: $current_key" \
            "http://localhost:8096/System/Info" || echo "000")
        if [[ "$http" == "200" ]]; then
            return 0
        fi
        report_log "info" "Existing Jellyfin API key rejected (HTTP $http) — regenerating"
    fi

    # Generate, stop, write, restart
    local new_token
    new_token=$(python3 -c 'import secrets; print(secrets.token_hex(16))')

    docker compose stop jellyfin > /dev/null 2>&1
    local py_status=0
    JF_DB="$db_path" JF_TOKEN="$new_token" python3 - <<'PYEOF' || py_status=$?
import os, sqlite3, datetime
db = os.environ["JF_DB"]
token = os.environ["JF_TOKEN"]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f0")
with sqlite3.connect(db) as con:
    con.execute("DELETE FROM ApiKeys WHERE Name = 'Homepage'")
    con.execute(
        "INSERT INTO ApiKeys (DateCreated, DateLastActivity, Name, AccessToken) VALUES (?, ?, ?, ?)",
        (now, "0001-01-01 05:51:00", "Homepage", token),
    )
PYEOF
    docker compose start jellyfin > /dev/null 2>&1

    if [[ $py_status -ne 0 ]]; then
        report_log "warning" "Failed to write Homepage API key to Jellyfin DB"
        return 1
    fi

    # Wait for Jellyfin to come back up, then verify the new key authenticates
    local waited=0
    while (( waited < 30 )); do
        if curl -s -o /dev/null -w '%{http_code}' \
            -H "X-Emby-Token: $new_token" \
            "http://localhost:8096/System/Info" | grep -q '^200$'; then
            set_env_value "JELLYFIN_API_KEY" "$new_token" "true" "$project_root/.env"
            export JELLYFIN_API_KEY="$new_token"
            report_log "info" "Provisioned Jellyfin Homepage API key"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    report_log "warning" "Jellyfin did not accept new Homepage API key within 30s"
    return 1
}

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"

    # Load environment
    if [[ -f ".env" ]]; then
        set -a
        source .env
        set +a
    else
        report_log "error" ".env file not found"
        exit 1
    fi

    # Ensure all required media directories exist
    local media_root="${MEDIA_ROOT:-/mnt/media}"
    local puid="${PUID:-1000}"
    local pgid="${PGID:-1000}"

    local media_dirs=("movies" "tv" "music" "downloads/complete" "downloads/incomplete" "downloads/watch" "transcode" "arm")
    local dirs_created=false

    for dir in "${media_dirs[@]}"; do
        if [[ ! -d "$media_root/$dir" ]]; then
            mkdir -p "$media_root/$dir"
            chown "${puid}:${pgid}" "$media_root/$dir"
            report_log "info" "Created missing directory: $media_root/$dir"
            dirs_created=true
        fi
    done

    # If we created any directories, restart containers so they can see the new mounts
    if [[ "$dirs_created" == "true" ]]; then
        report_log "info" "Restarting containers to apply new directory mappings..."
        docker compose restart sonarr radarr lidarr bazarr tdarr > /dev/null 2>&1 || true
        sleep 5
    fi

    print_section "Waiting for Services to Start"

    # Critical services - must be ready
    wait_for_service "Prowlarr" "http://localhost:9696/ping" 30 2 || exit 1
    wait_for_service "Sonarr" "http://localhost:8989/ping" 30 2 || exit 1
    wait_for_service "Radarr" "http://localhost:7878/ping" 30 2 || exit 1
    wait_for_service "Lidarr" "http://localhost:8686/ping" 30 2 || exit 1
    wait_for_service "qBittorrent" "http://localhost:8080" 30 2 || exit 1

    # Optional services - continue if not ready
    wait_for_service "Bazarr" "http://localhost:6767" 15 2 || print_info "Bazarr will need manual configuration"
    wait_for_service "SABnzbd" "http://localhost:8085" 15 2 || print_info "SABnzbd will need manual configuration"
    wait_for_service "Jellyfin" "http://localhost:8096/health" 15 2 || print_info "Jellyfin will need manual configuration"
    wait_for_service "Jellyseerr" "http://localhost:5055" 15 2 || print_info "Jellyseerr will need manual configuration"

    # Sync all API keys from container configs to .env
    # This ensures .env has the actual keys containers are using
    # before any dependent configure scripts run
    print_section "Syncing API Keys"
    local project_root
    project_root=$(get_project_root)

    # Sync *arr app keys (XML config format)
    for service in sonarr radarr lidarr prowlarr; do
        local config_file="$project_root/data/${service}/config/config.xml"
        if [[ -f "$config_file" ]]; then
            local key
            key=$(grep -oP '<ApiKey>\K[^<]+' "$config_file" 2>/dev/null || true)
            if [[ -n "$key" ]]; then
                local env_var="${service^^}_API_KEY"
                local current_key
                current_key=$(get_env_value "$env_var" "$project_root/.env")
                if [[ "$key" != "$current_key" ]]; then
                    set_env_value "$env_var" "$key" "true" "$project_root/.env"
                    export "${env_var}=${key}"
                    report_log "info" "Synced ${service^} API key"
                fi
            fi
        fi
    done

    # Sync SABnzbd key (INI config format)
    local sab_config="$project_root/data/sabnzbd/config/sabnzbd.ini"
    if [[ -f "$sab_config" ]]; then
        local sab_key
        sab_key=$(grep -oP '^api_key\s*=\s*\K\S+' "$sab_config" 2>/dev/null || true)
        if [[ -n "$sab_key" ]]; then
            local current_key
            current_key=$(get_env_value "SABNZBD_API_KEY" "$project_root/.env")
            if [[ "$sab_key" != "$current_key" ]]; then
                set_env_value "SABNZBD_API_KEY" "$sab_key" "true" "$project_root/.env"
                export SABNZBD_API_KEY="$sab_key"
                report_log "info" "Synced SABnzbd API key"
            fi
        fi
    fi

    # Sync Bazarr key (YAML config format)
    local bazarr_config="$project_root/data/bazarr/config/config/config.yaml"
    if [[ -f "$bazarr_config" ]]; then
        local bazarr_key
        bazarr_key=$(grep -oP '^\s*apikey:\s*\K\S+' "$bazarr_config" 2>/dev/null | head -1 || true)
        if [[ -n "$bazarr_key" ]]; then
            local current_key
            current_key=$(get_env_value "BAZARR_API_KEY" "$project_root/.env")
            if [[ "$bazarr_key" != "$current_key" ]]; then
                set_env_value "BAZARR_API_KEY" "$bazarr_key" "true" "$project_root/.env"
                export BAZARR_API_KEY="$bazarr_key"
                report_log "info" "Synced Bazarr API key"
            fi
        fi
    fi

    # Sync Jellyseerr key (JSON config format)
    local jellyseerr_config="$project_root/data/jellyseerr/config/settings.json"
    if [[ -f "$jellyseerr_config" ]]; then
        local jellyseerr_key
        jellyseerr_key=$(jq -r '.main.apiKey // empty' "$jellyseerr_config" 2>/dev/null || true)
        if [[ -n "$jellyseerr_key" ]]; then
            local current_key
            current_key=$(get_env_value "JELLYSEERR_API_KEY" "$project_root/.env")
            if [[ "$jellyseerr_key" != "$current_key" ]]; then
                set_env_value "JELLYSEERR_API_KEY" "$jellyseerr_key" "true" "$project_root/.env"
                export JELLYSEERR_API_KEY="$jellyseerr_key"
                report_log "info" "Synced Jellyseerr API key"
            fi
        fi
    fi

    # Provision Jellyfin API key for the Homepage widget.
    #
    # We previously authenticated as ADMIN_USERNAME/ADMIN_PASSWORD via /Users/AuthenticateByName
    # to mint an access token. That approach silently failed on any installation where the
    # Jellyfin admin password had drifted from .env (e.g. wizard was completed in a prior run
    # with different creds, or the user changed it via the UI). Because the failure was
    # swallowed by `|| true`, the homepage widget stayed broken with no visible error.
    #
    # We now write directly into Jellyfin's ApiKeys table — the same mechanism the Jellyfin
    # admin UI uses for "Dashboard → API Keys". It works regardless of admin password state
    # and is idempotent (DELETE + INSERT keyed on Name="Homepage").
    sync_jellyfin_widget_key "$project_root" || \
        report_log "warning" "Jellyfin widget API key not provisioned — homepage Jellyfin widget will show 'API Error'"

    report_log "success" "API keys synchronized from container configs"

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
