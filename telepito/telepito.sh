#!/usr/bin/env bash
#
# Szerverpark telepítő
# ====================
# Egy friss Debian 13 (Trixie) gépre – fizikai vasra, VM-be vagy Proxmox LXC-be –
# felteszi és be is állítja a teljes self-hosting készletet:
#
#   • AI            – Ollama + Open WebUI (GPU-t automatikusan felismeri)
#   • Fájltárolás   – Nextcloud + FileBrowser
#   • Helyi megosztás – Samba (Windows/telefon/Linux fájlkezelőből látszik)
#   • Weboldal-hosting – Caddy, automatikus HTTPS-sel, több oldalhoz
#   • Self-hosting alap – Dockge, Uptime Kuma, Homepage, Vaultwarden, Forgejo
#   • Mentés        – restic, napi automatikus mentéssel
#
# Használat:
#   sudo ./telepito.sh                 – varázsló (kérdez, majd telepít)
#   sudo ./telepito.sh --proba         – SEMMIT nem módosít, csak megmutatja
#   sudo ./telepito.sh --auto          – kérdés nélkül, a konfig szerint
#   sudo ./telepito.sh --csak ai,web   – csak a felsorolt modulok
#   sudo ./telepito.sh --lista         – mit tud telepíteni
#   sudo ./telepito.sh --conf /út/fájl – másik konfigfájl
#
set -euo pipefail

TELEPITO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TELEPITO_DIR}/lib/kozos.sh"
source "${TELEPITO_DIR}/lib/csomagkezelo.sh"

CONF_FAJL="/etc/szerverpark.conf"
PROBA=0
AUTO=0
CSAK=""

# --- modulok sorrendben ------------------------------------------------------
MODULOK=(alap docker proxy dns ai fajlok samba szinkron web selfhost media iratok otthon fotok konyvek hirek eszkozok offline penz orarend jatek botok ci monitor jegyzetek megosztas leltar lemez cronfigyelo kijelzo vedelem karbantartas vm sso mentes leallas portal)
OPCIONALIS=" dns otthon fotok konyvek hirek eszkozok offline penz orarend jatek botok ci monitor jegyzetek megosztas leltar lemez cronfigyelo kijelzo vedelem sso leallas portal "
declare -A MODUL_LEIRAS=(
    [alap]="Rendszer-alapok: csomagok, tűzfal, automatikus biztonsági frissítés"
    [docker]="Docker Engine + Compose + a közös 'park' hálózat"
    [proxy]="Caddy reverse proxy (szép címek + automatikus HTTPS)"
    [ai]="AI: helyi modellek (Ollama) + felhős átjáró (Claude/GPT/Gemini) + Open WebUI"
    [fajlok]="Nextcloud (saját felhő) + FileBrowser (gyors webes fájlkezelő)"
    [samba]="Samba – helyi hálózati fájlmegosztás (\\\\szerver\\megosztas)"
    [web]="Saját weboldalak kiszolgálása (statikus oldalak, több domain)"
    [selfhost]="Dockge, Uptime Kuma, Homepage, Vaultwarden, Forgejo"
    [szinkron]="FileBrowser (webes fájlkezelő) + Syncthing (eszközök közti szinkron)"
    [media]="Jellyfin (film, sorozat) + Navidrome (zene)"
    [iratok]="Paperless-ngx (iratok OCR-rel), Linkding (könyvjelzők), Wallabag (cikkek)"
    [karbantartas]="Watchtower (konténer-frissítés), Dozzle (naplók), Speedtest Tracker"
    [vm]="Virtuális gépek (KVM/libvirt) + test lab (Incus) + Cockpit webfelület"
    [mentes]="restic mentés + napi automatikus időzítés"
    [dns]="Unbound – saját rekurzív DNS-feloldó (a Pi-hole mögé)"
    [otthon]="Home Assistant + Mosquitto MQTT (okosotthon, ESP32-szenzorok)"
    [fotok]="Immich – fotók és videók, telefonos feltöltéssel"
    [konyvek]="Kavita (e-könyv, képregény) + Audiobookshelf (hangoskönyv, podcast)"
    [hirek]="Miniflux (RSS-olvasó) + changedetection.io (weboldal-figyelő)"
    [eszkozok]="Stirling-PDF + IT-Tools"
    [offline]="Kiwix – offline Wikipédia és tudástár"
    [penz]="Actual Budget – költségvetés"
    [orarend]="Órarend a saját Kréta-fiókodból (változás-értesítés, naptár-feed)"
    [jatek]="Minecraft-szerver (Paper/Fabric, Modrinth modokkal)"
    [botok]="Saját Python botok konténerben (Discord, kripto, …)"
    [ci]="Forgejo Actions runner – CI a saját git szerverhez"
    [monitor]="Beszel – CPU/RAM/lemez/hőfok grafikonok"
    [jegyzetek]="Memos (gyors jegyzetek) + Vikunja (teendők, kanban)"
    [megosztas]="PrivateBin (titkosított paste) + Excalidraw (rajztábla)"
    [leltar]="Homebox – háztartási leltár QR-címkékkel"
    [lemez]="Scrutiny – lemezek S.M.A.R.T. állapota, értesítéssel"
    [cronfigyelo]="Healthchecks – szól, ha a mentés (vagy más időzített feladat) kimarad"
    [kijelzo]="ESP32-eszközöknek: állapot-JSON (http://<ip>/allapot.json) + VM-távirányító (:8097)"
    [vedelem]="CrowdSec – behatolás-védelem, tűzfalas tiltással"
    [sso]="Tinyauth – közös belépés a kiválasztott címek elé"
    [leallas]="Leálláskor menti a konténereket/VM-eket, kikapcsoláskor a Tapo-dugaljat is lekapcsolja"
    [portal]="Captive portál a hotspothoz: e-mail + wifi-jelszó + ntfy-jóváhagyás (30 nap)"
)

# --- parancssor --------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --proba|--dry-run) PROBA=1; shift ;;
        --auto)            AUTO=1; shift ;;
        --csak)            CSAK="${2:-}"; shift 2 ;;
        --conf)            CONF_FAJL="${2:-}"; shift 2 ;;
        --lista)
            printf '\nTelepíthető modulok:\n\n'
            for m in "${MODULOK[@]}"; do printf '  %-10s %s\n' "$m" "${MODUL_LEIRAS[$m]}"; done
            printf '\n'; exit 0 ;;
        -h|--help)
            sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) vege_hibaval "Ismeretlen kapcsoló: $1  (segítség: --help)" ;;
    esac
done

export PROBA AUTO TELEPITO_DIR

# --- fejléc ------------------------------------------------------------------
printf '\n%s' "$C_FEHER"
cat <<'BANNER'
  ┌────────────────────────────────────────────┐
  │   S Z E R V E R P A R K   telepítő          │
  │   AI · fájltár · web · megosztás · backup   │
  └────────────────────────────────────────────┘
BANNER
printf '%s' "$C_RESET"

if [[ "$PROBA" == "1" ]]; then
    figy "PRÓBA MÓD – semmi nem változik meg a gépen (root sem kell hozzá)."
else
    root_kell
fi

# --- rendszer ellenőrzése ----------------------------------------------------
cim "Rendszer ellenőrzése"

if rendszer_felismer; then
    info "Rendszer: ${OS_NEV}  (család: ${OS_CSALAD}, tűzfal: ${TUZFAL})"
    case "$OS_CSALAD" in
        debian) ok "Debian-alap – ez az elsődlegesen tesztelt rendszer." ;;
        fedora) ok "Fedora/RHEL-alap – támogatott (dnf)." ;;
        suse)   ok "openSUSE-alap – támogatott (zypper)." ;;
        arch)   figy "Arch-alap: működik, de rolling rendszer szerveren kockázatosabb." ;;
    esac
else
    vege_hibaval "Ismeretlen disztribúció – a telepítő apt/dnf/zypper/pacman rendszereket ismer."
fi

if [[ -f /etc/pve/local/pve-ssl.key ]]; then
    figy "Úgy tűnik, ez maga a Proxmox HOST gép."
    figy "Jobb, ha a szolgáltatások egy VM-be vagy LXC-be kerülnek, nem a hostra."
    igen_nem "Biztosan itt folytassuk?" "n" || exit 0
fi

if [[ -f /proc/1/environ ]] && grep -qa container=lxc /proc/1/environ 2>/dev/null; then
    figy "LXC konténerben futunk – a Dockerhez a konténer legyen privilegizált"
    figy "vagy legalább nesting=1 opcióval indítva (Proxmox: Options → Features)."
