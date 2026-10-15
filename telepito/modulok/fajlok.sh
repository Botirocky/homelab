#!/usr/bin/env bash
# Modul: fájltárolás – Nextcloud + FileBrowser

cim "Fájltárolás – Nextcloud + FileBrowser"

NC_ADMIN_FELHASZNALO="${SMB_FELHASZNALO:-admin}"
env_beallit "NC_ADMIN_FELHASZNALO" "$NC_ADMIN_FELHASZNALO"
NC_ADMIN_JELSZO="$(titok NC_ADMIN_JELSZO 20)"
titok NC_DB_JELSZO 32 >/dev/null
titok NC_DB_ROOT_JELSZO 32 >/dev/null
env_frissit "NC_PUBLIKUS_DOMAIN" "${PUBLIKUS_DOMAIN:-}"
# Publikus domain nélkül a Nextcloud http-n szolgál ki; különben https-re
# generálja a linkeket (enélkül a kliensek rossz címre mennek).
if [[ -n "${PUBLIKUS_DOMAIN:-}" ]]; then
    env_frissit "NC_PROTOKOLL" "https"
else
    env_frissit "NC_PROTOKOLL" "http"
fi
# A gép saját IP-je is ismert név legyen (DNS nélküli eléréshez), és a
# Tailscale-címe is – különben távolról "untrusted domain" hibát dob.
SAJAT_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk "{print \$7; exit}" || true)"
NC_NEVEK="${SAJAT_IP:+${SAJAT_IP} ${SAJAT_IP}:8081}"
if van_parancs tailscale; then
    TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
    TS_NEV="$(tailscale status --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
    for n in $TS_IP $TS_NEV; do NC_NEVEK="${NC_NEVEK} ${n} ${n}:8081"; done
fi
env_frissit "NC_EXTRA_DOMAIN" "$NC_NEVEK"

# A felhasználói fájlok nőnek: mehetnek külön adathordozóra. Az adatbázis és a
# telepített Nextcloud SZÁNDÉKOSAN a rendszerlemezen marad (gyors, és egy
# kihúzott pendrive nem viszi magával az adatbázist).
NC_FAJL_DIR="${NC_FAJL_DIR:-${ADAT_DIR}/nextcloud/fajlok}"
env_frissit "NC_FAJL_DIR" "$NC_FAJL_DIR"
konyvtar "${ADAT_DIR}/nextcloud/db"
konyvtar "${ADAT_DIR}/nextcloud/app"
konyvtar "$NC_FAJL_DIR"
konyvtar "${ADAT_DIR}/filebrowser"
konyvtar "${ADAT_DIR}/megosztas"

stack_telepit fajlok

# A FileBrowser a szinkron stackből is jöhet. Ha már ott fut, itt NE indítsuk
# el újra: ütközne a konténernév és a fajlok.<domain> cím is (a Caddy két
# egyforma blokktól nem indul el). Ilyenkor profilba tesszük, így áll.
FB_MASHOL=0
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx park-filebrowser; then
    FB_PROJEKT="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' park-filebrowser 2>/dev/null || true)"
    [[ -n "$FB_PROJEKT" && "$FB_PROJEKT" != "fajlok" ]] && FB_MASHOL=1
fi

if (( FB_MASHOL )); then
    cat <<'FBKI' | fajlt_ir "${PARK_DIR}/stackek/fajlok/compose.override.yml"
# A FileBrowser máshol (szinkron stack) már fut, ezért itt nem indul el.
services:
  filebrowser:
    profiles: [kikapcsolt]
FBKI
    info "a FileBrowser a ${FB_PROJEKT} stackben fut – itt kihagyom"
else
    rm -f "${PARK_DIR}/stackek/fajlok/compose.override.yml" 2>/dev/null || true
fi

stack_indit fajlok

FELHO_VHOST="http://felho.${BELSO_DOMAIN} {
	reverse_proxy nextcloud:80
	# A Nextcloud-kliensek ezeket az átirányításokat várják:
	redir /.well-known/carddav /remote.php/dav 301
	redir /.well-known/caldav /remote.php/dav 301
}"
if (( FB_MASHOL == 0 )); then
    FELHO_VHOST="${FELHO_VHOST}

http://fajlok.${BELSO_DOMAIN} {
	reverse_proxy filebrowser:80
}"
fi
vhost_ir "20-felho" "$FELHO_VHOST"

# --- Nextcloud beüzemelése -----------------------------------------------
# Ezeket a Nextcloud admin felülete amúgy hiányolná: gyorsítótár, hiányzó
# adatbázis-indexek, és háttérfeladatok CRON módban (az alapértelmezett AJAX
# csak akkor fut, ha épp nézi valaki az oldalt – így a szinkron akadozik).
if [[ "$PROBA" == "1" ]]; then
    info "[próba] Nextcloud: indexek, gyorsítótár, cron-időzítő"
elif konteneret_var park-nextcloud 120; then
    NCOCC=(docker exec -u www-data park-nextcloud php occ)
    "${NCOCC[@]}" db:add-missing-indices      >/dev/null 2>&1 || true
    "${NCOCC[@]}" db:add-missing-columns      >/dev/null 2>&1 || true
    "${NCOCC[@]}" db:add-missing-primary-keys >/dev/null 2>&1 || true
    "${NCOCC[@]}" config:system:set default_phone_region --value="HU"            >/dev/null 2>&1 || true
    "${NCOCC[@]}" config:system:set maintenance_window_start --type=integer --value=1 >/dev/null 2>&1 || true
    "${NCOCC[@]}" config:system:set memcache.local       --value='\OC\Memcache\APCu'  >/dev/null 2>&1 || true
    "${NCOCC[@]}" config:system:set memcache.distributed --value='\OC\Memcache\Redis' >/dev/null 2>&1 || true
    "${NCOCC[@]}" config:system:set memcache.locking     --value='\OC\Memcache\Redis' >/dev/null 2>&1 || true
    "${NCOCC[@]}" config:system:set redis host --value="nextcloud-redis" >/dev/null 2>&1 || true
    "${NCOCC[@]}" config:system:set redis port --type=integer --value=6379 >/dev/null 2>&1 || true
    "${NCOCC[@]}" background:cron >/dev/null 2>&1 || true
    ok "Nextcloud beállítva (indexek, gyorsítótár, magyar régió)"
fi

cat <<'NCSVC' | fajlt_ir /etc/systemd/system/park-nextcloud-cron.service
[Unit]
Description=Nextcloud háttérfeladatok
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker exec -u www-data park-nextcloud php -f /var/www/html/cron.php
NCSVC
cat <<'NCTMR' | fajlt_ir /etc/systemd/system/park-nextcloud-cron.timer
[Unit]
Description=Nextcloud háttérfeladatok időzítése

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
NCTMR
if [[ "$PROBA" != "1" ]]; then
    systemctl daemon-reload
    systemctl enable --now park-nextcloud-cron.timer >/dev/null 2>&1 \
        && ok "háttérfeladatok 5 percenként futnak" || true
fi

szolgaltatas_jegyzes "Nextcloud" "http://felho.${BELSO_DOMAIN}" "belépés: ${NC_ADMIN_FELHASZNALO} (jelszó a .env-ben)"
(( FB_MASHOL == 0 )) && \
    szolgaltatas_jegyzes "FileBrowser" "http://fajlok.${BELSO_DOMAIN}" "első belépés: admin / admin – írd át!"

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
