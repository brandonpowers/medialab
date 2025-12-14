#!/bin/bash
#
# api.sh - Service API helper functions
# HTTP request wrappers and service communication utilities
#

# Prevent multiple sourcing
[[ -n "${_HOMELAB_API_LOADED:-}" ]] && return 0
_HOMELAB_API_LOADED=1

# Source common.sh and progress.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/progress.sh"

# ============================================
# SERVICE READINESS
# ============================================

# Wait for a service to be ready
# Usage: wait_for_service <name> <url> [max_attempts] [interval]
wait_for_service() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-30}"
    local interval="${4:-2}"
    local attempt=1

    report_log "info" "Waiting for $name to be ready..."

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
            report_log "success" "$name is ready"
            return 0
        fi

        if [[ "$OUTPUT_MODE" == "cli" ]]; then
            echo -n "."
        fi

        sleep "$interval"
        ((attempt++))
    done

    report_log "warning" "$name failed to become ready after $max_attempts attempts"
    return 1
}

# Check if a service is healthy
# Usage: check_service_health <name> <url>
check_service_health() {
    local name="$1"
    local url="$2"

    if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ============================================
# API KEY EXTRACTION
# ============================================

# Get API key from service config file
# Usage: get_api_key <service> [project_root]
get_api_key() {
    local service="$1"
    local project_root="${2:-$(get_project_root)}"
    local api_key=""

    # Handle different config formats
    if [[ "$service" == "bazarr" ]]; then
        # Bazarr uses YAML config
        local config_file="${project_root}/data/${service}/config/config/config.yaml"
        if [[ -f "$config_file" ]]; then
            api_key=$(grep -oP '^\s*apikey:\s*\K\S+' "$config_file" 2>/dev/null | head -1 || true)
        fi
    elif [[ "$service" == "sabnzbd" ]]; then
        # SABnzbd uses INI config
        local config_file="${project_root}/data/${service}/config/sabnzbd.ini"
        if [[ -f "$config_file" ]]; then
            api_key=$(grep -oP '^api_key\s*=\s*\K\S+' "$config_file" 2>/dev/null || true)
        fi
    else
        # *arr apps use XML config
        local config_file="${project_root}/data/${service}/config/config.xml"
        if [[ -f "$config_file" ]]; then
            api_key=$(grep -oP '<ApiKey>\K[^<]+' "$config_file" 2>/dev/null || true)
        fi
    fi

    echo "$api_key"
}

# ============================================
# HTTP REQUEST HELPERS
# ============================================

# Make an API GET request
# Usage: api_get <url> [api_key] [api_header_name]
api_get() {
    local url="$1"
    local api_key="${2:-}"
    local header_name="${3:-X-Api-Key}"

    local args=(-s --max-time 30)

    if [[ -n "$api_key" ]]; then
        args+=(-H "${header_name}: ${api_key}")
    fi

    curl "${args[@]}" "$url"
}

# Make an API POST request with JSON body
# Usage: api_post <url> <json_body> [api_key] [api_header_name]
api_post() {
    local url="$1"
    local body="$2"
    local api_key="${3:-}"
    local header_name="${4:-X-Api-Key}"

    local args=(-s --max-time 30 -X POST -H "Content-Type: application/json")

    if [[ -n "$api_key" ]]; then
        args+=(-H "${header_name}: ${api_key}")
    fi

    args+=(-d "$body")

    curl "${args[@]}" "$url"
}

# Make an API PUT request with JSON body
# Usage: api_put <url> <json_body> [api_key] [api_header_name]
api_put() {
    local url="$1"
    local body="$2"
    local api_key="${3:-}"
    local header_name="${4:-X-Api-Key}"

    local args=(-s --max-time 30 -X PUT -H "Content-Type: application/json")

    if [[ -n "$api_key" ]]; then
        args+=(-H "${header_name}: ${api_key}")
    fi

    args+=(-d "$body")

    curl "${args[@]}" "$url"
}

# ============================================
# ARR APP HELPERS
# ============================================

# Configure authentication for *arr app
# Usage: configure_arr_auth <service_url> <api_key> <username> <password> [api_version]
configure_arr_auth() {
    local url="$1"
    local api_key="$2"
    local username="$3"
    local password="$4"
    local api_version="${5:-v3}"

    # Get current host config
    local current_config
    current_config=$(api_get "${url}/api/${api_version}/config/host" "$api_key" 2>/dev/null || echo "{}")

    # Extract current ID (needed for PUT)
    local config_id
    config_id=$(echo "$current_config" | grep -oP '"id":\s*\K\d+' | head -1 || echo "1")

    # Build auth config payload
    local auth_body
    auth_body=$(cat <<EOF
{
    "id": ${config_id},
    "bindAddress": "*",
    "port": $(echo "$current_config" | grep -oP '"port":\s*\K\d+' | head -1 || echo "8989"),
    "urlBase": "",
    "instanceName": "$(echo "$current_config" | grep -oP '"instanceName":\s*"\K[^"]+' | head -1 || echo "")",
    "authenticationMethod": "forms",
    "authenticationRequired": "enabled",
    "username": "${username}",
    "password": "${password}",
    "certificateValidation": "enabled"
}
EOF
)

    if api_put "${url}/api/${api_version}/config/host" "$auth_body" "$api_key" > /dev/null 2>&1; then
        report_log "success" "Authentication configured"
        return 0
    else
        report_log "warning" "Could not configure authentication"
        return 1
    fi
}

# Get quality profile ID by name from *arr app
# Usage: get_quality_profile_id <service_url> <api_key> <profile_name>
get_quality_profile_id() {
    local url="$1"
    local api_key="$2"
    local profile_name="$3"

    local profiles
    profiles=$(api_get "${url}/api/v3/qualityprofile" "$api_key")

    echo "$profiles" | grep -oP "\"id\":\s*\K\d+(?=.*\"name\":\s*\"${profile_name}\")" | head -1
}

# Check if download client exists
# Usage: download_client_exists <service_url> <api_key> <client_name>
download_client_exists() {
    local url="$1"
    local api_key="$2"
    local client_name="$3"

    local clients
    clients=$(api_get "${url}/api/v3/downloadclient" "$api_key")

    # Handle both compact and pretty JSON
    echo "$clients" | grep -qE "\"name\":[[:space:]]*\"${client_name}\""
}

# Check if root folder exists
# Usage: root_folder_exists <service_url> <api_key> <path>
root_folder_exists() {
    local url="$1"
    local api_key="$2"
    local path="$3"

    local folders
    folders=$(api_get "${url}/api/v3/rootfolder" "$api_key")

    # Handle both compact JSON ("path":"/media/tv") and pretty JSON ("path": "/media/tv")
    echo "$folders" | grep -qE "\"path\":[[:space:]]*\"${path}\""
}

# Add root folder to *arr app
# Usage: add_root_folder <service_url> <api_key> <path>
add_root_folder() {
    local url="$1"
    local api_key="$2"
    local path="$3"

    if root_folder_exists "$url" "$api_key" "$path"; then
        report_log "info" "Root folder $path already exists"
        return 0
    fi

    local body="{\"path\":\"${path}\"}"
    api_post "${url}/api/v3/rootfolder" "$body" "$api_key" > /dev/null

    if root_folder_exists "$url" "$api_key" "$path"; then
        report_log "success" "Added root folder: $path"
        return 0
    else
        report_log "warning" "Failed to add root folder: $path"
        return 1
    fi
}

# ============================================
# PROWLARR HELPERS
# ============================================

# Check if indexer exists in Prowlarr
# Usage: indexer_exists <api_key> <indexer_name>
indexer_exists() {
    local api_key="$1"
    local indexer_name="$2"

    local indexers
    indexers=$(api_get "http://localhost:9696/api/v1/indexer" "$api_key")

    echo "$indexers" | grep -q "\"name\":\"${indexer_name}\""
}

# Add public indexer to Prowlarr
# Usage: add_public_indexer <api_key> <name> <definition> [tags_json]
add_public_indexer() {
    local api_key="$1"
    local name="$2"
    local definition="$3"
    local tags="${4:-[]}"

    if indexer_exists "$api_key" "$name"; then
        report_log "info" "$name already exists, skipping"
        return 0
    fi

    local body
    body=$(cat <<EOF
{
    "name": "${name}",
    "definitionName": "${definition}",
    "enable": true,
    "redirect": false,
    "appProfileId": 1,
    "priority": 25,
    "fields": [
        {"name": "definitionFile", "value": "${definition}"}
    ],
    "implementationName": "Cardigann",
    "implementation": "Cardigann",
    "configContract": "CardigannSettings",
    "tags": ${tags}
}
EOF
)

    if api_post "http://localhost:9696/api/v1/indexer" "$body" "$api_key" > /dev/null 2>&1; then
        report_log "success" "$name added"
        return 0
    else
        report_log "warning" "Failed to add $name"
        return 1
    fi
}

# ============================================
# QBITTORRENT HELPERS
# ============================================

# Login to qBittorrent and get session cookie
# Usage: qbittorrent_login <username> <password>
# Returns: cookie file path (or empty on failure)
qbittorrent_login() {
    local username="$1"
    local password="$2"
    local cookie_file
    cookie_file=$(mktemp)

    local response
    response=$(curl -s --max-time 10 -c "$cookie_file" \
        --header 'Referer: http://localhost:8080' \
        --data "username=${username}&password=${password}" \
        "http://localhost:8080/api/v2/auth/login" 2>/dev/null || echo "FAILED")

    if [[ "$response" == "Ok." ]]; then
        echo "$cookie_file"
    else
        rm -f "$cookie_file"
        echo ""
    fi
}

# Make qBittorrent API request with session cookie
# Usage: qbittorrent_api <cookie_file> <endpoint> [post_data]
qbittorrent_api() {
    local cookie_file="$1"
    local endpoint="$2"
    local post_data="${3:-}"

    local args=(-s --max-time 10 -b "$cookie_file" --header 'Referer: http://localhost:8080')

    if [[ -n "$post_data" ]]; then
        args+=(--data "$post_data")
    fi

    curl "${args[@]}" "http://localhost:8080/api/v2/${endpoint}"
}
