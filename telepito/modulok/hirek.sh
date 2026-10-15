#!/usr/bin/env bash

cim "Hírek és figyelés – Miniflux + changedetection.io"

for d in miniflux/db changedetection; do konyvtar "${ADAT_DIR}/${d}"; done
titok MINIFLUX_DB_JELSZO 32 >/dev/null
titok MINIFLUX_JELSZO 20 >/dev/null
env_beallit "MINIFLUX_FELHASZNALO" "${SMB_FELHASZNALO:-admin}"

stack_telepit hirek
stack_indit hirek

vhost_ir "67-hirek" "http://hirek.${BELSO_DOMAIN} {
	reverse_proxy miniflux:8080
}

http://valtozas.${BELSO_DOMAIN} {
	reverse_proxy changedetection:5000
}"

szolgaltatas_jegyzes "Miniflux"        "http://hirek.${BELSO_DOMAIN}"    "RSS-olvasó; belépés: $(env_ertek MINIFLUX_FELHASZNALO 2>/dev/null || echo "${SMB_FELHASZNALO:-admin}") (jelszó a .env-ben)"
szolgaltatas_jegyzes "changedetection" "http://valtozas.${BELSO_DOMAIN}" "weboldal-változás figyelő; értesítés: ntfy:// cím a beállításokban"

:
