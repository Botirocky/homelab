#!/usr/bin/env bash
# Modul: virtuális gépek + test lab
#
#   KVM / libvirt  – „igazi" virtuális gépek (bármilyen ISO: Windows, BSD, régi
#                    disztró, hálózati eszköz-imázs). Ezek lassan indulnak, de
#                    mindent tudnak.
#   Incus          – test lab: másodpercek alatt induló VM-ek ÉS konténerek,
#                    kész rendszerképekből, pillanatképekkel. Ide való a
#                    „gyorsan kipróbálom" jellegű munka.
#   Cockpit        – webes felület a VM-ekhez (kattintgatós kezelés).

cim "Virtualizáció – VM-ek és test lab"

# ------------------------------------------------------- támogatja-e a vas? --
GEP_ARCH="$(uname -m)"
if [[ "$GEP_ARCH" == aarch64 || "$GEP_ARCH" == arm64 ]]; then
    # ARM-en nincs vmx/svm flag: ott a /dev/kvm léte a jel (a Raspberry Pi 4/5
    # 64 bites kernellel tudja). Csak ARM vendéggépek mennek gyorsan.
    if [[ -e /dev/kvm ]]; then
        ok "ARM gép hardveres virtualizációval (/dev/kvm megvan)"
    else
        figy "Ezen az ARM gépen nincs /dev/kvm – a VM-ek csak emulációval mennek."
    fi
    figy "ARM-en csak ARM vendégrendszer fut gyorsan; x86-os ISO emulációval"
    figy "indul, ami használhatatlanul lassú. Konténerekhez az Incus a jó választás."
elif grep -qE '^flags.*\b(vmx|svm)\b' /proc/cpuinfo; then
    CPU_VIRT="$(grep -oE '\b(vmx|svm)\b' /proc/cpuinfo | head -1)"
    ok "a processzor támogatja a hardveres virtualizációt (${CPU_VIRT})"
else
    figy "A processzor NEM jelez hardveres virtualizációt (vmx/svm)."
    figy "Kapcsold be a BIOS/UEFI-ben: Intel VT-x / AMD-V (és VT-d, ha van)."
    figy "Enélkül a VM-ek csak emulációval mennek – használhatatlanul lassan."
fi
if [[ -e /dev/kvm ]]; then
    ok "/dev/kvm elérhető"
elif [[ "$PROBA" != "1" ]]; then
    figy "/dev/kvm még nincs – a modulok betöltése után meglesz (vagy BIOS-beállítás kell)."
fi

# ------------------------------------------------------------- csomagok ------
info "virtualizációs csomagok telepítése…"
# A QEMU rendszer-csomag architektúránként más nevű.
if [[ "$GEP_ARCH" == aarch64 || "$GEP_ARCH" == arm64 ]]; then
    QEMU_CSOMAG="qemu-system-arm"; OVMF_CSOMAG="qemu-efi-aarch64"
else
    QEMU_CSOMAG="qemu-system-x86"; OVMF_CSOMAG="ovmf"
fi
case "$OS_CSALAD" in
    debian)
        csomag_telepit "$QEMU_CSOMAG" qemu-utils libvirt-daemon-system \
            libvirt-clients virtinst bridge-utils cloud-image-utils \
            genisoimage "$OVMF_CSOMAG" swtpm cockpit cockpit-machines incus ;;
    fedora)
        csomag_telepit qemu-kvm libvirt virt-install bridge-utils \
            cloud-utils edk2-ovmf swtpm cockpit cockpit-machines incus ;;
    suse)
        csomag_telepit qemu-kvm libvirt virt-install bridge-utils \
            cloud-init-config-libvirt ovmf swtpm cockpit cockpit-machines incus ;;
    arch)
        csomag_telepit qemu-full libvirt virt-install dnsmasq bridge-utils \
            edk2-ovmf swtpm cockpit cockpit-machines incus ;;
esac
ok "KVM/libvirt + Incus + Cockpit fent"

szolgaltatas_be libvirtd
szolgaltatas_be cockpit.socket

# A napi felhasználó sudo nélkül is kezelhesse a VM-eket
CEL_USER="${SUDO_USER:-}"
if [[ -n "$CEL_USER" ]]; then
    for csop in libvirt kvm incus incus-admin; do
        if getent group "$csop" >/dev/null 2>&1 && ! id -nG "$CEL_USER" | grep -qw "$csop"; then
            fut usermod -aG "$csop" "$CEL_USER"
        fi
    done
    ok "$CEL_USER felvéve a libvirt/kvm/incus csoportokba (új bejelentkezés után él)"
fi

# ------------------------------------------------------------- tárhelyek -----
konyvtar "${ADAT_DIR}/vm" 0755
konyvtar "${ADAT_DIR}/vm/lemezek"       # a VM-ek virtuális lemezei
konyvtar "${ADAT_DIR}/vm/iso"           # ide töltsd az ISO-kat
konyvtar "${ADAT_DIR}/vm/incus"         # az Incus test lab tárolója
konyvtar "${ADAT_DIR}/vm/sablonok"      # cloud-init sablonok

# libvirt tárolók bejegyzése (ha még nincsenek)
if [[ "$PROBA" == "1" ]]; then
    info "[próba] libvirt tárolók létrehozása (lemezek, iso)"
else
    for par in "park-lemezek:${ADAT_DIR}/vm/lemezek" "park-iso:${ADAT_DIR}/vm/iso"; do
        nev="${par%%:*}"; ut="${par#*:}"
        if virsh pool-info "$nev" >/dev/null 2>&1; then
            kihagy "libvirt tároló: $nev"
        else
            virsh pool-define-as "$nev" dir --target "$ut" >/dev/null 2>&1 || true
            virsh pool-build "$nev" >/dev/null 2>&1 || true
            virsh pool-start "$nev" >/dev/null 2>&1 || true
            virsh pool-autostart "$nev" >/dev/null 2>&1 || true
            ok "libvirt tároló: $nev -> $ut"
        fi
    done
    # Az alapértelmezett NAT-hálózat induljon magától
    virsh net-autostart default >/dev/null 2>&1 || true
    virsh net-start default >/dev/null 2>&1 || true

    # A libvirt alapértelmezett hálózata saját dnsmasq-ot indít, ami elfoglalja
    # az 53-as portot. Ha a gépen DNS-kiszolgáló is fut (Pi-hole, AdGuard,
    # systemd-resolved), az a következő újraindításnál NEM tud elindulni –
    # és a hálózat DNS nélkül marad. Ezért a libvirt DNS-ét kikapcsoljuk
    # (a DHCP és a NAT marad), a VM-ek pedig a gép DNS-ét kapják meg.
    if ss -ln 2>/dev/null | grep -qE '[:.]53 '; then
        SAJAT_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || true)"
        python3 - "${SAJAT_IP:-}" <<'LIBVIRTDNS' && \
            ok "a libvirt DNS-e kikapcsolva – az 53-as port a DNS-kiszolgálóé marad" || \
            figy "a libvirt dnsmasq-ját nem sikerült átállítani – ellenőrizd: ss -lnp | grep :53"
import re, subprocess, sys
ip = sys.argv[1] if len(sys.argv) > 1 else ""
xml = subprocess.run(["virsh", "net-dumpxml", "default"],
                     capture_output=True, text=True).stdout
if not xml.strip():
    sys.exit(1)
if "<dns enable='no'/>" in xml or '<dns enable="no"' in xml:
    sys.exit(0)
NS = "http://libvirt.org/schemas/network/dnsmasq/1.0"
if "xmlns:dnsmasq" not in xml:
    xml = re.sub(r"<network(\s|>)", f"<network xmlns:dnsmasq='{NS}'\\1", xml, count=1)
xml = re.sub(r"\s*<dns[^>]*/>", "", xml)
xml = re.sub(r"\s*<dns>.*?</dns>", "", xml, flags=re.S)
xml = re.sub(r"\s*<dnsmasq:options>.*?</dnsmasq:options>", "", xml, flags=re.S)
blokk = "  <dns enable='no'/>\n"
if ip:
    blokk += ("  <dnsmasq:options>\n"
              f"    <dnsmasq:option value='dhcp-option=6,{ip}'/>\n"
              "  </dnsmasq:options>\n")
xml = xml.replace("</network>", blokk + "</network>", 1)
open("/tmp/park-libvirt-default.xml", "w").write(xml)
for cmd in (["virsh", "net-define", "/tmp/park-libvirt-default.xml"],
            ["virsh", "net-destroy", "default"],
            ["virsh", "net-start", "default"]):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if cmd[1] == "net-define" and r.returncode != 0:
        sys.exit(1)
sys.exit(0)
LIBVIRTDNS
    fi
fi

# ------------------------------------------------------------- Incus init ----
# Lépésenként, nem preseeddel: ha az egyik darab már megvan (pl. a tároló, de a
# hálózat nem), a preseed elhasal, a külön lépések viszont átlépik a meglévőt.
if [[ "$PROBA" == "1" ]]; then
    info "[próba] Incus alapbeállítás (dir tároló + incusbr0 hálózat)"
else
    if incus storage show default >/dev/null 2>&1; then
        kihagy "Incus tároló: default"
    elif incus storage create default dir source="${ADAT_DIR}/vm/incus" >/dev/null 2>&1; then
        ok "Incus tároló: default -> ${ADAT_DIR}/vm/incus"
    else
        figy "az Incus tárolót nem sikerült létrehozni"
    fi

    if incus network show incusbr0 >/dev/null 2>&1; then
        kihagy "Incus hálózat: incusbr0"
    else
        # Ha a gazdagép 53-as portján már ül valaki (Pi-hole, AdGuard,
        # systemd-resolved), az Incus dnsmasqja nem tud elindulni. A port=0 csak
        # a DNS-ét kapcsolja ki – a DHCP, ami a gépeknek kell, marad.
        DNSMASQ_EXTRA=""
        if ss -ln 2>/dev/null | grep -qE '[:.]53 '; then
            DNSMASQ_EXTRA="port=0"
            info "a gazdagép 53-as portja foglalt – az Incus DNS-e kikapcsolva (a DHCP megy)"
        fi
        if incus network create incusbr0 ipv4.address=auto ipv4.nat=true \
               ipv6.address=none raw.dnsmasq="$DNSMASQ_EXTRA" >/dev/null 2>&1; then
            ok "Incus hálózat: incusbr0"
        else
            figy "az Incus hálózatot nem sikerült létrehozni"
        fi
    fi

    INCUS_DNSMASQ="$(incus network get incusbr0 raw.dnsmasq 2>/dev/null || true)"
    INCUS_IP="$(incus network get incusbr0 ipv4.address 2>/dev/null | cut -d/ -f1 || true)"
    if grep -q '^port=0' <<<"$INCUS_DNSMASQ" && ! grep -q '^dhcp-option=6,' <<<"$INCUS_DNSMASQ" && [[ -n "$INCUS_IP" ]]; then
        incus network set incusbr0 raw.dnsmasq="$(printf '%s\ndhcp-option=6,%s' "$INCUS_DNSMASQ" "$INCUS_IP")" >/dev/null 2>&1 \
            && ok "Incus DHCP: DNS-nek a gazdagépet ($INCUS_IP) adja" \
            || figy "az Incus DHCP DNS-beállítása nem sikerült"
    fi

    incus profile show default 2>/dev/null | grep -qE '^ +eth0:' || \
        incus profile device add default eth0 nic network=incusbr0 name=eth0 >/dev/null 2>&1 || true
    incus profile show default 2>/dev/null | grep -qE '^ +root:' || \
        incus profile device add default root disk pool=default path=/ >/dev/null 2>&1 || true
    ok "Incus test lab kész (tároló: ${ADAT_DIR}/vm/incus)"
fi

if systemctl cat incus-startup.service >/dev/null 2>&1; then
    printf '[Service]\nExecStart=\nExecStart=-/usr/libexec/incus/incusd activateifneeded\n' \
        | fajlt_ir /etc/systemd/system/incus-startup.service.d/50-park-hibatures.conf
    [[ "$PROBA" != "1" ]] && systemctl daemon-reload 2>/dev/null || true
    ok "incus-startup: az activateifneeded hibája nem hagy failed unitot"
fi

# ------------------------------------------------------------- Cockpit -------
# A Cockpit a HOST-on fut (9090), a Caddy viszont konténerben – ezért a
# host-gateway címen éri el. Proxy mögött engedélyezni kell az eredetet.
cat <<COCKPIT | fajlt_ir /etc/cockpit/cockpit.conf
# A szerverpark telepítő írta.
[WebService]
Origins = http://vm.${BELSO_DOMAIN} https://vm.${BELSO_DOMAIN}
ProtocolHeader = X-Forwarded-Proto
AllowUnencrypted = true
COCKPIT
[[ "$PROBA" != "1" ]] && fut systemctl restart cockpit.socket 2>/dev/null || true

vhost_ir "40-vm" "http://vm.${BELSO_DOMAIN} {
	# A Cockpit a gazdagépen fut, nem konténerben.
	reverse_proxy host.docker.internal:9090
}"

# A proxy konténer lássa a gazdagépet
if ! grep -q "host-gateway" "${PARK_DIR}/stackek/proxy/compose.yml" 2>/dev/null; then
    if [[ "$PROBA" == "1" ]]; then
        info "[próba] host-gateway bejegyzés a proxy compose-ba"
    else
        python3 - "${PARK_DIR}/stackek/proxy/compose.yml" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
if "host-gateway" not in s:
    s = s.replace("    networks: [park]",
                  "    extra_hosts:\n"
                  "      - \"host.docker.internal:host-gateway\"\n"
                  "    networks: [park]", 1)
    p.write_text(s, encoding="utf-8")
PY
        ok "a proxy mostantól eléri a gazdagépet (Cockpit)"
        ( cd "${PARK_DIR}/stackek/proxy" && docker compose up -d >/dev/null 2>&1 ) || true
    fi
fi

# ------------------------------------------------------------- tűzfal --------
FO_IF="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}' || true)"
if [[ -n "$FO_IF" ]]; then
    HELYI_HALO="$(ip -4 route show scope link dev "$FO_IF" 2>/dev/null | awk '{print $1; exit}' || true)"
fi
if [[ -n "${HELYI_HALO:-}" ]]; then
    tuzfal_halozatrol "$HELYI_HALO" "9090" tcp        # Cockpit a LAN-ról
    # A Caddy konténerből proxyzza a Cockpitet, ezért a Docker-hidak is kellenek.
    tuzfal_halozatrol "172.16.0.0/12" "9090" tcp
    tuzfal_ervenyesit
    ok "Cockpit (9090) engedve a helyi hálózatról és a konténerekből"
fi

# Az Incus gépei a saját hídjukon kapnak DHCP-t, és azon mennek kifelé.
# ufw mellett ezt külön engedni kell, különben IP-t sem kapnak.
if [[ "$PROBA" != "1" ]] && [[ -d /sys/class/net/incusbr0 ]]; then
    tuzfal_interfeszrol incusbr0 "Incus test lab"
    if [[ "$TUZFAL" == "ufw" ]]; then
        for kulso_if in $( { echo "$FO_IF"; for d in /sys/class/net/*/device; do basename "$(dirname "$d")"; done; } | sort -u); do
            fut ufw route allow in on incusbr0 out on "$kulso_if" comment "Incus kifelé ($kulso_if)" >/dev/null 2>&1 || true
        done
    fi
    tuzfal_ervenyesit
    ok "az Incus gépei kapnak IP-t és kijutnak a netre"
fi

# ------------------------------------------------------- cloud-init sablon ---
cat <<'CLOUD' | fajlt_ir "${ADAT_DIR}/vm/sablonok/alap-user-data.yaml"
#cloud-config
# Alap cloud-init: a 'park lab uj' ezt adja az új gépeknek.
# A jelszó helyett SSH-kulcsot használj, ha van.
users:
  - name: admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    # jelszó: valtoztasd-meg   (mkpasswd -m sha-512 paranccsal cserélhető)
    plain_text_passwd: valtoztasd-meg
package_update: true
packages:
  - qemu-guest-agent
  - curl
  - htop
runcmd:
  - systemctl enable --now qemu-guest-agent
CLOUD

# ------------------------------------------------------------ figyelmeztetés -
figy "A VM-ek alapból NAT mögött vannak (kifelé mennek, kívülről nem látszanak)."
figy "Ha a VM-ek saját LAN-IP-t kapjanak, hálózati bridge (br0) kell – ezt a"
figy "telepítő SZÁNDÉKOSAN nem állítja be, mert rosszul megcsinálva megszakítja"
figy "a szerver hálózatát. Leírás: README, „VM-ek a házi hálózaton\" fejezet."

szolgaltatas_jegyzes "Cockpit (VM-ek)" "http://vm.${BELSO_DOMAIN}" "webes VM-kezelő, belépés a rendszer-jelszóval"
szolgaltatas_jegyzes "Test lab"        "park lab uj <név>"           "Incus – másodpercek alatt induló gépek"

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
