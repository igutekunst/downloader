#!/bin/bash
# Complete server setup script for downloader
# Run as root on a fresh Debian 13 server
#
# Usage: ./setup.sh [--skip-ssl]
#   --skip-ssl: Skip SSL certificate (useful for testing)

set -euo pipefail

# Configuration
APP_USER="downloader"
APP_DIR="/opt/downloader"
VOLUME_DIR="/mnt/volume_sfo3_01"
DOMAIN="downloader.dancingvoid.com"
EMAIL="admin@dancingvoid.com"

# Parse arguments
SKIP_SSL=false
for arg in "$@"; do
    case $arg in
        --skip-ssl) SKIP_SSL=true ;;
    esac
done

echo "============================================"
echo "  Downloader Server Setup"
echo "  Domain: $DOMAIN"
echo "============================================"
echo ""

# 1. Update system
echo "[1/10] Updating system..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# 2. Install dependencies
echo "[2/10] Installing dependencies..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    ufw \
    git \
    rsync

# 3. Install Docker (official method)
echo "[3/10] Installing Docker..."
if ! command -v docker &> /dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "Docker already installed, skipping..."
fi

# 4. Install nginx and certbot
echo "[4/10] Installing nginx and certbot..."
apt-get install -y nginx certbot python3-certbot-nginx

# 5. Create application user
echo "[5/10] Creating application user..."
if ! id "$APP_USER" &>/dev/null; then
    useradd -r -m -d "$APP_DIR" -s /bin/bash "$APP_USER"
    usermod -aG docker "$APP_USER"
    echo "Created user: $APP_USER"
else
    echo "User $APP_USER already exists"
fi

# Get user IDs for .env config
USER_UID=$(id -u "$APP_USER")
USER_GID=$(id -g "$APP_USER")

# 6. Setup directories
echo "[6/10] Setting up directories..."
mkdir -p "$APP_DIR"
mkdir -p "$VOLUME_DIR/downloads/complete"
mkdir -p "$VOLUME_DIR/downloads/incomplete"
mkdir -p "$APP_DIR/config/qbittorrent"
mkdir -p "$APP_DIR/config/keys"

# Symlink downloads to volume
ln -sfn "$VOLUME_DIR/downloads" "$APP_DIR/downloads"

# Set ownership
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$APP_USER:$APP_USER" "$VOLUME_DIR/downloads"

# 7. Configure firewall with Docker compatibility
echo "[7/10] Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https

# Add UFW rules for Docker compatibility
cat >> /etc/ufw/after.rules << 'EOF'

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [ACCEPT]
:ufw-docker-logging-deny - [ACCEPT]
:DOCKER-USER - [ACCEPT]
-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN
-A DOCKER-USER -p tcp -m tcp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN

-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP

COMMIT
# END UFW AND DOCKER
EOF

ufw --force enable

# 8. Configure nginx (port 8081 for qBittorrent proxy)
echo "[8/10] Configuring nginx..."
cat > /etc/nginx/sites-available/downloader.conf << 'NGINX_EOF'
# Nginx configuration for downloader.dancingvoid.com

upstream qbittorrent {
    server 127.0.0.1:8081;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name downloader.dancingvoid.com;

    access_log /var/log/nginx/downloader.access.log;
    error_log /var/log/nginx/downloader.error.log;

    client_max_body_size 100M;

    location / {
        proxy_pass http://qbittorrent;
        proxy_http_version 1.1;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_buffering off;
    }
}
NGINX_EOF

# Enable site
ln -sf /etc/nginx/sites-available/downloader.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload
nginx -t
systemctl reload nginx

# 9. Get SSL certificate
echo "[9/10] Obtaining SSL certificate..."
if [ "$SKIP_SSL" = true ]; then
    echo "Skipping SSL (--skip-ssl flag set)"
else
    certbot --nginx -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
fi

# 10. Restart Docker to apply UFW rules
echo "[10/10] Restarting Docker..."
systemctl restart docker

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "User: $APP_USER (UID=$USER_UID, GID=$USER_GID)"
echo "App directory: $APP_DIR"
echo "Downloads: $APP_DIR/downloads -> $VOLUME_DIR/downloads"
echo ""
echo "Add these to your .env file:"
echo "  PUID=$USER_UID"
echo "  PGID=$USER_GID"
echo ""
echo "Next steps:"
echo "1. Sync project files to $APP_DIR"
echo "2. Create $APP_DIR/.env with credentials"
echo "3. Start: sudo -u $APP_USER docker compose -f docker-compose.yml -f deploy/docker-compose.prod.yml up -d"
echo ""
echo "Site: https://$DOMAIN"
echo ""
