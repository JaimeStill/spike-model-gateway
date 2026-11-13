#!/usr/bin/env bash
# Deploys agentgateway to gb10-2 from the laptop over Tailscale SSH, from gateway/agentgateway/:
# config.yaml and the image and ports of deploy.env. Idempotent. It creates any consumer key
# config.yaml names that this machine lacks, renders the config with each key's hash, copies that
# beside the live one, pulls the pinned image if gb10-2 lacks it, validates the copy with that
# image, and moves it into place, where agentgateway reloads it with no restart. It then creates
# the container again only when its image or flags changed, or starts it if it is stopped;
# otherwise the config refresh is all a re-run does.
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
#
# Lines before the first directive must be comments or blank. The copy's first line names the
# overlays it carries (`# overlays: none` without), so `head -1 ~/agentgateway/config.yaml` on
# gb10-2 reads what is live.
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
        after)
          at=() i=
          for i in "${!lines[@]}"; do
            [[ ${lines[i]} != "$anchor" ]] || at+=("$i")
          done
          ((${#at[@]} == 1)) ||
            overlay_fail "$overlay" "${#at[@]} lines equal \"$anchor\"; one is needed"
          lines=("${lines[@]:0:at[0]+1}" "${section[@]}" "${lines[@]:at[0]+1}")
          ;;
      esac
      section=()
      case $raw in
        '#@ append') mode=append ;;
        '#@ after '*) mode=after anchor=${raw#'#@ after '} ;;
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

# The copy sent to gb10-2: config.yaml, its overlays applied, with each marker replaced by its
# key's hash. It is written only under .state/, which is untracked, and removed on exit. Replaced
# in bash, not by sed, so no hash is in a command's argv either.
rendered=$(mktemp "$state/config.rendered.XXXXXX.yaml")
trap 'rm -f "$rendered"' EXIT
marker='^(.*)sha256:@@([a-z0-9-]+)@@(.*)$'
{
  printf '# overlays: %s\n' "${*:-none}"
  for line in "${lines[@]}"; do
    if [[ $line =~ $marker && -n ${hashes[${BASH_REMATCH[2]}]+set} ]]; then
      line="${BASH_REMATCH[1]}sha256:${hashes[${BASH_REMATCH[2]}]}${BASH_REMATCH[3]}"
    fi
    printf '%s\n' "$line"
  done
} >"$rendered"
# A marker left over, or a keyHash that isn't a full hash, would deploy a key list that admits no
# one under that name; stop before anything is sent.
if grep -qP '@@[a-z0-9-]+@@' "$rendered" ||
  grep -P '^\s*- keyHash:' "$rendered" | grep -vqP '^\s*- keyHash: sha256:[0-9a-f]{64}\s*$'; then
  echo "agentgateway: a key marker, or a keyHash that isn't a full hash, is in the rendered config; nothing was sent" >&2
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
