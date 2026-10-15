#!/usr/bin/env bash
# Közös segédfüggvények a telepítő moduljaihoz.
# Ezt a fájlt a telepito.sh olvassa be, önmagában nem futtatandó.

# --- színek (csak ha terminálra írunk) --------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'; C_ZOLD=$'\e[32m'; C_SARGA=$'\e[33m'; C_PIROS=$'\e[31m'
    C_KEK=$'\e[36m'; C_SZURKE=$'\e[90m'; C_FEHER=$'\e[1;37m'
else
    C_RESET=""; C_ZOLD=""; C_SARGA=""; C_PIROS=""; C_KEK=""; C_SZURKE=""; C_FEHER=""
fi

NAPLO_FAJL="${NAPLO_FAJL:-/var/log/szerverpark-telepito.log}"

_naplo() {
    [[ -w "$(dirname "$NAPLO_FAJL")" ]] 2>/dev/null || return 0
    printf '%s  %s\n' "$(date '+%F %T')" "$*" >>"$NAPLO_FAJL" 2>/dev/null || true
}

cim()    { printf '\n%s╭─ %s %s\n'  "$C_KEK" "$*" "$C_RESET"; _naplo "== $* =="; }
info()   { printf '%s│%s  %s\n'      "$C_KEK" "$C_RESET" "$*"; _naplo "$*"; }
ok()     { printf '%s│%s  %s✔%s %s\n' "$C_KEK" "$C_RESET" "$C_ZOLD" "$C_RESET" "$*"; _naplo "OK: $*"; }
kihagy() { printf '%s│%s  %s•%s %s %s(már kész)%s\n' "$C_KEK" "$C_RESET" "$C_SZURKE" "$C_RESET" "$*" "$C_SZURKE" "$C_RESET"; _naplo "KIHAGY: $*"; }
figy()   { printf '%s│%s  %s!%s %s\n' "$C_KEK" "$C_RESET" "$C_SARGA" "$C_RESET" "$*"; _naplo "FIGY: $*"; }
hiba()   { printf '%s│%s  %s✘ %s%s\n' "$C_KEK" "$C_RESET" "$C_PIROS" "$*" "$C_RESET" >&2; _naplo "HIBA: $*"; }

vege_hibaval() { hiba "$*"; exit 1; }

# --- alap ellenőrzések -------------------------------------------------------
van_parancs() { command -v "$1" >/dev/null 2>&1; }

root_kell() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || vege_hibaval \
        "Ezt a telepítőt rootként kell futtatni:  sudo ./telepito.sh"
}

# --- futtatás (próba módot tisztelve) ---------------------------------------
# Minden rendszert MÓDOSÍTÓ parancs ezen keresztül fusson, így a --proba
# kapcsolóval végig lehet nézni, mi történne, anélkül hogy bármi megváltozna.
fut() {
    if [[ "${PROBA:-0}" == "1" ]]; then
        printf '%s│%s  %s[próba]%s %s\n' "$C_KEK" "$C_RESET" "$C_SZURKE" "$C_RESET" "$*"
        return 0
    fi
    _naplo "FUT: $*"
    "$@"
}

# Fájl írása adott útvonalra (próba módban csak jelzi).
fajlt_ir() {
    local cel="$1"; shift
    if [[ "${PROBA:-0}" == "1" ]]; then
        printf '%s│%s  %s[próba]%s fájl írása: %s\n' "$C_KEK" "$C_RESET" "$C_SZURKE" "$C_RESET" "$cel"
        cat >/dev/null
        return 0
    fi
    mkdir -p "$(dirname "$cel")"
    cat >"$cel"
    _naplo "ÍR: $cel"
}

konyvtar() {
    local d="$1" jog="${2:-0755}"
    if [[ -d "$d" ]]; then return 0; fi
    fut mkdir -p "$d"
    fut chmod "$jog" "$d"
}

# --- kérdezés ----------------------------------------------------------------
# kerdez "Kérdés szövege" "alapértelmezés" -> a választ a stdout-ra adja
kerdez() {
    local kerdes="$1" alap="${2:-}" valasz=""
    if [[ "${AUTO:-0}" == "1" ]]; then printf '%s' "$alap"; return 0; fi
    if [[ -n "$alap" ]]; then
        read -r -p "$(printf '%s? %s%s %s[%s]%s: ' "$C_ZOLD" "$C_RESET" "$kerdes" "$C_SZURKE" "$alap" "$C_RESET")" valasz </dev/tty
    else
        read -r -p "$(printf '%s? %s%s: ' "$C_ZOLD" "$C_RESET" "$kerdes")" valasz </dev/tty
    fi
    printf '%s' "${valasz:-$alap}"
}

# igen_nem "Kérdés" "i"|"n"  -> 0 = igen, 1 = nem
igen_nem() {
    local kerdes="$1" alap="${2:-i}" valasz=""
    if [[ "${AUTO:-0}" == "1" ]]; then [[ "$alap" == "i" ]]; return; fi
    local jelzes="[I/n]"; [[ "$alap" == "n" ]] && jelzes="[i/N]"
    read -r -p "$(printf '%s? %s%s %s%s%s ' "$C_ZOLD" "$C_RESET" "$kerdes" "$C_SZURKE" "$jelzes" "$C_RESET")" valasz </dev/tty
    valasz="${valasz:-$alap}"
    [[ "${valasz,,}" =~ ^(i|igen|y|yes)$ ]]
}

# --- jelszavak / .env --------------------------------------------------------
jelszo_general() {
    # Nem csővezetékkel, mert a 'head' lezárása SIGPIPE-ot okozna (set -o pipefail).
    local hossz="${1:-28}" nyers=""
    nyers="$(LC_ALL=C tr -dc 'A-Za-z0-9' <<<"$(head -c $((hossz * 12)) /dev/urandom | base64 | tr -d '\n')")"
    printf '%s' "${nyers:0:hossz}"
}

# env_beallit KULCS ERTEK  – a központi .env-be ír, meglévő értéket megtart.
# A .env-et a docker compose ÉS a bash is olvassa (a park-* szkriptek
# source-olják). Szóközt tartalmazó értéket ezért idézőjelbe kell tenni,
# különben a source a második szót parancsnak hiszi. A compose leszedi az
# idézőjelet, tehát mindkét oldalnak jó.
env_idezojel() {
    local ertek="$1"
    if [[ "$ertek" == *[[:space:]\'\"\\\$\`]* ]]; then
        ertek="${ertek//\\/\\\\}"; ertek="${ertek//\"/\\\"}"
        printf '"%s"' "$ertek"
    else
        printf '%s' "$ertek"
    fi
}

env_beallit() {
    local kulcs="$1" ertek="$2" fajl="${PARK_DIR}/.env"
    if [[ "${PROBA:-0}" == "1" ]]; then return 0; fi
    mkdir -p "$(dirname "$fajl")"; touch "$fajl"; chmod 600 "$fajl"
    if grep -q "^${kulcs}=" "$fajl" 2>/dev/null; then
        return 0                                   # meglévőt nem írunk felül
    fi
    printf '%s=%s\n' "$kulcs" "$(env_idezojel "$ertek")" >>"$fajl"
}

# env_frissit KULCS ERTEK – beállításokhoz: a meglévő értéket FELÜLÍRJA, hogy a
# .env ne csússzon el a /etc/szerverpark.conf-tól. Titkokhoz env_beallit kell.
env_frissit() {
    local kulcs="$1" ertek="$2" fajl="${PARK_DIR}/.env"
    if [[ "${PROBA:-0}" == "1" ]]; then return 0; fi
    mkdir -p "$(dirname "$fajl")"; touch "$fajl"; chmod 600 "$fajl"
    local kesz; kesz="$(env_idezojel "$ertek")"
    if grep -q "^${kulcs}=" "$fajl" 2>/dev/null; then
        local biztos="${kesz//\\/\\\\}"; biztos="${biztos//&/\\&}"; biztos="${biztos//|/\\|}"
        sed -i "s|^${kulcs}=.*|${kulcs}=${biztos}|" "$fajl"
    else
        printf '%s=%s\n' "$kulcs" "$kesz" >>"$fajl"
    fi
}

env_ertek() {
    local kulcs="$1" fajl="${PARK_DIR}/.env"
    [[ -f "$fajl" ]] || return 1
    sed -n "s/^${kulcs}=//p" "$fajl" | head -1
}

# Titok: ha még nincs, generál egyet és eltárolja.
titok() {
    local kulcs="$1" hossz="${2:-28}"
    local meglevo; meglevo="$(env_ertek "$kulcs" 2>/dev/null || true)"
    if [[ -z "$meglevo" ]]; then
        meglevo="$(jelszo_general "$hossz")"
        env_beallit "$kulcs" "$meglevo"
    fi
    printf '%s' "$meglevo"
}

# --- docker stackek ----------------------------------------------------------
# stack_telepit <név>  – a sablonok/<név> tartalmát a helyére másolja,
#                        beköti a közös .env-et, és elindítja.
stack_telepit() {
    local nev="$1"
    local forras="${TELEPITO_DIR}/sablonok/${nev}"
    local cel="${PARK_DIR}/stackek/${nev}"

    [[ -d "$forras" ]] || { hiba "Nincs ilyen sablon: $nev"; return 1; }
    konyvtar "$cel"

    local f
    for f in "$forras"/*; do
        [[ -e "$f" ]] || continue
        local alap; alap="$(basename "$f")"
        # A felhasználó által szerkeszthető beállításokat nem írjuk felül.
        if [[ -e "$cel/$alap" && "$alap" != "compose.yml" ]]; then
            continue
        fi
        if [[ "${PROBA:-0}" == "1" ]]; then
            info "[próba] másolás: $alap -> $cel/"
        else
            cp -r "$f" "$cel/"
        fi
    done

    # A közös .env-et minden stack mellé bekötjük (a compose innen olvas).
    if [[ "${PROBA:-0}" != "1" ]]; then
        ln -sfn "${PARK_DIR}/.env" "${cel}/.env"
    fi
    ok "stack előkészítve: $nev"
}

stack_indit() {
    local nev="$1" cel="${PARK_DIR}/stackek/${1}"
    [[ -f "$cel/compose.yml" || "${PROBA:-0}" == "1" ]] || \
        { hiba "hiányzik: $cel/compose.yml"; return 1; }
    info "stack indítása: $nev …"
    ( cd "$cel" 2>/dev/null || exit 0; fut docker compose up -d --remove-orphans ) \
        && ok "fut: $nev" || hiba "nem indult el: $nev"
}

# Vár, amíg egy konténer egészségesre/futóra vált (max n másodperc).
konteneret_var() {
    local nev="$1" max="${2:-60}" i=0
    [[ "${PROBA:-0}" == "1" ]] && return 0
    while (( i < max )); do
        if docker inspect -f '{{.State.Running}}' "$nev" 2>/dev/null | grep -q true; then
            return 0
        fi
        sleep 2; i=$((i+2))
    done
    return 1
}

# --- Caddy vhost -------------------------------------------------------------
# vhost_ir <fájlnév> <tartalom...>  – a proxy sites.d mappájába ír egy blokkot.
vhost_ir() {
    local nev="$1"; shift
    local cel="${PARK_DIR}/stackek/proxy/sites.d/${nev}.caddy"
    printf '%s\n' "$*" | sso_szur | fajlt_ir "$cel"
}

sso_szur() {
    local vedett="${SSO_VEDETT:-$(env_ertek SSO_VEDETT 2>/dev/null || true)}" aktiv=0
    vedett="${vedett//\"/}"
    [[ -f "${PARK_DIR}/stackek/proxy/sites.d/00-sso.caddy" && -n "$vedett" ]] && aktiv=1
    awk -v lista=" ${vedett} " -v dom="${BELSO_DOMAIN:-park.lan}" -v aktiv="$aktiv" '
        $0 == "\timport sso" { next }
        { print }
        aktiv == 1 && /^https?:\/\/[^ ]+ \{$/ {
            h = $0; sub(/^https?:\/\//, "", h); sub(/ \{$/, "", h)
            v = "." dom
            if (length(h) > length(v) && substr(h, length(h) - length(v) + 1) == v)
                h = substr(h, 1, length(h) - length(v))
            if (index(lista, " " h " ") > 0) print "\timport sso"
        }'
}

alap_vhost_ir() {
    vhost_ir "00-alap" ":80 {
	handle /allapot.json {
		root * /srv/web/allapot
		header Access-Control-Allow-Origin *
		header Cache-Control no-store
		file_server
	}
	handle {
		reverse_proxy homepage:3000
	}
}"
}

proxy_ujratolt() {
    [[ "${PROBA:-0}" == "1" ]] && return 0
    if docker ps --format '{{.Names}}' | grep -qx "park-caddy"; then
        docker exec park-caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 \
            && ok "reverse proxy újratöltve" \
            || figy "a Caddy újratöltése nem sikerült (indítsd újra: park indit proxy)"
    fi
}

# --- összefoglaló ------------------------------------------------------------
declare -a OSSZEFOGLALO=()
szolgaltatas_jegyzes() {   # név | cím | megjegyzés
    OSSZEFOGLALO+=("$1|$2|${3:-}")
}
