#!/usr/bin/env bash
# Disztribúció-független réteg: csomagkezelő, tűzfal, szolgáltatások.
# Támogatott családok: debian (apt), fedora (dnf), suse (zypper), arch (pacman).

rendszer_felismer() {
    OS_NEV="ismeretlen"; OS_CSALAD=""; OS_VERZIO=""
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_NEV="${PRETTY_NAME:-${NAME:-ismeretlen}}"
        OS_VERZIO="${VERSION_ID:-}"
        case "${ID:-}${ID_LIKE:-}" in
            *debian*|*ubuntu*)          OS_CSALAD="debian" ;;
            *fedora*|*rhel*|*centos*)   OS_CSALAD="fedora" ;;
            *suse*|*opensuse*)          OS_CSALAD="suse" ;;
            *arch*|*cachyos*)           OS_CSALAD="arch" ;;
        esac
        OS_ID="${ID:-}"
    fi
    [[ -n "$OS_CSALAD" ]] || return 1
    case "$OS_CSALAD" in
        debian) TUZFAL="ufw";      SAMBA_SZOLG="smbd nmbd" ;;
        fedora) TUZFAL="firewalld"; SAMBA_SZOLG="smb nmb"  ;;
        suse)   TUZFAL="firewalld"; SAMBA_SZOLG="smb nmb"  ;;
        arch)   TUZFAL="ufw";      SAMBA_SZOLG="smb nmb"  ;;
    esac
    export OS_NEV OS_CSALAD OS_VERZIO OS_ID TUZFAL SAMBA_SZOLG
}

# --- csomagok ----------------------------------------------------------------
csomag_van() {
    case "$OS_CSALAD" in
        debian) dpkg -s "$1" >/dev/null 2>&1 ;;
        fedora) rpm -q "$1" >/dev/null 2>&1 ;;
        suse)   rpm -q "$1" >/dev/null 2>&1 ;;
        arch)   pacman -Q "$1" >/dev/null 2>&1 ;;
    esac
}

csomaglista_frissit() {
    case "$OS_CSALAD" in
        debian) DEBIAN_FRONTEND=noninteractive fut apt-get update -qq -o DPkg::Lock::Timeout=600 ;;
        fedora) fut dnf -q makecache ;;
        suse)   fut zypper --non-interactive --quiet refresh ;;
        arch)   fut pacman -Sy --noconfirm >/dev/null ;;
    esac
}

csomag_telepit() {
    local hianyzo=()
    for cs in "$@"; do csomag_van "$cs" || hianyzo+=("$cs"); done
    if (( ${#hianyzo[@]} == 0 )); then return 0; fi
    case "$OS_CSALAD" in
        # A Lock::Timeout kell: ha épp fut az unattended-upgrades, az apt
        # különben azonnal elhasal a dpkg-záron, és a telepítő megáll.
        debian) DEBIAN_FRONTEND=noninteractive fut apt-get install -y -qq \
                    -o DPkg::Lock::Timeout=600 "${hianyzo[@]}" ;;
        fedora) fut dnf install -y -q "${hianyzo[@]}" ;;
        suse)   fut zypper --non-interactive --quiet install "${hianyzo[@]}" ;;
        arch)   fut pacman -S --noconfirm --needed "${hianyzo[@]}" ;;
    esac
}

# A családonként eltérő nevű alapcsomagok.
alap_csomaglista() {
    local kozos=(curl wget git jq unzip zstd rsync htop tmux fail2ban
                 smartmontools ncdu restic)
    case "$OS_CSALAD" in
        debian) printf '%s\n' "${kozos[@]}" ca-certificates gnupg nano vim-tiny \
                    lsb-release apt-transport-https ufw unattended-upgrades \
                    apt-listchanges avahi-daemon ;;
        fedora) printf '%s\n' "${kozos[@]}" ca-certificates gnupg2 nano vim-minimal \
                    firewalld dnf-automatic avahi policycoreutils-python-utils ;;
        suse)   printf '%s\n' "${kozos[@]}" ca-certificates gpg2 nano vim \
                    firewalld avahi ;;
        arch)   printf '%s\n' "${kozos[@]}" ca-certificates gnupg nano vim ufw avahi ;;
    esac
}

# --- automatikus biztonsági frissítés ---------------------------------------
auto_frissites_be() {
    case "$OS_CSALAD" in
        debian)
            cat <<'AU' | fajlt_ir /etc/apt/apt.conf.d/51szerverpark-auto
// Szerverpark: napi biztonsági frissítések, újraindítás nélkül.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
Unattended-Upgrade::Automatic-Reboot "false";
AU
            ok "automatikus biztonsági frissítés bekapcsolva (unattended-upgrades)" ;;
        fedora)
            if [[ "${PROBA:-0}" != "1" ]] && [[ -f /etc/dnf/automatic.conf ]]; then
                sed -i 's/^upgrade_type.*/upgrade_type = security/; s/^apply_updates.*/apply_updates = yes/' \
                    /etc/dnf/automatic.conf
            fi
            fut systemctl enable --now dnf-automatic.timer >/dev/null 2>&1 || true
            ok "automatikus biztonsági frissítés bekapcsolva (dnf-automatic)" ;;
        suse)
            cat <<'AU' | fajlt_ir /etc/systemd/system/szerverpark-frissites.service
[Unit]
Description=Szerverpark - biztonsági frissítések
[Service]
Type=oneshot
ExecStart=/usr/bin/zypper --non-interactive patch --category security
AU
            cat <<'AU' | fajlt_ir /etc/systemd/system/szerverpark-frissites.timer
[Unit]
Description=Szerverpark - napi biztonsági frissítés
[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30m
[Install]
WantedBy=timers.target
AU
            fut systemctl daemon-reload
            fut systemctl enable --now szerverpark-frissites.timer >/dev/null 2>&1 || true
            ok "automatikus biztonsági frissítés bekapcsolva (zypper patch)" ;;
        arch)
            figy "Arch/rolling: az automatikus frissítés itt kockázatos, kézzel: pacman -Syu" ;;
    esac
}

# --- tűzfal ------------------------------------------------------------------
tuzfal_alap() {
    if [[ "$TUZFAL" == "ufw" ]]; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            kihagy "tűzfal már aktív (ufw)"
        else
            fut ufw --force reset >/dev/null
            fut ufw default deny incoming
            fut ufw default allow outgoing
        fi
    else
        fut systemctl enable --now firewalld >/dev/null 2>&1 || true
    fi
}

tuzfal_port() {          # tuzfal_port <port> <tcp|udp> <megjegyzés>
    local port="$1" proto="${2:-tcp}" megj="${3:-}"
    if [[ "$TUZFAL" == "ufw" ]]; then
        fut ufw allow "${port}/${proto}" comment "$megj" >/dev/null 2>&1 || true
    else
        fut firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1 || true
    fi
}

tuzfal_halozatrol() {    # tuzfal_halozatrol <hálózat/CIDR> <port,port,...> [proto]
    local halo="$1" portok="$2" proto="${3:-tcp}"
    if [[ "$TUZFAL" == "ufw" ]]; then
        fut ufw allow from "$halo" to any port "$portok" proto "$proto" >/dev/null 2>&1 || true
    else
        fut firewall-cmd --permanent \
            --add-rich-rule="rule family=ipv4 source address=${halo} port port=${portok//,/ } protocol=${proto} accept" \
            >/dev/null 2>&1 || \
        fut firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 || true
    fi
}

tuzfal_interfeszrol() {  # tuzfal_interfeszrol <interfész> [megjegyzés]
    local iface="$1" megj="${2:-}"
    [[ -d "/sys/class/net/${iface}" ]] || return 0
    if [[ "$TUZFAL" == "ufw" ]]; then
        fut ufw allow in on "$iface" comment "$megj" >/dev/null 2>&1 || true
    else
        fut firewall-cmd --permanent --zone=trusted --add-interface="$iface" >/dev/null 2>&1 || true
    fi
}

tuzfal_ervenyesit() {
    if [[ "$TUZFAL" == "ufw" ]]; then
        fut ufw --force enable >/dev/null
    else
        fut firewall-cmd --reload >/dev/null 2>&1 || true
    fi
}

# --- szolgáltatások ----------------------------------------------------------
szolgaltatas_be() {
    for sz in "$@"; do
        fut systemctl enable --now "$sz" >/dev/null 2>&1 || true
    done
}

# --- Docker telepítése családonként -----------------------------------------
docker_engine_telepit() {
    case "$OS_CSALAD" in
        debian)
            konyvtar /etc/apt/keyrings 0755
            if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
                fut bash -c "curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg -o /etc/apt/keyrings/docker.asc"
                fut chmod a+r /etc/apt/keyrings/docker.asc
            fi
            local arch kodnev
            arch="$(dpkg --print-architecture)"
            kodnev="$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")"
            printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
                "$arch" "$OS_ID" "$kodnev" | fajlt_ir /etc/apt/sources.list.d/docker.list
            csomaglista_frissit
            csomag_telepit docker-ce docker-ce-cli containerd.io \
                           docker-buildx-plugin docker-compose-plugin ;;
        fedora)
            csomag_telepit dnf-plugins-core
            if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
                fut bash -c 'dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null \
                    || dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo'
            fi
            csomag_telepit docker-ce docker-ce-cli containerd.io \
                           docker-buildx-plugin docker-compose-plugin ;;
        suse)
            csomag_telepit docker docker-compose
            ;;
        arch)
            csomag_telepit docker docker-compose docker-buildx
            ;;
    esac
}
