# Network & Remote Access Setup

This stack uses a **privacy-first architecture** with Cloudflare Tunnel and Tailscale to provide secure remote access without exposing your home IP address or opening ports on your firewall.

## Overview

**Two-tier access model:**
- **Public services** (Jellyfin, Jellyseerr, etc.) → Cloudflare Tunnel
- **Admin services** (Sonarr, Radarr, etc.) → Tailscale VPN

## Cloudflare Tunnel

### What is Cloudflare Tunnel?

Cloudflare Tunnel creates an outbound-only connection from your server to Cloudflare's edge network. Benefits:

- ✅ **Your home IP stays hidden** - No one can find your actual location
- ✅ **No port forwarding** - No holes in your firewall
- ✅ **Free DDoS protection** - Cloudflare's enterprise-grade security
- ✅ **Automatic SSL** - HTTPS handled at Cloudflare's edge
- ✅ **Works behind CGNAT** - No public IP needed
- ✅ **Zero Trust security** - Optional access policies and authentication

### Prerequisites

1. **Domain name** - Any domain you own
2. **Cloudflare account** - Free tier is sufficient
3. **Domain managed by Cloudflare DNS** - Transfer or point nameservers

### Step 1: Transfer Domain to Cloudflare DNS

1. **Sign up at** [Cloudflare](https://dash.cloudflare.com/sign-up)

2. **Add your site:**
   - Click "Add a site"
   - Enter your domain name
   - Select Free plan
   - Click "Add site"

3. **Cloudflare will scan your DNS records** (if migrating from another provider)
   - Review the records found
   - Click "Continue"

4. **Update nameservers at your registrar:**
   - Cloudflare provides 2 nameservers (e.g., `emma.ns.cloudflare.com`)
   - Log into your domain registrar
   - Find DNS/Nameserver settings
   - Replace existing nameservers with Cloudflare's
   - Save changes

5. **Wait for DNS propagation** (5 minutes to 24 hours)
   - Cloudflare will email when active
   - Status shows "Active" in Cloudflare dashboard

### Step 2: Create Cloudflare Tunnel

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

### Step 3: Configure Public Hostname Routes

Now you'll route your subdomains to services. Add these public hostnames:

**1. Homarr (Dashboard)**
```
Public hostname: homarr.yourdomain.com
Service:
  Type: HTTP
  URL: homarr:7575
```

**2. Jellyfin (Media Server)**
```
Public hostname: jellyfin.yourdomain.com
Service:
  Type: HTTP
  URL: jellyfin:8096
Additional settings:
  - No TLS Verify: ON (internal traffic)
```

**3. Jellyseerr (Media Requests)**
```
Public hostname: jellyseerr.yourdomain.com
Service:
  Type: HTTP
  URL: jellyseerr:5055
```

**4. Audiobookshelf (Audiobooks & Podcasts)**
```
Public hostname: audiobooks.yourdomain.com
Service:
  Type: HTTP
  URL: audiobookshelf:80
```

**5. Calibre-Web (E-books)**
```
Public hostname: books.yourdomain.com
Service:
  Type: HTTP
  URL: calibre-web:8083
```

**6. Immich (Photo Backup)**
```
Public hostname: photos.yourdomain.com
Service:
  Type: HTTP
  URL: immich-server:3001
```

Click "Save tunnel" after adding all routes.

### Step 4: Configure Environment Variable

1. **Edit your `.env` file:**
   ```bash
   cd /opt/homelab
   nano .env
   ```

2. **Add your tunnel token:**
   ```bash
   CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoiYzU3Zj...
   ```
   (Use your actual token from Step 2)

3. **Save and exit** (Ctrl+X, Y, Enter)

### Step 5: Start the Stack

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

### Step 6: Test Access

**From Outside Your Network** (use mobile data or ask a friend):

```bash
# Test each subdomain
curl -I https://jellyfin.yourdomain.com
curl -I https://homarr.yourdomain.com
curl -I https://jellyseerr.yourdomain.com
curl -I https://audiobooks.yourdomain.com
curl -I https://books.yourdomain.com
curl -I https://photos.yourdomain.com
```

Or just open in browser:
- https://homarr.yourdomain.com - Should show your dashboard
- https://jellyfin.yourdomain.com - Should show Jellyfin login
- https://photos.yourdomain.com - Should show Immich login

**Check SSL Certificate:**
- Click padlock icon in browser
- Certificate issued by: Cloudflare
- Valid for: yourdomain.com and subdomains

---

## Tailscale Setup

Admin services (Sonarr, Radarr, etc.) should **NOT** be publicly accessible. Use Tailscale for secure private access.

### Step 1: Get Auth Key

1. **Go to:** https://login.tailscale.com/admin/settings/keys
2. **Click "Generate auth key"**
3. **Options:**
   - Reusable: **YES**
   - Ephemeral: **NO**
   - Tags: (optional) `tag:homelab`
4. **Copy the key** (starts with `tskey-auth-...`)

### Step 2: Add to `.env` file

```bash
nano .env
```

Add:
```bash
TAILSCALE_AUTH_KEY=tskey-auth-xxxxxxxxxxxxx-yyyyyyyyyyyyyyyy
```

### Step 3: Restart stack

```bash
docker compose up -d
```

### Step 4: Verify Tailscale

```bash
docker compose logs tailscale
```

Check Tailscale admin:
- Go to: https://login.tailscale.com/admin/machines
- You should see: `homelab-media`

### Step 5: Access Admin Services

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
   - Uptime Kuma: `http://homelab-media:3001`
   - OVOS GUI: `http://homelab-media:8484`

---

## Security Best Practices

### 1. Enable Cloudflare Web Application Firewall (WAF)
- Go to Cloudflare dashboard → Security → WAF
- Enable "OWASP Core Ruleset"
- Enable "Cloudflare Managed Ruleset"

### 2. Set Up Access Policies (Optional but recommended)
For additional security on public services:

- Go to Zero Trust → Access → Applications
- Create application for each service
- Add access policy:
  - Allow: Email ends with `@yourdomain.com`
  - Or: Country = United States (or your country)
  - Or: Require authentication via Google/GitHub/etc.

Example: Require login before accessing Jellyseerr

### 3. Enable Rate Limiting
- Cloudflare dashboard → Security → Settings
- Enable "Rate Limiting Rules"
- Limit: 100 requests per minute per IP

### 4. Monitor Access Logs
- Zero Trust → Logs → Access
- Review authentication attempts
- Set up alerts for suspicious activity

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

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                  Internet / Users                         │
└──────────────┬─────────────────────────┬──────────────────┘
               │                         │
               │ Public Services         │ Admin Access
               │ (*.yourdomain.com)     │ (Authorized only)
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
│  │  │        Docker Compose (31 Services)          │  │  │
│  │  │                                               │  │  │
│  │  │  PUBLIC (via Cloudflare):                    │  │  │
│  │  │    Jellyfin, Jellyseerr, Homarr              │  │  │
│  │  │    Audiobookshelf, Calibre-Web, Immich       │  │  │
│  │  │                                               │  │  │
│  │  │  PRIVATE (via Tailscale):                    │  │  │
│  │  │    *arr apps, Downloads, Tdarr               │  │  │
│  │  │    Uptime Kuma, OVOS                         │  │  │
│  │  └──────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

**Privacy-First Architecture:**
1. **Home IP never exposed** - Cloudflare Tunnel creates outbound connection only
2. **No ports opened** - Router firewall remains locked down
3. **Public services** - Routed through Cloudflare (DDoS protected, SSL at edge)
4. **Admin services** - Only accessible via Tailscale (zero-trust encrypted mesh)
5. **Local access** - All services still available on home network via IP:PORT
