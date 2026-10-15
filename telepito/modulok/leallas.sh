#!/usr/bin/env bash

cim "Leállás – munkafolyamat mentése + Tapo-dugalj lekapcsolása"

KASA_FORRAS="${KASA_FORRAS:-python-kasa @ git+https://github.com/ZeliardM/python-kasa@e7084472972f08f2e2235b342f3964aedbfaeb3b}"

if [[ "$PROBA" == "1" ]]; then
    info "[próba] install park-leallas -> /usr/local/bin/ + park-leallas.service + system-shutdown horog"
    info "[próba] python-kasa (TPAP) -> /opt/park-kasa venv; hitelesítés: /etc/park-dugalj.env"
else
    van_parancs git || csomag_telepit git
    csomag_van python3-venv || csomag_telepit python3-venv
    install -m 0755 "${TELEPITO_DIR}/skriptek/park-leallas" /usr/local/bin/park-leallas
    install -D -m 0644 "${TELEPITO_DIR}/sablonok/leallas/park-dugalj-idozito.py" /usr/local/lib/park/park-dugalj-idozito.py
    install -D -m 0755 "${TELEPITO_DIR}/sablonok/leallas/park-dugalj-horog" /usr/lib/systemd/system-shutdown/park-dugalj
    install -m 0644 "${TELEPITO_DIR}/sablonok/leallas/park-leallas.service" /etc/systemd/system/park-leallas.service
    [[ -f /etc/park-leallas.conf ]] || install -m 0644 "${TELEPITO_DIR}/sablonok/leallas/park-leallas.conf" /etc/park-leallas.conf

    if [[ ! -x /opt/park-kasa/bin/python ]]; then
        python3 -m venv /opt/park-kasa
    fi
    if /opt/park-kasa/bin/pip install -q "$KASA_FORRAS"; then
        ok "python-kasa (TPAP-ág) telepítve: /opt/park-kasa"
    else
        figy "a python-kasa nem települt – a dugalj lekapcsolása nem fog menni"
    fi

    install -d -m 0700 /etc/park-leallas
    [[ -f /etc/park-leallas/nagygep_ed25519 ]] || ssh-keygen -q -t ed25519 -N "" -C "picloud-park-leallas" -f /etc/park-leallas/nagygep_ed25519
    info "a nagygépen ehhez a kulcshoz ez a sor kell a /root/.ssh/authorized_keys-be (+ /usr/local/sbin/park-tavoli-leallas):"
    info "  command=\"/usr/local/sbin/park-tavoli-leallas\",restrict $(cat /etc/park-leallas/nagygep_ed25519.pub)"

    systemctl daemon-reload
    systemctl enable --now park-leallas.service >/dev/null 2>&1 \
        && ok "park-leallas.service aktív (leálláskor ment, indításkor visszaállít)" \
        || figy "a park-leallas.service nem indult: systemctl status park-leallas"

    if [[ -r /etc/park-dugalj.env ]]; then
        ok "dugalj-hitelesítés megvan: /etc/park-dugalj.env"
    else
        figy "nincs /etc/park-dugalj.env (minta: sablonok/leallas/park-dugalj.env.pelda, 0600) – addig a dugalj nem kapcsol le"
    fi
fi
