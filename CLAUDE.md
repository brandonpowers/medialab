# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Medialab is a **dynamic installer**, not a running application. It deploys a 15-service Docker Compose media-server stack (Jellyfin, the *arr apps, downloaders, Tdarr, ARM) onto a fresh Ubuntu Server 24.04 host. Almost all the code is Bash that auto-detects the host's hardware/network and configures the services via their HTTP APIs. There is no compiled artifact and no test suite.

**Core principle: auto-detect, never hardcode.** Host IPs, network/subnet, GPU device, optical drives, timezone, upstream DNS, and storage paths are all discovered at install time (`scripts/lib/detect.sh`) and written into `.env`. When adding features, follow this — derive values from the host instead of baking in assumptions. (Note: the host is still named `homelab`; the repo was rebranded but the hostname wasn't.)

## Commands

Everything routes through the CLI entry point `scripts/medialab` (the top-level `./medialab` is just a forwarder):

```bash
sudo ./scripts/medialab setup       # Phase 1: Docker, hardware detect, .env, dirs, pull, start
./scripts/medialab configure        # Phase 2: wire services together via their APIs
sudo ./scripts/medialab all         # setup + 30s wait + configure
./scripts/medialab status           # docker compose ps + LAN access hint
./scripts/medialab start            # launch the web setup wizard (= run-ui.sh)
```

Global flags: `--json` (machine-readable output for the web UI), `--config FILE` (feed a JSON config to modules, exported as `MEDIALAB_CONFIG`).

Web setup wizard (setup-time only — has RW access to `.env` and, in container form, the Docker socket; tear it down after install):

```bash
./scripts/run-ui.sh                                   # python3 -m http.server 8000 --cgi
docker compose -f docker-compose.web.yml up -d        # container variant
docker compose -f docker-compose.web.yml down         # stop it
```

Operations (utilities are standalone, not under the `medialab` CLI):

```bash
docker compose pull && docker compose up -d           # update images manually
docker compose logs -f <service>                      # logs
docker compose run --rm recyclarr sync                # sync TRaSH quality profiles
./scripts/utilities/update.sh                         # snapshot → pull → recreate → health-check
./scripts/utilities/backup.sh [dest]                  # snapshot ./data + .env + compose (NOT media)
./scripts/utilities/restore.sh <backup.tar.gz>        # restore (stop the stack first)
./scripts/utilities/health-check.sh
./scripts/utilities/validate-env.sh
sudo ./scripts/systemd/install-timers.sh              # install auto-update + cleanup timers
```

Unit tests for the pure lib helpers live in `tests/` (a self-contained bash harness, no deps beyond bash + jq):

```bash
bash tests/run-tests.sh        # run all tests/test-*.sh
```

There is no lint tooling. When changing Bash, validate with `bash -n <file>`, `shellcheck` if available, and add/extend a `tests/test-*.sh` for any new pure helper.

## Architecture

### Two-phase install

1. **setup** runs `scripts/modules/setup/*.sh` in a hardcoded numeric order (defined in `run_setup` in `scripts/medialab`). Prepares infra: prerequisites → detect hardware → select media drive → generate `.env` → create directories → generate Homepage config → ARM udev rules → pull images → start services. A module failure prompts to continue (interactive) or aborts (non-interactive/JSON).
2. **configure** runs `scripts/modules/configure/*.sh` sorted alphabetically (`00-jellyfin` … `13-homepage`). Connects the now-running services to each other through their REST APIs. Failures here are non-fatal — remaining modules still run, so the stack degrades gracefully rather than aborting.

Module ordering is positional: setup order is the explicit array in `run_setup`; configure order is filename sort. Renaming/numbering a module changes when it runs.

### Shared library (`scripts/lib/`)

Every module begins by sourcing `lib/init.sh`, which loads all libs (each guards against double-sourcing). Use these helpers rather than reimplementing:

- **common.sh** — colors + `print_*`, `get_project_root`, `require_root`, `generate_password`/`generate_hex`, `check_password_strength`, `missing_dependencies`/`ensure_dependencies` (apt-install required CLI tools; `01-prerequisites.sh` uses this to guarantee `jq`/`curl`/`openssl` regardless of whether Docker was pre-installed). Colors auto-disable when stdout isn't a TTY or `OUTPUT_MODE=json` (keeps JSON clean).
- **progress.sh** — `report_progress`/`report_log`. **Dual-mode**: human text when `OUTPUT_MODE=cli`, structured JSON (to stdout and/or `PROGRESS_FILE`) when `OUTPUT_MODE=json`. This is how the same modules drive both the CLI and the web wizard's live progress.
- **services.sh** — single source of truth for the host-side service URLs the configure phase talks to (`SONARR_URL`, `PROWLARR_URL`, …, each `http://localhost:<published-port>`, env-overridable). Use these instead of hardcoding `http://localhost:PORT`; a published-port change in `docker-compose.yml` is then a one-line edit here. `tests/test-services.sh` pins each to its compose port.
- **detect.sh** — hardware/network auto-detection (timezone, GPU, drives, DNS, subnet).
- **env.sh** — `.env` read/write: `get_env_value`, `set_env_value`, `load_env`, `update_env_api_key`.
- **api.sh** — service comms: `wait_for_service`, `wait_for_api_key <service>` (polls `get_api_key` until the service writes its config, replacing fixed `sleep N` readiness guesses), `api_get`/`api_post` (default `X-Api-Key` header), `json_first_id` (jq-based id extraction, replaces brittle `grep -oP '"id"'`), `resource_exists_by_name`/`ensure_resource` (idempotent create — GET the collection, skip if a resource with that `name` exists, POST only if absent, and report a real failure instead of masking it as "may already exist"; the configure modules use this for download clients, indexers, proxies, and quality profiles so re-runs are safe), and `get_api_key <service>` which **scrapes the key from each service's on-disk config** after first start (XML `<ApiKey>` for *arr apps, YAML for Bazarr, INI for SABnzbd, under `data/<service>/config/`). The configure phase extracts these keys, writes them back to `.env`, and uses them to wire services together.
- **docker.sh** — Docker/Compose checks and image-pull progress.

A configure module's typical shape: source `init.sh` → `report_progress` → `load_env` → `get_api_key` for its service → `update_env_api_key` → API calls to register download clients/indexers/profiles.

### Compose layout

- **docker-compose.yml** — the 15 services. Heavy use of YAML anchors at the top: `x-common-env` (`PUID`/`PGID`/`TZ`), `x-common-vol` (`MEDIA_ROOT`), `x-logging`, `x-dns`/`x-dns-opt` (pins upstream to `DOCKER_DNS` to avoid in-container resolver `EAI_AGAIN`/503s), `x-security` (`no-new-privileges`, `cap_drop: ALL` + a minimal `cap_add`). Resource caps on heavy services (tdarr, arm, flaresolverr, qbittorrent, sabnzbd).
- **docker-compose.override.yml** — auto-generated; uses Compose **profiles** to disable optional services (e.g. `cloudflared` only starts with the `cloudflare` profile). Don't hand-edit; it's regenerated by setup.
- **docker-compose.web.yml** — the setup wizard container.
- **.env** is generated by setup from `.env.example`; secrets (`600`). Services split into **public** (Jellyfin, Jellyseerr, Homepage — exposed via optional Cloudflare Tunnel, home IP never exposed) and **private/LAN-only** (everything else).

### Web wizard (`web/`)

Static `index.html` + `js/app.js` frontend; backend is **CGI scripts** (`web/cgi-bin/*.cgi`) served by Python's `http.server --cgi`. The CGI endpoints reuse the same `scripts/modules/*` and `scripts/lib/*` (via `OUTPUT_MODE=json` + `PROGRESS_FILE`), so the wizard and the CLI run identical install logic.

Security model lives in `web/cgi-bin/cgi-common.sh` and matters when touching CGI:
- `cgi_guard` — call **first** in every endpoint, before emitting headers. Enforces an Origin + Host allowlist (`MEDIALAB_UI_ALLOWED_HOSTS`) against CSRF / DNS-rebinding, since binding to 127.0.0.1 alone doesn't stop browser-driven attacks.
- `run-module.cgi` validates the requested module against **actual files on disk** (self-maintaining allowlist; rejects traversal) and parses only `phase`/`module` query params with strict char classes — never assigns arbitrary query keys to shell vars.
- PID registry (`wizard_register_pid` etc.) ensures the status endpoint can only kill processes the wizard itself spawned; the progress stream only exposes wizard-owned `/tmp/medialab-progress-*` files.

### systemd timers (`scripts/systemd/`)

`install-timers.sh` installs `medialab-update` (runs `utilities/update.sh`) and `medialab-cleanup` (runs `utilities/cleanup.sh`) timers for unattended maintenance.

## Docs

Service-specific operational docs live in `docs/` (media-streaming, media-automation, downloads, networking, monitoring, automated-configuration, ubuntu-installation, future-enhancements). README.md has the user-facing install/maintenance overview.
