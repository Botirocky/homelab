#!/usr/bin/env bash

cim "Állapot kijelzőknek – park-allapot"

van_parancs jq || csomag_telepit jq
konyvtar "${PARK_DIR}/web/allapot"

if [[ "$PROBA" == "1" ]]; then
    info "[próba] install park-allapot -> /usr/local/bin/ + időzítő (30 mp)"
else
    install -m 0755 "${TELEPITO_DIR}/skriptek/park-allapot" /usr/local/bin/park-allapot
    /usr/local/bin/park-allapot --telepit >/dev/null 2>&1 \
        && ok "park-allapot.timer bekapcsolva (30 mp-enként)" \
        || figy "az időzítő nem indult: systemctl status park-allapot.timer"
    /usr/local/bin/park-allapot || figy "az első futás nem sikerült: park-allapot --kiir"
fi

if [[ "$PROBA" == "1" ]]; then
    info "[próba] install park-gepek -> /usr/local/bin/ + park-gepek.service (port 8097, csak a helyi hálóról)"
else
    install -m 0755 "${TELEPITO_DIR}/skriptek/park-gepek" /usr/local/bin/park-gepek
    /usr/local/bin/park-gepek --telepit \
        && ok "park-gepek fut (VM-távirányító, port 8097; kulcs: park-gepek --kulcs)" \
        || figy "a park-gepek nem indult: systemctl status park-gepek"
fi

if [[ "$PROBA" == "1" ]]; then
    info "[próba] install park-ejszaka -> /usr/local/bin/ + park-ejszaka.service + /etc/park-ejszaka.conf"
else
    install -m 0755 "${TELEPITO_DIR}/skriptek/park-ejszaka" /usr/local/bin/park-ejszaka
    install -m 0644 "${TELEPITO_DIR}/sablonok/ejszaka/park-ejszaka.service" /etc/systemd/system/park-ejszaka.service
    [[ -f /etc/park-ejszaka.conf ]] || install -m 0644 "${TELEPITO_DIR}/sablonok/ejszaka/park-ejszaka.conf" /etc/park-ejszaka.conf
    systemctl daemon-reload
    ok "park-ejszaka kész (kíméletes éjszakai leállás; az ESP32 indítja: POST :8097/ejszaka/leallit)"
fi

alap_vhost_ir

szolgaltatas_jegyzes "VM-távirányító" "http://<szerver-ip>:8097/gepek" "X-Kulcs fejléccel; az ESP32 WoL-gomb ezzel indítja a VM-eket"
szolgaltatas_jegyzes "Állapot-JSON" "http://<szerver-ip>/allapot.json" "30 mp-enként frissül; az ESP32 kijelző ezt olvassa"

:
