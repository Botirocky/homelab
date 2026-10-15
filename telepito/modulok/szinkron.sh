#!/usr/bin/env bash
# Modul: fájlok böngészőből (FileBrowser) + eszközök közti szinkron (Syncthing)

cim "Fájlok böngészőből + szinkron"

for d in filebrowser syncthing; do konyvtar "${ADAT_DIR}/${d}"; done

SZINKRON_DIR="${SZINKRON_DIR:-${MEGOSZTAS_DIR:-${ADAT_DIR}/megosztas}/szinkron}"
konyvtar "$SZINKRON_DIR" 2775
[[ "$PROBA" != "1" ]] && fut chown -R "${PUID:-1000}:${PGID:-1000}" "$SZINKRON_DIR" 2>/dev/null

env_frissit "SZINKRON_DIR" "$SZINKRON_DIR"
env_frissit "TAROLO_DIR" "${TAROLO_DIR:-/srv/tarolok}"
env_beallit "SYNCTHING_NEV" "$(hostname)"

stack_telepit szinkron
stack_indit szinkron

vhost_ir "60-szinkron" "http://fajlok.${BELSO_DOMAIN} {
	reverse_proxy filebrowser:80
}

http://szinkron.${BELSO_DOMAIN} {
	reverse_proxy syncthing:8384
}"

szolgaltatas_jegyzes "FileBrowser" "http://fajlok.${BELSO_DOMAIN}"   "belépés: admin / admin – rögtön írd át!"
szolgaltatas_jegyzes "Syncthing"   "http://szinkron.${BELSO_DOMAIN}" "párosítsd a telefonnal/laptoppal"

:
