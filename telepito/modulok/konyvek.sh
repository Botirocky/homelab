#!/usr/bin/env bash

cim "Könyvek – Kavita + Audiobookshelf"

KONYV_DIR="${KONYV_DIR:-${MEDIA_DIR:-${ADAT_DIR}/media}}"
env_frissit "KONYV_DIR" "$KONYV_DIR"
for d in konyvek kepregenyek hangoskonyvek podcastok; do konyvtar "${KONYV_DIR}/${d}" 2775; done
for d in kavita audiobookshelf/config audiobookshelf/metadata; do konyvtar "${ADAT_DIR}/${d}"; done
[[ "$PROBA" != "1" ]] && fut chown "${PUID:-1000}:${PGID:-1000}" \
    "${KONYV_DIR}/konyvek" "${KONYV_DIR}/kepregenyek" "${KONYV_DIR}/hangoskonyvek" "${KONYV_DIR}/podcastok" 2>/dev/null

stack_telepit konyvek
stack_indit konyvek

vhost_ir "66-konyvek" "http://konyvek.${BELSO_DOMAIN} {
	reverse_proxy kavita:5000
}

http://hangoskonyv.${BELSO_DOMAIN} {
	reverse_proxy audiobookshelf:80
}"

szolgaltatas_jegyzes "Kavita"         "http://konyvek.${BELSO_DOMAIN}"     "e-könyv, képregény: ${KONYV_DIR}/konyvek"
szolgaltatas_jegyzes "Audiobookshelf" "http://hangoskonyv.${BELSO_DOMAIN}" "hangoskönyv, podcast; első megnyitáskor fiók"

:
