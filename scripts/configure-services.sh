#!/bin/bash
#
# configure-services.sh - Automated service configuration
# Links services together via API calls to eliminate manual setup
# Focused on video streaming: Jellyfin, *arr stack, ARM, Tdarr
#
# Usage: ./scripts/configure-services.sh
# Run after: setup-homelab.sh completes and all services are running
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================
# HELPER FUNCTIONS
# ============================================

print_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
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
    echo -e "$1"
}

# Wait for service to be ready
wait_for_service() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-30}"
    local attempt=1

    print_info "Waiting for $name to be ready..."

    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            print_success "$name is ready"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done

    print_warning "$name failed to become ready after $max_attempts attempts"
    return 1
}

# Get API key from service config
get_api_key() {
    local service="$1"
    local api_key=""

    # Handle different config formats
    if [ "$service" = "bazarr" ]; then
        # Bazarr uses YAML config
        local config_file="${PROJECT_ROOT}/data/${service}/config/config/config.yaml"
        if [ -f "$config_file" ]; then
            api_key=$(grep -oP '^\s*apikey:\s*\K\S+' "$config_file" 2>/dev/null | head -1 || true)
        fi
    else
        # *arr apps use XML config
        local config_file="${PROJECT_ROOT}/data/${service}/config/config.xml"
        if [ -f "$config_file" ]; then
            api_key=$(grep -oP '<ApiKey>\K[^<]+' "$config_file" 2>/dev/null || true)
        fi
    fi

    echo "$api_key"
    return 0
}

# Update .env with API key only if not already set or different
update_env_api_key() {
    local key_name="$1"
    local key_value="$2"

    if [ -z "$key_value" ]; then
        return 1
    fi

    # Check if key exists and has a real value (not placeholder)
    local existing_value=""
    if grep -q "^${key_name}=" "$PROJECT_ROOT/.env"; then
        existing_value=$(grep "^${key_name}=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)
    fi

    # Skip if already set to same value
    if [ "$existing_value" = "$key_value" ]; then
        print_info "  $key_name already set"
        return 0
    fi

    # Skip if existing value looks valid and different (don't overwrite user changes)
    if [ -n "$existing_value" ] && [ "$existing_value" != "your_${key_name,,}_here" ] && [[ "$existing_value" =~ ^[a-f0-9]{32}$ ]]; then
        print_info "  $key_name already configured, skipping"
        return 0
    fi

    # Update or add the key
    if grep -q "^${key_name}=" "$PROJECT_ROOT/.env"; then
        sed -i "s/^${key_name}=.*/${key_name}=${key_value}/" "$PROJECT_ROOT/.env"
    else
        echo "${key_name}=${key_value}" >> "$PROJECT_ROOT/.env"
    fi
    print_success "  $key_name updated"
}

# Prompt for optional credential if not in .env
prompt_credential() {
    local var_name="$1"
    local prompt_text="$2"
    local is_secret="${3:-false}"

    # Check if already set in .env
    local existing_value=""
    if grep -q "^${var_name}=" "$PROJECT_ROOT/.env" 2>/dev/null; then
        existing_value=$(grep "^${var_name}=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)
    fi

    # Return existing value if set
    if [ -n "$existing_value" ]; then
        echo "$existing_value"
        return 0
    fi

    # Prompt user
    local value=""
    if [ "$is_secret" = "true" ]; then
        read -s -p "$prompt_text" value
        echo "" >&2  # Newline to stderr so it doesn't get captured
    else
        read -p "$prompt_text" value
    fi

    # Save to .env if provided (quote values with special characters)
    if [ -n "$value" ]; then
        # Use single quotes to safely handle special characters
        echo "${var_name}='${value}'" >> "$PROJECT_ROOT/.env"
    fi

    echo "$value"
}

# ============================================
# LOAD ENVIRONMENT
# ============================================

print_section "Loading Configuration"

if [ ! -f "$PROJECT_ROOT/.env" ]; then
    print_error ".env file not found at $PROJECT_ROOT/.env"
    exit 1
fi

# Load environment variables
set -a
source "$PROJECT_ROOT/.env"
set +a

print_success "Configuration loaded"

# ============================================
# WAIT FOR SERVICES
# ============================================

print_section "Waiting for Services to Start"

cd "$PROJECT_ROOT"

# Critical services - must be ready
wait_for_service "Prowlarr" "http://localhost:9696/ping" || exit 1
wait_for_service "Sonarr" "http://localhost:8989/ping" || exit 1
wait_for_service "Radarr" "http://localhost:7878/ping" || exit 1
wait_for_service "Lidarr" "http://localhost:8686/ping" || exit 1
wait_for_service "qBittorrent" "http://localhost:8080" || exit 1

# Optional services - continue if not ready
wait_for_service "Bazarr" "http://localhost:6767" || print_info "Bazarr will need manual configuration"
wait_for_service "SABnzbd" "http://localhost:8085" || print_info "SABnzbd will need manual configuration"
wait_for_service "Jellyfin" "http://localhost:8096/health" || print_info "Jellyfin will need manual configuration"
wait_for_service "Jellyseerr" "http://localhost:5055" || print_info "Jellyseerr will need manual configuration"

# ============================================
# QBITTORRENT CONFIGURATION
# ============================================

print_section "Configuring qBittorrent"

# Get temporary password from logs
QBIT_TEMP_PASS=$(docker compose logs qbittorrent 2>/dev/null | grep -oP 'temporary password is provided for this session: \K\S+' | tail -1 || true)

# Show default credentials
print_info "Default qBittorrent credentials:"
print_info "  Username: admin"
if [ -n "$QBIT_TEMP_PASS" ]; then
    print_info "  Temporary Password: ${QBIT_TEMP_PASS}"
else
    print_info "  Password: (check logs or use your custom password)"
fi
echo ""

# Prompt for credentials
read -p "qBittorrent username [admin]: " QBIT_USER
QBIT_USER=${QBIT_USER:-admin}

if [ -n "$QBIT_TEMP_PASS" ] && [ "$QBIT_USER" = "admin" ]; then
    read -s -p "qBittorrent password [${QBIT_TEMP_PASS}]: " QBIT_PASS
    echo ""
    QBIT_PASS=${QBIT_PASS:-$QBIT_TEMP_PASS}
else
    read -s -p "qBittorrent password: " QBIT_PASS
    echo ""
fi

if [ -n "$QBIT_PASS" ]; then
    print_info "Logging into qBittorrent..."

    # Login to get session cookie (Referer header required)
    QBIT_COOKIE_FILE=$(mktemp)
    LOGIN_RESPONSE=$(curl -s --max-time 10 -c "$QBIT_COOKIE_FILE" \
        --header 'Referer: http://localhost:8080' \
        --data "username=${QBIT_USER}&password=${QBIT_PASS}" \
        "http://localhost:8080/api/v2/auth/login" 2>/dev/null || echo "FAILED")

    if [ "$LOGIN_RESPONSE" = "Ok." ]; then
        print_success "Logged into qBittorrent"

        # Configure download paths
        print_info "Configuring download paths..."
        curl -s --max-time 10 -b "$QBIT_COOKIE_FILE" \
            --header 'Referer: http://localhost:8080' \
            --data 'json={"save_path":"/downloads/complete","temp_path_enabled":true,"temp_path":"/downloads/incomplete"}' \
            "http://localhost:8080/api/v2/app/setPreferences" \
            > /dev/null 2>&1 && print_success "Download paths configured" || print_warning "Failed to configure download paths"

        # Create category directories for *arr apps
        print_info "Creating download categories..."
        for category in tv movies music; do
            curl -s --max-time 10 -b "$QBIT_COOKIE_FILE" \
                --header 'Referer: http://localhost:8080' \
                --data "category=${category}&savePath=/downloads/complete/${category}" \
                "http://localhost:8080/api/v2/torrents/createCategory" \
                > /dev/null 2>&1
        done
        print_success "Categories created (tv, movies, music)"

        rm -f "$QBIT_COOKIE_FILE"
    else
        rm -f "$QBIT_COOKIE_FILE" 2>/dev/null
        print_warning "Could not login to qBittorrent - check credentials and configure manually"
        print_info "Configure at: http://localhost:8080"
        print_info "Settings → Downloads → Default Save Path: /downloads/complete"
        print_info "Settings → Downloads → Keep incomplete in: /downloads/incomplete"
    fi
else
    print_warning "No password provided - skipping qBittorrent configuration"
fi

# ============================================
# PROWLARR CONFIGURATION
# ============================================

print_section "Configuring Prowlarr"

# Wait for Prowlarr to generate API key
sleep 5
PROWLARR_API_KEY=$(get_api_key "prowlarr")

if [ -z "$PROWLARR_API_KEY" ]; then
    print_error "Failed to get Prowlarr API key"
    print_info "Please configure Prowlarr manually at http://localhost:9696"
else
    print_success "Prowlarr API key: $PROWLARR_API_KEY"

    # Add FlareSolverr to Prowlarr
    print_info "Adding FlareSolverr to Prowlarr..."
    curl -s -X POST "http://localhost:9696/api/v1/indexerproxy" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "FlareSolverr",
            "fields": [
                {"name": "host", "value": "http://flaresolverr:8191"},
                {"name": "requestTimeout", "value": 60}
            ],
            "implementationName": "FlareSolverr",
            "implementation": "FlareSolverr",
            "configContract": "FlareSolverrSettings",
            "tags": []
        }' > /dev/null && print_success "FlareSolverr added to Prowlarr" || print_warning "FlareSolverr may already exist"

    # Configure download clients in Prowlarr
    print_info "Adding download clients to Prowlarr..."

    # Add qBittorrent
    curl -s -X POST "http://localhost:9696/api/v1/downloadclient" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "name": "qBittorrent",
            "fields": [
                {"name": "host", "value": "qbittorrent"},
                {"name": "port", "value": 8080},
                {"name": "urlBase", "value": ""},
                {"name": "username", "value": "admin"},
                {"name": "password", "value": "adminadmin"},
                {"name": "category", "value": "prowlarr"},
                {"name": "recentTvPriority", "value": 0},
                {"name": "olderTvPriority", "value": 0},
                {"name": "recentMoviePriority", "value": 0},
                {"name": "olderMoviePriority", "value": 0}
            ],
            "implementationName": "qBittorrent",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
            "tags": []
        }' > /dev/null && print_success "qBittorrent added to Prowlarr" || print_warning "qBittorrent may already exist"
fi

# ============================================
# SONARR CONFIGURATION
# ============================================

print_section "Configuring Sonarr"

sleep 5
SONARR_API_KEY=$(get_api_key "sonarr")

if [ -z "$SONARR_API_KEY" ]; then
    print_error "Failed to get Sonarr API key"
else
    print_success "Sonarr API key: $SONARR_API_KEY"

    # Update .env with Sonarr API key (only if not already set)
    update_env_api_key "SONARR_API_KEY" "$SONARR_API_KEY"

    # Add root folder
    print_info "Adding root folder to Sonarr..."
    curl -s -X POST "http://localhost:8989/api/v3/rootfolder" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"path": "/media/tv"}' > /dev/null && \
        print_success "Root folder added" || print_warning "Root folder may already exist"

    # Add qBittorrent download client
    print_info "Adding qBittorrent to Sonarr..."
    curl -s -X POST "http://localhost:8989/api/v3/downloadclient" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": true,
            "removeFailedDownloads": true,
            "name": "qBittorrent",
            "fields": [
                {"name": "host", "value": "qbittorrent"},
                {"name": "port", "value": 8080},
                {"name": "urlBase", "value": ""},
                {"name": "username", "value": "admin"},
                {"name": "password", "value": "adminadmin"},
                {"name": "tvCategory", "value": "tv"},
                {"name": "recentTvPriority", "value": 0},
                {"name": "olderTvPriority", "value": 0}
            ],
            "implementationName": "qBittorrent",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
            "tags": []
        }' > /dev/null && print_success "qBittorrent added" || print_warning "qBittorrent may already exist"

    # Add SABnzbd if configured
    if [ -n "${SABNZBD_API_KEY:-}" ]; then
        print_info "Adding SABnzbd to Sonarr..."
        curl -s -X POST "http://localhost:8989/api/v3/downloadclient" \
            -H "X-Api-Key: $SONARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"enable\": true,
                \"protocol\": \"usenet\",
                \"priority\": 1,
                \"removeCompletedDownloads\": true,
                \"removeFailedDownloads\": true,
                \"name\": \"SABnzbd\",
                \"fields\": [
                    {\"name\": \"host\", \"value\": \"sabnzbd\"},
                    {\"name\": \"port\", \"value\": 8080},
                    {\"name\": \"apiKey\", \"value\": \"${SABNZBD_API_KEY}\"},
                    {\"name\": \"tvCategory\", \"value\": \"tv\"}
                ],
                \"implementationName\": \"SABnzbd\",
                \"implementation\": \"Sabnzbd\",
                \"configContract\": \"SabnzbdSettings\",
                \"tags\": []
            }" > /dev/null && print_success "SABnzbd added" || print_warning "SABnzbd may already exist"
    fi
fi

# ============================================
# RADARR CONFIGURATION
# ============================================

print_section "Configuring Radarr"

sleep 5
RADARR_API_KEY=$(get_api_key "radarr")

if [ -z "$RADARR_API_KEY" ]; then
    print_error "Failed to get Radarr API key"
else
    print_success "Radarr API key: $RADARR_API_KEY"

    # Update .env with Radarr API key (only if not already set)
    update_env_api_key "RADARR_API_KEY" "$RADARR_API_KEY"

    # Add root folder
    print_info "Adding root folder to Radarr..."
    curl -s -X POST "http://localhost:7878/api/v3/rootfolder" \
        -H "X-Api-Key: $RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"path": "/media/movies"}' > /dev/null && \
        print_success "Root folder added" || print_warning "Root folder may already exist"

    # Add qBittorrent download client
    print_info "Adding qBittorrent to Radarr..."
    curl -s -X POST "http://localhost:7878/api/v3/downloadclient" \
        -H "X-Api-Key: $RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": true,
            "removeFailedDownloads": true,
            "name": "qBittorrent",
            "fields": [
                {"name": "host", "value": "qbittorrent"},
                {"name": "port", "value": 8080},
                {"name": "urlBase", "value": ""},
                {"name": "username", "value": "admin"},
                {"name": "password", "value": "adminadmin"},
                {"name": "movieCategory", "value": "movies"},
                {"name": "recentMoviePriority", "value": 0},
                {"name": "olderMoviePriority", "value": 0}
            ],
            "implementationName": "qBittorrent",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
            "tags": []
        }' > /dev/null && print_success "qBittorrent added" || print_warning "qBittorrent may already exist"

    # Add SABnzbd if configured
    if [ -n "${SABNZBD_API_KEY:-}" ]; then
        print_info "Adding SABnzbd to Radarr..."
        curl -s -X POST "http://localhost:7878/api/v3/downloadclient" \
            -H "X-Api-Key: $RADARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"enable\": true,
                \"protocol\": \"usenet\",
                \"priority\": 1,
                \"removeCompletedDownloads\": true,
                \"removeFailedDownloads\": true,
                \"name\": \"SABnzbd\",
                \"fields\": [
                    {\"name\": \"host\", \"value\": \"sabnzbd\"},
                    {\"name\": \"port\", \"value\": 8080},
                    {\"name\": \"apiKey\", \"value\": \"${SABNZBD_API_KEY}\"},
                    {\"name\": \"movieCategory\", \"value\": \"movies\"}
                ],
                \"implementationName\": \"SABnzbd\",
                \"implementation\": \"Sabnzbd\",
                \"configContract\": \"SabnzbdSettings\",
                \"tags\": []
            }" > /dev/null && print_success "SABnzbd added" || print_warning "SABnzbd may already exist"
    fi
fi

# ============================================
# LIDARR CONFIGURATION
# ============================================

print_section "Configuring Lidarr"

sleep 5
LIDARR_API_KEY=$(get_api_key "lidarr")

if [ -z "$LIDARR_API_KEY" ]; then
    print_error "Failed to get Lidarr API key"
else
    print_success "Lidarr API key: $LIDARR_API_KEY"

    # Add root folder
    print_info "Adding root folder to Lidarr..."
    curl -s -X POST "http://localhost:8686/api/v1/rootfolder" \
        -H "X-Api-Key: $LIDARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"path": "/media/music", "name": "Music"}' > /dev/null && \
        print_success "Root folder added" || print_warning "Root folder may already exist"

    # Add qBittorrent download client
    print_info "Adding qBittorrent to Lidarr..."
    curl -s -X POST "http://localhost:8686/api/v1/downloadclient" \
        -H "X-Api-Key: $LIDARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": true,
            "removeFailedDownloads": true,
            "name": "qBittorrent",
            "fields": [
                {"name": "host", "value": "qbittorrent"},
                {"name": "port", "value": 8080},
                {"name": "urlBase", "value": ""},
                {"name": "username", "value": "admin"},
                {"name": "password", "value": "adminadmin"},
                {"name": "musicCategory", "value": "music"}
            ],
            "implementationName": "qBittorrent",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
            "tags": []
        }' > /dev/null && print_success "qBittorrent added" || print_warning "qBittorrent may already exist"

    # Add SABnzbd if configured
    if [ -n "${SABNZBD_API_KEY:-}" ]; then
        print_info "Adding SABnzbd to Lidarr..."
        curl -s -X POST "http://localhost:8686/api/v1/downloadclient" \
            -H "X-Api-Key: $LIDARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"enable\": true,
                \"protocol\": \"usenet\",
                \"priority\": 1,
                \"removeCompletedDownloads\": true,
                \"removeFailedDownloads\": true,
                \"name\": \"SABnzbd\",
                \"fields\": [
                    {\"name\": \"host\", \"value\": \"sabnzbd\"},
                    {\"name\": \"port\", \"value\": 8080},
                    {\"name\": \"apiKey\", \"value\": \"${SABNZBD_API_KEY}\"},
                    {\"name\": \"musicCategory\", \"value\": \"music\"}
                ],
                \"implementationName\": \"SABnzbd\",
                \"implementation\": \"Sabnzbd\",
                \"configContract\": \"SabnzbdSettings\",
                \"tags\": []
            }" > /dev/null && print_success "SABnzbd added" || print_warning "SABnzbd may already exist"
    fi
fi

# ============================================
# LINK PROWLARR TO *ARR APPS
# ============================================

if [ -n "$PROWLARR_API_KEY" ]; then
    print_section "Linking Prowlarr to *arr Apps"

    # Add Sonarr to Prowlarr
    if [ -n "$SONARR_API_KEY" ]; then
        print_info "Linking Sonarr to Prowlarr..."
        curl -s -X POST "http://localhost:9696/api/v1/applications" \
            -H "X-Api-Key: $PROWLARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Sonarr\",
                \"syncLevel\": \"addAndRemove\",
                \"fields\": [
                    {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
                    {\"name\": \"baseUrl\", \"value\": \"http://sonarr:8989\"},
                    {\"name\": \"apiKey\", \"value\": \"${SONARR_API_KEY}\"},
                    {\"name\": \"syncCategories\", \"value\": [5000, 5010, 5020, 5030, 5040, 5045, 5050]}
                ],
                \"implementationName\": \"Sonarr\",
                \"implementation\": \"Sonarr\",
                \"configContract\": \"SonarrSettings\",
                \"tags\": []
            }" > /dev/null && print_success "Sonarr linked to Prowlarr" || print_warning "Sonarr may already be linked"
    fi

    # Add Radarr to Prowlarr
    if [ -n "$RADARR_API_KEY" ]; then
        print_info "Linking Radarr to Prowlarr..."
        curl -s -X POST "http://localhost:9696/api/v1/applications" \
            -H "X-Api-Key: $PROWLARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Radarr\",
                \"syncLevel\": \"addAndRemove\",
                \"fields\": [
                    {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
                    {\"name\": \"baseUrl\", \"value\": \"http://radarr:7878\"},
                    {\"name\": \"apiKey\", \"value\": \"${RADARR_API_KEY}\"},
                    {\"name\": \"syncCategories\", \"value\": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080]}
                ],
                \"implementationName\": \"Radarr\",
                \"implementation\": \"Radarr\",
                \"configContract\": \"RadarrSettings\",
                \"tags\": []
            }" > /dev/null && print_success "Radarr linked to Prowlarr" || print_warning "Radarr may already be linked"
    fi

    # Add Lidarr to Prowlarr
    if [ -n "$LIDARR_API_KEY" ]; then
        print_info "Linking Lidarr to Prowlarr..."
        curl -s -X POST "http://localhost:9696/api/v1/applications" \
            -H "X-Api-Key: $PROWLARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Lidarr\",
                \"syncLevel\": \"addAndRemove\",
                \"fields\": [
                    {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
                    {\"name\": \"baseUrl\", \"value\": \"http://lidarr:8686\"},
                    {\"name\": \"apiKey\", \"value\": \"${LIDARR_API_KEY}\"},
                    {\"name\": \"syncCategories\", \"value\": [3000, 3010, 3020, 3030, 3040, 3050, 3060]}
                ],
                \"implementationName\": \"Lidarr\",
                \"implementation\": \"Lidarr\",
                \"configContract\": \"LidarrSettings\",
                \"tags\": []
            }" > /dev/null && print_success "Lidarr linked to Prowlarr" || print_warning "Lidarr may already be linked"
    fi
fi

# ============================================
# BAZARR CONFIGURATION
# ============================================

print_section "Configuring Bazarr"

sleep 5
BAZARR_API_KEY=$(get_api_key "bazarr")

if [ -z "$BAZARR_API_KEY" ]; then
    print_warning "Bazarr API key not found - it may need manual configuration"
    print_info "Visit http://localhost:6767 to complete Bazarr setup"
else
    print_success "Bazarr API key: $BAZARR_API_KEY"

    # Link Sonarr to Bazarr via settings API
    if [ -n "$SONARR_API_KEY" ]; then
        print_info "Linking Sonarr to Bazarr..."
        # Bazarr uses PATCH to /api/system/settings with specific section
        curl -s -X PATCH "http://localhost:6767/api/system/settings/sonarr" \
            -H "X-Api-Key: $BAZARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"ip\": \"sonarr\",
                \"port\": 8989,
                \"base_url\": \"/\",
                \"ssl\": false,
                \"apikey\": \"${SONARR_API_KEY}\",
                \"full_update\": \"Daily\",
                \"only_monitored\": false
            }" > /dev/null 2>&1 && print_success "Sonarr linked" || print_warning "Manual Sonarr configuration may be needed"

        # Enable Sonarr in general settings
        curl -s -X PATCH "http://localhost:6767/api/system/settings/general" \
            -H "X-Api-Key: $BAZARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"use_sonarr": true}' > /dev/null 2>&1 || true
    fi

    # Link Radarr to Bazarr via settings API
    if [ -n "$RADARR_API_KEY" ]; then
        print_info "Linking Radarr to Bazarr..."
        curl -s -X PATCH "http://localhost:6767/api/system/settings/radarr" \
            -H "X-Api-Key: $BAZARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"ip\": \"radarr\",
                \"port\": 7878,
                \"base_url\": \"/\",
                \"ssl\": false,
                \"apikey\": \"${RADARR_API_KEY}\",
                \"full_update\": \"Daily\",
                \"only_monitored\": false
            }" > /dev/null 2>&1 && print_success "Radarr linked" || print_warning "Manual Radarr configuration may be needed"

        # Enable Radarr in general settings
        curl -s -X PATCH "http://localhost:6767/api/system/settings/general" \
            -H "X-Api-Key: $BAZARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"use_radarr": true}' > /dev/null 2>&1 || true
    fi
fi

# ============================================
# USENET CONFIGURATION (Optional)
# ============================================

print_section "Usenet Configuration (Optional)"

# Get SABnzbd API key from config file
get_sabnzbd_api_key() {
    local config_file="${PROJECT_ROOT}/data/sabnzbd/config/sabnzbd.ini"
    if [ -f "$config_file" ]; then
        grep -oP '^api_key\s*=\s*\K\S+' "$config_file" 2>/dev/null || true
    fi
}

# Check if SABnzbd needs initial setup wizard
check_sabnzbd_ready() {
    local api_key
    api_key=$(get_sabnzbd_api_key)
    if [ -n "$api_key" ] && [ "$api_key" != "changeme" ]; then
        return 0
    fi
    return 1
}

# Check if user wants to configure Usenet
CONFIGURE_USENET="n"
if [ -z "$(grep "^NEWSHOSTING_USER=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
    echo -n "Do you want to configure Newshosting (Usenet provider)? (y/N): "
    read -r CONFIGURE_USENET
fi

if [[ "$CONFIGURE_USENET" =~ ^[Yy]$ ]]; then
    print_info "Configuring Newshosting..."

    # Check if SABnzbd wizard needs to be completed
    if ! check_sabnzbd_ready; then
        echo ""
        print_warning "SABnzbd requires initial setup wizard completion."
        print_info ""
        print_info "Please complete the following steps:"
        print_info "  1. Open http://localhost:8085 in your browser"
        print_info "  2. Select your language and click 'Start Wizard'"
        print_info "  3. Skip the server configuration (we'll add it automatically)"
        print_info "  4. Complete the wizard by clicking through to the end"
        print_info ""
        echo -n "Press Enter once you've completed the SABnzbd wizard..."
        read -r

        # Wait a moment for SABnzbd to save config
        sleep 3

        if ! check_sabnzbd_ready; then
            print_error "SABnzbd still not ready. Please complete the wizard and re-run this script."
            print_info "Skipping Newshosting configuration for now."
            CONFIGURE_USENET="n"
        fi
    fi
fi

if [[ "$CONFIGURE_USENET" =~ ^[Yy]$ ]]; then
    NEWSHOSTING_USER=$(prompt_credential "NEWSHOSTING_USER" "Newshosting username: " "false")
    NEWSHOSTING_PASS=$(prompt_credential "NEWSHOSTING_PASS" "Newshosting password: " "true")
    NEWSHOSTING_CONNECTIONS=$(prompt_credential "NEWSHOSTING_CONNECTIONS" "Max connections (default 30): " "false")
    NEWSHOSTING_CONNECTIONS=${NEWSHOSTING_CONNECTIONS:-30}

    if [ -n "$NEWSHOSTING_USER" ] && [ -n "$NEWSHOSTING_PASS" ]; then
        # Get SABnzbd API key from config file
        SABNZBD_API_KEY=$(get_sabnzbd_api_key)

        if [ -n "$SABNZBD_API_KEY" ]; then
            print_info "Adding Newshosting server to SABnzbd..."
            curl -s "http://localhost:8085/sabnzbd/api" \
                -d "mode=set_config" \
                -d "apikey=${SABNZBD_API_KEY}" \
                -d "section=servers" \
                -d "keyword=newshosting" \
                -d "servers[newshosting][host]=news.newshosting.com" \
                -d "servers[newshosting][port]=563" \
                -d "servers[newshosting][ssl]=1" \
                -d "servers[newshosting][username]=${NEWSHOSTING_USER}" \
                -d "servers[newshosting][password]=${NEWSHOSTING_PASS}" \
                -d "servers[newshosting][connections]=${NEWSHOSTING_CONNECTIONS}" \
                -d "servers[newshosting][enable]=1" \
                > /dev/null 2>&1 && print_success "Newshosting added to SABnzbd" || print_warning "Failed to add Newshosting - configure manually"

            # Save SABnzbd API key to .env
            update_env_api_key "SABNZBD_API_KEY" "$SABNZBD_API_KEY"

            # Now add SABnzbd to the *arr apps since we have the API key
            print_info "Adding SABnzbd to Sonarr..."
            if [ -n "$SONARR_API_KEY" ]; then
                curl -s -X POST "http://localhost:8989/api/v3/downloadclient" \
                    -H "X-Api-Key: $SONARR_API_KEY" \
                    -H "Content-Type: application/json" \
                    -d "{
                        \"enable\": true,
                        \"protocol\": \"usenet\",
                        \"priority\": 1,
                        \"removeCompletedDownloads\": true,
                        \"removeFailedDownloads\": true,
                        \"name\": \"SABnzbd\",
                        \"fields\": [
                            {\"name\": \"host\", \"value\": \"sabnzbd\"},
                            {\"name\": \"port\", \"value\": 8080},
                            {\"name\": \"apiKey\", \"value\": \"${SABNZBD_API_KEY}\"},
                            {\"name\": \"tvCategory\", \"value\": \"tv\"}
                        ],
                        \"implementationName\": \"SABnzbd\",
                        \"implementation\": \"Sabnzbd\",
                        \"configContract\": \"SabnzbdSettings\",
                        \"tags\": []
                    }" > /dev/null 2>&1 && print_success "SABnzbd added to Sonarr" || print_warning "SABnzbd may already exist in Sonarr"
            fi

            print_info "Adding SABnzbd to Radarr..."
            if [ -n "$RADARR_API_KEY" ]; then
                curl -s -X POST "http://localhost:7878/api/v3/downloadclient" \
                    -H "X-Api-Key: $RADARR_API_KEY" \
                    -H "Content-Type: application/json" \
                    -d "{
                        \"enable\": true,
                        \"protocol\": \"usenet\",
                        \"priority\": 1,
                        \"removeCompletedDownloads\": true,
                        \"removeFailedDownloads\": true,
                        \"name\": \"SABnzbd\",
                        \"fields\": [
                            {\"name\": \"host\", \"value\": \"sabnzbd\"},
                            {\"name\": \"port\", \"value\": 8080},
                            {\"name\": \"apiKey\", \"value\": \"${SABNZBD_API_KEY}\"},
                            {\"name\": \"movieCategory\", \"value\": \"movies\"}
                        ],
                        \"implementationName\": \"SABnzbd\",
                        \"implementation\": \"Sabnzbd\",
                        \"configContract\": \"SabnzbdSettings\",
                        \"tags\": []
                    }" > /dev/null 2>&1 && print_success "SABnzbd added to Radarr" || print_warning "SABnzbd may already exist in Radarr"
            fi
        else
            print_error "Could not get SABnzbd API key after wizard completion"
            print_info "Configure Newshosting manually at http://localhost:8085"
        fi
    fi
else
    # Check if already configured
    if [ -n "$(grep "^NEWSHOSTING_USER=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
        print_info "Newshosting already configured"
    else
        print_info "Skipping Newshosting configuration"
    fi
fi

# NZBgeek Indexer Configuration
CONFIGURE_NZBGEEK="n"
if [ -z "$(grep "^NZBGEEK_API_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
    echo ""
    echo -n "Do you want to configure NZBgeek (Usenet indexer)? (y/N): "
    read -r CONFIGURE_NZBGEEK
fi

if [[ "$CONFIGURE_NZBGEEK" =~ ^[Yy]$ ]]; then
    print_info "Configuring NZBgeek indexer..."
    print_info "Get your API key from: https://nzbgeek.info/myaccount.php"

    NZBGEEK_API_KEY=$(prompt_credential "NZBGEEK_API_KEY" "NZBgeek API key: " "false")

    if [ -n "$NZBGEEK_API_KEY" ] && [ -n "$PROWLARR_API_KEY" ]; then
        print_info "Adding NZBgeek to Prowlarr..."
        curl -s -X POST "http://localhost:9696/api/v1/indexer" \
            -H "X-Api-Key: $PROWLARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"NZBgeek\",
                \"enable\": true,
                \"appProfileId\": 1,
                \"priority\": 25,
                \"fields\": [
                    {\"name\": \"baseUrl\", \"value\": \"https://api.nzbgeek.info\"},
                    {\"name\": \"apiPath\", \"value\": \"/api\"},
                    {\"name\": \"apiKey\", \"value\": \"${NZBGEEK_API_KEY}\"},
                    {\"name\": \"vipExpiration\", \"value\": \"\"},
                    {\"name\": \"baseSettings.limitsUnit\", \"value\": 0}
                ],
                \"implementationName\": \"Newznab\",
                \"implementation\": \"Newznab\",
                \"configContract\": \"NewznabSettings\",
                \"tags\": []
            }" > /dev/null 2>&1 && print_success "NZBgeek added to Prowlarr" || print_warning "NZBgeek may already exist or failed to add"
    fi
else
    if [ -n "$(grep "^NZBGEEK_API_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
        print_info "NZBgeek already configured"
    else
        print_info "Skipping NZBgeek configuration"
    fi
fi

# ============================================
# RUN RECYCLARR
# ============================================

if [ -n "$SONARR_API_KEY" ] && [ -n "$RADARR_API_KEY" ]; then
    print_section "Syncing Quality Profiles with Recyclarr"

    # Ensure recyclarr config directory and cache exist
    RECYCLARR_CONFIG_DIR="${PROJECT_ROOT}/data/recyclarr/config"
    RECYCLARR_CACHE="${RECYCLARR_CONFIG_DIR}/cache"
    mkdir -p "$RECYCLARR_CACHE"

    # Copy recyclarr.yml config if it doesn't exist
    if [ ! -f "${RECYCLARR_CONFIG_DIR}/recyclarr.yml" ]; then
        if [ -f "${PROJECT_ROOT}/config/recyclarr.yml" ]; then
            cp "${PROJECT_ROOT}/config/recyclarr.yml" "${RECYCLARR_CONFIG_DIR}/recyclarr.yml"
            print_success "Copied recyclarr.yml configuration"
        else
            print_error "config/recyclarr.yml not found in project"
            print_info "Skipping Recyclarr sync"
        fi
    fi

    # Fix ownership if running as root
    if [ "$(id -u)" = "0" ]; then
        chown -R "${PUID:-1000}:${PGID:-1000}" "${PROJECT_ROOT}/data/recyclarr"
    fi

    # Only run if config exists
    if [ -f "${RECYCLARR_CONFIG_DIR}/recyclarr.yml" ]; then
        print_info "Running Recyclarr sync..."
        # Pass API keys as environment variables to the container
        if docker compose run --rm \
            -e SONARR_API_KEY="$SONARR_API_KEY" \
            -e RADARR_API_KEY="$RADARR_API_KEY" \
            recyclarr sync; then
            print_success "Quality profiles synced successfully"
            print_info "Custom formats from TRaSH Guides have been applied"
        else
            print_warning "Recyclarr sync failed - you may need to run it manually later"
            print_info "Run: docker compose run --rm recyclarr sync"
        fi
    fi
fi

# ============================================
# JELLYSEERR CONFIGURATION
# ============================================

print_section "Configuring Jellyseerr"

JELLYSEERR_SETTINGS="${PROJECT_ROOT}/data/jellyseerr/config/settings.json"

if [ -f "$JELLYSEERR_SETTINGS" ] && command -v jq &> /dev/null; then
    # Get Jellyseerr API key from settings
    JELLYSEERR_API_KEY=$(jq -r '.main.apiKey' "$JELLYSEERR_SETTINGS" 2>/dev/null || true)

    if [ -n "$JELLYSEERR_API_KEY" ] && [ "$JELLYSEERR_API_KEY" != "null" ]; then
        # Check if Radarr is already configured
        EXISTING_RADARR=$(curl -s -H "X-Api-Key: $JELLYSEERR_API_KEY" \
            "http://localhost:5055/api/v1/settings/radarr" 2>/dev/null || echo "[]")

        if [ "$EXISTING_RADARR" = "[]" ] && [ -n "$RADARR_API_KEY" ]; then
            print_info "Adding Radarr to Jellyseerr..."

            # Get Radarr quality profile ID for HD-1080p
            RADARR_PROFILE_ID=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" \
                "http://localhost:7878/api/v3/qualityprofile" 2>/dev/null | \
                jq -r '.[] | select(.name == "HD-1080p") | .id' || echo "1")
            RADARR_PROFILE_ID=${RADARR_PROFILE_ID:-1}

            curl -s -X POST -H "X-Api-Key: $JELLYSEERR_API_KEY" \
                -H "Content-Type: application/json" \
                "http://localhost:5055/api/v1/settings/radarr" \
                -d "{
                    \"name\": \"Radarr\",
                    \"hostname\": \"radarr\",
                    \"port\": 7878,
                    \"apiKey\": \"${RADARR_API_KEY}\",
                    \"useSsl\": false,
                    \"baseUrl\": \"\",
                    \"activeProfileId\": ${RADARR_PROFILE_ID},
                    \"activeProfileName\": \"HD-1080p\",
                    \"activeDirectory\": \"/media/movies\",
                    \"is4k\": false,
                    \"minimumAvailability\": \"released\",
                    \"tags\": [],
                    \"isDefault\": true,
                    \"syncEnabled\": true,
                    \"preventSearch\": false,
                    \"tagRequests\": false
                }" > /dev/null 2>&1 && print_success "Radarr added to Jellyseerr" || print_warning "Failed to add Radarr"
        else
            print_info "Radarr already configured in Jellyseerr"
        fi

        # Check if Sonarr is already configured
        EXISTING_SONARR=$(curl -s -H "X-Api-Key: $JELLYSEERR_API_KEY" \
            "http://localhost:5055/api/v1/settings/sonarr" 2>/dev/null || echo "[]")

        if [ "$EXISTING_SONARR" = "[]" ] && [ -n "$SONARR_API_KEY" ]; then
            print_info "Adding Sonarr to Jellyseerr..."

            # Get Sonarr quality profile ID for WEB-1080p
            SONARR_PROFILE_ID=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" \
                "http://localhost:8989/api/v3/qualityprofile" 2>/dev/null | \
                jq -r '.[] | select(.name == "WEB-1080p") | .id' || echo "1")
            SONARR_PROFILE_ID=${SONARR_PROFILE_ID:-1}

            curl -s -X POST -H "X-Api-Key: $JELLYSEERR_API_KEY" \
                -H "Content-Type: application/json" \
                "http://localhost:5055/api/v1/settings/sonarr" \
                -d "{
                    \"name\": \"Sonarr\",
                    \"hostname\": \"sonarr\",
                    \"port\": 8989,
                    \"apiKey\": \"${SONARR_API_KEY}\",
                    \"useSsl\": false,
                    \"baseUrl\": \"\",
                    \"activeProfileId\": ${SONARR_PROFILE_ID},
                    \"activeProfileName\": \"WEB-1080p\",
                    \"activeDirectory\": \"/media/tv\",
                    \"activeAnimeProfileId\": ${SONARR_PROFILE_ID},
                    \"activeAnimeProfileName\": \"WEB-1080p\",
                    \"activeAnimeDirectory\": \"/media/tv\",
                    \"tags\": [],
                    \"animeTags\": [],
                    \"is4k\": false,
                    \"isDefault\": true,
                    \"enableSeasonFolders\": true,
                    \"syncEnabled\": true,
                    \"preventSearch\": false,
                    \"tagRequests\": false
                }" > /dev/null 2>&1 && print_success "Sonarr added to Jellyseerr" || print_warning "Failed to add Sonarr"
        else
            print_info "Sonarr already configured in Jellyseerr"
        fi
    else
        print_warning "Jellyseerr API key not found - complete the setup wizard first"
        print_info "Visit http://localhost:5055 to complete Jellyseerr setup"
    fi
else
    print_warning "Jellyseerr settings not found or jq not installed"
    print_info "Configure Jellyseerr manually at http://localhost:5055"
fi

# ============================================
# ARM CONFIGURATION
# ============================================

print_section "Configuring ARM (Automatic Ripping Machine)"

ARM_CONFIG="${PROJECT_ROOT}/data/arm/config/arm.yaml"

if [ -f "$ARM_CONFIG" ]; then
    print_info "Updating ARM configuration..."

    # Fix COMPLETED_PATH to output directly to movies folder
    if grep -q 'COMPLETED_PATH: "/home/arm/media/completed/"' "$ARM_CONFIG"; then
        sed -i 's|COMPLETED_PATH: "/home/arm/media/completed/"|COMPLETED_PATH: "/home/arm/movies/"|' "$ARM_CONFIG"
        print_success "COMPLETED_PATH updated to /home/arm/movies/"
    elif grep -q 'COMPLETED_PATH: "/home/arm/movies/"' "$ARM_CONFIG"; then
        print_info "COMPLETED_PATH already set correctly"
    else
        print_warning "COMPLETED_PATH has custom value - skipping"
    fi

    # Add TMDB API key if available and not already set
    if [ -n "${TMDB_API_KEY:-}" ]; then
        if grep -q 'TMDB_API_KEY: ""' "$ARM_CONFIG"; then
            sed -i "s|TMDB_API_KEY: \"\"|TMDB_API_KEY: \"${TMDB_API_KEY}\"|" "$ARM_CONFIG"
            print_success "TMDB_API_KEY added to ARM config"
        elif grep -q "TMDB_API_KEY: \"${TMDB_API_KEY}\"" "$ARM_CONFIG"; then
            print_info "TMDB_API_KEY already configured"
        else
            print_info "TMDB_API_KEY already has a value"
        fi

        # Switch to TMDB as metadata provider (more reliable than OMDB)
        if grep -q 'METADATA_PROVIDER: "omdb"' "$ARM_CONFIG"; then
            sed -i 's|METADATA_PROVIDER: "omdb"|METADATA_PROVIDER: "tmdb"|' "$ARM_CONFIG"
            print_success "Switched metadata provider to TMDB"
        fi
    else
        print_warning "No TMDB_API_KEY in .env - ARM may have trouble identifying discs"
        print_info "Get a free API key at: https://www.themoviedb.org/settings/api"
    fi

    # Fault tolerance: Skip transcoding (let Tdarr handle it)
    if grep -q 'SKIP_TRANSCODE: false' "$ARM_CONFIG"; then
        sed -i 's|SKIP_TRANSCODE: false|SKIP_TRANSCODE: true|' "$ARM_CONFIG"
        print_success "SKIP_TRANSCODE enabled (Tdarr will handle transcoding)"
    fi

    # Fault tolerance: Keep raw files on failure for recovery
    if grep -q 'DELRAWFILES: true' "$ARM_CONFIG"; then
        sed -i 's|DELRAWFILES: true|DELRAWFILES: false|' "$ARM_CONFIG"
        print_success "DELRAWFILES disabled (preserves files on failure)"
    fi

    # Fault tolerance: Add MakeMKV retry arguments for read errors
    if grep -q 'MKV_ARGS: ""' "$ARM_CONFIG"; then
        sed -i 's|MKV_ARGS: ""|MKV_ARGS: "--minlength=600 -r"|' "$ARM_CONFIG"
        print_success "MKV_ARGS set with retry flag for read errors"
    fi

    # Restart ARM to apply changes
    print_info "Restarting ARM container..."
    docker restart arm > /dev/null 2>&1 && print_success "ARM restarted" || print_warning "Failed to restart ARM"
else
    print_warning "ARM config not found at $ARM_CONFIG"
    print_info "ARM will be configured on first run"
fi

# ============================================
# TDARR CONFIGURATION
# ============================================

print_section "Configuring Tdarr (Transcoding)"

# Wait for Tdarr to be ready
wait_for_service "Tdarr" "http://localhost:8265" || {
    print_warning "Tdarr not ready - skipping configuration"
    print_info "Configure manually at http://localhost:8265"
}

# Generate schedule JSON (all hours enabled)
generate_tdarr_schedule() {
    local schedule="["
    local first=true
    for day in Sun Mon Tue Wed Thur Fri Sat; do
        for hour in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do
            local next_hour=$(printf "%02d" $(( (10#$hour + 1) % 24 )))
            if [ "$first" = true ]; then
                first=false
            else
                schedule+=","
            fi
            schedule+="{\"_id\":\"${day}:${hour}-${next_hour}\",\"checked\":true}"
        done
    done
    schedule+="]"
    echo "$schedule"
}

# Check if Movies library already exists
EXISTING_LIBRARIES=$(curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
    -H "Content-Type: application/json" \
    -d '{"data": {"collection":"LibrarySettingsJSONDB","mode":"getAll"}}' 2>/dev/null || echo "{}")

TDARR_SCHEDULE=$(generate_tdarr_schedule)

if echo "$EXISTING_LIBRARIES" | grep -q '"name":"Movies"'; then
    print_info "Tdarr Movies library already exists"
else
    print_info "Creating Tdarr Movies library..."

    # Generate a unique library ID
    LIBRARY_ID=$(openssl rand -hex 5)

    # Create the Movies library via API with all required fields
    TDARR_RESPONSE=$(curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
        -H "Content-Type: application/json" \
        -d "{
            \"data\": {
                \"collection\": \"LibrarySettingsJSONDB\",
                \"mode\": \"insert\",
                \"docID\": \"${LIBRARY_ID}\",
                \"obj\": {
                    \"_id\": \"${LIBRARY_ID}\",
                    \"name\": \"Movies\",
                    \"priority\": 0,
                    \"folder\": \"/media/movies\",
                    \"foldersToIgnore\": \"\",
                    \"foldersToIgnoreCaseInsensitive\": false,
                    \"folderWatchScanInterval\": 30,
                    \"scannerThreadCount\": 2,
                    \"cache\": \"/temp\",
                    \"output\": \"\",
                    \"folderToFolderConversion\": false,
                    \"folderToFolderConversionDeleteSource\": false,
                    \"folderToFolderRecordHistory\": true,
                    \"copyIfConditionsMet\": false,
                    \"container\": \".mkv\",
                    \"containerFilter\": \"mkv,mp4,mov,m4v,mpg,mpeg,avi,flv,webm,wmv,vob,evo,iso,m2ts,ts\",
                    \"createdAt\": $(date +%s)000,
                    \"folderWatching\": true,
                    \"useFsEvents\": false,
                    \"scheduledScanFindNew\": false,
                    \"processLibrary\": true,
                    \"processTranscodes\": true,
                    \"processHealthChecks\": true,
                    \"scanOnStart\": false,
                    \"exifToolScan\": true,
                    \"mediaInfoScan\": true,
                    \"ffprobeShowData\": false,
                    \"isDirectoryLibrary\": false,
                    \"closedCaptionScan\": false,
                    \"scanButtons\": true,
                    \"scanFound\": \"Files found:0\",
                    \"navItemSelected\": \"navSourceFolder\",
                    \"pluginIDs\": [],
                    \"pluginCommunity\": true,
                    \"handbrake\": true,
                    \"ffmpeg\": false,
                    \"handbrakescan\": true,
                    \"ffmpegscan\": false,
                    \"preset\": \"-Z \\\"Very Fast 1080p30\\\"\",
                    \"decisionMaker\": {
                        \"settingsPlugin\": false,
                        \"settingsFlows\": true,
                        \"settingsVideo\": false,
                        \"videoExcludeSwitch\": true,
                        \"video_codec_names_exclude\": [{\"codec\":\"hevc\",\"checked\":false},{\"codec\":\"h264\",\"checked\":true}],
                        \"video_size_range_include\": {\"min\":0,\"max\":100000},
                        \"video_height_range_include\": {\"min\":0,\"max\":3000},
                        \"video_width_range_include\": {\"min\":0,\"max\":4000},
                        \"settingsAudio\": false,
                        \"audioExcludeSwitch\": true,
                        \"audio_codec_names_exclude\": [{\"codec\":\"mp3\",\"checked\":true},{\"codec\":\"aac\",\"checked\":false}],
                        \"audio_size_range_include\": {\"min\":0,\"max\":10}
                    },
                    \"schedule\": ${TDARR_SCHEDULE},
                    \"totalHealthCheckCount\": 0,
                    \"totalTranscodeCount\": 0,
                    \"sizeDiff\": 0,
                    \"holdNewFiles\": false,
                    \"holdFor\": 3600,
                    \"holdForDisplayUnit\": \"hours\",
                    \"pluginStackOverview\": true,
                    \"filterResolutionsSkip\": \"\",
                    \"filterCodecsSkip\": \"\",
                    \"filterContainersSkip\": \"\",
                    \"processPluginsSequentially\": true
                }
            }
        }" 2>/dev/null)

    if echo "$TDARR_RESPONSE" | grep -q "\"_id\":\"${LIBRARY_ID}\""; then
        print_success "Movies library created with folder watching enabled"
    else
        print_warning "Could not create Movies library via API"
        print_info "Create manually at http://localhost:8265"
    fi
fi

# Check for TV library
if echo "$EXISTING_LIBRARIES" | grep -q '"name":"TV Shows"'; then
    print_info "Tdarr TV Shows library already exists"
else
    print_info "Creating Tdarr TV Shows library..."

    TV_LIBRARY_ID=$(openssl rand -hex 5)

    TDARR_TV_RESPONSE=$(curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
        -H "Content-Type: application/json" \
        -d "{
            \"data\": {
                \"collection\": \"LibrarySettingsJSONDB\",
                \"mode\": \"insert\",
                \"docID\": \"${TV_LIBRARY_ID}\",
                \"obj\": {
                    \"_id\": \"${TV_LIBRARY_ID}\",
                    \"name\": \"TV Shows\",
                    \"priority\": 1,
                    \"folder\": \"/media/tv\",
                    \"foldersToIgnore\": \"\",
                    \"foldersToIgnoreCaseInsensitive\": false,
                    \"folderWatchScanInterval\": 30,
                    \"scannerThreadCount\": 2,
                    \"cache\": \"/temp\",
                    \"output\": \"\",
                    \"folderToFolderConversion\": false,
                    \"folderToFolderConversionDeleteSource\": false,
                    \"folderToFolderRecordHistory\": true,
                    \"copyIfConditionsMet\": false,
                    \"container\": \".mkv\",
                    \"containerFilter\": \"mkv,mp4,mov,m4v,mpg,mpeg,avi,flv,webm,wmv,vob,evo,iso,m2ts,ts\",
                    \"createdAt\": $(date +%s)000,
                    \"folderWatching\": true,
                    \"useFsEvents\": false,
                    \"scheduledScanFindNew\": false,
                    \"processLibrary\": true,
                    \"processTranscodes\": true,
                    \"processHealthChecks\": true,
                    \"scanOnStart\": false,
                    \"exifToolScan\": true,
                    \"mediaInfoScan\": true,
                    \"ffprobeShowData\": false,
                    \"isDirectoryLibrary\": false,
                    \"closedCaptionScan\": false,
                    \"scanButtons\": true,
                    \"scanFound\": \"\",
                    \"navItemSelected\": \"navSourceFolder\",
                    \"pluginIDs\": [],
                    \"pluginCommunity\": true,
                    \"handbrake\": true,
                    \"ffmpeg\": false,
                    \"handbrakescan\": true,
                    \"ffmpegscan\": false,
                    \"preset\": \"-Z \\\"Very Fast 1080p30\\\"\",
                    \"decisionMaker\": {
                        \"settingsPlugin\": false,
                        \"settingsFlows\": true,
                        \"settingsVideo\": false,
                        \"videoExcludeSwitch\": true,
                        \"video_codec_names_exclude\": [{\"codec\":\"hevc\",\"checked\":false},{\"codec\":\"h264\",\"checked\":true}],
                        \"video_size_range_include\": {\"min\":0,\"max\":100000},
                        \"video_height_range_include\": {\"min\":0,\"max\":3000},
                        \"video_width_range_include\": {\"min\":0,\"max\":4000},
                        \"settingsAudio\": false,
                        \"audioExcludeSwitch\": true,
                        \"audio_codec_names_exclude\": [{\"codec\":\"mp3\",\"checked\":true},{\"codec\":\"aac\",\"checked\":false}],
                        \"audio_size_range_include\": {\"min\":0,\"max\":10}
                    },
                    \"schedule\": ${TDARR_SCHEDULE},
                    \"totalHealthCheckCount\": 0,
                    \"totalTranscodeCount\": 0,
                    \"sizeDiff\": 0,
                    \"holdNewFiles\": false,
                    \"holdFor\": 3600,
                    \"holdForDisplayUnit\": \"hours\",
                    \"pluginStackOverview\": true,
                    \"filterResolutionsSkip\": \"\",
                    \"filterCodecsSkip\": \"\",
                    \"filterContainersSkip\": \"\",
                    \"processPluginsSequentially\": true
                }
            }
        }" 2>/dev/null)

    if echo "$TDARR_TV_RESPONSE" | grep -q "\"_id\":\"${TV_LIBRARY_ID}\""; then
        print_success "TV Shows library created with folder watching enabled"
    else
        print_warning "Could not create TV Shows library via API"
    fi
fi

print_info ""
print_info "Tdarr libraries configured. To complete setup:"
print_info "  1. Open http://localhost:8265"
print_info "  2. Create a flow with: Input File → Check File Medium → Begin Command"
print_info "     → Set Video Encoder (hevc_vaapi for AMD) → Set Container (mkv)"
print_info "     → Execute → Replace Original File"
print_info "  3. Assign the flow to each library in Transcode Options"
print_info ""
print_success "ARM will output raw MKV files → Tdarr will transcode automatically"

# ============================================
# SUMMARY
# ============================================

print_section "Configuration Complete!"

print_info "Services configured:"
print_success "✓ Prowlarr - Indexer management with FlareSolverr"
print_success "✓ Sonarr - TV shows with download clients"
print_success "✓ Radarr - Movies with download clients"
print_success "✓ Lidarr - Music with download clients"
print_success "✓ Bazarr - Subtitles (may need manual configuration)"
print_success "✓ ARM - Blu-ray/DVD ripping (fault-tolerant, raw output)"
print_success "✓ Tdarr - Automatic transcoding with folder watching"
print_success "✓ Prowlarr synced to *arr apps"
[ -n "$SONARR_API_KEY" ] && [ -n "$RADARR_API_KEY" ] && print_success "✓ Quality profiles synced via Recyclarr"

echo ""
print_info "API Keys saved to .env:"
[ -n "$SONARR_API_KEY" ] && print_info "  SONARR_API_KEY=${SONARR_API_KEY}"
[ -n "$RADARR_API_KEY" ] && print_info "  RADARR_API_KEY=${RADARR_API_KEY}"
[ -n "$LIDARR_API_KEY" ] && print_info "  LIDARR_API_KEY=${LIDARR_API_KEY}"

echo ""
print_info "Still need manual configuration:"
if [ -z "$(grep "^NZBGEEK_API_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
    print_warning "⚠ Prowlarr: Add indexers at http://localhost:9696"
fi

# Get qBittorrent temporary password from logs
QBIT_TEMP_PASS=$(docker compose logs qbittorrent 2>/dev/null | grep -oP 'temporary password is provided for this session: \K\S+' | tail -1 || true)
if [ -n "$QBIT_TEMP_PASS" ]; then
    print_warning "⚠ qBittorrent: Change password at http://localhost:8080"
    print_info "    Username: admin"
    print_info "    Temporary Password: ${QBIT_TEMP_PASS}"
    print_info "    Change under: Settings → WebUI → Authentication"
else
    print_warning "⚠ qBittorrent: Change default password at http://localhost:8080"
fi

if [ -z "$(grep "^NEWSHOSTING_USER=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
    print_warning "⚠ SABnzbd: Add Usenet servers at http://localhost:8085"
fi
print_warning "⚠ Jellyfin: Complete initial setup at http://localhost:8096"
print_warning "⚠ Jellyseerr: Link to Jellyfin at http://localhost:5055"

echo ""
print_success "Your homelab is ready to use!"
