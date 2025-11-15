# Gitea Self-Hosted Git + CI/CD Setup

**Status:** ✅ Configured and Ready
**Access:** Via Tailscale at `http://homelab-media:3000`

## Overview

Your homelab now includes a complete self-hosted DevOps platform:

- **Gitea**: Self-hosted Git service (like GitHub)
- **Gitea Actions**: Built-in CI/CD (GitHub Actions compatible)
- **Auto-Deployment**: Push to main → Automatic deployment
- **PostgreSQL Backend**: Uses your shared database

## Services Added

| Service | Port | Purpose |
|---------|------|---------|
| Gitea | 3000 (HTTP), 2222 (SSH) | Git server + Web UI |
| Gitea Runner | Internal | CI/CD workflow execution |

**Database**: `gitea` (in shared PostgreSQL)

## Initial Setup

### 1. Generate Gitea Tokens

```bash
# SSH to your homelab server
ssh user@homelab-ip
cd /opt/homelab

# Generate secret keys
openssl rand -base64 32  # For GITEA_SECRET_KEY
openssl rand -base64 32  # For GITEA_INTERNAL_TOKEN

# Add to .env
nano .env
```

Add these lines to `.env`:
```bash
GITEA_DOMAIN=homelab-media
GITEA_ROOT_URL=http://homelab-media:3000/
GITEA_SECRET_KEY=<generated_key_1>
GITEA_INTERNAL_TOKEN=<generated_key_2>
GITEA_RUNNER_TOKEN=  # Will get this after first login
```

### 2. Deploy Gitea

```bash
docker compose up -d gitea
```

### 3. Complete Web-Based Setup

1. **Access Gitea**: `http://homelab-media:3000` (via Tailscale)

2. **Initial configuration will be pre-filled**:
   - Database: PostgreSQL (already configured)
   - Server settings: Already set via environment variables

3. **Create admin account**:
   - Username: `admin` (or your preference)
   - Email: your-email@example.com
   - Password: (strong password)

4. **Click "Install Gitea"** - Setup complete!

### 4. Set Up Gitea Actions Runner

1. **Login to Gitea as admin**

2. **Go to**: Site Administration → Actions → Runners

3. **Click "Create Runner"**

4. **Copy the Registration Token**

5. **Add token to .env**:
   ```bash
   nano .env
   # Add: GITEA_RUNNER_TOKEN=<copied_token>
   ```

6. **Start the runner**:
   ```bash
   docker compose up -d gitea-runner
   ```

7. **Verify runner is connected**:
   - Back in Gitea → Actions → Runners
   - You should see "homelab-runner" with status "Idle"

## Migrate Your Repository

### Option A: Push from GitHub (Recommended)

```bash
# On your laptop, in your homelab repo
git remote add gitea ssh://git@homelab-media:2222/admin/homelab.git

# Push everything to Gitea
git push gitea main

# (Optional) Make Gitea your primary remote
git remote rename origin github
git remote rename gitea origin
```

### Option B: Import from GitHub

1. In Gitea: **New Repository** → **Migration** → **GitHub**
2. Enter GitHub URL
3. Import (will pull all commits and branches)

## Auto-Deployment Workflow

The workflow `.gitea/workflows/deploy.yml` runs automatically on every push to `main`:

```yaml
Trigger: Push to main branch
Steps:
  1. Checkout code
  2. Pull latest Docker images
  3. Deploy stack (docker compose up -d)
  4. Wait for services to stabilize
  5. Verify critical services (postgres, redis, gitea)
  6. Clean up old images
  7. Report status
```

### How It Works

```
You push code → Gitea receives push
                    ↓
             Gitea Actions triggers workflow
                    ↓
             Runner executes deployment
                    ↓
             docker compose pull
                    ↓
             docker compose up -d
                    ↓
             Verify services healthy
                    ↓
             Done! ✅
```

### Manual Trigger

You can also trigger deployment manually:

1. Go to: Repository → Actions
2. Click on "Deploy Homelab Stack"
3. Click "Run workflow"
4. Select branch (usually `main`)
5. Click "Run"

## Usage

### Everyday Git Operations

```bash
# Clone your repo (first time)
git clone ssh://git@homelab-media:2222/admin/homelab.git
cd homelab

# Make changes
vim docker-compose.yml

# Commit and push
git add .
git commit -m "Add new service"
git push  # Automatically deploys!

# Check deployment status
# Go to Gitea → Actions → See workflow run
```

### SSH Key Setup

```bash
# On your laptop, generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy public key
cat ~/.ssh/id_ed25519.pub

# Add to Gitea:
# User Settings → SSH Keys → Add Key → Paste
```

Now you can use `git clone`, `git push`, etc. without passwords!

## Access Configuration

### Current: Tailscale Only (Private)

Gitea is currently accessible only via Tailscale VPN:
- URL: `http://homelab-media:3000`
- SSH: `ssh://git@homelab-media:2222`

### Optional: Add Cloudflare Tunnel (Public)

If you want to access Gitea from anywhere (not just Tailscale):

1. **Add to Cloudflare Tunnel routes**:
   - Public hostname: `git.glaance.io`
   - Service: `http://gitea:3000`

