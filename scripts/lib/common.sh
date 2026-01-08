#!/bin/bash
#
# common.sh - Shared utility functions for medialab scripts
# This is the single source of truth for colors and print functions
#

# Prevent multiple sourcing
[[ -n "${_MEDIALAB_COMMON_LOADED:-}" ]] && return 0
_MEDIALAB_COMMON_LOADED=1

# ============================================
# COLORS
# ============================================

# Only set colors if stdout is a terminal (allows clean JSON output)
if [[ -t 1 ]] && [[ "${OUTPUT_MODE:-cli}" != "json" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# ============================================
# PRINT FUNCTIONS
# ============================================

# Print a section header
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  MEDIALAB - $1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Print a section divider with title
print_section() {
    echo ""
    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}----------------------------------------${NC}"
    echo ""
}

# Print info message
print_info() {
    echo -e "${BLUE}i${NC} $1"
}

# Print success message
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print warning message
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Print error message
print_error() {
    echo -e "${RED}✗${NC} $1"
}

# ============================================
# SCRIPT UTILITIES
# ============================================

# Get the project root directory (parent of scripts/)
get_project_root() {
    local script_dir
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        script_dir="$(pwd)"
    fi

    # Navigate up from scripts/lib to project root
    if [[ "$script_dir" == */scripts/lib ]]; then
        echo "$(cd "$script_dir/../.." && pwd)"
    elif [[ "$script_dir" == */scripts ]]; then
        echo "$(cd "$script_dir/.." && pwd)"
    else
        # Fallback: look for docker-compose.yml
        local dir="$script_dir"
        while [[ "$dir" != "/" ]]; do
            if [[ -f "$dir/docker-compose.yml" ]]; then
                echo "$dir"
                return 0
            fi
            dir="$(dirname "$dir")"
        done
        echo "$script_dir"
    fi
}

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (sudo)"
        exit 1
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Generate a random password
generate_password() {
    openssl rand -base64 32
}

# Generate a random hex string
generate_hex() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}
