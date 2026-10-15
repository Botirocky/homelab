#!/usr/bin/env bash
# Modul: saját weboldalak kiszolgálása
# Statikus oldalak (HTML/CSS/JS) automatikus HTTPS-sel. Új oldal felvétele
# később egyetlen paranccsal:  park oldal pelda.hu

cim "Weboldal-hosting"

konyvtar "${PARK_DIR}/web"

# --- minta/kezdő oldal -------------------------------------------------------
OLDAL_DIR="${PARK_DIR}/web/${PUBLIKUS_DOMAIN:-alap}"
konyvtar "$OLDAL_DIR"

if [[ ! -f "${OLDAL_DIR}/index.html" ]]; then
    cat <<'HTML' | fajlt_ir "${OLDAL_DIR}/index.html"
<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Működik</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; min-height:100vh; display:grid; place-items:center;
         background:#0e1512; color:#e8f0ea;
         font:16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif; }
  .doboz { text-align:center; padding:2rem; }
  h1 { margin:0 0 .5rem; font-size:clamp(1.8rem,5vw,2.6rem); }
  code { background:#1b2620; padding:.2em .5em; border-radius:6px; }
  p { color:#9fb3a7; }
</style>
</head>
<body>
  <div class="doboz">
    <h1>A szerver él.</h1>
    <p>Ez az oldal innen jön: <code>__MAPPA__</code></p>
    <p>Cseréld le a fájlokat, és kész.</p>
  </div>
</body>
</html>
HTML
    [[ "$PROBA" != "1" ]] && sed -i "s#__MAPPA__#${OLDAL_DIR}#" "${OLDAL_DIR}/index.html"
    ok "minta oldal létrehozva: ${OLDAL_DIR}"
fi

# --- publikus domain (igazi HTTPS) ------------------------------------------
if [[ -n "$PUBLIKUS_DOMAIN" ]]; then
    vhost_ir "50-web-${PUBLIKUS_DOMAIN}" "${PUBLIKUS_DOMAIN}, www.${PUBLIKUS_DOMAIN} {
	root * /srv/web/${PUBLIKUS_DOMAIN}
	file_server
	encode gzip zstd

	# Biztonsági fejlécek
	header {
		Strict-Transport-Security \"max-age=31536000\"
		X-Content-Type-Options nosniff
		Referrer-Policy strict-origin-when-cross-origin
		-Server
	}

	handle_errors {
		respond \"{err.status_code} – {err.status_text}\"
	}
}"
    ok "publikus oldal beállítva: https://${PUBLIKUS_DOMAIN}"
    figy "Ehhez kell: a domain A-rekordja erre az IP-re mutasson, és a routeren"
    figy "a 80-as és 443-as port legyen átirányítva a szerverre."
    szolgaltatas_jegyzes "Weboldal" "https://${PUBLIKUS_DOMAIN}" "fájlok: ${PARK_DIR}/web/${PUBLIKUS_DOMAIN}"
else
    vhost_ir "50-web-belso" "http://web.${BELSO_DOMAIN} {
	root * /srv/web/alap
	file_server
	encode gzip
}"
    szolgaltatas_jegyzes "Weboldal (belső)" "http://web.${BELSO_DOMAIN}" "fájlok: ${PARK_DIR}/web/alap"
fi

info "Új oldal felvétele később:  park oldal <domain>"

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
