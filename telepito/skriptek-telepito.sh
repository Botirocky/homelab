#!/usr/bin/env bash
set -euo pipefail

TELEPITO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TELEPITO_DIR}/lib/kozos.sh"
source "${TELEPITO_DIR}/lib/csomagkezelo.sh"

CONF_FAJL="/etc/szerverpark.conf"
[[ -f "$CONF_FAJL" ]] && source "$CONF_FAJL"
PARK_DIR="${PARK_DIR:-/srv/szerverpark}"
ADAT_DIR="${ADAT_DIR:-${PARK_DIR}/adat}"
BELSO_DOMAIN="${BELSO_DOMAIN:-park.lan}"
export PARK_DIR

PROBA=0; AUTO=0; CSAK=""; NO_DOCKER=0; AKCIO="telepit"
SZKRIPTEK=(park park-ai-konfig park-egeszseg park-ertesito park-orzo park-koszonto park-tarolo park-halozat park-figyelo park-speedtest-boot park-arp-segito park-allapot park-gepek)

LEPESEK=(fuggosegek konyvtar szkriptek kiegeszites idozitok koszonto ertesites)
declare -A LEPES_LEIRAS=(
    [fuggosegek]="csomagok letöltése (docker, restic, curl, jq, git, mail)"
    [konyvtar]="PARK_DIR váz + .env titkokkal + /etc/szerverpark.conf"
    [szkriptek]="park és a segéd-szkriptek a /usr/local/bin-be"
    [kiegeszites]="bash-kiegészítés a park parancshoz"
    [idozitok]="systemd időzítők: őrszem (5p), napi egészség-jelentés, bootoláskori mérés, ARP-segéd"
    [koszonto]="belépési üzenőfal (/etc/profile.d)"
    [ertesites]="értesítési csatornák (ntfy / Discord / e-mail)"
)

sugo() {
    cat <<SUGO
${C_FEHER}szerverpark – szkriptek telepítő${C_RESET}

A park kezelő- és felügyeleti szkripteket teszi fel, és letölti a
működésükhöz kellő csomagokat. A teljes self-hosting telepítése: ./telepito.sh

${C_ZOLD}Használat${C_RESET}
  sudo ./skriptek-telepito.sh                 varázsló: letölt + beállít mindent
  sudo ./skriptek-telepito.sh --proba         SEMMIT nem módosít, csak megmutatja
  sudo ./skriptek-telepito.sh --auto          kérdés nélkül, alapértékekkel
  sudo ./skriptek-telepito.sh --csak szkriptek,idozitok   csak a felsorolt lépések
  sudo ./skriptek-telepito.sh --no-docker     a Docker telepítésének kihagyása

${C_ZOLD}Műveletek${C_RESET}
  --frissit        csak a szkriptek újratelepítése (frissítés a repóból)
  --allapot        mi van telepítve (szkriptek, időzítők, verziók)
  --onteszt        a felrakott szkriptek próbafuttatása
  --eltavolit      a telepített szkriptek, időzítők, üzenőfal eltávolítása
  --lista          a telepítési lépések listája
  -h, --help       ez a súgó
SUGO
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --proba|--dry-run) PROBA=1; shift ;;
        --auto)            AUTO=1; shift ;;
        --csak)            CSAK="${2:-}"; shift 2 ;;
        --no-docker)       NO_DOCKER=1; shift ;;
        --frissit)         AKCIO="frissit"; shift ;;
        --allapot|--status) AKCIO="allapot"; shift ;;
        --onteszt)         AKCIO="onteszt"; shift ;;
        --eltavolit|--uninstall) AKCIO="eltavolit"; shift ;;
        --lista)
            printf '\nTelepítési lépések:\n\n'
            for l in "${LEPESEK[@]}"; do printf '  %-12s %s\n' "$l" "${LEPES_LEIRAS[$l]}"; done
            printf '\n'; exit 0 ;;
        -h|--help) sugo; exit 0 ;;
        *) hiba "Ismeretlen kapcsoló: $1"; sugo; exit 1 ;;
    esac
done

export PROBA AUTO

fusson() {
    local nev="$1"
    [[ -z "$CSAK" ]] && return 0
    [[ ",${CSAK}," == *",${nev},"* ]]
}

env_set() {
    local kulcs="$1" ertek="$2" fajl="${PARK_DIR}/.env"
    [[ "$PROBA" == "1" ]] && { info "[próba] .env: ${kulcs}=…"; return 0; }
    mkdir -p "$(dirname "$fajl")"; touch "$fajl"; chmod 600 "$fajl"
    if grep -q "^${kulcs}=" "$fajl" 2>/dev/null; then
        sed -i "s#^${kulcs}=.*#${kulcs}=${ertek}#" "$fajl"
    else
        printf '%s=%s\n' "$kulcs" "$ertek" >>"$fajl"
    fi
}

lepes_fuggosegek() {
    cim "Csomagok letöltése"
    if ! rendszer_felismer; then
        figy "ismeretlen disztribúció – a csomagtelepítést kihagyom"
        return 0
    fi
    info "rendszer: ${OS_NEV} (${OS_CSALAD})"
    csomaglista_frissit
    csomag_telepit curl ca-certificates jq git restic
    ok "alapcsomagok fent"

    if [[ "$NO_DOCKER" == "1" ]]; then
        kihagy "Docker (--no-docker)"
    elif van_parancs docker; then
        kihagy "Docker (már fent)"
    else
        info "Docker Engine + Compose telepítése…"
        docker_engine_telepit && ok "Docker telepítve" || figy "a Docker telepítése nem sikerült"
        van_parancs systemctl && fut systemctl enable --now docker >/dev/null 2>&1 || true
    fi

    local u="${SMB_FELHASZNALO:-${SUDO_USER:-}}"
    if [[ -n "$u" ]] && getent group docker >/dev/null 2>&1; then
        fut usermod -aG docker "$u" 2>/dev/null && info "a(z) ${u} felhasználó a docker csoportba került" || true
    fi
}

lepes_konyvtar() {
    cim "Könyvtárváz és .env"
    local d
    for d in "$PARK_DIR" "$PARK_DIR/stackek" "$PARK_DIR/web" "$ADAT_DIR" "$PARK_DIR/mentes"; do
        konyvtar "$d"
    done
    if [[ "$PROBA" != "1" ]]; then
        touch "${PARK_DIR}/.env"; chmod 600 "${PARK_DIR}/.env"
    fi
    titok RESTIC_JELSZO 40 >/dev/null
    env_beallit MENTES_CEL "${MENTES_CEL:-${PARK_DIR}/mentes/repo}"
    ok ".env kész (a titkok generálva): ${PARK_DIR}/.env"

    if [[ ! -f "$CONF_FAJL" && -f "${TELEPITO_DIR}/szerver.conf.pelda" ]]; then
        if [[ "$PROBA" == "1" ]]; then
            info "[próba] ${CONF_FAJL} létrehozása a mintából"
        else
            install -m 0644 "${TELEPITO_DIR}/szerver.conf.pelda" "$CONF_FAJL"
            ok "beállításfájl létrehozva: ${CONF_FAJL}"
        fi
    else
        kihagy "beállításfájl (${CONF_FAJL} már megvan)"
    fi
}

lepes_szkriptek() {
    cim "Szkriptek telepítése"
    local s
    for s in "${SZKRIPTEK[@]}"; do
        if [[ -f "${TELEPITO_DIR}/skriptek/${s}" ]]; then
            if [[ "$PROBA" == "1" ]]; then
                info "[próba] install ${s} -> /usr/local/bin/${s}"
            else
                install -m 0755 "${TELEPITO_DIR}/skriptek/${s}" "/usr/local/bin/${s}"
            fi
        else
            figy "hiányzó szkript a repóban: ${s}"
        fi
    done
    ok "szkriptek telepítve (súgó: park)"
    szolgaltatas_jegyzes "park" "park súgó" "kezelő + felügyelet egy parancsban"
}

lepes_kiegeszites() {
    cim "Bash-kiegészítés"
    cat <<'COMP' | fajlt_ir /etc/bash_completion.d/park
_park() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    local parancsok="allapot indit leallit ujra naplo frissit takarit oldal tavoli tars mentes mentesek jelszavak koszonto egeszseg orzo ertesit ai-katalogus ai-modellek ai-modell ai-torol ai-kulcs lab vm sugo"
    local stackek=""
    [[ -d /srv/szerverpark/stackek ]] && stackek="$(find /srv/szerverpark/stackek -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null)"
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$parancsok" -- "$cur")); return
    fi
    case "$prev" in
        indit|leallit|ujra|naplo|frissit) COMPREPLY=($(compgen -W "$stackek" -- "$cur")) ;;
        egeszseg) COMPREPLY=($(compgen -W "--json --csendes --ertesit" -- "$cur")) ;;
        orzo)     COMPREPLY=($(compgen -W "--szaraz --nema --telepit-idozito" -- "$cur")) ;;
    esac
}
complete -F _park park
COMP
    ok "park bash-kiegészítés telepítve (új shell / source ~/.bashrc után él)"
}

lepes_idozitok() {
    cim "Systemd időzítők"
    if ! van_parancs systemctl; then
        figy "nincs systemd – az időzítőket kihagyom"
        return 0
    fi
    if [[ "$PROBA" == "1" ]]; then
        info "[próba] park-orzo.timer (5 percenként)"
    else
        park-orzo --telepit-idozito >/dev/null 2>&1 && ok "őrszem időzítő bekapcsolva (park-orzo.timer)" \
            || figy "az őrszem időzítő beállítása nem sikerült"
    fi

    if [[ "$PROBA" == "1" ]]; then
        info "[próba] park-tarolo udev-automatika"
    else
        park-tarolo --telepit >/dev/null 2>&1 && ok "tároló-automatika bekapcsolva (bedugott lemez magától felcsatolódik)" \
            || figy "a tároló-automatika beállítása nem sikerült"
    fi

    if [[ "$PROBA" == "1" ]]; then
        info "[próba] park-halozat: vezetékes elsőbbség + IP-követés"
    else
        park-halozat --telepit >/dev/null 2>&1 && ok "hálózati automatika bekapcsolva (kábelre vált, a nevek követik az IP-t)" \
            || figy "a hálózati automatika beállítása nem sikerült"
    fi

    cat <<'SVC' | fajlt_ir /etc/systemd/system/park-egeszseg.service
[Unit]
Description=Szerverpark napi egészség-jelentés
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/park-egeszseg --csendes --ertesit
SuccessExitStatus=1 2
SVC
    cat <<'TMR' | fajlt_ir /etc/systemd/system/park-egeszseg.timer
[Unit]
Description=Szerverpark napi egészség-jelentés időzítő

[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true

[Install]
WantedBy=timers.target
TMR
    cat <<'SVC' | fajlt_ir /etc/systemd/system/park-speedtest-boot.service
[Unit]
Description=Szerverpark: sebességmérés bekapcsolás után, ha régi az utolsó
After=docker.service time-sync.target network-online.target
Wants=time-sync.target network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/park-speedtest-boot
SVC
    cat <<'TMR' | fajlt_ir /etc/systemd/system/park-speedtest-boot.timer
[Unit]
Description=Szerverpark: sebességmérés 10 perccel a bekapcsolás után

[Timer]
OnBootSec=10min

[Install]
WantedBy=timers.target
TMR
    cat <<'SVC' | fajlt_ir /etc/systemd/system/park-arp-segito.service
[Unit]
Description=park-arp-segito: a router elnyelt ARP-válaszainak pótlása wifis klienseknek
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/park-arp-segito
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_RAW
DynamicUser=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
SVC
    if [[ "$PROBA" != "1" ]]; then
        systemctl daemon-reload
        if van_parancs python3; then
            systemctl enable park-arp-segito.service >/dev/null 2>&1 \
                && systemctl restart park-arp-segito.service >/dev/null 2>&1 \
                && ok "ARP-segéd bekapcsolva (wifis gépek is megtalálják a szervert)" \
                || figy "az ARP-segéd indítása nem sikerült (journalctl -u park-arp-segito)"
        else
            figy "nincs python3 – az ARP-segédet kihagyom"
        fi
        systemctl enable --now park-egeszseg.timer >/dev/null 2>&1 \
            && ok "napi egészség-jelentés bekapcsolva (08:00)" || true
        systemctl enable park-speedtest-boot.timer >/dev/null 2>&1 \
            && ok "bootoláskori sebességmérés bekapcsolva (10 perc után, ha 3 óránál régebbi az utolsó)" || true
    fi
}

lepes_koszonto() {
    cim "Belépési üzenőfal"
    cat <<'PROF' | fajlt_ir /etc/profile.d/00-park-koszonto.sh
case $- in *i*) ;; *) return 2>/dev/null || exit 0 ;; esac
[ -x /usr/local/bin/park-koszonto ] && /usr/local/bin/park-koszonto
PROF
    ok "üzenőfal beállítva (belépéskor megjelenik; kézzel: park koszonto)"
}

