#!/usr/bin/env bash
#
# Összekötő script – szerverpark  ↔  Raspberry Pi
# ================================================
# A nagy gépen (szerveren) futtatod, és ez köti össze a Pi-vel:
#
#   1. kapcsolat  – eléri-e a két gép egymást (SSH, Tailscale)
#   2. kulcs      – jelszó nélküli SSH a szervertől a Pi felé (mentéshez kell)
#   3. felderites – mi fut a Pi-n (portok, konténerek, szolgáltatások)
#   4. proxy      – a Pi szolgáltatásai is park.lan néven legyenek elérhetők
#   5. dns        – a Pi AdGuardja irányítsa a *.park.lan neveket a szerverre
#   6. mentes     – kölcsönös mentés: a Pi adatai a szerverre, a szerver
#                   mentése a Pi-re (így egyik gép halála sem visz mindent)
#   7. figyeles   – mit érdemes felvenni az Uptime Kumába
#
# Használat:
#   sudo ./osszekotes.sh                 – végigkérdezi
#   sudo ./osszekotes.sh --proba         – csak megmutatja, mit tenne
#   sudo ./osszekotes.sh --pi picloud    – másik gépnév/IP
#   sudo ./osszekotes.sh --csak mentes   – csak egy lépés
#
set -euo pipefail

TELEPITO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TELEPITO_DIR}/lib/kozos.sh"

NAPLO_FAJL="/var/log/szerverpark-osszekotes.log"
TARS_CONF="/etc/szerverpark-tars.conf"
PROBA=0
AUTO=0
CSAK=""
PI_HOST=""

LEPESEK=(kapcsolat kulcs felderites proxy dns mentes figyeles)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --proba|--dry-run) PROBA=1; shift ;;
        --auto) AUTO=1; shift ;;
        --pi)   PI_HOST="${2:-}"; shift 2 ;;
        --csak) CSAK="${2:-}"; shift 2 ;;
        -h|--help) sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) vege_hibaval "Ismeretlen kapcsoló: $1" ;;
    esac
done
export PROBA AUTO

printf '\n%s' "${C_FEHER}"
cat <<'BANNER'
  ┌──────────────────────────────────────────────┐
  │   Ö S S Z E K Ö T É S                        │
  │   szerverpark  ↔  Raspberry Pi               │
  └──────────────────────────────────────────────┘
BANNER
printf '%s' "${C_RESET}"

[[ "$PROBA" == "1" ]] && figy "PRÓBA MÓD – semmi nem változik meg."
[[ "$PROBA" == "1" ]] || root_kell

# --- beállítások -------------------------------------------------------------
[[ -f /etc/szerverpark.conf ]] && source /etc/szerverpark.conf
[[ -f "$TARS_CONF" ]] && source "$TARS_CONF"

PARK_DIR="${PARK_DIR:-/srv/szerverpark}"
ADAT_DIR="${ADAT_DIR:-${PARK_DIR}/adat}"
BELSO_DOMAIN="${BELSO_DOMAIN:-park.lan}"
PI_HOST="${PI_HOST:-${PI_HOST_MENTETT:-picloud}}"
PI_FELHASZNALO="${PI_FELHASZNALO:-}"
PI_MENTES_UT="${PI_MENTES_UT:-/mnt/mentes/park}"
KULCS="/root/.ssh/park_tars"

SZERVER_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}' || true)"
[[ -n "$SZERVER_IP" ]] || SZERVER_IP="$( { hostname -I 2>/dev/null || true; } | awk '{print $1}' || true)"

declare -A FUT=()
if [[ -n "$CSAK" ]]; then
    for l in "${LEPESEK[@]}"; do FUT[$l]=0; done
    IFS=',' read -ra k <<<"$CSAK"
    for l in "${k[@]}"; do
        l="$(echo "$l" | tr -d ' ')"
        [[ " ${LEPESEK[*]} " == *" $l "* ]] || vege_hibaval "Nincs ilyen lépés: $l"
        FUT[$l]=1
    done
    FUT[kapcsolat]=1
else
    for l in "${LEPESEK[@]}"; do FUT[$l]=1; done
fi

# segéd: parancs futtatása a Pi-n
pi_futtat() { ssh -o BatchMode=yes -o ConnectTimeout=6 "$PI_HOST" "$@" 2>/dev/null; }

# ============================================================== 1. kapcsolat ==
cim "Kapcsolat ellenőrzése"
info "a Pi elérési neve: ${PI_HOST}   (másik: --pi <név vagy IP>)"
info "a szerver IP-je:   ${SZERVER_IP:-ismeretlen}"

PI_ELERHETO=0
if PI_INFO="$(pi_futtat 'echo "$(hostname)|$(uname -m)|$(. /etc/os-release; echo "$PRETTY_NAME")|$(hostname -I | awk "{print \$1}")"')"; then
    IFS='|' read -r PI_NEV PI_ARCH PI_OS PI_IP <<<"$PI_INFO"
    ok "elérhető: ${PI_NEV} (${PI_OS}, ${PI_ARCH}) – IP: ${PI_IP}"
    PI_ELERHETO=1
else
    figy "A(z) ${PI_HOST} most NEM érhető el jelszó nélküli SSH-val."
    info "Lehetséges okok:"
    info "  • a Pi ki van kapcsolva vagy nincs hálózaton"
    info "  • a Tailscale nem fut valamelyik gépen  →  tailscale status"
    info "  • még nincs SSH-kulcs  →  a 2. lépés (kulcs) ezt megoldja"
fi

if van_parancs tailscale; then
    TS="$(tailscale status --peers=false 2>/dev/null | head -1 || true)"
    [[ -n "$TS" ]] && info "Tailscale (szerver): ${TS}" || figy "a Tailscale nem fut ezen a gépen"
else
    figy "Tailscale nincs telepítve a szerverre – kívülről így nem érnéd el a parkot."
    if igen_nem "Telepítsem most a Tailscale-t?" "i"; then
        fut bash -c 'curl -fsSL https://tailscale.com/install.sh | sh'
        fut tailscale up
    fi
fi

# ================================================================== 2. kulcs ==
if [[ "${FUT[kulcs]}" == "1" ]]; then
    cim "SSH-kulcs a szervertől a Pi felé"
    info "Ez kell ahhoz, hogy a mentés éjjel, jelszó nélkül is le tudjon futni."

    if [[ -f "$KULCS" ]]; then
        kihagy "kulcs már létezik: $KULCS"
    else
        konyvtar /root/.ssh 0700
        fut ssh-keygen -t ed25519 -N "" -C "szerverpark->${PI_HOST}" -f "$KULCS"
        ok "kulcs létrehozva: $KULCS"
    fi

    if [[ "$PI_ELERHETO" == "1" ]] && pi_futtat "grep -q '$(cut -d' ' -f2 "$KULCS.pub" 2>/dev/null || echo NINCS)' ~/.ssh/authorized_keys"; then
        kihagy "a kulcs már fent van a Pi-n"
    elif [[ "$PROBA" == "1" ]]; then
        info "[próba] ssh-copy-id -i ${KULCS}.pub ${PI_HOST}"
    else
        info "Most a Pi jelszavát fogja kérni (egyszer):"
        if ssh-copy-id -i "${KULCS}.pub" "$PI_HOST"; then
            ok "kulcs telepítve a Pi-re"
            PI_ELERHETO=1
        else
            figy "a kulcs telepítése nem sikerült – a mentés-lépés ki fog maradni"
        fi
    fi

    # SSH-beállítás, hogy a 'park-tars' név mindig ezt a kulcsot használja
    if [[ "$PROBA" != "1" ]] && ! grep -q "Host park-tars" /root/.ssh/config 2>/dev/null; then
        cat >>/root/.ssh/config <<SSHC

Host park-tars
    HostName ${PI_IP:-$PI_HOST}
    User ${PI_FELHASZNALO:-$(ssh -G "$PI_HOST" 2>/dev/null | awk '/^user /{print $2; exit}')}
    IdentityFile ${KULCS}
    StrictHostKeyChecking accept-new
SSHC
        chmod 600 /root/.ssh/config
        ok "'park-tars' SSH-bejegyzés létrehozva"
    fi
fi

# ============================================================= 3. felderítés ==
declare -a PI_SZOLGALTATASOK=()
if [[ "${FUT[felderites]}" == "1" && "$PI_ELERHETO" == "1" ]]; then
    cim "Mi fut a Pi-n?"

    PORTOK="$(pi_futtat "ss -tlnH 2>/dev/null | awk '{print \$4}' | sed 's/.*://' | sort -un" || true)"
    KONTENEREK="$(pi_futtat 'command -v docker >/dev/null && docker ps --format "{{.Names}} {{.Ports}}" 2>/dev/null' || true)"
    SZOLG="$(pi_futtat "systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print \$1}' | head -30" || true)"

    if [[ -n "$PORTOK" ]]; then
        info "nyitott portok a Pi-n:"
        for p in $PORTOK; do
            [[ "$p" == "22" || "$p" == "53" ]] && continue
            leiras=""
            case "$p" in
                80)   leiras="webszerver" ;;
                3000) leiras="AdGuard Home / webalkalmazás" ;;
                8080) leiras="webalkalmazás (csevegő?)" ;;
                8123) leiras="Home Assistant" ;;
                1883) leiras="MQTT" ;;
                9090) leiras="Cockpit / Prometheus" ;;
                3001) leiras="Uptime Kuma" ;;
            esac
            printf '%s│%s      %-6s %s\n' "$C_KEK" "$C_RESET" "$p" "$leiras"
            PI_SZOLGALTATASOK+=("$p|$leiras")
        done
    fi
    [[ -n "$KONTENEREK" ]] && { info "konténerek a Pi-n:"; sed 's/^/      /' <<<"$KONTENEREK"; }
    if grep -q csevego <<<"${SZOLG:-}"; then
        ok "fut a csevego.service (a csevegő app)"
    fi
fi

# ================================================================== 4. proxy ==
if [[ "${FUT[proxy]}" == "1" && "$PI_ELERHETO" == "1" ]]; then
    cim "A Pi szolgáltatásai park.lan néven"
    info "Így a Pi-n futó dolgok is szép címet kapnak, a szerver proxyján át."

    for bejegyzes in "${PI_SZOLGALTATASOK[@]:-}"; do
        [[ -z "$bejegyzes" ]] && continue
        port="${bejegyzes%%|*}"; leiras="${bejegyzes#*|}"
        alapnev="pi${port}"
        case "$port" in
            8080) alapnev="csevego" ;;
            8123) alapnev="ha" ;;
            3000) alapnev="adguard" ;;
            3001) alapnev="figyelo-pi" ;;
            80)   alapnev="pi" ;;
        esac
        igen_nem "  ${port} (${leiras:-?}) → bekötöd ${alapnev}.${BELSO_DOMAIN} néven?" "n" || continue
        nev="$(kerdez "    milyen néven" "$alapnev")"
        cat <<CADDY | fajlt_ir "${PARK_DIR}/stackek/proxy/sites.d/60-tavoli-${nev}.caddy"
# A Raspberry Pi-n futó szolgáltatás (összekötés: $(date '+%F')).
http://${nev}.${BELSO_DOMAIN} {
	reverse_proxy ${PI_IP}:${port}
}
CADDY
        ok "  http://${nev}.${BELSO_DOMAIN}  ->  ${PI_IP}:${port}"
    done

    if [[ "$PROBA" != "1" ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx park-caddy; then
        docker exec park-caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 \
            && ok "proxy újratöltve" || figy "a proxy újratöltése nem sikerült (park ujra proxy)"
    fi
fi

# ==================================================================== 5. DNS ==
if [[ "${FUT[dns]}" == "1" ]]; then
    cim "DNS – a Pi irányítsa a park.lan neveket"
    info "Ez az a lépés, amitől a szép címek az EGÉSZ hálózaton működnek,"
    info "nem csak ott, ahol kézzel beírtad a hosts fájlba."

    ADGUARD=0
    if [[ "$PI_ELERHETO" != "1" ]]; then
        ADGUARD=-1
    elif pi_futtat 'systemctl is-active --quiet AdGuardHome || pgrep -x AdGuardHome >/dev/null'; then
        ADGUARD=1; ok "AdGuard Home fut a Pi-n"
    fi

    if [[ "$ADGUARD" == "-1" ]]; then
        figy "A Pi nem elérhető, ezért NEM tudom megnézni, fut-e rajta AdGuard."
        info "Ha fut, ezt a DNS-átírást vedd fel benne:"
        printf '%s│%s      %s*.%s%s  →  %s%s%s\n' "$C_KEK" "$C_RESET" "$C_FEHER" "$BELSO_DOMAIN" "$C_RESET" "$C_FEHER" "$SZERVER_IP" "$C_RESET"
        info "Ha nem fut, a router DNS-ébe kerüljön ugyanez."
    elif [[ "$ADGUARD" == "1" ]]; then
        info "Vedd fel ezt a DNS-átírást (DNS rewrite) az AdGuardban:"
        printf '%s│%s      %s*.%s%s  →  %s%s%s\n' "$C_KEK" "$C_RESET" "$C_FEHER" "$BELSO_DOMAIN" "$C_RESET" "$C_FEHER" "$SZERVER_IP" "$C_RESET"
        info "Webfelület:  http://${PI_IP:-$PI_HOST}:3000  →  Szűrők → DNS rewrites → Add"
        if igen_nem "Felvegyem helyetted az AdGuard API-ján keresztül?" "n"; then
            ag_user="$(kerdez '  AdGuard felhasználó' 'admin')"
            read -rsp "  AdGuard jelszó: " ag_pw </dev/tty; echo
            if [[ "$PROBA" == "1" ]]; then
                info "[próba] POST /control/rewrite/add  (*.${BELSO_DOMAIN} -> ${SZERVER_IP})"
            else
                valasz="$(curl -s -u "${ag_user}:${ag_pw}" -H 'Content-Type: application/json' \
                    -d "{\"domain\":\"*.${BELSO_DOMAIN}\",\"answer\":\"${SZERVER_IP}\"}" \
                    "http://${PI_IP:-$PI_HOST}:3000/control/rewrite/add" -w '%{http_code}' -o /dev/null || true)"
                [[ "$valasz" == "200" ]] && ok "DNS-átírás felvéve az AdGuardba" \
                    || figy "nem sikerült (HTTP ${valasz}) – vedd fel kézzel a webfelületen"
            fi
        fi
    else
        info "Nincs AdGuard a Pi-n. Két lehetőség:"
        info "  a) telepítsd a Pi-re (ajánlott): reklámszűrés + helyi DNS egyben"
        info "  b) a router DNS-ébe vedd fel: *.${BELSO_DOMAIN} -> ${SZERVER_IP}"
    fi
fi

# ================================================================= 6. mentés ==
if [[ "${FUT[mentes]}" == "1" && "$PI_ELERHETO" == "1" ]]; then
    cim "Kölcsönös mentés"
    info "Cél: egyik gép elvesztése se vigyen el mindent."

    # --- 6/a: a Pi adatai a szerverre (a szerver húzza le) ---
    if igen_nem "A Pi fontos mappái ide másolódjanak (és bekerüljenek a napi mentésbe)?" "i"; then
        alap_mappak="/home/$(pi_futtat 'whoami' || echo pi)"
        MAPPAK="$(kerdez '  mely mappák a Pi-ről (szóközzel)' "$alap_mappak /etc")"
        konyvtar "${ADAT_DIR}/pi-mentes"
        cat <<PIM | fajlt_ir /usr/local/bin/park-pi-mentes
#!/usr/bin/env bash
# A Raspberry Pi fontos mappáinak áthúzása a szerverre.
# Innen a napi restic mentés (park-mentes) már magától viszi tovább.
set -euo pipefail
CEL="${ADAT_DIR}/pi-mentes"
mkdir -p "\$CEL"
for m in ${MAPPAK}; do
    echo "== Pi -> szerver: \$m"
    rsync -a --delete --timeout=60 \\
        -e "ssh -i ${KULCS} -o BatchMode=yes -o ConnectTimeout=10" \\
        --exclude '.cache' --exclude 'node_modules' --exclude '*.sock' \\
        "${PI_HOST}:\$m/" "\$CEL/\$(basename "\$m")/" || echo "  (kihagyva: \$m)"
done
echo "Kész: \$(date '+%F %T')"
PIM
        fut chmod +x /usr/local/bin/park-pi-mentes
        ok "park-pi-mentes létrehozva (a napi mentés előtt fut le)"
    fi

    # --- 6/b: a szerver mentése a Pi-re ---
    if igen_nem "A szerver mentése másolódjon át a Pi-re is (külső lemezre)?" "i"; then
        PI_MENTES_UT="$(kerdez '  útvonal a Pi-n (legyen rajta külső lemez!)' "$PI_MENTES_UT")"
        if [[ "$PROBA" == "1" ]]; then
            info "[próba] restic tároló létrehozása: sftp:park-tars:${PI_MENTES_UT}"
        else
            pi_futtat "mkdir -p '${PI_MENTES_UT}'" || figy "a mappát nem sikerült létrehozni a Pi-n"
            set -a; source "${PARK_DIR}/.env"; set +a
            if RESTIC_PASSWORD="$RESTIC_JELSZO" restic -r "sftp:park-tars:${PI_MENTES_UT}" snapshots >/dev/null 2>&1; then
                kihagy "a távoli restic tároló már létezik"
            elif RESTIC_PASSWORD="$RESTIC_JELSZO" restic -r "sftp:park-tars:${PI_MENTES_UT}" init >/dev/null 2>&1; then
                ok "távoli restic tároló létrehozva a Pi-n"
            else
                figy "a távoli tárolót nem sikerült létrehozni (van restic/sftp a Pi-n?)"
            fi
            env_beallit "MENTES_TAVOLI" "sftp:park-tars:${PI_MENTES_UT}"
        fi
        ok "a napi mentés ezentúl a Pi-re is átmásolja a pillanatképeket"
    fi
fi

# =============================================================== 7. figyelés ==
if [[ "${FUT[figyeles]}" == "1" ]]; then
    cim "Figyelés"
    info "Vedd fel ezeket az Uptime Kumába (ha a Pi-n fut, akkor a szervert figyeli"
    info "és fordítva – így a másik gép elszállásáról is kapsz értesítést):"
    printf '%s│%s      %-28s %s\n' "$C_KEK" "$C_RESET" "szerver (park)"  "http://${SZERVER_IP}"
    printf '%s│%s      %-28s %s\n' "$C_KEK" "$C_RESET" "AI"              "http://${SZERVER_IP}:3000"
    printf '%s│%s      %-28s %s\n' "$C_KEK" "$C_RESET" "Nextcloud"       "http://${SZERVER_IP}:8081"
    printf '%s│%s      %-28s %s\n' "$C_KEK" "$C_RESET" "Pi"              "ping ${PI_IP:-$PI_HOST}"
fi

# ============================================================== összefoglaló ==
if [[ "$PROBA" != "1" ]]; then
    cat >"$TARS_CONF" <<CONF
# Szerverpark – a társgép (Raspberry Pi) adatai. Az összekötés írta.
PI_HOST_MENTETT="${PI_HOST}"
PI_IP="${PI_IP:-}"
PI_MENTES_UT="${PI_MENTES_UT}"
KULCS_FAJL="${KULCS}"
CONF
    chmod 600 "$TARS_CONF"
fi

printf '\n%s╭──────────────────────────────────────────────────────────╮%s\n' "$C_ZOLD" "$C_RESET"
printf '%s│%s  Összekötés kész.\n' "$C_ZOLD" "$C_RESET"
printf '%s╰──────────────────────────────────────────────────────────╯%s\n\n' "$C_ZOLD" "$C_RESET"
cat <<VEGE
  Ellenőrzés:     park tars
  Mentés próba:   park-pi-mentes && park mentes
  Pi elérése:     ssh park-tars

VEGE
