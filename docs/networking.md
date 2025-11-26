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

Admin services (Sonarr, Radarr, etc.) should **NOT** be publicly accessible. Use Tailscale for secure private access from anywhere.

Tailscale is installed directly on the Ubuntu host (not as a Docker container) for simplicity and reliability.

### Step 1: Install Tailscale

The setup script (`scripts/setup-homelab.sh`) will offer to install Tailscale automatically. To install manually:

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to your Tailscale network
sudo tailscale up --hostname=homelab
```

A browser window will open for authentication. Log in with your Tailscale account.

### Step 2: Verify Connection

```bash
# Check status
tailscale status

# Get your Tailscale IP
tailscale ip -4
# Example output: 100.101.102.103
```

Check the Tailscale admin console:
- Go to: https://login.tailscale.com/admin/machines
- You should see: `homelab`

### Step 3: Install Tailscale on Your Devices

1. **Install Tailscale on your devices:**
   - **Mac/PC:** https://tailscale.com/download
   - **iOS/Android:** App store

2. **Log in with the same Tailscale account**

3. **Access admin services via Tailscale IP:**
   ```
   Sonarr:       http://<tailscale-ip>:8989
   Radarr:       http://<tailscale-ip>:7878
   Lidarr:       http://<tailscale-ip>:8686
   Prowlarr:     http://<tailscale-ip>:9696
   Bazarr:       http://<tailscale-ip>:6767
   qBittorrent:  http://<tailscale-ip>:8080
   SABnzbd:      http://<tailscale-ip>:8085
   Tdarr:        http://<tailscale-ip>:8265
   Uptime Kuma:  http://<tailscale-ip>:3001
   ARM:          http://<tailscale-ip>:8090
   ```

### Optional: Use MagicDNS

Enable MagicDNS in Tailscale admin to access services by hostname:
- Go to: https://login.tailscale.com/admin/dns
- Enable MagicDNS
- Access services at: `http://homelab:PORT`

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
# Check Tailscale is running on the host
tailscale status

# Get Tailscale IP
tailscale ip -4

# Restart Tailscale if needed
sudo systemctl restart tailscaled

# Re-authenticate if disconnected
sudo tailscale up --hostname=homelab
```

**Tailscale not installed:**
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=homelab
```

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                  Internet / Users                         │
└──────────────┬─────────────────────────┬──────────────────┘
               │                         │
               │ Public Services         │ Admin Access
               │ (*.yourdomain.com)      │ (Authorized only)
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
│                     Home Router                          │
└────────────────────────┬─────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────┐
│              Ubuntu Server (192.168.8.200)               │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Tailscale (host-level VPN)                        │  │
│  │  - Provides remote access to all services          │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │        Docker Compose Services                     │  │
│  │                                                    │  │
│  │  PUBLIC (via Cloudflare):                          │  │
│  │    Jellyfin, Jellyseerr, Homarr                    │  │
│  │    Audiobookshelf, Calibre-Web, Immich             │  │
│  │                                                    │  │
│  │  PRIVATE (via Tailscale or LAN):                   │  │
│  │    *arr apps, Downloads, Tdarr                     │  │
│  │    Uptime Kuma, ARM, OVOS                          │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

**Privacy-First Architecture:**
1. **Home IP never exposed** - Cloudflare Tunnel creates outbound connection only
2. **No ports opened** - Router firewall remains locked down
3. **Public services** - Routed through Cloudflare (DDoS protected, SSL at edge)
4. **Admin services** - Accessible via LAN or Tailscale (zero-trust encrypted mesh)
5. **Local access** - All services available on home network via `192.168.8.200:PORT`
6. **Remote access** - All services available via Tailscale IP
