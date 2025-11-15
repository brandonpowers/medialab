# Port Configuration & Security

**Last Updated:** 2025-11-14
**Status:** ✅ Audited and Secured

## Port Mapping Summary

All services with exposed ports on the host. Services are accessible within your LXC container and via configured access methods (Cloudflare Tunnel or Tailscale).

### Public Services (via Cloudflare Tunnel)
| Service | Host Port | Container Port | Access URL |
|---------|-----------|----------------|------------|
| Homarr | 7575 | 7575 | homarr.glaance.io |
| Jellyfin | 8096, 8920 | 8096, 8920 | jellyfin.glaance.io |
| Jellyseerr | 5055 | 5055 | jellyseerr.glaance.io |
| Immich | 2283 | 3001 | photos.glaance.io |
| Audiobookshelf | 13378 | 80 | audiobooks.glaance.io |
| Calibre-web | 8083 | 8083 | books.glaance.io |

### Private Admin Services (via Tailscale VPN)
| Service | Host Port | Container Port | Access URL |
|---------|-----------|----------------|------------|
| Portainer | 9000, 9443 | 9000, 9443 | http://homelab-media:9000 |
| Sonarr | 8989 | 8989 | http://homelab-media:8989 |
| Radarr | 7878 | 7878 | http://homelab-media:7878 |
| Lidarr | 8686 | 8686 | http://homelab-media:8686 |
| Readarr | 8787 | 8787 | http://homelab-media:8787 |
| Prowlarr | 9696 | 9696 | http://homelab-media:9696 |
| Bazarr | 6767 | 6767 | http://homelab-media:6767 |
| qBittorrent | 8080, 6881 (TCP/UDP) | 8080, 6881 | http://homelab-media:8080 |
| SABnzbd | 8085 | 8080 | http://homelab-media:8085 |
| Tdarr | 8265, 8266 | 8265, 8266 | http://homelab-media:8265 |
| Uptime Kuma | 3001 | 3001 | http://homelab-media:3001 |

### Backend Services (No External Access)
| Service | Host Port | Container Port | Access Method |
|---------|-----------|----------------|---------------|
| PostgreSQL | **NONE** | 5432 | `docker exec -it postgres psql -U homelab` |
| Redis | **NONE** | 6379 | `docker exec -it redis redis-cli -a $REDIS_PASSWORD` |
| Immich ML | **NONE** | Internal | Internal only (used by immich-server) |

### Access Services (Infrastructure)
| Service | Host Port | Notes |
|---------|-----------|-------|
| Cloudflared | None | Outbound tunnel only, no ports needed |
| Tailscale | None | Uses host network mode |
| Recyclarr | None | Runs on-demand, no persistent ports |

## Port Conflict Check

✅ **No port conflicts detected**

All host ports are unique except:
- Port 6881: Used by qBittorrent for both TCP and UDP (intentional, standard BitTorrent protocol)

## Security Analysis

### ✅ Security Improvements Applied

1. **Backend Services Locked Down**
   - PostgreSQL and Redis ports **NOT exposed** to host
   - Only accessible via internal Docker networks
   - Admin access via `docker exec` commands only
   - GUI access requires SSH tunneling

2. **Network Segmentation**
   - Dedicated `homelab_backend` network for database communication
   - Services on both `default` and `backend` networks as needed
   - Cloudflared and Tailscale handle external connectivity

3. **Public Service Protection**
   - All public-facing services behind Cloudflare Tunnel
   - Home IP address never exposed
   - DDoS protection and WAF at Cloudflare edge
   - SSL/TLS termination at Cloudflare

4. **Admin Service Protection**
   - All admin services only accessible via Tailscale VPN
   - Zero-trust encrypted mesh network
   - No direct internet exposure

### Port Binding Strategy

All exposed ports use the default `"PORT:PORT"` format which binds to `0.0.0.0` (all interfaces).

**Why this is secure in your setup:**
- Services run inside LXC container (CT 101)
- LXC container is on Proxmox private network
- No port forwarding on router (using Cloudflare Tunnel instead)
- Tailscale provides encrypted access to admin services
- Even if ports are bound to 0.0.0.0, they're not reachable from internet

**Access layers:**
```
Internet
  ↓
Cloudflare Tunnel (public services only)
  ↓
Router/Firewall (no ports forwarded)
  ↓
Proxmox Host (private network)
  ↓
LXC Container (isolated)
  ↓
Docker Services (individual containers)
```

## Database Admin Access

### PostgreSQL

**Via docker exec (Recommended):**
```bash
# Interactive psql
docker exec -it postgres psql -U homelab

# List databases
docker exec -it postgres psql -U homelab -c '\l'

# Connect to specific database
docker exec -it postgres psql -U homelab -d immich
```

**Via pgAdmin (SSH Tunnel):**
```bash
# On your local machine, create SSH tunnel
ssh -L 5432:localhost:5432 user@homelab-ct-ip

# Then in pgAdmin:
# Host: localhost
# Port: 5432
# Username: homelab
# Password: (from .env)
```

### Redis

**Via docker exec:**
```bash
# Connect to redis-cli
docker exec -it redis redis-cli -a YOUR_REDIS_PASSWORD

# Check status
docker exec redis redis-cli -a YOUR_REDIS_PASSWORD ping
# Returns: PONG

# Get info
docker exec redis redis-cli -a YOUR_REDIS_PASSWORD INFO
```

## Port Ranges Used

```
2000-2999:  2283 (Immich)
3000-3999:  3001 (Uptime Kuma)
5000-5999:  5055 (Jellyseerr)
6000-6999:  6767 (Bazarr), 6881 (qBittorrent)
7000-7999:  7575 (Homarr), 7878 (Radarr)
8000-8999:  8080 (qBittorrent), 8083 (Calibre), 8085 (SABnzbd),
            8096 (Jellyfin), 8265-8266 (Tdarr), 8686 (Lidarr),
            8787 (Readarr), 8920 (Jellyfin HTTPS), 8989 (Sonarr)
9000-9999:  9000 (Portainer), 9443 (Portainer HTTPS), 9696 (Prowlarr)
13000+:     13378 (Audiobookshelf)
```

## Future Additions

When adding new services, consider:

1. **Port availability**: Check this document for used ports
2. **Service type**: Determine if public (Cloudflare) or private (Tailscale)
3. **Backend needs**: If using postgres/redis, add to `homelab_backend` network
4. **Security**: Backend/admin services should NOT expose ports unless necessary

### Recommended Port Ranges for New Services

- **10000-10999**: Available for new services
- **11000-11999**: Available for new services
- **14000-14999**: Available for new services

## Troubleshooting

### "Port already in use" error

```bash
# Check what's using a port (example: 3001)
docker ps | grep 3001
netstat -tlnp | grep 3001  # Linux
lsof -i :3001  # macOS

# If another container is using it
docker stop <container-name>
```

### Service can't connect to postgres/redis

```bash
# Verify service is on backend network
docker inspect <service-name> | grep -A 10 Networks

# Check postgres is healthy
docker exec postgres pg_isready -U homelab

# Check redis is healthy
docker exec redis redis-cli -a $REDIS_PASSWORD ping
```

### Can't access admin service via Tailscale

```bash
# Check Tailscale is running
docker ps | grep tailscale

# Get Tailscale IP
docker exec tailscale tailscale ip

# Verify service is running
docker ps | grep <service-name>

# Test from within container
docker exec <service-name> curl -f http://localhost:<port>
```

## Security Best Practices

1. ✅ **Never expose backend ports** - Use docker exec or SSH tunnels
2. ✅ **Use Tailscale for admin access** - Never expose admin UIs to internet
3. ✅ **Let Cloudflare handle public access** - No port forwarding on router
4. ✅ **Keep .env secure** - Never commit to git, use strong passwords
5. ✅ **Regular updates** - Keep images updated via `docker compose pull`
6. ✅ **Monitor logs** - Check for unauthorized access attempts
7. ✅ **Backup databases** - Regular postgres backups critical

## Summary

**Total Exposed Ports:** 22 unique host ports
**Backend Ports Exposed:** 0 (secured)
**Port Conflicts:** 0 (6881 TCP/UDP is intentional)
**Security Rating:** ✅ Excellent

All ports properly configured for secure homelab operation with defense-in-depth:
- Public services behind Cloudflare Tunnel
- Admin services behind Tailscale VPN
- Backend services not exposed
- LXC container isolation
- No router port forwarding

---

**Last Audit:** 2025-11-14
**Next Audit:** When adding new services
