#!/usr/bin/env bash
# Modul: Caddy reverse proxy
# Ettől lesznek szép címek (ai.park.lan) a portszámok (:3000) helyett,
# a publikus oldalak pedig automatikusan kapnak HTTPS tanúsítványt.

cim "Reverse proxy (Caddy)"

env_beallit "EMAIL" "${EMAIL:-admin@${BELSO_DOMAIN}}"

stack_telepit proxy
konyvtar "${PARK_DIR}/stackek/proxy/sites.d"

# Kezdőlap-átirányítás: a szerver IP-jére nyitva a Homepage jöjjön be.
alap_vhost_ir

stack_indit proxy
szolgaltatas_jegyzes "Caddy (proxy)" "http://${BELSO_DOMAIN}" "80/443 – ő osztja szét a forgalmat"

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
