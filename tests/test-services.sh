#!/bin/bash
#
# Unit tests for the central service URL map (scripts/lib/services.sh). These
# pin each URL to the published port in docker-compose.yml so an accidental
# drift between the two is caught here.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/test-helpers.sh"
source "$DIR/../scripts/lib/services.sh"

assert_eq "http://localhost:3000" "$HOMEPAGE_URL"    "homepage url"
assert_eq "http://localhost:5055" "$JELLYSEERR_URL"  "jellyseerr url"
assert_eq "http://localhost:6767" "$BAZARR_URL"      "bazarr url"
assert_eq "http://localhost:7878" "$RADARR_URL"      "radarr url"
assert_eq "http://localhost:8080" "$QBITTORRENT_URL" "qbittorrent url"
assert_eq "http://localhost:8085" "$SABNZBD_URL"     "sabnzbd url"
assert_eq "http://localhost:8090" "$ARM_URL"         "arm url"
assert_eq "http://localhost:8096" "$JELLYFIN_URL"    "jellyfin url"
assert_eq "http://localhost:8265" "$TDARR_URL"       "tdarr url"
assert_eq "http://localhost:8686" "$LIDARR_URL"      "lidarr url"
assert_eq "http://localhost:8989" "$SONARR_URL"      "sonarr url"
assert_eq "http://localhost:9696" "$PROWLARR_URL"    "prowlarr url"

# Override from the environment must win (republish-on-different-port case).
( SONARR_URL="http://localhost:9999"
  unset _MEDIALAB_SERVICES_LOADED
  source "$DIR/../scripts/lib/services.sh"
  assert_eq "http://localhost:9999" "$SONARR_URL" "env override wins" )

finish_tests
