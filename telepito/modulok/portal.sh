#!/usr/bin/env bash

cim "Hotspot captive portál – park-portal"

if [[ "$PROBA" == "1" ]]; then
    info "[próba] install park-portal -> /usr/local/bin/ + /etc/park-portal/portal.nft + park-portal.service (port 8077)"
else
    van_parancs conntrack || csomag_telepit conntrack
    install -m 0755 "${TELEPITO_DIR}/skriptek/park-portal" /usr/local/bin/park-portal
    install -D -m 0644 "${TELEPITO_DIR}/sablonok/portal/portal.nft" /etc/park-portal/portal.nft
    [[ -f /etc/park-portal.conf ]] || install -m 0644 "${TELEPITO_DIR}/sablonok/portal/park-portal.conf" /etc/park-portal.conf
    install -m 0644 "${TELEPITO_DIR}/sablonok/portal/park-portal.service" /etc/systemd/system/park-portal.service
    van_parancs ufw && ufw allow in on wlan0 to any port 8077 proto tcp comment "park-portal" >/dev/null 2>&1
    if [[ ! -s /var/lib/park-portal/engedett.json ]]; then
        while read -r _ mac _ nev _; do
            [[ -n "$mac" ]] && /usr/local/bin/park-portal enged "$mac" orokre "telepítéskor már csatlakozva ($nev)" >/dev/null
        done < <(cat /var/lib/NetworkManager/dnsmasq-wlan0.leases 2>/dev/null)
        info "a már csatlakozott eszközök örökre engedélyezve (park-portal lista)"
    fi
    systemctl daemon-reload
    systemctl enable --now park-portal.service >/dev/null 2>&1 \
        && ok "park-portal fut (hotspot: e-mail + wifi-jelszó + ntfy-jóváhagyás, 30 nap)" \
        || figy "a park-portal nem indult: systemctl status park-portal"
fi

szolgaltatas_jegyzes "Wifi-hozzáférések" "http://<tailscale-ip>:8077/admin" "csak tailnetről; a hotspoton új eszköz e-mail + jelszó után ntfy-jóváhagyással kap netet"
