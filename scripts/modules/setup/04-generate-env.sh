#!/bin/bash
#
# 04-generate-env.sh - Generate environment configuration
# Creates or updates .env file with all required variables
#
# Usage:
#   ./04-generate-env.sh [--json] [--config file.json]
#
# Options:
#   --json           Output JSON format
#   --config FILE    Read configuration from JSON file (for UI)
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Parse arguments
CONFIG_FILE=""

for arg in "$@"; do
    case $arg in
        --json) OUTPUT_MODE="json" ;;
        --config=*) CONFIG_FILE="${arg#*=}" ;;
        --config)
            shift
            CONFIG_FILE="$1"
            ;;
    esac
done

# ============================================
# CONFIGURATION HELPERS
# ============================================

# Read value from JSON config file
get_config_value() {
    local key="$1"
    local default="${2:-}"

    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        local value
        value=$(jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null || true)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi

    echo "$default"
}

# ============================================
# MAIN
# ============================================

main() {
    init_progress "Generate Environment" 7
    local project_root
    project_root=$(get_project_root)
    local env_file="$project_root/.env"

    # Check if .env exists
    local is_update=false
    if [[ -f "$env_file" ]]; then
        is_update=true
        report_log "info" "Existing .env found - preserving values"

        # Create backup
        local backup
        backup=$(backup_env "$env_file")
        report_log "success" "Backup created: $backup"

        # Load existing values
        load_env "$env_file"
    fi

    # Step 1: Admin account
    report_progress 1 7 "Configuring admin account..."

    local admin_user admin_pass admin_email
    admin_user=$(get_config_value "admin.username" "")
    admin_pass=$(get_config_value "admin.password" "")
    admin_email=$(get_config_value "admin.email" "")

    if [[ -z "$admin_user" ]]; then
        admin_user=$(get_env_value "ADMIN_USERNAME" "$env_file")
    fi
    if [[ -z "$admin_pass" ]]; then
        admin_pass=$(get_env_value "ADMIN_PASSWORD" "$env_file")
    fi
    if [[ -z "$admin_email" ]]; then
        admin_email=$(get_env_value "ADMIN_EMAIL" "$env_file")
    fi

    # Interactive prompts if not set (only when stdin is a terminal)
    if [[ -z "$admin_user" && "$OUTPUT_MODE" != "json" && -t 0 ]]; then
        read -r -p "Admin username [admin]: " admin_user
        admin_user=${admin_user:-admin}
    fi
    if [[ -z "$admin_pass" && "$OUTPUT_MODE" != "json" && -t 0 ]]; then
        read -r -s -p "Admin password: " admin_pass
        echo ""
    fi
    if [[ -z "$admin_email" && "$OUTPUT_MODE" != "json" && -t 0 ]]; then
        read -r -p "Admin email (optional): " admin_email
    fi

    set_env_value "ADMIN_USERNAME" "${admin_user:-admin}" "true" "$env_file" || true
    set_env_value "ADMIN_PASSWORD" "${admin_pass:-}" "true" "$env_file" || true
    set_env_value "ADMIN_EMAIL" "${admin_email:-}" "true" "$env_file" || true

    report_log "success" "Admin: ${admin_user:-admin}"
    report_progress 1 7 "Admin account configured" "complete"

    # Step 2: System configuration
    report_progress 2 7 "Configuring system settings..."

    # Timezone
    local tz
    tz=$(get_config_value "system.timezone" "")
    if [[ -z "$tz" ]]; then
        tz=$(get_env_value "TZ" "$env_file")
    fi
    if [[ -z "$tz" ]]; then
        tz=$(detect_timezone)
    fi
    set_env_value "TZ" "$tz" "false" "$env_file" || true
    report_log "success" "Timezone: $tz"

    # Server name (for Jellyfin)
    local server_name
    server_name=$(get_config_value "system.server_name" "")
    if [[ -z "$server_name" ]]; then
        server_name=$(get_env_value "SERVER_NAME" "$env_file")
    fi
    if [[ -z "$server_name" ]]; then
        server_name="homelab"
    fi
    set_env_value "SERVER_NAME" "$server_name" "false" "$env_file" || true
    report_log "success" "Server name: $server_name"

    # Language (for subtitles/metadata)
    local language
    language=$(get_config_value "system.language" "")
    if [[ -z "$language" ]]; then
        language=$(get_env_value "LANGUAGE" "$env_file")
    fi
    if [[ -z "$language" ]]; then
        language="en"
    fi
    set_env_value "LANGUAGE" "$language" "false" "$env_file" || true
    report_log "success" "Language: $language"

    # PUID/PGID
    local puid pgid
    puid=$(get_config_value "system.puid" "")
    pgid=$(get_config_value "system.pgid" "")

    if [[ -z "$puid" ]]; then
        puid=$(get_env_value "PUID" "$env_file")
    fi
    if [[ -z "$puid" ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            puid=$(id -u "$SUDO_USER")
            pgid=$(id -g "$SUDO_USER")
        else
            puid=$(id -u)
            pgid=$(id -g)
        fi
    fi
    [[ -z "$pgid" ]] && pgid=$(get_env_value "PGID" "$env_file")
    [[ -z "$pgid" ]] && pgid=$puid

    set_env_value "PUID" "$puid" "false" "$env_file" || true
    set_env_value "PGID" "$pgid" "false" "$env_file" || true
    report_log "success" "User: $puid:$pgid"

    report_progress 2 7 "System settings configured" "complete"

    # Step 3: Media root
    report_progress 3 7 "Configuring media paths..."

    local media_root
    media_root=$(get_config_value "storage.media_path" "")
    if [[ -z "$media_root" ]]; then
        media_root=$(get_env_value "MEDIA_ROOT" "$env_file")
    fi
    if [[ -z "$media_root" ]]; then
        if [[ "$OUTPUT_MODE" != "json" && -t 0 ]]; then
            read -r -p "Media root path [/mnt/media]: " media_root
        fi
        media_root=${media_root:-/mnt/media}
    fi
    set_env_value "MEDIA_ROOT" "$media_root" "false" "$env_file" || true
    report_log "success" "Media root: $media_root"

    report_progress 3 7 "Media paths configured" "complete"

    # Step 4: Security keys
    report_progress 4 7 "Generating security keys..."

    # Homarr encryption key
    local homarr_key
    homarr_key=$(get_env_value "HOMARR_ENCRYPTION_KEY" "$env_file")
    if [[ -z "$homarr_key" ]]; then
        homarr_key=$(openssl rand -hex 32)
        set_env_value "HOMARR_ENCRYPTION_KEY" "$homarr_key" "false" "$env_file" || true
        report_log "success" "Generated HOMARR_ENCRYPTION_KEY"

        # Save to passwords file
        cat > "$project_root/.passwords.txt" << EOF
HOMELAB PASSWORDS - $(date)
KEEP THIS FILE SECURE!

Homarr Encryption Key: ${homarr_key}

These passwords have been added to .env
Consider storing them in a password manager and deleting this file.
EOF
        chmod 600 "$project_root/.passwords.txt"
        report_log "warning" "Passwords saved to .passwords.txt"
    fi

    report_progress 4 7 "Security keys ready" "complete"

    # Step 5: API keys
    report_progress 5 7 "Configuring API keys..."

    # TMDB API key
    local tmdb_key
    tmdb_key=$(get_config_value "api_keys.tmdb" "")
    if [[ -z "$tmdb_key" ]]; then
        tmdb_key=$(get_env_value "TMDB_API_KEY" "$env_file")
    fi
    if [[ -z "$tmdb_key" && "$OUTPUT_MODE" != "json" && -t 0 ]]; then
        echo ""
        report_log "info" "TMDB API Key is used by Jellyseerr for media discovery"
        echo "  Get one free at: https://www.themoviedb.org/settings/api"
        echo ""
        read -r -p "TMDB API Key (optional): " tmdb_key
    fi
    set_env_value "TMDB_API_KEY" "${tmdb_key:-}" "false" "$env_file" || true

    # Placeholders for *arr API keys (will be auto-populated by configure-services)
    set_env_value "SONARR_API_KEY" "your_sonarr_api_key_here" "false" "$env_file" || true
    set_env_value "RADARR_API_KEY" "your_radarr_api_key_here" "false" "$env_file" || true
    set_env_value "SABNZBD_API_KEY" "" "false" "$env_file" || true

    # Usenet provider settings (optional)
    local usenet_enabled usenet_host usenet_port usenet_user usenet_pass usenet_connections usenet_ssl
    usenet_enabled=$(get_config_value "usenet.enabled" "false")
    if [[ "$usenet_enabled" == "true" ]]; then
        usenet_host=$(get_config_value "usenet.host" "news.newshosting.com")
        usenet_port=$(get_config_value "usenet.port" "563")
        usenet_user=$(get_config_value "usenet.username" "")
        usenet_pass=$(get_config_value "usenet.password" "")
        usenet_connections=$(get_config_value "usenet.connections" "30")
        usenet_ssl=$(get_config_value "usenet.ssl" "true")

        set_env_value "USENET_HOST" "$usenet_host" "true" "$env_file" || true
        set_env_value "USENET_PORT" "$usenet_port" "true" "$env_file" || true
        set_env_value "USENET_USER" "$usenet_user" "true" "$env_file" || true
        set_env_value "USENET_PASS" "$usenet_pass" "true" "$env_file" || true
        set_env_value "USENET_CONNECTIONS" "$usenet_connections" "true" "$env_file" || true
        set_env_value "USENET_SSL" "$usenet_ssl" "true" "$env_file" || true
        report_log "success" "Usenet provider configured: $usenet_host"
    fi

    # NZB indexer settings (optional)
    local nzb_enabled nzb_type nzb_api_key nzb_url
    nzb_enabled=$(get_config_value "nzb_indexer.enabled" "false")
    if [[ "$nzb_enabled" == "true" ]]; then
        nzb_type=$(get_config_value "nzb_indexer.type" "nzbgeek")
        nzb_api_key=$(get_config_value "nzb_indexer.api_key" "")

        # Set URL based on indexer type
        case "$nzb_type" in
            nzbgeek) nzb_url="https://api.nzbgeek.info" ;;
            drunkenslug) nzb_url="https://api.drunkenslug.com" ;;
            nzbfinder) nzb_url="https://nzbfinder.ws" ;;
            custom) nzb_url=$(get_config_value "nzb_indexer.url" "") ;;
        esac

        set_env_value "NZB_INDEXER_TYPE" "$nzb_type" "true" "$env_file" || true
        set_env_value "NZB_INDEXER_API_KEY" "$nzb_api_key" "true" "$env_file" || true
        set_env_value "NZB_INDEXER_URL" "$nzb_url" "true" "$env_file" || true
        report_log "success" "NZB indexer configured: $nzb_type"
    fi

    report_progress 5 7 "API keys configured" "complete"

    # Step 6: Cloudflare Tunnel
    report_progress 6 7 "Configuring remote access..."

    local cf_token domain
    cf_token=$(get_config_value "cloud.tunnel_token" "")
    domain=$(get_config_value "cloud.domain" "")

    if [[ -z "$cf_token" ]]; then
        cf_token=$(get_env_value "CLOUDFLARE_TUNNEL_TOKEN" "$env_file")
    fi
    if [[ -z "$domain" ]]; then
        domain=$(get_env_value "DOMAIN" "$env_file")
    fi

    if [[ -z "$cf_token" || "$cf_token" == "your_tunnel_token_here" ]]; then
        if [[ "$OUTPUT_MODE" != "json" && -t 0 ]]; then
            # Only prompt if running interactively (stdin is a terminal)
            echo ""
            read -r -p "Set up Cloudflare Tunnel for public access? (y/N): " use_cf

            if [[ "$use_cf" =~ ^[Yy]$ ]]; then
                read -r -p "Domain name: " domain
                echo ""
                report_log "info" "To get your Cloudflare Tunnel token:"
                echo "  1. Go to: https://one.dash.cloudflare.com/"
                echo "  2. Navigate to: Zero Trust > Networks > Tunnels"
                echo "  3. Create a tunnel and copy the token"
                echo ""
                read -r -p "Cloudflare Tunnel Token: " cf_token

                set_env_value "DOMAIN" "${domain:-}" "true" "$env_file" || true
                set_env_value "CLOUDFLARE_TUNNEL_TOKEN" "${cf_token:-}" "true" "$env_file" || true
            else
                report_log "info" "Skipping Cloudflare - local access only"
                set_env_value "DOMAIN" "" "false" "$env_file" || true
                set_env_value "CLOUDFLARE_TUNNEL_TOKEN" "" "false" "$env_file" || true
            fi
        else
            # Non-interactive mode - skip Cloudflare setup
            report_log "info" "Skipping Cloudflare - not configured"
            set_env_value "DOMAIN" "" "false" "$env_file" || true
            set_env_value "CLOUDFLARE_TUNNEL_TOKEN" "" "false" "$env_file" || true
        fi
    else
        set_env_value "DOMAIN" "$domain" "false" "$env_file" || true
        set_env_value "CLOUDFLARE_TUNNEL_TOKEN" "$cf_token" "false" "$env_file" || true
    fi

    report_progress 6 7 "Remote access configured" "complete"

    # Step 7: Finalize
    report_progress 7 7 "Finalizing configuration..."
    report_progress 7 7 "Configuration complete" "complete"

    # Summary
    finish_progress "complete" "Environment configuration complete"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        env_to_json "$env_file"
    else
        echo ""
        echo "Configuration summary:"
        echo "  Timezone:     $tz"
        echo "  User/Group:   $puid:$pgid"
        echo "  Media root:   $media_root"
        [[ -n "${domain:-}" ]] && echo "  Domain:       $domain"
    fi

    return 0
}

main "$@"
