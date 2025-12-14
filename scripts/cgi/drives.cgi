#!/bin/bash
#
# drives.cgi - Drive listing API endpoint
# Returns available storage drives as JSON
#

# Set content type
echo "Content-Type: application/json"
echo ""

# Get script directory (resolve symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# Source library
source "$SCRIPT_DIR/../lib/init.sh"

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
