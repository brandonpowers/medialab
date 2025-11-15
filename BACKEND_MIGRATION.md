# Backend Services Migration Guide

This guide covers the unified PostgreSQL and Redis backend infrastructure for your homelab.

## Architecture Overview

### Current Setup
- **Shared PostgreSQL**: Single postgres instance with multiple databases
- **Shared Redis**: Single redis instance for caching and job queues
- **Isolated Network**: Dedicated `homelab_backend` network for database communication
- **Health Checks**: Services wait for postgres/redis to be healthy before starting

### Services Using PostgreSQL
| Service | Database | Status | Reason |
|---------|----------|--------|--------|
| Immich | `immich` | ✅ Active | Required for vector search |
| Jellyseerr | `jellyseerr` | ✅ Active | Better performance, official support |
| Uptime Kuma | `uptimekuma` | ✅ Active | Time-series data, grows indefinitely |

### Services Using Redis
| Service | Purpose | Status |
|---------|---------|--------|
| Immich | Job queues, caching | ✅ Active |

### Services Staying on SQLite
- **All *arr apps** (Sonarr, Radarr, Lidarr, Readarr, Prowlarr, Bazarr) - Proven stable, portable
- **Download clients** (qBittorrent, SABnzbd) - Minimal database usage
- **Media apps** (Jellyfin, Audiobookshelf, Calibre-web) - Small datasets
- **Admin tools** (Portainer) - Should remain independent

## Migration Instructions

### Fresh Installation (New Setup)

1. **Ensure .env is configured**:
   ```bash
   # Generate secure passwords
   openssl rand -base64 32  # Use for DB_PASSWORD
   openssl rand -base64 32  # Use for REDIS_PASSWORD

   # Edit .env
   nano .env
   ```

2. **Start the stack**:
   ```bash
   docker compose up -d
   ```

   The postgres init script will automatically create all databases:
   - `immich`
   - `jellyseerr`
   - `uptimekuma`

3. **Verify databases were created**:
   ```bash
   docker exec -it postgres psql -U homelab -c '\l'
   ```

### Migrating Existing Services

⚠️ **IMPORTANT**: Back up your data before migrating!

#### Jellyseerr Migration (SQLite → PostgreSQL)

1. **Stop Jellyseerr**:
   ```bash
   docker compose stop jellyseerr
   ```

2. **Backup existing data**:
   ```bash
   cp -r ./data/jellyseerr/config ./data/jellyseerr/config.backup
   ```

3. **Update docker-compose.yml** (already done if you pulled latest)

4. **Start postgres and create database**:
   ```bash
   docker compose up -d postgres
   # Wait for health check
   docker exec -it postgres psql -U homelab -c "CREATE DATABASE jellyseerr;"
   ```

5. **Start Jellyseerr** (will auto-migrate on first run):
   ```bash
   docker compose up -d jellyseerr
   ```

6. **Monitor logs**:
   ```bash
   docker logs -f jellyseerr
   ```
   Look for successful database connection and migration.

7. **Verify**: Access Jellyseerr UI and confirm all data is present.

8. **Clean up old SQLite files** (optional, after confirming everything works):
   ```bash
   rm ./data/jellyseerr/config/db/db.sqlite*
   ```

#### Uptime Kuma Migration (SQLite → PostgreSQL)

1. **Export existing monitors** (via UI):
   - Login to Uptime Kuma
   - Settings → Backup
   - Download JSON backup

2. **Stop Uptime Kuma**:
   ```bash
   docker compose stop uptime-kuma
   ```

3. **Backup data directory**:
   ```bash
   docker run --rm -v homelab_uptime_kuma_data:/data -v $(pwd):/backup alpine tar czf /backup/uptime-kuma-backup.tar.gz /data
   ```

4. **Update docker-compose.yml** (already done if you pulled latest)

5. **Start postgres and create database**:
   ```bash
   docker compose up -d postgres
   docker exec -it postgres psql -U homelab -c "CREATE DATABASE uptimekuma;"
   ```

6. **Clear old data volume and start Uptime Kuma**:
   ```bash
   docker volume rm homelab_uptime_kuma_data
   docker compose up -d uptime-kuma
   ```

7. **Import backup** (via UI):
   - Login to Uptime Kuma (may need to create new admin account)
   - Settings → Backup
   - Upload JSON backup file

8. **Verify all monitors are restored and working**

## Database Administration

### Access PostgreSQL via psql

```bash
# List all databases
docker exec -it postgres psql -U homelab -c '\l'

# Connect to specific database
docker exec -it postgres psql -U homelab -d immich

# Useful queries
\dt              # List tables
\d+ table_name   # Describe table
SELECT version(); # Postgres version
```

### Access PostgreSQL via pgAdmin (Optional)

**Note:** PostgreSQL port is not exposed for security. To use pgAdmin, you have two options:

**Option 1: SSH Tunnel (Recommended)**
```bash
# From your local machine
ssh -L 5432:localhost:5432 user@homelab-ip
# Then connect pgAdmin to localhost:5432
```

**Option 2: Temporarily expose port**
```bash
# Uncomment ports in docker-compose.yml, restart postgres
# Remember to comment out again after use
```

### Access Redis via redis-cli

```bash
# Connect to redis
docker exec -it redis redis-cli -a YOUR_REDIS_PASSWORD

# Useful commands
INFO                # Server info
DBSIZE              # Number of keys
KEYS *              # List all keys (use carefully in production)
MONITOR             # Watch all commands in real-time
```

### Backup PostgreSQL

```bash
# Backup all databases
docker exec postgres pg_dumpall -U homelab > backup_$(date +%Y%m%d).sql

# Backup specific database
docker exec postgres pg_dump -U homelab immich > immich_backup_$(date +%Y%m%d).sql

# Restore from backup
cat backup.sql | docker exec -i postgres psql -U homelab
```

### Backup Redis

```bash
# Trigger save
docker exec redis redis-cli -a YOUR_REDIS_PASSWORD SAVE

# Copy RDB file
docker cp redis:/data/dump.rdb ./redis_backup_$(date +%Y%m%d).rdb
```

## Network Architecture

Services are connected to two networks:

1. **`default` network**: For inter-service communication (e.g., Jellyseerr → Jellyfin)
2. **`homelab_backend` network**: Dedicated for database/cache connections

This provides isolation while maintaining flexibility.

## Troubleshooting

### Service won't start, shows "waiting for postgres"

```bash
# Check postgres health
docker inspect postgres | grep -A 10 Health

# Check postgres logs
docker logs postgres

# Manually test connection
docker exec -it postgres pg_isready -U homelab
```

### Jellyseerr shows database connection error

```bash
# Check environment variables are set
docker exec jellyseerr env | grep DB_

# Verify database exists
docker exec -it postgres psql -U homelab -c '\l' | grep jellyseerr

# Check jellyseerr logs
docker logs jellyseerr
```

### Uptime Kuma stuck in startup loop

```bash
# Check logs for database migration errors
docker logs uptime-kuma

# Verify database exists and is accessible
docker exec -it postgres psql -U homelab -d uptimekuma -c '\dt'
```

### Redis connection refused

```bash
# Check redis is running
docker ps | grep redis

# Check redis logs
docker logs redis

# Test connection with password
docker exec redis redis-cli -a YOUR_REDIS_PASSWORD ping
# Should return: PONG
```

## Adding More Services to PostgreSQL

To add a new service to the shared postgres instance:

1. **Add database name to `POSTGRES_MULTIPLE_DATABASES`** in docker-compose.yml:
   ```yaml
   POSTGRES_MULTIPLE_DATABASES: immich,jellyseerr,uptimekuma,newservice
   ```

2. **Configure service environment variables**:
   ```yaml
   environment:
     DB_TYPE: postgres        # or similar, varies by service
     DB_HOST: postgres
     DB_PORT: 5432
     DB_NAME: newservice
     DB_USER: ${DB_USER:-homelab}
     DB_PASSWORD: ${DB_PASSWORD}
   ```

3. **Add depends_on with health condition**:
   ```yaml
   depends_on:
     postgres:
       condition: service_healthy
   ```

4. **Add to backend network**:
   ```yaml
   networks:
     - backend
     - default
   ```

5. **Recreate postgres** to run init script:
   ```bash
   docker compose up -d --force-recreate postgres
   ```

## Rollback Instructions

If you need to revert to SQLite for any service:

1. **Stop the service**:
   ```bash
   docker compose stop jellyseerr
   ```

2. **Remove postgres environment variables** from docker-compose.yml

3. **Restore from backup**:
   ```bash
   rm -rf ./data/jellyseerr/config
   cp -r ./data/jellyseerr/config.backup ./data/jellyseerr/config
   ```

4. **Start service**:
   ```bash
   docker compose up -d jellyseerr
   ```

## Performance Monitoring

### Check Postgres Performance

```bash
# Active connections
docker exec -it postgres psql -U homelab -c "SELECT count(*) FROM pg_stat_activity;"

# Database sizes
docker exec -it postgres psql -U homelab -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database;"

# Slow queries (if enabled)
docker exec -it postgres psql -U homelab -c "SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"
```

### Check Redis Performance

```bash
# Memory usage
docker exec redis redis-cli -a YOUR_REDIS_PASSWORD INFO memory

# Stats
docker exec redis redis-cli -a YOUR_REDIS_PASSWORD INFO stats
```

## Security Notes

- PostgreSQL and Redis ports are **NOT exposed** - internal container communication only
- Admin access via `docker exec` commands (see Database Administration section)
- For pgAdmin/GUI access, use SSH tunnels (see Access PostgreSQL section)
- Passwords are required for both services (never hardcoded)
- Databases are isolated per-service (no shared tables)
- Dedicated `homelab_backend` network for database communication
- Network isolation prevents unauthorized access from non-backend services
- Regular backups recommended (automated solution coming soon)

## What's Next?

Future backend improvements:
- Automated backup scripts
- Optional pgAdmin/Redis Commander containers (Tailscale-only access)
- Connection pooling with PgBouncer (if needed at scale)
- Postgres replication for high availability (optional)
