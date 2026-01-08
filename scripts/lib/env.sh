#!/bin/bash
#
# env.sh - Environment variable management
# Functions for reading, writing, and validating .env files
#

# Prevent multiple sourcing
[[ -n "${_MEDIALAB_ENV_LOADED:-}" ]] && return 0
_MEDIALAB_ENV_LOADED=1

# Source common.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================
# ENVIRONMENT FILE OPERATIONS
# ============================================

# Get a value from .env file
# Usage: get_env_value <key> [env_file]
get_env_value() {
    local key="$1"
    local env_file="${2:-$(get_project_root)/.env}"

    if [[ -f "$env_file" ]]; then
        local value
        value=$(grep "^${key}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | head -1 || true)
        # Strip surrounding quotes if present
        if [[ "$value" =~ ^\'.*\'$ ]]; then
            value="${value:1:-1}"
        elif [[ "$value" =~ ^\".*\"$ ]]; then
            value="${value:1:-1}"
        fi
        echo "$value"
    fi
}

# Set a value in .env file (only if not already set or if forced)
# Usage: set_env_value <key> <value> [force] [env_file]
set_env_value() {
    local key="$1"
    local value="$2"
    local force="${3:-false}"
    local env_file="${4:-$(get_project_root)/.env}"

    # Create .env with header if it doesn't exist
    if [[ ! -f "$env_file" ]]; then
        cat > "$env_file" << EOF
# ============================================
# MEDIALAB ENVIRONMENT CONFIGURATION
# Generated: $(date)
# ============================================

EOF
    fi

    # Quote values containing shell special characters
    # This prevents issues when .env is sourced
    local quoted_value="$value"
    if [[ "$value" =~ [[:space:]\(\)\$\"\'\`\\!\#\&\*\;\<\>\|\~] ]]; then
        # Escape single quotes in value, then wrap in single quotes
        quoted_value="'${value//\'/\'\\\'\'}'"
    fi

    # Check if key LINE exists (not just if it has a value)
    # This fixes duplicate entries when key exists with empty value
    if grep -q "^${key}=" "$env_file" 2>/dev/null; then
        # Key exists in file
        if [[ "$force" == "true" ]]; then
            # Force update - replace existing value (use different delimiter for sed)
            # Delete and re-add to handle complex quoting
            sed -i "/^${key}=/d" "$env_file"
            echo "${key}=${quoted_value}" >> "$env_file"
        fi
        # Key exists and not forcing, skip (not an error)
        return 0
    fi

    # Key doesn't exist, append it
    echo "${key}=${quoted_value}" >> "$env_file"
    return 0
}

# Update API key in .env (always updates to the authoritative value from container config)
# Usage: update_env_api_key <key_name> <key_value> [env_file]
update_env_api_key() {
    local key_name="$1"
    local key_value="$2"
    local env_file="${3:-$(get_project_root)/.env}"

    [[ -z "$key_value" ]] && return 1

    local existing_value
    existing_value=$(get_env_value "$key_name" "$env_file")

    # Skip if already set to same value
    [[ "$existing_value" == "$key_value" ]] && return 0

    # Update or add the key (always update since container config is authoritative)
    if grep -q "^${key_name}=" "$env_file" 2>/dev/null; then
        sed -i "s/^${key_name}=.*/${key_name}=${key_value}/" "$env_file"
    else
        echo "${key_name}=${key_value}" >> "$env_file"
    fi

    return 0
}

# Load environment from .env file
# Usage: load_env [env_file]
load_env() {
    local env_file="${1:-$(get_project_root)/.env}"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a

    return 0
}

# ============================================
# CREDENTIAL PROMPTING
# ============================================

# Prompt for credential if not in .env
# Usage: prompt_credential <var_name> <prompt_text> [is_secret]
# Returns: the credential value
prompt_credential() {
    local var_name="$1"
    local prompt_text="$2"
    local is_secret="${3:-false}"
    local env_file="${4:-$(get_project_root)/.env}"

    # Check if already set in .env
    local existing_value
    existing_value=$(get_env_value "$var_name" "$env_file")

    # Return existing value if set
    if [[ -n "$existing_value" ]]; then
        echo "$existing_value"
        return 0
    fi

    # Prompt user
    local value=""
    if [[ "$is_secret" == "true" ]]; then
        read -s -r -p "$prompt_text" value
        echo "" >&2  # Newline to stderr so it doesn't get captured
    else
        read -r -p "$prompt_text" value
    fi

    # Save to .env if provided
    if [[ -n "$value" ]]; then
        # Use single quotes to safely handle special characters
        echo "${var_name}='${value}'" >> "$env_file"
    fi

    echo "$value"
}

# ============================================
# VALIDATION
# ============================================

# Validate that required environment variables are set
# Usage: validate_required_env <var1> <var2> ...
validate_required_env() {
    local missing=()

    for var in "$@"; do
        local value
        value=$(get_env_value "$var")
        if [[ -z "$value" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            print_error "  - $var"
        done
        return 1
    fi

    return 0
}

# Check if .env file exists and has minimum required variables
# Usage: check_env_file [env_file]
check_env_file() {
    local env_file="${1:-$(get_project_root)/.env}"

    if [[ ! -f "$env_file" ]]; then
        print_error ".env file not found at $env_file"
        return 1
    fi

    # Check for critical variables
    local required=(TZ PUID PGID MEDIA_ROOT)
    local missing=()

    for var in "${required[@]}"; do
        local value
        value=$(get_env_value "$var" "$env_file")
        if [[ -z "$value" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warning "Missing critical environment variables:"
        for var in "${missing[@]}"; do
            print_warning "  - $var"
        done
        return 1
    fi

    return 0
}

# ============================================
# BACKUP AND RESTORE
# ============================================

# Create a backup of .env file
# Usage: backup_env [env_file]
# Returns: backup file path
backup_env() {
    local env_file="${1:-$(get_project_root)/.env}"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    local backup_file="${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$env_file" "$backup_file"
    echo "$backup_file"
}

# List all environment variables as JSON
# Usage: env_to_json [env_file]
env_to_json() {
    local env_file="${1:-$(get_project_root)/.env}"

    if [[ ! -f "$env_file" ]]; then
        echo "{}"
        return
    fi

    local json="{"
    local first=true

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue

        $first || json+=","
        first=false

        # Escape quotes in value
        value="${value//\"/\\\"}"
        json+="\"$key\":\"$value\""
    done < "$env_file"

    json+="}"
    echo "$json"
}
