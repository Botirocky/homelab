#!/usr/bin/env bash
set -euo pipefail

DEV="${DEV:-}"
MNT="${MNT:-/mnt/picloud-sd}"
SSID="${SSID:-SAJAT-WIFI}"
COUNTRY="${COUNTRY:-HU}"
WIFI_PSK="${WIFI_PSK:-}"
TS_AUTHKEY="${TS_AUTHKEY:-}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!  %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mHIBA: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "root jog kell: sudo bash $0"

if [ -z "$DEV" ]; then
  DEV=$(lsblk -rno NAME,FSTYPE,LABEL | awk '$2=="ext4" && $3=="rootfs"{print "/dev/"$1; exit}')
  [ -n "$DEV" ] || die "Nem találom a Pi rootfs partícióját. Add meg: DEV=/dev/sdX2 sudo -E bash $0"
fi
say "Rootfs partíció: $DEV"

if [ -z "$WIFI_PSK" ]; then
  SRC="/etc/NetworkManager/system-connections/${SSID}.nmconnection"
  [ -f "$SRC" ] || die "Nincs helyi profil ehhez: $SSID — add meg: WIFI_PSK='jelszo' sudo -E bash $0"
  WIFI_PSK=$(awk -F= '/^psk=/{sub(/^psk=/,""); print; exit}' "$SRC")
  [ -n "$WIFI_PSK" ] || die "A profil nem tárolja a jelszót — add meg: WIFI_PSK='jelszo' sudo -E bash $0"
  echo "WiFi jelszó kiolvasva a helyi profilból."
fi

say "Felcsatolás: $MNT"
mkdir -p "$MNT"
mountpoint -q "$MNT" || mount "$DEV" "$MNT"
trap 'sync; umount "$MNT" 2>/dev/null || true' EXIT
[ -f "$MNT/etc/os-release" ] || die "Ez nem a Pi rootfs partíciója."
. "$MNT/etc/os-release"
echo "Rendszer: $PRETTY_NAME"

TARGET_USER=$(awk -F: '$3==1000{print $1; exit}' "$MNT/etc/passwd")
TARGET_USER="${TARGET_USER:-picloud}"
echo "Felhasználó: $TARGET_USER"

say "WiFi beállítása: $SSID"
if [ -e "$MNT/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ] \
   || [ -e "$MNT/etc/systemd/system/dbus-org.freedesktop.NetworkManager.service" ]; then
  CONN="$MNT/etc/NetworkManager/system-connections/${SSID}.nmconnection"
  mkdir -p "$(dirname "$CONN")"
  [ -f "$CONN" ] && cp -a "$CONN" "${CONN}.bak.$(date +%F)"
  cat > "$CONN" <<EOF
[connection]
id=${SSID}
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
interface-name=wlan0
autoconnect=true
autoconnect-priority=10

[wifi]
mode=infrastructure
ssid=${SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=default
EOF
  chmod 600 "$CONN"; chown 0:0 "$CONN"
  echo "NetworkManager profil kiírva."
elif [ -d "$MNT/etc/wpa_supplicant" ]; then
  CONF="$MNT/etc/wpa_supplicant/wpa_supplicant.conf"
  [ -f "$CONF" ] && cp -a "$CONF" "${CONF}.bak.$(date +%F)"
  grep -q "^country=" "$CONF" 2>/dev/null || \
    printf 'country=%s\nctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\nupdate_config=1\n' "$COUNTRY" > "$CONF"
  if grep -q "ssid=\"${SSID}\"" "$CONF"; then
    echo "Ez az SSID már szerepel — nem írom be újra."
  else
    cat >> "$CONF" <<EOF

network={
    ssid="${SSID}"
    psk="${WIFI_PSK}"
    key_mgmt=WPA-PSK
    priority=10
}
EOF
  fi
  chmod 600 "$CONF"; chown 0:0 "$CONF"
  echo "wpa_supplicant config kiírva."
else
  die "Nem található sem NetworkManager, sem wpa_supplicant."
fi

printf 'options cfg80211 ieee80211_regdom=%s\n' "$COUNTRY" > "$MNT/etc/modprobe.d/cfg80211.conf"
rm -f "$MNT/var/lib/systemd/rfkill/"*wlan* 2>/dev/null || true
echo "Régió: $COUNTRY, rfkill-állapot törölve."

say "Pi-hole fájlok másolása -> /opt/pihole"
mkdir -p "$MNT/opt/pihole"
cp "$SRC_DIR/docker-compose.yml" "$MNT/opt/pihole/"
cp "$SRC_DIR/.env" "$MNT/opt/pihole/"
chmod 600 "$MNT/opt/pihole/.env"
chown -R 0:0 "$MNT/opt/pihole"

say "Bootstrap script telepítése"
install -m 755 -o 0 -g 0 "$SRC_DIR/bootstrap.sh" "$MNT/usr/local/sbin/picloud-bootstrap.sh"

{
  printf 'TARGET_USER=%s\n' "$TARGET_USER"
  printf 'TS_HOSTNAME=picloud\n'
  [ -n "$TS_AUTHKEY" ] && printf 'TS_AUTHKEY=%s\n' "$TS_AUTHKEY"
} > "$MNT/etc/picloud-bootstrap.env"
chmod 600 "$MNT/etc/picloud-bootstrap.env"
chown 0:0 "$MNT/etc/picloud-bootstrap.env"
[ -n "$TS_AUTHKEY" ] && echo "Tailscale auth key beállítva (teljesen automatikus bejelentkezés)." \
  || warn "Nincs Tailscale auth key — a bejelentkezési URL a /boot/firmware/PICLOUD-SETUP.txt-be kerül."

say "First-boot systemd service"
cat > "$MNT/etc/systemd/system/picloud-bootstrap.service" <<'EOF'
[Unit]
Description=picloud first-boot bootstrap
After=network-online.target
Wants=network-online.target
ConditionPathExists=/usr/local/sbin/picloud-bootstrap.sh

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/picloud-bootstrap.sh
RemainAfterExit=yes
TimeoutStartSec=3600
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
chown 0:0 "$MNT/etc/systemd/system/picloud-bootstrap.service"
mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/picloud-bootstrap.service \
  "$MNT/etc/systemd/system/multi-user.target.wants/picloud-bootstrap.service"
echo "Engedélyezve — az első indításkor lefut."

say "SSH ellenőrzése"
if [ -e "$MNT/etc/systemd/system/multi-user.target.wants/ssh.service" ]; then
  echo "SSH engedélyezve."
else
  ln -sf /lib/systemd/system/ssh.service \
    "$MNT/etc/systemd/system/multi-user.target.wants/ssh.service" && echo "SSH bekapcsolva."
fi

say "Kész"
cat <<EOF

Kiveheted a kártyát, teheted a Pi-be.

Indítás után 5-15 perccel (a frissítés hossza miatt):
  - a Pi felcsatlakozik a(z) $SSID hálózatra
  - frissíti magát, feltelepíti a Dockert, Pi-hole-t, Tailscale-t, RPi Connectet
  - az összefoglaló ide kerül: /boot/firmware/PICLOUD-SETUP.txt
    (ezt a kártyát a laptopba dugva is elolvashatod)

Követés élőben, ha már látod a hálózaton:
  ssh $TARGET_USER@<ip> 'sudo tail -f /var/log/picloud-bootstrap.log'
EOF
