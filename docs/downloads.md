# Download Services

Download clients for torrents and Usenet.

## Services Overview

| Service | Purpose | Access | Port |
|---------|---------|--------|------|
| **qBittorrent** | Torrent download client | Private (LAN) | 8080 |
| **SABnzbd** | Usenet download client | Private (LAN) | 8085 |

---

## qBittorrent - Torrent Client

### Initial Setup

1. **Access:** http://SERVER_IP:8080

2. **Default Credentials:**
   ```bash
   Username: admin
   Password: (check logs on first run)

   # Get password from logs:
   docker compose logs qbittorrent | grep "temporary password"
   ```

3. **Change Password:**
   - Tools → Options → Web UI → Authentication
   - Change password to something secure

4. **Configure Download Paths:**

   Tools → Options → Downloads

   - **Default Save Path**: `/downloads/complete/torrents`
   - **Keep incomplete torrents in**: `/downloads/incomplete/torrents`
   - ✅ **Append .!qB extension to incomplete files**: Enable

5. **Configure Connection:**

   Tools → Options → Connection

   - **Listening Port**: 6881
   - ✅ **Use UPnP / NAT-PMP**: Disable (using VPN)
   - **Max connections**: 500
   - **Max connections per torrent**: 100

6. **Configure BitTorrent:**

   Tools → Options → BitTorrent

   - ✅ **Enable DHT**: Yes
   - ✅ **Enable PeX**: Yes
   - ✅ **Enable Local Peer Discovery**: Yes

### Usage

**Manual Downloads:**
1. Add torrent → URL or file
2. Select category (optional)
3. Start download

**Automatic Downloads:**
- Sonarr/Radarr sends downloads automatically
- Check Activity → Queue in Sonarr/Radarr

### Categories

Create categories for organization:

Tools → Options → Downloads → Categories

- `tv` → `/downloads/complete/torrents/tv`
- `movies` → `/downloads/complete/torrents/movies`
- `music` → `/downloads/complete/torrents/music`

---

## SABnzbd - Usenet Client

### What is Usenet?

Usenet is a faster, more reliable alternative to torrents:

**Benefits:**
- ✅ Maximum download speed (no seeders needed)
- ✅ Better privacy (direct encrypted connection)
- ✅ Better retention (files available for years)
- ✅ More reliable for automation
- ✅ No seeding required

**Downsides:**
- ❌ Costs money ($10-15/month for provider)
- ❌ DMCA takedowns
- ❌ More complex setup

### Prerequisites

You need:

1. **Usenet Provider** - Recommended:
   - Newshosting ($10-15/month)
   - UsenetServer ($10-15/month)
   - Eweka (€8-12/month, EU-based)
   - Frugal Usenet ($5-7/month, budget)

2. **Usenet Indexer** (optional but recommended):
   - NZBGeek ($12-20/year)
   - DrunkenSlug (invite only)
   - NinjaCentral ($10-15/year)

### Initial Setup

1. **Access:** http://SERVER_IP:8085

2. **Setup Wizard:**
   - Select language
   - Click "Start Wizard"

3. **Add Usenet Server:**
   - **Host**: Your provider's server (e.g., `news.newshosting.com`)
   - **Port**: `563` (SSL) or `119` (non-SSL) - **Use SSL!**
   - **Username**: Your provider username
   - **Password**: Your provider password
   - **Connections**: 20-30 (check provider's limit)
   - ✅ **SSL**: Enabled
   - **Priority**: `0` (primary server)
   - **Test Server**: Should show green checkmark

4. **Configure Folders:**

   Config → Folders

   - **Temporary Download Folder**: `/downloads/incomplete/usenet`
   - **Completed Download Folder**: `/downloads/complete/usenet`

5. **Configure Categories:**

   Config → Categories

   Create categories:
   - **tv**: `/downloads/complete/usenet/tv`
   - **movies**: `/downloads/complete/usenet/movies`
   - **music**: `/downloads/complete/usenet/music`

6. **Configure Switches:**

   Config → Switches

   - ✅ **Enable HTTPS**: Yes
   - **Unwanted Extensions**: `exe, com, bat, sh`
   - ✅ **Pause Downloads on Post-Processing**: Yes

7. **Get API Key:**
   - Config → General → API Key
   - Save this for Sonarr/Radarr configuration

### Add to Sonarr/Radarr/Lidarr

In each *arr app:

1. Settings → Download Clients → Add (+)
2. Select **SABnzbd**
3. Configure:
   - **Name**: SABnzbd
   - **Host**: `sabnzbd`
   - **Port**: `8080`
   - **API Key**: (from SABnzbd Config → General)
   - **Category**: `tv` (or `movies`, `music`)
   - **Priority**: `1` (preferred over torrents)
4. Test and Save

### Download Priority

In each *arr app (Settings → Download Clients):

- **SABnzbd Priority**: `1` (try first)
- **qBittorrent Priority**: `10` (fallback)

Lower priority = tried first.

### Add Indexers to Prowlarr

See [Media Automation](media-automation.md#prowlarr) for adding Usenet indexers.

---

## Usenet vs Torrents

### When to Use Usenet

- ✅ Popular, recent content (last 3 years)
- ✅ TV shows (automated daily downloads)
- ✅ Speed is priority
- ✅ Privacy concerns

### When to Use Torrents

- ✅ Old/rare content (beyond Usenet retention)
- ✅ Free option
- ✅ Content removed from Usenet
- ✅ Niche content with dedicated seeders

**Best Practice:** Use both! SABnzbd as primary, qBittorrent as fallback.

---

## Advanced Usenet Setup

### Multiple Providers

For maximum reliability, add a backup provider on different backbone:

**SABnzbd Config → Servers → Add Server**

**Server 1 (Primary):**
- Host: `news.newshosting.com` (Highwinds backbone)
- Priority: `0`
- Connections: `30`

**Server 2 (Backup - Block Account):**
- Host: `ssl.eweka.nl` (Independent backbone)
- Priority: `1` (only used if primary fails)
- Connections: `10`

When Server 1 can't find articles (DMCA removed), Server 2 kicks in automatically.

### Usenet Providers by Backbone

| Provider | Backbone | Best For |
|----------|----------|----------|
| Newshosting | Highwinds | US users, premium |
| UsenetServer | Highwinds | US users, premium |
| Eweka | Independent | EU users, privacy |
| Frugal Usenet | Omicron | Budget option |

**Tip:** Get primary provider on one backbone, backup on different backbone for redundancy.

---

## Download Priority & Fallback

### Configuration

In Sonarr/Radarr:

Settings → Download Clients

1. SABnzbd (Usenet) - Priority 1
2. qBittorrent (Torrents) - Priority 10

### How It Works

```
1. Media requested in Jellyseerr
        ↓
2. Sonarr/Radarr searches indexers
        ↓
3. Finds releases on both Usenet and torrents
        ↓
4. Tries SABnzbd first (priority 1)
        ↓
5. If Usenet download fails → tries qBittorrent (priority 10)
        ↓
6. Download completes
```

---

## Storage Management

### Download Structure

```
/mnt/media/downloads/
├── complete/
│   ├── torrents/
│   │   ├── movies/
│   │   ├── tv/
│   │   └── music/
│   └── usenet/
│       ├── movies/
│       ├── tv/
│       └── music/
└── incomplete/
    ├── torrents/
    └── usenet/
```

### Automatic Cleanup

Sonarr/Radarr automatically remove completed downloads after import.

Manual cleanup:
```bash
# Remove old completed downloads
find /mnt/media/downloads/complete -type f -mtime +7 -delete

# Remove failed downloads
find /mnt/media/downloads/incomplete -type f -mtime +3 -delete
```

---

## Troubleshooting

### qBittorrent

**Can't connect to peers:**
```bash
# Check VPN is working (if using VPN)
# Check port forwarding
# Verify DHT is enabled

# Check logs
docker compose logs qbittorrent
```

**Slow download speeds:**
- Increase max connections
- Check seeders (low seeders = slow download)
- Verify no bandwidth limits set
- Check VPN speed (if using VPN)

**Downloads stuck:**
- Check disk space: `df -h`
- Verify file permissions: `ls -la /mnt/media/downloads`
- Restart container: `docker compose restart qbittorrent`

### SABnzbd

**Can't connect to server:**
```bash
# Verify credentials with provider
# Check SSL is enabled (port 563)
# Reduce connections to 10 (test)
# Check provider status (website)

# View logs
docker compose logs sabnzbd
```

**Downloads fail with "missing articles":**
- Content may be DMCA'd or too old
- Add backup provider on different backbone
- Check content age vs provider retention
- Try torrent fallback

**Slow download speeds:**
- Increase connections (max per provider limit)
- Check server location (EU provider for EU users)
- Verify no bandwidth throttling from ISP
- Test without VPN (Usenet already encrypted)

---

## Performance Optimization

### qBittorrent

- **Max active downloads**: 3-5 (prevents overwhelming system)
- **Max active uploads**: 5-10 (good citizenship)
- **Connection limits**: 500 total, 100 per torrent
- **Enable sequential download**: For streaming while downloading

### SABnzbd

- **Connections**: 20-30 (check provider limit)
- **Article cache**: Increase to 500MB (Config → Tuning)
- **Direct unpack**: Enable for faster extraction
- **Cleanup**: Enable auto-delete of NZB files

---

## Cost Breakdown

### Torrents Only (Free)

**Cost:** $0/year
- qBittorrent (free)
- Public indexers (free)

**Limitations:**
- Slower downloads
- Less reliable for automation
- Requires seeding

### Usenet Setup

**Monthly:**
- Usenet Provider: $10-15/month
- Indexers: $1-2/month
- **Total: $11-17/month**

**Yearly:**
- Usenet Provider: $100-150/year
- Indexers: $20-40/year
- **Total: $120-190/year** (~$10-16/month)

**Budget Option:**
- Frugal Usenet: $60/year
- 1 paid indexer: $12/year
- **Total: $72/year** (~$6/month)

---

## Security & Privacy

### qBittorrent

**With VPN:**
- Router-level VPN (ProtonVPN) already configured
- All torrent traffic encrypted
- IP hidden from peers

**Without VPN:**
- Use private trackers only
- Enable IP filtering
- Use encrypted connections only

### SABnzbd

**Usenet Security:**
- ✅ Encrypted connection (SSL/TLS) to provider
- ✅ No IP exposed to other users
- ✅ Direct connection to servers (no P2P)

**With Your Router VPN:**
- Already encrypted via ProtonVPN
- Additional layer (may be overkill)
- Can disable VPN for Usenet to improve speeds

---

## Recommended Resources

- **r/Usenet** - Reddit community for help and deals
- **r/trackers** - Private tracker information
- **NZBGeek Wiki** - Comprehensive Usenet guides
- **TRaSH Guides** - Best practices for *arr apps: https://trash-guides.info/

---

## Common Access URLs

| Service | URL |
|---------|-----|
| qBittorrent | http://SERVER_IP:8080 |
| SABnzbd | http://SERVER_IP:8085 |

Both services accessible on your local network.
