#!/bin/bash
#
# run-tests.sh - Run all medialab lib unit tests (tests/test-*.sh, excluding
# this runner and the shared harness). Exit non-zero if any test fails.
#
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0

for t in "$TESTS_DIR"/test-*.sh; do
    [[ "$(basename "$t")" == "test-helpers.sh" ]] && continue
    echo "== $(basename "$t") =="
    if bash "$t"; then :; else failed=1; fi
    echo ""
done

[[ "$failed" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$failed"
