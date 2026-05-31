#!/bin/bash
#
# drives.cgi - Drive listing API endpoint
# Returns available storage drives as JSON
#

# Determine PROJECT_ROOT / SCRIPT_DIR (CGI may not inherit env vars)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$PROJECT_ROOT" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Shared CGI helpers (CSRF guard). Reject untrusted requests before any output.
source "$SCRIPT_DIR/cgi-common.sh"
cgi_guard

# Set content type
echo "Content-Type: application/json"
echo ""

# Source library
source "$PROJECT_ROOT/scripts/lib/init.sh"

# Get all drives (including system drives, marked appropriately)
drives_json=$(list_all_drives)

# Get recommended drive (only non-system drives)
recommended=$(detect_largest_storage_drive)

# Output JSON
cat << EOF
{
    "drives": $drives_json,
    "recommended": "$recommended",
    "status": "success"
}
EOF
