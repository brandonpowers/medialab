# Automated Service Configuration

This guide explains how to use the automated configuration script to link all services together via API calls.

## What Gets Automated

The `configure-services.sh` script automates the following:

### ✅ Automatically Configured

1. **Prowlarr** (Indexer Management)
   - Adds FlareSolverr proxy for Cloudflare-protected sites
   - Adds qBittorrent as download client
   - Adds SABnzbd as download client (if configured)

2. **Sonarr** (TV Shows)
   - Creates root folder at `/media/tv`
   - Adds qBittorrent download client with category `tv`
   - Adds SABnzbd download client (if configured)
   - Links to Prowlarr for automatic indexer sync

3. **Radarr** (Movies)
   - Creates root folder at `/media/movies`
   - Adds qBittorrent download client with category `movies`
   - Adds SABnzbd download client (if configured)
   - Links to Prowlarr for automatic indexer sync

4. **Lidarr** (Music)
   - Creates root folder at `/media/music`
   - Adds qBittorrent download client with category `music`
   - Links to Prowlarr for automatic indexer sync

5. **Bazarr** (Subtitles)
   - Links to Sonarr
   - Links to Radarr
   - *Note: May require additional manual configuration*

6. **Recyclarr** (Quality Profiles)
   - Syncs TRaSH Guides quality profiles to Sonarr
   - Syncs TRaSH Guides quality profiles to Radarr
   - Applies custom formats for better quality management

7. **API Keys**
   - Automatically extracts API keys from service config files
   - Updates `.env` with Sonarr and Radarr API keys
   - Enables Recyclarr to work immediately

## Usage

### Step 1: Initial Deployment

First, deploy your homelab stack:

```bash
cd /opt/homelab
./scripts/setup-homelab.sh
```

This will:
- Create all data directories
- Generate `.env` file with secure encryption key
- Start all 15 Docker services
- Wait for services to initialize

### Step 2: Wait for Services to Start

Wait ~2-3 minutes for all services to fully initialize and generate their API keys.

```bash
# Check service status
docker compose ps

# All services should show "Up (healthy)" or "Up"
```

### Step 3: Run Configuration Script

```bash
cd /opt/homelab
./scripts/configure-services.sh
```

This will:
- Wait for all services to become ready
- Extract API keys from service configs
- Configure download clients in each *arr app
- Link Prowlarr to all *arr apps
- Link Bazarr to Sonarr/Radarr
- Run Recyclarr to sync quality profiles
- Update `.env` with API keys

**Total time:** ~5-10 minutes

## What Still Requires Manual Setup

### 🔧 Manual Configuration Required

1. **Prowlarr - Add Indexers**
   - URL: `http://SERVER_IP:9696`
   - Add torrent/usenet indexers manually
   - FlareSolverr is already configured for protected sites
   - Once added, they auto-sync to all *arr apps

2. **qBittorrent - Change Password**
   - URL: `http://SERVER_IP:8080`
   - Default credentials: `admin` / `adminadmin`
   - Change password in Settings → Web UI

3. **SABnzbd - Add Usenet Servers** (Optional)
   - URL: `http://SERVER_IP:8085`
   - Complete initial wizard
   - Add your Usenet provider servers
   - Copy API key to `.env` as `SABNZBD_API_KEY`
   - Re-run: `./scripts/configure-services.sh`

4. **Jellyfin - Initial Setup**
   - URL: `http://SERVER_IP:8096`
   - Create admin account
   - Add media libraries:
     - Movies: `/media/movies`
     - TV Shows: `/media/tv`
     - Music: `/media/music`

5. **Jellyseerr - Link to Jellyfin**
   - URL: `http://SERVER_IP:5055`
   - Sign in with Jellyfin account
   - Configure Sonarr connection (API key already in `.env`)
   - Configure Radarr connection (API key already in `.env`)