lepes_ertesites() {
    cim "Értesítési csatornák"
    if [[ "$AUTO" == "1" ]]; then
        kihagy "értesítés (--auto: hagyd üresen, később: park ertesit)"
        return 0
    fi
    info "Riasztás lefagyáskor / gondnál. Elég egyet megadni; üres = kihagy."
    local ntfy disc mail
    ntfy="$(kerdez "ntfy topic URL (pl. https://ntfy.sh/valami-titkos)" "")"
    disc="$(kerdez "Discord webhook URL" "")"
    mail="$(kerdez "értesítési e-mail cím" "")"
    [[ -n "$ntfy" ]] && env_set NTFY_URL "$ntfy"
    [[ -n "$disc" ]] && env_set DISCORD_WEBHOOK "$disc"
    [[ -n "$mail" ]] && env_set ERTESITO_EMAIL "$mail"
    if [[ -n "$ntfy$disc$mail" && "$PROBA" != "1" ]]; then
        ok "értesítés beállítva – teszt: park ertesit --teszt"
        van_parancs park-ertesito && park-ertesito --teszt >/dev/null 2>&1 || true
    else
        kihagy "értesítés (nem adtál meg csatornát)"
    fi
}

akcio_allapot() {
    printf '\n%sTelepített szkriptek%s\n' "$C_KEK" "$C_RESET"
    local s
    for s in "${SZKRIPTEK[@]}"; do
        if [[ -x "/usr/local/bin/${s}" ]]; then
            printf '  %s✔%s %-16s /usr/local/bin/%s\n' "$C_ZOLD" "$C_RESET" "$s" "$s"
        else
            printf '  %s•%s %-16s (nincs telepítve)\n' "$C_SZURKE" "$C_RESET" "$s"
        fi
    done
    printf '\n%sIdőzítők%s\n' "$C_KEK" "$C_RESET"
    local t
    for t in park-orzo.timer park-egeszseg.timer park-mentes.timer park-speedtest-boot.timer park-arp-segito.service; do
        if van_parancs systemctl && systemctl is-enabled "$t" >/dev/null 2>&1; then
            printf '  %s✔%s %-22s %s\n' "$C_ZOLD" "$C_RESET" "$t" "$(systemctl is-active "$t" 2>/dev/null)"
        else
            printf '  %s•%s %-22s (kikapcsolva)\n' "$C_SZURKE" "$C_RESET" "$t"
        fi
    done
    printf '\n%sEgyéb%s\n' "$C_KEK" "$C_RESET"
    [[ -f /etc/profile.d/00-park-koszonto.sh ]] && printf '  %s✔%s belépési üzenőfal\n' "$C_ZOLD" "$C_RESET" || printf '  %s•%s belépési üzenőfal\n' "$C_SZURKE" "$C_RESET"
    [[ -f /etc/bash_completion.d/park ]] && printf '  %s✔%s bash-kiegészítés\n' "$C_ZOLD" "$C_RESET" || printf '  %s•%s bash-kiegészítés\n' "$C_SZURKE" "$C_RESET"
    [[ -f "${PARK_DIR}/.env" ]] && printf '  %s✔%s .env (%s)\n' "$C_ZOLD" "$C_RESET" "${PARK_DIR}/.env" || printf '  %s•%s .env\n' "$C_SZURKE" "$C_RESET"
    printf '\n'
}

akcio_onteszt() {
    cim "Önteszt"
    local s hibak=0
    for s in "${SZKRIPTEK[@]}"; do
        if [[ -x "/usr/local/bin/${s}" ]]; then
            if bash -n "/usr/local/bin/${s}" 2>/dev/null; then ok "$s – szintaxis rendben"
            else hiba "$s – szintaxishiba"; hibak=$((hibak+1)); fi
        else
            figy "$s – nincs telepítve"
        fi
    done
    if van_parancs park-egeszseg; then
        info "park-egeszseg próbafuttatás:"
        park-egeszseg || true
    fi
    (( hibak == 0 )) && ok "önteszt kész" || vege_hibaval "az önteszt ${hibak} hibát talált"
}

akcio_eltavolit() {
    cim "Eltávolítás"
    root_kell
    local s
    for s in "${SZKRIPTEK[@]}"; do fut rm -f "/usr/local/bin/${s}"; done
    if van_parancs systemctl; then
        local t
        for t in park-orzo park-egeszseg park-speedtest-boot; do
            fut systemctl disable --now "${t}.timer" >/dev/null 2>&1 || true
            fut rm -f "/etc/systemd/system/${t}.timer" "/etc/systemd/system/${t}.service"
        done
        fut systemctl disable --now park-arp-segito.service >/dev/null 2>&1 || true
        fut rm -f /etc/systemd/system/park-arp-segito.service
        fut systemctl daemon-reload
    fi
    fut rm -f /etc/profile.d/00-park-koszonto.sh /etc/bash_completion.d/park
    ok "a szkriptek, időzítők és az üzenőfal eltávolítva"
    figy "az adatok és a .env megmaradtak itt: ${PARK_DIR}"
}

telepit() {
    [[ "$PROBA" == "1" ]] && figy "PRÓBA mód – semmi nem módosul" || root_kell
    local l
    for l in "${LEPESEK[@]}"; do
        fusson "$l" || continue
        "lepes_${l}"
    done
    printf '\n%s╭─ Kész%s\n' "$C_KEK" "$C_RESET"
    if (( ${#OSSZEFOGLALO[@]} )); then
        local sor
        for sor in "${OSSZEFOGLALO[@]}"; do
            IFS='|' read -r nev cim megj <<<"$sor"
            printf '%s│%s  %s%-16s%s %s  %s%s%s\n' "$C_KEK" "$C_RESET" "$C_ZOLD" "$nev" "$C_RESET" "$cim" "$C_SZURKE" "$megj" "$C_RESET"
        done
    fi
    printf '%s│%s  Következő: %spark koszonto%s · %spark egeszseg%s · %spark súgó%s\n' \
        "$C_KEK" "$C_RESET" "$C_ZOLD" "$C_RESET" "$C_ZOLD" "$C_RESET" "$C_ZOLD" "$C_RESET"
    printf '%s╰─%s\n\n' "$C_KEK" "$C_RESET"
}

case "$AKCIO" in
    telepit)   telepit ;;
    frissit)   root_kell; lepes_szkriptek; lepes_kiegeszites; ok "frissítés kész" ;;
    allapot)   akcio_allapot ;;
    onteszt)   akcio_onteszt ;;
    eltavolit) akcio_eltavolit ;;
esac
