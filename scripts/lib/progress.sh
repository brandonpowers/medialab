#!/bin/bash
#
# progress.sh - Dual-mode progress reporting (CLI and JSON)
# Enables real-time progress tracking for UI integration
#

# Prevent multiple sourcing
[[ -n "${_MEDIALAB_PROGRESS_LOADED:-}" ]] && return 0
_MEDIALAB_PROGRESS_LOADED=1

# Source common.sh for colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================
# CONFIGURATION
# ============================================

# Output mode: "cli" (default) or "json"
OUTPUT_MODE="${OUTPUT_MODE:-cli}"

# Progress file for SSE streaming (optional)
PROGRESS_FILE="${PROGRESS_FILE:-}"

# Current module name for context
CURRENT_MODULE="${CURRENT_MODULE:-}"

# ============================================
# PROGRESS REPORTING
# ============================================

# Report progress step
# Usage: report_progress <step> <total> <message> [status]
# Status: running (default), complete, error, skipped
report_progress() {
    local step="$1"
    local total="$2"
    local message="$3"
    local status="${4:-running}"
    local timestamp
    timestamp=$(date +%s)

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local json
        json=$(cat <<EOF
{"step":$step,"total":$total,"message":"$message","status":"$status","module":"${CURRENT_MODULE:-}","timestamp":$timestamp}
EOF
)
        echo "$json"

        # Also write to progress file for SSE polling
        if [[ -n "$PROGRESS_FILE" ]]; then
            echo "$json" >> "$PROGRESS_FILE"
        fi
    else
        # CLI mode - colored output
        local color=""
        local icon=""
        case "$status" in
            complete) color="$GREEN"; icon="✓" ;;
            error)    color="$RED"; icon="✗" ;;
            skipped)  color="$YELLOW"; icon="-" ;;
            *)        color="$BLUE"; icon="●" ;;
        esac

        echo -e "${color}[$step/$total]${NC} ${icon} $message"
    fi
}

# Report sub-progress (for docker pull, long operations)
# Usage: report_sub_progress <context> <percent> <detail>
report_sub_progress() {
    local context="$1"
    local percent="$2"
    local detail="${3:-}"
    local timestamp
    timestamp=$(date +%s)

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local json
        json=$(cat <<EOF
{"type":"sub_progress","context":"$context","percent":$percent,"detail":"$detail","timestamp":$timestamp}
EOF
)
        echo "$json"

        if [[ -n "$PROGRESS_FILE" ]]; then
            echo "$json" >> "$PROGRESS_FILE"
        fi
    else
        # CLI mode - overwrite line with progress bar
        local bar_width=30
        local filled=$((percent * bar_width / 100))
        local empty=$((bar_width - filled))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done

        printf "\r  ${CYAN}%s${NC} [%s] %3d%% %s" "$context" "$bar" "$percent" "$detail"

        # Newline when complete
        if [[ "$percent" -ge 100 ]]; then
            echo ""
        fi
    fi
}

# Report a log message (for detailed output during long operations)
# Usage: report_log <level> <message>
# Level: info, success, warning, error, debug
report_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +%s)

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        echo "{\"type\":\"log\",\"level\":\"$level\",\"message\":\"$message\",\"timestamp\":$timestamp}"

        if [[ -n "$PROGRESS_FILE" ]]; then
            echo "{\"type\":\"log\",\"level\":\"$level\",\"message\":\"$message\",\"timestamp\":$timestamp}" >> "$PROGRESS_FILE"
        fi
    else
        case "$level" in
            success) print_success "$message" ;;
            warning) print_warning "$message" ;;
            error)   print_error "$message" ;;
            debug)   [[ -n "${DEBUG:-}" ]] && echo -e "${CYAN}[debug]${NC} $message" ;;
            *)       print_info "$message" ;;
        esac
    fi
}

# Initialize progress tracking for a module
# Usage: init_progress <module_name> <total_steps>
init_progress() {
    local module_name="$1"
    local total_steps="$2"

    CURRENT_MODULE="$module_name"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local json
        json="{\"type\":\"init\",\"module\":\"$module_name\",\"total_steps\":$total_steps,\"timestamp\":$(date +%s)}"
        echo "$json"

        # Also write to progress file for SSE polling
        if [[ -n "$PROGRESS_FILE" ]]; then
            echo "$json" >> "$PROGRESS_FILE"
        fi
    else
        print_section "$module_name"
    fi
}

# Finalize progress tracking for a module
# Usage: finish_progress [status] [message]
finish_progress() {
    local status="${1:-complete}"
    local message="${2:-Module completed}"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local json
        json="{\"type\":\"finish\",\"module\":\"${CURRENT_MODULE:-}\",\"status\":\"$status\",\"message\":\"$message\",\"timestamp\":$(date +%s)}"
        echo "$json"

        # Also write to progress file for SSE polling
        if [[ -n "$PROGRESS_FILE" ]]; then
            echo "$json" >> "$PROGRESS_FILE"
        fi
    else
        if [[ "$status" == "complete" ]]; then
            print_success "$message"
        elif [[ "$status" == "error" ]]; then
            print_error "$message"
        else
            print_info "$message"
        fi
    fi

    CURRENT_MODULE=""
}

# ============================================
# PROGRESS FILE MANAGEMENT
# ============================================

# Create a new progress file for SSE streaming
# Returns the path to the progress file
create_progress_file() {
    local prefix="${1:-medialab}"
    PROGRESS_FILE="/tmp/${prefix}-progress-$$"
    touch "$PROGRESS_FILE"
    echo "$PROGRESS_FILE"
}

# Clean up progress file
cleanup_progress_file() {
    if [[ -n "$PROGRESS_FILE" && -f "$PROGRESS_FILE" ]]; then
        rm -f "$PROGRESS_FILE"
    fi
    PROGRESS_FILE=""
}
