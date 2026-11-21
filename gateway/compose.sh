#!/usr/bin/env bash
# Runs `docker compose <argument>...` on the gateway's compose project, from its directory, on
# gb10-2, where the deploy copies it to ~/gateway. It sets the values the compose files read at run
# time, each looked up on gb10-2 so none is written down or printed: the deploying user; gb10-2's
# tailnet address, where agentgateway's consumer port and the Collector's OTLP port are published;
# each row host's tailnet address; and a hash of the deployed config's top-level `config` section,
# which agentgateway reads only at start. The rest come from the project's .env, the deploy's copy
# of deploy.env. It also turns off buildx's default attestation, so an unchanged build keeps its
# image id. Run as `gateway/compose.sh up --detach --wait --build`, or by `mise run gateway:up`,
# `gateway:down`, or `gateway:reset` over SSH.
# See docs/stack.md#agentgateway
# See docs/stack.md#unattested-builds
set -euo pipefail
cd "$(dirname "$0")"

uncommented_config_section_hash() {
  local config=agentgateway/config.yaml section=
  if [[ -f $config ]]; then
    section=$(awk '/^[^[:space:]#]/ { in_config = /^config:/ } in_config && !/^[[:space:]]*#/' "$config") || return
  fi
  printf '%s' "$section" | sha256sum | cut -c1-12
}

AGW_USER="$(id -u):$(id -g)"
AGW_ADDR=$(tailscale ip -4)
GB10_1_ADDR=$(tailscale ip -4 gb10-1)
GB10_2_ADDR=$(tailscale ip -4 gb10-2)
FRAMEWORK_ADDR=$(tailscale ip -4 framework)
AGW_CONFIG_SECTION=$(uncommented_config_section_hash)
BUILDX_NO_DEFAULT_ATTESTATIONS=1

export AGW_USER AGW_ADDR GB10_1_ADDR GB10_2_ADDR FRAMEWORK_ADDR AGW_CONFIG_SECTION
export BUILDX_NO_DEFAULT_ATTESTATIONS
exec docker compose "$@"
