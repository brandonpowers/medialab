#!/bin/bash
#
# Behavior tests for wait_for_api_key (scripts/lib/api.sh). get_api_key is the
# stubbed seam; the polling/retry logic under test is real. interval=0 keeps
# the tests fast.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/api.sh"

# --- Case 1: key available on first poll -> returned, rc 0, one call ---------
_calls=0
get_api_key() { _calls=$((_calls+1)); echo "abc123"; }
out=$(wait_for_api_key sonarr 5 0); rc=$?
assert_eq "abc123" "$out" "available key is returned"
assert_rc 0 $rc "available key returns success"

# --- Case 2: key appears after 2 empty polls -> returned once present --------
# Counter via tempfile: get_api_key runs in a command-substitution subshell, so
# in-memory mutations would not persist across polls.
c2=$(mktemp); echo 0 > "$c2"
get_api_key() {
    local n=$(( $(cat "$c2") + 1 )); echo "$n" > "$c2"
    [[ $n -ge 3 ]] && echo "late-key" || echo ""
}
out=$(wait_for_api_key sonarr 5 0); rc=$?
rm -f "$c2"
assert_eq "late-key" "$out" "key returned once it appears"
assert_rc 0 $rc "delayed key returns success"

# --- Case 3: key never appears -> empty, rc 1, bounded by max_attempts -------
# Count calls via a temp file (subshell in $(...) loses variable mutations).
counter=$(mktemp)
echo 0 > "$counter"
get_api_key() { echo $(( $(cat "$counter") + 1 )) > "$counter"; echo ""; }
out=$(wait_for_api_key sonarr 4 0); rc=$?
assert_eq "" "$out" "missing key yields empty"
assert_rc 1 $rc "missing key returns failure"
assert_eq "4" "$(cat "$counter")" "polled exactly max_attempts times"
rm -f "$counter"

finish_tests
