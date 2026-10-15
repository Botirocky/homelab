#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
if [[ -z "$HOST" || "$HOST" == "-h" || "$HOST" == "--help" ]]; then
    cat <<SUGO
tavoli-build – a Botirocky ISO építése egy távoli Debian gépen (SSH-n).

  ./tavoli-build.sh <ssh-host> [keszit.sh kapcsolók...]

Példák:
  ./tavoli-build.sh debian-vm --proba
  ./tavoli-build.sh felhasznalo@192.168.1.50
  ./tavoli-build.sh debian-vm --nev pi-park --disztro trixie

A <ssh-host> bármilyen SSH-alias vagy cím. Kulcsos, jelszó nélküli belépés
ajánlott. A sudo miatt a build tty-t kap (-t), ha kell root-jelszó, be tudod írni.
SUGO
    exit 0
fi
shift || true

PROJEKT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SZULO="$(cd "$PROJEKT/.." && pwd)"

if [[ -t 1 ]]; then Z=$'\e[32m'; S=$'\e[33m'; P=$'\e[31m'; K=$'\e[36m'; N=$'\e[0m'; G=$'\e[90m'
else Z=""; S=""; P=""; K=""; N=""; G=""; fi
cim()  { printf '\n%s╭─ %s%s\n' "$K" "$*" "$N"; }
info() { printf '%s│%s  %s\n' "$K" "$N" "$*"; }
ok()   { printf '%s│%s  %s✔%s %s\n' "$K" "$N" "$Z" "$N" "$*"; }
hiba() { printf '%s│%s  %s✘ %s%s\n' "$K" "$N" "$P" "$*" "$N" >&2; }
vege() { printf '%s╰─%s\n' "$K" "$N"; }
van()  { command -v "$1" >/dev/null 2>&1; }

cim "Kapcsolat"
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" true 2>/dev/null; then
    hiba "nem érem el jelszó nélkül: $HOST"
    info "próbáld: ssh-copy-id $HOST   (majd ssh $HOST igazolja, hogy megy)"
    vege; exit 1
fi
tavoli_debian=0
ssh "$HOST" 'test -f /etc/debian_version' 2>/dev/null && tavoli_debian=1
(( tavoli_debian )) && ok "elérhető: $HOST (Debian)" || { hiba "a cél nem Debian – a live-build itt nem megy"; vege; exit 1; }

cim "Projektek másolása"
masol() {
    local forras="$1" cel="$2"
    if van rsync && ssh "$HOST" 'command -v rsync >/dev/null 2>&1'; then
        rsync -az --delete \
            --exclude '.git' --exclude 'config' --exclude 'auto' \
            --exclude '*.iso' --exclude '*.iso.sha256' --exclude '.build' --exclude 'cache' \
            "$forras/" "$HOST:$cel/"
    else
        ssh "$HOST" "rm -rf '$cel'"
        scp -q -r "$forras" "$HOST:$cel"
    fi
}
masol "$PROJEKT" '~/szerverpark-os'
ok "szerverpark-os átmásolva"
if [[ -d "$SZULO/szerverpark" ]]; then
    masol "$SZULO/szerverpark" '~/szerverpark'
    ok "szerverpark stack átmásolva (a disztró ezt süti bele)"
else
    info "nincs mellette szerverpark repó – a disztró a --nincs-szerver móddal épül"
fi
ssh "$HOST" 'chmod +x ~/szerverpark-os/keszit.sh ~/szerverpark-os/rendszer/mento 2>/dev/null || true'
vege

cim "Build indítása a távoli gépen"
info "parancs: sudo ./keszit.sh $*"
if ssh -t "$HOST" "cd ~/szerverpark-os && sudo ./keszit.sh $*"; then
    ok "a távoli build lefutott"
else
    hiba "a távoli build hibával zárult (lásd a fenti kimenetet)"
    vege; exit 1
fi
vege

iso="$(ssh "$HOST" 'ls -1 ~/szerverpark-os/*.iso 2>/dev/null | head -1' 2>/dev/null || true)"
if [[ -n "$iso" ]]; then
    cim "Kész ISO"
    info "a távoli gépen: $iso"
    info "letöltés ide:  scp $HOST:'$iso' ."
    vege
fi
