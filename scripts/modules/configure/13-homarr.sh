#!/bin/bash
#
# 13-homarr.sh - Add services to Homarr dashboard
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Homarr"
MODULE_STEP=13
MODULE_TOTAL=13

# ============================================
# HOMARR API HELPERS
# ============================================

# Make API request to Homarr
homarr_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local api_key="${HOMARR_API_KEY:-}"

    local curl_args=(
        -s
        -X "$method"
        -H "ApiKey: ${api_key}"
        -H "Content-Type: application/json"
    )

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    curl "${curl_args[@]}" "${HOMARR_URL}/api${endpoint}" 2>/dev/null
}

# Check if app already exists by name
app_exists() {
    local name="$1"
    local apps
    apps=$(homarr_api GET "/apps" 2>/dev/null || echo "[]")

    if echo "$apps" | grep -qi "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""; then
        return 0
    fi
    return 1
}

# Create an app in Homarr
create_app() {
    local name="$1"
    local url="$2"
    local icon="$3"
    local description="${4:-}"
    local ping_url="${5:-}"

    if app_exists "$name"; then
        print_info "  $name already exists, skipping"
        return 0
    fi

    # Build JSON payload
    local payload
    payload=$(jq -n \
        --arg name "$name" \
        --arg desc "$description" \
        --arg icon "$icon" \
        --arg href "$url" \
        --arg ping "$ping_url" \
        '{
            name: $name,
            description: (if $desc == "" then null else $desc end),
            iconUrl: $icon,
            href: (if $href == "" then null else $href end),
            pingUrl: (if $ping == "" then null else $ping end)
        }')

    local response
    local http_code
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "ApiKey: ${HOMARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${HOMARR_URL}/api/apps" 2>/dev/null)

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]]; then
        report_log "success" "  Added $name"
        return 0
    else
        report_log "warning" "  Failed to add $name (HTTP $http_code)"
        return 1
    fi
}

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Homarr Dashboard Configuration"

    # Check for jq
    if ! command -v jq &> /dev/null; then
        report_log "error" "jq is required but not installed"
        print_info "Install with: sudo apt install jq"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "error"
        exit 1
    fi

    # Homarr configuration
    local homarr_host="${HOMARR_HOST:-localhost}"
    local homarr_port="${HOMARR_PORT:-7575}"
    export HOMARR_URL="http://${homarr_host}:${homarr_port}"

    # Check if Homarr is running
    print_info "Checking Homarr availability at ${HOMARR_URL}..."
    if ! curl -sf "${HOMARR_URL}" > /dev/null 2>&1; then
        report_log "error" "Homarr is not accessible at ${HOMARR_URL}"
        print_info "Make sure Homarr is running: docker compose ps homarr"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "error"
        exit 1
    fi
    report_log "success" "Homarr is running"

    # Check for API key
    print_info "Checking for API key..."
    local project_root
    project_root=$(get_project_root)

    if [[ -f "$project_root/.env" ]]; then
        HOMARR_API_KEY=$(grep "^HOMARR_API_KEY=" "$project_root/.env" 2>/dev/null | cut -d'=' -f2 || true)
    fi

    if [[ -n "$HOMARR_API_KEY" ]] && [[ "$HOMARR_API_KEY" != "your_homarr_api_key_here" ]]; then
        report_log "success" "Found existing API key in .env"
    else
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            report_log "info" "No Homarr API key - skipping auto-configuration"
            report_log "info" "Setup Homarr manually at http://localhost:7575"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            finish_progress "complete" "$MODULE_NAME"
            exit 0
        fi

        echo ""
        report_log "warning" "No Homarr API key found!"
        echo ""
        print_info "To create an API key:"
        echo "  1. Open ${HOMARR_URL} in your browser"
        echo "  2. Complete initial setup if you haven't already"
        echo "  3. Go to: Management → Tools → API → Authentication tab"
        echo "  4. Click 'Create API Token'"
        echo "  5. Copy the generated key"
        echo ""
        echo -n "Paste your Homarr API key: "
        read -r HOMARR_API_KEY

        if [[ -z "$HOMARR_API_KEY" ]]; then
            report_log "error" "No API key provided. Exiting."
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "error"
            exit 1
        fi
    fi

    export HOMARR_API_KEY

    # Test the API key
    print_info "Testing API key..."
    local api_test
    api_test=$(homarr_api GET "/apps" 2>&1)

    if echo "$api_test" | grep -qi "unauthorized\|forbidden"; then
        report_log "error" "API key is invalid"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "error"
        exit 1
    fi

    report_log "success" "API key is valid"

    # Save API key if not already saved
    if ! grep -q "^HOMARR_API_KEY=" "$project_root/.env" 2>/dev/null; then
        echo "" >> "$project_root/.env"
        echo "# Homarr API Key (for dashboard automation)" >> "$project_root/.env"
        echo "HOMARR_API_KEY=${HOMARR_API_KEY}" >> "$project_root/.env"
        report_log "success" "API key saved to .env"
    fi

    # Get server IP for URLs
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    print_info "Using server IP: ${server_ip}"

    # Icon base URL
    local icon_base="https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png"

    # Track counts
    local added=0
    local failed=0

    print_section "Adding Apps to Homarr"

    # Public Services
    echo -e "${YELLOW:-}Adding public services...${NC:-}"
    create_app "Jellyfin" "http://${server_ip}:8096" "${icon_base}/jellyfin.png" "Media streaming server" "http://${server_ip}:8096/health" && ((added++)) || ((failed++))
    create_app "Jellyseerr" "http://${server_ip}:5055" "${icon_base}/jellyseerr.png" "Media request management" "http://${server_ip}:5055" && ((added++)) || ((failed++))

    # Automation (*arr Stack)
    echo ""
    echo -e "${YELLOW:-}Adding automation services...${NC:-}"
    create_app "Sonarr" "http://${server_ip}:8989" "${icon_base}/sonarr.png" "TV show automation" "http://${server_ip}:8989/ping" && ((added++)) || ((failed++))
    create_app "Radarr" "http://${server_ip}:7878" "${icon_base}/radarr.png" "Movie automation" "http://${server_ip}:7878/ping" && ((added++)) || ((failed++))
    create_app "Lidarr" "http://${server_ip}:8686" "${icon_base}/lidarr.png" "Music automation" "http://${server_ip}:8686/ping" && ((added++)) || ((failed++))
    create_app "Prowlarr" "http://${server_ip}:9696" "${icon_base}/prowlarr.png" "Indexer management" "http://${server_ip}:9696/ping" && ((added++)) || ((failed++))
    create_app "Bazarr" "http://${server_ip}:6767" "${icon_base}/bazarr.png" "Subtitle automation" "http://${server_ip}:6767" && ((added++)) || ((failed++))

    # Download Clients
    echo ""
    echo -e "${YELLOW:-}Adding download clients...${NC:-}"
    create_app "qBittorrent" "http://${server_ip}:8080" "${icon_base}/qbittorrent.png" "Torrent download client" "http://${server_ip}:8080" && ((added++)) || ((failed++))
    create_app "SABnzbd" "http://${server_ip}:8085" "${icon_base}/sabnzbd.png" "Usenet download client" "http://${server_ip}:8085" && ((added++)) || ((failed++))

    # Media Processing
    echo ""
    echo -e "${YELLOW:-}Adding media processing services...${NC:-}"
    create_app "Tdarr" "http://${server_ip}:8265" "${icon_base}/tdarr.png" "Automated transcoding" "http://${server_ip}:8265" && ((added++)) || ((failed++))
    create_app "ARM" "http://${server_ip}:8090" "${icon_base}/arm.png" "Automatic Ripping Machine" "http://${server_ip}:8090" && ((added++)) || ((failed++))

    # Monitoring
    echo ""
    echo -e "${YELLOW:-}Adding monitoring services...${NC:-}"
    create_app "Uptime Kuma" "http://${server_ip}:3001" "${icon_base}/uptime-kuma.png" "Service monitoring" "http://${server_ip}:3001" && ((added++)) || ((failed++))

    # Summary
    print_section "Configuration Complete!"

    echo "Results:"
    report_log "success" "Added: $added apps"
    [[ $failed -gt 0 ]] && report_log "warning" "Failed: $failed apps"

    echo ""
    print_info "Next steps:"
    echo "  1. Open ${HOMARR_URL}"
    echo "  2. Go to Management → Boards → New Board"
    echo "  3. Create a board named 'Homelab'"
    echo "  4. Click Edit mode (pencil icon)"
    echo "  5. Add App widgets and select your apps"
    echo "  6. Arrange with drag-and-drop"
    echo "  7. Set as home board in your profile"

    report_log "success" "Your apps are ready to use in Homarr!"

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
