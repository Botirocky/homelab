#!/usr/bin/env bash
# Modul: karbantartás – konténer-frissítés (Watchtower), naplók (Dozzle),
# internet-sebesség mérése (Speedtest Tracker).

cim "Karbantartás és felügyelet"

for d in speedtest; do konyvtar "${ADAT_DIR}/${d}"; done

if [[ -z "$(env_ertek SPEEDTEST_APP_KEY 2>/dev/null || true)" ]]; then
    env_beallit "SPEEDTEST_APP_KEY" "base64:$(openssl rand -base64 32)"
fi

# A Watchtower csak a címkézett konténereket frissíti – a Pi-hole-hoz és a
# kézzel rögzített verziójú stackekhez nem nyúl.
NTFY_CIM="${NTFY_URL:-$(env_ertek NTFY_URL 2>/dev/null || true)}"
if [[ -n "$NTFY_CIM" ]]; then
    env_beallit "WATCHTOWER_NTFY" "ntfy://${NTFY_CIM#https://}?scheme=https"
else
    env_beallit "WATCHTOWER_NTFY" ""
fi
env_beallit "GEPNEV" "$(hostname)"

stack_telepit karbantartas
stack_indit karbantartas

# A Dozzle MINDEN konténer naplóját megmutatja (jelszavak, tokenek is
# átfuthatnak rajta), saját bejelentkezése viszont nincs. Ezért a proxy elé
# teszünk egy jelszót. A hasht a Caddy generálja, a jelszó a .env-be kerül.
DOZZLE_JELSZO="$(titok DOZZLE_JELSZO 20)"
DOZZLE_HASH=""
if [[ "$PROBA" != "1" ]] && docker ps --format '{{.Names}}' | grep -qx park-caddy; then
    DOZZLE_HASH="$(docker exec park-caddy caddy hash-password --plaintext "$DOZZLE_JELSZO" 2>/dev/null || true)"
fi

if [[ -n "$DOZZLE_HASH" ]]; then
    NAPLO_BLOKK="http://naplo.${BELSO_DOMAIN} {
	basic_auth {
		${SMB_FELHASZNALO:-admin} ${DOZZLE_HASH}
	}
	reverse_proxy dozzle:8080
}"
    ok "a napló-nézegető jelszót kapott (felhasználó: ${SMB_FELHASZNALO:-admin})"
else
    NAPLO_BLOKK="http://naplo.${BELSO_DOMAIN} {
	reverse_proxy dozzle:8080
}"
fi

vhost_ir "61-karbantartas" "${NAPLO_BLOKK}

http://sebesseg.${BELSO_DOMAIN} {
	reverse_proxy speedtest:80
}"

szolgaltatas_jegyzes "Watchtower" "(nincs felülete)"                  "vasárnap 4:30 frissíti a címkézett konténereket"
szolgaltatas_jegyzes "Dozzle"     "http://naplo.${BELSO_DOMAIN}"      "konténer-naplók; belépés: ${SMB_FELHASZNALO:-admin} (jelszó a .env-ben)"
szolgaltatas_jegyzes "Speedtest"  "http://sebesseg.${BELSO_DOMAIN}"   "6 óránként méri az internetet"

:
