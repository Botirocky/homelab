#!/usr/bin/env bash
set -euo pipefail

MAPPA="$(cd "$(dirname "$0")" && pwd)"
TITKOK="${MAPPA}/pico/titkok.py"
MPREMOTE=(uvx mpremote)

sugo() {
    cat <<'SUGO'
feltolt.sh – biztonsági őr (Pico WH + picloud)

  ./feltolt.sh titkok        pico/titkok.py létrehozása (WiFi a laptopról, kulcs a Pi-ről vagy új)
  ./feltolt.sh pico          ssd1306 + sdcard meghajtó + main.py + web.html + titkok.py a Picóra (USB), újraindítás
  ./feltolt.sh pi [cím]      park-or telepítése a picloudra (cím: a Pico IP:port-ja, alap or.local:8080)
  ./feltolt.sh naplo         a Pico soros kimenete (kilépés: Ctrl+X)
  ./feltolt.sh teszt         próbariasztás a Pi-ről
  ./feltolt.sh sdnaplo [N]   a Pico SD-naplójának utolsó N sora
  ./feltolt.sh ki | be       az őr ki-/bekapcsolása WiFi-n (PICO_CIM, alap 192.168.1.20:8080)
SUGO
}

veletlen() { head -c 64 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$1"; }

titkok() {
    if [[ -f "$TITKOK" ]]; then
        echo "titkok.py már megvan, nem írom felül: $TITKOK"
        return
    fi
    local ssid jelszo kulcs
    ssid="${WIFI_SSID:-$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')}"
    jelszo="${WIFI_JELSZO:-$(nmcli -s -g 802-11-wireless-security.psk connection show "$ssid")}"
    kulcs="$(ssh -o BatchMode=yes -o ConnectTimeout=5 picloud 'sudo park-or --kulcs' 2>/dev/null || true)"
    [[ -n "$kulcs" ]] || kulcs="$(veletlen 24)"
    umask 077
    cat > "$TITKOK" <<EOF
WIFI_SSID = "${ssid}"
WIFI_JELSZO = "${jelszo}"
KULCS = "${kulcs}"
PORT = 8080
NEV = "or"
EOF
    echo "titkok.py kész: $TITKOK"
}

kapcsol() {
    local cim="${PICO_CIM:-192.168.1.20:8080}"
    curl -fsS -m 5 -X POST -H "X-Kulcs: $(kulcs_titkokbol)" "http://${cim}/$1"
    echo
}

kulcs_titkokbol() { sed -n 's/^KULCS = "\(.*\)"/\1/p' "$TITKOK"; }

pico() {
    [[ -f "$TITKOK" ]] || titkok
    "${MPREMOTE[@]}" connect auto mip install ssd1306 sdcard
    "${MPREMOTE[@]}" connect auto exec "import os
try:
    os.rename('main.py', 'main_ki.py')
except OSError:
    pass" + reset
    sleep 3
    "${MPREMOTE[@]}" connect auto cp "${MAPPA}/pico/web.html" "$TITKOK" : + cp "${MAPPA}/pico/main.py" :main.py + exec "import os
try:
    os.remove('main_ki.py')
except OSError:
    pass" + reset
    echo "Feltöltve. Böngészőben: http://<a Pico IP-je>:8080/"
}

pi() {
    [[ -f "$TITKOK" ]] || titkok
    local cim="${1:-or.local:8080}" kulcs
    kulcs="$(kulcs_titkokbol)"
    scp -q "${MAPPA}/pi/park-or" picloud:/tmp/park-or
    ssh -t picloud "sudo install -m 755 /tmp/park-or /usr/local/bin/park-or && rm /tmp/park-or && \
        if [ ! -f /etc/park-or.conf ]; then echo '${cim}' | sudo PARK_OR_KULCS='${kulcs}' PARK_OR_MAC='${PICO_MAC:-}' park-or --telepit; \
        else sudo park-or --telepit; fi"
}

case "${1:-}" in
    titkok) titkok ;;
    pico) pico ;;
    pi) pi "${2:-}" ;;
    naplo) "${MPREMOTE[@]}" connect auto repl ;;
    teszt) ssh picloud 'sudo park-or --teszt' ;;
    ki) kapcsol kikapcs ;;
    be) kapcsol bekapcs ;;
    sdnaplo) ssh picloud "sudo park-or --naplo ${2:-50}" ;;
    *) sugo ;;
esac
