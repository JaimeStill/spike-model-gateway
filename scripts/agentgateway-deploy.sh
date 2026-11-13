#!/usr/bin/env bash
# Deploys agentgateway to gb10-2 from the laptop over Tailscale SSH, from gateway/agentgateway/:
# config.yaml and the image and ports of deploy.env. Idempotent. It creates any consumer key
# config.yaml names that this machine lacks, renders the config with each key's hash, copies that
# beside the live one, pulls the pinned image if gb10-2 lacks it, validates the copy with that
# image, and moves it into place, where agentgateway reloads it with no restart. It then creates
# the container again only when its image or flags changed, or starts it if it is stopped;
# otherwise the config refresh is all a re-run does.
#
# Each command is printed to stderr before it runs, as `+ <time> <host>: <command>`, the form of
# .state/<task>/commands-*.log, so a finding can quote it exactly. Commands run on gb10-2 are sent
# as written: `$(tailscale ip -4)`, `$(id -u)`, and `$HOME` expand there, so the consumer port is
# published on gb10-2's tailnet address with no address written down or printed. Needs no root.
set -euo pipefail
cd "$(dirname "$0")/.."

host=gb10-2
# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env holds three assignments.
source gateway/agentgateway/deploy.env

# Prints the command given, then runs it on gb10-2, where it expands.
on_host() {
  printf '+ %s %s: %s\n' "$(date -Iseconds)" "$host" "$1" >&2
  # shellcheck disable=SC2029 # The command is built to expand on gb10-2.
  ssh "$host" "$1"
}

config=gateway/agentgateway/config.yaml
state=.state/agentgateway
keys=$state/keys

# Keys. config.yaml commits each key's name only, as the marker `keyHash: sha256:@@<name>@@`; the
# names are read from the markers, so adding an entry is all it takes to issue a key. A missing key
# is created on this machine, 0600 in a 0700 directory, and an existing one is reused, so a re-run
# changes nothing. Only names are printed: no key or hash reaches the terminal or the command log.
umask 077
mkdir -p "$keys"
chmod 700 "$keys"
mapfile -t names < <(grep -oP '^\s*- keyHash: sha256:@@\K[a-z0-9-]+(?=@@\s*$)' "$config")
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

# The copy sent to gb10-2: config.yaml with each marker replaced by its key's hash. It is written
# only under .state/, which is untracked, and removed on exit. Replaced in bash, not by sed, so no
# hash is in a command's argv either.
rendered=$(mktemp "$state/config.rendered.XXXXXX.yaml")
trap 'rm -f "$rendered"' EXIT
marker='^(.*)sha256:@@([a-z0-9-]+)@@(.*)$'
while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line =~ $marker && -n ${hashes[${BASH_REMATCH[2]}]+set} ]]; then
    line="${BASH_REMATCH[1]}sha256:${hashes[${BASH_REMATCH[2]}]}${BASH_REMATCH[3]}"
  fi
  printf '%s\n' "$line"
done <"$config" >"$rendered"
# A marker left over, or a keyHash that isn't a full hash, would deploy a key list that admits no
# one under that name; stop before anything is sent.
if grep -qP '@@[a-z0-9-]+@@' "$rendered" ||
  grep -P '^\s*- keyHash:' "$rendered" | grep -vqP '^\s*- keyHash: sha256:[0-9a-f]{64}\s*$'; then
  echo "agentgateway: a key marker is left in the rendered config; nothing was sent" >&2
  exit 1
fi

on_host 'mkdir -p ~/agentgateway'

printf '+ %s laptop: %s\n' "$(date -Iseconds)" \
  "ssh $host 'cat > ~/agentgateway/config.yaml.next' < $rendered" >&2
ssh "$host" 'cat > ~/agentgateway/config.yaml.next' <"$rendered"

on_host "docker image inspect $AGW_IMAGE >/dev/null 2>&1 || docker pull $AGW_IMAGE"

# The container runs as the deploying user and reads the config directory read-only. agentgateway
# follows config.yaml across the rename that moves a new copy into place.
# shellcheck disable=SC2016 # Both expand on gb10-2.
user='--user "$(id -u):$(id -g)"' mount='--volume "$HOME/agentgateway:/config:ro"'

on_host "docker run --rm $user $mount $AGW_IMAGE -f /config/config.yaml.next --validate-only"
on_host 'mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml'

# The container's image and flags, hashed into its spike.spec label: a container with the same
# label runs the same image with the same flags. The tailnet address isn't in the hash; a node keeps
# its address.
flags="--restart unless-stopped $user"
flags+=" --publish \"\$(tailscale ip -4):$AGW_PORT:$AGW_PORT\""
flags+=" --publish 127.0.0.1:$AGW_UI_PORT:$AGW_UI_PORT $mount"
# gb10-2 resolves names through systemd-resolved's stub (127.0.0.53), which a container can't
# reach, so docker gives it an outside resolver that doesn't know the tailnet's short names. Each
# row's host is added by its tailnet address, looked up on gb10-2 when the container is created.
for h in gb10-1 gb10-2 framework; do
  flags+=" --add-host \"$h:\$(tailscale ip -4 $h)\""
done
spec=$(printf '%s %s' "$flags" "$AGW_IMAGE" | sha256sum | cut -c1-12)

current=$(on_host "docker container inspect agentgateway \
--format '{{index .Config.Labels \"spike.spec\"}} {{.State.Running}}' 2>/dev/null || true")

case $current in
"$spec true")
  echo "agentgateway: image and flags unchanged; config.yaml reloads in place"
  ;;
"$spec false")
  on_host 'docker start agentgateway'
  ;;
*)
  if [[ -n $current ]]; then
    on_host 'docker rm --force agentgateway'
  fi
  on_host "docker run --detach --name agentgateway $flags --label spike.spec=$spec \
$AGW_IMAGE -f /config/config.yaml"
  ;;
esac

on_host "docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'"
