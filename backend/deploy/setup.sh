#!/usr/bin/env bash
# Sets up or updates the game server on one Linux machine (Ubuntu 22.04 / 24.04), for example
# a DigitalOcean droplet. Safe to run again: it installs what is missing and restarts what
# changed. deploy-server.bat on the Windows PC uploads the backend here and runs this.
#
#   bash /opt/rummy/deploy/setup.sh <host name>
#
# <host name> is the public name the apps connect to (rummy.example.com); its DNS record must
# point at this machine before the HTTPS certificate can be issued. What runs afterwards:
#   docker compose   the game server, PostgreSQL and Redis (backend/docker-compose.yml)
#   caddy            HTTPS on 443 with a free certificate, forwarding to the game server
#   a daily backup   of the database into /opt/rummy/backups, kept for 14 days
set -euo pipefail

HOST_NAME="${1:-}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$HOST_NAME" ]; then
  echo "Use: bash $0 <host name>   (the public name of this server, e.g. rummy.example.com)"
  exit 1
fi
if [ ! -f "$APP_DIR/.env" ]; then
  echo "There is no $APP_DIR/.env yet. Copy .env.example to .env and fill it in (deploy-server.bat does this)."
  exit 1
fi
cd "$APP_DIR"

step() { printf '\n==> %s\n' "$*"; }

step "Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
docker --version

step "Caddy (HTTPS)"
if ! command -v caddy >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
fi
cat > /etc/caddy/Caddyfile <<EOF
# Written by deploy/setup.sh. The game server listens on 3001 on this machine only;
# Caddy answers https://$HOST_NAME, gets the certificate by itself, and passes
# everything (including the WebSocket of the game) through.
$HOST_NAME {
    encode gzip
    reverse_proxy 127.0.0.1:3001
}
EOF
systemctl enable --now caddy >/dev/null
systemctl reload caddy

step "Firewall"
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null
  ufw status | head -n 6
else
  echo "ufw is not installed; make sure only ports 22, 80 and 443 are open (the DigitalOcean firewall does this too)."
fi

step "The game server, PostgreSQL and Redis"
docker compose --env-file .env up -d --build --remove-orphans
printf 'waiting for the server'
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:3001/health >/dev/null 2>&1; then
    echo " up"
    break
  fi
  printf '.'
  sleep 2
done
if ! curl -fsS http://127.0.0.1:3001/health >/dev/null 2>&1; then
  echo
  echo "The server did not come up. Its last lines:"
  docker compose logs --tail=40 server
  exit 1
fi

step "Daily database backup"
mkdir -p "$APP_DIR/backups"
cat > /etc/cron.daily/rummy-backup <<EOF
#!/bin/sh
# Written by deploy/setup.sh: one dump a day, the last 14 kept.
cd "$APP_DIR" || exit 1
docker compose exec -T db pg_dump -U rummy rummy | gzip > "backups/rummy-\$(date +%F).sql.gz"
find backups -name 'rummy-*.sql.gz' -mtime +14 -delete
EOF
chmod +x /etc/cron.daily/rummy-backup
echo "a dump is written to $APP_DIR/backups every day"

step "Done"
echo "Game server:  https://$HOST_NAME"
echo "Check:        https://$HOST_NAME/health   and   /privacy   /terms   /delete-account"
echo "Logs:         cd $APP_DIR && docker compose logs -f server"
echo "Update:       run deploy-server.bat again from the PC"
echo "Restore:      gunzip -c backups/rummy-<date>.sql.gz | docker compose exec -T db psql -U rummy rummy"
