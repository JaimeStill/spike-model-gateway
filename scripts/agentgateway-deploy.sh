#!/usr/bin/env bash
# Deploys the gateway's compose project, agentgateway and its Postgres (gateway/compose.yml), to
# gb10-2 from the laptop over Tailscale SSH. Idempotent. It creates any consumer key config.yaml
# names that this machine lacks, and Postgres's password if this machine lacks it, renders the
# config with each key's hash and each secret substituted, copies the compose project to ~/gateway
# on gb10-2 and the rendered config beside the live one, pulls the pinned image if gb10-2 lacks it,
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
#   azure-rg             AZURE_RG there, its resource group
#
# The Azure files are written when the account is set up, outside the deploy, and read only if
# present: a marker whose file is missing stops the deploy before anything is sent, naming the
# marker. No secret is printed or logged, or in a process's argv.
#
# Each command is printed to stderr before it runs, as `+ <time> <host>: <command>`, the form of
# .state/<task>/commands-*.log, so a finding can quote it exactly. Commands run on gb10-2 are sent
# as written, and what gateway/compose.sh looks up there (each tailnet address, the user) expands
# there, so the consumer port is published on gb10-2's tailnet address with no address written
# down or printed. Needs no root.
set -euo pipefail
cd "$(dirname "$0")/.."

host=gb10-2
# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env is assignments.
source gateway/agentgateway/deploy.env

# Prints the command given, then runs it on gb10-2, where it expands.
on_host() {
  printf '+ %s %s: %s\n' "$(date -Iseconds)" "$host" "$1" >&2
  # shellcheck disable=SC2029 # The command is built to expand on gb10-2.
  ssh "$host" "$1"
}

# Prints the command given, as run on the laptop.
on_laptop() {
  printf '+ %s laptop: %s\n' "$(date -Iseconds)" "$1" >&2
}

config=gateway/agentgateway/config.yaml
state=.state/agentgateway
keys=$state/keys

# Keys. config.yaml commits each key's name only, as the marker `keyHash: sha256:@@<name>@@`; the
# names are read from the markers, so adding an entry is all it takes to issue a key; a name listed
# twice is one key. A missing key is created on this machine, 0600 in a 0700 directory, and an
# existing one is reused, so a re-run changes nothing. Only names are printed: no key or hash
# reaches the terminal or the command log.
umask 077
mkdir -p "$keys"
chmod 700 "$state" "$keys"
mapfile -t names < <(grep -oP '^\s*- keyHash: sha256:@@\K[a-z0-9-]+(?=@@\s*$)' "$config" | sort -u)
if ((${#names[@]} == 0)); then
  echo "agentgateway: no key markers in $config" >&2
  exit 1
fi
declare -A hashes
for name in "${names[@]}"; do
  if [[ -e $keys/$name ]]; then
    echo "key $name: existing"
  else
    openssl rand -hex 32 >"$keys/$name"
    echo "key $name: created"
  fi
  key=$(<"$keys/$name")
  # agentgateway's hash of a presented key: sha256 of its exact characters, no newline, as lowercase
  # hex (APIKeyHash::from_raw_key). printf is a builtin, so the key is never in a process's argv.
  hash=$(printf %s "$key" | sha256sum)
  hashes[$name]=${hash%% *}
done

# Secrets, as the header lists them. Postgres's password is created like a key, once, and reused;
# Postgres reads it only when it first initializes its volume, so it must not change after.
declare -A secrets
if [[ -e $state/postgres-password ]]; then
  echo "secret postgres-password: existing"
else
  openssl rand -hex 32 >"$state/postgres-password"
  echo "secret postgres-password: created"
fi
secrets[postgres-password]=$(<"$state/postgres-password")
if [[ -s .state/azure/key ]]; then
  secrets[azure-key]=$(<.state/azure/key)
  echo "secret azure-key: read"
fi
if [[ -s .state/azure/account.env ]]; then
  # Read as assignments, not sourced: each value is the line's text after `=`, quotes stripped.
  while IFS='=' read -r var value; do
    value=${value%\"} value=${value#\"} value=${value%\'} value=${value#\'}
    case $var in
      AZURE_ACCOUNT) secrets[azure-account]=$value ;;
      AZURE_RG) secrets[azure-rg]=$value ;;
    esac
  done <.state/azure/account.env
  for name in azure-account azure-rg; do
    [[ -z ${secrets[$name]+set} ]] || echo "secret $name: read"
  done
fi
# A value is substituted into YAML and a URL as it is, so it may hold only these characters.
for name in "${!secrets[@]}"; do
  if [[ ! ${secrets[$name]} =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "agentgateway: secret $name holds a character other than A-Z, a-z, 0-9, ., _ or -; nothing was sent" >&2
    exit 1
  fi
done

# The overlays, applied to config.yaml's lines in memory, as the header describes; any refusal
# stops the deploy before anything is sent.
overlay_fail() {
  echo "agentgateway: overlay $1: $2; nothing was sent" >&2
  exit 1
}
mapfile -t lines <"$config"
top_key='^([A-Za-z][A-Za-z0-9]*):'
for overlay in "$@"; do
  file=gateway/agentgateway/probes/$overlay.yaml
  [[ $overlay =~ ^[a-z0-9-]+$ && -f $file ]] || overlay_fail "$overlay" "no $file"
  mapfile -t body <"$file"
  body+=('#@ end')
  mode='' anchor='' section=()
  for raw in "${body[@]}"; do
    if [[ $raw == '#@ '* ]]; then
      # The section read so far is placed before the next one is read.
      case $mode in
        append)
          for l in "${section[@]}"; do
            [[ $l =~ $top_key ]] || continue
            for have in "${lines[@]}"; do
              [[ $have != "${BASH_REMATCH[1]}:"* ]] ||
                overlay_fail "$overlay" "top-level ${BASH_REMATCH[1]} is in the config already"
            done
          done
          lines+=("${section[@]}")
          ;;
        after | replace)
          at=() i=
          for i in "${!lines[@]}"; do
            [[ ${lines[i]} != "$anchor" ]] || at+=("$i")
          done
          ((${#at[@]} == 1)) ||
            overlay_fail "$overlay" "${#at[@]} lines equal \"$anchor\"; one is needed"
          # after keeps the anchor line, replace drops it.
          keep=$((at[0] + 1))
          [[ $mode == after ]] || keep=${at[0]}
          lines=("${lines[@]:0:keep}" "${section[@]}" "${lines[@]:at[0]+1}")
          ;;
      esac
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

# The copy sent to gb10-2: config.yaml, its overlays applied, with each key marker replaced by its
# key's hash and each secret marker by its value. It is written only under .state/, which is
# untracked, and removed on exit, as is Postgres's env file. Replaced in bash, not by sed, so no
# hash or secret is in a command's argv either.
rendered=$(mktemp "$state/config.rendered.XXXXXX.yaml")
pg_env=$(mktemp "$state/postgres.XXXXXX.env")
trap 'rm -f "$rendered" "$pg_env"' EXIT
marker='^(.*)sha256:@@([a-z0-9-]+)@@(.*)$'
secret='^(.*)@@secret:([a-z0-9-]+)@@(.*)$'
{
  printf '# overlays: %s\n' "${*:-none}"
  for line in "${lines[@]}"; do
    if [[ $line =~ $marker && -n ${hashes[${BASH_REMATCH[2]}]+set} ]]; then
      line="${BASH_REMATCH[1]}sha256:${hashes[${BASH_REMATCH[2]}]}${BASH_REMATCH[3]}"
    fi
    # A line may name more than one secret; the last is replaced first. One with no value stays,
    # and the check below refuses it.
    while [[ $line =~ $secret && -n ${secrets[${BASH_REMATCH[2]}]+set} ]]; do
      line="${BASH_REMATCH[1]}${secrets[${BASH_REMATCH[2]}]}${BASH_REMATCH[3]}"
    done
    printf '%s\n' "$line"
  done
} >"$rendered"
printf 'POSTGRES_PASSWORD=%s\n' "${secrets[postgres-password]}" >"$pg_env"
# A marker left over, or a keyHash that isn't a full hash, would deploy a key list that admits no
# one under that name, or a secret that isn't one; stop before anything is sent. Only the
# markers' names are printed.
if left=$(grep -oP '@@\K[a-z0-9:-]+(?=@@)' "$rendered" | sort -u | paste -sd' ') && [[ -n $left ]]; then
  echo "agentgateway: markers with no value in the rendered config: $left; nothing was sent" >&2
  exit 1
fi
if grep -P '^\s*- keyHash:' "$rendered" | grep -vqP '^\s*- keyHash: sha256:[0-9a-f]{64}\s*$'; then
  echo "agentgateway: a keyHash that isn't a full hash is in the rendered config; nothing was sent" >&2
  exit 1
fi

on_host 'mkdir -p ~/gateway/agentgateway'

# The compose project, as gateway/ holds it, with deploy.env as the project's .env, the values its
# compose files read; the rendered config and Postgres's env file follow, each its own copy.
project=(compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env)
on_laptop "tar -C gateway --transform 's,^agentgateway/deploy.env\$,.env,' -cf - ${project[*]} | ssh $host 'tar -C ~/gateway -xf -'"
tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - "${project[@]}" |
  ssh "$host" 'tar -C ~/gateway -xf -'

on_laptop "ssh $host 'umask 077 && cat > ~/gateway/postgres.env' < $state/postgres.<tmp>.env"
ssh "$host" 'umask 077 && cat > ~/gateway/postgres.env' <"$pg_env"

on_laptop "ssh $host 'cat > ~/gateway/agentgateway/config.yaml.next' < $state/config.rendered.<tmp>.yaml"
ssh "$host" 'cat > ~/gateway/agentgateway/config.yaml.next' <"$rendered"

on_host "docker image inspect $AGW_IMAGE >/dev/null 2>&1 || docker pull $AGW_IMAGE"

# The copy is validated as the container reads it: as the deploying user, its directory mounted
# read-only. Validation parses the config and connects to nothing, Postgres included.
on_host "docker run --rm --user \"\$(id -u):\$(id -g)\" --volume \"\$HOME/gateway/agentgateway:/config:ro\" \
$AGW_IMAGE -f /config/config.yaml.next --validate-only"
# agentgateway follows config.yaml across the rename that moves a new copy into place.
on_host 'mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml'

# The container `docker run` created before the compose project holds the name and the ports
# compose's agentgateway takes; it carries no compose project label. Removed once, on the first
# compose deploy.
owner=$(on_host "docker container inspect agentgateway \
--format '{{index .Config.Labels \"com.docker.compose.project\"}}' 2>/dev/null || echo absent")
case $owner in
  gateway | absent) ;;
  *) on_host 'docker rm --force agentgateway' ;;
esac

on_host 'gateway/compose.sh up --detach --wait --build'
on_host 'gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"'
