#!/usr/bin/env bash
# Modul: automatikus mentés (restic)
# Naponta ment, deduplikálva és titkosítva. A régi mentéseket ritkítja.

cim "Automatikus mentés (restic)"

if ! van_parancs restic; then
    info "restic telepítése…"
    fut apt-get install -y -qq restic
fi

MENTES_CEL="${MENTES_CEL:-${PARK_DIR}/mentes/repo}"
RESTIC_JELSZO="$(titok RESTIC_JELSZO 40)"
env_frissit "MENTES_CEL" "$MENTES_CEL"
konyvtar "$(dirname "$MENTES_CEL")"

if [[ "$PROBA" == "1" ]]; then
    info "[próba] restic tároló létrehozása: $MENTES_CEL"
elif [[ -f "${MENTES_CEL}/config" ]]; then
    kihagy "restic tároló már létezik"
else
    RESTIC_PASSWORD="$RESTIC_JELSZO" restic init --repo "$MENTES_CEL" >/dev/null 2>&1 \
        && ok "restic tároló létrehozva: $MENTES_CEL" \
        || figy "a restic tárolót nem sikerült létrehozni"
fi

# --- mentő szkript -----------------------------------------------------------
cat <<'MENTO' | fajlt_ir /usr/local/bin/park-mentes
#!/usr/bin/env bash
# Napi mentés – a systemd időzítő indítja, de kézzel is futtatható: park mentes
set -euo pipefail

PARK_DIR="${PARK_DIR:-/srv/szerverpark}"
[ -r /etc/szerverpark.conf ] && . /etc/szerverpark.conf
set -a; source "${PARK_DIR}/.env"; set +a
export RESTIC_PASSWORD="$RESTIC_JELSZO"
export HOME="${HOME:-/root}"
CEL="${MENTES_CEL:-${PARK_DIR}/mentes/repo}"

hc() { [ -n "${HC_MENTES_URL:-}" ] && curl -fsS -m 10 --retry 3 -o /dev/null "${HC_MENTES_URL}$1" 2>/dev/null || true; }
hc /start
trap 'hc "/$?"' EXIT

echo "== Mentés indul: $(date '+%F %T')"

TAROLOK="${TAROLO_DIR:-/srv/tarolok}"
TAROLOK="${TAROLOK%/}"
HIANYZO=()
for UT in "$CEL" ${MENTES_EXTRA:-}; do
    case "$UT" in "$TAROLOK"/*) ;; *) continue ;; esac
    RESZ="${UT#"$TAROLOK"/}"
    GYOKER="${TAROLOK}/${RESZ%%/*}"
    mountpoint -q "$GYOKER" || HIANYZO+=("$UT  (a(z) $GYOKER nincs felcsatolva)")
done
if [ "${#HIANYZO[@]}" -gt 0 ]; then
    echo "!! A mentés KIMARAD – hiányzó tároló:"
    printf '   %s\n' "${HIANYZO[@]}"
    if command -v park-ertesito >/dev/null 2>&1; then
        park-ertesito "Mentés kimaradt: hiányzó tároló" "$(printf '%s\n' "${HIANYZO[@]}")" "hiba" >/dev/null 2>&1 || true
    fi
    exit 1
fi

# Ha egy korábbi futás félbeszakadt (áramszünet, leállítás), a restic ottfelejti
# a zárolását, és onnantól MINDEN ritkítás elhasal. Az 'unlock' csak az elárvult
# zárolásokat szedi le; a systemd amúgy sem indít két mentést egyszerre.
restic unlock --repo "$CEL" >/dev/null 2>&1 || true

# A társgép (Pi) mappáinak áthúzása, ha az összekötés beállította.
if [ -x /usr/local/bin/park-pi-mentes ]; then
    echo "== Társgép adatainak áthúzása"
    /usr/local/bin/park-pi-mentes || echo "  FIGYELEM: a társgép nem elérhető, kihagyva"
fi

# Az adatbázisok konzisztens mentése (a futó MariaDB fájljait nem elég másolni).
if docker ps --format '{{.Names}}' | grep -qx park-nextcloud-db; then
    mkdir -p "${PARK_DIR}/mentes/db"
    docker exec park-nextcloud-db sh -c \
        'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --single-transaction nextcloud' \
        > "${PARK_DIR}/mentes/db/nextcloud.sql" 2>/dev/null \
        && echo "  Nextcloud adatbázis kimentve" \
        || echo "  FIGYELEM: az adatbázis-mentés nem sikerült"
fi

for PG in park-immich-db park-miniflux-db; do
    docker ps --format '{{.Names}}' | grep -qx "$PG" || continue
    mkdir -p "${PARK_DIR}/mentes/db"
    docker exec "$PG" sh -c 'pg_dumpall --clean --if-exists -U "$POSTGRES_USER"' \
        > "${PARK_DIR}/mentes/db/${PG#park-}.sql" 2>/dev/null \
        && echo "  ${PG#park-} adatbázis kimentve" \
        || echo "  FIGYELEM: a(z) ${PG#park-} adatbázis mentése nem sikerült"
done

MENTENDO=("${ADAT_DIR}" "${PARK_DIR}/stackek" "${PARK_DIR}/web" "${PARK_DIR}/.env")
[ -d "${PARK_DIR}/mentes/db" ] && MENTENDO+=("${PARK_DIR}/mentes/db")
[ -f /etc/szerverpark.conf ] && MENTENDO+=(/etc/szerverpark.conf)
[ -f /etc/samba/szerverpark.conf ] && MENTENDO+=(/etc/samba/szerverpark.conf)
[ -f /etc/fstab ] && MENTENDO+=(/etc/fstab)

for UT in ${MENTES_EXTRA:-}; do
    if [ -e "$UT" ]; then
        MENTENDO+=("$UT")
    else
        echo "  FIGYELEM: a mentendő útvonal nem létezik: $UT"
    fi
done

echo "== Mentendő útvonalak: ${MENTENDO[*]}"

restic backup \
    --repo "$CEL" \
    --tag automata \
    --exclude "${ADAT_DIR}/ai/ollama" \
    --exclude "${AI_MODELL_DIR:-/nincs-ilyen-utvonal}" \
    --exclude "**/node_modules" \
    --exclude "**/.cache" \
    --exclude "**/*.sock" \
    --exclude "${KIWIX_DIR:-${ADAT_DIR}/kiwix}" \
    --exclude "${FOTO_DIR:-${ADAT_DIR}/immich/fotok}/thumbs" \
    --exclude "${FOTO_DIR:-${ADAT_DIR}/immich/fotok}/encoded-video" \
    --exclude "${ADAT_DIR}/immich/ml-cache" \
    --exclude "${CEL}" \
    "${MENTENDO[@]}"

echo "== Régi mentések ritkítása"
restic forget --repo "$CEL" --prune \
    --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 2

if [ -n "${MENTES_TAVOLI:-}" ]; then
    /usr/local/bin/park-mentes-masolat || true
fi

echo "== Kész: $(date '+%F %T')"
restic snapshots --repo "$CEL" --latest 3
MENTO
fut chmod +x /usr/local/bin/park-mentes

cat <<'MASOLAT' | fajlt_ir /usr/local/bin/park-mentes-masolat
#!/usr/bin/env bash
set -uo pipefail

PARK_DIR="${PARK_DIR:-/srv/szerverpark}"
[ -r /etc/szerverpark.conf ] && . /etc/szerverpark.conf
set -a; source "${PARK_DIR}/.env"; set +a
export RESTIC_PASSWORD="$RESTIC_JELSZO" RESTIC_FROM_PASSWORD="$RESTIC_JELSZO"
export HOME="${HOME:-/root}"
CEL="${MENTES_CEL:-${PARK_DIR}/mentes/repo}"
JEL_DIR=/var/lib/park-mentes
JEL="${JEL_DIR}/masolat-fuggo"
POTLAS=0
[ "${1:-}" = "--potlas" ] && POTLAS=1

[ -n "${MENTES_TAVOLI:-}" ] || exit 0
if (( POTLAS )) && [ ! -f "$JEL" ]; then
    exit 0
fi
mkdir -p "$JEL_DIR"

ertesit() { command -v park-ertesito >/dev/null 2>&1 && park-ertesito "$@" >/dev/null 2>&1 || true; }

echo "== Másolat a társgépre: $MENTES_TAVOLI$( (( POTLAS )) && echo ' (pótlás)')"
if HIBA="$(restic -r "$MENTES_TAVOLI" copy --from-repo "$CEL" 2>&1 >/dev/null)"; then
    restic -r "$MENTES_TAVOLI" forget --prune \
        --keep-daily 7 --keep-weekly 5 --keep-monthly 12 >/dev/null 2>&1 || true
    echo "  Kész – a mentés két külön gépen van."
    if [ -f "$JEL" ]; then
        elso="$(sed -n 1p "$JEL")"
        rm -f "$JEL"
        ertesit "Mentés: a társgépre másolás pótolva" \
            "$(printf 'Cél: %s\nAz első sikertelen próba: %s' "$MENTES_TAVOLI" "$(date -d "@${elso:-0}" '+%F %H:%M' 2>/dev/null)")" "info"
    fi
    exit 0
fi

echo "  FIGYELEM: a társgépre másolás nem sikerült (a társgép elérhető?)"
[ -n "$HIBA" ] && printf '%s\n' "$HIBA" | tail -3 | sed 's/^/  /'
most=$(date +%s)
if [ -f "$JEL" ]; then
    elso="$(sed -n 1p "$JEL")"; utolso="$(sed -n 2p "$JEL")"
else
    elso="$most"; utolso=0
fi
if (( most - ${utolso:-0} >= 86400 )); then
    ertesit "Mentés: a társgépre másolás nem sikerült" \
        "$(printf 'Cél: %s\n%s\nÓránként újrapróbálom.' "$MENTES_TAVOLI" "$(printf '%s\n' "$HIBA" | tail -3)")" "hiba"
    utolso="$most"
fi
printf '%s\n%s\n' "$elso" "$utolso" > "$JEL"
exit 1
MASOLAT
fut chmod +x /usr/local/bin/park-mentes-masolat

# --- systemd időzítő ---------------------------------------------------------
cat <<'SVC' | fajlt_ir /etc/systemd/system/park-mentes.service
[Unit]
Description=Szerverpark – napi mentés (restic)
After=docker.service

[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/usr/local/bin/park-mentes
Nice=10
IOSchedulingClass=idle
SVC

cat <<'TMR' | fajlt_ir /etc/systemd/system/park-mentes.timer
[Unit]
Description=Szerverpark – napi mentés időzítése

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
TMR

cat <<'SVC' | fajlt_ir /etc/systemd/system/park-mentes-masolat.service
[Unit]
Description=Szerverpark – elmaradt társgép-másolás pótlása
After=network-online.target docker.service
Wants=network-online.target
ConditionPathExists=/var/lib/park-mentes/masolat-fuggo

[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/usr/local/bin/park-mentes-masolat --potlas
SuccessExitStatus=1
Nice=10
IOSchedulingClass=idle
SVC

cat <<'TMR' | fajlt_ir /etc/systemd/system/park-mentes-masolat.timer
[Unit]
Description=Szerverpark – társgép-másolás újrapróbálása óránként

[Timer]
OnBootSec=10min
OnUnitActiveSec=1h
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
TMR

fut systemctl daemon-reload
fut systemctl enable --now park-mentes.timer >/dev/null 2>&1 || true
fut systemctl enable --now park-mentes-masolat.timer >/dev/null 2>&1 || true
ok "napi mentés beállítva (hajnali 3:30)"

figy "A mentés most ugyanazon a gépen van! Tegyél mellé külső célt is:"
figy "  külső USB lemez, NAS, vagy távoli tároló (restic rclone/sftp)."
szolgaltatas_jegyzes "Mentés" "$MENTES_CEL" "naponta 3:30, 7 napi + 5 heti + 12 havi"

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
