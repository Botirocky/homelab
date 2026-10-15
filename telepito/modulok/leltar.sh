#!/usr/bin/env bash

cim "Háztartási leltár – Homebox"

konyvtar "${ADAT_DIR}/homebox"
titok HOMEBOX_JELSZO 20 >/dev/null
titok HOMEBOX_PEPPER 64 >/dev/null
FELH="${SMB_FELHASZNALO:-admin}"
KESZ="${ADAT_DIR}/homebox/.park-fiok"

stack_telepit leltar

if [[ "$PROBA" != "1" && ! -f "$KESZ" ]]; then
    env_frissit HOMEBOX_REGISZTRACIO true
    stack_indit leltar
    if konteneret_var park-homebox 60; then
        valasz=""
        for _ in $(seq 1 20); do
            valasz="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8105/api/v1/users/register \
                -H 'Content-Type: application/json' \
                -d "{\"name\":\"${FELH}\",\"email\":\"${FELH}@${BELSO_DOMAIN}\",\"password\":\"$(env_ertek HOMEBOX_JELSZO)\"}" 2>/dev/null || true)"
            [[ "$valasz" =~ ^2 ]] && break
            sleep 2
        done
        if [[ "$valasz" =~ ^2 ]]; then
            touch "$KESZ"
            ok "Homebox-fiók létrehozva: ${FELH}@${BELSO_DOMAIN}"
        else
            figy "a Homebox-fiókot nem sikerült létrehozni (HTTP ${valasz:-?}) – a regisztráció nyitva marad"
        fi
    fi
fi
[[ -f "$KESZ" || "$PROBA" == "1" ]] && env_frissit HOMEBOX_REGISZTRACIO false
stack_indit leltar

vhost_ir "73-leltar" "http://leltar.${BELSO_DOMAIN} {
	reverse_proxy homebox:7745
}"

szolgaltatas_jegyzes "Homebox" "http://leltar.${BELSO_DOMAIN}" "leltár QR-címkékkel; belépés: ${FELH}@${BELSO_DOMAIN} (HOMEBOX_JELSZO a .env-ben)"

:
