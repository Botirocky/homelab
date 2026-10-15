#!/usr/bin/env bash

cim "Lemezegészség – Scrutiny (S.M.A.R.T.)"

for d in scrutiny/config scrutiny/influxdb; do konyvtar "${ADAT_DIR}/${d}"; done
csomag_telepit smartmontools >/dev/null 2>&1 || true

stack_telepit lemez

LEMEZEK=()
if [[ "$PROBA" != "1" ]]; then
    while read -r nev tip; do
        [[ "$tip" == "disk" ]] || continue
        case "$nev" in zram*|loop*|sr*|mmcblk*boot*) continue ;; esac
        LEMEZEK+=("/dev/${nev}")
    done < <(lsblk -dno NAME,TYPE 2>/dev/null)
fi

if [[ ${#LEMEZEK[@]} -eq 0 && "$PROBA" != "1" ]]; then
    figy "nem találtam S.M.A.R.T.-képes lemezt – a Scrutiny kimarad"
    return 0
fi

{
    echo "services:"
    echo "  scrutiny:"
    echo "    devices:"
    for l in "${LEMEZEK[@]}"; do echo "      - \"${l}\""; done
} | fajlt_ir "${PARK_DIR}/stackek/lemez/compose.override.yml"

NTFY="${NTFY_URL:-}"
if [[ -n "$NTFY" ]]; then
    NTFY_SHOUTRRR="ntfy://${NTFY#https://}"
    NTFY_SHOUTRRR="${NTFY_SHOUTRRR#ntfy://http://}"
    cat <<YAML | fajlt_ir "${ADAT_DIR}/scrutiny/config/scrutiny.yaml"
version: 1
web:
  listen:
    port: 8080
    host: 0.0.0.0
  database:
    location: /opt/scrutiny/config/scrutiny.db
  src:
    frontend:
      path: /opt/scrutiny/web
  influxdb:
    host: 0.0.0.0
    port: 8086
    retention_policy: true
log:
  level: INFO
notify:
  urls:
    - "${NTFY_SHOUTRRR}?title=Lemezhiba%20($(hostname))&tags=floppy_disk"
YAML
fi

stack_indit lemez

if [[ "$PROBA" != "1" ]] && konteneret_var park-scrutiny 60; then
    sleep 20
    docker exec park-scrutiny /opt/scrutiny/bin/scrutiny-collector-metrics run >/dev/null 2>&1 \
        && ok "első S.M.A.R.T.-mérés kész (${LEMEZEK[*]})" \
        || figy "az első mérés nem futott le – 6 óránként magától is mér"
fi

vhost_ir "74-lemez" "http://lemez.${BELSO_DOMAIN} {
	reverse_proxy scrutiny:8080
}"

szolgaltatas_jegyzes "Scrutiny" "http://lemez.${BELSO_DOMAIN}" "lemezek S.M.A.R.T. állapota, hőfok; hibánál ntfy"

:
