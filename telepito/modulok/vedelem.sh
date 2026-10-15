#!/usr/bin/env bash

cim "Behatolás-védelem – CrowdSec"

if ! csomag_van crowdsec; then
    if [[ "$OS_CSALAD" == "debian" || "$OS_CSALAD" == "fedora" ]]; then
        info "CrowdSec csomagtároló felvétele…"
        if [[ "$PROBA" == "1" ]]; then
            info "[próba] curl -fsSL https://install.crowdsec.net | sh"
        else
            curl -fsSL https://install.crowdsec.net | sh >/dev/null 2>&1 \
                || figy "a CrowdSec tárolót nem sikerült felvenni – a disztró saját csomagjával próbálom"
        fi
        csomaglista_frissit
    fi
    csomag_telepit crowdsec || { hiba "a CrowdSec nem települt"; return 0; }
fi

if [[ "$TUZFAL" == "ufw" ]] || van_parancs iptables; then
    BOUNCER="crowdsec-firewall-bouncer-iptables"
else
    BOUNCER="crowdsec-firewall-bouncer-nftables"
fi
csomag_telepit "$BOUNCER" || figy "a tűzfal-bouncer nem települt – a CrowdSec így csak jelez, nem tilt"

cat <<'WL' | fajlt_ir /etc/crowdsec/parsers/s02-enrich/park-whitelist.yaml
name: park/whitelist
description: "Saját hálózat: LAN, Docker, tailnet"
whitelist:
  reason: "saját hálózat"
  cidr:
    - "127.0.0.0/8"
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
    - "100.64.0.0/10"
WL

cat <<'AQ' | fajlt_ir /etc/crowdsec/acquis.d/park-journal.yaml
source: journalctl
journalctl_filter:
  - "_SYSTEMD_UNIT=ssh.service"
labels:
  type: syslog
---
source: journalctl
journalctl_filter:
  - "_SYSTEMD_UNIT=sshd.service"
labels:
  type: syslog
AQ

fut cscli collections install crowdsecurity/linux crowdsecurity/sshd >/dev/null 2>&1 || true

BCONF=/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
if [[ "$PROBA" != "1" && -f "$BCONF" ]] && ! grep -qE '^\s+- DOCKER-USER' "$BCONF"; then
    sed -i -E 's/^#\s*- DOCKER-USER/  - DOCKER-USER/' "$BCONF"
    grep -qE '^\s+- DOCKER-USER' "$BCONF" && ok "a tiltás a Docker-konténerek portjaira is vonatkozik"
fi

if [[ "$PROBA" != "1" ]]; then
    systemctl enable crowdsec >/dev/null 2>&1 || true
    systemctl restart crowdsec && ok "CrowdSec fut" || figy "a CrowdSec nem indult: journalctl -u crowdsec"
    systemctl restart crowdsec-firewall-bouncer >/dev/null 2>&1 || true
fi

szolgaltatas_jegyzes "CrowdSec" "(nincs felülete)" "sudo cscli decisions list | sudo cscli alerts list"

:
