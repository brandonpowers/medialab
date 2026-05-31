#!/bin/bash
#
# progress.cgi - Server-Sent Events progress stream
# Streams progress from a progress file to the client
#
# Query parameters:
#   file=/tmp/medialab-progress-12345
#

# Shared CGI helpers (CSRF guard, progress-file validation). Reject untrusted
# requests BEFORE emitting any headers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cgi-common.sh"
cgi_guard

# Set SSE content type
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# Extract only the `file` parameter, with a strict character class. We do NOT
# assign arbitrary query-string keys to shell variables.
progress_file=""
if [[ -n "${QUERY_STRING:-}" ]]; then
    progress_file=$(echo "$QUERY_STRING" | grep -oP '(^|&)file=\K[A-Za-z0-9._/-]+' | head -n1 || true)
fi

# Only stream wizard-owned progress files. This blocks reading arbitrary files
# (e.g. the mounted .env) via a crafted `file=` parameter.
if ! wizard_is_valid_progress_file "$progress_file" || [[ ! -f "$progress_file" ]]; then
    echo "event: error"
    echo "data: {\"error\": \"Progress file not found\"}"
    echo ""
    exit 0
fi

# Track position in file
position=0

# Stream progress updates
while true; do
    # Read new lines from progress file
    has_finish=false
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            echo "data: $line"
            echo ""
            # Check if this line is the finish message
            if [[ "$line" == *'"type":"finish"'* ]]; then
                has_finish=true
            fi
        fi
    done < <(tail -c +$((position + 1)) "$progress_file" 2>/dev/null)

    # Update position
    if [[ -f "$progress_file" ]]; then
        new_size=$(stat -c%s "$progress_file" 2>/dev/null || echo "$position")
        position=$new_size
    fi

    # Check if we just sent the finish message
    if [[ "$has_finish" == "true" ]]; then
        echo "event: done"
        echo "data: {\"status\": \"complete\"}"
        echo ""
        break
    fi

    # Also check file for finish message (in case we started after it was written)
    if grep -q '"type":"finish"' "$progress_file" 2>/dev/null; then
        # Make sure we've sent everything
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                echo "data: $line"
                echo ""
            fi
        done < <(tail -c +$((position + 1)) "$progress_file" 2>/dev/null)

        echo "event: done"
        echo "data: {\"status\": \"complete\"}"
        echo ""
        break
    fi

    # Send keepalive
    echo ": keepalive"
    echo ""

    sleep 0.5
done
