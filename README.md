# Downloader

Generic download tool with VPN protection and automatic SFTP upload.

## POC: BitTorrent

- **Client**: qBittorrent
- **VPN**: ProtonVPN
- **Deploy**: Docker Compose

## Features

- VPN kill-switch (no traffic leaks)
- Filesystem watcher triggers upload on completion
- SFTP upload with `.uploading` extension, renamed on success
- Uploads preserve original file/folder structure

## Stack

```
ProtonVPN ──network──▶ qBittorrent ──complete──▶ Uploader ──sftp──▶ Remote
```

## Config

Copy `.env.example` to `.env` and configure:
- ProtonVPN credentials
- SFTP destination
