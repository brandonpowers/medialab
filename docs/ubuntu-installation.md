# Ubuntu Server Installation Guide

Complete guide for installing Ubuntu Server 24.04 LTS for the homelab stack.

## Prerequisites

- Server hardware with:
  - Intel CPU with QuickSync GPU (or AMD equivalent)
  - Blu-ray/DVD optical drive (for ARM)
  - Minimum 16GB RAM (24GB+ recommended)
  - 100GB+ storage for system
  - Separate storage for media files
- USB drive for Ubuntu installer (4GB+)

## Download Ubuntu Server

1. **Download Ubuntu Server 24.04 LTS**
   - URL: https://ubuntu.com/download/server
   - Choose: Ubuntu Server 24.04 LTS (64-bit)

2. **Create bootable USB**
   - **Linux/Mac**: `dd if=ubuntu-24.04-live-server-amd64.iso of=/dev/sdX bs=4M status=progress`
   - **Windows**: Use Rufus or Balena Etcher

## Installation Steps

### 1. Boot from USB

1. Insert USB drive
2. Boot from USB (usually F12/F11 during startup)
3. Select "Try or Install Ubuntu Server"

### 2. Language and Keyboard

1. Select language: **English**
2. Select keyboard layout: **English (US)** (or your layout)

### 3. Installation Type

1. Choose: **Ubuntu Server** (not minimized)
2. Continue

### 4. Network Configuration

**Option A: DHCP (Simpler)**
- Accept default DHCP configuration
- You'll set static IP after installation

**Option B: Static IP (Recommended)**
- Edit the network interface
- Set static IP: `192.168.8.202` (or your preference)
- Subnet: `192.168.8.0/24`
- Gateway: `192.168.8.1` (your router)
- DNS: `1.1.1.1,8.8.8.8`

### 5. Proxy Configuration

- Leave blank unless you use a proxy
- Continue

### 6. Ubuntu Archive Mirror

- Accept default: `http://archive.ubuntu.com/ubuntu`
- Continue

### 7. Storage Configuration

**Option A: Entire Disk (Simpler)**
1. Select: **Use an entire disk**
2. Choose your system disk
3. **Do NOT** select "Set up this disk as an LVM group" (unless you want LVM)
4. Continue

**Option B: ZFS (Recommended for Snapshots)**
1. Select: **Use an entire disk and set up ZFS**
2. Choose your system disk
3. This enables easy system snapshots
4. Continue

**Option C: Manual Partitioning (Advanced)**
- Only if you have specific requirements

Review the partition layout:
```
/boot/efi    512MB   FAT32
/            Rest    ext4 or ZFS
```

Confirm changes: **Continue**

### 8. Profile Setup

- **Your name**: Your full name
- **Server name**: `homelab-media` (recommended)
- **Username**: Your username (e.g., `brandon`)
- **Password**: Strong password
- Confirm password

### 9. SSH Setup

- Select: ✅ **Install OpenSSH server**
- Do NOT import SSH keys (unless you want to)
- Continue

### 10. Featured Server Snaps

- **Do NOT select any snaps** (we'll install Docker via apt)
- Leave all unchecked
- Continue

### 11. Installation

- Installation begins (takes 5-10 minutes)
- Wait for "Installation complete!"
- Select: **Reboot Now**
- Remove USB drive when prompted

## Post-Installation Setup

### 1. Login

```bash
# Login with your username/password
ssh username@192.168.8.202
```

### 2. Update System

```bash
sudo apt update
sudo apt upgrade -y
```

### 3. Install Basic Tools

```bash
sudo apt install -y git curl wget htop
```

### 4. Set Static IP (If Using DHCP)

Edit netplan configuration:

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Update to:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s31f6:  # Your interface name (check with: ip a)
      addresses:
        - 192.168.8.202/24
      routes:
        - to: default
          via: 192.168.8.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

Apply changes:

```bash
sudo netplan apply
```

### 5. Configure Hostname (Optional)

If you didn't set it during installation:

```bash
sudo hostnamectl set-hostname homelab-media
```

### 6. Enable Automatic Security Updates (Optional)

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Select: **Yes**

## Install Homelab Stack

Now you're ready to deploy the homelab:

```bash
# Clone repository
sudo git clone https://github.com/yourusername/homelab.git /opt/homelab

# Change ownership
sudo chown -R $(whoami):$(whoami) /opt/homelab

# Run setup script
cd /opt/homelab
sudo ./scripts/setup-homelab.sh
```

The setup script will:
- Install Docker and Docker Compose
- Configure media directories
- Generate passwords and API keys
- Start all services
- Configure ARM for automatic disc ripping

## Verify Installation

### Check Services

```bash
cd /opt/homelab
docker compose ps
```

All services should show "Up" status.

### Access Web UIs

**Public Services** (via Cloudflare Tunnel - after configuration):
- Jellyfin: https://jellyfin.yourdomain.com
- Jellyseerr: https://jellyseerr.yourdomain.com
- Homarr: https://homarr.yourdomain.com

**Private Services** (LAN only):
- Sonarr: http://SERVER_IP:8989
- Radarr: http://SERVER_IP:7878
- Prowlarr: http://SERVER_IP:9696
- ARM: http://SERVER_IP:8090

All services accessible on your local network via `http://SERVER_IP:PORT`

## Troubleshooting

### Can't SSH to server

```bash
# Check if SSH is running on server (from console)
sudo systemctl status ssh

# Start SSH if needed
sudo systemctl start ssh
sudo systemctl enable ssh
```

### Network not working

```bash
# Check network interfaces
ip a

# Check routes
ip route

# Test connectivity
ping 8.8.8.8
```

### Services won't start

```bash
# Check Docker service
sudo systemctl status docker

# Check logs
docker compose logs

# Restart services
docker compose down
docker compose up -d
```

## Next Steps

After successful installation:

1. **[Configure Cloudflare Tunnel](networking.md#cloudflare-tunnel)** - For remote access (optional)
2. **[Set up media libraries](../README.md#initial-setup)** - Configure Sonarr/Radarr
3. **[Configure ARM](../README.md#blu-ray-ripping)** - Test automatic disc ripping

## Backup Strategy

Important directories to backup regularly:
- `./data/` - All service configurations and databases
- `.env` - Your environment configuration
- `docker-compose.yml` - Service definitions

```bash
# Create backup
tar -czf homelab-backup-$(date +%Y%m%d).tar.gz ./data .env docker-compose.yml
```
