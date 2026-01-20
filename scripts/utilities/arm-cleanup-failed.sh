#!/bin/bash
#
# arm-cleanup-failed.sh - Clean up failed ARM jobs
#
# This script removes failed job entries from the ARM database,
# allowing discs to be re-ripped after a failure.
#
# Usage:
#   ./arm-cleanup-failed.sh           # Clean all failed jobs
#   ./arm-cleanup-failed.sh "HP4"     # Clean failed jobs matching title
#

TITLE_FILTER="${1:-}"

if [ -n "$TITLE_FILTER" ]; then
    echo "Cleaning failed ARM jobs matching: $TITLE_FILTER"
    QUERY="DELETE FROM job WHERE status = 'fail' AND title LIKE '%${TITLE_FILTER}%'"
else
    echo "Cleaning all failed ARM jobs..."
    QUERY="DELETE FROM job WHERE status = 'fail'"
fi

docker exec arm python3 -c "
import sqlite3
conn = sqlite3.connect('/home/arm/db/arm.db')
cur = conn.cursor()

# Count before
cur.execute(\"SELECT COUNT(*) FROM job WHERE status = 'fail'\")
before = cur.fetchone()[0]

# Delete
cur.execute(\"${QUERY}\")
deleted = cur.rowcount
conn.commit()

print(f'Deleted {deleted} failed job(s) (was {before} total failed)')
conn.close()
"

# Also clean up empty/partial directories in unidentified
echo ""
echo "Checking for empty directories in unidentified..."
find /mnt/media/unidentified -maxdepth 1 -type d -empty -print -delete 2>/dev/null || true

echo ""
echo "Done. You can now re-insert the disc."
