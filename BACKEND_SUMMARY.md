# Unified Backend - Quick Reference

**Status:** ✅ Complete and validated
**Date:** 2025-11-14

## What Changed

Your homelab now has a **unified PostgreSQL and Redis backend** that multiple services share, while keeping other services on SQLite for optimal balance.

## Architecture

```
┌─────────────────────────────────────────────────┐
│         Shared Backend Services                 │
├─────────────────────────────────────────────────┤
│  PostgreSQL (port 5432)                         │
│  ├── immich database                            │
│  ├── jellyseerr database                        │
│  └── uptimekuma database                        │
│                                                  │
│  Redis (port 6379)                              │
│  └── immich (job queues & caching)              │
└─────────────────────────────────────────────────┘
         ▲          ▲           ▲
         │          │           │
    ┌────┴──┐  ┌────┴────┐  ┌──┴─────────┐
    │Immich │  │Jellyseerr│  │Uptime Kuma │
    └───────┘  └──────────┘  └────────────┘

homelab_backend network (isolated)
```

## Quick Start (New Deployment)

1. **Generate passwords**:
   ```bash
   openssl rand -base64 32  # Use for DB_PASSWORD
   openssl rand -base64 32  # Use for REDIS_PASSWORD
   ```

2. **Update .env**:
   ```bash
   cp .env.example .env
   nano .env
   # Add DB_PASSWORD and REDIS_PASSWORD
   ```

3. **Start the stack**:
   ```bash
   docker compose up -d
   ```

That's it! Databases are created automatically.

## Upgrading Existing Deployment

⚠️ **Important:** Back up first!

```bash
# 1. Stop services
docker compose stop jellyseerr uptime-kuma

# 2. Backup
cp -r ./data/jellyseerr ./data/jellyseerr.backup
docker run --rm -v homelab_uptime_kuma_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/uptime-kuma-backup.tar.gz /data

# 3. Add passwords to .env
nano .env
# Add DB_PASSWORD and REDIS_PASSWORD

# 4. Recreate postgres to create new databases
docker compose up -d --force-recreate postgres

# 5. Start migrated services (auto-migrates on first run)
docker compose up -d jellyseerr uptime-kuma

# 6. Check logs
docker logs -f jellyseerr
docker logs -f uptime-kuma

# 7. Verify everything works in the UIs
```

See [BACKEND_MIGRATION.md](BACKEND_MIGRATION.md) for detailed steps.

## Key Features

✅ **Health Checks** - Services wait for postgres/redis to be healthy
✅ **Network Isolation** - Dedicated `homelab_backend` network
✅ **Admin Access** - Postgres (5432) and Redis (6379) exposed for pgAdmin/redis-cli via Tailscale
✅ **Auto Database Creation** - Script creates all databases on startup
✅ **Password Protected** - Both postgres and redis require authentication
✅ **Hybrid Approach** - PostgreSQL where it helps, SQLite where it's fine

## Services Using PostgreSQL

| Service | Database | Why? |
|---------|----------|------|
| Immich | `immich` | Required (vector search) |
| Jellyseerr | `jellyseerr` | Better performance, official support |
| Uptime Kuma | `uptimekuma` | Time-series data, grows indefinitely |

## Services Staying on SQLite

- **All *arr apps** - Proven stable, portable
- **Download clients** - Minimal DB usage
- **Media servers** - Small datasets
- **Admin tools** - Should stay independent

## Database Admin

### Via psql (inside container)
```bash
# List all databases
docker exec -it postgres psql -U homelab -c '\l'

# Connect to database
docker exec -it postgres psql -U homelab -d immich

# Inside psql:
\dt              # List tables
\d+ table_name   # Describe table
```

### Via pgAdmin (SSH Tunnel)
**Note:** Postgres port not exposed for security.
```bash
# Create SSH tunnel first
ssh -L 5432:localhost:5432 user@homelab-ip
# Then connect pgAdmin to localhost:5432
```
- Host: `localhost`
- Port: `5432`
- Username: `homelab` (from .env DB_USER)
- Password: (from .env DB_PASSWORD)

### Backups
```bash
# Backup all databases
docker exec postgres pg_dumpall -U homelab > backup_$(date +%Y%m%d).sql

# Backup specific database
docker exec postgres pg_dump -U homelab immich > immich_$(date +%Y%m%d).sql

# Restore
cat backup.sql | docker exec -i postgres psql -U homelab
```

## Troubleshooting

### Service won't start
```bash
# Check postgres health
docker exec postgres pg_isready -U homelab

# Check logs
docker logs postgres
docker logs jellyseerr
docker logs uptime-kuma
```

### Database connection error
```bash
# Verify database exists
docker exec -it postgres psql -U homelab -c '\l' | grep jellyseerr

# Check environment variables
docker exec jellyseerr env | grep DB_
```

### Full troubleshooting guide
See [BACKEND_MIGRATION.md](BACKEND_MIGRATION.md) - Troubleshooting section

## Files Modified

- ✅ `docker-compose.yml` - Backend config, service migrations, network
- ✅ `.env.example` - Updated database documentation
- ✅ `README.md` - Quick start updates
- 📄 `BACKEND_MIGRATION.md` - Complete migration guide (NEW)
- 📄 `CHANGELOG_BACKEND.md` - Detailed changelog (NEW)
- 📄 `BACKEND_SUMMARY.md` - This file (NEW)

## Documentation

- **[BACKEND_MIGRATION.md](BACKEND_MIGRATION.md)** - Complete guide with migration steps, admin commands, troubleshooting
- **[CHANGELOG_BACKEND.md](CHANGELOG_BACKEND.md)** - Detailed technical changelog
- **[README.md](README.md)** - Main homelab documentation

## Validation

✅ Syntax validated with `docker compose config`
✅ All services properly configured
✅ Health checks in place
✅ Networks configured
✅ Documentation complete

## Next Steps

1. **Fresh install?** Just add passwords to `.env` and `docker compose up -d`
2. **Upgrading?** Follow the upgrade steps above or see BACKEND_MIGRATION.md
3. **Want more?** Consider adding pgAdmin or automated backups (see BACKEND_MIGRATION.md - What's Next)

## Questions?

- Detailed migration: [BACKEND_MIGRATION.md](BACKEND_MIGRATION.md)
- Technical details: [CHANGELOG_BACKEND.md](CHANGELOG_BACKEND.md)
- General setup: [README.md](README.md)

---

**Backend unification complete!** 🎉

Your homelab now has a clean, unified, well-documented backend infrastructure.
