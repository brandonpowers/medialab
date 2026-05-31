#!/bin/bash
#
# cgi-common.sh - Shared helpers for the Medialab setup-wizard CGI endpoints.
#
# This file is *sourced* by the .cgi scripts (it is not an endpoint itself and
# must not be marked executable, so the CGI server will not serve it).
#
# It provides:
#   - cgi_guard            CSRF / DNS-rebinding defense (Origin + Host check)
#   - wizard_register_pid  / wizard_pid_is_registered / wizard_unregister_pid
#                          a registry of PIDs the wizard itself spawned, so the
#                          status endpoint can only kill its own children
#   - wizard_is_valid_progress_file
#                          restrict the progress stream to wizard-owned files
#
# The wizard binds to 127.0.0.1 only, but localhost binding does NOT stop a
# malicious web page (CSRF) or a DNS-rebinding attack from reaching these
# endpoints through the user's browser. These helpers close that gap.

# Hosts the wizard legitimately answers to. Override via MEDIALAB_UI_ALLOWED_HOSTS
# (space- or comma-separated) if you change the bind address/port.
MEDIALAB_UI_ALLOWED_HOSTS="${MEDIALAB_UI_ALLOWED_HOSTS:-127.0.0.1:8000 localhost:8000}"

# Where the wizard records the PIDs of modules it has launched.
MEDIALAB_WIZARD_PID_DIR="${MEDIALAB_WIZARD_PID_DIR:-/tmp/medialab-wizard-pids}"

# Progress/output files created by run-module.cgi share this prefix.
MEDIALAB_PROGRESS_PREFIX="/tmp/medialab-progress-"

# Emit a 403 response (JSON) and stop. Safe to call before any other output.
_cgi_forbid() {
    local message="${1:-Forbidden}"
    echo "Status: 403 Forbidden"
    echo "Content-Type: application/json"
    echo ""
    echo "{\"status\": \"error\", \"message\": \"${message}\"}"
    exit 0
}

# Reject cross-origin requests and untrusted Host headers (DNS rebinding).
# Call this FIRST in every endpoint, before printing any headers.
cgi_guard() {
    local allowed="${MEDIALAB_UI_ALLOWED_HOSTS//,/ }"
    local host ok

    # Cross-origin requests carry an Origin header; same-origin GETs usually
    # do not. If present, it must match an allowed host.
    if [[ -n "${HTTP_ORIGIN:-}" ]]; then
        local origin_host="${HTTP_ORIGIN#*://}"   # strip scheme://
        ok=false
        for host in $allowed; do
            [[ "$origin_host" == "$host" ]] && { ok=true; break; }
        done
        $ok || _cgi_forbid "Cross-origin request blocked"
    fi

    # A DNS-rebinding attack reaches 127.0.0.1 but presents the attacker's
    # hostname in the Host header. Require a known-good Host.
    if [[ -n "${HTTP_HOST:-}" ]]; then
        ok=false
        for host in $allowed; do
            [[ "$HTTP_HOST" == "$host" ]] && { ok=true; break; }
        done
        $ok || _cgi_forbid "Untrusted Host header blocked"
    fi
}

# --- PID registry: only kill what the wizard started -----------------------

wizard_register_pid() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    mkdir -p "$MEDIALAB_WIZARD_PID_DIR" 2>/dev/null || return 1
    : > "$MEDIALAB_WIZARD_PID_DIR/$pid"
}

wizard_pid_is_registered() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ -f "$MEDIALAB_WIZARD_PID_DIR/$pid" ]]
}

wizard_unregister_pid() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    rm -f "$MEDIALAB_WIZARD_PID_DIR/$pid" 2>/dev/null || true
}

# --- Progress stream: only expose wizard-owned files -----------------------

# True only for files the wizard creates (no traversal, correct prefix).
wizard_is_valid_progress_file() {
    local f="$1"
    [[ -n "$f" ]] || return 1
    [[ "$f" == *".."* ]] && return 1
    [[ "$f" == "${MEDIALAB_PROGRESS_PREFIX}"* ]] || return 1
    return 0
}
