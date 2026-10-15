#!/usr/bin/env bash

cim "Offline tudástár – Kiwix"

KIWIX_DIR="${KIWIX_DIR:-${ADAT_DIR}/kiwix}"
konyvtar "$KIWIX_DIR" 2775
env_frissit "KIWIX_DIR" "$KIWIX_DIR"

for zim in ${KIWIX_LETOLT:-}; do
    fajl="${zim##*/}"
    if [[ -f "${KIWIX_DIR}/${fajl}" ]]; then
        kihagy "$fajl"
        continue
    fi
    info "letöltés: $fajl (nagy fájl, eltarthat egy darabig)…"
    if fut curl -fL --retry 3 -C - -o "${KIWIX_DIR}/${fajl}.resz" "$zim"; then
        fut mv "${KIWIX_DIR}/${fajl}.resz" "${KIWIX_DIR}/${fajl}"
        ok "letöltve: $fajl"
    else
        figy "nem sikerült letölteni: $zim"
    fi
done

stack_telepit offline

if [[ "$PROBA" == "1" ]] || compgen -G "${KIWIX_DIR}/*.zim" >/dev/null; then
    stack_indit offline
else
    figy "még nincs .zim fájl itt: ${KIWIX_DIR} – addig a Kiwix nem indul."
    figy "  letölthető: https://download.kiwix.org/zim/  (pl. wikipedia/wikipedia_hu_all_nopic_*.zim)"
    figy "  bemásolás után: park indit offline"
fi

vhost_ir "69-offline" "http://wiki.${BELSO_DOMAIN} {
	reverse_proxy kiwix:8080
}"

szolgaltatas_jegyzes "Kiwix" "http://wiki.${BELSO_DOMAIN}" "offline Wikipédia; új .zim után: park ujra offline"

:
