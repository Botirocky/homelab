#!/usr/bin/env bash

cim "Saját botok (Python) konténerben"

BOTOK_DIR="${BOTOK_DIR:-${PARK_DIR}/botok}"
konyvtar "$BOTOK_DIR" 2775
env_frissit "BOTOK_DIR" "$BOTOK_DIR"
STACK="${PARK_DIR}/stackek/botok"
konyvtar "$STACK"

bot_belepes() {
    local d="$1" f
    if [[ -f "$d/.belepes" ]]; then
        head -1 "$d/.belepes" | tr -d '\r'
        return
    fi
    for f in bot.py main.py app.py __main__.py; do
        [[ -f "$d/$f" ]] && { printf '%s' "$f"; return 0; }
    done
    return 0
}

BOTOK=()
while IFS= read -r d; do
    [[ -f "$d/requirements.txt" ]] || continue
    nev="$(basename "$d" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')"
    belepes="$(bot_belepes "$d")"
    if [[ -z "$belepes" ]]; then
        figy "$(basename "$d"): nincs bot.py/main.py/app.py, és .belepes fájl sem – kihagyva"
        continue
    fi
    python_verzio="3.12"
    [[ -f "$d/.python-version" ]] && python_verzio="$(head -1 "$d/.python-version" | tr -dc '0-9.')"
    BOTOK+=("${nev}|${d}|${belepes}|${python_verzio}")
done < <(find "$BOTOK_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if (( ${#BOTOK[@]} == 0 )); then
    info "még nincs bot a ${BOTOK_DIR} mappában. Egy bot = egy almappa, benne:"
    info "  requirements.txt + bot.py (vagy main.py / app.py, vagy .belepes fájlban a név)"
    info "  a titkok mehetnek a mappa .env fájljába; utána: sudo ./telepito.sh --csak botok"
    szolgaltatas_jegyzes "Botok" "$BOTOK_DIR" "még üres – másold be a botjaidat"
    return 0
fi

{
    echo "services:"
    for sor in "${BOTOK[@]}"; do
        IFS='|' read -r nev d belepes python_verzio <<<"$sor"
        cat <<SVC
  bot-${nev}:
    build:
      context: ${d}
      dockerfile_inline: |
        FROM python:${python_verzio}-slim
        WORKDIR /app
        COPY requirements.txt /tmp/requirements.txt
        RUN pip install --no-cache-dir -r /tmp/requirements.txt
        CMD ["python", "-u", "${belepes}"]
    image: park-bot-${nev}:helyi
    container_name: park-bot-${nev}
    restart: unless-stopped
    working_dir: /app
    volumes:
      - ${d}:/app
    env_file:
      - path: ${d}/.env
        required: false
    environment:
      TZ: \${TZ}
      PYTHONUNBUFFERED: "1"
    networks: [park]

SVC
    done
    cat <<'NET'
networks:
  park:
    external: true
NET
} | fajlt_ir "${STACK}/compose.yml"

[[ "$PROBA" != "1" ]] && ln -sfn "${PARK_DIR}/.env" "${STACK}/.env"

if [[ "$PROBA" != "1" ]]; then
    info "botok építése és indítása…"
    ( cd "$STACK" && docker compose up -d --build --remove-orphans ) \
        && ok "fut: ${#BOTOK[@]} bot" || hiba "a botok nem indultak el: park naplo botok"
fi

for sor in "${BOTOK[@]}"; do
    IFS='|' read -r nev d belepes _ <<<"$sor"
    szolgaltatas_jegyzes "bot: ${nev}" "(konténer: park-bot-${nev})" "${d}/${belepes}"
done

:
