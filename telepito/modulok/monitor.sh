#!/usr/bin/env bash

cim "Erőforrás-grafikonok – Beszel"

for d in data socket agent; do konyvtar "${ADAT_DIR}/beszel/${d}"; done
env_frissit "TAROLO_DIR" "${TAROLO_DIR:-/srv/tarolok}"

stack_telepit monitor
stack_indit monitor

KULCS_FAJL="${ADAT_DIR}/beszel/data/id_ed25519"
if [[ "$PROBA" != "1" ]]; then
    for _ in $(seq 1 30); do [[ -f "$KULCS_FAJL" ]] && break; sleep 2; done
    if [[ -f "$KULCS_FAJL" ]] && KULCS="$(ssh-keygen -y -f "$KULCS_FAJL" 2>/dev/null)"; then
        env_frissit "BESZEL_KULCS" "$KULCS"
        ( cd "${PARK_DIR}/stackek/monitor" && docker compose --profile ugynok up -d >/dev/null 2>&1 ) \
            && ok "ügynök fut (a hub kulcsával)" || figy "az ügynök nem indult el"
    else
        figy "nincs meg a hub kulcsa – a webfelület Add System ablakából másold a .env BESZEL_KULCS sorába,"
        figy "  majd: cd ${PARK_DIR}/stackek/monitor && docker compose --profile ugynok up -d"
    fi
fi

vhost_ir "71-monitor" "http://monitor.${BELSO_DOMAIN} {
	reverse_proxy beszel:8090
}"

szolgaltatas_jegyzes "Beszel" "http://monitor.${BELSO_DOMAIN}" "első megnyitáskor fiók; Add System → Host: /beszel_socket/beszel.sock"

:
