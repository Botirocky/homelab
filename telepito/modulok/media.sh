#!/usr/bin/env bash
# Modul: média – Jellyfin (film, sorozat) és Navidrome (zene)

cim "Média – filmek és zene"

konyvtar "${ADAT_DIR}/jellyfin"
konyvtar "${ADAT_DIR}/navidrome"
[[ "$PROBA" != "1" ]] && fut chown -R "${PUID:-1000}:${PGID:-1000}" "${ADAT_DIR}/navidrome" 2>/dev/null

MEDIA_DIR="${MEDIA_DIR:-${ADAT_DIR}/media}"
for d in filmek sorozatok zene; do konyvtar "${MEDIA_DIR}/${d}" 2775; done
[[ "$PROBA" != "1" ]] && fut chown -R "${PUID:-1000}:${PGID:-1000}" "$MEDIA_DIR" 2>/dev/null

env_frissit "MEDIA_DIR" "$MEDIA_DIR"
env_beallit "VIDEO_GID" "$(getent group video | cut -d: -f3 || echo 44)"
env_beallit "RENDER_GID" "$(getent group render | cut -d: -f3 || echo 104)"

stack_telepit media
stack_indit media

vhost_ir "62-media" "http://media.${BELSO_DOMAIN} {
	reverse_proxy jellyfin:8096
}

http://zene.${BELSO_DOMAIN} {
	reverse_proxy navidrome:4533
}"

szolgaltatas_jegyzes "Jellyfin"  "http://media.${BELSO_DOMAIN}" "első megnyitáskor varázsló; a fájlok: ${MEDIA_DIR}"
szolgaltatas_jegyzes "Navidrome" "http://zene.${BELSO_DOMAIN}"  "zene: ${MEDIA_DIR}/zene"

:
