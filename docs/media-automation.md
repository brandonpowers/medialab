# Media Automation Services

The *arr stack automates media management, downloading, and quality control.

## Services Overview

| Service | Purpose | Access | Port |
|---------|---------|--------|------|
| **Sonarr** | TV show automation | Private (LAN) | 8989 |
| **Radarr** | Movie automation | Private (LAN) | 7878 |
| **Lidarr** | Music automation | Private (LAN) | 8686 |
| **Prowlarr** | Indexer management | Private (LAN) | 9696 |
| **Bazarr** | Subtitle automation | Private (LAN) | 6767 |
| **Recyclarr** | Quality profile sync | CLI only | N/A |

---

## Prowlarr - Indexer Manager

**Start here first!** Prowlarr centralizes indexer management for all *arr apps.

### Initial Setup

1. **Access:** http://SERVER_IP:9696

2. **Add Indexers:**
   - Indexers → Add Indexer
   - Search for your indexer (e.g., "1337x", "NZBGeek")
   - Configure with API key (for private indexers)
   - Test and save

**Recommended Public Indexers (Torrents):**
- 1337x
- ThePirateBay
- EZTV (TV shows)
- RARBG replacements
- Nyaa (anime)

**Recommended Usenet Indexers:**
- NZBGeek (paid)
- NZBFinder
- See [Downloads documentation](downloads.md) for Usenet setup

3. **Add Applications:**
   - Settings → Apps → Add Application
   - Select Sonarr/Radarr/Lidarr
   - Configure:
     - **Prowlarr Server**: http://prowlarr:9696
     - **Application Server**: http://sonarr:8989 (or radarr/lidarr)
     - **API Key**: From respective app (Settings → General)
   - Test and save
   - Prowlarr will sync indexers automatically!

4. **Sync Indexers:**
   - Apps → Sync App Indexers
   - Indexers now appear in Sonarr/Radarr/Lidarr

---

## Sonarr - TV Show Automation

### Initial Setup

1. **Access:** http://SERVER_IP:8989

2. **Configure Download Clients:**

   Settings → Download Clients → Add (+)

   **qBittorrent:**
   - Host: `qbittorrent`
   - Port: `8080`
   - Username/Password: (from qBittorrent)
   - Category: `tv`
   - Priority: `10` (fallback)

   **SABnzbd** (if using Usenet):
   - Host: `sabnzbd`
   - Port: `8080`
   - API Key: (from SABnzbd)
   - Category: `tv`
   - Priority: `1` (preferred)

3. **Configure Media Management:**

   Settings → Media Management

   - ✅ **Rename Episodes**: Enable
   - ✅ **Replace Illegal Characters**: Enable
   - **Standard Episode Format**: `{Series Title} - S{season:00}E{episode:00} - {Episode Title}`
   - **Root Folder**: `/media/tv`

4. **Quality Profiles:**
   - Use profiles synced by Recyclarr (see below)
   - Or create custom profiles in Settings → Profiles

### Adding TV Shows

**Method 1: Via Jellyseerr (Recommended)**
- Users request shows in Jellyseerr
- Sonarr receives request automatically

**Method 2: Direct in Sonarr**
- Series → Add New
- Search for show
- Select quality profile
- Choose monitor options (all episodes, future, etc.)
- Add series

### Monitoring

- **Activity → Queue**: See current downloads
- **Calendar**: Upcoming episodes
- **History**: Download history

---

## Radarr - Movie Automation

### Initial Setup

1. **Access:** http://SERVER_IP:7878

2. **Configure Download Clients:**

   Same as Sonarr, but use category `movies`

3. **Configure Media Management:**

   Settings → Media Management

   - ✅ **Rename Movies**: Enable
   - **Standard Movie Format**: `{Movie Title} ({Release Year})`
   - **Root Folder**: `/media/movies`

4. **Quality Profiles:**
   - Use profiles synced by Recyclarr
   - Or create custom profiles in Settings → Profiles

### Adding Movies

**Method 1: Via Jellyseerr**
- Request movies in Jellyseerr

**Method 2: Direct in Radarr**
- Movies → Add New
- Search for movie
- Select quality profile
- Add movie

---

## Lidarr - Music Automation

### Initial Setup

1. **Access:** http://SERVER_IP:8686

2. **Configure Download Clients:**

   Same as Sonarr/Radarr, but use category `music`

3. **Configure Media Management:**

   Settings → Media Management

   - ✅ **Rename Tracks**: Enable
   - **Root Folder**: `/media/music`

4. **Add Artists:**
   - Artists → Add New
   - Search for artist
   - Select quality profile
   - Choose monitor options (all albums, studio only, etc.)

---

## Bazarr - Subtitle Automation

### Initial Setup

1. **Access:** http://SERVER_IP:6767

