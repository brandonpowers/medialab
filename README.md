# Homelab Media Server

A complete, privacy-first media server stack running in an Ubuntu 24.04 LXC on Proxmox. Features automated media management, streaming, secure remote access, and local voice control.

## Overview

**31 Docker services** providing:
- 🎬 Media streaming and management (movies, TV, music, audiobooks, podcasts, e-books, photos)
- 🔒 Privacy-first remote access (Cloudflare Tunnel + Tailscale)
- 🤖 Complete automation (*arr stack with TRaSH Guides integration)
- 🗣️ Local voice assistant (Open Voice OS)
- 📦 Dual download methods (Usenet + Torrents)
- 🔄 Storage optimization (automated transcoding)
- 📊 Service monitoring and management
- 🧑‍💻 Self-hosted Git with CI/CD

## Quick Start

### Automated Setup (Recommended)

Deploy your entire homelab in 2 commands:

```bash
# Clone and enter directory
git clone https://github.com/brandonpowers/homelab.git /opt/homelab
cd /opt/homelab

# Run automated setup
./scripts/setup-homelab.sh
```

**What the script does:**
- ✅ Checks prerequisites (Docker, Docker Compose, OpenSSL)
- ✅ Prompts for configuration (timezone, domain, email, etc.)
- ✅ Generates all passwords and security tokens automatically
- ✅ Creates `.env` configuration file
- ✅ Sets up all data directories
- ✅ Validates docker-compose.yml
- ✅ Pulls all Docker images
- ✅ Starts all services
- ✅ Waits for postgres/redis to be healthy
- ✅ Verifies all databases created
- ✅ Shows service status and access URLs

**Total time:** ~10-20 minutes (mostly downloading images)

### Manual Setup

If you prefer manual setup or need to deploy on Proxmox:

#### 1) On the Proxmox host
```bash
cd /root
git clone https://github.com/<you>/homelab.git
cd homelab/host
chmod +x create-ct.sh

# Optional non-interactive password:
# export CT_PASSWORD='yourStrongPass'

./create-ct.sh   # creates/updates CT (idempotent)
```

#### 2) Inside the LXC Container
```bash
pct enter 101
cd /opt/homelab

# Run automated setup
./scripts/setup-homelab.sh

# Optional: Enable auto-start on boot
./ct/install-service.sh
```

## Service Documentation

### Media Services
- **[Media Streaming](docs/media-streaming.md)** - Jellyfin, Jellyseerr, Homarr
- **[Books & Audiobooks](docs/books-audiobooks.md)** - Calibre-Web, Audiobookshelf
- **[Photos](docs/photos.md)** - Immich photo backup and management

### Automation & Downloads
- **[Media Automation](docs/media-automation.md)** - Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Recyclarr
- **[Downloads](docs/downloads.md)** - qBittorrent, SABnzbd, Usenet setup

### Infrastructure
- **[Network & Remote Access](docs/networking.md)** - Cloudflare Tunnel, Tailscale, security
- **[Backend Services](docs/backend.md)** - PostgreSQL, Redis
- **[Monitoring & Management](docs/monitoring.md)** - Uptime Kuma, Portainer, Tdarr

### Special Features
- **[Gitea (Git + CI/CD)](docs/gitea.md)** - Self-hosted Git with auto-deployment
- **[Open Voice OS](docs/ovos.md)** - Privacy-first voice assistant
- **[Future Enhancements](docs/future-enhancements.md)** - Optional additions

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                  Internet / Users                         │
└──────────────┬─────────────────────────┬──────────────────┘
               │                         │
               │ Public Services         │ Admin Access
               │ (*.yourdomain.com)     │ (Authorized only)
               ▼                         ▼
     ┌──────────────────┐      ┌──────────────────┐
     │  Cloudflare Edge │      │  Tailscale VPN   │
     │   (SSL/DDoS)     │      │  (Zero Trust)    │
     └────────┬─────────┘      └────────┬─────────┘
              │                         │
              │ Outbound Tunnel         │ Encrypted Mesh
              │ (No ports open)         │
              ▼                         ▼
┌──────────────────────────────────────────────────────────┐
│                 GL-AX1800 Router                         │
│              (WireGuard via ProtonVPN)                   │
└────────────────────────┬─────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────┐
│                  Proxmox VE Host                         │
│  ┌────────────────────────────────────────────────────┐  │
│  │      Ubuntu 24.04 LXC Container (CT 101)           │  │
│  │                                                     │  │
│  │  ┌──────────────────────────────────────────────┐  │  │
│  │  │        Docker Compose (31 Services)          │  │  │
│  │  │                                               │  │  │
│  │  │  PUBLIC (via Cloudflare):                    │  │  │
│  │  │    Jellyfin, Jellyseerr, Homarr              │  │  │
│  │  │    Audiobookshelf, Calibre-Web, Immich       │  │  │
│  │  │                                               │  │  │
│  │  │  PRIVATE (via Tailscale):                    │  │  │
│  │  │    *arr apps, Downloads, Tdarr               │  │  │
│  │  │    Portainer, Uptime Kuma, OVOS, Gitea       │  │  │
│  │  │                                               │  │  │
│  │  │  BACKEND: PostgreSQL, Redis                  │  │  │
│  │  └──────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

**Privacy-First Design:**
1. **Home IP never exposed** - Cloudflare Tunnel creates outbound connection only
2. **No ports opened** - Router firewall remains locked down
3. **Public services** - Routed through Cloudflare (DDoS protected, SSL at edge)
4. **Admin services** - Only accessible via Tailscale (zero-trust encrypted mesh)
5. **Local access** - All services still available on home network via IP:PORT

## Service Access

### Public Services (via Cloudflare Tunnel)
Accessible from anywhere with **home IP hidden**:

- **Dashboard** → https://homarr.yourdomain.com
- **Jellyfin** → https://jellyfin.yourdomain.com
- **Jellyseerr** → https://jellyseerr.yourdomain.com
- **Photos** → https://photos.yourdomain.com
- **Audiobooks** → https://audiobooks.yourdomain.com
- **E-books** → https://books.yourdomain.com

### Private Admin Services (via Tailscale)
Secure access from **authorized devices only**:

- **Sonarr** → http://homelab-media:8989
- **Radarr** → http://homelab-media:7878
- **Lidarr** → http://homelab-media:8686
- **Prowlarr** → http://homelab-media:9696
- **Bazarr** → http://homelab-media:6767
- **qBittorrent** → http://homelab-media:8080
- **SABnzbd** → http://homelab-media:8085
- **Tdarr** → http://homelab-media:8265
- **Portainer** → https://homelab-media:9443
- **Uptime Kuma** → http://homelab-media:3001
- **Gitea** → http://homelab-media:3000
- **OVOS GUI** → http://homelab-media:8484

### Local Network Access
Direct access within your home network at `http://CT-IP:PORT`

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
- `recyclarr.yml` - Quality profile configuration

```bash
# Create backup
tar -czf homelab-backup-$(date +%Y%m%d).tar.gz ./data .env docker-compose.yml recyclarr.yml
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
- GPU: Intel QuickSync recommended for transcoding

**Software:**
- Proxmox VE (or any Linux host)
- Docker & Docker Compose
- Ubuntu 24.04 (or similar)

**Network:**
- Domain name (for Cloudflare Tunnel)
- Cloudflare account (free tier)
- Tailscale account (free tier)

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

# Check Tailscale
docker compose exec tailscale tailscale status
```

### Database Issues
```bash
# Check postgres is healthy
docker exec postgres pg_isready -U homelab

# List databases
docker exec postgres psql -U homelab -c '\l'
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

**Production-ready and feature-complete for 2025!** ✨

Built with ❤️ for the homelab community.
