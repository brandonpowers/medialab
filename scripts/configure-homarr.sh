#!/bin/bash
#
# configure-homarr.sh - Automated Homarr dashboard configuration
# Adds all homelab services to Homarr via the OpenAPI
#
# Prerequisites:
#   1. Homarr must be running with initial setup complete
#   2. An API key must be created in Homarr (Management > Tools > API > Authentication)
#
# Usage: ./scripts/configure-homarr.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Homarr configuration
HOMARR_HOST="${HOMARR_HOST:-localhost}"
HOMARR_PORT="${HOMARR_PORT:-7575}"
HOMARR_URL="http://${HOMARR_HOST}:${HOMARR_PORT}"

# ============================================
# HELPER FUNCTIONS
# ============================================

print_section() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Check if Homarr is accessible
check_homarr() {
    if curl -sf "${HOMARR_URL}" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Get API key from .env or prompt
get_api_key() {
    local api_key=""

    # Check .env first
    if [ -f "$PROJECT_ROOT/.env" ]; then
        api_key=$(grep "^HOMARR_API_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2 || true)
    fi

    if [ -n "$api_key" ] && [ "$api_key" != "your_homarr_api_key_here" ]; then
        echo "$api_key"
        return 0
    fi

    return 1
}

# Save API key to .env
save_api_key() {
    local api_key="$1"

    if grep -q "^HOMARR_API_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null; then
        sed -i "s|^HOMARR_API_KEY=.*|HOMARR_API_KEY=${api_key}|" "$PROJECT_ROOT/.env"
    else
        echo "" >> "$PROJECT_ROOT/.env"
        echo "# Homarr API Key (for dashboard automation)" >> "$PROJECT_ROOT/.env"
        echo "HOMARR_API_KEY=${api_key}" >> "$PROJECT_ROOT/.env"
    fi
}

# Make API request to Homarr
homarr_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local curl_args=(
        -s
        -X "$method"
        -H "ApiKey: ${HOMARR_API_KEY}"
        -H "Content-Type: application/json"
    )

    if [ -n "$data" ]; then
        curl_args+=(-d "$data")
    fi

    curl "${curl_args[@]}" "${HOMARR_URL}/api${endpoint}" 2>/dev/null
}

# Get all existing apps
get_all_apps() {
    homarr_api GET "/apps" 2>/dev/null || echo "[]"
}

# Check if app already exists by name
app_exists() {
    local name="$1"
    local apps
    apps=$(get_all_apps)

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

    # Check if app already exists
    if app_exists "$name"; then
        print_info "  $name already exists, skipping"
        return 0
    fi

    # Build JSON payload
    # All fields are required per the API schema
    local payload=$(jq -n \
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

    # Make the request and capture both response and HTTP code
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "ApiKey: ${HOMARR_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${HOMARR_URL}/api/apps" 2>/dev/null)

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        print_success "  Added $name"
        return 0
    else
        print_warning "  Failed to add $name (HTTP $http_code)"
        [ -n "$response" ] && echo "    Response: ${response:0:100}"
        return 1
    fi
}

# ============================================
# MAIN SCRIPT
# ============================================

print_section "Homarr Dashboard Configuration"

# Check for jq
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed"
    print_info "Install with: sudo apt install jq"
    exit 1
fi

# Check if Homarr is running
print_info "Checking Homarr availability at ${HOMARR_URL}..."
if ! check_homarr; then
    print_error "Homarr is not accessible at ${HOMARR_URL}"
    print_info "Make sure Homarr is running: docker compose ps homarr"
    print_info "You can set HOMARR_HOST environment variable if needed"
    exit 1
fi
print_success "Homarr is running"

# Check for API key
print_info "Checking for API key..."
if HOMARR_API_KEY=$(get_api_key); then
    print_success "Found existing API key in .env"
else
    echo ""
    print_warning "No Homarr API key found!"
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

    if [ -z "$HOMARR_API_KEY" ]; then
        print_error "No API key provided. Exiting."
        exit 1
    fi
fi

# Test the API key
print_info "Testing API key..."
API_TEST=$(homarr_api GET "/apps" 2>&1)

if echo "$API_TEST" | grep -qi "unauthorized\|forbidden"; then
    print_error "API key is invalid"
    print_info "Make sure you copied the complete API key"
    exit 1
fi

if echo "$API_TEST" | grep -qi "error"; then
    print_warning "API returned an error: ${API_TEST:0:100}"
    echo -n "Continue anyway? (y/N): "
    read -r continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "API key is valid"
    # Save the API key if we prompted for it
    if ! grep -q "^HOMARR_API_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null; then
        save_api_key "$HOMARR_API_KEY"
        print_success "API key saved to .env"
    fi
fi

# Get server IP for URLs
SERVER_IP=$(hostname -I | awk '{print $1}')
print_info "Using server IP: ${SERVER_IP}"

# ============================================
# ADD APPS TO HOMARR
# ============================================

print_section "Adding Apps to Homarr"

# Track success/failure counts
added=0
skipped=0
failed=0

# Icon base URL (using walkxcode dashboard icons)
ICON_BASE="https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png"

# ═══ PUBLIC SERVICES ═══
echo -e "${YELLOW}Adding public services...${NC}"

if create_app "Jellyfin" \
    "http://${SERVER_IP}:8096" \
    "${ICON_BASE}/jellyfin.png" \
    "Media streaming server" \
    "http://${SERVER_IP}:8096/health"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

if create_app "Jellyseerr" \
    "http://${SERVER_IP}:5055" \
    "${ICON_BASE}/jellyseerr.png" \
    "Media request management" \
    "http://${SERVER_IP}:5055"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

# ═══ AUTOMATION (*arr Stack) ═══
echo ""
echo -e "${YELLOW}Adding automation services...${NC}"

if create_app "Sonarr" \
    "http://${SERVER_IP}:8989" \
    "${ICON_BASE}/sonarr.png" \
    "TV show automation" \
    "http://${SERVER_IP}:8989/ping"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

if create_app "Radarr" \
    "http://${SERVER_IP}:7878" \
    "${ICON_BASE}/radarr.png" \
    "Movie automation" \
    "http://${SERVER_IP}:7878/ping"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

if create_app "Lidarr" \
    "http://${SERVER_IP}:8686" \
    "${ICON_BASE}/lidarr.png" \
    "Music automation" \
    "http://${SERVER_IP}:8686/ping"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

if create_app "Prowlarr" \
    "http://${SERVER_IP}:9696" \
    "${ICON_BASE}/prowlarr.png" \
    "Indexer management" \
    "http://${SERVER_IP}:9696/ping"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

if create_app "Bazarr" \
    "http://${SERVER_IP}:6767" \
    "${ICON_BASE}/bazarr.png" \
    "Subtitle automation" \
    "http://${SERVER_IP}:6767"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

# ═══ DOWNLOAD CLIENTS ═══
echo ""
echo -e "${YELLOW}Adding download clients...${NC}"

if create_app "qBittorrent" \
    "http://${SERVER_IP}:8080" \
    "${ICON_BASE}/qbittorrent.png" \
    "Torrent download client" \
    "http://${SERVER_IP}:8080"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

if create_app "SABnzbd" \
    "http://${SERVER_IP}:8085" \
    "${ICON_BASE}/sabnzbd.png" \
    "Usenet download client" \
    "http://${SERVER_IP}:8085"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

# ═══ MEDIA PROCESSING ═══
echo ""
echo -e "${YELLOW}Adding media processing services...${NC}"

if create_app "Tdarr" \
    "http://${SERVER_IP}:8265" \
    "${ICON_BASE}/tdarr.png" \
    "Automated transcoding" \
    "http://${SERVER_IP}:8265"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

if create_app "ARM" \
    "http://${SERVER_IP}:8090" \
    "${ICON_BASE}/arm.png" \
    "Automatic Ripping Machine" \
    "http://${SERVER_IP}:8090"; then
    ((added++)) || true
else
    ((failed++)) || true
fi

# ============================================
# SUMMARY
# ============================================

print_section "Configuration Complete!"

echo "Results:"
print_success "Added: $added apps"
[ $skipped -gt 0 ] && print_info "Skipped: $skipped apps (already exist)"
[ $failed -gt 0 ] && print_warning "Failed: $failed apps"

echo ""
print_info "Next steps:"
echo "  1. Open ${HOMARR_URL}"
echo "  2. Go to Management → Boards → New Board"
echo "  3. Create a board named 'Homelab'"
echo "  4. Click Edit mode (pencil icon)"
echo "  5. Add App widgets and select your apps"
echo "  6. Arrange with drag-and-drop"
echo "  7. Set as home board in your profile"
echo ""
print_info "Tips:"
echo "  • Add sections to group apps (Media, Downloads, etc.)"
echo "  • Enable Docker integration for container status"
echo "  • Add Calendar widget for *arr release schedules"
echo "  • Configure integrations for live data (Sonarr, Radarr, etc.)"
echo ""
print_success "Your apps are ready to use in Homarr!"
