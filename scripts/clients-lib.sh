#!/usr/bin/env bash
# The agentgateway task's client steps for slice 3 (behaviors 9-11): go-ai's integration tier and
# infer's, the released infer CLI, and the curl requests of the 429 and 503 probes, each through
# the gateway with a gateway-issued key. Sourced from the repository root on the laptop, then
# called one step at a time in the architect's view:
#
#   source scripts/clients-lib.sh
#
#   goai_checkout     a worktree of go-ai at tools/infer/v0.1.0, detached, under
#                     .state/agentgateway/go-ai; go-ai's own working tree is not touched
#   infer_install     the released infer, `go install ...tools/infer/cmd/infer@v0.1.0`, into
#                     .state/agentgateway/bin
#   goai_tier <name> <alias>...
#                     go-ai's integration tier, from the worktree, with each alias's role set to
#                     its base URL on the gateway; output in .state/agentgateway/clients/<name>.log
#   infer_tier <name> <alias>...
#                     infer's integration tier the same way, from the worktree's tools/infer
#   infer_at <alias> <infer argument>...
#                     the released infer once, INFER_BASE_URL at the alias's base URL, no model
#   gw_curl <key> <curl argument>...
#                     curl with the named key's credential header, read from its key file
#
# The keys. Every helper reads a key from .state/agentgateway/keys/<name> with bash's `$(<file)`
# inside a subshell, with xtrace off there, into the environment of the one process that sends
# it: AI_<ROLE>_TOKEN for go-ai's and infer's tiers, INFER_TOKEN for infer, or curl's config read
# from its stdin (`curl -K -`, written by printf, a builtin). No key is ever in a process's argv,
# printed, or logged; the log shows only the expression that reads it. go-ai's and infer's tiers
# send a role's credential from AI_<ROLE>_TOKEN or AI_<ROLE>_HEADER and print neither value on any
# failure (go-ai's integration/doc.go and tools/infer/integration/doc.go at tools/infer/v0.1.0);
# infer has no flag for INFER_TOKEN or INFER_HEADER. After each tier run, the helper searches its
# log for the key (`grep -F -f` the key file) and says whether it was found.
#
# The credential's place: Bearer by default, as the gateway reads it. With CLIENTS_KEY_IN=header,
# the key is sent as `x-api-key: <key>` instead, through AI_<ROLE>_HEADER, INFER_HEADER, or the
# curl header, for the gateway with the `key-header` probes overlay deployed.
#
# The command log. Each helper call and each command it runs is appended to
# .state/agentgateway/commands-<YYYY-MM-DD>.log and printed to stderr as
# `+ <ISO time> <host>: <command>`, the form measure-lib.sh and the deploy script print.

if ! (return 0 2>/dev/null); then
  echo 'clients-lib.sh is sourced, not run: source scripts/clients-lib.sh' >&2
  exit 2
fi

CLIENTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Relative to the root: every command runs from there, so the log names no home directory.
CLIENTS_STATE=.state/agentgateway
CLIENTS_GATEWAY=http://gb10-2:3000
CLIENTS_GOAI_REPO=$HOME/architecture/go-ai
# go-ai's release that carries per-role credentials in both tiers: tools/infer/v0.1.0. Its base
# module's code is v0.1.0's; only the integration tier's files and docs differ from the v0.1.0 tag.
CLIENTS_GOAI_TAG=tools/infer/v0.1.0
CLIENTS_WORKTREE=$CLIENTS_STATE/go-ai
CLIENTS_INFER=$CLIENTS_STATE/bin/infer

# Each alias's role in go-ai's tiers.
declare -gA CLIENTS_ROLE=(
  [agent]=AGENT
  [vision]=VISION
  [audio]=AUDIO
  [embedding]=EMBEDDING
)

_clients_log() {
  printf '+ %s %s: %s\n' "$(date -Iseconds)" "$1" "$2" |
    tee -a "$CLIENTS_ROOT/$CLIENTS_STATE/commands-$(date +%F).log" >&2
}

# Copies its input to stdout, and each non-empty line to the day's log as
# `= <time> <helper>: <line>`.
_clients_say() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
    [[ -z $line ]] ||
      printf '= %s %s: %s\n' "$(date -Iseconds)" "$1" "$line" \
        >>"$CLIENTS_ROOT/$CLIENTS_STATE/commands-$(date +%F).log"
  done
}

# The credential's variable expression for the log, and its value for the environment.
# shellcheck disable=SC2016 # The expression is logged as written, never expanded.
_clients_shown() {
  if [[ ${CLIENTS_KEY_IN:-bearer} == header ]]; then
    printf "'x-api-key: '\$(<%s)" "$CLIENTS_STATE/keys/$1"
  else
    printf '$(<%s)' "$CLIENTS_STATE/keys/$1"
  fi
}

_clients_key_ok() {
  if [[ ! -s $CLIENTS_ROOT/$CLIENTS_STATE/keys/$1 ]]; then
    echo "no key at $CLIENTS_STATE/keys/$1; run mise run agentgateway-deploy first" >&2
    return 2
  fi
}

goai_checkout() {
  local wt=$CLIENTS_ROOT/$CLIENTS_WORKTREE
  if [[ -d $wt ]]; then
    echo "goai_checkout: $CLIENTS_WORKTREE exists, at $(git -C "$wt" describe --tags)" >&2
    return 0
  fi
  _clients_log laptop "git -C ~/architecture/go-ai worktree add --detach $CLIENTS_WORKTREE $CLIENTS_GOAI_TAG"
  git -C "$CLIENTS_GOAI_REPO" worktree add --detach "$wt" "$CLIENTS_GOAI_TAG"
}

infer_install() {
  _clients_log laptop "GOBIN=$CLIENTS_STATE/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.1.0 && $CLIENTS_INFER version"
  (
    cd "$CLIENTS_ROOT" || exit
    GOBIN=$CLIENTS_ROOT/$CLIENTS_STATE/bin go install \
      github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.1.0 &&
      "$CLIENTS_INFER" version
  )
}

# Runs one tier: go-ai's (dir .) or infer's (dir tools/infer), in the worktree, verbose, with the
# go-ai key as each named alias's credential and every other role unset, so it skips.
_clients_tier() {
  local kind=$1 sub=$2 name=$3 alias rc
  shift 3
  local usage="usage: ${kind}_tier <name> <alias>..."
  (($# > 0)) || {
    echo "$usage" >&2
    return 2
  }
  for alias in "$@"; do
    [[ -n ${CLIENTS_ROLE[$alias]-} ]] || {
      echo "${kind}_tier: unknown alias $alias (agent, vision, audio, embedding)" >&2
      return 2
    }
  done
  _clients_key_ok go-ai || return
  [[ -d $CLIENTS_ROOT/$CLIENTS_WORKTREE ]] || {
    echo "${kind}_tier: no worktree; run goai_checkout first" >&2
    return 2
  }
  local out=$CLIENTS_STATE/clients/$name.log
  if [[ -e $CLIENTS_ROOT/$out ]]; then
    echo "${kind}_tier: $out exists; name each run once" >&2
    return 2
  fi
  mkdir -p "$CLIENTS_ROOT/$CLIENTS_STATE/clients"
  local shown='' cred=TOKEN
  [[ ${CLIENTS_KEY_IN:-bearer} != header ]] || cred=HEADER
  for alias in "$@"; do
    shown+="AI_${CLIENTS_ROLE[$alias]}_BASE_URL=$CLIENTS_GATEWAY/$alias/v1 "
    shown+="AI_${CLIENTS_ROLE[$alias]}_$cred=$(_clients_shown go-ai) "
  done
  _clients_log laptop "${kind}_tier $name $*"
  _clients_log laptop "cd $CLIENTS_WORKTREE/$sub && ${shown}GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee $out"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT/$CLIENTS_WORKTREE/$sub" || exit
    # Every role's variables from the caller's shell cleared, so only the named roles run.
    for v in "${CLIENTS_ROLE[@]}" TRANSCRIPTION; do
      unset "AI_${v}_BASE_URL" "AI_${v}_TOKEN" "AI_${v}_HEADER"
    done
    key=$(<"$CLIENTS_ROOT/$CLIENTS_STATE/keys/go-ai")
    for alias in "$@"; do
      export "AI_${CLIENTS_ROLE[$alias]}_BASE_URL=$CLIENTS_GATEWAY/$alias/v1"
      if [[ $cred == HEADER ]]; then
        export "AI_${CLIENTS_ROLE[$alias]}_HEADER=x-api-key: $key"
      else
        export "AI_${CLIENTS_ROLE[$alias]}_TOKEN=$key"
      fi
    done
    unset key
    export GOWORK=off
    go test -race -tags integration -count=1 -v ./integration/... 2>&1 |
      tee "$CLIENTS_ROOT/$out"
    exit "${PIPESTATUS[0]}"
  )
  rc=$?
  {
    echo "$name: exit $rc"
    # grep's 1 is "not found"; any other failure is no answer, and says so.
    grep -qF -f "$CLIENTS_ROOT/$CLIENTS_STATE/keys/go-ai" "$CLIENTS_ROOT/$out" 2>/dev/null
    case $? in
      0) echo "$name: THE KEY IS IN $out; delete it before anything is shared" ;;
      1) echo "$name: the key is not in $out" ;;
      *) echo "$name: THE KEY SEARCH FAILED on $out; search it before anything is shared" ;;
    esac
    echo "$name: $(grep -c -- '^--- PASS' "$CLIENTS_ROOT/$out") passed, $(grep -c -- '^--- FAIL' "$CLIENTS_ROOT/$out") failed, $(grep -c -- '^--- SKIP' "$CLIENTS_ROOT/$out") skipped (top-level tests)"
  } | _clients_say "${kind}_tier"
  return "$rc"
}

goai_tier() { _clients_tier goai . "$@"; }
infer_tier() { _clients_tier infer tools/infer "$@"; }

infer_at() {
  (($# >= 2)) || {
    echo 'usage: infer_at <alias> <infer argument>...' >&2
    return 2
  }
  local alias=$1
  shift
  [[ -n ${CLIENTS_ROLE[$alias]-} ]] || {
    echo "infer_at: unknown alias $alias" >&2
    return 2
  }
  _clients_key_ok go-ai || return
  [[ -x $CLIENTS_ROOT/$CLIENTS_INFER ]] || {
    echo 'infer_at: no infer; run infer_install first' >&2
    return 2
  }
  local cred=INFER_TOKEN
  [[ ${CLIENTS_KEY_IN:-bearer} != header ]] || cred=INFER_HEADER
  _clients_log laptop "$cred=$(_clients_shown go-ai) INFER_BASE_URL=$CLIENTS_GATEWAY/$alias/v1 $CLIENTS_INFER $*"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT" || exit
    unset INFER_TOKEN INFER_HEADER INFER_MODEL
    key=$(<"$CLIENTS_STATE/keys/go-ai")
    if [[ $cred == INFER_HEADER ]]; then
      export INFER_HEADER="x-api-key: $key"
    else
      export INFER_TOKEN=$key
    fi
    unset key
    export INFER_BASE_URL=$CLIENTS_GATEWAY/$alias/v1
    exec "$CLIENTS_INFER" "$@"
  )
}

gw_curl() {
  (($# >= 2)) || {
    echo 'usage: gw_curl <key name> <curl argument>...' >&2
    return 2
  }
  local name=$1
  shift
  _clients_key_ok "$name" || return
  local header='Authorization: Bearer '
  [[ ${CLIENTS_KEY_IN:-bearer} != header ]] || header='x-api-key: '
  _clients_log laptop "printf 'header = \"$header%s\"\\n' \"\$(<$CLIENTS_STATE/keys/$name)\" | curl -K - $*"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT" || exit
    # shellcheck disable=SC2059 # The format is built from a fixed header name.
    printf "header = \"$header%s\"\n" "$(<"$CLIENTS_STATE/keys/$name")" | curl -K - "$@"
  )
}

mkdir -p "$CLIENTS_ROOT/$CLIENTS_STATE"
_clients_log laptop "source scripts/clients-lib.sh"