fi

ARCH="$(uname -m)"
info "Architektúra: $ARCH"
MEM_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
info "Memória: ${MEM_GB} GB"
(( MEM_GB < 4 )) && figy "4 GB alatt a Nextcloud + AI együtt szűkös lesz."

# --- konfiguráció ------------------------------------------------------------
cim "Beállítások"

if [[ -r "$CONF_FAJL" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FAJL"
    ok "beállítások betöltve: $CONF_FAJL"
elif [[ -f "$CONF_FAJL" && "$PROBA" == "1" ]]; then
    figy "a configfájl root-only ($CONF_FAJL) – próba módban az alapértékekkel megyek"
elif [[ "$AUTO" == "1" ]]; then
    vege_hibaval "--auto módhoz kell egy konfigfájl: $CONF_FAJL (minta: szerver.conf.pelda)"
fi

# alapértékek (a konfigfájl felülírja)
PARK_DIR="${PARK_DIR:-/srv/szerverpark}"
ADAT_DIR="${ADAT_DIR:-${PARK_DIR}/adat}"
IDOZONA="${IDOZONA:-Europe/Budapest}"
BELSO_DOMAIN="${BELSO_DOMAIN:-park.lan}"
PUBLIKUS_DOMAIN="${PUBLIKUS_DOMAIN:-}"
EMAIL="${EMAIL:-}"
SMB_FELHASZNALO="${SMB_FELHASZNALO:-${SUDO_USER:-admin}}"
AI_MODELLEK="${AI_MODELLEK:-}"          # üres = a géphez automatikusan válogatva
AI_BEAGYAZO="${AI_BEAGYAZO:-nomic-embed-text}"
WHISPER_MODELL="${WHISPER_MODELL:-base}"
AI_KEPGENERALAS="${AI_KEPGENERALAS:-n}"
SSH_PORT="${SSH_PORT:-22}"

if [[ "$AUTO" != "1" && ! -f "$CONF_FAJL" ]]; then
    info "Néhány kérdés, aztán magától megy. (Enter = a szögletes zárójelben lévő)"
    printf '\n'
    PARK_DIR="$(kerdez  'Hova kerüljenek a beállítások' "$PARK_DIR")"
    ADAT_DIR="$(kerdez  'Hova kerüljenek az ADATOK (ide érdemes nagy lemezt tenni)' "${PARK_DIR}/adat")"
    IDOZONA="$(kerdez   'Időzóna' "$IDOZONA")"
    BELSO_DOMAIN="$(kerdez 'Belső (otthoni) domain a szolgáltatásokhoz' "$BELSO_DOMAIN")"
    if igen_nem 'Lesz publikus weboldal is (saját domain, internetről elérhető)?' 'i'; then
        PUBLIKUS_DOMAIN="$(kerdez 'A weboldal domainje' "$PUBLIKUS_DOMAIN")"
        EMAIL="$(kerdez 'E-mail cím a Let'"'"'s Encrypt tanúsítványhoz' "$EMAIL")"
    fi
    SMB_FELHASZNALO="$(kerdez 'Melyik felhasználó kapjon Samba-hozzáférést' "$SMB_FELHASZNALO")"
    info "Az AI modelleket alapból a géped méretéhez válogatom (RAM/VRAM alapján)."
    AI_MODELLEK="$(kerdez 'AI modellek – üres = automatikus, vagy sorold fel őket' "$AI_MODELLEK")"
    igen_nem 'Kell képgenerálás is (ComfyUI)? Csak erős GPU-val ajánlott' 'n' \
        && AI_KEPGENERALAS="i" || AI_KEPGENERALAS="n"
fi

export PARK_DIR ADAT_DIR IDOZONA BELSO_DOMAIN PUBLIKUS_DOMAIN EMAIL \
       SMB_FELHASZNALO AI_MODELLEK AI_BEAGYAZO WHISPER_MODELL AI_KEPGENERALAS SSH_PORT

info "beállítások:  $PARK_DIR  |  adatok: $ADAT_DIR  |  belső domain: $BELSO_DOMAIN"

# --- melyik modul fusson -----------------------------------------------------
declare -A FUSSON=()
declare -A JEGYZETT=()      # ez kerül a configba (a --csak nem írja át a többit)
if [[ -n "$CSAK" ]]; then
    for m in "${MODULOK[@]}"; do FUSSON[$m]=0; done
    IFS=',' read -ra kert <<<"$CSAK"
    for m in "${kert[@]}"; do
        m="$(echo "$m" | tr -d ' ')"
        [[ -n "${MODUL_LEIRAS[$m]:-}" ]] || vege_hibaval "Nincs ilyen modul: $m (lista: --lista)"
        FUSSON[$m]=1
    done
    # az alap + docker mindig kell a többihez
    for m in alap docker; do [[ "${FUSSON[$m]}" == 1 ]] || FUSSON[$m]=1; done
    # A --csak csak EZT a futást szűkíti: a configban a többi modul állapota
    # maradjon, ami volt. Enélkül egy "--csak ai" futás után a config szerint
    # semmi más nem lenne felrakva, és egy későbbi teljes futás kihagyná őket.
    for m in "${MODULOK[@]}"; do
        valtozo="MOD_${m^^}"
        JEGYZETT[$m]="$([[ "${FUSSON[$m]}" == 1 ]] && echo 1 || echo "$([[ "${!valtozo:-}" == "i" ]] && echo 1 || echo 0)")"
    done
else
    cim "Mi kerüljön fel?"
    for m in "${MODULOK[@]}"; do
        valtozo="MOD_${m^^}"
        elore="${!valtozo:-}"
        if [[ -n "$elore" ]]; then
            [[ "$elore" == "i" ]] && FUSSON[$m]=1 || FUSSON[$m]=0
            continue
        fi
        alapert="i"
        [[ "$OPCIONALIS" == *" $m "* ]] && alapert="n"
        case "$m" in
            alap|docker) FUSSON[$m]=1 ;;
            *) igen_nem "$(printf '%-9s – %s' "$m" "${MODUL_LEIRAS[$m]}")" "$alapert" \
                   && FUSSON[$m]=1 || FUSSON[$m]=0 ;;
        esac
    done
    for m in "${MODULOK[@]}"; do JEGYZETT[$m]="${FUSSON[$m]}"; done
fi

# --- konfig mentése ----------------------------------------------------------
if [[ "$PROBA" != "1" ]]; then
    MENTENDO_KULCSOK=(
        PARK_DIR ADAT_DIR TAROLO_DIR IDOZONA SSH_PORT TUZFAL_EXTRA
        BELSO_DOMAIN PUBLIKUS_DOMAIN EMAIL SMB_FELHASZNALO MEGOSZTAS_DIR
        AI_MODELLEK AI_BEAGYAZO WHISPER_MODELL AI_KEPGENERALAS
        ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GROQ_API_KEY
        MISTRAL_API_KEY DEEPSEEK_API_KEY XAI_API_KEY OPENROUTER_API_KEY
        VM_CPU VM_RAM VM_LEMEZ VM_OS LAB_CPU LAB_RAM
        MEDIA_DIR SZINKRON_DIR NC_FAJL_DIR IRATOK_DIR AI_MODELL_DIR
        MENTES_CEL MENTES_EXTRA ORZO_EXTRA ORZO_TUREM NTFY_URL DISCORD_WEBHOOK ERTESITO_EMAIL
        UNBOUND_PORT PIHOLE_UNBOUND FOTO_DIR FOTO_ML KONYV_DIR KIWIX_DIR KIWIX_LETOLT
        MINECRAFT_EULA MC_TIPUS MC_VERZIO MC_MEMORIA MC_MODOK BOTOK_DIR CI_PARHUZAMOS SSO_VEDETT
    )
    MEGORZENDO=""
    if [[ -f "$CONF_FAJL" ]]; then
        ISMERT="$(IFS='|'; echo "${MENTENDO_KULCSOK[*]}")"
        MEGORZENDO="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$CONF_FAJL" 2>/dev/null \
            | grep -vE "^(${ISMERT}|MOD_[A-Z]+)=" || true)"
    fi
    {
        echo "# Szerverpark – a telepítő ezt olvassa vissza (--auto módban is)."
        echo "# Készült: $(date '+%F %T')"
        for v in "${MENTENDO_KULCSOK[@]}"; do
            printf '%s="%s"\n' "$v" "${!v:-}"
        done
        for m in "${MODULOK[@]}"; do
            printf 'MOD_%s="%s"\n' "${m^^}" "$([[ "${JEGYZETT[$m]:-${FUSSON[$m]}}" == 1 ]] && echo i || echo n)"
        done
        if [[ -n "$MEGORZENDO" ]]; then
            echo
            echo "# saját kulcsok – a telepítő nem nyúl hozzájuk"
            echo "$MEGORZENDO"
        fi
    } >"$CONF_FAJL"
    chmod 600 "$CONF_FAJL"
    ok "beállítások elmentve: $CONF_FAJL"
