# Deployment Guide

Deploy downloader to `downloader.dancingvoid.com`.

## Initial Server Setup (one-time)

SSH into the server and run:

```bash
ssh downloader

# Download and run setup script (or copy it manually)
curl -O https://raw.githubusercontent.com/yourusername/downloader/master/deploy/setup.sh
chmod +x setup.sh
./setup.sh
```

Or manually copy and run:

```bash
scp deploy/setup.sh downloader:/root/
ssh downloader "chmod +x /root/setup.sh && /root/setup.sh"
```

## Configure nginx

```bash
ssh downloader

# Copy nginx config
cp /opt/downloader/deploy/nginx/downloader.conf /etc/nginx/sites-available/

# Enable site
ln -s /etc/nginx/sites-available/downloader.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload
nginx -t
systemctl reload nginx
```

## Get SSL Certificate

```bash
ssh downloader
certbot --nginx -d downloader.dancingvoid.com
```

Follow the prompts. Certbot will automatically update the nginx config.

## Create .env File

On the server, create `/opt/downloader/.env`:

```bash
ssh downloader
sudo -u downloader nano /opt/downloader/.env
```

Copy contents from `.env.example` and fill in:
- `PROTONVPN_USER` and `PROTONVPN_PASS` (OpenVPN credentials from ProtonVPN)
- `SFTP_HOST`, `SFTP_USER`, etc.
- `PUID` and `PGID` - get these from setup.sh output, or run:
  ```bash
  id -u downloader  # PUID
  id -g downloader  # PGID
  ```

## Deploy the App

From your local machine:

```bash
./deploy/deploy.sh
```

## Enable systemd Service (optional)

For auto-start on boot:

```bash
ssh downloader
cp /opt/downloader/deploy/systemd/downloader.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable downloader
systemctl start downloader
```

## Manual Operations

### View logs
```bash
ssh downloader
sudo -u downloader docker compose -f /opt/downloader/docker-compose.yml logs -f
```

### Restart services
```bash
ssh downloader
sudo -u downloader docker compose -f /opt/downloader/docker-compose.yml restart
```

### Update deployment
```bash
# From local machine
./deploy/deploy.sh
```

### Check VPN status
```bash
ssh downloader
sudo -u downloader docker exec gluetun curl -s ifconfig.me
```

## Directory Structure on Server

```
/opt/downloader/           # App directory (owned by downloader user)
├── docker-compose.yml
├── .env                   # Your credentials (create manually)
├── config/
│   ├── qbittorrent/       # qBittorrent config (persistent)
│   └── keys/              # SFTP keys (auto-generated)
├── downloads -> /mnt/volume_sfo3_01/downloads  # Symlink to volume
└── services/
    └── uploader/

/mnt/volume_sfo3_01/       # 100GB volume
└── downloads/
    ├── complete/          # Finished downloads
    └── incomplete/        # In-progress downloads
```

## Firewall Rules

The setup script configures:
- SSH (22): allowed
- HTTP (80): allowed (redirects to HTTPS)
- HTTPS (443): allowed
- All other incoming: denied

## Security Notes

1. qBittorrent WebUI is only exposed via nginx (localhost:8080)
2. SSL/HTTPS enforced via Let's Encrypt
3. VPN kill-switch prevents torrent traffic leaks
4. Firewall denies all unnecessary ports
5. App runs as non-root `downloader` user
