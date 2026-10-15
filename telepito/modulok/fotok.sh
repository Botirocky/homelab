#!/usr/bin/env bash

cim "Fotók – Immich"

FOTO_DIR="${FOTO_DIR:-${ADAT_DIR}/immich/fotok}"
konyvtar "$FOTO_DIR"
konyvtar "${ADAT_DIR}/immich/db"
env_frissit "FOTO_DIR" "$FOTO_DIR"
env_frissit "TAROLO_DIR" "${TAROLO_DIR:-/srv/tarolok}"
titok IMMICH_DB_JELSZO 32 >/dev/null

if [[ -z "${FOTO_ML:-}" ]]; then
    if [[ "$(uname -m)" == "aarch64" ]] || (( ${MEM_GB:-0} < 12 )); then FOTO_ML="n"; else FOTO_ML="i"; fi
fi
FELULIRO="${PARK_DIR}/stackek/fotok/compose.override.yml"
if [[ "$FOTO_ML" == "i" ]]; then
    env_frissit "FOTO_ML_BE" "true"
    cat <<'ML' | fajlt_ir "$FELULIRO"
services:
  immich-ml:
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-v3}
    container_name: park-immich-ml
    restart: unless-stopped
    volumes:
      - ${ADAT_DIR}/immich/ml-cache:/cache
    environment:
      TZ: ${TZ}
    networks: [park]
ML
    info "gépi tanulás (arcok, keresés szöveggel): BE"
else
    env_frissit "FOTO_ML_BE" "false"
    [[ -f "$FELULIRO" ]] && fut rm -f "$FELULIRO"
    info "gépi tanulás: KI (kis gépen lassú; bekapcsolás: FOTO_ML=\"i\" a confban)"
fi

stack_telepit fotok
stack_indit fotok

vhost_ir "65-fotok" "http://fotok.${BELSO_DOMAIN} {
	request_body {
		max_size 50GB
	}
	reverse_proxy immich-server:2283
}"

szolgaltatas_jegyzes "Immich" "http://fotok.${BELSO_DOMAIN}" "első megnyitáskor admin fiók; a tárolók: /tarolok (külső könyvtárnak, csak olvasva)"

:
