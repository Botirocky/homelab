# picloud — Pi-hole + Tailscale + RPi Connect

Teljesen automata beállítás a Raspberry Pi szerverhez. Az SD-kártyát a laptopon
előkészíted, a Pi-t bekapcsolod, és minden magától felépül.

## 1. SD-kártya előkészítése (a laptopon)

Dugd be az SD-kártyát, majd:

```bash
sudo bash prepare-sd.sh
```

Ez beírja a WiFi-profilt (a jelszót a saját NetworkManager-profilodból veszi),
felmásolja a bootstrap scriptet és a Pi-hole fájlokat, és bekapcsolja a
first-boot service-t.

Opciók:

```bash
SSID="MasikHalozat" sudo -E bash prepare-sd.sh
WIFI_PSK="jelszo" sudo -E bash prepare-sd.sh          # ha a profil nem tárolja
TS_AUTHKEY="tskey-auth-..." sudo -E bash prepare-sd.sh # automata Tailscale-belépés
DEV=/dev/sdb2 sudo -E bash prepare-sd.sh               # ha nem találja a partíciót
```

Tailscale auth key: https://login.tailscale.com/admin/settings/keys

## 2. Kártya a Pi-be, bekapcsolás

Az első indításkor a `picloud-bootstrap.service` lefut és elvégzi:

1. Megvárja a hálózatot (2 percig, közben újrapróbálja a WiFi-t)
2. `apt full-upgrade` — teljes rendszerfrissítés
3. Docker + compose plugin telepítése
4. 53-as port felszabadítása, Pi-hole indítása, feloldás/blokkolás teszt
5. Tailscale telepítés + bejelentkezés
6. RPi Connect (rpi-connect-lite) telepítés + bejelentkezés
7. Összefoglaló: `/boot/firmware/PICLOUD-SETUP.txt`

Ez 5-15 percig tart a frissítés méretétől függően.

## 3. Eredmény megnézése

Ha látod a Pi-t a hálózaton:

```bash
ssh picloud@<ip> 'sudo tail -f /var/log/picloud-bootstrap.log'
ssh picloud@<ip> 'cat /boot/firmware/PICLOUD-SETUP.txt'
```

Ha nem jön fel: kapcsold ki, tedd a kártyát a laptopba, és olvasd el a
`PICLOUD-SETUP.txt`-t a boot partícióról — abban benne van, melyik lépés bukott el.

Egy lépés hibája nem állítja meg a többit, és a script újrafuttatható:

```bash
ssh picloud@<ip> 'sudo /usr/local/sbin/picloud-bootstrap.sh'
```

## Elérés

- Pi-hole admin: `http://<pi-ip>:8080/admin` (a 8080 azért kell, mert a csevegő a 8000-en fut)
- Jelszó: `.env` fájlban
- DNS: a Pi IP-je, 53-as port
- Tailscale / RPi Connect bejelentkezési URL: a `PICLOUD-SETUP.txt`-ben

## Hálózat ráállítása a Pi-hole-ra

Router admin → DHCP → DNS szerver: a Pi IP-je.
Előbb adj a Pi-nek fix IP-t (DHCP-foglalás a routerben), különben egy IP-váltásnál
az egész háló DNS nélkül marad. Tesztnek állítsd be előbb csak egy gépen kézzel.

## Üzemeltetés

```bash
ssh picloud 'cd /opt/pihole && docker compose logs -f'     # logok
ssh picloud 'docker exec pihole pihole -g'                 # blokklisták frissítése
ssh picloud 'docker exec pihole pihole -q example.com'     # domain ellenőrzése
ssh picloud 'docker exec pihole pihole allow example.com'  # engedélyezés
```

Pi-hole frissítése: tag átírása a `docker-compose.yml`-ben, majd
`ssh picloud 'cd /opt/pihole && docker compose pull && docker compose up -d'`

## Fájlok

| fájl | mi ez |
|---|---|
| `prepare-sd.sh` | SD-kártya előkészítése a laptopon (root jog kell) |
| `bootstrap.sh` | a Pi-n futó telepítő (a kártyára kerül) |
| `docker-compose.yml` | Pi-hole v6, pinnelt tag |
| `.env` | Pi-hole admin jelszó |
| `deploy.sh` | Pi-hole telepítése egy **már futó**, SSH-n elérhető Pi-re |

## Visszaállítás

```bash
ssh picloud 'cd /opt/pihole && docker compose down'
ssh picloud 'sudo rm -f /etc/systemd/resolved.conf.d/99-pihole.conf && sudo systemctl restart systemd-resolved'
```
És a routerben állítsd vissza az eredeti DNS-t.
