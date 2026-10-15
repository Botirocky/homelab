#!/usr/bin/env bash
set -uo pipefail

LOG=/var/log/picloud-bootstrap.log
ENV_FILE=/etc/picloud-bootstrap.env
PIHOLE_DIR=/opt/pihole
FAILED=()

[ -f "$ENV_FILE" ] && . "$ENV_FILE"
TS_AUTHKEY="${TS_AUTHKEY:-}"
TS_HOSTNAME="${TS_HOSTNAME:-picloud}"
TARGET_USER="${TARGET_USER:-$(getent passwd 1000 | cut -d: -f1)}"
TARGET_USER="${TARGET_USER:-picloud}"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

step() {
  local name="$1"; shift
  log "=== $name ==="
  if "$@" >>"$LOG" 2>&1; then
    log "OK: $name"
    return 0
  else
    log "HIBA: $name (folytatom)"
    FAILED+=("$name")
    return 1
  fi
}

boot_dir() {
  [ -d /boot/firmware ] && echo /boot/firmware || echo /boot
}

wait_for_network() {
  local i
  for i in $(seq 1 60); do
    if getent hosts deb.debian.org >/dev/null 2>&1 || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
      log "Hálózat elérhető ($(hostname -I | awk '{print $1}'))"
      return 0
    fi
    if [ "$i" -eq 20 ] && command -v nmcli >/dev/null; then
      log "Nincs net 40mp után — WiFi kapcsolat újraindítása"
      nmcli radio wifi on >/dev/null 2>&1
      nmcli connection up "$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1; exit}')" >/dev/null 2>&1
    fi
    sleep 2
  done
  log "Nincs hálózat 2 perc után — a telepítés nem folytatható"
  return 1
}

system_update() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade
  apt-get -y autoremove --purge
  apt-get -y install curl ca-certificates
}

install_docker() {
  if command -v docker >/dev/null; then
    log "Docker már telepítve: $(docker --version)"
  else
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi
  usermod -aG docker "$TARGET_USER"
  docker compose version >/dev/null 2>&1 || apt-get -y install docker-compose-plugin
  systemctl enable --now docker
}

free_port_53() {
  if ss -tulpn 2>/dev/null | grep -qE ':53\s.*systemd-resolve'; then
    cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F)" 2>/dev/null
    mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/99-pihole.conf
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    systemctl restart systemd-resolved
    log "systemd-resolved stub listener kikapcsolva"
  elif ss -tulpn 2>/dev/null | grep -qE ':53\s'; then
    log "Az 53-as portot más foglalja:"
    ss -tulpn | grep -E ':53\s' | tee -a "$LOG"
    return 1
  else
    log "53-as port szabad"
  fi
}

start_pihole() {
  [ -f "$PIHOLE_DIR/docker-compose.yml" ] || { log "Nincs $PIHOLE_DIR/docker-compose.yml"; return 1; }
  cd "$PIHOLE_DIR"
  docker compose up -d
  sleep 20
  docker compose ps
  docker exec pihole dig +short google.com @127.0.0.1 | head -2
  docker exec pihole dig +short doubleclick.net @127.0.0.1 | head -2
}

install_tailscale() {
  if ! command -v tailscale >/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  systemctl enable --now tailscaled
  if tailscale status >/dev/null 2>&1 && ! tailscale status 2>&1 | grep -q "Logged out"; then
    log "Tailscale már be van jelentkezve"
    return 0
  fi
  if [ -n "$TS_AUTHKEY" ]; then
    tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" --ssh
  else
    timeout 60 tailscale up --hostname="$TS_HOSTNAME" --ssh 2>&1 | tee -a "$LOG"
    tailscale status 2>&1 | grep -iE "log in at|https://login" | tee /run/ts-login.txt
  fi
}

install_rpi_connect() {
  apt-get -y install rpi-connect-lite || apt-get -y install rpi-connect || return 1
  loginctl enable-linger "$TARGET_USER"
  sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    systemctl --user enable --now rpi-connect
  sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    timeout 60 rpi-connect signin 2>&1 | tee /run/rpi-connect-signin.txt
}

write_summary() {
  local out="$(boot_dir)/PICLOUD-SETUP.txt"
  local ip pw
  ip=$(hostname -I | awk '{print $1}')
  pw=$(awk -F= '/^PIHOLE_PASSWORD=/{print $2}' "$PIHOLE_DIR/.env" 2>/dev/null)
  {
    echo "picloud bootstrap — $(date '+%F %T')"
    echo
    echo "IP cím:         $ip"
    echo "Pi-hole admin:  http://$ip:8080/admin"
    echo "Pi-hole jelszó: ${pw:-lásd /opt/pihole/.env}"
    echo "SSH:            ssh ${TARGET_USER}@${ip}"
    echo
    echo "Tailscale:"
    tailscale status 2>&1 | head -5 || echo "  (nem fut)"
    [ -s /run/ts-login.txt ] && cat /run/ts-login.txt
    echo
    echo "RPi Connect:"
    [ -s /run/rpi-connect-signin.txt ] && cat /run/rpi-connect-signin.txt || echo "  (nincs signin adat)"
    echo
    if [ -e /var/run/reboot-required ]; then
      echo "FIGYELEM: újraindítás szükséges (kernelfrissítés)."
      echo
    fi
    if [ ${#FAILED[@]} -gt 0 ]; then
      echo "SIKERTELEN LÉPÉSEK:"
      printf '  - %s\n' "${FAILED[@]}"
      echo "Részletek: /var/log/picloud-bootstrap.log"
    else
      echo "Minden lépés sikeres."
    fi
  } > "$out"
  chmod 644 "$out"
  cat "$out"
}

main() {
  [ "$(id -u)" -eq 0 ] || { echo "root jog kell"; exit 1; }
  log "########## picloud bootstrap indul (user: $TARGET_USER) ##########"

  if ! wait_for_network; then
    FAILED+=("hálózat")
    write_summary
    exit 1
  fi

  step "Rendszerfrissítés"     system_update
  step "Docker telepítése"     install_docker
  step "53-as port"            free_port_53 && step "Pi-hole indítása" start_pihole
  step "Tailscale"             install_tailscale
  step "RPi Connect"           install_rpi_connect

  log "########## kész ##########"
  write_summary

  systemctl disable picloud-bootstrap.service 2>/dev/null
  log "A first-boot service letiltva. Újrafuttatás: sudo /usr/local/sbin/picloud-bootstrap.sh"
}

main "$@"
