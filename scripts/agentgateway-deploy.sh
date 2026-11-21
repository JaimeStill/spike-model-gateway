#!/usr/bin/env bash
# Deploys the gateway's compose project, agentgateway, its Postgres, and its traces' Collector,
# Tempo, and Grafana (gateway/compose.yml), to gb10-2 from the laptop over Tailscale SSH.
# Idempotent. It creates any consumer key config.yaml names that this machine lacks, and
# Postgres's password if this machine lacks it, renders the config with each key's hash and each
# secret substituted, copies the compose project to ~/gateway on gb10-2 and the rendered config
# beside the live one, pulls the pinned image if gb10-2 lacks it,
# validates the copy with that image, and moves it into place, where agentgateway reloads it with
# no restart. It then runs `docker compose up --detach --wait --build` there, through
# gateway/compose.sh, which creates a container again only when its image, build, or settings
# changed, or a field under the config's top-level `config` section did, which agentgateway reads
# only at start; otherwise the config refresh is all a re-run does. The first compose deploy
# removes the container `docker run` created before the compose project, of the same name.
#
# Overlays. `scripts/agentgateway-deploy.sh [<overlay>...]` takes the names of probe overlays,
# each gateway/agentgateway/probes/<overlay>.yaml, and applies them, in the order given, to the
# copy it sends, never to config.yaml itself, which stays probe-free. A deploy with no overlay
# sends config.yaml alone, so it is also how an overlay is removed. Either way the run is
# idempotent: the same names render the same copy. An overlay file holds sections, each opened by
# a directive comment:
#
#   #@ append            the lines below are added at the end of the copy, as top-level
#                        sections; a top-level key the copy already has is refused, since YAML
#                        would hold it twice
#   #@ after <line>      the lines below are inserted after the one line of the copy equal to
#                        <line>, the rest of the directive exactly, its indentation included; no
#                        such line, or more than one, is refused
#   #@ replace <line>    the lines below take the place of the one line of the copy equal to
#                        <line>, matched as `after` matches, for a value YAML can't hold twice,
#                        such as a provider's hostOverride
#
# Lines before the first directive must be comments or blank. The copy's first line names the
# overlays it carries (`# overlays: none` without), so `head -1 ~/gateway/agentgateway/config.yaml`
# on gb10-2 reads what is live.
#
# Secrets. The config commits no secret: each is the marker `@@secret:<name>@@`, replaced in the
# copy sent to gb10-2, as a key's marker is by its hash. The names, each read from an untracked
# file on this machine:
#
#   postgres-password    .state/agentgateway/postgres-password, created by the deploy if missing;
#                        it also reaches gb10-2 in ~/gateway/postgres.env, 0600, for Postgres
#   azure-key            .state/azure/key, the Azure AI Foundry account's key
#   azure-account        AZURE_ACCOUNT in .state/azure/account.env, the account's resource name
#
# The Azure files are written when the account is set up, outside the deploy, and read only if
# present: a marker whose file is missing stops the deploy before anything is sent, naming the
# marker. A marker in a comment, a whole-line one or one after a value, stops it too, naming the
# line: a comment would carry the secret into the deployed copy in clear text, where nothing reads
# it. No secret is printed or logged, or in a process's argv.
#
# Each command is printed to stderr before it runs, as `+ <time> <host>: <command>`, the form of
# .state/<task>/commands-*.log, so a finding can quote it exactly. Commands run on gb10-2 are sent
# as written, and what gateway/compose.sh looks up there (each tailnet address, the user) expands
# there, so the consumer port is published on gb10-2's tailnet address with no address written
# down or printed. Needs no root.
# See docs/scripts.md#the-deploy
set -euo pipefail
cd "$(dirname "$0")/.."

host=gb10-2
# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env is assignments.
source gateway/agentgateway/deploy.env

config=gateway/agentgateway/config.yaml
state=.state/agentgateway
keys=$state/keys
top_key='^([A-Za-z][A-Za-z0-9]*):'
comment_secret='^[[:space:]]*#.*@@secret:[a-z0-9-]+@@|[[:space:]]#.*@@secret:[a-z0-9-]+@@'
marker='^(.*)sha256:@@([a-z0-9-]+)@@(.*)$'
secret='^(.*)@@secret:([a-z0-9-]+)@@(.*)$'
project=(compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env
  otel-collector.yml otel-collector tempo.yml tempo grafana.yml grafana)
declare -A hashes secrets
lines=()
rendered=
pg_env=

