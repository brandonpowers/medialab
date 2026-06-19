#!/bin/bash
#
# Unit tests for missing_dependencies (scripts/lib/common.sh).
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/common.sh"

# A command that certainly exists (bash) yields nothing missing.
out=$(missing_dependencies bash)
assert_eq "" "$out" "present command reports nothing missing"

# A command that certainly does not exist is reported.
out=$(missing_dependencies definitely-not-a-real-command-xyz)
assert_eq "definitely-not-a-real-command-xyz" "$out" "absent command is reported"

# Mix: only the missing ones are listed, order preserved.
out=$(missing_dependencies bash definitely-not-a-real-command-xyz jq-not-real-zzz)
assert_eq "definitely-not-a-real-command-xyz jq-not-real-zzz" "$out" "only missing commands listed, in order"

# All present yields nothing.
out=$(missing_dependencies bash ls)
assert_eq "" "$out" "all-present yields empty"

finish_tests
