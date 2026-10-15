#!/usr/bin/env bash

cim "Pénzügyek – Actual Budget"

konyvtar "${ADAT_DIR}/actual"

stack_telepit penz
stack_indit penz

vhost_ir "70-penz" "https://penz.${BELSO_DOMAIN} {
	tls internal
	reverse_proxy actual:5006
}"

PENZ_CIM="https://penz.${BELSO_DOMAIN}"
PENZ_MEGJ="HTTPS kell neki; a böngésző elsőre figyelmeztet (saját tanúsítvány)"
if [[ "$PROBA" != "1" ]] && van_parancs tailscale && tailscale status >/dev/null 2>&1; then
    TS_NEV="$(tailscale status --json 2>/dev/null | sed -n 's/.*"DNSName": *"\([^"]*\)\.".*/\1/p' | head -1 || true)"
    if [[ -n "$TS_NEV" ]] && tailscale serve --bg --https="${PENZ_TS_PORT:-8443}" http://127.0.0.1:5006 >/dev/null 2>&1; then
        PENZ_CIM="https://${TS_NEV}:${PENZ_TS_PORT:-8443}"
        PENZ_MEGJ="valódi tanúsítvánnyal, a tailneten"
        ok "Actual a tailneten: ${PENZ_CIM}"
    fi
fi

szolgaltatas_jegyzes "Actual Budget" "$PENZ_CIM" "$PENZ_MEGJ"

:
