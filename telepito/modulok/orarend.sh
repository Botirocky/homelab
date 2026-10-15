#!/usr/bin/env bash

cim "Órarend – Kréta-alapú órarendkezelő"

konyvtar "${ADAT_DIR}/orarend"
[[ "$PROBA" == "1" ]] || chown 1000:1000 "${ADAT_DIR}/orarend"

titok ORAREND_ICS_KULCS 32 >/dev/null
ORAREND_JELSZO="$(titok ORAREND_JELSZO 20)"

stack_telepit orarend
if [[ "$PROBA" != "1" ]]; then
    rm -rf "${PARK_DIR}/stackek/orarend/app"
    cp -r "${TELEPITO_DIR}/sablonok/orarend/app" "${TELEPITO_DIR}/sablonok/orarend/Dockerfile" "${PARK_DIR}/stackek/orarend/"
    info "kép építése: park-orarend …"
    ( cd "${PARK_DIR}/stackek/orarend" && fut docker compose build -q ) || hiba "nem épült meg a park-orarend kép"
fi
stack_indit orarend

vhost_ir "71-orarend" "http://orarend.${BELSO_DOMAIN} {
	reverse_proxy orarend:8080
}"

ORAREND_CIM="http://orarend.${BELSO_DOMAIN}"
ORAREND_MEGJ="saját jelszó: ORAREND_JELSZO; első lépés: Kréta-belépés"
if [[ "$PROBA" != "1" ]] && van_parancs tailscale && tailscale status >/dev/null 2>&1; then
    TS_NEV="$(tailscale status --json 2>/dev/null | sed -n 's/.*"DNSName": *"\([^"]*\)\.".*/\1/p' | head -1 || true)"
    if [[ -n "$TS_NEV" ]] && tailscale serve --bg --https="${ORAREND_TS_PORT:-8444}" "http://127.0.0.1:${ORAREND_HELYI_PORT:-8099}" >/dev/null 2>&1; then
        ORAREND_CIM="https://${TS_NEV}:${ORAREND_TS_PORT:-8444}"
        ORAREND_MEGJ="valódi tanúsítvánnyal, a tailneten (itthon: http://orarend.${BELSO_DOMAIN}); jelszó: ORAREND_JELSZO"
        ok "órarend a tailneten: ${ORAREND_CIM}"
    else
        figy "a tailscale serve nem sikerült – csak http://orarend.${BELSO_DOMAIN} megy"
    fi
fi

szolgaltatas_jegyzes "Órarend (Kréta)" "$ORAREND_CIM" "$ORAREND_MEGJ"

:
