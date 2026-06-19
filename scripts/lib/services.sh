#!/bin/bash
#
# services.sh - Single source of truth for the host-side service URLs the
# configure phase talks to. The scripts run on the Docker host and reach each
# service on its published localhost port, so these are http://localhost:<port>
# where <port> matches the published port in docker-compose.yml. Keeping them
# here means a published-port change is a one-line edit, not a hunt across 14
# configure modules.
#
# Each is overridable from the environment (e.g. if you republish a service on
# a different port) but defaults to the stack's standard port.
#

# Prevent multiple sourcing
[[ -n "${_MEDIALAB_SERVICES_LOADED:-}" ]] && return 0
_MEDIALAB_SERVICES_LOADED=1

: "${HOMEPAGE_URL:=http://localhost:3000}"
: "${JELLYSEERR_URL:=http://localhost:5055}"
: "${BAZARR_URL:=http://localhost:6767}"
: "${RADARR_URL:=http://localhost:7878}"
: "${QBITTORRENT_URL:=http://localhost:8080}"
: "${SABNZBD_URL:=http://localhost:8085}"
: "${ARM_URL:=http://localhost:8090}"
: "${JELLYFIN_URL:=http://localhost:8096}"
: "${TDARR_URL:=http://localhost:8265}"
: "${LIDARR_URL:=http://localhost:8686}"
: "${SONARR_URL:=http://localhost:8989}"
: "${PROWLARR_URL:=http://localhost:9696}"
