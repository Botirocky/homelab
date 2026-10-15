#!/usr/bin/env bash
# Modul: Docker Engine + Compose + közös hálózat

cim "Docker"

if van_parancs docker && docker compose version >/dev/null 2>&1; then
    kihagy "Docker + Compose ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ,))"
else
    info "Docker telepítése (${OS_CSALAD})…"
    docker_engine_telepit
    ok "Docker telepítve"
fi

szolgaltatas_be docker

# A napi felhasználó sudo nélkül is dockerezhessen
CEL_USER="${SUDO_USER:-}"
if [[ -n "$CEL_USER" ]] && ! id -nG "$CEL_USER" 2>/dev/null | grep -qw docker; then
    fut usermod -aG docker "$CEL_USER"
    ok "$CEL_USER hozzáadva a docker csoporthoz (új bejelentkezés után él)"
fi

# Napló-korlát: ne egye meg a lemezt a konténerek logja
if [[ ! -f /etc/docker/daemon.json ]]; then
    cat <<'DJ' | fajlt_ir /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "dns": ["1.1.1.1", "9.9.9.9"]
}
DJ
    fut systemctl restart docker
    ok "konténer-naplók korlátozva (3 × 10 MB)"
fi

# Közös hálózat, hogy a Caddy név szerint elérje a többi konténert
if [[ "$PROBA" == "1" ]]; then
    info "[próba] docker network create park"
elif docker network inspect park >/dev/null 2>&1; then
    kihagy "'park' hálózat"
else
    fut docker network create park >/dev/null
    ok "'park' docker hálózat létrehozva"
fi

# GPU felismerés az AI modulhoz
if van_parancs nvidia-smi; then
    GPU_TIPUS="nvidia"
    info "NVIDIA GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
elif [[ -d /dev/dri ]]; then
    GPU_TIPUS="intel-amd"
    info "Intel/AMD videókártya észlelve (/dev/dri)"
else
    GPU_TIPUS="nincs"
fi
export GPU_TIPUS

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
