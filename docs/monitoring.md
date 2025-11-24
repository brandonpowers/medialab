# Monitoring & Management Services

Services for monitoring, managing, and optimizing your homelab.

## Services Overview

| Service | Purpose | Access | Port |
|---------|---------|--------|------|
| **Uptime Kuma** | Service monitoring and uptime tracking | Private (Tailscale) | 3001 |
| **Tdarr** | Automated video transcoding | Private (Tailscale) | 8265 |

---

## Uptime Kuma - Service Monitoring

Monitor all your services and get alerts when they go down.

### Features

- HTTP(s) monitoring
- TCP/UDP port monitoring
- Ping monitoring
- DNS monitoring
- Docker container monitoring
- SSL certificate expiry monitoring
- Notifications (Discord, Telegram, Email, Slack, etc.)
- Public status pages
- Uptime statistics
- Response time graphs

### Initial Setup

1. **Access:** http://homelab-media:3001 (via Tailscale)

2. **First Time Setup:**
   - Create admin account
   - Set username and password
   - Complete setup

3. **Add Monitors:**

   Click **Add New Monitor**

   **For Each Service:**
   - **Monitor Type**: HTTP(s)
   - **Friendly Name**: Service name (e.g., "Jellyfin")
   - **URL**: Internal Docker URL (e.g., `http://jellyfin:8096`)
   - **Heartbeat Interval**: 60 seconds
   - **Retries**: 3
   - **Max Redirects**: 10
   - Click **Save**

### Recommended Monitors

**Public Services:**
```
Jellyfin → http://jellyfin:8096
Jellyseerr → http://jellyseerr:5055
Homarr → http://homarr:7575
Audiobookshelf → http://audiobookshelf:80
Calibre-Web → http://calibre-web:8083
Immich → http://immich-server:3001
```

**Admin Services:**
```
Sonarr → http://sonarr:8989
Radarr → http://radarr:7878
Lidarr → http://lidarr:8686
Prowlarr → http://prowlarr:9696
Bazarr → http://bazarr:6767
qBittorrent → http://qbittorrent:8080
SABnzbd → http://sabnzbd:8080
ARM (Blu-ray Ripper) → http://arm:8090
```

**Backend Services:**
```
PostgreSQL → tcp://postgres:5432
Redis → tcp://redis:6379
```

**Network Services:**
```
Cloudflare Tunnel → Check tunnel status page
Tailscale → Check admin console
```

### Notifications

**Set Up Notifications:**

1. Settings → Notifications
2. Click **Add New Notification**
3. Select notification type

**Popular Options:**

**Discord:**
- Create webhook in Discord server settings
- Paste webhook URL
- Test notification

**Email:**
- SMTP hostname (e.g., smtp.gmail.com)
- Port: 587 (STARTTLS)
- Username and password
- From and to addresses

**Telegram:**
- Create bot with @BotFather
- Get bot token and chat ID
- Configure in Uptime Kuma

**Gotify:**
- Self-hosted notification service
- Install Gotify separately if desired

4. **Enable Notifications Per Monitor:**
   - Edit monitor
   - Select notification methods
   - Configure when to notify (down, up, certificate expiry)

### Status Pages

**Create Public Status Page:**

1. Status Pages → **Add Status Page**
2. **Title**: Your Homelab Status
3. **Slug**: Custom URL path
4. Select monitors to include
5. Customize:
   - Theme (light/dark)
   - Show/hide monitor tags
   - Custom CSS
6. **Save**

**Share Status Page:**
- Public URL: `http://homelab-media:3001/status/your-slug`
- Share with family/friends
- No login required
- Shows real-time status

### Maintenance Windows

**Schedule Maintenance:**
1. Maintenance → **Add Maintenance**
2. Set start and end time
3. Select affected monitors
4. Notifications paused during maintenance

---

## Tdarr - Automated Transcoding

Automate video transcoding to save storage space and optimize for streaming.

### Features

- Automated H.265 (HEVC) conversion
- Hardware transcoding (Intel QuickSync, NVIDIA, AMD)
- Scheduled transcoding
- Health checks (find corrupt files)
- File size reduction (30-50% typical)
- Configurable quality settings
- Plugin system
- Statistics dashboard

### Initial Setup

1. **Access:** http://homelab-media:8265 (via Tailscale)

2. **First Time Setup:**
   - Complete welcome wizard
   - Accept defaults for most options

3. **Add Libraries:**

   Libraries → **Add Library**

   **Movies:**
   - **Source**: `/media/movies`
   - **Cache**: `/temp`
   - **Output**: Same as source (replace original)
   - **Schedule**: Overnight (1 AM - 6 AM)
   - **Priority**: Low

   **TV Shows:**
   - **Source**: `/media/tv`
   - **Cache**: `/temp`
   - **Output**: Same as source
   - **Schedule**: Overnight
   - **Priority**: Low

4. **Configure Transcode Settings:**

   Libraries → Select library → **Transcode Options**

   **Plugin Flow:**
   - **Check Video Codec**: If not H.265 → Transcode
   - **Transcode to H.265**: Using hardware acceleration
   - **Check Audio Codec**: Keep audio as-is (or transcode to AAC)
   - **Health Check**: Remove corrupt files

### Transcode Plugins

**Recommended Plugins:**

**Video:**
- `Migz-Transcode using GPU` - Hardware H.265 encoding
- `Migz-Check video codec` - Skip if already H.265
- `Migz-Set video options` - CRF 23, medium preset

**Audio:**
- `Migz-Keep one audio stream` - Remove extra audio tracks
- `Migz-Normalize audio` - Consistent volume

**Health Check:**
- `Check file health` - Find corrupt files
- `Check file readability` - Verify file integrity

### Hardware Acceleration

Tdarr uses Intel QuickSync GPU for transcoding:

**Verify GPU Access:**
```bash
docker exec tdarr ls -la /dev/dri/
# Should see renderD128
```

**Enable Hardware Encoding:**
- Libraries → Transcode Options → Use GPU
- Plugins → Select GPU plugin
- **Encoder**: h265_qsv (Intel QuickSync)

### Scheduling

**Set Transcode Schedule:**

Libraries → Select library → **Schedule**

**Recommended:**
- **Start**: 1:00 AM
- **End**: 6:00 AM
- **Days**: Every day
- **Priority**: Low (doesn't impact streaming)

**Why overnight?**
- Transcoding is CPU/GPU intensive
- Avoid during streaming hours
- Prevents buffering for users

### Statistics

**Monitor Progress:**

Dashboard shows:
- **Files processed**: Total files transcoded
- **Space saved**: GB saved
- **Processing queue**: Files waiting
- **Active workers**: Current transcodes

**Savings Example:**
- Original: 10 GB movie (H.264)
- Transcoded: 5 GB movie (H.265)
- **Savings: 50%** (5 GB)

### Workers

**Configure Workers:**

Settings → Workers

- **CPU Workers**: 1 (transcoding is intensive)
- **GPU Workers**: 1 (if GPU available)
- **Transcode limit**: 1 (avoid overload)

### Quality Settings

**Constant Rate Factor (CRF):**
- **CRF 18**: Near lossless (large files)
- **CRF 23**: Balanced (recommended)
- **CRF 28**: Smaller files (lower quality)

**Preset:**
- **Slow**: Better quality, slower
- **Medium**: Balanced (recommended)
- **Fast**: Faster, larger files

### Best Practices

1. **Don't transcode everything** - Skip files less than 7 days old
2. **Test settings** - Transcode one file first, verify quality
3. **Backup originals** - Keep originals until verified
4. **Schedule wisely** - Only run overnight
5. **Monitor stats** - Track space savings
6. **GPU acceleration** - Much faster than CPU
7. **CRF 23** - Good balance of quality and size

---

## Integration

### Uptime Kuma + Notifications

**Discord Bot:**
- Get notifications in Discord channel
- See when services go down/up
- Monitor from anywhere

**Status Page:**
- Share with family
- See service status at a glance
- No login required

### Tdarr + Storage Management

**Automatic Optimization:**
- Reduce storage usage by 30-50%
- Better streaming performance (smaller files)
- Consistent quality across library

---

## Troubleshooting

### Uptime Kuma

**Monitor shows false positives:**
```bash
# Check service is actually accessible
curl http://jellyfin:8096

# Increase timeout in monitor settings
# Increase retries to 5

# Check Uptime Kuma logs
docker compose logs uptime-kuma
```

**Notifications not working:**
- Test notification in settings
- Check webhook URLs are correct
- Verify bot tokens/credentials
- Check firewall rules

### Tdarr

**Transcoding not starting:**
```bash
# Check logs
docker compose logs tdarr

# Verify GPU access (if using)
docker exec tdarr ls -la /dev/dri/

# Check schedule is active
# Libraries → Schedule → Verify times
```

**Slow transcoding:**
- Enable hardware acceleration (GPU)
- Reduce worker count to 1
- Lower preset (fast instead of slow)
- Check CPU usage: `docker stats tdarr`

**Corrupt output files:**
- Increase CRF (lower quality, more reliable)
- Change preset to medium/slow
- Test hardware encoder
- Check source files are valid

---

## Performance Optimization

### Uptime Kuma

- **Moderate check intervals**: 60 seconds is fine
- **Disable unnecessary monitors**: Only monitor critical services
- **Database maintenance**: Prune old data regularly

### Tdarr

- **One transcode at a time**: Prevents overload
- **Schedule overnight**: Avoid peak usage
- **Use GPU**: 10x faster than CPU
- **Skip recent files**: Don't transcode new downloads
- **Monitor disk I/O**: Transcoding is disk-intensive

---

## Common Access URLs

| Service | URL |
|---------|-----|
| Uptime Kuma | http://homelab-media:3001 |
| Tdarr | http://homelab-media:8265 |

All services accessible only via Tailscale VPN for security.