on_host() {
  printf '+ %s %s: %s\n' "$(date -Iseconds)" "$host" "$1" >&2
  # shellcheck disable=SC2029 # The command is built to expand on gb10-2.
  ssh "$host" "$1"
}

on_laptop() {
  printf '+ %s laptop: %s\n' "$(date -Iseconds)" "$1" >&2
}

hash_each_key_creating_missing() {
  local names name key hash
  umask 077
  mkdir -p "$keys"
  chmod 700 "$state" "$keys"
  mapfile -t names < <(grep -oP '^\s*- keyHash: sha256:@@\K[a-z0-9-]+(?=@@\s*$)' "$config" | sort -u)
  if ((${#names[@]} == 0)); then
    echo "agentgateway: no key markers in $config" >&2
    exit 1
  fi
  for name in "${names[@]}"; do
    if [[ -e $keys/$name ]]; then
      echo "key $name: existing"
    else
      openssl rand -hex 32 >"$keys/$name"
      echo "key $name: created"
    fi
    key=$(<"$keys/$name") || return
    hash=$(printf %s "$key" | sha256sum) || return
    hashes[$name]=${hash%% *}
  done
}

read_secrets_creating_postgres_password() {
  local var value
  if [[ -e $state/postgres-password ]]; then
    echo "secret postgres-password: existing"
  else
    openssl rand -hex 32 >"$state/postgres-password"
    echo "secret postgres-password: created"
  fi
  secrets[postgres-password]=$(<"$state/postgres-password") || return
  if [[ -s .state/azure/key ]]; then
    secrets[azure-key]=$(<.state/azure/key) || return
    echo "secret azure-key: read"
  fi
  if [[ -s .state/azure/account.env ]]; then
    while IFS='=' read -r var value; do
      value=${value%\"} value=${value#\"} value=${value%\'} value=${value#\'}
      [[ $var != AZURE_ACCOUNT ]] || secrets[azure-account]=$value
    done <.state/azure/account.env
    [[ -z ${secrets[azure-account]+set} ]] || echo "secret azure-account: read"
  fi
}

refuse_secret_unsafe_in_yaml_or_url() {
  local name
  for name in "${!secrets[@]}"; do
    if [[ ! ${secrets[$name]} =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "agentgateway: secret $name holds a character other than A-Z, a-z, 0-9, ., _ or -; nothing was sent" >&2
      exit 1
    fi
  done
}

overlay_fail() {
  echo "agentgateway: overlay $1: $2; nothing was sent" >&2
  exit 1
}

place_overlay_section() {
  local overlay=$1 mode=$2 anchor=$3 l have at=() i keep
  shift 3
  case $mode in
    append)
      for l in "$@"; do
        [[ $l =~ $top_key ]] || continue
        for have in "${lines[@]}"; do
          [[ $have != "${BASH_REMATCH[1]}:"* ]] ||
            overlay_fail "$overlay" "top-level ${BASH_REMATCH[1]} is in the config already"
        done
      done
      lines+=("$@")
      ;;
    after | replace)
      for i in "${!lines[@]}"; do
        [[ ${lines[i]} != "$anchor" ]] || at+=("$i")
      done
      ((${#at[@]} == 1)) ||
        overlay_fail "$overlay" "${#at[@]} lines equal \"$anchor\"; one is needed"
      keep=$((at[0] + 1))
      [[ $mode == after ]] || keep=${at[0]}
      lines=("${lines[@]:0:keep}" "$@" "${lines[@]:at[0]+1}")
      ;;
  esac
}

apply_overlays() {
  local overlay file body mode anchor section raw
  mapfile -t lines <"$config"
  for overlay in "$@"; do
    file=gateway/agentgateway/probes/$overlay.yaml
    [[ $overlay =~ ^[a-z0-9-]+$ && -f $file ]] || overlay_fail "$overlay" "no $file"
    mapfile -t body <"$file"
    body+=('#@ end')
    mode='' anchor='' section=()
    for raw in "${body[@]}"; do
      if [[ $raw == '#@ '* ]]; then
        place_overlay_section "$overlay" "$mode" "$anchor" "${section[@]}"
        section=()
        case $raw in
          '#@ append') mode=append ;;
          '#@ after '*) mode=after anchor=${raw#'#@ after '} ;;
          '#@ replace '*) mode=replace anchor=${raw#'#@ replace '} ;;
          '#@ end') mode= ;;
          *) overlay_fail "$overlay" "unknown directive \"$raw\"" ;;
        esac
      elif [[ -n $mode ]]; then
        section+=("$raw")
      elif [[ -n ${raw//[[:space:]]/} && $raw != '#'* ]]; then
        overlay_fail "$overlay" "a line before its first directive isn't a comment"
      fi
    done
    echo "overlay $overlay: applied"
  done
}

refuse_secret_marker_in_comment() {
  local i refused=0
  for i in "${!lines[@]}"; do
    if [[ ${lines[i]} =~ $comment_secret ]]; then
      printf 'agentgateway: line %d of the copy (%s, overlays: %s) holds a secret marker in a comment: %s\n' \
        $((i + 1)) "$config" "${*:-none}" "${lines[i]}" >&2
      refused=1
    fi
  done
  if ((refused)); then
    echo "agentgateway: a comment would carry its secret to gb10-2 in clear text; nothing was sent" >&2
    exit 1
  fi
}

render_copy_in_bash() {
  local line
  rendered=$(mktemp "$state/config.rendered.XXXXXX.yaml") || return
  pg_env=$(mktemp "$state/postgres.XXXXXX.env") || return
  trap 'rm -f "$rendered" "$pg_env"' EXIT
  {
    printf '# overlays: %s\n' "${*:-none}"
    for line in "${lines[@]}"; do
      if [[ $line =~ $marker && -n ${hashes[${BASH_REMATCH[2]}]+set} ]]; then
        line="${BASH_REMATCH[1]}sha256:${hashes[${BASH_REMATCH[2]}]}${BASH_REMATCH[3]}"
      fi
      while [[ $line =~ $secret && -n ${secrets[${BASH_REMATCH[2]}]+set} ]]; do
        line="${BASH_REMATCH[1]}${secrets[${BASH_REMATCH[2]}]}${BASH_REMATCH[3]}"
      done
      printf '%s\n' "$line"
    done
  } >"$rendered"
  printf 'POSTGRES_PASSWORD=%s\n' "${secrets[postgres-password]}" >"$pg_env"
}

refuse_unrendered_marker_or_partial_hash() {
  local left
  if left=$(grep -oP '@@\K[a-z0-9:-]+(?=@@)' "$rendered" | sort -u | paste -sd' ') && [[ -n $left ]]; then
    echo "agentgateway: markers with no value in the rendered config: $left; nothing was sent" >&2
    exit 1
  fi
  if grep -qP '^\s*- keyHash:(?! sha256:[0-9a-f]{64}\s*$)' "$rendered"; then
    echo "agentgateway: a keyHash that isn't a full hash is in the rendered config; nothing was sent" >&2
    exit 1
  fi
}

send_project_and_copy() {
  on_host 'mkdir -p ~/gateway/agentgateway'

  on_laptop "tar -C gateway --transform 's,^agentgateway/deploy.env\$,.env,' -cf - ${project[*]} | ssh $host 'tar -C ~/gateway -xf -'"
  tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - "${project[@]}" |
    ssh "$host" 'tar -C ~/gateway -xf -'

  on_laptop "ssh $host 'umask 077 && cat > ~/gateway/postgres.env' < $state/postgres.<tmp>.env"
  ssh "$host" 'umask 077 && cat > ~/gateway/postgres.env' <"$pg_env"

  on_laptop "ssh $host 'cat > ~/gateway/agentgateway/config.yaml.next' < $state/config.rendered.<tmp>.yaml"
  ssh "$host" 'cat > ~/gateway/agentgateway/config.yaml.next' <"$rendered"
}

validate_copy_as_container_reads_it_and_move_into_place() {
  on_host "docker image inspect $AGW_IMAGE >/dev/null 2>&1 || docker pull $AGW_IMAGE"
  on_host "docker run --rm --user \"\$(id -u):\$(id -g)\" --volume \"\$HOME/gateway/agentgateway:/config:ro\" \
$AGW_IMAGE -f /config/config.yaml.next --validate-only"
  on_host 'mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml'
}

remove_container_from_before_compose() {
  local owner
  owner=$(on_host "docker container inspect agentgateway \
--format '{{index .Config.Labels \"com.docker.compose.project\"}}' 2>/dev/null || echo absent") || return
  case $owner in
    gateway | absent) ;;
    *) on_host 'docker rm --force agentgateway' ;;
  esac
}

hash_each_key_creating_missing
read_secrets_creating_postgres_password
refuse_secret_unsafe_in_yaml_or_url
apply_overlays "$@"
refuse_secret_marker_in_comment "$@"
render_copy_in_bash "$@"
refuse_unrendered_marker_or_partial_hash
send_project_and_copy
validate_copy_as_container_reads_it_and_move_into_place
remove_container_from_before_compose
on_host 'gateway/compose.sh up --detach --wait --build'
on_host 'gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"'
