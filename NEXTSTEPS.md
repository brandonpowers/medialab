# Future Enhancements

Optional additions and ideas for your homelab media server. Your current 24-service stack is **production-ready** with all essential 2025 features.

## Immediate Optimizations

### 1. Automate Recyclarr (Recommended)
Keep quality profiles updated automatically:

```bash
# Add to crontab (run at 3 AM daily)
crontab -e

# Add this line:
0 3 * * * cd /opt/homelab && docker compose run --rm recyclarr sync >/dev/null 2>&1
```

### 2. Configure Automated Backups
Protect your configuration:

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
0 2 * * * /opt/homelab/backup.sh
```

### 3. Set Up Uptime Kuma Notifications
Get alerts when services go down:
- Settings → Notifications
- Add Discord/Telegram/Email
- Enable on all monitors

## User Experience Enhancements

### Komga - Comics & Manga Server
Beautiful web reader with progress tracking:

```yaml
komga:
  image: gotson/komga:latest
  container_name: komga
  restart: unless-stopped
  ports:
    - "25600:25600"
  environment:
    <<: *common-env
  volumes:
    - ./data/komga/config:/config
    - ${MEDIA_ROOT}/comics:/data
```

Add to Cloudflare Tunnel: `comics.glaance.io`

Create directory: `mkdir -p /mnt/media/comics`

### Homepage - Alternative Dashboard
Modern alternative to Homarr with widgets:

```yaml
homepage:
  image: ghcr.io/gethomepage/homepage:latest
  container_name: homepage
  restart: unless-stopped
  ports:
    - "3003:3000"
  environment:
    <<: *common-env
  volumes:
    - ./data/homepage/config:/app/config
    - /var/run/docker.sock:/var/run/docker.sock:ro
```

More customizable than Homarr, integrates with service APIs.

## Storage & Performance

### Unpackerr - Automatic Archive Extraction
Extracts .rar/.zip files from downloads automatically:

```yaml
unpackerr:
  image: golift/unpackerr:latest
  container_name: unpackerr
  restart: unless-stopped
  environment:
    <<: *common-env
    UN_SONARR_0_URL: http://sonarr:8989
    UN_SONARR_0_API_KEY: ${SONARR_API_KEY}
    UN_RADARR_0_URL: http://radarr:7878
    UN_RADARR_0_API_KEY: ${RADARR_API_KEY}
  volumes:
    - ${MEDIA_ROOT}/downloads:/downloads
```

No more manual extraction!

### Optimize Tdarr Settings
Fine-tune transcoding for best results:
- **Schedule:** Only run 1 AM - 6 AM (avoid peak streaming)
- **Quality:** Use CRF 23 for H.265 (balances size/quality)
- **Skip recent:** Don't transcode files less than 7 days old
- **Monitor savings:** Dashboard shows space reclaimed

## Privacy & Security

### Authelia - Single Sign-On with 2FA
Add 2FA to all your public services:

```yaml
authelia:
  image: authelia/authelia:latest
  container_name: authelia
  restart: unless-stopped
  ports:
    - "9091:9091"
  environment:
    TZ: ${TZ}
  volumes:
    - ./data/authelia/config:/config
```

Then configure Cloudflare Access to use Authelia for authentication.

**Benefits:**
- One login for all services
- TOTP 2FA (Google Authenticator, etc.)
- WebAuthn support (YubiKey, FaceID, etc.)
- Per-service access policies

## Advanced Features

### Navidrome - Advanced Music Server
Alternative to Jellyfin's music features with better mobile apps:

```yaml
navidrome:
  image: deluan/navidrome:latest
  container_name: navidrome
  restart: unless-stopped
  ports:
    - "4533:4533"
  environment:
    <<: *common-env
    ND_SCANSCHEDULE: 1h
    ND_LOGLEVEL: info
  volumes:
    - ./data/navidrome:/data
    - ${MEDIA_ROOT}/music:/music:ro
```

Mobile apps: **Symfonium** (Android), **play:Sub** (iOS)

### Whisparr - Adult Content Management
Like Sonarr/Radarr but for adult content (if desired):

```yaml
whisparr:
  image: ghcr.io/hotio/whisparr:nightly
  container_name: whisparr
  restart: unless-stopped
  ports:
    - "6969:6969"
  environment:
    <<: *common-env
  volumes:
    - ./data/whisparr/config:/config
    - *common-vol
```

Integrates with Prowlarr and download clients like other *arr apps.

## Download Optimization

### Swap qBittorrent for Deluge or Transmission
If you prefer different torrent clients:

**Deluge** (more plugins):
```yaml
deluge:
  image: lscr.io/linuxserver/deluge:latest
  container_name: deluge
  restart: unless-stopped
  ports:
    - "8112:8112"
    - "6881:6881"
    - "6881:6881/udp"
  environment:
    <<: *common-env
  volumes:
    - ./data/deluge/config:/config
    - ${MEDIA_ROOT}/downloads:/downloads
```

**Transmission** (lightweight):
```yaml
transmission:
  image: lscr.io/linuxserver/transmission:latest
  container_name: transmission
  restart: unless-stopped
  ports:
    - "9091:9091"
    - "51413:51413"
    - "51413:51413/udp"
  environment:
    <<: *common-env
  volumes:
    - ./data/transmission/config:/config
    - ${MEDIA_ROOT}/downloads:/downloads
```

### Add Multiple Usenet Providers
For maximum availability:
- **Primary:** Newshosting/UsenetServer (Highwinds backbone)
- **Backup:** Eweka (independent backbone)

Add backup provider in SABnzbd with priority 1 (tried when primary fails).

## Automation

### Watchtower - Auto-Update Containers
Automatically update Docker images (use with caution):

```yaml
watchtower:
  image: containrrr/watchtower:latest
  container_name: watchtower
  restart: unless-stopped
  environment:
    - WATCHTOWER_CLEANUP=true
    - WATCHTOWER_SCHEDULE=0 0 4 * * *  # 4 AM daily
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
```

**Safer alternative:** Use Diun for notifications only, update manually.

### Diun - Update Notifications
Get notified of available updates without auto-updating:

```yaml
diun:
  image: crazymax/diun:latest
  container_name: diun
  restart: unless-stopped
  environment:
    - TZ=${TZ}
    - DIUN_WATCH_SCHEDULE=0 */6 * * *  # Check every 6 hours
    - DIUN_NOTIF_DISCORD_WEBHOOKURL=${DISCORD_WEBHOOK}
  volumes:
    - ./data/diun:/data
    - /var/run/docker.sock:/var/run/docker.sock:ro
```

## Network Alternatives

### Gluetun - Container-Level VPN
Route only downloads through VPN (Jellyfin direct for speed):

```yaml
gluetun:
  image: qmcgaw/gluetun:latest
  container_name: gluetun
  restart: unless-stopped
  cap_add:
    - NET_ADMIN
  devices:
    - /dev/net/tun:/dev/net/tun
  ports:
    - "8080:8080"  # qBittorrent
    - "8085:8085"  # SABnzbd
  environment:
    - VPN_SERVICE_PROVIDER=protonvpn
    - OPENVPN_USER=${PROTONVPN_USERNAME}
    - OPENVPN_PASSWORD=${PROTONVPN_PASSWORD}
  volumes:
    - ./data/gluetun:/gluetun

qbittorrent:
  network_mode: "service:gluetun"
  depends_on:
    - gluetun

sabnzbd:
  network_mode: "service:gluetun"
  depends_on:
    - gluetun
```

Then disable router-level VPN for better streaming performance.

## Media Organization

### Tips for Optimal Library Structure

**Movies:**
```
/media/movies/
  Movie Title (Year)/
    Movie Title (Year).mkv
```

**TV Shows:**
```
/media/tv/
  Show Name/
    Season 01/
      Show Name - S01E01 - Episode Title.mkv
```

**Audiobooks:**
```
/media/audiobooks/
  Author Name/
    Book Title/
      01 - Chapter 1.mp3
```

**E-books:**
```
/media/books/
  Author Name/
    Book Title.epub
```

Use Sonarr/Radarr's "Rename" feature to auto-organize.

## What NOT to Add

Things to avoid to keep your stack lean:

❌ **Plex** - You have Jellyfin (open-source, no paywalls)
❌ **Emby** - Same as Plex
❌ **Prometheus/Grafana** - Overkill for homelab unless you love metrics
❌ **Netdata** - Uptime Kuma is sufficient for monitoring
❌ **Multiple dashboards** - Pick one (Homarr or Homepage)
❌ **Duplicate *arr apps** - One of each is enough

## Questions to Ask Before Adding

1. **Will I actually use this?** - Don't add services "just because"
2. **Does it solve a problem I have?** - Be intentional
3. **Do I have the resources?** - CPU/RAM/storage sufficient?
4. **Can I maintain it?** - More services = more updates

## Your Stack is Complete!

Remember: Your current 24 services include all essential 2025 features:
- ✅ Privacy-first remote access
- ✅ Rich media types (movies, TV, music, audiobooks, podcasts, e-books)
- ✅ Full automation (*arr stack with quality management)
- ✅ Dual downloads (Usenet + torrents)
- ✅ Storage optimization (Tdarr)
- ✅ Monitoring (Uptime Kuma)

Everything above is **optional**. Focus on using what you have!

## Resources

- **r/selfhosted** - Homelab community
- **r/usenet** - Usenet help
- **TRaSH Guides** - https://trash-guides.info/
- **Servarr Wiki** - https://wiki.servarr.com/
- **Awesome Self-Hosted** - https://github.com/awesome-selfhosted/awesome-selfhosted
