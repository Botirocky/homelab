#!/usr/bin/env bash

cim "Cron-figyelő – Healthchecks (szól, ha egy ütemezett feladat NEM fut le)"

konyvtar "${ADAT_DIR}/healthchecks"
[[ "$PROBA" != "1" ]] && fut chown -R 999:999 "${ADAT_DIR}/healthchecks" 2>/dev/null
titok HC_SECRET 50 >/dev/null
titok HC_JELSZO 20 >/dev/null
FELH="${SMB_FELHASZNALO:-admin}"
EMAIL="${FELH}@${BELSO_DOMAIN}"

stack_telepit cronfigyelo
stack_indit cronfigyelo

FIGYELOK='[["park-mentes", 24, 3, "mentes"]]'

if [[ "$PROBA" != "1" ]] && konteneret_var park-healthchecks 90; then
    KI=""
    for _ in $(seq 1 15); do
        KI="$(docker exec -i \
            -e PARK_EMAIL="$EMAIL" -e PARK_JELSZO="$(env_ertek HC_JELSZO)" \
            -e PARK_NTFY="${NTFY_URL:-}" -e PARK_FIGYELOK="$FIGYELOK" \
            park-healthchecks python /opt/healthchecks/manage.py shell \
            < "${TELEPITO_DIR}/sablonok/cronfigyelo/beallit.py" 2>/dev/null || true)"
        grep -q '^PING ' <<<"$KI" && break
        sleep 4
    done
    if grep -q '^PING ' <<<"$KI"; then
        ok "Healthchecks-fiók: ${EMAIL}"
        while read -r _ nev kod; do
            kulcs="HC_$(tr 'a-z-' 'A-Z_' <<<"${nev#park-}")_URL"
            env_frissit "$kulcs" "http://127.0.0.1:8107/ping/${kod}"
            ok "figyelő: ${nev} → ${kulcs}"
        done < <(grep '^PING ' <<<"$KI")
    else
        figy "a Healthchecks beállítása nem sikerült – nézd meg: docker logs park-healthchecks"
    fi
fi

vhost_ir "75-cronfigyelo" "http://cron.${BELSO_DOMAIN} {
	reverse_proxy healthchecks:8000
}"

szolgaltatas_jegyzes "Healthchecks" "http://cron.${BELSO_DOMAIN}" "ha a mentés nem fut le időben, ntfy-on szól; belépés: ${EMAIL} (HC_JELSZO a .env-ben)"

:
