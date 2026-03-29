# E2EChat

Self-hosted, end-to-end encrypted Matrix communication stack with voice/video calling. Deploy to any VPS in minutes.

## What You Get

- **Encrypted messaging** — 1:1 and group chats with E2EE enabled by default
- **Voice/video calls** — Group calls with screen sharing via Element Call + LiveKit
- **Browser access** — Element Web so anyone can chat without installing an app
- **Federation** — Talk to users on any Matrix server worldwide
- **Full data sovereignty** — Everything runs on your server, you own the data

## Architecture

```
Internet
  |
  |-- TCP 80/443/8448 --> Caddy (auto-TLS reverse proxy)
  |     |-- chat.example.com/_matrix/*     --> Continuwuity (homeserver)
  |     |-- chat.example.com/.well-known/* --> Caddy inline JSON
  |     |-- call.example.com/sfu/*         --> lk-jwt-service (call auth)
  |     |-- call.example.com/*             --> LiveKit (media SFU)
  |     |-- app.example.com/*              --> Element Web (browser client)
  |
  |-- TCP 7881       --> LiveKit (WebRTC TCP fallback)
  |-- UDP 3478       --> LiveKit (built-in TURN)
  |-- UDP 50100-50200 --> LiveKit (WebRTC media)
  |-- UDP 50300-50400 --> LiveKit (TURN relay)
```

| Service | Purpose | RAM |
|---------|---------|-----|
| Continuwuity | Matrix homeserver (Rust) | ~100 MB |
| LiveKit | Voice/video media server | ~50 MB idle |
| lk-jwt-service | Element Call authentication | ~20 MB |
| Caddy | Reverse proxy + auto-TLS | ~15 MB |
| Element Web | Browser client (static files) | ~10 MB |
| **Total** | | **~200 MB** |

## Prerequisites

- A server with 1+ GB RAM (Oracle Cloud Always Free, Hetzner, DigitalOcean, etc.)
- A domain with DNS control (need 3 A records)
- Docker Engine 20+ and Docker Compose v2+
- Ports 80, 443, 8448, 7881, 3478, 50100-50400 open

## Quick Start

### Oracle Cloud (recommended)

When creating your Oracle Cloud instance, paste `cloud-init.sh` into the **Cloud-Init Script** field. This automatically installs Docker, opens firewall ports, and blocks internal-only ports. Once the instance is ready:

```bash
# 1. SSH into your instance
ssh ubuntu@<server-ip>

# 2. Verify cloud-init completed
ls ~/.cloud-init-complete

# 3. Clone the repo
git clone https://github.com/ctf05/E2EChat.git
cd E2EChat

# 4. Run setup (generates secrets, builds configs)
./scripts/setup.sh

# 5. Set up DNS records (setup.sh prints instructions)

# 6. Start the stack
docker compose up -d

# 7. Create your first admin user
./scripts/create-user.sh --admin yourusername

# 8. Log in at https://app.yourdomain.com
```

### Other VPS

```bash
# 1. Install Docker: https://docs.docker.com/engine/install/
# 2. Open firewall ports (see Firewall Setup below)

# 3. Clone the repo
git clone https://github.com/ctf05/E2EChat.git
cd E2EChat

# 4. Run setup (generates secrets, builds configs)
./scripts/setup.sh

# 5. Set up DNS and firewall (setup.sh prints instructions)

# 6. Start the stack
docker compose up -d

# 7. Create your first admin user
./scripts/create-user.sh --admin yourusername

# 8. Log in at https://app.yourdomain.com
```

## DNS Setup

Create three A records pointing to your server's public IP:

| Record | Value |
|--------|-------|
| `chat.yourdomain.com` | `<server-ip>` |
| `call.yourdomain.com` | `<server-ip>` |
| `app.yourdomain.com` | `<server-ip>` |

All three point to the same IP. Replace `yourdomain.com` with your actual domain.

## Firewall Setup

### Required Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP (ACME challenges + redirect) |
| 443 | TCP + UDP | HTTPS + HTTP/3 |
| 8448 | TCP | Matrix federation |
| 7881 | TCP | WebRTC TCP fallback |
| 3478 | UDP | TURN server |
| 50100-50200 | UDP | WebRTC media streams |
| 50300-50400 | UDP | TURN relay |

Block ports **7880** and **8080** externally (internal services only).

### Ubuntu (UFW)

```bash
sudo ufw allow 80,443,8448,7881/tcp
sudo ufw allow 443/udp
sudo ufw allow 3478/udp
sudo ufw allow 50100:50400/udp
sudo ufw deny 7880/tcp
sudo ufw deny 8080/tcp
```

### Oracle Cloud

Use `cloud-init.sh` when creating the instance (paste into the Cloud-Init Script field). It handles iptables automatically.

If you already have an instance, run it manually as root:

```bash
sudo bash cloud-init.sh
```

You also need ingress rules in the **VCN Security List** (OCI Console: **Networking > Virtual Cloud Networks > [your VCN] > Security Lists**):

| Source | Protocol | Dest Port | Description |
|--------|----------|-----------|-------------|
| 0.0.0.0/0 | TCP | 80, 443, 8448, 7881 | HTTP, HTTPS, federation, WebRTC TCP |
| 0.0.0.0/0 | UDP | 443, 3478, 50100-50400 | HTTP/3, TURN, WebRTC media |

## User Management

### Create a regular user

```bash
./scripts/create-user.sh alice
```

### Create an admin user

```bash
./scripts/create-user.sh --admin alice
```

### Share registration

Give users your registration token (shown during setup, stored in `.env`) and your homeserver address. They can register in Element or any Matrix client.

## Client Setup

### Element Web (browser)

Go to `https://app.yourdomain.com` — the homeserver is pre-configured.

### Element X (mobile — recommended)

1. Install Element X from App Store / Google Play
2. Tap "Sign in"
3. Set homeserver to `chat.yourdomain.com`
4. Log in with your credentials

### Element Desktop

1. Download from https://element.io/download
2. Click "Sign in" → "Edit" homeserver
3. Set homeserver to `chat.yourdomain.com`
4. Log in

### Other Matrix clients

Any Matrix client works (FluffyChat, SchildiChat, Cinny, etc.). Set the homeserver to `chat.yourdomain.com`.

## Updating

```bash
docker compose pull
docker compose up -d
```

This pulls the latest images and recreates containers. Data is preserved in Docker volumes.

## Backups

```bash
# Create a backup
./scripts/backup.sh

# Backup to a specific directory
./scripts/backup.sh /path/to/backup/dir
```

Backups include the Continuwuity database, Caddy TLS certificates, and config files.

### Restore

```bash
# 1. Stop services
docker compose down

# 2. Restore Continuwuity data
docker run --rm -v e2echat_continuwuity_data:/target -v ./backups:/backup \
  alpine sh -c "cd /target && tar xzf /backup/e2echat_TIMESTAMP_continuwuity.tar.gz"

# 3. Restore Caddy certificates
docker run --rm -v e2echat_caddy_data:/target -v ./backups:/backup \
  alpine sh -c "cd /target && tar xzf /backup/e2echat_TIMESTAMP_caddy.tar.gz"

# 4. Restore config
tar xzf backups/e2echat_TIMESTAMP_config.tar.gz

# 5. Start services
docker compose up -d
```

## Troubleshooting

### Caddy fails to get certificates

- Ensure ports 80 and 443 are open and reachable from the internet
- Check DNS records point to the correct IP: `dig chat.yourdomain.com`
- View Caddy logs: `docker compose logs caddy`

### Federation not working

- Test at https://federationtester.matrix.org
- Ensure port 8448 is open
- Check `.well-known` response: `curl https://chat.yourdomain.com/.well-known/matrix/server`

### Element Call says "Waiting for media" or calls fail

- Ensure UDP ports 50100-50400 and 3478 are open
- Check LiveKit logs: `docker compose logs livekit`
- Verify JWT service health: `curl https://call.yourdomain.com/healthz`
- Check the well-known includes RTC foci: `curl https://chat.yourdomain.com/.well-known/matrix/client`

### "Unable to decrypt" messages

- Verify cross-signing is set up in Element settings
- Export and import encryption keys between devices
- Dehydrated device support (MSC3814) helps prevent this for offline scenarios

### Continuwuity won't start

- Check logs: `docker compose logs continuwuity`
- Verify config: `cat data/continuwuity.toml`
- Ensure the data volume has correct permissions

### Port conflicts

If ports 80/443 are already in use, check for existing web servers:

```bash
sudo ss -tlnp | grep -E ':80|:443'
```

## Capacity

Each voice/video call participant uses 2 UDP ports. With the default port ranges:
- **50 concurrent call participants** (media)
- **50 concurrent TURN-relayed participants** (for clients behind strict firewalls)

To increase capacity, expand the port ranges in `livekit.yaml` and your firewall rules.

## File Reference

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service orchestration |
| `continuwuity.toml` | Homeserver config template |
| `livekit.yaml` | LiveKit SFU config template |
| `Caddyfile` | Reverse proxy config template |
| `element-web-config.json` | Element Web config template |
| `.env.example` | Environment variable template |
| `scripts/setup.sh` | First-time setup + secret generation |
| `scripts/create-user.sh` | Create Matrix user accounts |
| `scripts/backup.sh` | Backup database + certs |
| `cloud-init.sh` | Oracle Cloud instance setup (firewall + Docker) |
| `data/` | Generated configs (gitignored) |
| `.env` | Your secrets (gitignored) |
