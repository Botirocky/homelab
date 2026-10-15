#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-picloud}"
REMOTE_DIR="/opt/pihole"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mHIBA: %s\033[0m\n' "$*" >&2; exit 1; }

say "Kapcsolódás: $HOST"
ssh -o ConnectTimeout=10 "$HOST" true || die "$HOST nem érhető el SSH-n."

say "Rendszer ellenőrzése"
ssh "$HOST" 'bash -s' <<'REMOTE'
set -e
. /etc/os-release
echo "OS:     $PRETTY_NAME ($(uname -m))"
echo "IP:     $(hostname -I | awk '{print $1}')"
echo "Docker: $(docker --version 2>/dev/null || echo 'NINCS')"
echo "53-as port:"
ss -tulpn 2>/dev/null | grep -E ':53\s' || echo "  szabad"
REMOTE

say "Docker telepítése, ha hiányzik"
ssh "$HOST" 'bash -s' <<'REMOTE'
set -e
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
  sudo usermod -aG docker "$USER"
  rm -f /tmp/get-docker.sh
fi
docker compose version >/dev/null || sudo apt-get install -y docker-compose-plugin
REMOTE

say "53-as port felszabadítása (systemd-resolved stub listener)"
ssh "$HOST" 'bash -s' <<'REMOTE'
set -e
if ss -tulpn 2>/dev/null | grep -qE ':53\s.*systemd-resolve'; then
  sudo cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%F)
  sudo mkdir -p /etc/systemd/resolved.conf.d
  printf '[Resolve]\nDNSStubListener=no\n' | sudo tee /etc/systemd/resolved.conf.d/99-pihole.conf >/dev/null
  sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  sudo systemctl restart systemd-resolved
  echo "systemd-resolved stub listener kikapcsolva (backup: /etc/resolv.conf.bak.*)"
elif ss -tulpn 2>/dev/null | grep -qE ':53\s'; then
  echo "FIGYELEM: az 53-as portot más foglalja:"
  ss -tulpn | grep -E ':53\s'
  exit 1
else
  echo "53-as port szabad"
fi
REMOTE

say "Fájlok másolása -> $HOST:$REMOTE_DIR"
ssh "$HOST" "sudo mkdir -p $REMOTE_DIR && sudo chown \$USER:\$USER $REMOTE_DIR"
scp "$LOCAL_DIR/docker-compose.yml" "$LOCAL_DIR/.env" "$HOST:$REMOTE_DIR/"
ssh "$HOST" "chmod 600 $REMOTE_DIR/.env"

say "Pi-hole indítása"
ssh "$HOST" "bash -s" <<REMOTE
set -e
cd $REMOTE_DIR
DC="docker compose"
docker info >/dev/null 2>&1 || DC="sudo docker compose"
\$DC up -d
sleep 15
\$DC ps
REMOTE

say "Teszt"
ssh "$HOST" 'bash -s' <<'REMOTE'
set -e
IP=$(hostname -I | awk '{print $1}')
D="docker"
docker info >/dev/null 2>&1 || D="sudo docker"
echo "--- feloldás teszt ---"
$D exec pihole dig +short google.com @127.0.0.1 | head -3
echo "--- blokkolás teszt (0.0.0.0 = jó) ---"
$D exec pihole dig +short doubleclick.net @127.0.0.1 | head -3
echo
echo "Webfelület:  http://$IP:8080/admin"
echo "DNS szerver: $IP"
REMOTE

say "Kész"
printf 'Jelszó: %s\n' "$(grep PIHOLE_PASSWORD "$LOCAL_DIR/.env" | cut -d= -f2)"
