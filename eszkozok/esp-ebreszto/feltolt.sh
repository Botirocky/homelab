#!/usr/bin/env bash
set -euo pipefail

MAPPA="$(cd "$(dirname "$0")" && pwd)"
FQBN="esp32:esp32:adafruit_feather_esp32_v2"
TITKOK="${MAPPA}/titkok.h"

sugo() {
    cat <<'SUGO'
feltolt.sh – a ébresztő (WoL-gomb) fordítása és feltöltése

  ./feltolt.sh titkok              titkok.h létrehozása (WiFi a laptopról, webes kulcs, a Pi park-gepek kulcsa)
  ./feltolt.sh forditas            csak fordítás
  ./feltolt.sh usb [/dev/ttyACM0]  fordítás + feltöltés USB-n
  ./feltolt.sh ota [ebreszto.local]  fordítás + feltöltés WiFi-n (ha már fut rajta az őrszem)
  ./feltolt.sh figyel [/dev/ttyACM0]  soros napló
SUGO
}

veletlen() { head -c 64 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$1"; }

titkok() {
    if [[ -f "$TITKOK" ]]; then
        echo "titkok.h már megvan, nem írom felül: $TITKOK"
        return
    fi
    local ssid jelszo
    ssid="${WIFI_SSID:-$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')}"
    jelszo="${WIFI_JELSZO:-$(nmcli -s -g 802-11-wireless-security.psk connection show "$ssid")}"
    umask 077
    {
        echo "#pragma once"
        echo "#define WIFI_SSID \"${ssid}\""
        echo "#define WIFI_JELSZO \"${jelszo}\""
        echo "#define WEB_KULCS \"$(veletlen 12)\""
        echo "#define GEPEK_KULCS \"$(ssh picloud 'sudo park-gepek --kulcs')\""
    } > "$TITKOK"
    echo "titkok.h kész: $TITKOK"
}

forditas() {
    [[ -f "$TITKOK" ]] || titkok
    arduino-cli compile --fqbn "$FQBN" --export-binaries "$MAPPA"
    chmod -R go-rwx "${MAPPA}/build"
}

case "${1:-}" in
    titkok) titkok ;;
    forditas) forditas ;;
    usb)
        forditas
        arduino-cli upload --fqbn "$FQBN" -p "${2:-/dev/ttyACM0}" "$MAPPA"
        ;;
    ota)
        forditas
        kulcs="$(sed -n 's/^#define WEB_KULCS "\(.*\)"/\1/p' "$TITKOK")"
        espota="$(find ~/.arduino15/packages/esp32/hardware/esp32 -name espota.py | sort -V | tail -1)"
        python3 "$espota" -i "${2:-ebreszto.local}" -P 47123 -a "$kulcs" -f "${MAPPA}/build/esp32.esp32.adafruit_feather_esp32_v2/ebreszto.ino.bin" -r
        ;;
    figyel) arduino-cli monitor -p "${2:-/dev/ttyACM0}" -c baudrate=115200 ;;
    *) sugo ;;
esac
