# Backend Services

Shared database and caching services used by multiple applications.

## Services Overview

| Service | Purpose | Used By | Port |
|---------|---------|---------|------|
| **PostgreSQL** | Relational database | Immich | 5432 |
| **Redis** | In-memory cache | Immich | 6379 |

**Note:** Ports are not exposed externally - internal Docker network only.

---

## PostgreSQL - Shared Database

PostgreSQL provides reliable, production-ready database for multiple services.

### Features

- **Shared database server** for multiple applications
- **Automatic database creation** via init script
- **Vector extension** (pgvecto-rs) for Immich ML features
- **Health checks** ensure services wait for database
- **Persistent storage** via Docker volume

### Databases

The following databases are automatically created:

| Database | Used By | Purpose |
|----------|---------|---------|
| `immich` | Immich | Photo metadata, users, albums |

**Note:** Jellyseerr and Uptime Kuma use their own internal SQLite databases for simplicity.

### Configuration

**Environment Variables** (in `.env`):
```bash
DB_USER=homelab          # Database superuser
DB_PASSWORD=<generated>  # Strong password (auto-generated)
```

**Connection Details:**
```
Host: postgres
Port: 5432
User: homelab
Password: <from .env>
Databases: immich
```

### Access Database

**Via Docker:**
```bash
# Connect to PostgreSQL
docker exec -it postgres psql -U homelab

# Connect to specific database
docker exec -it postgres psql -U homelab -d immich

# List databases
docker exec postgres psql -U homelab -c '\l'

# List tables in database
docker exec postgres psql -U homelab -d immich -c '\dt'
```

**Sample Queries:**
```sql
-- Check database sizes
SELECT pg_database.datname as "database",
       pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
ORDER BY pg_database_size(pg_database.datname) DESC;

-- Check table sizes (immich example)
\c immich
SELECT tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

-- Show active connections
SELECT datname, usename, application_name, client_addr, state
FROM pg_stat_activity
WHERE state = 'active';
```

### Maintenance

**Vacuum Database:**
```bash
# Vacuum all databases (reclaim space)
docker exec postgres vacuumdb -U homelab --all

# Analyze and vacuum (update statistics)
docker exec postgres vacuumdb -U homelab --all --analyze

# Vacuum specific database
docker exec postgres vacuumdb -U homelab -d immich
```

**Backup Database:**
```bash
# Backup all databases
docker exec postgres pg_dumpall -U homelab > homelab-databases-$(date +%Y%m%d).sql

# Backup specific database
docker exec postgres pg_dump -U homelab immich > immich-backup-$(date +%Y%m%d).sql

# Restore database
cat immich-backup-20240115.sql | docker exec -i postgres psql -U homelab immich

# Restore all databases
cat homelab-databases-20240115.sql | docker exec -i postgres psql -U homelab
```

**Automated Backup Script:**
```bash
#!/bin/bash
# /opt/homelab/scripts/backup-databases.sh

BACKUP_DIR="/mnt/media/backups/databases"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup all databases
docker exec postgres pg_dumpall -U homelab | gzip > "$BACKUP_DIR/all-databases-$DATE.sql.gz"

# Keep only last 30 days
find "$BACKUP_DIR" -name "all-databases-*.sql.gz" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR/all-databases-$DATE.sql.gz"
```

**Schedule with cron:**
```bash
crontab -e
# Add:
0 2 * * * /opt/homelab/scripts/backup-databases.sh
```

### Performance Tuning

**Check Database Performance:**
```sql
-- Slow queries
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Cache hit ratio (should be >99%)
SELECT
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as cache_hit_ratio
FROM pg_statio_user_tables;

-- Index usage
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

**Optimize Settings** (if needed):

Edit `docker-compose.yml` → postgres → command:
```yaml
command: >
  postgres
  -c shared_buffers=256MB
  -c effective_cache_size=1GB
  -c maintenance_work_mem=64MB
  -c max_connections=100
```

### Troubleshooting

**Can't connect to database:**
```bash
# Check PostgreSQL is running
docker compose ps postgres

# Check health
docker exec postgres pg_isready -U homelab

# Check logs
docker compose logs postgres

# Restart PostgreSQL
docker compose restart postgres
```

**Database doesn't exist:**
```bash
# List databases
docker exec postgres psql -U homelab -c '\l'

# Create database manually
docker exec postgres createdb -U homelab dbname

# Re-run init script
docker compose down postgres
docker compose up -d postgres
```

**Out of disk space:**
```bash
# Check disk usage
df -h

# Check database sizes
docker exec postgres psql -U homelab -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;"

# Vacuum to reclaim space
docker exec postgres vacuumdb -U homelab --all --full
```

---

## Redis - Cache Server

Redis provides in-memory caching for fast data access.

### Features

- **In-memory storage** for high-speed caching
- **Persistence** to disk for data durability
- **Password protection** for security
- **Used by Immich** for job queues and caching

### Configuration

**Environment Variables** (in `.env`):
```bash
REDIS_PASSWORD=<generated>  # Strong password (auto-generated)
```

**Connection Details:**
```
Host: redis
Port: 6379
Password: <from .env>
```

### Access Redis

**Via Docker:**
```bash
# Connect to Redis CLI
docker exec -it redis redis-cli

# Authenticate
AUTH your-redis-password

# Check Redis info
INFO

# Check memory usage
INFO memory

# List all keys (use carefully in production!)
KEYS *

# Get key value
GET key-name

# Delete key
DEL key-name

# Flush all data (WARNING: destructive!)
FLUSHALL
```

**Sample Commands:**
```bash
# Check Redis is running
docker exec redis redis-cli ping
# Should return: PONG

# Get memory stats
docker exec redis redis-cli INFO memory

# Check connected clients
docker exec redis redis-cli CLIENT LIST

# Monitor commands in real-time
docker exec redis redis-cli MONITOR
```

### Maintenance

**Backup Redis:**
```bash
# Redis automatically persists to /data/dump.rdb
# Backup the Redis data volume
docker exec redis redis-cli SAVE
tar -czf redis-backup-$(date +%Y%m%d).tar.gz ./data/redis

# Or copy the RDB file
docker cp redis:/data/dump.rdb redis-backup-$(date +%Y%m%d).rdb
```

**Restore Redis:**
```bash
# Stop Redis
docker compose stop redis

# Restore RDB file
docker cp redis-backup-20240115.rdb redis:/data/dump.rdb

# Start Redis
docker compose start redis
```

### Performance Monitoring

**Check Performance:**
```bash
# Redis INFO stats
docker exec redis redis-cli INFO stats

# Slow log (queries >10ms)
docker exec redis redis-cli SLOWLOG GET 10

# Memory usage by key pattern
docker exec redis redis-cli --bigkeys
```

**Memory Management:**
```bash
# Check memory usage
docker exec redis redis-cli INFO memory | grep used_memory_human

# Check max memory setting
docker exec redis redis-cli CONFIG GET maxmemory

# Set max memory (if needed)
docker exec redis redis-cli CONFIG SET maxmemory 512mb
docker exec redis redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### Troubleshooting

**Can't connect to Redis:**
```bash
# Check Redis is running
docker compose ps redis

# Check health
docker exec redis redis-cli ping

# Check logs
docker compose logs redis

# Restart Redis
docker compose restart redis
```

**Redis out of memory:**
```bash
# Check memory usage
docker exec redis redis-cli INFO memory

# Clear all cache (WARNING: will impact performance temporarily)
docker exec redis redis-cli FLUSHALL

# Increase memory limit in docker-compose.yml
services:
  redis:
    deploy:
      resources:
        limits:
          memory: 512M  # Increase as needed
```

**High CPU usage:**
```bash
# Check slow queries
docker exec redis redis-cli SLOWLOG GET 20

# Monitor commands
docker exec redis redis-cli MONITOR

# Check for expensive operations (KEYS *, SMEMBERS on large sets)
```

---

## Database Creation Script

The `create-multiple-postgres-databases.sh` script automatically creates all required databases on first PostgreSQL startup.

**Script Location:** `scripts/create-multiple-postgres-databases.sh`

**How It Works:**
1. Reads `POSTGRES_MULTIPLE_DATABASES` env var
2. Creates each database if it doesn't exist
3. Runs on container first start (docker-entrypoint-initdb.d)

**Manual Database Creation:**
```bash
# Create new database
docker exec postgres createdb -U homelab newdatabase

# Grant permissions
docker exec postgres psql -U homelab -c "GRANT ALL PRIVILEGES ON DATABASE newdatabase TO homelab;"
```

---

## Resource Usage

### Typical Resource Consumption

**PostgreSQL:**
- **RAM**: 100-300 MB (idle), 500 MB - 1 GB (active)
- **Disk**: 500 MB - 5 GB (depends on photo library size)
- **CPU**: Low (spikes during queries)

**Redis:**
- **RAM**: 50-200 MB (depends on cache size)
- **Disk**: Minimal (persistence)
- **CPU**: Very low

### Monitoring Resources

```bash
# Check container stats
docker stats postgres redis

# Check disk usage
df -h
du -sh ./data/postgres
du -sh ./data/redis

# Check memory usage
docker exec postgres free -h
docker exec redis free -h
```

---

## Security Best Practices

### PostgreSQL

1. **Strong passwords** - Auto-generated, store securely
2. **No external exposure** - Port 5432 not exposed to host
3. **Regular backups** - Automate database backups
4. **Update regularly** - Keep PostgreSQL updated
5. **Principle of least privilege** - Each app uses own database

### Redis

1. **Password protection** - Always require password
2. **No external exposure** - Port 6379 not exposed
3. **Regular backups** - Backup Redis data volume
4. **Disable dangerous commands** (if needed):
   ```yaml
   command: redis-server --requirepass ${REDIS_PASSWORD} --rename-command FLUSHALL ""
   ```

---

## Upgrading

### PostgreSQL

**Before Upgrading:**
1. Backup all databases
2. Check release notes for breaking changes
3. Test upgrade on copy first

**Upgrade Process:**
```bash
# Backup databases
docker exec postgres pg_dumpall -U homelab > backup-before-upgrade.sql

# Pull new image
docker compose pull postgres

# Recreate container
docker compose up -d postgres

# Verify
docker compose logs postgres
docker exec postgres psql -U homelab -c 'SELECT version();'
```

### Redis

**Redis Upgrade:**
```bash
# Backup
docker exec redis redis-cli SAVE
docker cp redis:/data/dump.rdb redis-backup.rdb

# Pull new image
docker compose pull redis

# Recreate
docker compose up -d redis

# Verify
docker exec redis redis-cli INFO server | grep redis_version
```

---

## Troubleshooting Common Issues

### Services Can't Connect to Database

**Check network:**
```bash
# Verify services are on backend network
docker network inspect homelab_backend

# Test connection from service
docker exec immich-server ping postgres
docker exec uptime-kuma ping postgres
```

**Check database exists:**
```bash
docker exec postgres psql -U homelab -c '\l' | grep immich
```

**Check credentials:**
- Verify `.env` file has correct `DB_PASSWORD`
- Check service configuration matches

### Database Corruption

**Check and repair:**
```bash
# Stop all services using database
docker compose stop immich-server uptime-kuma

# Check database integrity
docker exec postgres pg_dump -U homelab immich > /dev/null

# If corruption detected
docker exec postgres reindexdb -U homelab immich

# Restart services
docker compose up -d
```

### Slow Database Performance

**Analyze and optimize:**
```bash
# Update statistics
docker exec postgres vacuumdb -U homelab --all --analyze

# Check slow queries (requires pg_stat_statements extension)
docker exec postgres psql -U homelab -c "SELECT query, calls, total_time FROM pg_stat_statements ORDER BY total_time DESC LIMIT 5;"

# Check table bloat
docker exec postgres psql -U homelab -d immich -c "VACUUM FULL ANALYZE;"
```

---

## Data Persistence

**PostgreSQL Data:**
- Volume: `postgres_data`
- Location: `/var/lib/docker/volumes/homelab_postgres_data`
- Contains: All database files

**Redis Data:**
- Volume: `redis_data`
- Location: `/var/lib/docker/volumes/homelab_redis_data`
- Contains: dump.rdb (Redis snapshot)

**Backup Strategy:**
- **PostgreSQL**: SQL dumps (logical backup)
- **Redis**: RDB file (snapshot)
- **Complete**: Backup entire data directory
- **Frequency**: Daily (automated via cron)
- **Retention**: 30 days

---

## Common Access Methods

### PostgreSQL

**From Host:**
```bash
docker exec -it postgres psql -U homelab
```

**From Service Container:**
```bash
# Services use internal hostname: postgres
docker exec jellyseerr env | grep DB_HOST
# DB_HOST=postgres
```

### Redis

**From Host:**
```bash
docker exec -it redis redis-cli
AUTH your-password
```

**From Service Container:**
```bash
# Services use internal hostname: redis
docker exec immich-server env | grep REDIS_HOSTNAME
# REDIS_HOSTNAME=redis
```

---

## Summary

Both PostgreSQL and Redis are critical backend services that require:
- ✅ Regular backups (automated daily)
- ✅ Health monitoring (via Uptime Kuma)
- ✅ Proper resource allocation
- ✅ Security best practices (passwords, no external exposure)
- ✅ Occasional maintenance (vacuum, analyze)

**These services should generally be left alone** - they run automatically and services depend on them. Only access for:
- Backups
- Troubleshooting
- Performance tuning
- Maintenance

**Access:** Internal Docker network only (not exposed externally)
