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

    # Generate Jellyfin API key (access token for Homepage widget)
    local jellyfin_key
    jellyfin_key=$(get_env_value "JELLYFIN_API_KEY" "$project_root/.env")
    if [[ -z "$jellyfin_key" ]]; then
        local admin_user admin_pass
        admin_user=$(get_env_value "ADMIN_USERNAME" "$project_root/.env")
        admin_pass=$(get_env_value "ADMIN_PASSWORD" "$project_root/.env")
        if [[ -n "$admin_user" && -n "$admin_pass" ]]; then
            local auth_response
            auth_response=$(curl -s -X POST "http://localhost:8096/Users/AuthenticateByName" \
                -H "Content-Type: application/json" \
                -H "X-Emby-Authorization: MediaBrowser Client=\"Medialab\", Device=\"Homepage\", DeviceId=\"homepage-widget\", Version=\"1.0\"" \
                -d "{\"Username\": \"${admin_user}\", \"Pw\": \"${admin_pass}\"}" 2>/dev/null || true)
            jellyfin_key=$(echo "$auth_response" | jq -r '.AccessToken // empty' 2>/dev/null || true)
            if [[ -n "$jellyfin_key" ]]; then
                set_env_value "JELLYFIN_API_KEY" "$jellyfin_key" "true" "$project_root/.env"
                export JELLYFIN_API_KEY="$jellyfin_key"
                report_log "info" "Generated Jellyfin API key"
            fi
        fi
    fi

    report_log "success" "API keys synchronized from container configs"

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