fi

# --- könyvtárszerkezet -------------------------------------------------------
konyvtar "$PARK_DIR"
konyvtar "$PARK_DIR/stackek"
konyvtar "$ADAT_DIR"
konyvtar "$PARK_DIR/web"
konyvtar "$PARK_DIR/mentes"
env_frissit "TZ" "$IDOZONA"
env_frissit "PARK_DIR" "$PARK_DIR"
env_frissit "ADAT_DIR" "$ADAT_DIR"
env_frissit "BELSO_DOMAIN" "$BELSO_DOMAIN"
env_beallit "PUID" "1000"
env_beallit "PGID" "1000"

# --- modulok futtatása -------------------------------------------------------
KEZDET=$(date +%s)
for m in "${MODULOK[@]}"; do
    [[ "${FUSSON[$m]:-0}" == "1" ]] || continue
    modul="${TELEPITO_DIR}/modulok/${m}.sh"
    [[ -f "$modul" ]] || { figy "hiányzó modul: $modul"; continue; }
    # shellcheck disable=SC1090
    source "$modul"
done

proxy_ujratolt

# --- összefoglaló ------------------------------------------------------------
PERC=$(( ( $(date +%s) - KEZDET ) / 60 ))
# A gép saját IP-je: az alapértelmezett útvonal szerinti cím (nem a dockeré).
IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || true)"
[[ -n "$IP" ]] || IP="$( { hostname -I 2>/dev/null || true; } | awk '{print $1}' || true)"

printf '\n%s╭──────────────────────────────────────────────────────────╮%s\n' "$C_ZOLD" "$C_RESET"
printf '%s│%s  KÉSZ – a szerverpark áll. (%s perc)\n' "$C_ZOLD" "$C_RESET" "$PERC"
printf '%s╰──────────────────────────────────────────────────────────╯%s\n\n' "$C_ZOLD" "$C_RESET"

if (( ${#OSSZEFOGLALO[@]} )); then
    printf '  %-16s %-34s %s\n' "SZOLGÁLTATÁS" "CÍM" "MEGJEGYZÉS"
    printf '  %s\n' "$(printf '─%.0s' {1..76})"
    for sor in "${OSSZEFOGLALO[@]}"; do
        IFS='|' read -r nev cim_ megj <<<"$sor"
        printf '  %-16s %-34s %s\n' "$nev" "$cim_" "$megj"
    done
    printf '\n'
fi

cat <<ZARO
  Hogy a szép címek működjenek, a hálózaton a(z) ${BELSO_DOMAIN} nevek
  mutassanak erre a gépre (${IP:-a szerver IP-jére}). Két mód:

    1) AdGuard Home / router DNS-ébe: *.${BELSO_DOMAIN}  ->  ${IP:-SZERVER_IP}
    2) vagy a kliens gépek hosts fájljába (Linux/macOS: /etc/hosts,
       Windows: C:\\Windows\\System32\\drivers\\etc\\hosts):

$( for sor in "${OSSZEFOGLALO[@]}"; do
     IFS='|' read -r _ c _ <<<"$sor"
     host="${c#http://}"; host="${host#https://}"; host="${host%%/*}"; host="${host%%:*}"
     [[ "$host" == *"$BELSO_DOMAIN" ]] && printf '       %s  %s\n' "${IP:-SZERVER_IP}" "$host"
   done | sort -u )

  Jelszavak:   ${PARK_DIR}/.env        (park jelszavak)
  Kezelés:     park allapot | park indit <stack> | park naplo <stack> | park mentes
  Napló:       ${NAPLO_FAJL}

ZARO
