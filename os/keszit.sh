#!/usr/bin/env bash
set -euo pipefail

PROJEKT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJEKT"

DISZTRO="trixie"
ARCH="amd64"
GEPNEV="szerverpark"
SZERVER=1
PROBA=0
TESZT_UEFI=0
SSH_KULCS_FAJL=""
AKCIO="epit"
TOVABBI=()

if [[ -t 1 ]]; then
    Z=$'\e[32m'; S=$'\e[33m'; P=$'\e[31m'; K=$'\e[36m'; N=$'\e[0m'; G=$'\e[90m'; F=$'\e[1;37m'
else Z=""; S=""; P=""; K=""; N=""; G=""; F=""; fi
cim()  { printf '\n%s╭─ %s%s\n' "$K" "$*" "$N"; }
info() { printf '%s│%s  %s\n' "$K" "$N" "$*"; }
ok()   { printf '%s│%s  %s✔%s %s\n' "$K" "$N" "$Z" "$N" "$*"; }
figy() { printf '%s│%s  %s!%s %s\n' "$K" "$N" "$S" "$N" "$*"; }
hiba() { printf '%s│%s  %s✘ %s%s\n' "$K" "$N" "$P" "$*" "$N" >&2; }
vege() { printf '%s╰─%s\n' "$K" "$N"; }
van()  { command -v "$1" >/dev/null 2>&1; }
fut()  { if (( PROBA )); then printf '%s│%s  %s[próba]%s %s\n' "$K" "$N" "$G" "$N" "$*"; else "$@"; fi; }

sugo() {
    cat <<SUGO
${F}Botirocky – ISO-készítő${N}

Saját, Debian-alapú szerver-disztribúció: bootoláskor élő MENTŐ/recovery mód
(a mento eszközkészlettel), vagy a szerver AUTOMATA telepítése (szerverpark).
Motor: Debian live-build. Rendes hibrid ISO (BIOS + UEFI).

${Z}Használat${N}
  sudo ./keszit.sh                 letölt + megépíti az ISO-t
  sudo ./keszit.sh --proba         csak a terv + függőség-ellenőrzés (root sem kell)
  sudo ./keszit.sh --disztro bookworm | trixie     Debian-kiadás (alap: trixie)
  sudo ./keszit.sh --nev pi-park    a rendszer hostneve (alap: szerverpark)
  sudo ./keszit.sh --nincs-szerver  ne süsse bele a szerverpark stacket (csak mentő)
  ./keszit.sh --ssh-kulcs <fájl>   ez a nyilvános kulcs léphet be rootként SSH-n
                                   (alap: ~/.ssh/id_ed25519.pub, ha van)
  ./keszit.sh --docker             építés privilegizált Debian-konténerben (bármilyen Linuxon)
  ./keszit.sh --teszt [--uefi]     a kész ISO bootolása QEMU-ban (alap: BIOS)
  sudo ./keszit.sh --tiszta        a build-melléktermékek törlése (lb clean)
  -h, --help
SUGO
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --proba|--dry-run) PROBA=1; shift ;;
        --disztro) DISZTRO="${2:?}"; TOVABBI+=(--disztro "$2"); shift 2 ;;
        --nev)     GEPNEV="${2:?}"; TOVABBI+=(--nev "$2"); shift 2 ;;
        --nincs-szerver) SZERVER=0; TOVABBI+=(--nincs-szerver); shift ;;
        --teszt)   AKCIO="teszt"; shift ;;
        --uefi)    TESZT_UEFI=1; shift ;;
        --ssh-kulcs) SSH_KULCS_FAJL="${2:?}"; shift 2 ;;
        --docker)  AKCIO="docker"; shift ;;
        --tiszta)  AKCIO="tiszta"; shift ;;
        -h|--help) sugo; exit 0 ;;
        *) hiba "ismeretlen kapcsoló: $1"; sugo; exit 1 ;;
    esac
done

KIMENET="botirocky-${DISZTRO}-${ARCH}.iso"

root_kell() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { hiba "ehhez root kell (sudo)"; exit 1; }; }

fuggosegek() {
    cim "Függőségek"
    if van lb; then ok "live-build már fent"; else
        info "live-build telepítése…"
        if van apt-get; then
            fut bash -c "DEBIAN_FRONTEND=noninteractive apt-get update -qq"
            fut bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq live-build ca-certificates xorriso librsvg2-bin fonts-dejavu-core"
        else
            figy "nem Debian a build-gép – tedd fel kézzel: live-build xorriso"
        fi
    fi
    van lb || figy "az lb (live-build) hiányzik – csak --proba fut le build nélkül"
    vege
}

elokeszit() {
    cim "Konfiguráció összeállítása"
    mkdir -p auto config/package-lists \
             config/includes.chroot/usr/local/bin \
             config/includes.chroot/etc \
             config/includes.chroot/etc/systemd/system \
             config/hooks/normal \
             config/includes.installer \
             config/includes.chroot/etc/ssh/sshd_config.d \
             config/includes.chroot/etc/systemd/system

    cat > auto/config <<CFG
#!/bin/sh
set -e
lb config noauto \\
  --distribution ${DISZTRO} \\
  --architectures ${ARCH} \\
  --archive-areas "main contrib non-free non-free-firmware" \\
  --binary-images iso-hybrid \\
  --debian-installer live \\
  --debian-installer-gui false \\
  --memtest memtest86+ \\
  --bootappend-live "boot=live components hostname=${GEPNEV} keyboard-layouts=hu locales=hu_HU.UTF-8" \\
  --iso-application "Botirocky" \\
  --iso-publisher "Botirocky" \\
  --iso-volume "BOTIROCKY" \\
  "\${@}"
CFG
    chmod +x auto/config
    ok "auto/config kész (${DISZTRO}, ${ARCH}, hibrid ISO)"

    cat > config/package-lists/mento.list.chroot <<'PKG'
parted gdisk
e2fsprogs dosfstools xfsprogs btrfs-progs ntfs-3g exfatprogs
cryptsetup lvm2 mdadm
smartmontools nvme-cli gddrescue testdisk
rsync restic curl wget git ca-certificates
openssh-client openssh-server
whiptail dialog less nano vim-tiny htop tmux fastfetch kitty-terminfo
pciutils usbutils lshw memtester
iproute2 iputils-ping dnsutils isc-dhcp-client network-manager
grub-common console-setup keyboard-configuration
PKG
    ok "csomaglista (mentő + rendszer eszközök)"

    install -m 0755 "${PROJEKT}/rendszer/mento" config/includes.chroot/usr/local/bin/mento
    ok "mento eszközkészlet bemásolva"

    install -D -m 0644 "${PROJEKT}/rendszer/fastfetch/logo.txt" config/includes.chroot/usr/share/botirocky/fastfetch-logo.txt
    install -D -m 0644 "${PROJEKT}/rendszer/fastfetch/config.jsonc" config/includes.chroot/etc/xdg/fastfetch/config.jsonc
    install -D -m 0644 "${PROJEKT}/rendszer/fastfetch/botirocky-fastfetch.sh" config/includes.chroot/etc/profile.d/zz-botirocky-fastfetch.sh
    ok "fastfetch téma (Botirocky logó, belépéskor indul)"

    cat > config/includes.chroot/etc/motd <<MOTD

  Botirocky  –  mentő / recovery rendszer

  Eszközök:   mento            (interaktív menü)
              mento rendszer   mento lemezek   mento halozat
  Telepítés:  szerverpark-telepit    (a szerver kiépítése erre a gépre)

MOTD
    printf 'Botirocky \\n \\l\n\n' > config/includes.chroot/etc/issue

    if (( SZERVER )) && [[ -d "${PROJEKT}/../szerverpark" ]]; then
        mkdir -p config/includes.chroot/opt
        rm -rf config/includes.chroot/opt/szerverpark
        mkdir -p config/includes.chroot/opt/szerverpark
        tar -C "${PROJEKT}/../szerverpark" --exclude-vcs --exclude-vcs-ignores --exclude=.env -cf - . \
            | tar -C config/includes.chroot/opt/szerverpark -xf -
        cat > config/includes.chroot/usr/local/bin/szerverpark-telepit <<'WRAP'
#!/usr/bin/env bash
exec /opt/szerverpark/telepito.sh "$@"
WRAP
        chmod +x config/includes.chroot/usr/local/bin/szerverpark-telepit
        ok "szerverpark stack beépítve (/opt/szerverpark + szerverpark-telepit)"
    else
        figy "szerverpark stack kihagyva (--nincs-szerver vagy nincs mellette a repó)"
    fi

    cat > config/includes.chroot/etc/ssh/sshd_config.d/50-botirocky.conf <<'SSHD'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
SSHD
    cat > config/includes.chroot/etc/systemd/system/botirocky-ssh-kulcsok.service <<'UNIT'
[Unit]
Description=Botirocky: egyedi SSH host-kulcsok az első indításkor
Before=ssh.service ssh.socket
ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=ssh.service
UNIT
    ok "SSH: csak kulccsal, egyedi host-kulcsok, az élő rendszeren alapból KI"

    local kulcs="${SSH_KULCS_FAJL}"
    [[ -z $kulcs && -z ${SSH_KULCS:-} && -f "${HOME}/.ssh/id_ed25519.pub" ]] && kulcs="${HOME}/.ssh/id_ed25519.pub"
    mkdir -p config/includes.chroot/root/.ssh
    chmod 700 config/includes.chroot/root/.ssh
    if [[ -n $kulcs ]]; then
        cat "$kulcs" > config/includes.chroot/root/.ssh/authorized_keys
    elif [[ -n ${SSH_KULCS:-} ]]; then
        printf '%s\n' "$SSH_KULCS" > config/includes.chroot/root/.ssh/authorized_keys
    else
        rm -f config/includes.chroot/root/.ssh/authorized_keys
    fi
    if [[ -s config/includes.chroot/root/.ssh/authorized_keys ]]; then
        chmod 600 config/includes.chroot/root/.ssh/authorized_keys
        ok "root SSH-kulcs: $(awk '{print $NF}' config/includes.chroot/root/.ssh/authorized_keys | head -1)"
    else
        figy "nincs SSH-kulcs (--ssh-kulcs) – a telepített gépre SSH-n senki nem lép be"
    fi

    mkdir -p config/includes.chroot/usr/local/sbin
    cat > config/includes.chroot/usr/local/sbin/botirocky-telepites-utan <<UTAN
#!/bin/sh
set -e
rm -f /etc/ssh/ssh_host_*
systemctl enable botirocky-ssh-kulcsok.service ssh.service
if [ -f /etc/apt/sources.list ]; then
  sed -i 's/^deb cdrom:/# deb cdrom:/' /etc/apt/sources.list
fi
cat > /etc/apt/sources.list.d/debian.sources <<SRC
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${DISZTRO} ${DISZTRO}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${DISZTRO}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SRC
UTAN
    chmod +x config/includes.chroot/usr/local/sbin/botirocky-telepites-utan

    cat > config/hooks/normal/9000-branding.hook.chroot <<'HOOK'
#!/bin/sh
set -e
if [ ! -e /usr/lib/os-release.debian ]; then
  dpkg-divert --local --rename --divert /usr/lib/os-release.debian --add /usr/lib/os-release
fi
f=$(cut -d. -f1 /etc/debian_version)
sed -e 's/^PRETTY_NAME=.*/PRETTY_NAME="Botirocky (Debian '"$f"')"/' \
    -e 's/^NAME=.*/NAME="Botirocky"/' /usr/lib/os-release.debian > /usr/lib/os-release
grep -q '^VARIANT=' /usr/lib/os-release || echo 'VARIANT="Botirocky szerver"' >> /usr/lib/os-release
ln -sf ../usr/lib/os-release /etc/os-release
[ -e /etc/update-motd.d/10-uname ] && chmod -x /etc/update-motd.d/10-uname
rm -f /etc/ssh/ssh_host_*
systemctl enable botirocky-ssh-kulcsok.service
systemctl disable ssh.service ssh.socket 2>/dev/null || true
HOOK
    chmod +x config/hooks/normal/9000-branding.hook.chroot
    ok "branding hook"

    cp "${PROJEKT}/rendszer/splash.svg" config/botirocky-splash.svg
    cat > config/hooks/normal/9100-boot-menu.hook.binary <<'HOOK'
#!/bin/sh
set -e
verzio="$(. ../chroot/etc/os-release && echo "$VERSION_ID")"
kernel="$(ls ../chroot/boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)"
sed -e "s|@VERSION@|${verzio}|g" -e "s|@DISTRIBUTION@|$(. ../chroot/etc/os-release && echo "$VERSION_CODENAME")|g" \
    -e "s|@ARCHITECTURE@|$(dpkg --print-architecture)|g" -e "s|@LINUX_VERSIONS@|${kernel}|g" \
    -e "s|@YEAR@|$(date -u +%Y)|g" -e "s|@MONTH@|$(date -u +%m)|g" -e "s|@DAY@|$(date -u +%d)|g" \
    ../config/botirocky-splash.svg > /tmp/botirocky-splash.svg
if [ -d isolinux ]; then
  rsvg-convert --format png --width 640 --height 480 /tmp/botirocky-splash.svg -o isolinux/splash.png
  sed -i -e 's/Live system (\([a-z0-9]*\) fail-safe mode)/Mento rendszer (biztonsagos mod)/' \
         -e 's/\^Live system (\([a-z0-9]*\))/Botirocky ^mento \/ elo rendszer/' \
         -e 's/Start \^installer/Botirocky ^telepitese/' \
         -e 's/Start installer with \^speech synthesis/Telepites ^beszedszintezissel/' \
         -e 's/\^Advanced install options/^Halado telepitesi modok/; s/menu title Advanced install options/menu title Halado telepitesi modok/' \
         -e 's/\^Utilities/^Eszkozok/; s/menu title Utilities/menu title Eszkozok/' \
         -e 's/\^Back\.\./^Vissza/' \
         -e 's/menu title Boot menu/menu title Botirocky/' \
         -e 's/menu tabmsg Press ENTER to boot or TAB to edit a menu entry/menu tabmsg ENTER: inditas    TAB: szerkesztes/' \
         -e 's/#76a1d0ff/#e01f8f6e/g' \
         isolinux/*.cfg
fi
if [ -d boot/grub ]; then
  rsvg-convert --format png --width 800 --height 600 /tmp/botirocky-splash.svg -o boot/grub/splash.png
  sed -i -e 's/"Live system (\([a-z0-9]*\) fail-safe mode)"/"Mentő rendszer (biztonságos mód)"/' \
         -e 's/"Live system (\([a-z0-9]*\))"/"Botirocky mentő \/ élő rendszer"/' \
         -e "s/'Start installer'/'Botirocky telepítése'/" \
         -e "s/'Start installer with speech synthesis'/'Telepítés beszédszintézissel'/" \
         -e "s/'Advanced install options \.\.\.'/'Haladó telepítési módok ...'/" \
         -e "s/'Utilities\.\.\.'/'Eszközök ...'/" \
         -e "s/'Verify integrity of the boot medium'/'A boot-lemez ellenőrzése'/; s/\"Verify integrity of the boot medium\"/\"A boot-lemez ellenőrzése\"/" \
         -e "s/\"UEFI Firmware Settings\"/\"UEFI-beállítások\"/" \
         boot/grub/*.cfg
  sed -i -e 's/title-text: .*/title-text: ""/' \
         -e 's/text = "@KEYMAP_SHORT@"/text = "enter: indítás    e: szerkesztés    c: parancssor"/' \
         -e 's/selected_item_color= "#ffffff"/selected_item_color= "#4fd1a5"/' \
         boot/grub/live-theme/theme.txt
fi
rm -f /tmp/botirocky-splash.svg
HOOK
    chmod +x config/hooks/normal/9100-boot-menu.hook.binary
    ok "boot-menü: Botirocky splash + magyar menüpontok"

    cat > config/includes.installer/preseed.cfg <<PRE
d-i debian-installer/locale string hu_HU.UTF-8
d-i debian-installer/language string hu
d-i debian-installer/country string HU
d-i keyboard-configuration/xkb-keymap select hu
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string ${GEPNEV}
d-i netcfg/get_domain string lan
d-i netcfg/hostname string ${GEPNEV}
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i apt-setup/use_mirror boolean true
d-i apt-setup/non-free-firmware boolean true
d-i apt-setup/contrib boolean true
d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true
d-i time/zone string Europe/Budapest
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/choose_label select gpt
d-i partman-partitioning/default_label string gpt
d-i partman-efi/non_efi_system boolean true
d-i partman/choose_partition select finish
d-i partman-md/device_remove_md boolean false
d-i partman-lvm/device_remove_lvm boolean false
d-i pkgsel/run_tasksel boolean false
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default
d-i preseed/late_command string in-target /usr/local/sbin/botirocky-telepites-utan
d-i finish-install/reboot_in_progress note
PRE
    ok "preseed (automata telepítéshez)"
    vege
}

epit() {
    (( PROBA )) || root_kell
    fuggosegek
    if (( PROBA )); then
        cim "Terv (semmit nem módosít)"
        info "alap:     Debian ${DISZTRO} / ${ARCH}, hibrid ISO (BIOS + UEFI), hostname=${GEPNEV}"
        info "csomagok: parted, e2fsprogs, xfsprogs, btrfs-progs, smartmontools, gddrescue,"
        info "          testdisk, cryptsetup, lvm2, mdadm, restic, rsync, whiptail, network-manager…"
        info "payload:  /usr/local/bin/mento (mentőkészlet)"
        (( SZERVER )) && info "payload:  /opt/szerverpark + szerverpark-telepit (automata szerver-telepítés)" \
                       || info "payload:  szerver stack kihagyva (--nincs-szerver)"
        info "preseed:  Debian-telepítés (hu, Europe/Budapest); a lemezt és a root jelszót megkérdezi"
        info "ssh:      élő rendszeren KI (mento ssh be), telepítve csak kulccsal"
        info "kimenet:  ${KIMENET}   (lb build: több GB letöltés, ~15-40 perc)"
        vege; return 0
    fi
    elokeszit
    cim "ISO építése (lb build)"
    if ! van lb; then
        figy "live-build nélkül nem tudok építeni – telepítsd (Debian: apt install live-build), majd: sudo ./keszit.sh"
        vege; return 0
    fi
    fut lb clean
    local d
    for d in cache/bootstrap chroot; do
        if [[ -d $d ]] && [[ $(stat -c %u "$d") != 0 || $(stat -c %u "$d/usr/bin" 2>/dev/null || echo 0) != 0 ]]; then
            figy "${d}: nem root tulajdonú fájlok – törlöm, különben a telepített rendszerbe kerülnének"
            fut rm -rf "$d"
        fi
    done
    rm -f "$KIMENET" "${KIMENET}.sha256"
    fut lb build
    if [[ -f live-image-${ARCH}.hybrid.iso ]]; then
        mv "live-image-${ARCH}.hybrid.iso" "$KIMENET"
        sha256sum "$KIMENET" > "${KIMENET}.sha256"
        ok "kész: ${KIMENET}"
        info "USB-re írás:  sudo dd if=${KIMENET} of=/dev/sdX bs=4M status=progress oflag=sync"
        info "boot-teszt:   ./keszit.sh --teszt"
    else
        hiba "az ISO nem készült el – nézd meg a live-build kimenetét"
    fi
    vege
}

teszt() {
    cim "Boot-teszt QEMU-ban"
    [[ -f "$KIMENET" ]] || { hiba "nincs kész ISO: $KIMENET (előbb: sudo ./keszit.sh)"; vege; return 1; }
    if ! van qemu-system-x86_64; then
        figy "a QEMU nincs telepítve (Debian: apt install qemu-system-x86 ovmf)"; vege; return 1
    fi
    info "indítás… (a bezáráshoz zárd be a QEMU-ablakot)"
    local ovmf="" f
    if (( TESZT_UEFI )); then
        for f in /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd /usr/share/edk2/x64/OVMF.4m.fd /usr/share/edk2-ovmf/x64/OVMF.4m.fd; do
            [[ -f $f ]] && { ovmf="-bios $f"; break; }
        done
        [[ -n $ovmf ]] && info "UEFI mód: ${ovmf#-bios }" || figy "nincs OVMF – BIOS módban indul"
    fi
    local kvm=""; [[ -w /dev/kvm ]] && kvm="-enable-kvm -cpu host"
    qemu-system-x86_64 -m 2048 -smp 2 $kvm $ovmf -cdrom "$KIMENET" -boot d || true
    vege
}

tiszta() {
    cim "Takarítás"
    van lb && fut lb clean --purge || true
    fut rm -rf auto config/includes.chroot config/hooks config/package-lists config/includes.installer
    ok "build-melléktermékek törölve (az ISO megmarad, ha volt)"
    vege
}

docker_epit() {
    cim "Építés Docker-konténerben (debian:${DISZTRO})"
    van docker || { hiba "nincs docker"; vege; exit 1; }
    local ctx=()
    docker --context default info >/dev/null 2>&1 && ctx=(--context default)
    local szulo; szulo="$(cd "${PROJEKT}/.." && pwd)"
    local kulcs_fajl="${SSH_KULCS_FAJL:-$HOME/.ssh/id_ed25519.pub}" kulcs_tartalom=""
    if [[ -f $kulcs_fajl ]]; then
        kulcs_tartalom="$(head -1 "$kulcs_fajl")"
        ok "root SSH-kulcs a telepített géphez: ${kulcs_fajl}"
    else
        figy "nincs SSH-kulcs (${kulcs_fajl}) – a telepített gépre SSH-n senki nem lép be"
    fi
    info "a konténer a ${szulo} mappát látja (/munka), a cache megmarad a következő buildhez"
    vege
    local tty=(); [[ -t 0 && -t 1 ]] && tty=(-it)
    docker "${ctx[@]}" run --rm "${tty[@]}" --privileged \
        -v "${szulo}:/munka" -w /munka/"$(basename "$PROJEKT")" \
        -e SSH_KULCS="${kulcs_tartalom}" \
        "debian:${DISZTRO}" \
        bash -c "rm -f .lock; apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq live-build xorriso ca-certificates librsvg2-bin fonts-dejavu-core >/dev/null \
                 && ./keszit.sh ${TOVABBI[*]} ; rc=\$?; find . \\( -path ./cache -o -path ./chroot -o -path ./binary \\) -prune -o -exec chown -h $(id -u):$(id -g) {} + ; exit \$rc"
}

case "$AKCIO" in
    epit)   epit ;;
    docker) docker_epit ;;
    teszt)  teszt ;;
    tiszta) tiszta ;;
esac
