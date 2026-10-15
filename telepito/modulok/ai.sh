#!/usr/bin/env bash
# Modul: AI
#   • Ollama      – helyi modellek (a katalógusból, a vashoz méretezve)
#   • LiteLLM     – átjáró a felhős modellekhez (Claude, GPT, Gemini, …)
#   • Open WebUI  – közös felület mindkettőhöz, webkereséssel és RAG-gal
#   • SearXNG     – a webkereséshez
#   • ComfyUI     – képgenerálás (opcionális)

cim "AI – helyi modellek + felhős átjáró"

titok WEBUI_SECRET 40 >/dev/null
LITELLM_KULCS="$(titok LITELLM_KULCS 32)"
env_beallit "AI_BEAGYAZO" "${AI_BEAGYAZO:-nomic-embed-text}"
env_beallit "WHISPER_MODELL" "${WHISPER_MODELL:-base}"
# Hány modell lehet EGYSZERRE a memóriában. Kis gépen egy is sok, mert a
# betöltött modell a teljes méretét lefoglalja a RAM-ból/VRAM-ból.
RAM_OSSZ_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
if (( RAM_OSSZ_GB <= 10 )); then
    env_beallit "OLLAMA_MAX_LOADED_MODELS" "1"
    env_beallit "OLLAMA_NUM_PARALLEL" "1"
    env_beallit "OLLAMA_KEEP_ALIVE" "2m"      # hamarabb szabaduljon fel a RAM
    info "kis memória (${RAM_OSSZ_GB} GB): egyszerre 1 modell, 2 perc után kirakja"
else
    env_beallit "OLLAMA_MAX_LOADED_MODELS" "2"
    env_beallit "OLLAMA_NUM_PARALLEL" "2"
    env_beallit "OLLAMA_KEEP_ALIVE" "5m"
fi

# A modellek több GB-osak és bármikor újratölthetők – ezért mehetnek külön
# adathordozóra (AI_MODELL_DIR), a rendszerlemez helyett.
AI_MODELL_DIR="${AI_MODELL_DIR:-${ADAT_DIR}/ai/ollama}"
env_frissit "AI_MODELL_DIR" "$AI_MODELL_DIR"
konyvtar "$AI_MODELL_DIR"
for d in open-webui comfyui/models comfyui/output comfyui/input; do
    konyvtar "${ADAT_DIR}/ai/${d}"
done

# ---------------------------------------------------------------- vas-méret --
VRAM_GB=0
if van_parancs nvidia-smi; then
    VRAM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)"
    VRAM_GB=$(( ${VRAM_MB:-0} / 1024 ))
fi
RAM_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
# Amivel reálisan dolgozhatunk: a VRAM, vagy GPU nélkül a RAM fele.
if (( VRAM_GB > 0 )); then KERET_GB=$VRAM_GB; else KERET_GB=$(( RAM_GB / 2 )); fi
info "elérhető keret a modelleknek: ${KERET_GB} GB (RAM ${RAM_GB} GB, VRAM ${VRAM_GB} GB)"

# ------------------------------------------------------- modellek kiválasztása
if [[ -z "${AI_MODELLEK:-}" ]]; then
    # Automatikus csomag a vas méretéhez: csevegő + kódoló + gondolkodó +
    # képértő + beágyazó (utóbbi kell a dokumentum-kereséshez).
    if   (( KERET_GB >= 24 )); then
        AI_MODELLEK="qwen2.5:32b qwen2.5-coder:14b deepseek-r1:14b llama3.2-vision:11b nomic-embed-text"
    elif (( KERET_GB >= 12 )); then
        AI_MODELLEK="qwen2.5:14b qwen2.5-coder:7b deepseek-r1:7b llava:7b nomic-embed-text"
    elif (( KERET_GB >= 8 )); then
        AI_MODELLEK="qwen2.5:7b qwen2.5-coder:7b deepseek-r1:7b nomic-embed-text"
    elif (( KERET_GB >= 4 )); then
        AI_MODELLEK="llama3.2:3b qwen2.5:3b nomic-embed-text"
    else
        AI_MODELLEK="llama3.2:1b nomic-embed-text"
    fi
    info "automatikus modellcsomag: ${AI_MODELLEK}"
else
    info "beállított modellek: ${AI_MODELLEK}"
fi
env_beallit "AI_MODELLEK" "$AI_MODELLEK"

# ------------------------------------------------------- felhős szolgáltatók --
# Csak azok kerülnek a LiteLLM-be, amelyekhez van API-kulcs. A kulcsokat
# később is meg lehet adni:  park ai-kulcs anthropic sk-ant-...
declare -A SZOLGALTATO_NEV=(
    [ANTHROPIC_API_KEY]="anthropic"   [OPENAI_API_KEY]="openai"
    [GEMINI_API_KEY]="gemini"         [GROQ_API_KEY]="groq"
    [MISTRAL_API_KEY]="mistral"       [DEEPSEEK_API_KEY]="deepseek"
    [XAI_API_KEY]="xai"               [OPENROUTER_API_KEY]="openrouter"
)

AKTIV_SZOLGALTATOK=()
for kulcs in "${!SZOLGALTATO_NEV[@]}"; do
    ertek="${!kulcs:-}"
    [[ -z "$ertek" ]] && ertek="$(env_ertek "$kulcs" 2>/dev/null || true)"
    env_beallit "$kulcs" "$ertek"
    [[ -n "$ertek" ]] && AKTIV_SZOLGALTATOK+=("${SZOLGALTATO_NEV[$kulcs]}")
done

# ------------------------------------------------------------ LiteLLM konfig --
stack_telepit ai

if [[ "$PROBA" == "1" ]]; then
    info "[próba] park-ai-konfig -> ${PARK_DIR}/stackek/ai/litellm.config.yaml (csak a kulccsal bíró szolgáltatók)"
else
    PARK_DIR="$PARK_DIR" "${TELEPITO_DIR}/skriptek/park-ai-konfig" >/dev/null
fi

if (( ${#AKTIV_SZOLGALTATOK[@]} )); then
    ok "felhős szolgáltatók kulccsal: ${AKTIV_SZOLGALTATOK[*]}"
else
    info "felhős kulcs még nincs – a Claude/GPT/Gemini akkor él, ha megadod:"
    info "    park ai-kulcs anthropic sk-ant-…"
fi

# ------------------------------------------------------------------ SearXNG --
SEARX_TITOK="$(titok SEARXNG_TITOK 32)"
if [[ ! -f "${PARK_DIR}/stackek/ai/searxng/settings.yml" ]]; then
    cat <<SEARX | fajlt_ir "${PARK_DIR}/stackek/ai/searxng/settings.yml"
# SearXNG – a webkereséshez, amit az Open WebUI használ.
use_default_settings: true
server:
  secret_key: "${SEARX_TITOK}"
  limiter: false
  image_proxy: true
search:
  safe_search: 0
  autocomplete: "duckduckgo"
  # A JSON formátum KELL, különben az Open WebUI nem tud keresni:
  formats:
    - html
    - json
SEARX
    ok "SearXNG beállítva (webkeresés az AI-nak)"
fi

# ------------------------------------------------------------------- GPU -----
if [[ "${GPU_TIPUS:-nincs}" == "nvidia" ]]; then
    if ! csomag_van nvidia-container-toolkit; then
        info "nvidia-container-toolkit telepítése (GPU átadás a konténernek)…"
        case "$OS_CSALAD" in
            debian)
                fut bash -c 'curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
                    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg'
                fut bash -c 'curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
                    | sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" \
                    > /etc/apt/sources.list.d/nvidia-container-toolkit.list'
                csomaglista_frissit ;;
            fedora)
                fut bash -c 'curl -fsSL -o /etc/yum.repos.d/nvidia-container-toolkit.repo \
                    https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo' ;;
        esac
        csomag_telepit nvidia-container-toolkit
        fut nvidia-ctk runtime configure --runtime=docker
        fut systemctl restart docker
    fi
    if [[ "$PROBA" != "1" ]]; then
        cp "${TELEPITO_DIR}/sablonok/ai/compose.gpu.yml" \
           "${PARK_DIR}/stackek/ai/compose.override.yml"
    fi
    ok "GPU-gyorsítás bekapcsolva (NVIDIA, ${VRAM_GB} GB VRAM)"
else
    info "GPU nélkül, processzoron fut – ezért kaptál kisebb modelleket."
    [[ -f "${PARK_DIR}/stackek/ai/compose.override.yml" ]] && \
        fut rm -f "${PARK_DIR}/stackek/ai/compose.override.yml"
fi

# --------------------------------------------------------- képgenerálás ------
if [[ "${AI_KEPGENERALAS:-n}" == "i" ]]; then
    env_beallit "COMPOSE_PROFILES" "kep"
    figy "ComfyUI bekapcsolva – a modelleket külön kell letölteni ide:"
    figy "  ${ADAT_DIR}/ai/comfyui/models/checkpoints/"
fi

# A katalógus a szerverre is kerüljön, hogy a 'park ai-katalogus' lássa.
if [[ "$PROBA" != "1" ]]; then
    cp "${TELEPITO_DIR}/lib/ai-katalogus.txt" "${PARK_DIR}/ai-katalogus.txt"
fi

stack_indit ai

vhost_ir "10-ai" "http://ai.${BELSO_DOMAIN} {
	reverse_proxy open-webui:8080
}

http://ai-api.${BELSO_DOMAIN} {
	# OpenAI-kompatibilis API MINDEN modellhez (helyi + felhős).
	reverse_proxy litellm:4000
}

http://kereso.${BELSO_DOMAIN} {
	reverse_proxy searxng:8080
}

http://kepgen.${BELSO_DOMAIN} {
	reverse_proxy comfyui:8188
}"

# ------------------------------------------------------- modellek letöltése --
if [[ "$PROBA" != "1" ]]; then
    if konteneret_var park-ollama 90; then
        DB=0
        for modell in $AI_MODELLEK; do
            if docker exec park-ollama ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$modell"; then
                kihagy "modell: $modell"
                DB=$((DB+1)); continue
            fi
            info "modell letöltése: ${modell} … (ez eltarthat pár percig)"
            if docker exec park-ollama ollama pull "$modell" >/dev/null 2>&1; then
                ok "kész: $modell"; DB=$((DB+1))
            else
                figy "nem sikerült: $modell  (később: park ai-modell $modell)"
            fi
        done
        ok "${DB} modell elérhető helyben"
    else
        figy "az Ollama nem indult el időben – a modelleket később: park ai-modell <név>"
    fi
fi

szolgaltatas_jegyzes "Open WebUI"  "http://ai.${BELSO_DOMAIN}"      "helyi + felhős modellek egy helyen"
szolgaltatas_jegyzes "AI API"      "http://ai-api.${BELSO_DOMAIN}"  "OpenAI-kompatibilis (LiteLLM)"
szolgaltatas_jegyzes "Kereső"      "http://kereso.${BELSO_DOMAIN}"  "SearXNG – az AI webkeresése"
if [[ "${AI_KEPGENERALAS:-n}" == "i" ]]; then
    szolgaltatas_jegyzes "ComfyUI" "http://kepgen.${BELSO_DOMAIN}"  "képgenerálás"
fi

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
