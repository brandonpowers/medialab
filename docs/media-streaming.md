# Media Streaming Services

Services for streaming and managing your media library.

## Services Overview

| Service | Purpose | Access | Port |
|---------|---------|--------|------|
| **Jellyfin** | Media server for movies, TV, and music | Public (Cloudflare) | 8096 |
| **Jellyseerr** | Media request and discovery platform | Public (Cloudflare) | 5055 |
| **Homepage** | Unified dashboard for all services | Public (Cloudflare) | 3000 |

## Jellyfin

Open-source media server with hardware transcoding support.

### Features
- Stream movies, TV shows, and music
- Intel QuickSync hardware transcoding
- Mobile apps for iOS/Android
- Web player with subtitle support
- User management and profiles
- Watch progress tracking

### Initial Setup

1. **Access Jellyfin:**
   - Public: https://jellyfin.yourdomain.com
   - Local: http://CT-IP:8096

2. **Complete initial setup wizard:**
   - Create admin account
   - Set display language
   - Add media libraries

3. **Add Media Libraries:**

   Navigate to Dashboard → Libraries → Add Media Library

   - **Movies**: `/media/movies`
   - **TV Shows**: `/media/tv`
   - **Music**: `/media/music`

   Configure each library:
   - Enable metadata providers (TheMovieDB, TheTVDB, MusicBrainz)
   - Enable automatic refresh
   - Set preferred language

4. **Enable Hardware Acceleration:**

   Dashboard → Playback → Transcoding

   - **Video Acceleration API (VAAPI)** or **Intel Quick Sync**
   - **Device**: `/dev/dri/renderD128`
   - Enable hardware encoding for H.264 and H.265

   This dramatically reduces CPU usage during transcoding.

### User Management

Create users for family/friends:

1. Dashboard → Users → Add User
2. Set username and password
3. Configure library access
4. Set streaming quality limits (optional)

### Mobile Apps

- **iOS**: Jellyfin app (App Store)
- **Android**: Jellyfin app (Play Store)
- **Configuration**: Server URL: https://jellyfin.yourdomain.com

### Troubleshooting

**Transcoding not working:**
```bash
# Verify GPU is accessible
docker exec jellyfin ls -la /dev/dri/

# Check Jellyfin logs
docker compose logs jellyfin
```

**Media not appearing:**
```bash
# Force library scan
Dashboard → Libraries → Scan All Libraries

# Check file permissions
ls -la /mnt/media/movies
```

**Buffering issues:**
- Enable hardware transcoding if not already enabled
- Lower streaming quality in playback settings
- Check network bandwidth

---

## Jellyseerr

Media request and discovery platform that integrates with Jellyfin, Sonarr, and Radarr.

### Features
- Beautiful media discovery interface
- User request system
- Automatic approval workflows
- Integration with TMDB for metadata
- Email notifications
- Mobile-responsive web interface

### Initial Setup

1. **Access Jellyseerr:**
   - Public: https://jellyseerr.yourdomain.com
   - Local: http://CT-IP:5055

2. **Sign in with Jellyfin:**
   - Use your Jellyfin admin credentials
   - Jellyseerr will authenticate via Jellyfin

3. **Configure Jellyfin Connection:**

   Settings → Jellyfin

   - **Server URL**: `http://jellyfin:8096`
   - Sign in with admin credentials
   - Select libraries to sync

4. **Configure Sonarr:**

   Settings → Services → Sonarr

   - **Server URL**: `http://sonarr:8989`
   - **API Key**: (from Sonarr Settings → General)
   - **Quality Profile**: Select your preferred profile
   - **Root Folder**: `/media/tv`
   - Enable "External" to allow requests
   - Test connection and save

5. **Configure Radarr:**

   Settings → Services → Radarr

   - **Server URL**: `http://radarr:7878`
   - **API Key**: (from Radarr Settings → General)
   - **Quality Profile**: Select your preferred profile
   - **Root Folder**: `/media/movies`
   - Enable "External" to allow requests
   - Test connection and save

6. **Configure TMDB API:**

   Settings → Services → The Movie Database

   - **API Key**: Add your TMDB API key from `.env` file
   - Get free API key at: https://www.themoviedb.org/settings/api

7. **Set Up User Permissions:**

   Settings → Users

   - Configure default permissions for new users
   - Set request limits (optional)
   - Configure approval requirements

### Using Jellyseerr

**Requesting Content:**

1. Search for movie or TV show
2. Click request button
3. For TV shows, select specific seasons
4. Submit request

**Approval Workflow:**

- Admin users can approve/deny requests
- Auto-approval can be enabled per user
- Email notifications for request status

**Discovery:**

- Browse popular, trending, and upcoming content
- Filter by genre, rating, year
- See availability in Jellyfin

### Troubleshooting

**Can't connect to Sonarr/Radarr:**
```bash
# Verify services are running
docker compose ps sonarr radarr

# Check API keys match
docker compose exec sonarr cat /config/config.xml | grep ApiKey
docker compose exec radarr cat /config/config.xml | grep ApiKey
```

**Requests not processing:**
- Check Sonarr/Radarr logs for errors
- Verify quality profiles exist
- Ensure root folders are correct
- Check download client is configured

---

## Homepage

Unified dashboard providing quick access to all your services with live status widgets.

### Features
- Pre-configured during setup with all services
- Live service widgets showing real-time data
- Docker container status monitoring
- System resource monitoring (CPU, RAM, disk)
- Customizable YAML configuration
- Dark theme by default

### Accessing Homepage

- **Public**: https://home.yourdomain.com
- **Local**: http://SERVER_IP:3000

### Configuration

Homepage is **pre-configured automatically** during setup. All services are added with:
- Service icons
- API integration for live data
- Docker container status
- Health monitoring

Configuration files are in `data/homepage/config/`:
- `settings.yaml` - Theme and layout
- `services.yaml` - Service widgets
- `docker.yaml` - Container monitoring
- `widgets.yaml` - Info widgets
- `bookmarks.yaml` - Quick links

### Customization

**Edit services.yaml** to customize widgets:
```yaml
- Media:
    - Jellyfin:
        icon: jellyfin.svg
        href: http://SERVER_IP:8096
        widget:
          type: jellyfin
          url: http://SERVER_IP:8096
          key: your-api-key
```

**Restart after changes:**
```bash
docker compose restart homepage
```

### Service Widgets

Homepage shows live data from:
- **Jellyfin**: Now playing, library stats
- **Sonarr/Radarr**: Queue, wanted items
- **qBittorrent**: Download/seed status
- **SABnzbd**: Download queue
- **ARM**: Current disc ripping progress and status
- **Tdarr**: Transcoding progress

### Troubleshooting

**Services not showing status:**
```bash
# Check Homepage logs
docker compose logs homepage

# Verify API keys in docker-compose.yml environment
# Check services.yaml for correct URLs
```

**Can't access Homepage:**
- Check Cloudflare Tunnel configuration
- Verify service is running: `docker compose ps homepage`
- Check logs: `docker compose logs homepage`

---

## Integration Between Services

### Jellyfin ← Jellyseerr Workflow

1. User requests content in Jellyseerr
2. Jellyseerr sends request to Sonarr/Radarr
3. Sonarr/Radarr searches for content
4. Downloads via qBittorrent/SABnzbd
5. Content imported to `/media/movies` or `/media/tv`
6. Jellyfin automatically scans and adds to library
7. User receives notification in Jellyseerr
8. Content available to stream in Jellyfin

### Homepage Dashboard Integration

Homepage provides:
- One-click access to all services
- Live service widgets with API data
- Docker container status
- Unified dashboard for family/friends

---

## Tips & Best Practices

### Jellyfin

1. **Enable hardware transcoding** - Dramatically improves performance
2. **Set up libraries properly** - Use correct content types (Movies, TV, Music)
3. **Regular maintenance** - Scan libraries periodically for new content
4. **User profiles** - Create separate profiles for family members
5. **Backup metadata** - Important for watch history and custom artwork

### Jellyseerr

1. **Configure auto-approval** - For trusted users
2. **Set request limits** - Prevent abuse
3. **Enable notifications** - Email updates for request status
4. **Regular quota checks** - Monitor user requests
5. **Link with Overseerr** - Can migrate from Overseerr if needed

### Homepage

1. **Organize services by category** - Edit services.yaml groups
2. **Use Docker integration** - Monitor container health via docker.yaml
3. **Add info widgets** - Edit widgets.yaml for system stats
4. **Customize theme** - Edit settings.yaml for colors/layout
5. **Backup config** - Backup data/homepage/config/ directory

---

## Advanced Configuration

### Jellyfin Collections

Create collections for movie series:
1. Go to movie details
2. Click **Add to Collection**
3. Create new collection or add to existing
4. Collections appear in library view

### Jellyseerr Webhooks

Send notifications to Discord/Slack:
1. Settings → Notifications → Webhook
2. Add webhook URL
3. Configure notification types
4. Test webhook

### Homepage Custom Styling

Add custom CSS/JS:
1. Create `custom.css` or `custom.js` in config directory
2. Styles are automatically loaded
3. Restart container to apply

---

## Performance Optimization

### Jellyfin

- Enable hardware transcoding (reduces CPU usage by 80%+)
- Set transcode location to `/tmp` (faster I/O)
- Limit simultaneous transcodes in Dashboard → Playback
- Use appropriate streaming quality settings per user

### Jellyseerr

- Uses SQLite database (built-in)
- Database is stored in container config volume

### Homepage

- Lightweight and fast by design
- Uses built-in icon set (no external requests)
- Caches API responses automatically

---

## Common Access URLs

| Service | Public URL | LAN URL |
|---------|-----------|---------|
| Jellyfin | https://jellyfin.yourdomain.com | http://SERVER_IP:8096 |
| Jellyseerr | https://jellyseerr.yourdomain.com | http://SERVER_IP:5055 |
| Homepage | https://home.yourdomain.com | http://SERVER_IP:3000 |

All services accessible on your local network or remotely via Cloudflare Tunnel.
