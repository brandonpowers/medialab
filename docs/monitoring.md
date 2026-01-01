# Media Processing Services

Services for automated media processing and optimization.

## Services Overview

| Service | Purpose | Access | Port |
|---------|---------|--------|------|
| **Tdarr** | Automated video transcoding | Private (LAN) | 8265 |
| **ARM** | Automatic Blu-ray/DVD ripping | Private (LAN) | 8090 |

---

## Tdarr - Automated Transcoding

Automate video transcoding to save storage space and optimize for streaming.

### Features

- Automated H.265 (HEVC) conversion
- Hardware transcoding (Intel QuickSync, NVIDIA, AMD VAAPI)
- Scheduled transcoding
- Health checks (find corrupt files)
- File size reduction (30-50% typical)
- Configurable quality settings
- Flow-based plugin system
- Statistics dashboard

### Initial Setup

1. **Access:** http://SERVER_IP:8265

2. **First Time Setup:**
   - Complete welcome wizard
   - Accept defaults for most options

3. **Add Libraries:**

   Libraries -> **Add Library**

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

4. **Create Transcode Flow:**

   Flows -> **Add Flow**

   **Recommended Flow for AMD VAAPI:**
   1. Input File
   2. Check File Medium (video)
   3. Begin Command
   4. Set Video Encoder: `hevc_vaapi`
      - Preset: fast
      - Quality: 25
   5. Set Container: `mkv`
   6. Execute
   7. Replace Original File

5. **Assign Flow to Libraries:**
   - Libraries -> Select library -> Transcode Options
   - Enable "Use Flows"
   - Select your flow

### Hardware Acceleration

Tdarr uses GPU for transcoding (Intel QuickSync or AMD VAAPI):

**Verify GPU Access:**
```bash
docker exec tdarr ls -la /dev/dri/
# Should see renderD128
```

**AMD VAAPI Encoders:**
- `hevc_vaapi` - H.265/HEVC (recommended)
- `h264_vaapi` - H.264/AVC

**Intel QuickSync Encoders:**
- `hevc_qsv` - H.265/HEVC
- `h264_qsv` - H.264/AVC

### Scheduling

**Set Transcode Schedule:**

Libraries -> Select library -> **Schedule**

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

### Quality Settings

**Constant Rate Factor (CRF) / Quality:**
- **18-20**: Near lossless (large files)
- **23-25**: Balanced (recommended)
- **28-30**: Smaller files (lower quality)

**Preset:**
- **Slow**: Better quality, slower
- **Medium**: Balanced
- **Fast**: Faster, larger files (recommended for hardware encoding)

---

## ARM - Automatic Ripping Machine

Automatically rip Blu-ray and DVD discs when inserted.

### Features

- Automatic disc detection via udev
- MakeMKV for disc ripping
- Metadata lookup (TMDB/OMDB)
- Web UI for monitoring
- Fault-tolerant settings for damaged discs

### Initial Setup

1. **Access:** http://SERVER_IP:8090

2. **Configuration:**
   The `./scripts/homelab configure` command sets these automatically:
   - `COMPLETED_PATH`: `/home/arm/movies/` (outputs to Jellyfin movies folder)
   - `SKIP_TRANSCODE`: true (Tdarr handles transcoding)
   - `DELRAWFILES`: false (preserves files on failure)
   - `MKV_ARGS`: `--minlength=600 -r` (retry on read errors)

3. **TMDB API Key:**
   - Get free key at: https://www.themoviedb.org/settings/api
   - Add to `.env` as `TMDB_API_KEY`
   - Run `./scripts/homelab configure` to apply

### Workflow: ARM + Tdarr

```
1. Insert disc
       |
2. ARM auto-detects via udev
       |
3. MakeMKV rips to raw MKV
       |
4. ARM moves to /media/movies
       |
5. Tdarr detects new file
       |
6. Tdarr transcodes to H.265 (VAAPI)
       |
7. Jellyfin scans and adds to library
       |
8. Ready to stream!
```

### Manual Ripping

If automatic detection doesn't work:

1. Open ARM web UI: http://SERVER_IP:8090
2. Click "Scan for Disc"
3. Monitor progress in the UI

### Troubleshooting ARM

**Container keeps restarting:**
```bash
# Check permissions
ls -la data/arm/
# Should be owned by PUID:PGID (usually 1000:1000)

# Fix if needed
sudo chown -R 1000:1000 data/arm/
```

**Disc not detected:**
```bash
# Check udev rule exists
cat /etc/udev/rules.d/99-arm.rules

# Reload udev rules
sudo udevadm control --reload-rules

# Check ARM logs
docker compose logs -f arm
```

**Read errors during rip:**
- The MKV_ARGS `-r` flag enables retries
- Some discs may be too damaged to rip
- Try cleaning the disc
- Check raw/ folder for partial rips

---

## Integration

### ARM -> Tdarr -> Jellyfin

The pipeline is automatic:
1. ARM rips raw MKV files to `/media/movies`
2. Tdarr watches the folder and transcodes to H.265
3. Jellyfin scans and adds to library

---

## Troubleshooting

### Tdarr

**Transcoding not starting:**
```bash
# Check logs
docker compose logs tdarr

# Verify GPU access (if using)
docker exec tdarr ls -la /dev/dri/

# Check schedule is active
# Libraries -> Schedule -> Verify times
```

**Slow transcoding:**
- Enable hardware acceleration (GPU)
- Reduce worker count to 1
- Use "fast" preset instead of slow
- Check CPU usage: `docker stats tdarr`

**Corrupt output files:**
- Increase CRF/Quality value (lower quality, more reliable)
- Change preset to medium/slow
- Test hardware encoder
- Check source files are valid

---

## Performance Optimization

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
| Tdarr | http://SERVER_IP:8265 |
| ARM | http://SERVER_IP:8090 |

All services accessible on your local network.