2. **Connect to Sonarr/Radarr:**

   Settings → Sonarr/Radarr

   **Sonarr:**
   - Address: `http://sonarr:8989`
   - API Key: (from Sonarr)

   **Radarr:**
   - Address: `http://radarr:7878`
   - API Key: (from Radarr)

3. **Add Subtitle Providers:**

   Settings → Providers

   Popular providers:
   - OpenSubtitles
   - Subscene
   - Addic7ed

4. **Configure Languages:**

   Settings → Languages

   - Add desired subtitle languages
   - Set default language

5. **Configure Download Settings:**

   Settings → Subtitles

   - Choose subtitle format (SRT recommended)
   - Enable hearing impaired subtitles (optional)

### Usage

Bazarr automatically:
- Scans Sonarr/Radarr libraries
- Downloads missing subtitles
- Upgrades existing subtitles when better versions found

---

## Recyclarr - Quality Profile Automation

Recyclarr syncs TRaSH Guides quality profiles to Sonarr/Radarr automatically.

### Setup

1. **Get API Keys:**
   - Sonarr: Settings → General → API Key
   - Radarr: Settings → General → API Key

2. **Add to `.env`:**
   ```bash
   SONARR_API_KEY=your_key_here
   RADARR_API_KEY=your_key_here
   ```

3. **Configuration file is already created:** `data/recyclarr/config/recyclarr.yml`

4. **Run sync:**
   ```bash
   docker compose run --rm recyclarr sync
   ```

5. **Verify in Sonarr/Radarr:**
   - Settings → Profiles
   - Should see quality profiles like "WEB-1080p", "HD-1080p"
   - Custom formats populated

### Automation

Add to cron for automatic daily sync:

```bash
crontab -e
# Add:
0 3 * * * cd /opt/homelab && docker compose run --rm recyclarr sync
```

### What Recyclarr Does

- Syncs TRaSH Guides quality profiles (community best practices)
- Sets up custom formats (prefer specific releases, codecs, etc.)
- Configures quality definitions (file size limits)
- Keeps profiles updated automatically

---

## Complete Automation Workflow

```
1. User requests content in Jellyseerr
         ↓
2. Jellyseerr → Sonarr/Radarr
         ↓
3. Sonarr/Radarr searches indexers (via Prowlarr)
         ↓
4. Best release sent to download client
         ↓
5. qBittorrent/SABnzbd downloads
         ↓
6. Sonarr/Radarr imports to /media/*
         ↓
7. Bazarr downloads subtitles
         ↓
8. Jellyfin scans and adds to library
         ↓
9. User notified, ready to stream!
```

---

## Tips & Best Practices

### Prowlarr
- Add 4-6 indexers for best coverage
- Mix public and private trackers
- Enable Usenet indexers for faster downloads
- Check indexer status regularly

### Sonarr/Radarr
- Use quality profiles from Recyclarr (TRaSH Guides)
- Monitor "Wanted" tab for missing episodes
- Set up notifications (Discord, Email, etc.)
- Regular maintenance: Delete old activity logs

### Lidarr
- Less reliable than Sonarr/Radarr (music harder to automate)
- Consider manual downloads for obscure artists
- Use MusicBrainz metadata for best results

### Bazarr
- Add multiple providers for better coverage
- Set up language priorities
- Enable "upgrade subtitles" for better quality
- Monitor failed downloads

### Recyclarr
- Run sync after *arr app updates
- Check TRaSH Guides for profile changes
- Test profiles in Sonarr/Radarr after sync
- Keep recyclarr.yml in version control

---

## Troubleshooting

### Prowlarr Not Syncing

```bash
# Check logs
docker compose logs prowlarr

# Verify API keys
# Settings → Apps → Test each app connection

# Force sync
# Apps → Sync App Indexers
```

### Downloads Not Starting

**Check indexers:**
- Prowlarr → Indexers → Verify status
- Test indexer search

**Check download clients:**
- Settings → Download Clients → Test connection
- Verify qBittorrent/SABnzbd is running

**Check search results:**
- Activity → Queue → Manual Search
- See if releases are found

### Import Failures

```bash
# Check logs
docker compose logs sonarr
docker compose logs radarr

# Common issues:
# - File permissions (fix: chmod -R 755 /mnt/media)
# - Incorrect paths (verify root folder)
# - Quality not met (adjust quality profile)
```

### Bazarr Not Downloading Subtitles

```bash
# Check provider status
Settings → Providers → Test each provider

# Check logs
docker compose logs bazarr

# Force search
Series/Movies → Select item → Search for subtitles
```

---

## Common Access URLs

| Service | URL |
|---------|-----|
| Prowlarr | http://SERVER_IP:9696 |
| Sonarr | http://SERVER_IP:8989 |
| Radarr | http://SERVER_IP:7878 |
| Lidarr | http://SERVER_IP:8686 |
| Bazarr | http://SERVER_IP:6767 |

All services accessible on your local network.
