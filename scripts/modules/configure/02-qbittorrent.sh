#!/bin/bash
#
# 02-qbittorrent.sh - Configure qBittorrent download client
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure qBittorrent"
MODULE_STEP=2
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"

    # Load environment
    load_env

    print_section "Configuring qBittorrent"

    # Get temporary password from logs
    local temp_pass
    temp_pass=$(docker compose logs qbittorrent 2>/dev/null | grep -oP 'temporary password is provided for this session: \K\S+' | tail -1 || true)

    # Get credentials from environment or use defaults
    local qbit_user="${QBIT_USER:-admin}"
    local qbit_pass="${QBIT_PASS:-$temp_pass}"

    if [[ -z "$qbit_pass" ]]; then
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            report_log "warning" "No qBittorrent password available"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            return 0
        fi

        print_info "Default qBittorrent credentials:"
        print_info "  Username: admin"
        if [[ -n "$temp_pass" ]]; then
            print_info "  Temporary Password: ${temp_pass}"
        else
            print_info "  Password: (check logs or use your custom password)"
        fi
        echo ""

        read -p "qBittorrent username [admin]: " input_user
        qbit_user=${input_user:-admin}

        read -s -p "qBittorrent password: " qbit_pass
        echo ""
    fi

    if [[ -z "$qbit_pass" ]]; then
        report_log "warning" "No password provided - skipping qBittorrent configuration"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    print_info "Logging into qBittorrent..."

    local cookie_file
    cookie_file=$(qbittorrent_login "$qbit_user" "$qbit_pass")

    if [[ -n "$cookie_file" ]]; then
        report_log "success" "Logged into qBittorrent"

        # Change credentials to admin username/password
        local admin_user="${ADMIN_USERNAME:-admin}"
        local admin_pass="${ADMIN_PASSWORD:-}"
        if [[ -n "$admin_pass" && ( "$qbit_pass" != "$admin_pass" || "$qbit_user" != "$admin_user" ) ]]; then
            print_info "Setting qBittorrent credentials to admin account..."
            # URL encode for JSON
            local escaped_user escaped_pass
            escaped_user=$(printf '%s' "$admin_user" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
            escaped_pass=$(printf '%s' "$admin_pass" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

            if qbittorrent_api "$cookie_file" "app/setPreferences" \
                "json={\"web_ui_username\":${escaped_user},\"web_ui_password\":${escaped_pass}}" \
                > /dev/null 2>&1; then
                report_log "success" "Credentials changed to admin account"
                qbit_user="$admin_user"
                qbit_pass="$admin_pass"

                # Re-login with new credentials
                rm -f "$cookie_file"
                cookie_file=$(qbittorrent_login "$qbit_user" "$qbit_pass")
                if [[ -z "$cookie_file" ]]; then
                    report_log "warning" "Could not re-login after credential change"
                fi
            else
                report_log "warning" "Failed to change credentials"
            fi
        fi

        # Configure download paths
        print_info "Configuring download paths..."
        qbittorrent_api "$cookie_file" "app/setPreferences" \
            'json={"save_path":"/downloads/complete","temp_path_enabled":true,"temp_path":"/downloads/incomplete"}' \
            > /dev/null 2>&1 && report_log "success" "Download paths configured" || report_log "warning" "Failed to configure download paths"

        # Create category directories for *arr apps
        print_info "Creating download categories..."
        for category in tv movies music; do
            qbittorrent_api "$cookie_file" "torrents/createCategory" \
                "category=${category}&savePath=/downloads/complete/${category}" \
                > /dev/null 2>&1
        done
        report_log "success" "Categories created (tv, movies, music)"

        rm -f "$cookie_file"

        # Export credentials for other modules
        export QBIT_USER="$qbit_user"
        export QBIT_PASS="$qbit_pass"

        # Save to .env for persistence
        set_env_value "QBIT_USER" "$qbit_user"
    else
        report_log "warning" "Could not login to qBittorrent - check credentials and configure manually"
        print_info "Configure at: http://localhost:8080"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
