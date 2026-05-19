#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on the Oracle Ubuntu VM." >&2
  exit 1
fi

apt-get update
apt-get install -y coturn curl ca-certificates gnupg ufw

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

if ! command -v caddy >/dev/null 2>&1; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key |
    gpg --dearmor -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt |
    tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update
  apt-get install -y caddy
fi

id -u rain-turn >/dev/null 2>&1 || useradd --system --home /opt/rain-turn-broker --shell /usr/sbin/nologin rain-turn
install -d -o rain-turn -g rain-turn /opt/rain-turn-broker
install -d /var/log/turnserver
chown turnserver:turnserver /var/log/turnserver

echo "Copy backend/turn/src, package.json, package-lock.json, and env files to /opt/rain-turn-broker next."
echo "Then copy coturn/turnserver.conf.template to /etc/turnserver.conf and replace placeholders."
