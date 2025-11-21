# Books & Audiobooks Services

Services for managing and streaming books, audiobooks, and podcasts.

## Services Overview

| Service | Purpose | Access | Port |
|---------|---------|--------|------|
| **Calibre-Web** | E-book library and reader | Public (Cloudflare) | 8083 |
| **Audiobookshelf** | Audiobook and podcast server | Public (Cloudflare) | 13378 |

---

## Calibre-Web - E-book Library

Web-based e-book library with send-to-Kindle support and OPDS catalog.

### Features

- Web-based e-book reader
- Send books to Kindle via email
- OPDS catalog for e-readers
- Multiple format support (EPUB, MOBI, PDF, etc.)
- User management
- Reading progress tracking
- Custom shelves and collections

### Initial Setup

1. **Access:**
   - Public: https://books.yourdomain.com
   - Local: http://CT-IP:8083

2. **First Time Login:**
   ```
   Username: admin
   Password: admin123
   ```
   **⚠️ Change this immediately!**

3. **Change Admin Password:**
   - Click admin → Edit User
   - Change password
   - Save

4. **Configure Database Location:**
   - Admin → Edit Basic Configuration
   - **Calibre Database Path**: `/books`
   - If database doesn't exist, it will be created automatically

5. **Enable Uploads:**
   - Admin → Edit Basic Configuration → Feature Configuration
   - ✅ **Enable Uploads**: Yes
   - Set allowed formats (EPUB, MOBI, PDF, AZW3, etc.)
   - Save

6. **Configure Send-to-Kindle (Optional):**

   Admin → Edit Basic Configuration → E-Mail Server Settings

   **Using Gmail:**
   - **SMTP Hostname**: `smtp.gmail.com`
   - **SMTP Port**: 587
   - **SMTP Login**: your-email@gmail.com
   - **SMTP Password**: App-specific password (not your regular password)
   - **From E-mail**: your-email@gmail.com
   - ✅ **Encryption**: STARTTLS

   **Note:** For Gmail, you need to create an "App Password":
   1. Go to Google Account → Security
   2. Enable 2-Factor Authentication
   3. Generate App Password for "Mail"
   4. Use that password in Calibre-Web

7. **Set Up OPDS Catalog (For E-Readers):**
   - Admin → Edit Basic Configuration → Feature Configuration
   - ✅ **Enable OPDS**: Yes
   - OPDS URL: `https://books.yourdomain.com/opds`
   - Configure in your e-reader app

### Adding Books

**Method 1: Upload via Web Interface**
1. Click "Upload" button
2. Select file(s)
3. Fill in metadata (title, author, etc.)
4. Upload

**Method 2: Use Readarr**
- See [Media Automation](media-automation.md) docs
- Readarr → Calibre integration
- Automatic downloads and metadata

**Method 3: Manual File Copy**
```bash
# Copy books to directory
cp ~/my-books/*.epub /mnt/media/books/

# Rescan library in Calibre-Web
Admin → Reconnect to Calibre Database
```

### User Management

Create users for family/friends:

1. Admin → Add New User
2. Set username and password
3. Configure permissions:
   - Download books
   - Upload books
   - Edit books
   - Delete books
4. Save

### Reading Books

**In Browser:**
- Click book cover
- Click "Read in Browser"
- Supports EPUB and PDF

**Download to Device:**
- Click book cover
- Click download icon
- Select format (EPUB, MOBI, PDF, etc.)

**Send to Kindle:**
1. Set up your Kindle email in user profile
2. Add calibre-web email to Kindle approved senders list
3. Click book → "Send to Kindle"
4. Book appears on your Kindle in minutes

### Collections & Shelves

**Create Custom Shelves:**
1. Click "Create Shelf"
2. Name shelf (e.g., "To Read", "Favorites")
3. Add books to shelf from book details page

### Metadata Management

**Edit Book Metadata:**
1. Click book cover
2. Click "Edit Metadata"
3. Update title, author, description, cover, etc.
4. Save

**Fetch Metadata Automatically:**
- Enable metadata providers in Admin settings
- Google Books, Goodreads, etc.
- Auto-fetch on upload

---

## Audiobookshelf - Audiobook & Podcast Server

Modern audiobook and podcast server with mobile apps.

### Features

- Beautiful web and mobile interfaces
- Audiobook playback with chapter support
- Podcast subscriptions with auto-download
- Progress tracking across devices
- Sleep timer
- Playback speed control
- Library statistics
- User management
- OPML import/export
- Mobile apps (iOS/Android)

### Initial Setup

1. **Access:**
   - Public: https://audiobooks.yourdomain.com
   - Local: http://CT-IP:13378

2. **First Time Setup:**
   - Create admin account
   - Choose username and password
   - Set server name

3. **Add Audiobook Library:**

   Settings → Libraries → Add Library

   - **Library Name**: Audiobooks
   - **Library Type**: Audiobooks
   - **Folder Path**: `/audiobooks`
   - ✅ **Watch for Changes**: Enable (auto-scan)
   - Save

4. **Add Podcast Library:**

   Settings → Libraries → Add Library

   - **Library Name**: Podcasts
   - **Library Type**: Podcasts
   - **Folder Path**: `/podcasts`
   - ✅ **Download Podcasts**: Enable
   - Save

5. **Configure Metadata Providers:**

   Settings → Settings → Metadata

   - ✅ **AudiobookShelf Metadata**: Enable
   - ✅ **Audible**: Enable (for audiobook covers/metadata)
   - ✅ **iTunes**: Enable (for podcast metadata)

6. **Configure Backups:**

   Settings → Backups

   - ✅ **Automatic Backups**: Enable
   - **Schedule**: Daily at 3 AM
   - **Max Backups**: 7

### Adding Audiobooks

**Method 1: Upload via Web Interface**
1. Click library
2. Click "Upload"
3. Select audio files
4. Upload

**Method 2: Manual File Copy**
```bash
# Create directory structure
mkdir -p /mnt/media/audiobooks/"Author Name"/"Book Title"

# Copy audiobook files
cp ~/audiobooks/*.m4a /mnt/media/audiobooks/"Author Name"/"Book Title"/

# Audiobookshelf will auto-scan and detect
```

**Recommended Structure:**
```
/audiobooks/
  Author Name/
    Book Title/
      01 - Chapter 1.m4a
      02 - Chapter 2.m4a
      cover.jpg
```

### Managing Podcasts

**Subscribe to Podcast:**
1. Go to Podcasts library
2. Click "Add Podcast"
3. Enter RSS feed URL
4. Configure auto-download settings
5. Subscribe

**Auto-Download Settings:**
- **Download Episodes**: Enable
- **Auto-Download New Episodes**: Enable
- **Max Episodes to Keep**: 10 (or preferred)

**Find Podcast RSS:**
- Search podcast name + "RSS feed"
- Use podcast directories (Podcast Index, iTunes)
- Most podcast websites have RSS feed link

### Mobile Apps

**iOS/Android Apps:**
- Search "Audiobookshelf" in App Store / Play Store
- Download and install
- Configure server connection

**Server Connection:**
- **Server URL**: https://audiobooks.yourdomain.com
- **Username**: Your username
- **Password**: Your password

**Features:**
- Offline downloads
- Progress sync across devices
- Sleep timer
- Playback speed control
- Bluetooth support

### User Management

Create users for family/friends:

1. Settings → Users → Add User
2. Set username and password
3. Configure permissions:
   - Library access
   - Download permissions
   - Upload permissions
4. Save

### Library Statistics

View statistics:
- Settings → Stats
- Total listening time
- Books completed
- Most listened authors
- Daily/weekly activity

---

## Integration

### Calibre-Web + Readarr

Use Readarr to automate e-book downloads:

1. Set up Readarr (see [Media Automation](media-automation.md))
2. Configure Readarr → Calibre:
   - Settings → Calibre
   - **Calibre Host**: `calibre-web`
   - **Port**: `8083`
   - **Calibre Library**: `/books`
3. Add authors to monitor
4. Readarr downloads → Calibre-Web library

### Audiobookshelf Auto-Organization

Audiobookshelf automatically:
- Detects book metadata
- Creates author folders
- Organizes files
- Downloads cover art
- Fetches audiobook metadata

---

## Tips & Best Practices

### Calibre-Web

1. **Use EPUB format** - Best web reader support
2. **Enable OPDS** - Access from e-reader apps
3. **Regular backups** - Backup `/mnt/media/books` directory
4. **Send-to-Kindle** - Configure for easy Kindle transfers
5. **Custom columns** - Add custom metadata fields (read status, rating, etc.)

### Audiobookshelf

1. **Proper file naming** - Use clear chapter names
2. **Include cover art** - Add `cover.jpg` to audiobook folders
3. **Use M4A/MP3** - Best compatibility
4. **Configure auto-download** - For podcasts you follow regularly
5. **Backup database** - Enable automatic backups
6. **Mobile app sync** - Keep local copies for offline listening

---

## Storage Requirements

### E-books (Calibre-Web)
- **EPUB**: 1-5 MB per book
- **PDF**: 5-50 MB per book
- **1000 books**: ~2-10 GB

### Audiobooks (Audiobookshelf)
- **Standard quality**: 50-100 MB per hour
- **High quality**: 100-200 MB per hour
- **Average book (10 hours)**: 500 MB - 2 GB

### Podcasts
- **Episode (1 hour)**: 50-100 MB
- **Auto-cleanup recommended**: Keep last 10 episodes

---

## Troubleshooting

### Calibre-Web

**Can't connect to database:**
```bash
# Check directory exists
ls -la /mnt/media/books

# Check permissions
chmod -R 755 /mnt/media/books

# Restart container
docker compose restart calibre-web
```

**Send-to-Kindle not working:**
- Verify email configuration (test in settings)
- Check Kindle approved sender list
- Gmail: Use app-specific password, not regular password
- Check spam folder on Kindle

**Books not appearing:**
- Admin → Reconnect to Calibre Database
- Check file permissions
- Verify files are in `/books` directory

### Audiobookshelf

**Auto-scan not working:**
```bash
# Check library settings
Settings → Libraries → Watch for Changes (enabled?)

# Manual scan
Library → Scan

# Check logs
docker compose logs audiobookshelf
```

**Podcast downloads failing:**
- Verify RSS feed is valid (test in browser)
- Check disk space: `df -h /mnt/media`
- Check logs for errors
- Try re-subscribing to podcast

**Mobile app won't connect:**
- Verify server URL (https://audiobooks.yourdomain.com)
- Check Cloudflare Tunnel is healthy
- Test web interface works first
- Verify username/password

---

## Advanced Configuration

### Calibre-Web Custom Themes

Admin → Edit Basic Configuration → UI Configuration

- Change theme color
- Customize layout
- Add custom CSS

### Audiobookshelf Custom Metadata

For audiobooks:
- Edit audiobook → Metadata
- Add custom tags
- Set genres
- Add narrator information
- Set series and sequence

### Backup & Restore

**Calibre-Web Backup:**
```bash
# Backup books directory
tar -czf calibre-backup-$(date +%Y%m%d).tar.gz /mnt/media/books

# Backup Calibre-Web config
tar -czf calibre-web-config-$(date +%Y%m%d).tar.gz ./data/calibre-web
```

**Audiobookshelf Backup:**
- Settings → Backups → Download Backup
- Stores in `./data/audiobookshelf/backups`
- Includes database and metadata

---

## Common Access URLs

| Service | Public URL | Private URL |
|---------|-----------|-------------|
| Calibre-Web | https://books.yourdomain.com | http://homelab-media:8083 |
| Audiobookshelf | https://audiobooks.yourdomain.com | http://homelab-media:13378 |

Both services accessible via Cloudflare Tunnel publicly and Tailscale privately.
