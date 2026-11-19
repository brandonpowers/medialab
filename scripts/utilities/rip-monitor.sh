#!/usr/bin/env bash
# Live fault-tolerance monitor for the ARM Blu-ray ripping pipeline.
#
# Emits ONE line per actionable event. Robust against:
#   * startup history replay (existing logs are primed to EOF, never replayed)
#   * concurrent/interleaved jobs (per-file byte offsets, not a single "newest")
#   * SCSI read-error floods (throttled: first hit, then every 25th, exact total
#     is captured by the terminal "Failed to save"/CRITICAL lines)
# Each stdout line is one event, so it works as a plain terminal tail or under a
# line-per-notification watcher such as Claude Code's Monitor tool.
#
# Usage:
#   ./scripts/utilities/rip-monitor.sh          # runs until interrupted
#
# Paths come from the install itself: ARM's logs under this repo's data dir, and
# MEDIA_ROOT / OPTICAL_DRIVE from .env. DISK_WARN_GB and SCSI_STEP can be
# overridden from the environment.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib/common.sh"
source "$REPO_ROOT/scripts/lib/env.sh"

LOGDIR="$REPO_ROOT/data/arm/home/logs"   # ./data/arm/home is mounted at /home/arm
MEDIA="$(get_env_value MEDIA_ROOT "$REPO_ROOT/.env")"
MEDIA="${MEDIA:-/mnt/media}"
DRIVE="$(get_env_value OPTICAL_DRIVE "$REPO_ROOT/.env")"
DRIVE="${DRIVE:-/dev/sr0}"
DISK_WARN_GB="${DISK_WARN_GB:-80}"
SCSI_STEP="${SCSI_STEP:-25}"

if [[ ! -d "$LOGDIR" ]]; then
    echo "[!] ARM log dir not found: $LOGDIR (is ARM installed and has it run once?)" >&2
    exit 1
fi

declare -A OFF      # per-file byte offset already reported
declare -A SCSI     # per-file cumulative SCSI/read-error count
declare -A SCSI_RPT # per-file last reported SCSI milestone
primed=0; disk_warned=0; drive_warned=0

SIGNAL='CRITICAL|ERROR|Ripping disc with MakeMKV|Could not fetch beta key|Keeping existing app_Key|Failed to save title|MakeMKV failed with code|titles? saved|Identified|completed successfully|Rip(ping)? with MakeMKV completed|Moving movie|Releasing current job|fatal'
NOISE='Scsi error|TRACK FOLLOWING|Handbrake call successful|findmnt'

while true; do
  # All job logs touched in the last ~3h (handles interleaved jobs), newest last.
  while IFS= read -r f; do
    [ -n "$f" ] && [ -s "$f" ] || continue
    base=$(basename "$f")
    sz=$(wc -c < "$f" 2>/dev/null || echo 0)

    if [ -z "${OFF[$f]+x}" ]; then
      if [ "$primed" -eq 0 ]; then
        OFF[$f]=$sz                       # startup: skip pre-existing history
      else
        OFF[$f]=0
        echo "[DISC] new job started: ${base%.log}"
      fi
      SCSI[$f]=0; SCSI_RPT[$f]=0
    fi

    if [ "$sz" -gt "${OFF[$f]}" ]; then
      chunk=$(tail -c +$(( ${OFF[$f]} + 1 )) "$f" 2>/dev/null); OFF[$f]=$sz

      n=$(printf '%s\n' "$chunk" | grep -ciE 'Scsi error|TRACK FOLLOWING')
      if [ "$n" -gt 0 ]; then
        SCSI[$f]=$(( ${SCSI[$f]} + n ))
        # Report on first error and then each SCSI_STEP crossing only.
        if [ "${SCSI_RPT[$f]}" -eq 0 ] || \
           [ $(( ${SCSI[$f]} / SCSI_STEP )) -gt $(( ${SCSI_RPT[$f]} / SCSI_STEP )) ]; then
          echo "[DRIVE] ${base%.log}: ${SCSI[$f]} disc read errors (SCSI/TRACK-FOLLOWING) — disc likely dirty/scratched"
          SCSI_RPT[$f]=${SCSI[$f]}
        fi
      fi

      printf '%s\n' "$chunk" \
        | grep -aE "$SIGNAL" | grep -avE "$NOISE" \
        | sed -E 's#^.*[0-9]{2}:[0-9]{2}:[0-9]{2} ##; s/ARM: //' \
        | while IFS= read -r line; do [ -n "$line" ] && echo "[ARM] ${base%.log}: $line"; done
    fi
  done < <(find "$LOGDIR" -maxdepth 1 -name '*.log' ! -name 'arm.log' -mmin -180 -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-)
  primed=1

  avail=$(df -BG --output=avail "$MEDIA" 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ -n "$avail" ] && [ "$avail" -lt "$DISK_WARN_GB" ] && [ "$disk_warned" -eq 0 ]; then
    echo "[DISK] $MEDIA low: ${avail}G free (<${DISK_WARN_GB}G)"; disk_warned=1
  fi

  if [ ! -e "$DRIVE" ]; then
    [ "$drive_warned" -eq 0 ] && echo "[DRIVE] $DRIVE MISSING — optical drive disappeared!"
    drive_warned=1
  else
    drive_warned=0
  fi

  sleep 3
done