2. **Update .env**:
   ```bash
   GITEA_DOMAIN=git.glaance.io
   GITEA_ROOT_URL=https://git.glaance.io/
   ```

3. **Restart Gitea**:
   ```bash
   docker compose restart gitea
   ```

**Security Note**: Only do this if you need external access. Tailscale-only is more secure.

## Features

### ✅ What You Get

- **Private Git Hosting**: All your code on your own server
- **Web IDE**: Edit files directly in browser
- **Pull Requests**: Full PR workflow like GitHub
- **Issues & Wiki**: Built-in project management
- **Actions/CI**: Automated workflows (GitHub Actions syntax)
- **Auto-Deploy**: Push to main = instant deployment
- **Webhooks**: Trigger external services
- **Organizations**: Manage multiple repos
- **Fine-Grained Permissions**: User/team access control

### 📊 PostgreSQL Integration

Gitea uses your shared PostgreSQL database:
- Database: `gitea`
- Automatic backups via postgres backups
- No SQLite files to manage

## Workflow Examples

### Example 1: Add a New Service

```bash
# Edit docker-compose.yml
vim docker-compose.yml
# Add new service

# Commit and push
git add docker-compose.yml
git commit -m "Add new monitoring service"
git push

# Gitea Actions automatically:
# - Pulls new images
# - Deploys the stack
# - Verifies services are healthy
# You get notification when done!
```

### Example 2: Update Configuration

```bash
# Update .env.example with new variables
vim .env.example

git add .env.example
git commit -m "Add environment variables for new service"
git push

# Auto-deploys (but you'll need to manually update .env on server)
```

## Troubleshooting

### Runner not connecting

```bash
# Check runner logs
docker logs gitea-runner

# Verify token is correct
docker exec gitea-runner cat /data/.runner

# Restart runner
docker compose restart gitea-runner
```

### Workflow failing

```bash
# Check workflow logs in Gitea UI:
# Repository → Actions → Click on failed run → View logs

# Common issues:
# - Docker socket permissions
# - Service health check timeout
# - Image pull failures
```

### Can't push to Gitea

```bash
# Verify SSH key is added to Gitea
# User Settings → SSH Keys

# Test SSH connection
ssh -T git@homelab-media -p 2222
# Should say: "Hi there, <username>! You've successfully authenticated"

# Check Gitea is running
docker ps | grep gitea
```

### Database connection errors

```bash
# Verify postgres is healthy
docker exec postgres pg_isready -U homelab

# Check gitea database exists
docker exec postgres psql -U homelab -c '\l' | grep gitea

# Check Gitea logs
docker logs gitea
```

## Backup & Recovery

### Backup Gitea Data

```bash
# Gitea data is in ./data/gitea
# Database is in postgres (backed up with other databases)

# Backup repositories and configuration
tar -czf gitea-backup-$(date +%Y%m%d).tar.gz ./data/gitea

# Backup gitea database specifically
docker exec postgres pg_dump -U homelab gitea > gitea-db-backup-$(date +%Y%m%d).sql
```

### Restore from Backup

```bash
# Stop Gitea
docker compose stop gitea gitea-runner

# Restore data directory
tar -xzf gitea-backup-YYYYMMDD.tar.gz

# Restore database
cat gitea-db-backup-YYYYMMDD.sql | docker exec -i postgres psql -U homelab gitea

# Restart Gitea
docker compose up -d gitea gitea-runner
```

## Resource Usage

**Gitea**: ~100-150MB RAM
**Gitea Runner**: ~50-100MB RAM (idle), more during builds
**Total**: ~150-250MB RAM

Very lightweight compared to GitLab (~4GB) or self-hosted GitHub Enterprise.

## Security Best Practices

1. ✅ **Tailscale Access Only** (unless you need external access)
2. ✅ **Strong Admin Password** (use password manager)
3. ✅ **SSH Keys** (never commit private keys!)
4. ✅ **Regular Backups** (automate this)
5. ✅ **Keep Updated** (`docker compose pull gitea`)
6. ⚠️  **Never expose port 3000 to internet** without Cloudflare protection
7. ⚠️  **Secrets in .env** never committed (in .gitignore)

## Advanced: GitHub Mirror (Optional)

Keep GitHub as an upstream backup:

```bash
# Add GitHub as a secondary remote
git remote add github https://github.com/your-username/homelab.git

# Push to both
git push origin main  # Gitea (auto-deploys)
git push github main  # GitHub (backup)

# Or create alias to push to both
git config alias.pushall '!git push origin && git push github'
# Now: git pushall
```

## Migration Complete!

You've successfully set up:

- ✅ Self-hosted Git (Gitea)
- ✅ CI/CD platform (Gitea Actions)
- ✅ Auto-deployment on push to main
- ✅ PostgreSQL backend integration
- ✅ Secure Tailscale-only access

No more dependency on GitHub/GitLab for your homelab! 🎉

---

**Next Steps**:
1. Complete initial Gitea setup (web UI)
2. Create admin account
3. Set up Actions runner
4. Push your code to Gitea
5. Make a test commit and watch auto-deployment!

**Documentation**:
- Gitea Docs: https://docs.gitea.io
- Gitea Actions: https://docs.gitea.io/en-us/usage/actions/overview/
- GitHub Actions Syntax: https://docs.github.com/en/actions (compatible!)
