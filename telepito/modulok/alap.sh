#!/usr/bin/env bash
# Modul: rendszer-alapok
# Csomagok, időzóna, tűzfal, automatikus biztonsági frissítés, könyvtárak.
# Disztribúció-független: apt / dnf / zypper / pacman.

cim "Rendszer-alapok (${OS_NEV})"

info "csomaglista frissítése…"
csomaglista_frissit

mapfile -t CSOMAGOK < <(alap_csomaglista)
info "alapcsomagok telepítése (${#CSOMAGOK[@]} db)…"
csomag_telepit "${CSOMAGOK[@]}" || figy "néhány csomag nem települt – nézd meg a naplót"
ok "alapcsomagok fent"

# --- időzóna -----------------------------------------------------------------
if [[ "$(timedatectl show -p Timezone --value 2>/dev/null)" == "$IDOZONA" ]]; then
    kihagy "időzóna: $IDOZONA"
else
    fut timedatectl set-timezone "$IDOZONA" && ok "időzóna: $IDOZONA"
fi

# --- automatikus biztonsági frissítés ---------------------------------------
auto_frissites_be

# --- tűzfal ------------------------------------------------------------------
tuzfal_alap
tuzfal_port "$SSH_PORT" tcp 'SSH'
tuzfal_port 80  tcp 'HTTP (Caddy)'
tuzfal_port 443 tcp 'HTTPS (Caddy)'
NYITOTT="SSH(${SSH_PORT}), 80, 443"
if [[ -n "${TUZFAL_EXTRA:-}" ]]; then
    for BEJEGYZES in ${TUZFAL_EXTRA//,/ }; do
        E_PORT="${BEJEGYZES%%/*}"
        E_PROTO="${BEJEGYZES##*/}"
        [[ "$E_PROTO" == "$BEJEGYZES" ]] && E_PROTO=tcp
        tuzfal_port "$E_PORT" "$E_PROTO" 'TUZFAL_EXTRA'
        NYITOTT="${NYITOTT}, ${E_PORT}/${E_PROTO}"
    done
fi
# A Tailscale-en érkező forgalom mehet: enélkül egy szigorú alap-szabály
# kizárná a távoli elérést (a tailscaled maga is szűr).
if [[ -d /sys/class/net/tailscale0 ]]; then
    tuzfal_interfeszrol tailscale0 "Tailscale"
    tuzfal_port 41641 udp 'Tailscale WireGuard'
    NYITOTT="${NYITOTT}, tailscale0"
fi
tuzfal_ervenyesit
ok "tűzfal: ${NYITOTT} nyitva, minden más zárva"

# Kézzel írt nftables tűzfal az ufw MELLETT: a kettő egymásra hat. A régi
# /etc/nftables.conf-ok jellemzően "flush ruleset"-tel kezdődnek, ami bootkor
# az ufw és a Docker szabályait is kimoshatja, a "policy drop" pedig elvágja a
# konténerek és a gazdagép közti forgalmat. Csak jelezzük – nem nyúlunk hozzá.
if [[ "$TUZFAL" == "ufw" ]] && systemctl is-enabled nftables >/dev/null 2>&1; then
    figy "Az nftables.service is fut az ufw mellett – a kettő ütközik."
    figy "Nézd meg a /etc/nftables.conf-ot: ha 'flush ruleset' van benne, bootkor"
    figy "kimoshatja az ufw és a Docker szabályait. Javasolt: systemctl disable nftables"
fi

# --- fail2ban ----------------------------------------------------------------
cat <<F2B | fajlt_ir /etc/fail2ban/jail.d/szerverpark.conf
# SSH-védelem: 5 hibás próbálkozás után 1 óra tiltás.
[sshd]
enabled  = true
port     = ${SSH_PORT}
maxretry = 5
findtime = 10m
bantime  = 1h
F2B
szolgaltatas_be fail2ban
ok "fail2ban véd az SSH brute-force ellen"

# --- hálózaton látszódjunk (mDNS) -------------------------------------------
szolgaltatas_be avahi-daemon 2>/dev/null || szolgaltatas_be avahi-daemon.service

# --- könyvtárszerkezet -------------------------------------------------------
konyvtar "$ADAT_DIR"
konyvtar "$ADAT_DIR/megosztas"
konyvtar "$ADAT_DIR/nextcloud"
konyvtar "$ADAT_DIR/ai"
konyvtar "$PARK_DIR/web"
konyvtar "$PARK_DIR/mentes"
ok "könyvtárszerkezet kész ($ADAT_DIR)"

# --- lemez-figyelmeztetés ----------------------------------------------------
SZABAD_GB=$( { df -BG --output=avail "$ADAT_DIR" 2>/dev/null || true; } | tail -1 | tr -dc '0-9' || true)
if [[ -n "$SZABAD_GB" ]] && (( SZABAD_GB < 20 )); then
    figy "Csak ${SZABAD_GB} GB szabad hely az adatoknak – tegyél be nagyobb lemezt."
fi

# --- zram kis memóriájú gépen ------------------------------------------------
# 8-12 GB RAM-nál a tömörített RAM-swap sokat segít: a ritkán használt
# konténer-memória tömörítve kerül félre, lemez-swap helyett.
RAM_GB_ALAP=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
# Van már zram-swap? A Raspberry Pi OS pl. sajátot hoz (rpi-swap: zram +
# írás-visszatöltés fájlba). Két zram-kezelő ugyanazon az eszközön veszekszik:
# az egyik elhasal, és a végén swap nélkül marad a gép. Ilyenkor nem nyúlunk bele.
VAN_ZRAM=0
if grep -q '^/dev/zram' /proc/swaps 2>/dev/null || [[ -e /etc/rpi/swap.conf ]]; then
    VAN_ZRAM=1
fi
if (( VAN_ZRAM )); then
    kihagy "zram: a rendszer sajátja kezeli (nem nyúlok hozzá)"
elif (( RAM_GB_ALAP <= 12 )); then
    case "$OS_CSALAD" in
        debian) csomag_telepit zram-tools
                cat <<'ZRAM' | fajlt_ir /etc/default/zramswap
# A szerverpark telepítő állította be (kis memóriájú gép).
ALGO=zstd
PERCENT=50
PRIORITY=100
ZRAM
                szolgaltatas_be zramswap ;;
        fedora) csomag_telepit zram-generator-defaults ;;
        arch|suse) csomag_telepit zram-generator 2>/dev/null || true ;;
    esac
    ok "zram bekapcsolva (${RAM_GB_ALAP} GB RAM – tömörített RAM-swap)"
    figy "8 GB RAM-nál az AI és a VM-ek NE fussanak egyszerre – lásd README."
fi

# --- megbízhatóság: napló, watchdog, óra ------------------------------------
# A napló maradjon meg újraindítás után is: különben egy lefagyás után nincs
# mit megnézni. A méretet lekötjük, hogy ne rágja a kártyát/lemezt.
cat <<'JD' | fajlt_ir /etc/systemd/journald.conf.d/50-park.conf
# A szerverpark telepítő írta.
[Journal]
Storage=persistent
SystemMaxUse=200M
SystemMaxFileSize=20M
JD
[[ "$PROBA" != "1" ]] && { systemctl restart systemd-journald 2>/dev/null || true; journalctl --flush 2>/dev/null || true; }
ok "tartós rendszernapló (max 200 MB)"

# Hardveres watchdog: ha a kernel megáll, a gép magától újraindul.
if [[ -e /dev/watchdog ]]; then
    cat <<'WD' | fajlt_ir /etc/systemd/system.conf.d/50-park-watchdog.conf
# A szerverpark telepítő írta. A név 50-nel kezdődik, hogy a Raspberry Pi OS
# saját 40-rpi-enable-watchdog.conf-ját felülírja.
[Manager]
RuntimeWatchdogSec=14s
RebootWatchdogSec=2min
WD
    [[ "$PROBA" != "1" ]] && systemctl daemon-reload 2>/dev/null || true
    ok "hardveres watchdog: 14 s (lefagyás után magától újraindul)"
