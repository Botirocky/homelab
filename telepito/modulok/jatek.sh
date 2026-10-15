#!/usr/bin/env bash

cim "Játékszerver – Minecraft"

[[ -z "${MINECRAFT_EULA:-}" ]] && MINECRAFT_EULA="$(env_ertek MINECRAFT_EULA 2>/dev/null || true)"
if [[ "${MINECRAFT_EULA:-}" != "i" ]]; then
    info "A Minecraft-szerverhez el kell fogadni a Mojang EULA-t: https://aka.ms/MinecraftEULA"
    if igen_nem "Elfogadod?" "n"; then
        MINECRAFT_EULA="i"
    else
        figy "EULA nélkül nem telepítem (az --auto módhoz: MINECRAFT_EULA=\"i\" a confban)"
        return 0
    fi
fi

env_frissit "MINECRAFT_EULA" "i"
konyvtar "${ADAT_DIR}/minecraft"
[[ "$PROBA" != "1" ]] && fut chown "${PUID:-1000}:${PGID:-1000}" "${ADAT_DIR}/minecraft" 2>/dev/null

if [[ -z "${MC_MEMORIA:-}" ]]; then
    if (( ${MEM_GB:-0} >= 16 )); then MC_MEMORIA="4G"; elif (( ${MEM_GB:-0} >= 7 )); then MC_MEMORIA="2G"; else MC_MEMORIA="1G"; fi
fi
env_frissit "MC_TIPUS"   "${MC_TIPUS:-PAPER}"
env_frissit "MC_VERZIO"  "${MC_VERZIO:-LATEST}"
env_frissit "MC_MEMORIA" "$MC_MEMORIA"
env_frissit "MC_MODOK"   "${MC_MODOK:-}"
titok MC_RCON_JELSZO 24 >/dev/null

stack_telepit jatek
stack_indit jatek

szolgaltatas_jegyzes "Minecraft" "<szerver-ip>:25565" "${MC_TIPUS:-PAPER}, ${MC_MEMORIA} RAM; konzol: docker exec -it park-minecraft rcon-cli"

:
