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
            CONFIG_FILE="${1:-}"
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
        # Require a password that meets the strength policy, entered twice.
        local pw_reason admin_pass_confirm
        while true; do
            read -r -s -p "Admin password (min ${PASSWORD_MIN_LENGTH} chars): " admin_pass
            echo ""
            if ! pw_reason=$(check_password_strength "$admin_pass"); then
                print_warning "$pw_reason"
                continue
            fi
            read -r -s -p "Confirm password: " admin_pass_confirm
            echo ""
            if [[ "$admin_pass" != "$admin_pass_confirm" ]]; then
                print_warning "Passwords did not match - please try again."
                continue
            fi
            break
        done
    fi

    # Server-side guard: in non-interactive/JSON mode the password comes from the
    # web wizard (which validates client-side) or a prior .env. Warn loudly if a
    # weak/empty value slips through rather than silently accepting it.
    if [[ -n "${admin_pass:-}" ]]; then
        local pw_reason_ni
        if ! pw_reason_ni=$(check_password_strength "$admin_pass"); then
            report_log "warning" "Weak admin password: $pw_reason_ni"
        fi
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
        server_name="medialab"
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

    # Docker group GID (for Homepage container to access docker.sock)
    local docker_gid
    docker_gid=$(get_env_value "DOCKER_GID" "$env_file")
    if [[ -z "$docker_gid" ]]; then
        docker_gid=$(getent group docker 2>/dev/null | cut -d: -f3 || echo "")
    fi
    if [[ -n "$docker_gid" ]]; then
        set_env_value "DOCKER_GID" "$docker_gid" "false" "$env_file" || true
        report_log "success" "Docker GID: $docker_gid"
    else
        report_log "warning" "Docker group not found - Homepage container status may not work"
    fi

    # Upstream DNS for containers. Pinning the host's own upstream resolver in
    # docker-compose.yml bypasses the in-container systemd-resolved hop that can
    # cause intermittent EAI_AGAIN / 503 lookup failures (e.g. Radarr -> TMDB).
    local docker_dns
    docker_dns=$(get_config_value "system.dns" "")
    [[ -z "$docker_dns" ]] && docker_dns=$(get_env_value "DOCKER_DNS" "$env_file")
    [[ -z "$docker_dns" ]] && docker_dns=$(detect_upstream_dns)
    set_env_value "DOCKER_DNS" "$docker_dns" "false" "$env_file" || true
    if [[ -n "$docker_dns" ]]; then
        report_log "success" "Docker upstream DNS: $docker_dns"
    else
        report_log "info" "Upstream DNS not detected - containers will use public fallback (1.1.1.1)"
    fi

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

    # Note: Homepage dashboard doesn't require encryption keys
    # It uses file-based YAML configuration
    report_log "success" "Security configuration ready"

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

    # Tdarr API key for automated auth (must start with tapi_, 14+ chars, alphanumeric + underscore)
    local tdarr_api_key
    tdarr_api_key=$(get_env_value "TDARR_API_KEY" "$env_file")
    if [[ -z "$tdarr_api_key" || "$tdarr_api_key" == "your_tdarr_api_key_here" ]]; then
        # Generate a seeded API key: tapi_ + 16 random alphanumeric characters
        tdarr_api_key="tapi_$(openssl rand -hex 8)"
    fi
    set_env_value "TDARR_API_KEY" "$tdarr_api_key" "false" "$env_file" || true

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

    # Homepage allowed hosts: build the list of hosts the dashboard is actually
    # reached by, instead of a wildcard. Covers localhost, the LAN IP, the
    # machine hostname (and .local), and the public domain when configured.
    local hp_hosts="localhost:3000,127.0.0.1:3000"
    local lan_ip host_short
    lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -n "$lan_ip" ]] && hp_hosts+=",${lan_ip}:3000"
    host_short=$(hostname 2>/dev/null || true)
    [[ -n "$host_short" ]] && hp_hosts+=",${host_short}:3000,${host_short}.local:3000"
    [[ -n "${domain:-}" ]] && hp_hosts+=",${domain}"
    set_env_value "HOMEPAGE_ALLOWED_HOSTS" "$hp_hosts" "false" "$env_file" || true
    report_log "success" "Homepage allowed hosts: $hp_hosts"

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
