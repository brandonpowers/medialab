# Medialab Media Server

A complete, privacy-first media server stack running on Ubuntu Server 24.04 LTS. Features automated media management, streaming, secure remote access with a single-script deployment.

## Overview

**15 Docker services** providing:
- Media streaming and management (movies, TV, music)
- Privacy-first remote access (Cloudflare Tunnel - optional)
- Complete automation (*arr stack with TRaSH Guides integration)
- Dual download methods (Usenet + Torrents)
- Blu-ray/DVD ripping (ARM - Automatic Ripping Machine)
- Automated transcoding (Tdarr with GPU acceleration)

## Quick Start

### Prerequisites

1. **Hardware Requirements:**
   - Intel/AMD CPU with GPU (QuickSync/VAAPI for transcoding)
   - 16GB+ RAM
   - 100GB+ storage for system
   - Separate storage for media files
   - Blu-ray/DVD optical drive (optional, for ARM)

2. **Fresh Ubuntu Server 24.04 LTS Installation**
   - See **[Ubuntu Installation Guide](docs/ubuntu-installation.md)** for detailed steps
   - Set static IP (or use DHCP reservation)
   - Enable OpenSSH server during installation

### Automated Deployment

Deploy and configure your entire medialab with automated scripts:

```bash
# Clone repository
sudo git clone https://github.com/brandonpowers/medialab.git /opt/medialab
sudo chown -R $(whoami):$(whoami) /opt/medialab
cd /opt/medialab

# Step 1: Run automated setup
sudo ./scripts/medialab setup

# Step 2: Wait for services to start (2-3 minutes)
./scripts/medialab status

# Step 3: Run automated configuration
./scripts/medialab configure
```

Or run everything at once:

```bash
sudo ./scripts/medialab all
```

**Setup Phase** - Prepares infrastructure:
- Installs Docker and Docker Compose
- Detects GPU and optical drives
- Configures storage and media directories with correct ownership
- Generates `.env` with secure passwords
- Sets up ARM udev rules for disc detection
- Pulls Docker images and starts services

**Configure Phase** - Connects services via API:
- Extracts and links API keys
- Connects download clients to *arr apps
- Links Prowlarr to Sonarr/Radarr/Lidarr
- Configures Bazarr for subtitles
- Syncs TRaSH Guides via Recyclarr
- Sets up Tdarr transcoding libraries
- Configures ARM for disc ripping
- Pre-configures Homepage dashboard with all services

**Total time:** ~20-30 minutes (mostly downloading Docker images)

### Web UI Wizard

For a guided setup experience, use the web-based wizard:

```bash
./scripts/run-ui.sh
```

Then open http://localhost:8000 in your browser. The wizard walks you through:
1. Hardware detection (GPU, optical drives)
2. Storage selection
3. Configuration options
4. Automated installation with real-time progress

> **⚠️ The wizard is a setup-time-only tool.** It has read-write access to your
> `.env` and (in the container variant) the Docker socket. It binds to
> `127.0.0.1` and its endpoints enforce an Origin/Host check, but you should
> still **shut it down once setup is complete** — press `Ctrl+C` if you launched
> it with `run-ui.sh`, or run `docker compose -f docker-compose.web.yml down` if
> you started the container. Do not leave it running during normal operation or
> expose it beyond localhost.

For detailed information about automated configuration, see **[Automated Configuration Guide](docs/automated-configuration.md)**

## Service Documentation

### Media Services
- **[Media Streaming](docs/media-streaming.md)** - Jellyfin, Jellyseerr, Homepage dashboard

### Automation & Downloads
- **[Media Automation](docs/media-automation.md)** - Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Recyclarr
- **[Downloads](docs/downloads.md)** - qBittorrent, SABnzbd, Usenet setup

### Infrastructure
- **[Network & Remote Access](docs/networking.md)** - Cloudflare Tunnel setup and security
- **[Media Processing](docs/monitoring.md)** - Tdarr transcoding, ARM disc ripping

### Special Features
- **Automatic Blu-ray Ripping** - ARM automatically rips discs, Tdarr transcodes with GPU acceleration
- **[Future Enhancements](docs/future-enhancements.md)** - Optional additions

## Architecture

```
                  Internet / Users
                        |
                        |
                  Public Services
                (*.yourdomain.com)
                        |
                 +--------------+
                 | Cloudflare   |
                 |   (SSL/DDoS) |
                 +------+-------+
                        |
                        |   Outbound Tunnel
                        |   (No ports open)
                        |
                 +------+-------+
                 | Home Router  |
                 +------+-------+
                        |
  +---------------------+----------------------+
  |           Ubuntu Server 24.04 LTS         |
  |                                           |
  |  +-------------------------------------+  |
  |  |     Docker Compose Services         |  |
  |  |                                     |  |
  |  |  PUBLIC (via Cloudflare):           |  |
  |  |    Jellyfin, Jellyseerr, Homepage   |  |
  |  |                                     |  |
  |  |  PRIVATE (LAN only):                |  |
  |  |    *arr apps, Downloads, Tdarr, ARM |  |
  |  +-------------------------------------+  |
  +-------------------------------------------+
```

**Privacy-First Design:**
1. **Home IP never exposed** - Cloudflare Tunnel creates outbound connection only
2. **No ports opened** - Router firewall remains locked down
3. **Public services** - Routed through Cloudflare (DDoS protected, SSL at edge)
4. **Admin services** - Accessible via LAN only
5. **Local access** - All services available on home network via `SERVER_IP:PORT`

## Service Access

### Public Services (via Cloudflare Tunnel)
Accessible from anywhere with **home IP hidden**:

- **Dashboard** - https://home.yourdomain.com
- **Jellyfin** - https://jellyfin.yourdomain.com
- **Jellyseerr** - https://jellyseerr.yourdomain.com

### Private Admin Services (LAN only)
Access from your local network:

| Service | Port | URL |
|---------|------|-----|
| Sonarr | 8989 | http://SERVER_IP:8989 |
| Radarr | 7878 | http://SERVER_IP:7878 |
| Lidarr | 8686 | http://SERVER_IP:8686 |
| Prowlarr | 9696 | http://SERVER_IP:9696 |
| Bazarr | 6767 | http://SERVER_IP:6767 |
| qBittorrent | 8080 | http://SERVER_IP:8080 |
| SABnzbd | 8085 | http://SERVER_IP:8085 |
| Tdarr | 8265 | http://SERVER_IP:8265 |
| ARM | 8090 | http://SERVER_IP:8090 |

## Services

| Service | Purpose | Port |
|---------|---------|------|
| **Cloudflared** | Secure tunnel for public access | - |
| **Homepage** | Dashboard for all services | 3000 |
| **Jellyfin** | Media streaming server | 8096 |
| **Jellyseerr** | Media request management | 5055 |
| **Sonarr** | TV show automation | 8989 |
| **Radarr** | Movie automation | 7878 |
| **Lidarr** | Music automation | 8686 |
| **Prowlarr** | Indexer management | 9696 |
| **FlareSolverr** | Cloudflare bypass for indexers | 8191 |
| **Bazarr** | Subtitle automation | 6767 |
| **Recyclarr** | Quality profile sync | - |
| **qBittorrent** | Torrent download client | 8080 |
| **SABnzbd** | Usenet download client | 8085 |
| **Tdarr** | Automated transcoding | 8265 |
| **ARM** | Blu-ray/DVD ripping | 8090 |

## Maintenance

### Common Commands

```bash
# Update all services
docker compose pull
docker compose up -d
docker image prune -f

# View logs
docker compose logs -f
docker compose logs -f jellyfin

# Restart services
docker compose restart
docker compose restart jellyfin

# Check service status
docker compose ps

# Sync quality profiles (Recyclarr)
docker compose run --rm recyclarr sync
```

### Backups

Use the bundled helper to snapshot your service configs (`./data`), `.env`, and
the compose/recyclarr config. Your media library (under `MEDIA_ROOT`) is
intentionally excluded — it's far too large to tar.

```bash
# Create a snapshot now (writes to ./backups by default)
./scripts/utilities/backup.sh

# ...or to a specific destination (e.g. a separate drive)
./scripts/utilities/backup.sh /mnt/media/backups

# Restore a snapshot (stop the stack first: docker compose down)
./scripts/utilities/restore.sh ./backups/medialab-backup-YYYYmmdd-HHMMSS.tar.gz
```

Snapshots contain secrets and are written with mode `600`. They are gitignored.

### Updates

Use the bundled helper. It takes a configuration snapshot **before** pulling new
images (so a bad `:latest` image can be rolled back), recreates the containers,
and verifies service health afterward:

```bash
git pull                            # update the repo itself (optional)
./scripts/utilities/update.sh       # snapshot → pull → recreate → health check
```

Pass `--no-backup` to skip the pre-update snapshot (not recommended). If a
service is unhealthy after an update, restore the snapshot the script just took
with `./scripts/utilities/restore.sh <backup>`.

## Requirements

**Hardware:**
- CPU: 4+ cores (8+ recommended)
- RAM: 16GB minimum (24GB recommended)
- Storage: 100GB for services + your media storage
- GPU: Intel QuickSync or AMD VAAPI recommended for transcoding

**Software:**
- Ubuntu Server 24.04 LTS (recommended)
- Docker & Docker Compose (installed by setup script)

**Network:**
- Domain name (for Cloudflare Tunnel - optional)
- Cloudflare account (free tier - optional)

**Optional:**
- Usenet provider ($10-15/month for faster downloads)
- Usenet indexers ($12-20/year for better automation)

## Troubleshooting

### Service Issues
```bash
# Check all services are running
docker compose ps

# View specific service logs
docker compose logs servicename

# Restart a service
docker compose restart servicename
```

### Network Issues
```bash
# Check Cloudflare Tunnel
docker compose logs cloudflared
```

For detailed troubleshooting, see individual service documentation.

## Support & Community

- **r/selfhosted** - Reddit community for medialab enthusiasts
- **r/usenet** - Usenet-specific help and discussions
- **r/medialab** - General medialab hardware and software
- **TRaSH Guides** - https://trash-guides.info/ - Quality profile guides
- **Servarr Wiki** - https://wiki.servarr.com/ - Official *arr documentation
- **Awesome Self-Hosted** - https://github.com/awesome-selfhosted/awesome-selfhosted

## Stack Status

**Production-ready and optimized for video streaming!**

Built for the medialab community.
