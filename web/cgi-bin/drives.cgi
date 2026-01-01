#!/bin/bash
#
# drives.cgi - Drive listing API endpoint
# Returns available storage drives as JSON
#

# Set content type
echo "Content-Type: application/json"
echo ""

# Determine PROJECT_ROOT if not set (CGI may not inherit env vars)
if [[ -z "$PROJECT_ROOT" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

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