fi

# Óra nélküli gépek (Raspberry Pi): bootkor a régi időről indulnak, ezért a
# konténerek és a naplók hamis időt kapnak. A fake-hwclock visszatölti a
# legutóbb mentett időt, a time-wait-sync pedig megvárja az NTP-t.
if [[ ! -e /dev/rtc0 && ! -e /dev/rtc ]]; then
    case "$OS_CSALAD" in debian) csomag_telepit fake-hwclock ;; esac
    if [[ "$PROBA" != "1" ]]; then
        for u in fake-hwclock-load.service fake-hwclock-save.service fake-hwclock-save.timer; do
            systemctl enable "$u" >/dev/null 2>&1 || true
        done
        systemctl enable systemd-time-wait-sync.service >/dev/null 2>&1 || true
    fi
    # Az eredeti unit TimeoutStartSec=infinity-vel vár az NTP-re, és közben a
    # sysinit.target-et blokkolja: ha bootkor nincs net (pl. a router lassabban
    # indul), a gép ott ragadna. Két perc után lépjen tovább.
    cat <<'TWS' | fajlt_ir /etc/systemd/system/systemd-time-wait-sync.service.d/50-park.conf
# A szerverpark telepítő írta.
[Service]
TimeoutStartSec=120
TWS
    cat <<'DCK' | fajlt_ir /etc/systemd/system/docker.service.d/50-park-ido.conf
# A szerverpark telepítő írta.
[Unit]
After=time-sync.target
Wants=time-sync.target
DCK
    [[ "$PROBA" != "1" ]] && systemctl daemon-reload 2>/dev/null || true
    ok "óra nélküli gép: mentett idő visszatöltése + várakozás az NTP-re"
fi

# --- smartd csak akkor, ha van mit figyelnie -------------------------------
# SD-kártyán / pendrive-on nincs SMART: a smartd 17-tel kilép, és a unit örökre
# "failed" marad – ami elnyomja a VALÓDI hibákat a systemctl --failed listában.
if van_parancs smartctl && [[ "$PROBA" != "1" ]]; then
    if [[ -z "$(smartctl --scan 2>/dev/null)" ]]; then
        systemctl disable --now smartmontools >/dev/null 2>&1 || true
        info "nincs SMART-képes lemez – a smartd leállítva (lemez betétele után: systemctl enable --now smartmontools)"
    fi
fi

# --- SELinux (Fedora/RHEL/openSUSE) -----------------------------------------
if van_parancs getenforce && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
    info "SELinux bekapcsolva – a konténer-kötések :z jelöléssel mennek."
    export SELINUX_AKTIV=1
fi

# --- 'park' kezelő parancs ---------------------------------------------------
if [[ "$PROBA" == "1" ]]; then
    info "[próba] /usr/local/bin/park telepítése"
    info "[próba] park-egeszseg, park-ertesito, park-orzo, park-koszonto, park-figyelo telepítése"
    info "[próba] belépési üzenőfal: /etc/profile.d/00-park-koszonto.sh"
else
    install -m 0755 "${TELEPITO_DIR}/skriptek/park" /usr/local/bin/park
    for s in park-egeszseg park-ertesito park-orzo park-koszonto park-figyelo; do
        [[ -f "${TELEPITO_DIR}/skriptek/${s}" ]] && \
            install -m 0755 "${TELEPITO_DIR}/skriptek/${s}" "/usr/local/bin/${s}"
    done
    ok "'park' + segéd-szkriptek telepítve (súgó: park)"
    if van_parancs systemctl; then
        park-orzo --telepit-idozito >/dev/null 2>&1 && ok "őrszem időzítő bekapcsolva (park-orzo)" || true
    fi
    cat >/etc/profile.d/00-park-koszonto.sh <<'PROF'
case $- in *i*) ;; *) return 2>/dev/null || exit 0 ;; esac
[ -x /usr/local/bin/park-koszonto ] && /usr/local/bin/park-koszonto
PROF
    ok "belépési üzenőfal beállítva (park koszonto)"
fi

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
