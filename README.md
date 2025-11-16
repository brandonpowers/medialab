# Homelab Media Server (Proxmox LXC → Docker Stack)

A complete, modern media server stack running in an Ubuntu 24.04 LXC on Proxmox. Includes automated media management, streaming, request handling, and secure remote access via Cloudflare Tunnel and Tailscale.

## Overview

This is a **privacy-first, production-ready media server** with:
- ✅ **25 Docker services** - Complete automation stack
- ✅ **Privacy-first** - Cloudflare Tunnel (home IP hidden) + Tailscale (admin access)
- ✅ **Rich media types** - Movies, TV, music, audiobooks, podcasts, e-books
- ✅ **Dual downloads** - Usenet (fast) + Torrents (free)
- ✅ **Automatic HTTPS** - Cloudflare Tunnel with edge SSL
- ✅ **Quality automation** - TRaSH Guides via Recyclarr
- ✅ **Storage optimization** - Tdarr automated transcoding
- ✅ **Full monitoring** - Uptime Kuma tracks all services
- ✅ **User-friendly** - Jellyseerr for easy content requests
- ✅ **Hardware transcoding** - Intel GPU pass-through
- ✅ **VPN protected** - Router-level WireGuard via ProtonVPN

## Table of Contents

- [Services Included](#services-included)
- [Quick Start](#quick-start)
- [Network & Remote Access Setup](#network--remote-access-setup)
  - [What is Cloudflare Tunnel?](#what-is-cloudflare-tunnel)
  - [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
  - [Tailscale Setup](#tailscale-setup)
  - [Security Best Practices](#security-best-practices)
- [Service Access](#service-access)
- [Initial Service Configuration](#initial-service-configuration)
- [Usenet Setup Guide](#usenet-setup-guide)
- [Testing the Complete Workflow](#testing-the-complete-workflow)
- [Maintenance & Updates](#maintenance--updates)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [What's Next?](#whats-next)

## Services Included (25 Total)

**DevOps & Version Control:**
- **Gitea** - Self-hosted Git service with built-in CI/CD (see [GITEA_SETUP.md](GITEA_SETUP.md))
- **Gitea Actions Runner** - Automated deployment on push to main

**Remote Access & Privacy:**
- **Cloudflare Tunnel** - Secure remote access (home IP hidden, no ports open)
- **Tailscale** - Private VPN for admin access (zero-trust security)

**Public User-Facing Services** (via Cloudflare Tunnel):
- **Jellyfin** - Open-source media server (movies, TV, music) with GPU transcoding
- **Jellyseerr** - Media request and discovery platform
- **Immich** - Self-hosted photo and video backup (Google Photos alternative)
- **Audiobookshelf** - Audiobook and podcast server with mobile apps
- **Calibre-Web** - E-book library with send-to-Kindle support
- **Homarr** - Unified dashboard for all services

**Private Admin Services** (via Tailscale only):
- **Portainer** - Docker container management UI
- **Uptime Kuma** - Service monitoring and uptime tracking

**Media Automation (*arr stack):**
- **Sonarr** - TV show management and automation
- **Radarr** - Movie management and automation
- **Lidarr** - Music management and automation
- **Readarr** - E-book management and automation
- **Prowlarr** - Centralized indexer manager for all *arr apps
- **Bazarr** - Subtitle downloading and management
- **Recyclarr** - Automated quality profile management (TRaSH guides)

**Downloads & Optimization:**
- **qBittorrent** - Torrent download client with modern WebUI
- **SABnzbd** - Usenet download client (faster, more reliable than torrents)
- **Tdarr** - Automated video transcoding (H.265 conversion, saves 30-50% storage)

**Shared Backend Services:**
- **PostgreSQL** - Shared database for Immich, Jellyseerr, Uptime Kuma
- **Redis** - Shared cache for Immich job queues and caching
- 📖 See [BACKEND_SUMMARY.md](BACKEND_SUMMARY.md) for quick reference or [BACKEND_MIGRATION.md](BACKEND_MIGRATION.md) for detailed guide

## Quick Start

### ⚡ Automated Setup (Recommended)

**Deploy your entire homelab in 2 commands:**

```bash
# 1. Clone and enter directory
git clone https://github.com/brandonpowers/homelab.git /opt/homelab
cd /opt/homelab

# 2. Run automated setup
./scripts/setup-homelab.sh
```

**What the script does:**
1. ✅ Checks prerequisites (Docker, Docker Compose, OpenSSL)
2. ✅ Prompts for configuration (timezone, domain, email, etc.)
3. ✅ Generates all passwords and security tokens automatically
4. ✅ Creates `.env` configuration file
5. ✅ Sets up all data directories
6. ✅ Validates docker-compose.yml
7. ✅ Pulls all Docker images
8. ✅ Starts all 25 services
9. ✅ Waits for postgres/redis to be healthy
10. ✅ Verifies all databases created
11. ✅ Shows service status and access URLs

**After setup:**
- `.env` created with all configuration
- `.passwords.txt` created with auto-generated passwords (store securely, then delete!)
- All services running and verified
- Ready to configure Cloudflare Tunnel and Tailscale

**Total time:** ~10-20 minutes (mostly downloading images)

### Manual Setup

If you prefer manual setup:

### 1) On the Proxmox host
```bash
cd /root
git clone https://github.com/<you>/homelab.git
cd homelab/host
chmod +x create-ct.sh

# Optional non-interactive password:
# export CT_PASSWORD='yourStrongPass'

./create-ct.sh   # creates/updates CT (idempotent)
```

### 2) On the CT Host
```bash
pct enter 101

git clone https://github.com/<you>/homelab.git /opt/homelab
cd /opt/homelab/ct
chmod +x bootstrap.sh install-service.sh
./bootstrap.sh

# prepare env
cd /opt/homelab
cp .env.example .env

# IMPORTANT: Edit .env with your values:
# - DOMAIN=glaance.io
# - EMAIL=your-email@example.com
# - DB_PASSWORD=... (generate with: openssl rand -base64 32)
# - REDIS_PASSWORD=... (generate with: openssl rand -base64 32)
# - TMDB_API_KEY=... (get from https://www.themoviedb.org/settings/api)
# - CLOUDFLARE_TUNNEL_TOKEN=... (see Cloudflare Tunnel Setup section)
# - TAILSCALE_AUTH_KEY=... (see Tailscale Setup section)
nano .env

# start on boot
cd /opt/homelab/ct
./install-service.sh
```

---

## Network & Remote Access Setup

This stack uses a **privacy-first architecture** with Cloudflare Tunnel and Tailscale:

### What is Cloudflare Tunnel?

Cloudflare Tunnel creates an outbound-only connection from your server to Cloudflare's edge network. Benefits:

- ✅ **Your home IP stays hidden** - No one can find your actual location
- ✅ **No port forwarding** - No holes in your firewall
- ✅ **Free DDoS protection** - Cloudflare's enterprise-grade security
- ✅ **Automatic SSL** - HTTPS handled at Cloudflare's edge
- ✅ **Works behind CGNAT** - No public IP needed
- ✅ **Zero Trust security** - Optional access policies and authentication

### Cloudflare Tunnel Setup

#### Prerequisites

1. **Domain name** - You have glaance.io
2. **Cloudflare account** - Free tier is sufficient
3. **Domain managed by Cloudflare DNS** - Transfer or point nameservers

#### Step 1: Transfer Domain to Cloudflare DNS

1. **Sign up at** [Cloudflare](https://dash.cloudflare.com/sign-up)

2. **Add your site:**
   - Click "Add a site"
   - Enter: `glaance.io`
   - Select Free plan
   - Click "Add site"

3. **Cloudflare will scan your DNS records** (if migrating from another provider)
   - Review the records found
   - Click "Continue"

4. **Update nameservers at your registrar:**
   - Cloudflare provides 2 nameservers (e.g., `emma.ns.cloudflare.com`)
   - Log into your domain registrar (where you bought glaance.io)
   - Find DNS/Nameserver settings
   - Replace existing nameservers with Cloudflare's
   - Save changes

5. **Wait for DNS propagation** (5 minutes to 24 hours)
   - Cloudflare will email when active
   - Status shows "Active" in Cloudflare dashboard

#### Step 2: Create Cloudflare Tunnel

1. **Navigate to Zero Trust:**
   - In Cloudflare dashboard, click "Zero Trust" in left sidebar
   - (First time: Set up a team name, any name works)

2. **Create a tunnel:**
   - Go to: **Networks** → **Tunnels**
   - Click "Create a tunnel"
   - Select "Cloudflared"
   - Name: `homelab-media` (or any name)
   - Click "Save tunnel"

3. **Install connector** (we'll use Docker - already in your compose file):
   - Cloudflare shows installation methods
   - **Select: Docker**
   - Copy the tunnel token shown (starts with `eyJ...`)
   - Save this token - you'll add it to `.env` file

4. **Skip the connector install** (we handle this in docker-compose.yml):
   - Click "Next"

#### Step 3: Configure Public Hostname Routes

Now you'll route your subdomains to services. Add these public hostnames:

**1. Homarr (Dashboard)**
```
Public hostname: homarr.glaance.io
Service:
  Type: HTTP
  URL: homarr:7575
```

**2. Jellyfin (Media Server)**
```
Public hostname: jellyfin.glaance.io
Service:
  Type: HTTP
  URL: jellyfin:8096
Additional settings:
  - No TLS Verify: ON (internal traffic)
```

**3. Jellyseerr (Media Requests)**
```
Public hostname: jellyseerr.glaance.io
Service:
  Type: HTTP
  URL: jellyseerr:5055
```

**4. Audiobookshelf (Audiobooks & Podcasts)**
```
Public hostname: audiobooks.glaance.io
Service:
  Type: HTTP
  URL: audiobookshelf:80
```

**5. Calibre-Web (E-books)**
```
Public hostname: books.glaance.io
Service:
  Type: HTTP
  URL: calibre-web:8083
```

**6. Immich (Photo Backup)**
```
Public hostname: photos.glaance.io
Service:
  Type: HTTP
  URL: immich-server:3001
```

Click "Save tunnel" after adding all routes.

#### Step 4: Configure Environment Variable

1. **Edit your `.env` file:**
   ```bash
   cd /opt/homelab
   nano .env
   ```

2. **Add your tunnel token:**
   ```bash
   CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoiYzU3ZjE4M2Y0YmY0MTMwNjk3OTk4ZjhmNTdjYzRhZmYiLCJ0IjoiOWRkMzllYTYtMWI4Ni00MjU3LTg5YzAtZmYzYjRhNzUwMDUwIiwicyI6Ik1USTRZemxsTVRFdFlUVTRNeTAwWkRVM0xUazRNRGt0TnpNNE9HTm1Zekl5TnpNeSJ9
   ```
   (Use your actual token from Step 2)

3. **Save and exit** (Ctrl+X, Y, Enter)

#### Step 5: Start the Stack

1. **Pull images and start services:**
   ```bash
   cd /opt/homelab
   docker compose pull
   docker compose up -d
   ```

2. **Verify tunnel is connected:**
   ```bash
   docker compose logs cloudflared
   ```

   Look for:
   ```
   INF Connection <UUID> registered connIndex=0
   INF Tunnel created successfully
   ```

3. **Check Cloudflare dashboard:**
   - Go back to **Networks** → **Tunnels**
   - Your tunnel should show status: **HEALTHY** with a green checkmark

#### Step 6: Test Access

**From Outside Your Network** (use mobile data or ask a friend):

```bash
# Test each subdomain
curl -I https://jellyfin.glaance.io
curl -I https://homarr.glaance.io
curl -I https://jellyseerr.glaance.io
curl -I https://audiobooks.glaance.io
curl -I https://books.glaance.io
curl -I https://photos.glaance.io
```

Or just open in browser:
- https://homarr.glaance.io - Should show your dashboard
- https://jellyfin.glaance.io - Should show Jellyfin login
- https://photos.glaance.io - Should show Immich login

**Check SSL Certificate:**
- Click padlock icon in browser
- Certificate issued by: Cloudflare
- Valid for: glaance.io and subdomains

---

### Tailscale Setup

Admin services (Sonarr, Radarr, Portainer, etc.) should **NOT** be publicly accessible. Use Tailscale for secure private access.

#### Step 1: Get Auth Key

1. **Go to:** https://login.tailscale.com/admin/settings/keys
2. **Click "Generate auth key"**
3. **Options:**
   - Reusable: **YES**
   - Ephemeral: **NO**
   - Tags: (optional) `tag:homelab`
4. **Copy the key** (starts with `tskey-auth-...`)

#### Step 2: Add to `.env` file

```bash
nano .env
```

Add:
```bash
TAILSCALE_AUTH_KEY=tskey-auth-xxxxxxxxxxxxx-yyyyyyyyyyyyyyyy
```

#### Step 3: Restart stack

```bash
docker compose up -d
```

#### Step 4: Verify Tailscale

```bash
docker compose logs tailscale
```

Check Tailscale admin:
- Go to: https://login.tailscale.com/admin/machines
- You should see: `homelab-media`

#### Step 5: Access Admin Services

1. **Install Tailscale on your devices:**
   - **Mac/PC:** https://tailscale.com/download
   - **iOS/Android:** App store

2. **Log in with same account**

3. **Get Tailscale IP:**
   ```bash
   docker compose exec tailscale tailscale ip
   # Example: 100.101.102.103
   ```

4. **Access admin services via Tailscale:**
   - Sonarr: `http://homelab-media:8989` or `http://100.101.102.103:8989`
   - Radarr: `http://homelab-media:7878`
   - Lidarr: `http://homelab-media:8686`
   - Readarr: `http://homelab-media:8787`
   - Prowlarr: `http://homelab-media:9696`
   - Bazarr: `http://homelab-media:6767`
   - qBittorrent: `http://homelab-media:8080`
   - SABnzbd: `http://homelab-media:8085`
   - Tdarr: `http://homelab-media:8265`
   - Portainer: `https://homelab-media:9443`
   - Uptime Kuma: `http://homelab-media:3001`

---

### Security Best Practices

#### 1. Enable Cloudflare Web Application Firewall (WAF)
- Go to Cloudflare dashboard → Security → WAF
- Enable "OWASP Core Ruleset"
- Enable "Cloudflare Managed Ruleset"

#### 2. Set Up Access Policies (Optional but recommended)
For additional security on public services:

- Go to Zero Trust → Access → Applications
- Create application for each service
- Add access policy:
  - Allow: Email ends with `@yourdomain.com`
  - Or: Country = United States (or your country)
  - Or: Require authentication via Google/GitHub/etc.

Example: Require login before accessing Jellyseerr

#### 3. Enable Rate Limiting
- Cloudflare dashboard → Security → Settings
- Enable "Rate Limiting Rules"
- Limit: 100 requests per minute per IP

#### 4. Monitor Access Logs
- Zero Trust → Logs → Access
- Review authentication attempts
- Set up alerts for suspicious activity

---

## Service Access

### Public Services (via Cloudflare Tunnel)
Accessible from anywhere with **home IP hidden**:

- **Dashboard** → https://homarr.glaance.io
- **Jellyfin** → https://jellyfin.glaance.io
- **Jellyseerr** → https://jellyseerr.glaance.io
- **Photos** → https://photos.glaance.io
- **Audiobooks** → https://audiobooks.glaance.io
- **E-books** → https://books.glaance.io

### Private Admin Services (via Tailscale)
Secure access from **authorized devices only**:

- **Sonarr** → http://homelab-media:8989
- **Radarr** → http://homelab-media:7878
- **Lidarr** → http://homelab-media:8686
- **Readarr** → http://homelab-media:8787
- **Prowlarr** → http://homelab-media:9696
- **Bazarr** → http://homelab-media:6767
- **qBittorrent** → http://homelab-media:8080
- **SABnzbd** → http://homelab-media:8085
- **Tdarr** → http://homelab-media:8265
- **Portainer** → https://homelab-media:9443
- **Uptime Kuma** → http://homelab-media:3001

### Local Network Access
Direct access within your home network:

All services available at `http://CT-IP:PORT` (see docker-compose.yml for ports)

---

## Initial Service Configuration

After services are running, configure them in this order:

### 1. qBittorrent Setup
1. Access qBittorrent WebUI (default password is in container logs: `docker compose logs qbittorrent`)
2. Change default password: Tools → Options → Web UI → Authentication
3. Configure download paths:
   - Default Save Path: `/downloads/complete`
   - Incomplete torrents: `/downloads/incomplete`
4. (Optional) Set category-based paths for automatic organization

### 2. Prowlarr - Indexer Manager
1. Open Prowlarr and complete initial setup
2. Add indexers: Indexers → Add Indexer
   - **Public Indexers** (no account needed):
     - 1337x, ThePirateBay, EZTV, RARBG alternatives, Nyaa (anime)
   - **Private Trackers** (if you have accounts):
     - Add with your credentials
3. Add apps: Settings → Apps → Add Application
   - Add Sonarr (get API key from Sonarr: Settings → General)
   - Add Radarr (get API key from Radarr: Settings → General)
   - Add Lidarr (get API key from Lidarr: Settings → General)
4. Test sync - indexers should now appear in all *arr apps

### 3. Configure Download Client in *arr Apps
For each of Sonarr, Radarr, and Lidarr:
1. Go to Settings → Download Clients → Add (+)
2. Select qBittorrent
3. Configure:
   - Host: `qbittorrent`
   - Port: `8080`
   - Username/Password: (from qBittorrent setup)
4. Test and Save

### 4. Jellyfin Setup
1. Open Jellyfin and complete initial setup wizard
2. Create admin account
3. Add media libraries:
   - Movies: `/media/movies`
   - TV Shows: `/media/tv`
   - Music: `/media/music`
4. Enable hardware acceleration: Dashboard → Playback → Transcoding
   - Select: Video Acceleration API (VAAPI) or Intel Quick Sync
   - Device: `/dev/dri/renderD128`

### 5. Jellyseerr - Request Management
1. Open Jellyseerr and sign in with your Jellyfin admin account
2. Configure Jellyfin: Settings → Jellyfin → Add Server
   - Server URL: `http://jellyfin:8096`
   - Sign in with Jellyfin credentials
3. Configure Sonarr: Settings → Services → Sonarr → Add Server
   - Server URL: `http://sonarr:8989`
   - API Key: (from Sonarr Settings → General)
   - Quality Profile: Select your preferred profile
   - Root Folder: `/media/tv`
4. Configure Radarr: Settings → Services → Radarr → Add Server
   - Server URL: `http://radarr:7878`
   - API Key: (from Radarr Settings → General)
   - Quality Profile: Select your preferred profile
   - Root Folder: `/media/movies`
5. Configure TMDB: Settings → Services → The Movie Database
   - Add your TMDB API key (from `.env` file)
6. Set up user permissions and approval workflows

### 6. Media Library Structure
Ensure your `/mnt/media` directory has this structure:
```
/mnt/media/
├── downloads/
│   ├── complete/
│   │   ├── torrents/
│   │   └── usenet/
│   └── incomplete/
│       ├── torrents/
│       └── usenet/
├── movies/
├── tv/
├── music/
├── audiobooks/
├── podcasts/
├── books/
└── photos/
```

Create directories if needed:
```bash
mkdir -p /mnt/media/downloads/{complete/{torrents,usenet},incomplete/{torrents,usenet}}
mkdir -p /mnt/media/{movies,tv,music,audiobooks,podcasts,books,photos}
```

### 7. Recyclarr - Automated Quality Profiles

Recyclarr automatically syncs TRaSH Guides quality profiles to your *arr apps.

**Setup:**

1. Get API keys from Sonarr and Radarr:
   - Sonarr: Settings → General → API Key
   - Radarr: Settings → General → API Key

2. Add to your `.env` file:
   ```bash
   SONARR_API_KEY=your_sonarr_api_key
   RADARR_API_KEY=your_radarr_api_key
   READARR_API_KEY=your_readarr_api_key
   ```

3. Copy the config template:
   ```bash
   cp recyclarr.yml data/recyclarr/config/recyclarr.yml
   ```

4. Run Recyclarr to sync profiles:
   ```bash
   docker compose run --rm recyclarr sync
   ```

5. Verify in Sonarr/Radarr:
   - Go to Settings → Profiles
   - You should see new quality profiles: `WEB-1080p` (Sonarr), `HD-1080p` (Radarr)
   - Custom formats should be populated

6. **(Optional) Automate with cron:**
   ```bash
   # Add to crontab to run daily at 3 AM
   0 3 * * * cd /opt/homelab && docker compose run --rm recyclarr sync
   ```

**What Recyclarr does:**
- Syncs TRaSH Guides quality profiles (community best practices)
- Sets up custom formats (prefer specific streaming services, codecs, etc.)
- Configures quality definitions (file size limits)
- Keeps profiles updated automatically

### 8. Uptime Kuma - Service Monitoring

Monitor all your services and get alerts when they go down.

**Setup:**

1. Open Uptime Kuma: `http://homelab-media:3001` (via Tailscale)

2. Create admin account (first time only)

3. Add monitors for each service:
   - Click **Add New Monitor**
   - **Monitor Type**: HTTP(s)
   - **Friendly Name**: Jellyfin
   - **URL**: `http://jellyfin:8096` (for internal monitoring)
   - **Heartbeat Interval**: 60 seconds
   - **Retries**: 3
   - Click **Save**

4. Repeat for all services:
   - Sonarr: `http://sonarr:8989`
   - Radarr: `http://radarr:7878`
   - Lidarr: `http://lidarr:8686`
   - Prowlarr: `http://prowlarr:9696`
   - Bazarr: `http://bazarr:6767`
   - qBittorrent: `http://qbittorrent:8080`
   - SABnzbd: `http://sabnzbd:8080`
   - Jellyseerr: `http://jellyseerr:5055`
   - Portainer: `https://portainer:9443`

5. **(Optional) Set up notifications:**
   - Settings → Notifications
   - Add notification methods: Discord, Telegram, Email, Slack, etc.
   - Get alerts when services go down

6. **(Optional) Create Status Page:**
   - Status Pages → Add Status Page
   - Select monitors to include
   - Generate public URL to share uptime with users

### 9. Audiobookshelf - Audiobooks & Podcasts

1. Access: `https://audiobooks.glaance.io` (or local IP:13378)
2. Create admin account on first visit
3. Add libraries:
   - **Audiobooks**: `/audiobooks`
   - **Podcasts**: `/podcasts`
4. Configure:
   - Enable podcast auto-download
   - Set up mobile app sync (iOS/Android apps available)
   - Configure metadata providers

### 10. Calibre-Web + Readarr - E-books

**Calibre-Web Setup:**
1. Access: `https://books.glaance.io` (or local IP:8083)
2. Initial setup:
   - Database location: `/books/metadata.db` (will be created)
   - Admin username: `admin`, Password: `admin123` (change immediately!)
3. Configure:
   - Enable uploads
   - Configure email for send-to-Kindle
   - Set up OPDS catalog for e-readers

**Readarr Setup (via Tailscale):**
1. Access: `http://homelab-media:8787`
2. Add Calibre library: Settings → Calibre → `/books`
3. Add download clients: qBittorrent and/or SABnzbd
4. Connect to Prowlarr (auto-configured if Prowlarr sync is set)
5. Add authors and books to monitor

### 11. Tdarr - Automated Transcoding

1. Access (via Tailscale): `http://homelab-media:8265`
2. Initial setup wizard:
   - Accept defaults for most options
3. Add libraries:
   - **Movies**: `/media/movies`
   - **TV Shows**: `/media/tv`
4. Configure transcode rules:
   - Libraries → Select library → Transcode Options
   - Enable: "H265 GPU Encoding" (uses Intel Quick Sync)
   - Set: Transcode to H.265, keep audio as-is
5. Set schedule: Only transcode overnight (avoid during streaming hours)
6. Monitor: Dashboard shows transcoding progress and space saved

### 12. Immich - Photo & Video Backup

**Access:** `https://photos.glaance.io` (or local IP:2283)

**Initial Setup:**

1. Open Immich for the first time
2. Create admin account (email + password)
3. Complete welcome wizard

**Mobile App Setup:**

1. **Download Immich mobile app:**
   - iOS: https://apps.apple.com/app/immich/id1613945652
   - Android: https://play.google.com/store/apps/details?id=app.alextran.immich

2. **Connect to your server:**
   - Server URL: `https://photos.glaance.io`
   - Login with your admin credentials

3. **Enable automatic backup:**
   - Settings → Backup
   - Enable "Automatic backup"
   - Select albums/folders to backup
   - Choose backup settings (original quality recommended)

**Key Features:**

- ✅ **Automatic photo/video backup** - Like Google Photos, but self-hosted
- ✅ **Face recognition** - ML-powered people detection
- ✅ **Smart search** - Search by objects, places, dates
- ✅ **Album sharing** - Share albums with family/friends
- ✅ **Mobile apps** - iOS and Android native apps
- ✅ **Live photos** - Full support for iOS live photos
- ✅ **RAW support** - Professional photography formats
- ✅ **Video transcoding** - Automatic video optimization

**Storage Location:**

Photos are stored in: `/mnt/media/photos/`

Create this directory if it doesn't exist:
```bash
mkdir -p /mnt/media/photos
```

**Tips:**

- **Original quality:** Immich stores photos in original quality (no compression)
- **Storage estimates:** ~2GB per 1000 photos (varies by resolution)
- **Performance:** ML features use CPU; consider disabling on low-power systems
- **Backup strategy:** Immich is your backup, but consider backing up the `/media/photos` directory too

---

## Usenet Setup Guide

Usenet is a faster, more reliable alternative to torrents for automated media downloading. This guide will help you set up SABnzbd with a Usenet provider and integrate it with your *arr stack.

### What is Usenet?

Usenet is a distributed discussion system that has been repurposed for file sharing. Unlike torrents (peer-to-peer), Usenet uses centralized servers, providing:

- ✅ **Maximum speed** - Downloads max out your connection (no seeders needed)
- ✅ **Better privacy** - Direct encrypted connection to provider servers
- ✅ **Better retention** - Files available for years (4000+ days with good providers)
- ✅ **More automation-friendly** - Reliable for Sonarr/Radarr automation
- ✅ **No seeding required** - Download and done

**Downsides:**
- ❌ **Costs money** - Typically $10-15/month for provider + indexer
- ❌ **DMCA takedowns** - Popular content may get removed faster than torrents
- ❌ **Learning curve** - More complex setup than torrents

**Best Practice:** Use Usenet as primary, keep torrents (qBittorrent) as fallback for rare/old content.

### Step 1: Choose a Usenet Provider

You need a Usenet provider subscription. Here are popular, reliable options:

**Tier 1: Premium (Fastest, Best Retention)**
- **[Newshosting](https://www.newshosting.com/)** - $10-15/month
  - 5500+ day retention
  - Unlimited downloads
  - Fast speeds
  - Good for US/EU

- **[UsenetServer](https://www.usenetserver.com/)** - $10-15/month
  - 5500+ day retention
  - Unlimited downloads
  - Highwinds backbone

- **[Eweka](https://www.eweka.nl/)** - €8-12/month
  - EU-based (Netherlands)
  - 5000+ day retention
  - Independent backbone
  - Great for EU users

**Tier 2: Budget Options**
- **[Frugal Usenet](https://frugalusenet.com/)** - $5-7/month
  - 3000+ day retention
  - Good speeds
  - Budget-friendly

- **[Newsgroup Ninja](https://www.newsgroup.ninja/)** - $8/month
  - Unlimited downloads
  - 3000+ day retention

#### Provider Selection Tips

1. **Backbone diversity**: Some providers share the same backbone (Omicron, Highwinds, Abavia). If content is removed from one, it's removed from all on that backbone. Consider getting 2 providers on different backbones for redundancy.

2. **Location matters**: Choose a provider with servers close to you for best speeds.

3. **Black Friday deals**: Usenet providers often have 50-70% off deals in November.

#### Recommended Setup (Optimal)
- **Primary:** Newshosting or UsenetServer (Highwinds backbone)
- **Block account:** Eweka (different backbone for DMCA-removed content)

A "block account" is a one-time purchase of data (500GB-1TB) you can use as backup when primary fails.

### Step 2: Choose Usenet Indexers

Indexers are like torrent trackers - they index and catalog NZB files (Usenet's equivalent of .torrent files).

**Free Indexers**
- **NZBGeek** - https://nzbgeek.info/ (limited free tier)
- **NZBFinder** - https://nzbfinder.ws/ (limited free tier)

**Paid Indexers (Recommended)**
- **NZBGeek** - $12-20/year (lifetime options available)
- **DrunkenSlug** - Invite only, but worth getting
- **NinjaCentral** - $10-15/year

**How Many Indexers?**
- **Minimum:** 1-2 indexers (mix of free and paid)
- **Recommended:** 3-4 indexers for best coverage
- **Note:** Prowlarr will manage all your indexers centrally!

### Step 3: Configure SABnzbd

**Access SABnzbd:**
After deploying the stack:
- **Local:** `http://CT-IP:8085`
- **Via Tailscale:** `http://homelab-media:8085` (private admin access)

**Initial Setup Wizard:**

1. **Language**: Select your language

2. **Add Usenet Server:**
   - Host: Your provider's server address (e.g., `news.newshosting.com`)
   - Port: `563` (SSL) or `119` (non-SSL) - **Use SSL!**
   - Username: Your provider username
   - Password: Your provider password
   - Connections: `20-30` (check your provider's limit)
   - SSL: ✅ **Enabled**
   - Priority: `0` (primary server)

3. **Test Server**: Click "Test Server" - should show green checkmark

4. **Complete Setup**

**Configure Download Settings:**

Go to **Config → Folders**:
- **Temporary Download Folder**: `/downloads/incomplete/usenet`
- **Completed Download Folder**: `/downloads/complete/usenet`

Go to **Config → Categories**:
- Create categories for better organization:
  - **tv**: `/downloads/complete/usenet/tv`
  - **movies**: `/downloads/complete/usenet/movies`
  - **music**: `/downloads/complete/usenet/music`

Go to **Config → Switches**:
- ✅ **Enable HTTPS**: Yes (if using reverse proxy)
- **Unwanted Extensions**: `exe, com, bat, sh` (block dangerous files)
- ✅ **Pause Downloads on Post-Processing**: Yes

Go to **Config → General**:
- Set **API Key** (you'll need this for Sonarr/Radarr)

### Step 4: Add Indexers to Prowlarr

1. **Open Prowlarr**: `http://CT-IP:9696` (local) or `http://homelab-media:9696` (via Tailscale)

2. **Add Usenet Indexer:**
   - Go to **Indexers → Add Indexer**
   - Search for your indexer (e.g., "NZBGeek")
   - Click the indexer
   - Fill in:
     - **Base URL**: Usually pre-filled
     - **API Key**: From your indexer's website (usually in profile/settings)
   - **Test** and **Save**

3. **Repeat** for all your indexers

4. **Sync to Apps**: Prowlarr automatically syncs indexers to Sonarr/Radarr/Lidarr

### Step 5: Add SABnzbd to *arr Apps

**Configure in Sonarr:**

1. Go to **Settings → Download Clients → Add (+)**
2. Select **SABnzbd**
3. Configure:
   - **Name**: SABnzbd
   - **Host**: `sabnzbd`
   - **Port**: `8080`
   - **API Key**: (from SABnzbd Config → General)
   - **Category**: `tv`
   - **Priority**: `1` (or `0` if you want Usenet preferred over torrents)
4. **Test** and **Save**

**Configure in Radarr:**

1. Go to **Settings → Download Clients → Add (+)**
2. Select **SABnzbd**
3. Configure:
   - **Name**: SABnzbd
   - **Host**: `sabnzbd`
   - **Port**: `8080`
   - **API Key**: (from SABnzbd)
   - **Category**: `movies`
   - **Priority**: `1`
4. **Test** and **Save**

**Configure in Lidarr:**

1. Go to **Settings → Download Clients → Add (+)**
2. Select **SABnzbd**
3. Configure:
   - **Name**: SABnzbd
   - **Host**: `sabnzbd`
   - **Port**: `8080`
   - **API Key**: (from SABnzbd)
   - **Category**: `music`
   - **Priority**: `1`
4. **Test** and **Save**

### Step 6: Download Priority (Usenet First, Torrents Fallback)

In each *arr app (Sonarr/Radarr/Lidarr):

**Settings → Download Clients:**
- **SABnzbd Priority**: `1` (download first)
- **qBittorrent Priority**: `10` (fallback if Usenet fails)

Lower priority = tried first. This ensures Usenet is attempted before torrents.

### Step 7: Test the Setup

1. **Open Jellyseerr** or **Sonarr directly**
2. Search for a popular TV show or movie
3. Request/Add it
4. Watch the process:
   - Prowlarr searches Usenet indexers
   - Best NZB is sent to SABnzbd
   - SABnzbd downloads at max speed
   - Sonarr/Radarr imports to media folder
   - Jellyfin picks it up

### Usenet Cost Breakdown

**Monthly:**
- Usenet Provider: $10-15/month
- Total: **$10-15/month**

**Yearly:**
- Usenet Provider: $100-150/year (often cheaper annually)
- Indexers: $20-40/year (1-2 paid indexers)
- Total: **$120-190/year** (~$10-16/month)

**Budget Option:**
- Frugal Usenet: $60/year
- 1 paid indexer: $12/year
- Total: **$72/year** (~$6/month)

### Advanced: Multiple Providers

For maximum reliability, add a backup provider on a different backbone:

**SABnzbd Config → Servers → Add Server**

**Server 1 (Primary):**
- Host: `news.newshosting.com` (Highwinds)
- Priority: `0`
- Connections: `30`

**Server 2 (Backup - Block Account):**
- Host: `ssl.eweka.nl` (Abavia/independent)
- Priority: `1` (only used if primary fails)
- Connections: `10`

When Server 1 can't find articles (DMCA removed), Server 2 kicks in automatically.

### Usenet Troubleshooting

**Can't connect to server:**
- Verify credentials with provider
- Check SSL is enabled (port 563)
- Ensure VPN (if using) doesn't block Usenet ports
- Try reducing connections to `10`

**Downloads fail with "missing articles":**
- Content may be DMCA'd or too old
- Add a backup provider on different backbone
- Check retention (content age vs provider retention)

**Downloads are slow:**
- Increase connections in SABnzbd (max per provider's limit)
- Check server location (EU provider for EU users, etc.)
- Verify no bandwidth throttling from ISP
- Router-level VPN might slow things down

**Indexer returns no results:**
- Verify API key is correct
- Check indexer is online (visit website)
- Free indexers have rate limits
- Consider paid indexers for better coverage

**Sonarr/Radarr can't connect to SABnzbd:**
- Verify container name is `sabnzbd`
- Check API key matches
- Test from Sonarr: Settings → Download Clients → Test
- Check SABnzbd logs for errors

### Usenet vs Torrents: When to Use Each

**Use Usenet for:**
- ✅ Popular, recent content (last 3 years)
- ✅ TV shows (automated daily downloads)
- ✅ Speed is priority
- ✅ Privacy concerns

**Use Torrents (qBittorrent) for:**
- ✅ Old/rare content (beyond retention)
- ✅ Free option
- ✅ Content removed from Usenet
- ✅ Niche content with dedicated seeders

### Usenet Security & Privacy

**Usenet Security:**
- ✅ Encrypted connection (SSL/TLS) to provider
- ✅ No IP exposed to other users (unlike torrents)
- ✅ Direct connection to servers (no P2P)

**With Your VPN Setup:**
- Your router-level ProtonVPN encrypts ALL traffic, including Usenet
- This is secure but may be overkill since Usenet is already encrypted
- **Optional:** Disable VPN for Usenet to improve speeds (if you trust provider's SSL)

### Recommended Resources

- **r/Usenet** - Reddit community for help and deals
- **NZBGeek Wiki** - Comprehensive Usenet guides
- **TRaSH Guides** - Best practices for *arr apps with Usenet: https://trash-guides.info/

**Usenet Providers Comparison Chart**

| Provider       | Retention | Backbone    | Price/Month | Best For       |
|----------------|-----------|-------------|-------------|----------------|
| Newshosting    | 5500 days | Highwinds   | $10-15      | US/Premium     |
| UsenetServer   | 5500 days | Highwinds   | $10-15      | US/Premium     |
| Eweka          | 5000 days | Independent | €8-12       | EU/Privacy     |
| Frugal Usenet  | 3000 days | Omicron     | $5-7        | Budget         |
| Newsgroup Ninja| 3000 days | Highwinds   | $8          | Mid-tier       |

---

## Testing the Complete Workflow

1. **Request Content via Jellyseerr:**
   - Search for a movie or TV show
   - Click "Request"

2. **Automatic Processing:**
   - Jellyseerr sends request to Sonarr/Radarr
   - Sonarr/Radarr searches via Prowlarr indexers
   - Best release is sent to SABnzbd (if Usenet) or qBittorrent
   - Download completes to `/downloads/complete`
   - Sonarr/Radarr moves file to `/media/movies` or `/media/tv`
   - Jellyfin automatically scans and adds to library

3. **Watch in Jellyfin:**
   - Open Jellyfin
   - Content should appear in your library
   - Start streaming!

---

## Maintenance & Updates

### Update All Services
```bash
cd /opt/homelab
docker compose pull        # Pull latest images
docker compose up -d       # Recreate containers with new images
docker image prune -f      # Remove old images
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f jellyfin
docker compose logs -f cloudflared

# Last 100 lines
docker compose logs --tail=100 sonarr
```

### Restart Services
```bash
# All services
docker compose restart

# Specific service
docker compose restart jellyfin
```

### Backup Important Data
Important directories to backup:
- `./data/` - All service configurations and databases
- `.env` - Your environment configuration

```bash
# Example backup command
tar -czf homelab-backup-$(date +%Y%m%d).tar.gz ./data .env docker-compose.yml recyclarr.yml
```

### Automated Backup Script

Create a backup script at `/opt/homelab/backup.sh`:

```bash
#!/bin/bash
# /opt/homelab/backup.sh

BACKUP_DIR="/mnt/media/backups"
DATE=$(date +%Y%m%d_%H%M%S)

cd /opt/homelab
tar -czf "$BACKUP_DIR/homelab-config-$DATE.tar.gz" \
    ./data .env docker-compose.yml recyclarr.yml

# Keep only last 30 days
find "$BACKUP_DIR" -name "homelab-config-*.tar.gz" -mtime +30 -delete
```

Run daily via cron:
```bash
crontab -e
# Add this line:
0 2 * * * /opt/homelab/backup.sh
```

---

## Troubleshooting

### Cloudflare Tunnel Issues

**Tunnel shows "Down" or "Unhealthy":**
```bash
# Check logs
docker compose logs cloudflared

# Common issues:
# - Wrong token in .env file
# - Network connectivity issues
# - Restart container
docker compose restart cloudflared
```

**Subdomain not resolving:**
- Wait 5 minutes for DNS propagation
- Check tunnel status in Cloudflare dashboard
- Verify public hostname is configured correctly
- Check service is running: `docker compose ps`

**"Bad Gateway" error:**
- Service might not be running: `docker compose ps`
- Check service logs: `docker compose logs jellyfin`
- Verify internal URL in tunnel config (e.g., `jellyfin:8096`)

### Tailscale Issues

**Can't access admin services via Tailscale:**
```bash
# Check Tailscale is running
docker compose ps tailscale

# Get Tailscale IP
docker compose exec tailscale tailscale status

# Verify on other device:
tailscale status  # Should show homelab-media
```

### General Service Issues

**Service won't start:**
```bash
# Check logs
docker compose logs servicename

# Check if port is already in use
netstat -tulpn | grep :PORT
```

**Can't access services:**
```bash
# Check all services are running
docker compose ps

# Check container can be reached
docker compose exec jellyfin ping google.com
```

**Indexers not working in Prowlarr:**
- Check indexer status on their websites
- Some public indexers may be down temporarily
- Try different indexers

**Downloads not importing to Jellyfin:**
- Check file permissions on `/mnt/media`
- Verify paths match between download clients and *arr apps
- Check *arr logs for import errors

**Local access stopped working:**
- Services are still accessible on LAN via direct IP:
  - `http://CT-IP:8096` for Jellyfin
  - `http://CT-IP:7575` for Homarr
  - etc.

---

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                  Internet / Users                         │
└──────────────┬─────────────────────────┬──────────────────┘
               │                         │
               │ Public Services         │ Admin Access
               │ (*.glaance.io)         │ (Authorized only)
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
│  │  │        Docker Compose (23 Services)          │  │  │
│  │  ├──────────────────────────────────────────────┤  │  │
│  │  │  PUBLIC (via Cloudflare):                    │  │  │
│  │  │    Jellyfin, Jellyseerr, Homarr              │  │  │
│  │  │    Audiobookshelf, Calibre-Web, Immich       │  │  │
│  │  ├──────────────────────────────────────────────┤  │  │
│  │  │  PRIVATE (via Tailscale):                    │  │  │
│  │  │    *arr apps, Downloads, Tdarr               │  │  │
│  │  │    Portainer, Uptime Kuma                    │  │  │
│  │  ├──────────────────────────────────────────────┤  │  │
│  │  │  BACKEND: PostgreSQL, Redis                  │  │  │
│  │  │  ACCESS: cloudflared + tailscale             │  │  │
│  │  └──────────────────────────────────────────────┘  │  │
│  │                                                     │  │
│  │  Mounts: /dev/dri (GPU), /mnt/media (storage)      │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

**Privacy-First Architecture:**
1. **Home IP never exposed** - Cloudflare Tunnel creates outbound connection only
2. **No ports opened** - Router firewall remains locked down
3. **Public services** - Routed through Cloudflare (DDoS protected, SSL at edge)
4. **Admin services** - Only accessible via Tailscale (zero-trust encrypted mesh)
5. **Local access** - All services still available on home network via IP:PORT

---

## What's Next?

Your stack is **complete and production-ready** with all 2025 best practices! 🎉

For optional enhancements and future ideas, see **[NEXTSTEPS.md](NEXTSTEPS.md)**.

### Notes on Idempotency
- **Host script** won't recreate the CT if it exists; only adjusts settings and appends missing lines in the CT config.
- It **adds** sysctl lines on the host just once.
- **Bootstrap** only installs Docker if absent, creates missing data dirs, and creates `.env` from `.env.example` if needed.
- **Service install** only overwrites the unit if content changed.

---

## Quick Reference

### Stack Overview

**Service Count:** 25 services (6 public, 19 private)
**Total Cost:** $0/year (Cloudflare + Tailscale free) + optional $120-190/year (Usenet)
**Storage:** ~100GB for services + media storage
**Resources:** 8 CPU cores, 24GB RAM (configured in LXC)
**Privacy:** ✅ Home IP hidden, ✅ No ports open, ✅ Zero-trust admin access

### Quick Commands

**Daily Operations:**
```bash
# Update all services
bash scripts/update.sh

# Check service health
bash scripts/health-check.sh

# View logs (all services)
docker compose logs -f

# View logs (specific service)
docker compose logs -f jellyfin

# Restart a service
docker compose restart servicename

# Check service status
docker compose ps
```

**Maintenance:**
```bash
# Clean up disk space
bash scripts/cleanup.sh

# Validate .env configuration
bash scripts/validate-env.sh

# Manual update (step-by-step)
docker compose pull          # Pull latest images
docker compose up -d         # Recreate containers
docker image prune -f        # Remove old images

# Stop all services
docker compose down

# Start all services
docker compose up -d

# Restart entire stack
docker compose restart
```

**Recyclarr (Quality Profiles):**
```bash
# Sync quality profiles (after adding API keys to .env)
docker compose run --rm recyclarr sync

# Test recyclarr configuration
docker compose run --rm recyclarr config validate
```

**Service Management:**
```bash
# View systemd service status
systemctl status homelab.service

# Restart via systemd
systemctl restart homelab.service

# View systemd logs
journalctl -u homelab.service -f

# Reload systemd service (pull + restart)
systemctl reload homelab.service
```

**Troubleshooting:**
```bash
# Check Cloudflare Tunnel status
docker compose logs cloudflared

# Check Tailscale status
docker compose exec tailscale tailscale status

# Get Tailscale IP
docker compose exec tailscale tailscale ip

# Check container resource usage
docker stats

# Check disk usage
df -h /opt /mnt/media
```

## Community & Support

- **r/selfhosted** - Reddit community for homelab enthusiasts
- **r/usenet** - Usenet-specific help and discussions
- **r/homelab** - General homelab hardware and software
- **TRaSH Guides** - https://trash-guides.info/ - Quality profile guides
- **Servarr Wiki** - https://wiki.servarr.com/ - Official *arr documentation
- **Awesome Self-Hosted** - https://github.com/awesome-selfhosted/awesome-selfhosted

---

Built with ❤️ for the homelab community.

**Stack Status:** Production-ready and feature-complete for 2025!
