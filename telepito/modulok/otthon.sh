#!/usr/bin/env bash

cim "Okosotthon – Home Assistant + MQTT"

HA_DIR="${ADAT_DIR}/homeassistant"
MQ_DIR="${ADAT_DIR}/mosquitto"
konyvtar "$HA_DIR"
for d in config data log; do konyvtar "${MQ_DIR}/${d}"; done

MQTT_FELHASZNALO="${SMB_FELHASZNALO:-park}"
env_beallit "MQTT_FELHASZNALO" "$MQTT_FELHASZNALO"
MQTT_FELHASZNALO="$(env_ertek MQTT_FELHASZNALO 2>/dev/null || true)"
MQTT_FELHASZNALO="${MQTT_FELHASZNALO:-${SMB_FELHASZNALO:-park}}"
MQTT_JELSZO="$(titok MQTT_JELSZO 24)"

if [[ ! -f "${HA_DIR}/configuration.yaml" ]]; then
    cat <<'HACONF' | fajlt_ir "${HA_DIR}/configuration.yaml"
default_config:

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
    - 127.0.0.1

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
HACONF
    echo "[]" | fajlt_ir "${HA_DIR}/automations.yaml"
    : | fajlt_ir "${HA_DIR}/scripts.yaml"
    : | fajlt_ir "${HA_DIR}/scenes.yaml"
else
    kihagy "Home Assistant konfig"
fi

if [[ ! -f "${MQ_DIR}/config/mosquitto.conf" ]]; then
    cat <<'MQCONF' | fajlt_ir "${MQ_DIR}/config/mosquitto.conf"
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest stdout
MQCONF
fi
if [[ "$PROBA" != "1" ]]; then
    [[ -f "${MQ_DIR}/config/passwd" ]] || install -m 0600 /dev/null "${MQ_DIR}/config/passwd"
    chown -R 1883:1883 "$MQ_DIR"
fi

stack_telepit otthon
stack_indit otthon

if [[ "$PROBA" != "1" ]] && konteneret_var park-mosquitto 60; then
    if grep -q "^${MQTT_FELHASZNALO}:" "${MQ_DIR}/config/passwd" 2>/dev/null; then
        kihagy "MQTT felhasználó: ${MQTT_FELHASZNALO}"
    elif docker exec -u 1883 park-mosquitto mosquitto_passwd -b /mosquitto/config/passwd \
            "$MQTT_FELHASZNALO" "$MQTT_JELSZO" >/dev/null 2>&1; then
        docker restart park-mosquitto >/dev/null
        ok "MQTT felhasználó létrehozva: ${MQTT_FELHASZNALO}"
    else
        figy "az MQTT felhasználót nem sikerült létrehozni"
    fi
fi

vhost_ir "64-otthon" "http://otthon.${BELSO_DOMAIN} {
	reverse_proxy homeassistant:8123
}"

szolgaltatas_jegyzes "Home Assistant" "http://otthon.${BELSO_DOMAIN}" "első megnyitáskor fiók; MQTT integráció: mosquitto:1883"
szolgaltatas_jegyzes "MQTT (Mosquitto)" "mqtt://<szerver-ip>:1883" "felhasználó: ${MQTT_FELHASZNALO}, jelszó a .env-ben (MQTT_JELSZO)"

:
