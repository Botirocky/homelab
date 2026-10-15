#!/usr/bin/env bash

cim "Jegyzetek és teendők – Memos + Vikunja"

for d in memos vikunja/files vikunja/db; do konyvtar "${ADAT_DIR}/${d}"; done
[[ "$PROBA" != "1" ]] && fut chown -R 1000:1000 "${ADAT_DIR}/vikunja" 2>/dev/null
titok VIKUNJA_JWT 48 >/dev/null
titok VIKUNJA_JELSZO 20 >/dev/null
titok MEMOS_JELSZO 20 >/dev/null
FELH="${SMB_FELHASZNALO:-admin}"

stack_telepit jegyzetek
stack_indit jegyzetek

if [[ "$PROBA" != "1" && ! -f "${ADAT_DIR}/memos/.park-fiok" ]] && konteneret_var park-memos 60; then
    for _ in $(seq 1 15); do
        valasz="$(curl -s -X POST http://127.0.0.1:8101/api/v1/users -H 'Content-Type: application/json' \
            -d "{\"username\":\"${FELH}\",\"password\":\"$(env_ertek MEMOS_JELSZO)\",\"role\":\"HOST\"}" 2>/dev/null || true)"
        [[ -n "$valasz" ]] && break
        sleep 2
    done
    if grep -q '"ADMIN"\|"HOST"' <<<"$valasz"; then
        touch "${ADAT_DIR}/memos/.park-fiok"
        ok "Memos-fiók létrehozva: $FELH (admin)"
    else
        figy "a Memos-fiókot nem sikerült létrehozni – az első regisztráló lesz az admin"
    fi
fi

if [[ "$PROBA" != "1" ]] && konteneret_var park-vikunja 60; then
    sleep 3
    if docker exec park-vikunja /app/vikunja/vikunja user list 2>/dev/null | grep -qw "$FELH"; then
        kihagy "Vikunja-fiók: $FELH"
    elif docker exec park-vikunja /app/vikunja/vikunja user create \
            --username "$FELH" --email "${FELH}@${BELSO_DOMAIN}" \
            --password "$(env_ertek VIKUNJA_JELSZO)" >/dev/null 2>&1; then
        ok "Vikunja-fiók létrehozva: $FELH"
    else
        figy "a Vikunja-fiókot nem sikerült létrehozni: docker exec park-vikunja /app/vikunja/vikunja user create …"
    fi
fi

vhost_ir "71-jegyzetek" "http://jegyzet.${BELSO_DOMAIN} {
	reverse_proxy memos:5230
}

http://teendo.${BELSO_DOMAIN} {
	reverse_proxy vikunja:3456
}"

szolgaltatas_jegyzes "Memos"   "http://jegyzet.${BELSO_DOMAIN}" "gyors jegyzetek; belépés: ${FELH} (MEMOS_JELSZO a .env-ben)"
szolgaltatas_jegyzes "Vikunja" "http://teendo.${BELSO_DOMAIN}"  "teendők, kanban; belépés: ${FELH} (VIKUNJA_JELSZO a .env-ben)"

:
