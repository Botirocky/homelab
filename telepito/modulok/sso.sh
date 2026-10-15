#!/usr/bin/env bash

cim "Közös belépés (SSO) – Tinyauth"

if [[ "$PROBA" != "1" ]] && ! docker ps --format '{{.Names}}' | grep -qx park-caddy; then
    figy "nem fut a Caddy (park-caddy) – az SSO a proxy modul nélkül nem működik"
    return 0
fi

SSO_FELHASZNALO="${SMB_FELHASZNALO:-admin}"
SSO_JELSZO="$(titok SSO_JELSZO 20)"
SSO_VEDETT="${SSO_VEDETT:-$(env_ertek SSO_VEDETT 2>/dev/null || true)}"
SSO_VEDETT="${SSO_VEDETT//\"/}"
SSO_VEDETT="${SSO_VEDETT:-valtozas pdf eszkozok wiki}"
env_frissit "SSO_VEDETT" "$SSO_VEDETT"

stack_telepit sso
FELH="${PARK_DIR}/stackek/sso/felhasznalok"
if [[ "$PROBA" == "1" ]]; then
    info "[próba] felhasználó: ${SSO_FELHASZNALO}"
elif ! grep -q "^${SSO_FELHASZNALO}:" "$FELH" 2>/dev/null; then
    HASH="$(docker exec park-caddy caddy hash-password --plaintext "$SSO_JELSZO" 2>/dev/null || true)"
    if [[ -n "$HASH" ]]; then
        printf '%s:%s\n' "$SSO_FELHASZNALO" "$HASH" >>"$FELH"
        chmod 644 "$FELH"
        ok "SSO felhasználó: ${SSO_FELHASZNALO}"
    else
        hiba "nem sikerült jelszó-hasht készíteni"
        return 0
    fi
else
    kihagy "SSO felhasználó: ${SSO_FELHASZNALO}"
fi

stack_indit sso

vhost_ir "00-sso" "(sso) {
	forward_auth tinyauth:3000 {
		uri /api/auth/caddy
		copy_headers Remote-User Remote-Name Remote-Email Remote-Groups
	}
}

http://auth.${BELSO_DOMAIN} {
	reverse_proxy tinyauth:3000
}"

if [[ "$PROBA" != "1" ]]; then
    for f in "${PARK_DIR}"/stackek/proxy/sites.d/*.caddy; do
        [[ "$(basename "$f")" == "00-sso.caddy" ]] && continue
        sso_szur <"$f" >"${f}.uj" && mv "${f}.uj" "$f"
    done
fi
info "védett címek: $(for n in $SSO_VEDETT; do printf '%s.%s ' "$n" "$BELSO_DOMAIN"; done)"

szolgaltatas_jegyzes "Tinyauth (SSO)" "http://auth.${BELSO_DOMAIN}" "belépés: ${SSO_FELHASZNALO} (jelszó a .env-ben: SSO_JELSZO); lista: SSO_VEDETT"

:
