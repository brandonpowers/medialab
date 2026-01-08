#!/bin/bash
#
# 05b-generate-homepage-config.sh - Generate Homepage configuration files
# Part of the setup phase
#
# Generates all Homepage YAML configuration files with service widgets
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Generate Homepage Config"
MODULE_STEP=5b
MODULE_TOTAL=13

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Generating Homepage Configuration"

    local project_root
    project_root=$(get_project_root)
    local config_dir="$project_root/data/homepage/config"

    # Create config directory if it doesn't exist
    mkdir -p "$config_dir"

    # Get server IP for URLs
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}' || echo "localhost")

    # Generate settings.yaml
    print_info "Generating settings.yaml..."
    cat > "$config_dir/settings.yaml" <<'EOF'
---
title: Medialab Dashboard
favicon: https://gethomepage.dev/img/favicon.ico
theme: dark
color: slate
layout:
  Media Streaming:
    style: row
    columns: 3
  Media Management:
    style: row
    columns: 3
  Media Production:
    style: row
    columns: 3
  Downloads:
    style: row
    columns: 2
  System:
    style: row
    columns: 2
EOF

    # Generate services.yaml
    print_info "Generating services.yaml..."
    cat > "$config_dir/services.yaml" <<EOF
---
- Media Streaming:
    - Jellyfin:
        icon: jellyfin.svg
        href: http://${server_ip}:8096
        description: Media Server
        widget:
          type: jellyfin
          url: http://jellyfin:8096
          key: {{HOMEPAGE_VAR_JELLYFIN_API_KEY}}
          enableBlocks: true
          enableNowPlaying: true

    - Jellyseerr:
        icon: jellyseerr.svg
        href: http://${server_ip}:5055
        description: Media Requests
        widget:
          type: jellyseerr
          url: http://jellyseerr:5055
          key: {{HOMEPAGE_VAR_JELLYSEERR_API_KEY}}

- Media Management:
    - Sonarr:
        icon: sonarr.svg
        href: http://${server_ip}:8989
        description: TV Show Management
        widget:
          type: sonarr
          url: http://sonarr:8989
          key: {{HOMEPAGE_VAR_SONARR_API_KEY}}
          enableQueue: true

    - Radarr:
        icon: radarr.svg
        href: http://${server_ip}:7878
        description: Movie Management
        widget:
          type: radarr
          url: http://radarr:7878
          key: {{HOMEPAGE_VAR_RADARR_API_KEY}}
          enableQueue: true

    - Bazarr:
        icon: bazarr.svg
        href: http://${server_ip}:6767
        description: Subtitle Management
        widget:
          type: bazarr
          url: http://bazarr:6767
          key: {{HOMEPAGE_VAR_BAZARR_API_KEY}}

    - Prowlarr:
        icon: prowlarr.svg
        href: http://${server_ip}:9696
        description: Indexer Management
        widget:
          type: prowlarr
          url: http://prowlarr:9696
          key: {{HOMEPAGE_VAR_PROWLARR_API_KEY}}

- Media Production:
    - ARM:
        icon: mdi-disc
        href: http://${server_ip}:8090
        description: Automatic Ripping Machine
        widget:
          type: customapi
          url: http://${server_ip}:8090/json?mode=joblist
          refreshInterval: 5000
          mappings:
            - field:
                results:
                  0:
                    title
              label: Current Disc
              format: text
            - field:
                results:
                  0:
                    year
              label: Year
              format: text
            - field:
                results:
                  0:
                    status
              label: Status
              format: text
            - field:
                results:
                  0:
                    progress
              label: Progress
              format: number
              suffix: "%"
            - field:
                results:
                  0:
                    disctype
              label: Type
              format: text

    - Tdarr:
        icon: tdarr.svg
        href: http://${server_ip}:8265
        description: Media Transcoding
        widget:
          type: tdarr
          url: http://tdarr:8265

- Downloads:
    - qBittorrent:
        icon: qbittorrent.svg
        href: http://${server_ip}:8080
        description: Torrent Client
        widget:
          type: qbittorrent
          url: http://qbittorrent:8080
          username: {{HOMEPAGE_VAR_QBIT_USER}}
          password: {{HOMEPAGE_VAR_QBIT_PASS}}

    - SABnzbd:
        icon: sabnzbd.svg
        href: http://${server_ip}:8081
        description: Usenet Client
        widget:
          type: sabnzbd
          url: http://sabnzbd:8080
          key: {{HOMEPAGE_VAR_SABNZBD_API_KEY}}

- System:
    - Portainer:
        icon: portainer.svg
        href: http://${server_ip}:9000
        description: Container Management

    - Cloudflare Tunnel:
        icon: cloudflare.svg
        href: https://one.dash.cloudflare.com/
        description: Secure Remote Access
EOF

    # Generate docker.yaml
    print_info "Generating docker.yaml..."
    cat > "$config_dir/docker.yaml" <<'EOF'
---
my-docker:
  socket: /var/run/docker.sock
EOF

    # Generate widgets.yaml
    print_info "Generating widgets.yaml..."
    cat > "$config_dir/widgets.yaml" <<'EOF'
---
- logo:
    icon: mdi-server

- search:
    provider: google
    target: _blank

- resources:
    cpu: true
    memory: true
    disk: /
    expanded: true

- datetime:
    text_size: xl
    format:
      dateStyle: long
      timeStyle: short
EOF

    # Generate bookmarks.yaml
    print_info "Generating bookmarks.yaml..."
    cat > "$config_dir/bookmarks.yaml" <<'EOF'
---
- Media:
    - Movies:
        - href: /media/movies
    - TV Shows:
        - href: /media/tv
    - Music:
        - href: /media/music

- Documentation:
    - Homepage Docs:
        - href: https://gethomepage.dev
    - ARM Wiki:
        - href: https://github.com/automatic-ripping-machine/automatic-ripping-machine/wiki
EOF

    # Set permissions
    print_info "Setting permissions..."
    chown -R "${PUID}:${PGID}" "$config_dir"

    report_log "success" "Homepage configuration files generated"

    # List generated files
    echo ""
    print_info "Generated files:"
    ls -lh "$config_dir"/*.yaml | awk '{print "  - " $9 " (" $5 ")"}'
    echo ""

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
}

main "$@"
