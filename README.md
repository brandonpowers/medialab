# Homelab Media Server

A complete, privacy-first media server stack running on Ubuntu Server 24.04 LTS. Features automated media management, streaming, secure remote access with a single-script deployment.

## Overview

**16 Docker services** providing:
- Media streaming and management (movies, TV, music)
- Privacy-first remote access (Cloudflare Tunnel)
- Complete automation (*arr stack with TRaSH Guides integration)
- Dual download methods (Usenet + Torrents)
- Automated transcoding (Tdarr with GPU acceleration)
- Blu-ray/DVD ripping (ARM - Automatic Ripping Machine)
- Service monitoring and management

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

Deploy and configure your entire homelab with automated scripts:

```bash
# Clone repository
sudo git clone https://github.com/brandonpowers/homelab.git /opt/homelab
sudo chown -R $(whoami):$(whoami) /opt/homelab
cd /opt/homelab

# Step 1: Run automated setup
sudo ./scripts/homelab setup

# Step 2: Wait for services to start (2-3 minutes)
./scripts/homelab status

# Step 3: Run automated configuration
./scripts/homelab configure
```

Or run everything at once:

```bash
sudo ./scripts/homelab all
```

**Setup Phase** - Prepares infrastructure:
- Installs Docker and Docker Compose
- Detects GPU and optical drives
- Configures storage and media directories
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
- Adds all services to Homarr dashboard

**Total time:** ~20-30 minutes (mostly downloading Docker images)

### Web UI Wizard

For a guided setup experience, use the web-based wizard:

```bash
./scripts/serve-ui.sh
```

Then open http://localhost:8000 in your browser. The wizard walks you through:
1. Hardware detection (GPU, optical drives)
2. Storage selection
3. Configuration options
4. Automated installation with real-time progress

For detailed information about automated configuration, see **[Automated Configuration Guide](docs/automated-configuration.md)**

## Service Documentation

### Media Services
- **[Media Streaming](docs/media-streaming.md)** - Jellyfin, Jellyseerr, Homarr

### Automation & Downloads
- **[Media Automation](docs/media-automation.md)** - Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Recyclarr
- **[Downloads](docs/downloads.md)** - qBittorrent, SABnzbd, Usenet setup

### Infrastructure
- **[Network & Remote Access](docs/networking.md)** - Cloudflare Tunnel setup and security
- **[Monitoring & Management](docs/monitoring.md)** - Uptime Kuma, Tdarr, ARM

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
  |  |    Jellyfin, Jellyseerr, Homarr     |  |
  |  |                                     |  |
  |  |  PRIVATE (LAN only):                |  |
  |  |    *arr apps, Downloads, Tdarr      |  |
  |  |    ARM, Uptime Kuma                 |  |
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

- **Dashboard** - https://homarr.yourdomain.com
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
| Uptime Kuma | 3001 | http://SERVER_IP:3001 |

## Services

| Service | Purpose | Port |
|---------|---------|------|
| **Cloudflared** | Secure tunnel for public access | - |
| **Homarr** | Dashboard for all services | 7575 |
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
| **Uptime Kuma** | Service monitoring | 3001 |

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

Important directories to backup:
- `./data/` - All service configurations and databases
- `.env` - Your environment configuration
- `docker-compose.yml` - Service definitions
- `config/recyclarr.yml` - Quality profile configuration

```bash
# Create backup
tar -czf homelab-backup-$(date +%Y%m%d).tar.gz ./data .env docker-compose.yml config/
```

### Updates

Stay up to date with:

```bash
cd /opt/homelab
git pull
docker compose pull
docker compose up -d
```

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

- **r/selfhosted** - Reddit community for homelab enthusiasts
- **r/usenet** - Usenet-specific help and discussions
- **r/homelab** - General homelab hardware and software
- **TRaSH Guides** - https://trash-guides.info/ - Quality profile guides
- **Servarr Wiki** - https://wiki.servarr.com/ - Official *arr documentation
- **Awesome Self-Hosted** - https://github.com/awesome-selfhosted/awesome-selfhosted

## Stack Status

**Production-ready and optimized for video streaming!**

Built for the homelab community.
