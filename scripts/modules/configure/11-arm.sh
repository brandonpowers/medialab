#!/bin/bash
#
# 11-arm.sh - Configure ARM (Automatic Ripping Machine)
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure ARM"
MODULE_STEP=11
MODULE_TOTAL=12

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring ARM (Automatic Ripping Machine)"

    local project_root
    project_root=$(get_project_root)
    local arm_config="${project_root}/data/arm/config/arm.yaml"

    if [[ ! -f "$arm_config" ]]; then
        report_log "warning" "ARM config not found at $arm_config"
        print_info "ARM will be configured on first run"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    print_info "Updating ARM configuration..."

    # Fix COMPLETED_PATH to output directly to movies folder
    if grep -q 'COMPLETED_PATH: "/home/arm/media/completed/"' "$arm_config"; then
        sed -i 's|COMPLETED_PATH: "/home/arm/media/completed/"|COMPLETED_PATH: "/home/arm/movies/"|' "$arm_config"
        report_log "success" "COMPLETED_PATH updated to /home/arm/movies/"
    fi

    # Add TMDB API key if available
    if [[ -n "${TMDB_API_KEY:-}" ]]; then
        if grep -q 'TMDB_API_KEY: ""' "$arm_config"; then
            sed -i "s|TMDB_API_KEY: \"\"|TMDB_API_KEY: \"${TMDB_API_KEY}\"|" "$arm_config"
            report_log "success" "TMDB_API_KEY added to ARM config"
        fi

        # Switch to TMDB as metadata provider
        if grep -q 'METADATA_PROVIDER: "omdb"' "$arm_config"; then
            sed -i 's|METADATA_PROVIDER: "omdb"|METADATA_PROVIDER: "tmdb"|' "$arm_config"
            report_log "success" "Switched metadata provider to TMDB"
        fi
    else
        report_log "warning" "No TMDB_API_KEY in .env - ARM may have trouble identifying discs"
        print_info "Get a free API key at: https://www.themoviedb.org/settings/api"
    fi

    # Skip transcoding (let Tdarr handle it)
    if grep -q 'SKIP_TRANSCODE: false' "$arm_config"; then
        sed -i 's|SKIP_TRANSCODE: false|SKIP_TRANSCODE: true|' "$arm_config"
        report_log "success" "SKIP_TRANSCODE enabled (Tdarr will handle transcoding)"
    fi

    # Keep raw files on failure
    if grep -q 'DELRAWFILES: true' "$arm_config"; then
        sed -i 's|DELRAWFILES: true|DELRAWFILES: false|' "$arm_config"
        report_log "success" "DELRAWFILES disabled (preserves files on failure)"
    fi

    # Add MakeMKV retry arguments
    if grep -q 'MKV_ARGS: ""' "$arm_config"; then
        sed -i 's|MKV_ARGS: ""|MKV_ARGS: "--minlength=600 -r --directio=false --noscan"|' "$arm_config"
        report_log "success" "MKV_ARGS set for protected disc handling"
    fi

    # Configure rip method for Blu-rays
    if grep -q 'RIPMETHOD_BR: "mkv"' "$arm_config" || grep -q 'RIPMETHOD_BR: "PLACEHOLDER"' "$arm_config"; then
        sed -i 's|RIPMETHOD_BR: "mkv"|RIPMETHOD_BR: "backup"|' "$arm_config"
        sed -i 's|RIPMETHOD_BR: "PLACEHOLDER"|RIPMETHOD_BR: "backup"|' "$arm_config"
        report_log "success" "RIPMETHOD_BR set to backup (better for protected Blu-rays)"
    fi

    # Configure ARM web UI authentication
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_pass="${ADMIN_PASSWORD:-}"

    if [[ -n "$admin_pass" ]] && docker ps --format '{{.Names}}' | grep -q "^arm$"; then
        print_info "Configuring ARM web authentication..."

        # Wait for ARM database to be created (ARM initializes it on first run)
        local db_wait=0
        while ! docker exec arm test -f /home/arm/db/arm.db 2>/dev/null; do
            sleep 2
            db_wait=$((db_wait + 2))
            if [[ $db_wait -ge 30 ]]; then
                report_log "warning" "ARM database not found - ARM may need manual configuration"
                break
            fi
        done

        if docker exec arm test -f /home/arm/db/arm.db 2>/dev/null; then
            # ARM only supports ONE admin user (always uses User.query.first())
            # Must update user_id=1 and store hash as BYTES via Flask-SQLAlchemy
            docker exec arm python3 -c "
import sys
sys.path.insert(0, '/opt/arm')
import bcrypt

from arm.ui import db, app
from arm.models.user import User

username = '${admin_user}'
password = '${admin_pass}'

with app.app_context():
    # ARM only supports one admin - always update the first user
    admin = User.query.first()
    if admin:
        # Generate bcrypt hash (stored as bytes by SQLAlchemy)
        new_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt(12))
        admin.email = username
        admin.password = new_hash
        admin.hash = new_hash
        db.session.commit()
        print(f'Updated admin user: {username}')
    else:
        print('No admin user found - ARM may need manual setup', file=sys.stderr)
        sys.exit(1)
" 2>&1 && report_log "success" "ARM authentication configured for user: $admin_user" || report_log "warning" "Could not configure ARM authentication"
        fi
    fi

    # Configure MakeMKV settings inside container
    print_info "Configuring MakeMKV settings inside ARM container..."

    if docker ps --format '{{.Names}}' | grep -q "^arm$"; then
        docker exec arm mkdir -p /home/arm/.MakeMKV 2>/dev/null || true

        local existing_settings
        existing_settings=$(docker exec arm cat /home/arm/.MakeMKV/settings.conf 2>/dev/null || echo "")

        if ! echo "$existing_settings" | grep -q "io_ErrorRetryCount = \"20\""; then
            local app_key
            app_key=$(echo "$existing_settings" | grep "^app_Key" || echo "")

            docker exec arm bash -c "cat > /home/arm/.MakeMKV/settings.conf << 'MKVSETTINGS'
${app_key}
io_ErrorRetryCount = \"20\"
io_RBufSizeMB = \"128\"
MKVSETTINGS"
            report_log "success" "MakeMKV settings optimized (retry=20, buffer=128MB)"
        else
            print_info "MakeMKV settings already optimized"
        fi

        # Restart ARM to apply changes
        print_info "Restarting ARM container..."
        docker restart arm > /dev/null 2>&1 && report_log "success" "ARM restarted" || report_log "warning" "Failed to restart ARM"
    else
        report_log "warning" "ARM container not running"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
