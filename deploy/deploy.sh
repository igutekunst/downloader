#!/bin/bash
# Deploy script - run from your local machine in the project root
# Usage: ./deploy/deploy.sh

set -euo pipefail

REMOTE="downloader"
APP_DIR="/opt/downloader"
APP_USER="downloader"

echo "=== Deploying to $REMOTE ==="

# Sync files (excluding sensitive stuff and runtime data)
echo "[1/4] Syncing files..."
rsync -avz --delete \
    --exclude '.env' \
    --exclude '.git' \
    --exclude 'downloads' \
    --exclude 'config/qbittorrent/' \
    --exclude 'config/keys/' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude '.DS_Store' \
    --exclude '.venv' \
    --exclude 'venv' \
    ./ "$REMOTE:$APP_DIR/"

# Fix ownership
echo "[2/4] Fixing ownership..."
ssh "$REMOTE" "chown -R $APP_USER:$APP_USER $APP_DIR"

# Ensure downloads symlink exists
ssh "$REMOTE" "ln -sfn /mnt/volume_sfo3_01/downloads $APP_DIR/downloads"

# Build and restart
echo "[3/4] Building and restarting containers..."
ssh "$REMOTE" "sudo -u $APP_USER bash -c 'cd $APP_DIR && docker compose -f docker-compose.yml -f deploy/docker-compose.prod.yml up -d --build --remove-orphans'"

# Show status
echo "[4/4] Checking status..."
ssh "$REMOTE" "sudo -u $APP_USER docker compose -f $APP_DIR/docker-compose.yml -f $APP_DIR/deploy/docker-compose.prod.yml ps"

echo ""
echo "=== Deployment complete ==="
echo "Visit: https://downloader.dancingvoid.com"