6. **Cloudflare Tunnel - Configure Routes** (Optional)
   - See: [Networking Guide](networking.md#cloudflare-tunnel-setup)
   - Add public hostnames for:
     - Jellyfin
     - Jellyseerr
     - Homarr

## Environment Variables

### Required Variables (Generated Automatically)

```bash
# System
TZ=America/Chicago
PUID=1000
PGID=1000
MEDIA_ROOT=/mnt/media

# Homarr (auto-generated encryption key)
HOMARR_ENCRYPTION_KEY=<generated>
```

### Required Variables (You Must Provide)

```bash
# Remote Access
CLOUDFLARE_TUNNEL_TOKEN=eyJ...

# API Keys
TMDB_API_KEY=<your_key>
```

### Optional Variables (Auto-Populated by Script)

```bash
# Auto-extracted from service configs
SONARR_API_KEY=<extracted>
RADARR_API_KEY=<extracted>

# Optional Usenet
SABNZBD_API_KEY=<manual>
```

## Verification

After running `configure-services.sh`, verify everything is linked:

### Check Prowlarr

```bash
# Should show Sonarr, Radarr, Lidarr
curl -s "http://localhost:9696/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" | jq '.[].name'
```

### Check Sonarr Download Clients

```bash
# Should show qBittorrent (and SABnzbd if configured)
curl -s "http://localhost:8989/api/v3/downloadclient" \
  -H "X-Api-Key: $SONARR_API_KEY" | jq '.[].name'
```

### Check Recyclarr Sync

```bash
# Manually trigger sync
docker compose run --rm recyclarr sync

# Check logs
docker compose logs recyclarr
```

## Troubleshooting

### API Keys Not Found

If the script can't extract API keys:

```bash
# Check service is running and healthy
docker compose ps

# Restart services to generate configs
docker compose restart sonarr radarr lidarr

# Wait 2-3 minutes and try again
./scripts/configure-services.sh
```

### Download Client Connection Failed

If *arr apps can't connect to qBittorrent:

```bash
# Check qBittorrent is running
docker compose ps qbittorrent

# Check default password hasn't been changed yet
# Username: admin
# Password: adminadmin

# If you changed it, update the script or add manually via UI
```

### Prowlarr Apps Not Syncing

If Prowlarr → *arr sync fails:

1. Check API keys are correct in `.env`
2. Verify services can reach each other:
   ```bash
   docker compose exec sonarr ping -c 3 prowlarr
   ```
3. Manually test Prowlarr → Sonarr sync:
   - Prowlarr → Settings → Apps → Sonarr → Test

### Recyclarr Sync Failed

If quality profiles don't sync:

```bash
# Check API keys in .env
cat .env | grep API_KEY

# Verify services are reachable
docker compose exec recyclarr ping -c 3 sonarr

# Check Recyclarr logs
docker compose logs recyclarr

# Manually run with verbose output
docker compose run --rm recyclarr sync --debug
```

## Re-running the Script

The script is idempotent - safe to run multiple times. It will:
- Skip existing configurations (warnings like "may already exist")
- Update API keys if they changed
- Re-sync quality profiles

```bash
# Safe to re-run anytime
./scripts/configure-services.sh
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    configure-services.sh                    │
└─────────────────────────────────────────────────────────────┘
                             │
    ┌────────────────────────┼────────────────────────┐
    ▼                        ▼                        ▼
┌─────────┐            ┌──────────┐            ┌──────────┐
│Prowlarr │◄───────────┤  Sonarr  │            │  Radarr  │
│         │            │          │            │          │
│ Syncs   │◄─────┐     │  TV/API  │            │Movies/API│
│Indexers │      │     └────┬─────┘            └────┬─────┘
└────┬────┘      │          │                       │
     │           │          ▼                       ▼
     │      ┌────┴────┐   ┌──────────────┐   ┌──────────────┐
     │      │ Lidarr  │   │ qBittorrent  │   │   SABnzbd    │
     │      │         │   │   (Torrent)  │   │   (Usenet)   │
     │      │Music/API│   └──────────────┘   └──────────────┘
     │      └────┬────┘
     │           │
     │           │
     ▼           ▼
┌──────────────────────────┐
│     FlareSolverr         │
│  (Cloudflare Bypass)     │
└──────────────────────────┘

                 │
                 ▼
          ┌────────────┐
          │  Bazarr    │
          │ (Subtitles)│
          └────────────┘
                 │
                 ▼
          ┌────────────┐
          │ Recyclarr  │
          │ (Quality)  │
          └────────────┘
```

## Next Steps

After automated configuration:

1. **[Add Indexers to Prowlarr](media-automation.md#prowlarr-setup)** - Required for content discovery
2. **[Configure Jellyfin Libraries](media-streaming.md#jellyfin-setup)** - Point to media folders
3. **[Link Jellyseerr](media-streaming.md#jellyseerr-setup)** - User-friendly request system
4. **[Set Up Remote Access](networking.md)** - Cloudflare Tunnel (optional)
5. **[Test ARM Disc Ripping](../README.md#blu-ray-ripping)** - Insert a disc to verify

## Benefits of Automation

**Before** (Manual Setup):
- ⏱️ 2-3 hours of clicking through UIs
- 🔑 Copying/pasting API keys between 10+ pages
- 📝 Easy to miss a setting or connection
- 🔁 Hard to replicate on new installs

**After** (Automated Script):
- ⏱️ 5-10 minutes hands-free
- 🤖 All services linked automatically
- ✅ Consistent configuration every time
- 🔁 Easy to replicate and share

## See Also

- [Setup Guide](../README.md#automated-deployment) - Initial deployment
- [Media Automation](media-automation.md) - How *arr apps work
- [Downloads](downloads.md) - qBittorrent and SABnzbd configuration
- [Networking](networking.md) - Remote access setup
