#!/usr/bin/env bash
# Modul: self-hosting alapkészlet
# Dockge (stack-kezelő), Uptime Kuma (figyelés), Homepage (kezdőlap),
# Vaultwarden (jelszókezelő), Forgejo (saját git).

cim "Self-hosting készlet"

titok VAULTWARDEN_ADMIN_TOKEN 48 >/dev/null
for d in dockge uptime-kuma vaultwarden forgejo; do konyvtar "${ADAT_DIR}/${d}"; done

stack_telepit selfhost
stack_telepit git

# --- Homepage kezdőlap tartalma ---------------------------------------------
HP="${PARK_DIR}/stackek/selfhost/homepage"
konyvtar "$HP"

cat <<HPS | fajlt_ir "${HP}/settings.yaml"
title: Szerverpark
theme: dark
color: slate
headerStyle: clean
layout:
  AI:
    style: row
    columns: 2
  Média:
    style: row
    columns: 2
  Fájlok:
    style: row
    columns: 3
  Iratok:
    style: row
    columns: 3
  Otthon:
    style: row
    columns: 3
  Olvasás:
    style: row
    columns: 4
  Eszközök:
    style: row
    columns: 3
  Rendszer:
    style: row
    columns: 3
HPS

van() {
    [[ "${FUSSON[$1]:-0}" == "1" ]] && return 0
    [[ -d "${PARK_DIR}/stackek/$1" ]] && return 0
    return 1
}

{
    if van ai; then
        cat <<HPSV
- AI:
    - Open WebUI:
        href: http://ai.${BELSO_DOMAIN}
        description: Helyi AI beszélgetés (Ollama)
        icon: ollama.png
    - Kereső:
        href: http://kereso.${BELSO_DOMAIN}
        description: SearXNG – reklám és követés nélkül
        icon: searxng.png
    - AI API:
        href: http://ai-api.${BELSO_DOMAIN}
        description: OpenAI-kompatibilis végpont (LiteLLM)
        icon: litellm.png
HPSV
    fi

    if van media; then
        cat <<HPSV

- Média:
    - Jellyfin:
        href: http://media.${BELSO_DOMAIN}
        description: Filmek és sorozatok
        icon: jellyfin.png
    - Navidrome:
        href: http://zene.${BELSO_DOMAIN}
        description: Zene bárhonnan
        icon: navidrome.png
HPSV
    fi

    if van fajlok || van szinkron || van samba; then
        printf '\n- Fájlok:\n'
        van fajlok && cat <<HPSV
    - Nextcloud:
        href: http://felho.${BELSO_DOMAIN}
        description: Saját felhő, telefonos szinkronnal
        icon: nextcloud.png
HPSV
        (van fajlok || van szinkron) && cat <<HPSV
    - FileBrowser:
        href: http://fajlok.${BELSO_DOMAIN}
        description: Gyors webes fájlkezelő
        icon: filebrowser.png
HPSV
        van szinkron && cat <<HPSV
    - Syncthing:
        href: http://szinkron.${BELSO_DOMAIN}
        description: Eszközök közti szinkron
        icon: syncthing.png
HPSV
    fi

    if van iratok; then
        cat <<HPSV

- Iratok:
    - Paperless:
        href: http://iratok.${BELSO_DOMAIN}
        description: Iratok, számlák – kereshetően
        icon: paperless-ngx.png
    - Linkding:
        href: http://konyvjelzo.${BELSO_DOMAIN}
        description: Könyvjelzők
        icon: linkding.png
    - Wallabag:
        href: http://olvaso.${BELSO_DOMAIN}
        description: Cikkek későbbre
        icon: wallabag.png
HPSV
    fi

    if van otthon || van fotok || van penz || van orarend; then
        printf '\n- Otthon:\n'
        if van orarend; then
            ORAREND_HREF="http://orarend.${BELSO_DOMAIN}"
            if [[ "$PROBA" != "1" ]] && tailscale serve status 2>/dev/null | grep -q ":${ORAREND_TS_PORT:-8444} "; then
                ORAREND_HREF="$(tailscale serve status 2>/dev/null | grep -o "https://[^ ]*:${ORAREND_TS_PORT:-8444}" | head -1)"
            fi
            cat <<HPSV
    - Órarend:
        href: ${ORAREND_HREF}
        description: Kréta-órarend, helyettesítések, dolgozatok
        icon: mdi-school
        widget:
          type: customapi
          url: http://orarend:8080/api/kezdolap?k=$(env_ertek ORAREND_ICS_KULCS 2>/dev/null | tr -d '"')
          refreshInterval: 60000
          mappings:
            - field: most
              label: Most
            - field: kovetkezo
              label: Következő
            - field: szamonkeres
              label: Dolgozat
HPSV
        fi
        van otthon && cat <<HPSV
    - Home Assistant:
        href: http://otthon.${BELSO_DOMAIN}
        description: Okosotthon, szenzorok
        icon: home-assistant.png
HPSV
        van fotok && cat <<HPSV
    - Immich:
        href: http://fotok.${BELSO_DOMAIN}
        description: Fotók és videók
        icon: immich.png
HPSV
        van penz && cat <<HPSV
    - Actual Budget:
        href: https://penz.${BELSO_DOMAIN}
        description: Költségvetés
        icon: actual-budget.png
HPSV
    fi

    if van konyvek || van hirek || van offline; then
        printf '\n- Olvasás:\n'
        van konyvek && cat <<HPSV
    - Kavita:
        href: http://konyvek.${BELSO_DOMAIN}
        description: E-könyvek, képregények
        icon: kavita.png
    - Audiobookshelf:
        href: http://hangoskonyv.${BELSO_DOMAIN}
        description: Hangoskönyvek, podcastok
        icon: audiobookshelf.png
HPSV
        van hirek && cat <<HPSV
    - Miniflux:
        href: http://hirek.${BELSO_DOMAIN}
        description: Hírek (RSS)
        icon: miniflux.png
HPSV
        van offline && cat <<HPSV
    - Kiwix:
        href: http://wiki.${BELSO_DOMAIN}
        description: Offline Wikipédia
        icon: kiwix.png
HPSV
    fi

    if van eszkozok || van hirek; then
        printf '\n- Eszközök:\n'
        van eszkozok && cat <<HPSV
    - Stirling-PDF:
        href: http://pdf.${BELSO_DOMAIN}
        description: PDF-műveletek helyben
        icon: stirling-pdf.png
    - IT-Tools:
        href: http://eszkozok.${BELSO_DOMAIN}
        description: Fejlesztői apróságok
        icon: it-tools.png
HPSV
        van hirek && cat <<HPSV
    - changedetection:
        href: http://valtozas.${BELSO_DOMAIN}
        description: Weboldalak változásai
        icon: changedetection-io.png
HPSV
    fi

    printf '\n- Rendszer:\n'
    cat <<HPSV
    - Dockge:
        href: http://dockge.${BELSO_DOMAIN}
        description: Konténer-stackek kezelése
        icon: dockge.png
    - Uptime Kuma:
        href: http://figyelo.${BELSO_DOMAIN}
        description: Mi él, mi halott
        icon: uptime-kuma.png
    - Vaultwarden:
        href: http://jelszo.${BELSO_DOMAIN}
        description: Jelszókezelő
        icon: vaultwarden.png
    - Git (Forgejo):
        href: http://git.${BELSO_DOMAIN}
        description: Saját git szerver
        icon: forgejo.png
HPSV
    [[ -f /etc/cockpit/cockpit.conf ]] && cat <<HPSV
    - Cockpit:
        href: http://vm.${BELSO_DOMAIN}
        description: Gép és VM-ek webről
        icon: cockpit.png
HPSV
    van karbantartas && cat <<HPSV
    - Dozzle:
        href: http://naplo.${BELSO_DOMAIN}
        description: Konténer-naplók
        icon: dozzle.png
    - Speedtest:
        href: http://sebesseg.${BELSO_DOMAIN}
        description: Internet sebessége
        icon: speedtest-tracker.png
HPSV
    van monitor && cat <<HPSV
    - Beszel:
        href: http://monitor.${BELSO_DOMAIN}
        description: Erőforrás-grafikonok
        icon: beszel.png
HPSV
    van sso && cat <<HPSV
    - Tinyauth:
        href: http://auth.${BELSO_DOMAIN}
        description: Közös belépés
        icon: tinyauth.png
HPSV
    if [[ -f "${HP}/services-extra.yaml" ]]; then
        printf '\n'
        cat "${HP}/services-extra.yaml"
    fi
} | fajlt_ir "${HP}/services.yaml"
if [[ "$PROBA" != "1" ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx park-homepage; then
    curl -s -m10 http://127.0.0.1:3002/api/revalidate >/dev/null 2>&1 || true
fi

# A kereső a saját SearXNG-t használja, ha van – így a kezdőlapról indított
# keresés sem megy ki egy külső szolgáltatóhoz.
if van ai; then
    KERESO_BLOKK="- search:
    provider: custom
    url: http://kereso.${BELSO_DOMAIN}/search?q=
    target: _blank"
else
    KERESO_BLOKK="- search:
    provider: duckduckgo
    target: _blank"
fi
# A tárolók a konténerbe /tarolok alatt vannak becsatolva (lásd compose).
TAROLO_WIDGET=""
if [[ -d "${TAROLO_DIR:-/srv/tarolok}" ]]; then
    while read -r t; do
        [[ -z "$t" ]] && continue
        TAROLO_WIDGET="${TAROLO_WIDGET}
- resources:
    label: $(basename "$t")
    disk: /tarolok/$(basename "$t")"
    done < <(find "${TAROLO_DIR:-/srv/tarolok}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -3)
fi

cat <<HPW | fajlt_ir "${HP}/widgets.yaml"
- greeting:
    text_size: xl
    text: ${GEPNEV:-$(hostname)}

- resources:
    label: gép
    cpu: true
    memory: true
    cputemp: true
    uptime: true
    tempmin: 0
    tempmax: 85

- resources:
    label: rendszerlemez
    disk: /
${TAROLO_WIDGET}

${KERESO_BLOKK}
HPW

: | fajlt_ir "${HP}/bookmarks.yaml"
: | fajlt_ir "${HP}/docker.yaml"

stack_indit selfhost
stack_indit git

vhost_ir "30-selfhost" "http://dockge.${BELSO_DOMAIN} {
	reverse_proxy dockge:5001
}

http://figyelo.${BELSO_DOMAIN} {
	reverse_proxy uptime-kuma:3001
}

http://kezdolap.${BELSO_DOMAIN} {
	reverse_proxy homepage:3000
}

http://jelszo.${BELSO_DOMAIN} {
	reverse_proxy vaultwarden:80
}

http://git.${BELSO_DOMAIN} {
	reverse_proxy forgejo:3000
}"

szolgaltatas_jegyzes "Kezdőlap"     "http://kezdolap.${BELSO_DOMAIN}" "innen minden elérhető"
szolgaltatas_jegyzes "Dockge"       "http://dockge.${BELSO_DOMAIN}"   "stackek indítása/leállítása"
szolgaltatas_jegyzes "Uptime Kuma"  "http://figyelo.${BELSO_DOMAIN}"  "állítsd be az értesítést"
szolgaltatas_jegyzes "Vaultwarden"  "http://jelszo.${BELSO_DOMAIN}"   "regisztrálj, aztán tiltsd le a regisztrációt"
szolgaltatas_jegyzes "Forgejo"      "http://git.${BELSO_DOMAIN}"      "git: ssh -p 2222"

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
