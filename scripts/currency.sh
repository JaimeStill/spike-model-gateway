#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each mise tool behind its latest, and exits 1 if
# any; prints nothing when all are current. Reads mise.toml and the bench environment
# (mise.bench.toml, GuideLLM's and lm-evaluation-harness's) together: MISE_ENV=bench loads both.
# mise lists a tool not installed here with no bump, so its pin is compared with its latest
# instead. A pin held on purpose, as the bench tools' Python is, is reported like any other, and
# its comment says why it is held. Reads the network.
set -euo pipefail
cd "$(dirname "$0")/.."

trailing=$(MISE_ENV=bench MISE_LOG_LEVEL=error mise outdated --bump --local --json |
  jq -r 'to_entries[] | (.value.bump // .value.latest) as $to | select($to != .value.requested) |
    "\(.value.source.path | split("/") | last): \(.key) \(.value.requested) -> \($to)"' | sort -u)

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
