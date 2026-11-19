#!/usr/bin/env bash
# Prints `<file>: <tool> <pin> -> <latest>` for each pin behind its latest, and exits 1 if any;
# prints nothing when all are current. Reads mise.toml and the bench environment (mise.bench.toml,
# GuideLLM's and lm-evaluation-harness's) together: MISE_ENV=bench loads both. mise lists a tool not
# installed here with no bump, so its pin is compared with its latest instead. A pin held on
# purpose, as the bench tools' Python is, is reported like any other, and its comment says why it
# is held. Each gateway's image pin is compared with its project's latest GitHub release:
# agentgateway's in gateway/agentgateway/deploy.env. Each compose Dockerfile's FROM line,
# gateway/<service>/Dockerfile (Postgres's, the Collector's, Tempo's, and Grafana's), is compared
# with the highest semantic-version tag that carries the pin's variant suffix (a pin of
# 18.7-alpine against the newest -alpine release, a bare 3.1.1 against the newest bare release),
# listed by crane.
# The client helpers' go-ai release, CLIENTS_GOAI_TAG in scripts/clients-lib.sh, is compared with
# the highest tools/infer/v* tag on go-ai's remote, and the retry test's go-ai requirement in
# retry/go.mod with the module's latest release on the module proxy. Reads the network.
set -euo pipefail
cd "$(dirname "$0")/.."

trailing=$(MISE_ENV=bench MISE_LOG_LEVEL=error mise outdated --bump --local --json |
  jq -r 'to_entries[] | (.value.bump // .value.latest) as $to | select($to != .value.requested) |
    "\(.value.source.path | split("/") | last): \(.key) \(.value.requested) -> \($to)"' | sort -u)

report() {
  trailing+=${trailing:+$'\n'}$1
}

# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env is assignments.
source gateway/agentgateway/deploy.env
pin=${AGW_IMAGE##*:}
latest=$(gh release view -R agentgateway/agentgateway --json tagName --jq .tagName)
[[ $pin == "$latest" ]] || report "gateway/agentgateway/deploy.env: agentgateway $pin -> $latest"

# The highest semantic-version tag of an image that carries the pin's variant suffix. A tag needs
# at least one dot to count, so a bare build number never sorts above a release.
latest_tag() {
  local image=$1 pin=$2 suffix pattern tags
  suffix=${pin#"${pin%%[!0-9.]*}"}
  pattern="^[0-9]+(\.[0-9]+)+${suffix//./\\.}\$"
  tags=$(crane ls "$image")
  grep -E "$pattern" <<<"$tags" | sed "s/${suffix}\$//" | sort -V | tail -n1 | sed "s/\$/${suffix}/"
}

for dockerfile in gateway/*/Dockerfile; do
  [[ -e $dockerfile ]] || continue
  ref=$(sed -n 's/^FROM  *\([^ ]*\).*/\1/p' "$dockerfile" | head -n1)
  image=${ref%:*} pin=${ref##*:}
  latest=$(latest_tag "$image" "$pin")
  [[ $pin == "$latest" ]] || report "$dockerfile: $image $pin -> $latest"
done

# The helpers' go-ai tag, read from its assignment, since clients-lib.sh is sourced only.
goai_tag=$(sed -n 's/^CLIENTS_GOAI_TAG=//p' scripts/clients-lib.sh)
latest=$(git ls-remote --tags --refs https://github.com/standards-lab/go-ai.git 'refs/tags/tools/infer/v*' |
  sed 's|.*refs/tags/||' | sort -V | tail -n1)
[[ -n $latest ]] || {
  echo "currency: no tools/infer tag listed on go-ai's remote" >&2
  exit 2
}
[[ $goai_tag == "$latest" ]] || report "scripts/clients-lib.sh: go-ai $goai_tag -> $latest"

# The retry test's go-ai: `go list -m -u` names an update past the required version, or none.
mod=$(cd retry && go list -m -u -f '{{.Version}} {{with .Update}}{{.Version}}{{end}}' github.com/standards-lab/go-ai)
read -r pin update <<<"$mod"
[[ -z $update ]] || report "retry/go.mod: go-ai $pin -> $update"

if [[ -n $trailing ]]; then
  echo "$trailing"
  exit 1
fi
