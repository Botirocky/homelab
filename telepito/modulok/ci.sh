#!/usr/bin/env bash

cim "CI – Forgejo Actions runner"

if [[ "$PROBA" != "1" ]] && ! docker ps --format '{{.Names}}' | grep -qx park-forgejo; then
    figy "nem fut a Forgejo (park-forgejo) – előbb a selfhost modul kell"
    return 0
fi

RUNNER_DIR="${ADAT_DIR}/forgejo-runner"
konyvtar "$RUNNER_DIR"
env_frissit "DOCKER_GID" "$(getent group docker | cut -d: -f3 || echo 999)"
RUNNER_TITOK="$(env_ertek FORGEJO_RUNNER_TITOK 2>/dev/null || true)"
if [[ -z "$RUNNER_TITOK" ]]; then
    RUNNER_TITOK="$(openssl rand -hex 20)"
    env_beallit "FORGEJO_RUNNER_TITOK" "$RUNNER_TITOK"
fi
RUNNER_UUID="$(printf '%s' "${RUNNER_TITOK:0:16}" | od -An -tx1 | tr -d ' \n' \
    | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12})$/\1-\2-\3-\4-\5/')"
RUNNER_NEV="$(hostname)"

cat <<CFG | fajlt_ir "${RUNNER_DIR}/config.yml"
log:
  level: info
runner:
  file: .runner
  capacity: ${CI_PARHUZAMOS:-1}
  timeout: 1h
  labels:
    - "debian:docker://node:22-trixie"
    - "ubuntu-latest:docker://node:22-bookworm"
    - "docker:docker://node:22-bookworm"
server:
  connections:
    park:
      url: http://forgejo:3000/
      uuid: ${RUNNER_UUID}
      token: ${RUNNER_TITOK}
container:
  network: park
  options: --add-host=git.${BELSO_DOMAIN}:host-gateway
  valid_volumes: []
CFG
[[ "$PROBA" != "1" ]] && { chown -R "1000:1000" "$RUNNER_DIR"; chmod 600 "${RUNNER_DIR}/config.yml"; }

if [[ "$PROBA" == "1" ]]; then
    info "[próba] runner regisztrálása a Forgejóban: ${RUNNER_NEV}"
elif docker exec -u git park-forgejo forgejo forgejo-cli actions register \
        --name "$RUNNER_NEV" --secret "$RUNNER_TITOK" >/dev/null 2>&1; then
    ok "runner regisztrálva a Forgejóban: ${RUNNER_NEV}"
else
    figy "a regisztráció nem sikerült – be vannak kapcsolva az Actions? (FORGEJO__actions__ENABLED)"
fi

stack_telepit ci
stack_indit ci

szolgaltatas_jegyzes "Forgejo runner" "http://git.${BELSO_DOMAIN}/admin/actions/runners" "workflow: .forgejo/workflows/*.yml, runs-on: debian"

:
