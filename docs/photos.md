# Photo Management - Immich

Self-hosted photo and video backup solution (Google Photos alternative).

## Service Overview

| Service | Purpose | Access | Port |
|---------|---------|--------|------|
| **Immich Server** | Photo/video backup and management | Public (Cloudflare) | 2283 |
| **Immich ML** | Machine learning for face detection | Internal | N/A |

---

## Immich - Photo & Video Backup

### Features

- ✅ Automatic photo/video backup from mobile devices
- ✅ Face recognition with ML-powered people detection
- ✅ Smart search (search by objects, places, dates, people)
- ✅ Album creation and sharing
- ✅ Mobile apps (iOS and Android)
- ✅ Live photos support (iOS)
- ✅ RAW format support
- ✅ Video transcoding and optimization
- ✅ Timeline view
- ✅ Map view (geotagged photos)
- ✅ Duplicate detection

### Initial Setup

1. **Access:**
   - Public: https://photos.yourdomain.com
   - Local: http://CT-IP:2283

2. **First Time Setup:**
   - Open Immich for the first time
   - Create admin account (email + password)
   - Complete welcome wizard

3. **Storage Location:**

   Photos are stored in: `/mnt/media/photos/`

   Create directory if it doesn't exist:
   ```bash
   mkdir -p /mnt/media/photos
   chmod -R 755 /mnt/media/photos
   ```

### Mobile App Setup

1. **Download Immich App:**
   - **iOS**: https://apps.apple.com/app/immich/id1613945652
   - **Android**: https://play.google.com/store/apps/details?id=app.alextran.immich

2. **Connect to Server:**
   - Open app
   - **Server URL**: `https://photos.yourdomain.com`
   - Login with admin credentials (or create user account)

3. **Enable Automatic Backup:**
   - Settings → Backup
   - ✅ **Automatic backup**: Enable
   - Select albums/folders to backup
   - Choose backup frequency (immediate, daily, etc.)
   - **Upload quality**: Original quality (recommended)

4. **Configure Backup Settings:**
   - **Background backup**: Enable (iOS/Android)
   - **Require WiFi**: Enable (save mobile data)
   - **Require charging**: Optional
   - **Include videos**: Yes

---

## Features & Usage

### Photo Management

**Timeline View:**
- Chronological view of all photos
- Scroll through years, months, days
- Zoom to adjust thumbnail size

**Search:**
- Search by date: "December 2023"
- Search by object: "dog", "car", "sunset"
- Search by place: "Paris", "beach"
- Search by person: Select face from People view

**Favorites:**
- Star photos to add to favorites
- Quick access from sidebar
- Favorite albums

### Albums

**Create Album:**
1. Select photos (long press on mobile, click on web)
2. Click "Add to Album"
3. Create new album or add to existing
4. Name album and add description

**Share Album:**
1. Open album
2. Click share icon
3. Generate share link
4. Set permissions (view only, add photos, etc.)
5. Share link with family/friends

**Public Albums:**
- Create public link for album
- No login required for viewers
- Password protection (optional)

### People (Face Recognition)

**Enable Face Detection:**
- Settings → Machine Learning
- ✅ **Enable face detection**: Yes
- Immich ML container processes photos automatically

**Manage People:**
1. Go to "People" tab
2. Immich detects and groups faces
3. Name each person
4. Merge duplicates if needed
5. Click person to see all their photos

**Performance Note:** Face detection is CPU-intensive. It runs in the background and may take time for large libraries.

### Map View

**View Photos by Location:**
- Click "Map" tab
- See geotagged photos on map
- Zoom and pan to explore
- Click markers to view photos

**Note:** Only works for photos with GPS data (most smartphone photos).

### Memories

Immich automatically creates:
- "On this day" memories (photos from past years)
- Trip compilations
- People highlights

Access from home screen.

---

## User Management

**Create Users:**
1. Admin Settings → Users
2. Click "Create User"
3. Set email and password
4. Configure storage quota (optional)
5. Set permissions

**User Permissions:**
- Upload photos
- Create albums
- Share albums
- Access to shared albums

**Family Sharing:**
- Create account for each family member
- Share albums with specific users
- Set up shared libraries

---

## Advanced Features

### External Libraries

Add existing photo directories without uploading:

1. Settings → Libraries
2. Create external library
3. Set path (must be accessible to container)
4. Scan library

Useful for importing existing photo collections.

### Partner Sharing

Share entire library with partner:

1. Settings → Partner Sharing
2. Select user to share with
3. Partner can view all your photos
4. Two-way sharing option

### Archive

Hide photos without deleting:
- Select photos → Archive
- Photos removed from timeline
- Access archived photos from Archive tab

---

## Storage Management

### Storage Estimates

- **Photos (JPEG)**: 2-5 MB each
- **RAW photos**: 20-50 MB each
- **Videos (1080p)**: 100-200 MB per minute
- **Videos (4K)**: 300-500 MB per minute

**Example:**
- 10,000 photos ≈ 20-50 GB
- 1,000 videos (5 min each) ≈ 500 GB - 2.5 TB

### Disk Space Monitoring

```bash
# Check photos directory size
du -sh /mnt/media/photos

# Check available space
df -h /mnt/media
```

### Automatic Cleanup

Settings → Transcoding → Video Transcoding
- Enable video transcoding to save space
- Convert to H.265 (HEVC)
- Saves 30-50% storage

---

## Backup Strategy

**Immich is your backup**, but consider backing up the backup:

### Backup Options

**Option 1: External Hard Drive**
```bash
# Backup photos to external drive
rsync -av /mnt/media/photos/ /mnt/external-backup/photos/
```

**Option 2: Cloud Storage**
- rclone to Backblaze B2
- rclone to Google Drive
- rclone to AWS S3

**Option 3: NAS**
```bash
# Sync to NAS
rsync -av /mnt/media/photos/ user@nas:/backups/photos/
```

### Immich Database Backup

PostgreSQL database includes metadata:

```bash
# Backup Immich database
docker exec postgres pg_dump -U homelab immich > immich-backup-$(date +%Y%m%d).sql

# Restore database
cat immich-backup-20240115.sql | docker exec -i postgres psql -U homelab immich
```

---

## Performance Optimization

### Machine Learning

**Face detection is CPU-intensive:**

Settings → Machine Learning

- **Adjust face detection sensitivity** (lower = faster)
- **Schedule ML jobs** (run overnight)
- **Disable face detection** (on low-power systems)

### Transcoding

**Video transcoding improves streaming:**

Settings → Video Transcoding

- **Enable hardware acceleration** (if GPU available)
- **Set target resolution** (1080p for most devices)
- **H.265 codec** (better compression)

### Thumbnail Generation

Immich generates thumbnails automatically:
- Small thumbnail: Quick loading
- Large preview: Better quality
- Original: Full resolution

Thumbnails stored in `/mnt/media/photos/thumbs/`

---

## Troubleshooting

### App Won't Connect

```bash
# Check Immich is running
docker compose ps immich-server

# Check Cloudflare Tunnel
docker compose logs cloudflared

# Test web access first
# Open https://photos.yourdomain.com in browser
```

**If web works but app doesn't:**
- Verify server URL in app (https, not http)
- Check for typos in URL
- Try on WiFi vs mobile data

### Upload Failures

**Check storage space:**
```bash
df -h /mnt/media
```

**Check logs:**
```bash
docker compose logs immich-server
```

**Common causes:**
- Disk full
- Permissions issue
- Network interruption (retry upload)

### Face Detection Not Working

```bash
# Check ML container is running
docker compose ps immich-machine-learning

# Check logs
docker compose logs immich-machine-learning

# Restart ML container
docker compose restart immich-machine-learning
```

**Performance:**
- Face detection takes time (be patient)
- CPU-intensive (low-power systems may struggle)
- Check progress in Settings → Jobs

### Slow Performance

**For large libraries (>50,000 photos):**

1. **Enable Redis caching** (already configured)
2. **Use PostgreSQL** (already configured)
3. **Increase container resources:**
   ```yaml
   # In docker-compose.yml (if needed)
   immich-server:
     deploy:
       resources:
         limits:
           cpus: '2'
           memory: 4G
   ```

4. **Disable ML features** (if not needed)
5. **Use SSD for storage** (if possible)

---

## Mobile App Features

### Background Backup

- Automatically uploads new photos
- Works when app is closed
- Requires proper permissions:
  - iOS: Allow "Always" location access
  - Android: Allow background activity

### Selective Backup

Choose specific albums to backup:
- Settings → Backup → Select albums
- Exclude screenshots, downloads, etc.
- Save mobile storage

### Offline Access

- Favorite photos/albums
- Download for offline viewing
- Syncs when back online

### Sharing

- Share photos/albums from app
- Generate share links
- QR code sharing

---

## Privacy & Security

### Data Privacy

- ✅ **Self-hosted** - Your photos never leave your server
- ✅ **No cloud processing** - ML runs locally
- ✅ **No third-party access** - Complete control

### Security Best Practices

1. **Strong passwords** - Use unique password for admin
2. **HTTPS only** - Cloudflare Tunnel provides SSL
3. **User permissions** - Limit access appropriately
4. **Regular backups** - Protect against data loss
5. **Update regularly** - Keep Immich updated

### Shared Albums

When sharing albums:
- Public links: Anyone with link can view
- Password protect sensitive albums
- Revoke share links when no longer needed

---

## Comparison with Google Photos

| Feature | Immich | Google Photos |
|---------|--------|---------------|
| **Storage** | Unlimited (your hardware) | 15 GB free, paid after |
| **Privacy** | 100% private | Data used for ads/ML |
| **Cost** | Server hardware + electricity | Free tier, $1.99+/month |
| **Face Recognition** | Yes (local) | Yes (cloud) |
| **Search** | Yes (local ML) | Yes (cloud ML) |
| **Mobile Apps** | Yes | Yes |
| **Sharing** | Yes | Yes |
| **Video Backup** | Yes | Yes |
| **RAW Support** | Yes | Limited |

---

## Tips & Best Practices

1. **Original quality** - Always backup in original quality
2. **Regular backups** - Backup the `/media/photos` directory
3. **Start fresh** - Don't import entire Google Photos library at once (causes issues)
4. **Gradual migration** - Start backing up new photos, migrate old ones slowly
5. **Face training** - Name people early for better detection
6. **Albums** - Organize photos into albums regularly
7. **Cleanup** - Delete duplicates and unwanted photos
8. **Monitor storage** - Keep eye on disk space
9. **Test restore** - Verify backups work before disaster
10. **Update app** - Keep mobile app updated

---

## Migration from Google Photos

### Export from Google Photos

1. Google Takeout: https://takeout.google.com/
2. Select "Photos"
3. Export size: 50 GB per file
4. Download archive(s)

### Import to Immich

**Option 1: Upload via Web**
- Extract Takeout archives
- Upload folders via Immich web interface
- **Warning:** Slow for large libraries

**Option 2: Direct File Copy**
```bash
# Extract Takeout
unzip takeout-*.zip -d /tmp/takeout

# Copy to Immich
cp -r /tmp/takeout/Takeout/Google\ Photos/* /mnt/media/photos/

# Trigger rescan in Immich
# Settings → Jobs → Scan Library
```

**Option 3: Use immich-go (Third-party tool)**
- https://github.com/simulot/immich-go
- Preserves metadata, albums, favorites
- Recommended for large migrations

---

## Common Access URLs

| Service | Public URL | Private URL |
|---------|-----------|-------------|
| Immich | https://photos.yourdomain.com | http://homelab-media:2283 |

Accessible via Cloudflare Tunnel publicly and Tailscale privately.
