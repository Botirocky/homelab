#!/usr/bin/env bash
# Modul: iratok és olvasnivaló – Paperless-ngx, Linkding, Wallabag

cim "Iratok és olvasnivaló"

# A beolvasott iratok nőnek: mehetnek külön adathordozóra. Az adatbázis és a
# keresőindex (data) a rendszerlemezen marad.
IRATOK_DIR="${IRATOK_DIR:-${ADAT_DIR}/paperless}"
env_frissit "IRATOK_DIR" "$IRATOK_DIR"
for d in media export consume; do konyvtar "${IRATOK_DIR}/${d}"; done
for d in paperless/data paperless/redis linkding wallabag/data wallabag/images; do
    konyvtar "${ADAT_DIR}/${d}"
done
[[ "$PROBA" != "1" ]] && fut chown -R "${PUID:-1000}:${PGID:-1000}" "$IRATOK_DIR" 2>/dev/null
[[ "$PROBA" != "1" ]] && fut chown -R "${PUID:-1000}:${PGID:-1000}" "${ADAT_DIR}/paperless" 2>/dev/null
[[ "$PROBA" != "1" ]] && fut chown -R "${PUID:-1000}:${PGID:-1000}" "${ADAT_DIR}/linkding" "${ADAT_DIR}/wallabag" 2>/dev/null

PAPERLESS_JELSZO="$(titok PAPERLESS_JELSZO 20)"
LINKDING_JELSZO="$(titok LINKDING_JELSZO 20)"
titok WALLABAG_SECRET 40 >/dev/null
titok PAPERLESS_SECRET_KEY 64 >/dev/null
env_beallit "PAPERLESS_FELHASZNALO" "${SMB_FELHASZNALO:-admin}"
env_beallit "LINKDING_FELHASZNALO" "${SMB_FELHASZNALO:-admin}"

stack_telepit iratok
stack_indit iratok

vhost_ir "63-iratok" "http://iratok.${BELSO_DOMAIN} {
	reverse_proxy paperless:8000
}

http://konyvjelzo.${BELSO_DOMAIN} {
	reverse_proxy linkding:9090
}

http://olvaso.${BELSO_DOMAIN} {
	reverse_proxy wallabag:80
}"

szolgaltatas_jegyzes "Paperless" "http://iratok.${BELSO_DOMAIN}"     "iratok OCR-rel; a jelszó a .env-ben"
szolgaltatas_jegyzes "Linkding"  "http://konyvjelzo.${BELSO_DOMAIN}" "könyvjelzők; a jelszó a .env-ben"
szolgaltatas_jegyzes "Wallabag"  "http://olvaso.${BELSO_DOMAIN}"     "cikkek későbbre; első belépés: wallabag / wallabag"

:
