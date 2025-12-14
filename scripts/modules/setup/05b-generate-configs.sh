#!/bin/bash
#
# 05b-generate-configs.sh - Generate service config files with pre-seeded credentials
# Creates config files for services that actually use pre-configuration
# Note: *arr apps (Sonarr, Radarr, etc.) generate their own configs - we configure them via API
#
# Usage:
#   ./05b-generate-configs.sh [--json] [--config file.json]
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
    esac
done

# Read value from JSON config or .env file
get_config_value() {
    local key="$1"
    local default="${2:-}"
    local project_root
    project_root=$(get_project_root)

    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        local value
        value=$(jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null || true)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi

    # Fall back to .env
    if [[ -f "$project_root/.env" ]]; then
        local env_key="${key^^}"
        env_key="${env_key//./_}"
        local value
        value=$(grep "^${env_key}=" "$project_root/.env" 2>/dev/null | cut -d= -f2- || true)
        if [[ -n "$value" ]]; then
            echo "$value"
            return
        fi
    fi

    echo "$default"
}

# Generate random API key (32 hex chars)
generate_api_key() {
    openssl rand -hex 16
}

# ============================================
# MAIN
# ============================================

main() {
    init_progress "Generate Service Configs" 5
    local project_root
    project_root=$(get_project_root)

    # Load environment
    if [[ -f "$project_root/.env" ]]; then
        load_env "$project_root/.env"
    fi

    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    local server_name="${SERVER_NAME:-homelab}"
    local language="${LANGUAGE:-en}"

    # Override from config file if provided
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        admin_user=$(get_config_value "admin.username" "$admin_user")
        admin_pass=$(get_config_value "admin.password" "$admin_pass")
        server_name=$(get_config_value "system.server_name" "$server_name")
        language=$(get_config_value "system.language" "$language")
    fi

    # Note: *arr apps (Sonarr, Radarr, Lidarr, Prowlarr) generate their own config.xml
    # with API keys on first start. We configure them via API in the configure phase.
    # This avoids sync issues between pre-generated keys and actual container keys.

    # Step 1: Generate qBittorrent config
    report_progress 1 5 "Generating qBittorrent config..."

    local qbit_config_dir="$project_root/data/qbittorrent/config/qBittorrent"
    if [[ -d "$project_root/data/qbittorrent/config" ]]; then
        mkdir -p "$qbit_config_dir"

        # Create categories.json if not exists
        if [[ ! -f "$qbit_config_dir/categories.json" ]]; then
            cat > "$qbit_config_dir/categories.json" << 'EOF'
{
    "movies": {
        "save_path": "/media/movies"
    },
    "music": {
        "save_path": "/media/music"
    },
    "tv": {
        "save_path": "/media/tv"
    }
}
EOF
            report_log "success" "Created qBittorrent categories.json"
        fi

        # Note: qBittorrent password will be changed via API after first run
        # Default credentials are admin/adminadmin
        report_log "info" "qBittorrent will use default credentials initially"
    fi

    report_progress 1 5 "qBittorrent config generated" "complete"

    # Step 2: Generate SABnzbd config
    report_progress 2 5 "Generating SABnzbd config..."

    local sab_config_dir="$project_root/data/sabnzbd/config"
    local sab_config="$sab_config_dir/sabnzbd.ini"

    if [[ -d "$sab_config_dir" && ! -f "$sab_config" ]]; then
        local sab_api_key
        sab_api_key=$(generate_api_key)
        local sab_nzb_key
        sab_nzb_key=$(generate_api_key)

        cat > "$sab_config" << EOF
[misc]
api_key = ${sab_api_key}
nzb_key = ${sab_nzb_key}
username = ${admin_user}
password = ${admin_pass}
host = 0.0.0.0
port = 8080
https_port = 9090
download_dir = /media/downloads/incomplete
complete_dir = /media/downloads/complete
dirscan_dir = /media/downloads/watch
log_dir = /config/logs
admin_dir = /config/admin
script_dir = /config/scripts
nzb_backup_dir = /config/nzb_backup
cache_dir = /config/cache
language = ${language}
local_ranges = 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8
inet_exposure = 4

[servers]

[categories]
[[*]]
dir =
newzbin =
priority = 0

[[movies]]
dir = movies
newzbin =
priority = 0

[[tv]]
dir = tv
newzbin =
priority = 0

[[music]]
dir = music
newzbin =
priority = 0
EOF

        # Save API key to .env
        set_env_value "SABNZBD_API_KEY" "$sab_api_key" "true" "$project_root/.env" || true
        report_log "success" "Created SABnzbd config with credentials"
    fi

    report_progress 2 5 "SABnzbd config generated" "complete"

    # Step 3: Generate Bazarr config
    report_progress 3 5 "Generating Bazarr config..."

    local bazarr_config_dir="$project_root/data/bazarr/config/config"
    if [[ -d "$project_root/data/bazarr/config" ]]; then
        mkdir -p "$bazarr_config_dir"
        local bazarr_config="$bazarr_config_dir/config.yaml"

        if [[ ! -f "$bazarr_config" ]]; then
            local bazarr_api_key
            bazarr_api_key=$(generate_api_key)

            # Map language code to Bazarr language name
            local bazarr_lang="en"
            case "$language" in
                es) bazarr_lang="es" ;;
                fr) bazarr_lang="fr" ;;
                de) bazarr_lang="de" ;;
                it) bazarr_lang="it" ;;
                pt) bazarr_lang="pt" ;;
                nl) bazarr_lang="nl" ;;
                pl) bazarr_lang="pl" ;;
                ru) bazarr_lang="ru" ;;
                ja) bazarr_lang="ja" ;;
                zh) bazarr_lang="zh" ;;
                ko) bazarr_lang="ko" ;;
            esac

            cat > "$bazarr_config" << EOF
analytics:
  enabled: true
auth:
  apikey: ${bazarr_api_key}
  type: null
  username: null
  password: null
general:
  base_url: /
  branch: master
  debug: false
  ip: 0.0.0.0
  port: 6767
  use_radarr: true
  use_sonarr: true
  single_language: false
  serie_default_enabled: true
  serie_default_language:
  - ${bazarr_lang}
  movie_default_enabled: true
  movie_default_language:
  - ${bazarr_lang}
sonarr:
  apikey: ''
  base_url: /
  full_update: Daily
  ip: sonarr
  only_monitored: false
  port: 8989
  ssl: false
radarr:
  apikey: ''
  base_url: /
  full_update: Daily
  ip: radarr
  only_monitored: false
  port: 7878
  ssl: false
EOF

            set_env_value "BAZARR_API_KEY" "$bazarr_api_key" "true" "$project_root/.env" || true
            report_log "success" "Created Bazarr config with language: $bazarr_lang"
        fi
    fi

    report_progress 3 5 "Bazarr config generated" "complete"

    # Step 4: Generate Tdarr config
    report_progress 4 5 "Generating Tdarr config..."

    local tdarr_config_dir="$project_root/data/tdarr/configs"
    if [[ -d "$tdarr_config_dir" ]]; then
        local tdarr_config="$tdarr_config_dir/Tdarr_Server_Config.json"

        if [[ ! -f "$tdarr_config" ]]; then
            local tdarr_api_key
            tdarr_api_key=$(generate_api_key)
            local tdarr_auth_key
            tdarr_auth_key=$(generate_api_key)

            cat > "$tdarr_config" << EOF
{
  "serverPort": "8266",
  "webUIPort": "8265",
  "serverIP": "0.0.0.0",
  "handbrakePath": "",
  "ffmpegPath": "",
  "mkvpropeditPath": "",
  "auth": true,
  "authSecretKey": "${tdarr_auth_key}",
  "seededApiKey": "${tdarr_api_key}",
  "logLevel": "info"
}
EOF

            set_env_value "TDARR_API_KEY" "$tdarr_api_key" "true" "$project_root/.env" || true
            set_env_value "TDARR_AUTH_KEY" "$tdarr_auth_key" "true" "$project_root/.env" || true
            report_log "success" "Created Tdarr config with authentication"
        fi
    fi

    report_progress 4 5 "Tdarr config generated" "complete"

    # Step 5: Generate Jellyfin config
    report_progress 5 5 "Generating Jellyfin config..."

    local jellyfin_config_dir="$project_root/data/jellyfin/config"
    if [[ -d "$jellyfin_config_dir" ]]; then
        local jellyfin_system="$jellyfin_config_dir/system.xml"

        # Note: We can't fully skip the wizard without database manipulation
        # But we can pre-set the server name
        if [[ ! -f "$jellyfin_system" ]]; then
            cat > "$jellyfin_system" << EOF
<?xml version="1.0" encoding="utf-8"?>
<ServerConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <IsStartupWizardCompleted>false</IsStartupWizardCompleted>
  <ServerName>${server_name}</ServerName>
  <EnableMetrics>false</EnableMetrics>
  <EnableNormalizedItemByNameIds>true</EnableNormalizedItemByNameIds>
  <IsPortAuthorized>true</IsPortAuthorized>
  <QuickConnectAvailable>true</QuickConnectAvailable>
  <EnableCaseSensitiveItemIds>true</EnableCaseSensitiveItemIds>
  <DisableLiveTvChannelUserDataName>true</DisableLiveTvChannelUserDataName>
  <MetadataPath>/config/metadata</MetadataPath>
  <MetadataNetworkPath />
  <PreferredMetadataLanguage>${language}</PreferredMetadataLanguage>
  <MetadataCountryCode>US</MetadataCountryCode>
  <SortReplaceCharacters>
    <string>.</string>
    <string>+</string>
    <string>%</string>
  </SortReplaceCharacters>
  <SortRemoveCharacters>
    <string>,</string>
    <string>&amp;</string>
    <string>-</string>
    <string>{</string>
    <string>}</string>
    <string>'</string>
  </SortRemoveCharacters>
  <SortRemoveWords>
    <string>the</string>
    <string>a</string>
    <string>an</string>
  </SortRemoveWords>
  <MinResumePct>5</MinResumePct>
  <MaxResumePct>90</MaxResumePct>
  <MinResumeDurationSeconds>300</MinResumeDurationSeconds>
  <MinAudiobookResume>5</MinAudiobookResume>
  <MaxAudiobookResume>5</MaxAudiobookResume>
  <InactiveSessionThreshold>0</InactiveSessionThreshold>
  <LibraryMonitorDelay>60</LibraryMonitorDelay>
  <ImageSavingConvention>Compatible</ImageSavingConvention>
  <SkipDeserializationForBasicTypes>true</SkipDeserializationForBasicTypes>
  <ChapterImageResolution>MatchSource</ChapterImageResolution>
  <ParallelImageEncodingLimit>0</ParallelImageEncodingLimit>
  <EnableSlowResponseWarning>true</EnableSlowResponseWarning>
  <SlowResponseThresholdMs>500</SlowResponseThresholdMs>
  <CorsHosts>
    <string>*</string>
  </CorsHosts>
  <ActivityLogRetentionDays>30</ActivityLogRetentionDays>
  <LibraryScanFanoutConcurrency>0</LibraryScanFanoutConcurrency>
  <LibraryMetadataRefreshConcurrency>0</LibraryMetadataRefreshConcurrency>
  <RemoveOldPlugins>false</RemoveOldPlugins>
  <AllowClientLogUpload>true</AllowClientLogUpload>
</ServerConfiguration>
EOF
            report_log "info" "Created Jellyfin config with server name: $server_name"
            report_log "warning" "Jellyfin wizard still requires manual completion"
        fi
    fi

    report_progress 5 5 "Jellyfin config generated" "complete"

    finish_progress "complete" "Service configs generated"
}

main "$@"
