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

    # Wait for qBittorrent to be fully ready (it may still be starting)
    report_log "info" "Waiting for qBittorrent to be ready..."
    local max_wait=30
    local waited=0
    while ! curl -s -m 2 "http://localhost:8080/api/v2/app/version" > /dev/null 2>&1; do
        sleep 2
        waited=$((waited + 2))
        if [[ $waited -ge $max_wait ]]; then
            report_log "warning" "qBittorrent not responding - skipping auto-configuration"
            report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
            finish_progress "complete" "$MODULE_NAME"
            return 0
        fi
    done
    report_log "success" "qBittorrent is ready"

    # Get credentials from environment
    local qbit_user="${QBIT_USER:-admin}"
    local qbit_pass="${QBIT_PASS:-}"
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"
    local cookie_file=""

    # Try stored qBittorrent credentials first
    if [[ -n "$qbit_pass" ]]; then
        report_log "info" "Trying stored qBittorrent credentials..."
        cookie_file=$(qbittorrent_login "$qbit_user" "$qbit_pass")
    fi

    # Try admin credentials (qBittorrent may have been configured to use these)
    if [[ -z "$cookie_file" && -n "$admin_pass" ]]; then
        report_log "info" "Trying admin credentials..."
        cookie_file=$(qbittorrent_login "$admin_user" "$admin_pass")
        if [[ -n "$cookie_file" ]]; then
            qbit_user="$admin_user"
            qbit_pass="$admin_pass"
        fi
    fi

    # Try temporary password from logs (for fresh installs)
    if [[ -z "$cookie_file" ]]; then
        report_log "info" "Checking for temporary password in logs..."
        local temp_pass
        temp_pass=$(docker compose logs qbittorrent 2>/dev/null | grep -oP 'temporary password is provided for this session: \K\S+' | tail -1 || true)

        if [[ -n "$temp_pass" ]]; then
            report_log "info" "Found temporary password, attempting login..."
            cookie_file=$(qbittorrent_login "admin" "$temp_pass")
            if [[ -n "$cookie_file" ]]; then
                qbit_user="admin"
                qbit_pass="$temp_pass"
            fi
        fi
    fi

    # If all login attempts failed, reset the password
    if [[ -z "$cookie_file" ]]; then
        report_log "info" "All login attempts failed - resetting qBittorrent password..."

        local config_file
        config_file="$(get_project_root)/data/qbittorrent/config/qBittorrent/qBittorrent.conf"

        if [[ -f "$config_file" ]]; then
            # Stop qBittorrent
            docker compose stop qbittorrent > /dev/null 2>&1 || true

            # Remove password line from config (forces temp password generation)
            sed -i '/WebUI\\Password_PBKDF2/d' "$config_file"

            # Also set the username to admin user
            if grep -q "WebUI\\\\Username=" "$config_file"; then
                sed -i "s/WebUI\\\\Username=.*/WebUI\\\\Username=$admin_user/" "$config_file"
            fi

            # Restart qBittorrent
            docker compose up -d qbittorrent > /dev/null 2>&1 || true
            sleep 5

            # Get new temp password
            local temp_pass
            temp_pass=$(docker compose logs qbittorrent 2>/dev/null | grep -oP 'temporary password is provided for this session: \K\S+' | tail -1 || true)

            if [[ -n "$temp_pass" ]]; then
                report_log "info" "Got new temporary password, logging in..."
                cookie_file=$(qbittorrent_login "$admin_user" "$temp_pass")
                if [[ -n "$cookie_file" ]]; then
                    qbit_user="$admin_user"
                    qbit_pass="$temp_pass"
                    report_log "success" "Password reset successful"
                fi
            fi
        fi
    fi

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

        # Save to .env for persistence (so future runs can use these)
        local project_root
        project_root=$(get_project_root)
        set_env_value "QBIT_USER" "$qbit_user" "true" "$project_root/.env"
        set_env_value "QBIT_PASS" "$qbit_pass" "true" "$project_root/.env"
        report_log "success" "Credentials saved to .env"
    else
        report_log "warning" "Could not login to qBittorrent"
        report_log "info" "Configure manually at http://localhost:8080"
        report_log "info" "Check logs: docker compose logs qbittorrent | grep password"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
