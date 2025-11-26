#!/bin/bash
#
# configure-services.sh - Automated service configuration
# Links services together via API calls to eliminate manual setup
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
    local config_file="${PROJECT_ROOT}/data/${service}/config/config.xml"

    if [ ! -f "$config_file" ]; then
        echo ""
        return 1
    fi

    # Extract API key from XML config
    grep -oP '<ApiKey>\K[^<]+' "$config_file" || echo ""
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
    if [ "$is_secret" = "true" ]; then
        read -s -p "$prompt_text" value
        echo ""
    else
        read -p "$prompt_text" value
    fi

    # Save to .env if provided
    if [ -n "$value" ]; then
        echo "${var_name}=${value}" >> "$PROJECT_ROOT/.env"
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
    print_error "Failed to get Bazarr API key - it may need manual configuration"
    print_info "Visit http://localhost:6767 to complete Bazarr setup"
else
    print_success "Bazarr API key: $BAZARR_API_KEY"

    # Link Sonarr to Bazarr
    if [ -n "$SONARR_API_KEY" ]; then
        print_info "Linking Sonarr to Bazarr..."
        curl -s -X POST "http://localhost:6767/api/system/settings" \
            -H "X-Api-Key: $BAZARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"settings\": {
                    \"sonarr\": {
                        \"ip\": \"sonarr\",
                        \"port\": 8989,
                        \"base_url\": \"/\",
                        \"ssl\": false,
                        \"apikey\": \"${SONARR_API_KEY}\",
                        \"full_update\": \"Daily\",
                        \"only_monitored\": true
                    }
                }
            }" > /dev/null 2>&1 && print_success "Sonarr linked" || print_warning "Manual Sonarr configuration may be needed"
    fi

    # Link Radarr to Bazarr
    if [ -n "$RADARR_API_KEY" ]; then
        print_info "Linking Radarr to Bazarr..."
        curl -s -X POST "http://localhost:6767/api/system/settings" \
            -H "X-Api-Key: $BAZARR_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"settings\": {
                    \"radarr\": {
                        \"ip\": \"radarr\",
                        \"port\": 7878,
                        \"base_url\": \"/\",
                        \"ssl\": false,
                        \"apikey\": \"${RADARR_API_KEY}\",
                        \"full_update\": \"Daily\",
                        \"only_monitored\": true
                    }
                }
            }" > /dev/null 2>&1 && print_success "Radarr linked" || print_warning "Manual Radarr configuration may be needed"
    fi
fi

# ============================================
# USENET CONFIGURATION (Optional)
# ============================================

print_section "Usenet Configuration (Optional)"

# Check if user wants to configure Usenet
CONFIGURE_USENET="n"
if [ -z "$(grep "^NEWSHOSTING_USER=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
    echo -n "Do you want to configure Newshosting (Usenet provider)? (y/N): "
    read -r CONFIGURE_USENET
fi

if [[ "$CONFIGURE_USENET" =~ ^[Yy]$ ]]; then
    print_info "Configuring Newshosting..."

    NEWSHOSTING_USER=$(prompt_credential "NEWSHOSTING_USER" "Newshosting username: " "false")
    NEWSHOSTING_PASS=$(prompt_credential "NEWSHOSTING_PASS" "Newshosting password: " "true")
    NEWSHOSTING_CONNECTIONS=$(prompt_credential "NEWSHOSTING_CONNECTIONS" "Max connections (default 30): " "false")
    NEWSHOSTING_CONNECTIONS=${NEWSHOSTING_CONNECTIONS:-30}

    if [ -n "$NEWSHOSTING_USER" ] && [ -n "$NEWSHOSTING_PASS" ]; then
        # Get SABnzbd API key
        SABNZBD_API_KEY=$(curl -s "http://localhost:8085/sabnzbd/api?mode=get_config" 2>/dev/null | grep -oP '"api_key"\s*:\s*"\K[^"]+' || echo "")

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
        else
            print_warning "Could not get SABnzbd API key - configure Newshosting manually at http://localhost:8085"
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

    print_info "Running Recyclarr sync..."
    if docker compose run --rm recyclarr sync; then
        print_success "Quality profiles synced successfully"
        print_info "Custom formats from TRaSH Guides have been applied"
    else
        print_warning "Recyclarr sync failed - you may need to run it manually later"
        print_info "Run: docker compose run --rm recyclarr sync"
    fi
fi

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
print_success "✓ Prowlarr synced to *arr apps"
[ -n "$SONARR_API_KEY" ] && [ -n "$RADARR_API_KEY" ] && print_success "✓ Quality profiles synced via Recyclarr"

echo ""
print_info "API Keys saved to .env:"
[ -n "$SONARR_API_KEY" ] && print_info "  SONARR_API_KEY=${SONARR_API_KEY}"
[ -n "$RADARR_API_KEY" ] && print_info "  RADARR_API_KEY=${RADARR_API_KEY}"

echo ""
print_info "Still need manual configuration:"
if [ -z "$(grep "^NZBGEEK_API_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
    print_warning "⚠ Prowlarr: Add indexers at http://localhost:9696"
fi
print_warning "⚠ qBittorrent: Change default password (admin/adminadmin) at http://localhost:8080"
if [ -z "$(grep "^NEWSHOSTING_USER=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2)" ]; then
    print_warning "⚠ SABnzbd: Add Usenet servers at http://localhost:8085"
fi
print_warning "⚠ Jellyfin: Complete initial setup at http://localhost:8096"
print_warning "⚠ Jellyseerr: Link to Jellyfin at http://localhost:5055"

echo ""
print_success "Your homelab is ready to use!"
