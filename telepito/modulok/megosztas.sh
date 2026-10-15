#!/usr/bin/env bash

cim "Megosztás – PrivateBin + Excalidraw"

konyvtar "${ADAT_DIR}/privatebin"
[[ "$PROBA" != "1" ]] && fut chown -R 65534:82 "${ADAT_DIR}/privatebin" 2>/dev/null

stack_telepit megosztas
stack_indit megosztas

vhost_ir "72-megosztas" "http://paste.${BELSO_DOMAIN} {
	reverse_proxy privatebin:8080
}

http://rajz.${BELSO_DOMAIN} {
	reverse_proxy excalidraw:80
}"

szolgaltatas_jegyzes "PrivateBin" "http://paste.${BELSO_DOMAIN}" "titkosított szöveg-/fájlmegosztás, lejárattal"
szolgaltatas_jegyzes "Excalidraw" "http://rajz.${BELSO_DOMAIN}"  "rajztábla, vázlatok, diagramok"

:
