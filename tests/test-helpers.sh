#!/bin/bash
#
# test-helpers.sh - Minimal assertion harness for medialab lib unit tests.
# No external deps beyond bash + the libs under test. Each test file sources
# this, calls assert_* helpers, and ends with `finish_tests`.
#

_TESTS_RUN=0
_TESTS_FAILED=0

# assert_eq <expected> <actual> <message>
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    ((++_TESTS_RUN))
    if [[ "$expected" == "$actual" ]]; then
        echo "  ok   - $msg"
    else
        ((++_TESTS_FAILED))
        echo "  FAIL - $msg"
        echo "         expected: [$expected]"
        echo "         actual:   [$actual]"
    fi
}

# assert_rc <expected_rc> <actual_rc> <message>
assert_rc() {
    local expected="$1" actual="$2" msg="$3"
    ((++_TESTS_RUN))
    if [[ "$expected" -eq "$actual" ]]; then
        echo "  ok   - $msg"
    else
        ((++_TESTS_FAILED))
        echo "  FAIL - $msg (expected rc=$expected, got rc=$actual)"
    fi
}

finish_tests() {
    echo ""
    echo "  $_TESTS_RUN run, $_TESTS_FAILED failed"
    [[ "$_TESTS_FAILED" -eq 0 ]]
}
