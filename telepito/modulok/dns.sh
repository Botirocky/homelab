#!/usr/bin/env bash

cim "Saját DNS-feloldó (Unbound)"

UNBOUND_PORT="${UNBOUND_PORT:-5335}"
csomag_telepit unbound || { figy "az unbound nem települt"; return 0; }

UNBOUND_IP6="no"
[[ -n "$(ip -6 route show default 2>/dev/null || true)" ]] && UNBOUND_IP6="yes"

cat <<UNB | fajlt_ir /etc/unbound/unbound.conf.d/park.conf
server:
    verbosity: 0
    interface: 127.0.0.1
    port: ${UNBOUND_PORT}
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: ${UNBOUND_IP6}
    prefer-ip6: no
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no
    edns-buffer-size: 1232
    prefetch: yes
    num-threads: 1
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
UNB

if [[ "$PROBA" != "1" ]] && systemctl list-unit-files unbound-resolvconf.service >/dev/null 2>&1; then
    systemctl disable --now unbound-resolvconf.service >/dev/null 2>&1 || true
fi
[[ -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf ]] && \
    fut rm -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf

if [[ "$PROBA" != "1" ]]; then
    if unbound-checkconf >/dev/null 2>&1; then
        systemctl enable unbound >/dev/null 2>&1 || true
        systemctl restart unbound && ok "Unbound fut: 127.0.0.1#${UNBOUND_PORT}" \
            || figy "az Unbound nem indult el: journalctl -u unbound"
    else
        hiba "hibás Unbound-konfig: unbound-checkconf"
    fi
fi

if [[ "$PROBA" != "1" ]] && van_parancs dig; then
    if dig +short +time=5 @127.0.0.1 -p "$UNBOUND_PORT" debian.org A >/dev/null 2>&1; then
        ok "a feloldás működik (debian.org)"
    else
        figy "az első lekérdezés nem sikerült – a gyökérszerverek elérhetők? (53/udp kifelé)"
    fi
fi

PIHOLE_KONTENER="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -xE 'pihole|park-pihole' | head -1 || true)"
if [[ -n "$PIHOLE_KONTENER" ]]; then
    PIHOLE_HALO="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$PIHOLE_KONTENER" 2>/dev/null || true)"
    PIHOLE_ENV_UPSTREAM="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$PIHOLE_KONTENER" 2>/dev/null \
        | grep -c '^FTLCONF_dns_upstreams=' || true)"
    if [[ "$PIHOLE_HALO" != "host" ]]; then
        figy "a ${PIHOLE_KONTENER} nem host hálózaton fut – a 127.0.0.1#${UNBOUND_PORT} onnan nem látszik"
    elif [[ "$PIHOLE_ENV_UPSTREAM" != "0" ]]; then
        figy "a Pi-hole feloldóit a compose-ban lévő FTLCONF_dns_upstreams rögzíti;"
        figy "  ott írd át erre: '127.0.0.1#${UNBOUND_PORT}'"
    elif [[ "${PIHOLE_UNBOUND:-n}" == "i" ]] || igen_nem "Átállítsam a Pi-hole-t az Unboundra (Cloudflare/Quad9 helyett)?" "n"; then
        fut docker exec "$PIHOLE_KONTENER" pihole-FTL --config dns.upstreams "[\"127.0.0.1#${UNBOUND_PORT}\"]" >/dev/null \
            && ok "a Pi-hole mostantól az Unboundot kérdezi" \
            || figy "a Pi-hole átállítása nem sikerült"
    else
        info "a Pi-hole-hoz nem nyúltam; kézzel: Settings → DNS → Custom: 127.0.0.1#${UNBOUND_PORT}"
    fi
fi

szolgaltatas_jegyzes "Unbound" "127.0.0.1#${UNBOUND_PORT}" "rekurzív feloldó; Pi-hole upstreamnek"

:
