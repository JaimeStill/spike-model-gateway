#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each pin behind its latest, and exits 1 if any;
# prints nothing when all are current. Reads mise.toml and the bench environment (mise.bench.toml,
# GuideLLM's and lm-evaluation-harness's) together: MISE_ENV=bench loads both. mise lists a tool not
# installed here with no bump, so its pin is compared with its latest instead. A pin held on
# purpose, as the bench tools' Python is, is reported like any other, and its comment says why it
# is held. Each gateway's image pin is compared with its project's latest GitHub release:
# agentgateway's in gateway/agentgateway/deploy.env. Reads the network.
set -euo pipefail
cd "$(dirname "$0")/.."

trailing=$(MISE_ENV=bench MISE_LOG_LEVEL=error mise outdated --bump --local --json |
  jq -r 'to_entries[] | (.value.bump // .value.latest) as $to | select($to != .value.requested) |
    "\(.value.source.path | split("/") | last): \(.key) \(.value.requested) -> \($to)"' | sort -u)

# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env holds three assignments.
source gateway/agentgateway/deploy.env
pin=${AGW_IMAGE##*:}
latest=$(gh release view -R agentgateway/agentgateway --json tagName --jq .tagName)
if [[ $pin != "$latest" ]]; then
  trailing+=${trailing:+$'\n'}"gateway/agentgateway/deploy.env: agentgateway $pin -> $latest"
fi

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
