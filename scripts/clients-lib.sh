#!/usr/bin/env bash
# The client steps through the gateway, each with a gateway-issued key: go-ai's integration tier
# and infer's, the released infer CLI, and curl, for the routing task's behavior checks and probes
# (and the agentgateway task's before it). Sourced from the repository root on the laptop, then
# called one step at a time in the architect's view:
#
#   source scripts/clients-lib.sh
#
#   gw_base <alias>   the alias's base URL on the gateway, http://gb10-2:3000/<alias>/v1, the port
#                     read from gateway/agentgateway/deploy.env
#   goai_checkout     a worktree of go-ai at tools/infer/v0.1.0, detached, under
#                     .state/priority/go-ai; go-ai's own working tree is not touched
#   infer_install     the released infer, `go install ...tools/infer/cmd/infer@v0.1.0`, into
#                     .state/priority/bin
#   goai_tier <name> <alias>...
#                     go-ai's integration tier, from the worktree, with each alias's role set to
#                     its base URL on the gateway; output in .state/priority/clients/<name>.log
#   infer_tier <name> <alias>...
#                     infer's integration tier the same way, from the worktree's tools/infer
#   infer_at <alias> <infer argument>...
#                     the released infer once, INFER_BASE_URL at the alias's base URL, no model
#   gw_curl <key> <curl argument>...
#                     curl with the named key's credential header, read from its key file
#   az_curl <path> <curl argument>...
#                     curl straight to the spike's Azure AI Foundry account, past the gateway, at
#                     https://$AZURE_ACCOUNT.services.ai.azure.com/openai/v1/<path>, with the
#                     account's key (below); the request names its deployment in "model"
#   row_burst <alias> <count> [<max tokens>]
#                     <count> chat requests at once straight to the alias's row, past the gateway
#                     and with no key, each generating <max tokens> (512 by default) with
#                     ignore_eos so all are in flight together; prints how many replies had each
#                     status, so a count one past the row's --max-num-queued-reqs shows its 503
#   azure_count <since> [<until>]
#                     the requests Azure AI Foundry answered, read from the gateway's access log on
#                     gb10-2 since <since> (and until <until>), a time `docker logs` takes: an RFC
#                     3339 time such as 2026-11-16T14:05:00 (local), or a Unix time. Counted per
#                     alias, so per deployment, and per status; read-only, and it prints counts
#                     only (below)
#   budget_status [<key>]
#                     each key's token budget, or the named key's, as the gateway counts it now:
#                     its limit, its use in the current window, whether it is exceeded, its action
#                     (Block or Audit), and the window's end; read from the UI's
#                     /api/budgets/status on gb10-2's loopback over SSH, read-only (below)
#   request_log [<count>]
#                     the newest <count> rows (10 by default) of the request log in Postgres on
#                     gb10-2, read-only, a fixed set of columns: time (UTC), status, the key's
#                     name as agentgateway logged it and as the UI's user, provider, model,
#                     tokens, duration, and whether a payload row was kept; then the count of
#                     payload rows, which `llm: metadata` keeps at none (below)
#   logged <command>  any other step, given as one string: run with bash from the root, logged as
#                     written, and its output, stdout and stderr, appended to the log as printed;
#                     for a command that prints no key, such as `mise run agentgateway-deploy`, a
#                     curl without a key, or `mise run watch`
#
# The base URL. The gateway serves each alias through its own route on the consumer port, so its
# base URL is /<alias>/v1 there, whose /v1/models lists the alias alone
# (gateway/agentgateway/config.yaml).
#
# The keys. Every helper reads a key from .state/agentgateway/keys/<name>, where the deploy keeps
# them, with bash's `$(<file)` inside a subshell, with xtrace off there, into the environment of the
# one process that sends it: AI_<ROLE>_TOKEN for go-ai's and infer's tiers, INFER_TOKEN for infer,
# or curl's config read from its stdin (`curl -K -`, written by printf, a builtin). No key is ever
# in a process's argv, printed, or logged; the log shows only the expression that reads it. go-ai's
# and infer's tiers send a role's credential from AI_<ROLE>_TOKEN or AI_<ROLE>_HEADER and print
# neither value on any failure (go-ai's integration/doc.go and tools/infer/integration/doc.go at
# tools/infer/v0.1.0); infer has no flag for INFER_TOKEN or INFER_HEADER. After each tier run, the
# helper searches its log for the key (`grep -F -f` the key file) and says whether it was found.
#
# The credential's place: Bearer by default, as the gateway reads it. With CLIENTS_KEY_IN=header,
# the key is sent as `x-api-key: <key>` instead, through AI_<ROLE>_HEADER, INFER_HEADER, or the
# curl header, for the gateway with the `key-header` probes overlay deployed.
#
# Azure. az_curl reads the Azure AI Foundry account's key from .state/azure/key and its resource
# name from AZURE_ACCOUNT in .state/azure/account.env, both untracked, written when the account is
# set up. Both reach curl only in the config it reads from its stdin, the header and the URL
# together, so neither is in a process's argv, printed, or logged: the log shows the expressions
# that read them. A curl error that names its host would print the account's name, so pass -s
# without -S, and no --write-out naming the URL.
#
# The Azure request count. Each reply an Azure deployment answers carries `x-gateway-overflow:
# azure`, which the gateway's access log records on that request's line as `overflow="azure"`
# (gateway/agentgateway/config.yaml); the line's route names the alias, and each alias overflows to
# one deployment (CLIENTS_DEPLOYMENT). azure_count reads `docker logs` of the agentgateway container
# over SSH and keeps only counts: a log line names the Azure account's host in `endpoint`, so no
# line is printed or logged. It also counts the lines that went to Azure with no marker, a request
# Azure never answered (`gen_ai.provider.name=azure`: a failed connection, or a reply the gateway
# couldn't read), and flags Azure's 429, a stop condition of the task's cap. One line is one client
# request, its last attempt: an Azure 503 that the route retried leaves no line of its own. The log
# lasts as long as the container, which compose recreates only when the config's `config` section
# or the stack changes, so the count is read after each step, not once at the end. What counts
# toward the cap of 300 is Azure's 2xx and its 4xx other than 429; its 429s, refused without being
# processed, are printed apart (the architect's decision after benchmark C-agent, 2026-11-16).
#
# Budgets and the request log (the priority task's behaviors 15 and 16). budget_status reads
# agentgateway's own count, which the UI serves at /api/budgets/status, filtered by key name
# (crates/agentgateway/src/ui.rs, budget_status) [src]; the UI's port is published on gb10-2's
# loopback only (gateway/agentgateway.yml), so it is read there with curl over SSH. Each budget is
# printed by its key's name, never by the key's hash, which names it in Postgres's budget_usage.
# request_log reads Postgres's request_logs table from inside its container with psql, the query
# sent on psql's stdin; it selects named columns only, never attributes_json whole, which holds the
# caller's address and an overflow's endpoint, the Azure account's host. The UI itself is reached
# through an SSH tunnel, `mise run gateway:ui`, at http://localhost:3001/ui.
#
# The command log. Each helper call and each command it runs is appended to
# .state/priority/commands-<YYYY-MM-DD>.log and printed to stderr as
# `+ <ISO time> <host>: <command>`, the form measure-lib.sh and the deploy script print.

if ! (return 0 2>/dev/null); then
  echo 'clients-lib.sh is sourced, not run: source scripts/clients-lib.sh' >&2
  exit 2
fi

CLIENTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Relative to the root: every command runs from there, so the log names no home directory.
CLIENTS_STATE=.state/priority
CLIENTS_KEYS=.state/agentgateway/keys
CLIENTS_AZURE=.state/azure
CLIENTS_HOST=gb10-2
CLIENTS_GOAI_REPO=$HOME/architecture/go-ai
# go-ai's release that carries per-role credentials in both tiers: tools/infer/v0.1.0. Its base
# module's code is v0.1.0's; only the integration tier's files and docs differ from the v0.1.0 tag.
CLIENTS_GOAI_TAG=tools/infer/v0.1.0
CLIENTS_WORKTREE=$CLIENTS_STATE/go-ai
CLIENTS_INFER=$CLIENTS_STATE/bin/infer

# The consumer port, deploy.env's AGW_PORT.
# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env is assignments.
source "$CLIENTS_ROOT/gateway/agentgateway/deploy.env"

# Each alias's role in go-ai's tiers.
declare -gA CLIENTS_ROLE=(
  [agent]=AGENT
  [vision]=VISION
  [audio]=AUDIO
  [embedding]=EMBEDDING
)

# Each alias's Azure AI Foundry deployment, its overflow (config.yaml's `<alias>-azure` provider).
declare -gA CLIENTS_DEPLOYMENT=(
  [agent]=gpt-oss-120b
  [vision]=gpt-5-mini
  [audio]=gpt-audio-mini
  [embedding]=text-embedding-3-small
)

# Each alias's row, as host:port, as measure-lib.sh's MEASURE_ROW.
declare -gA CLIENTS_ROW=(
  [agent]=gb10-1:8000
  [vision]=gb10-2:8000
  [audio]=framework:8001
  [embedding]=framework:8002
)

gw_base() {
  local alias=${1:?usage: gw_base <alias>}
  [[ -n ${CLIENTS_ROLE[$alias]-} ]] || {
    echo "gw_base: unknown alias $alias (agent, vision, audio, embedding)" >&2
    return 2
  }
  echo "http://$CLIENTS_HOST:$AGW_PORT/$alias/v1"
}

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
    printf "'x-api-key: '\$(<%s)" "$CLIENTS_KEYS/$1"
  else
    printf '$(<%s)' "$CLIENTS_KEYS/$1"
  fi
}

_clients_key_ok() {
  if [[ ! -s $CLIENTS_ROOT/$CLIENTS_KEYS/$1 ]]; then
    echo "no key at $CLIENTS_KEYS/$1; run mise run agentgateway-deploy first" >&2
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
    shown+="AI_${CLIENTS_ROLE[$alias]}_BASE_URL=$(gw_base "$alias") "
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
    key=$(<"$CLIENTS_ROOT/$CLIENTS_KEYS/go-ai")
    for alias in "$@"; do
      export "AI_${CLIENTS_ROLE[$alias]}_BASE_URL=$(gw_base "$alias")"
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
    grep -qF -f "$CLIENTS_ROOT/$CLIENTS_KEYS/go-ai" "$CLIENTS_ROOT/$out" 2>/dev/null
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
  _clients_log laptop "$cred=$(_clients_shown go-ai) INFER_BASE_URL=$(gw_base "$alias") $CLIENTS_INFER $*"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT" || exit
    unset INFER_TOKEN INFER_HEADER INFER_MODEL
    key=$(<"$CLIENTS_KEYS/go-ai")
    if [[ $cred == INFER_HEADER ]]; then
      export INFER_HEADER="x-api-key: $key"
    else
      export INFER_TOKEN=$key
    fi
    unset key
    INFER_BASE_URL=$(gw_base "$alias")
    export INFER_BASE_URL
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
  _clients_log laptop "printf 'header = \"$header%s\"\\n' \"\$(<$CLIENTS_KEYS/$name)\" | curl -K - $*"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT" || exit
    # shellcheck disable=SC2059 # The format is built from a fixed header name.
    printf "header = \"$header%s\"\n" "$(<"$CLIENTS_KEYS/$name")" | curl -K - "$@"
  )
}

az_curl() {
  (($# >= 1)) || {
    echo 'usage: az_curl <path under /openai/v1> <curl argument>...' >&2
    return 2
  }
  local path=$1
  shift
  if [[ ! -s $CLIENTS_ROOT/$CLIENTS_AZURE/key || ! -s $CLIENTS_ROOT/$CLIENTS_AZURE/account.env ]]; then
    echo "no key or account at $CLIENTS_AZURE/key and $CLIENTS_AZURE/account.env; set up the account first" >&2
    return 2
  fi
  # The account's name is read from account.env as an assignment, not sourced, in the subshell
  # below; the log shows the expression.
  local name_expr="\$(sed -n 's/^AZURE_ACCOUNT=//p' $CLIENTS_AZURE/account.env | tr -d \\\"\\')"
  _clients_log laptop "printf 'header = \"api-key: %s\"\\nurl = \"https://%s.services.ai.azure.com/openai/v1/$path\"\\n' \"\$(<$CLIENTS_AZURE/key)\" \"$name_expr\" | curl -K - $*"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT" || exit
    printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/%s"\n' \
      "$(<"$CLIENTS_AZURE/key")" \
      "$(sed -n 's/^AZURE_ACCOUNT=//p' "$CLIENTS_AZURE/account.env" | tr -d \"\')" "$path" |
      curl -K - "$@"
  )
}

row_burst() {
  (($# == 2 || $# == 3)) || {
    echo 'usage: row_burst <alias> <count> [<max tokens>]' >&2
    return 2
  }
  local alias=$1 count=$2 tokens=${3:-512}
  [[ $alias != embedding && -n ${CLIENTS_ROW[$alias]-} ]] || {
    echo "row_burst: no chat row for $alias (agent, vision, audio)" >&2
    return 2
  }
  [[ $count =~ ^[1-9][0-9]*$ && $tokens =~ ^[1-9][0-9]*$ ]] || {
    echo 'row_burst: <count> and <max tokens> are positive integers' >&2
    return 2
  }
  # Each request names the row's one served name, its alias, and asks for exactly <max tokens>.
  local body
  body=$(printf '{"model":"%s","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":%d,"ignore_eos":true}' "$alias" "$tokens")
  logged "for i in \$(seq $count); do curl -s -o /dev/null -w '%{http_code}\\n' -H 'content-type: application/json' -d '$body' http://${CLIENTS_ROW[$alias]}/v1/chat/completions & done | sort | uniq -c"
}

azure_count() {
  (($# == 1 || $# == 2)) || {
    echo 'usage: azure_count <since> [<until>]' >&2
    return 2
  }
  local t
  for t in "$@"; do
    [[ $t =~ ^[0-9][0-9T:.Z+-]*$ ]] || {
      echo "azure_count: $t isn't a time docker logs takes (2026-11-16T14:05:00, or a Unix time)" >&2
      return 2
    }
  done
  local remote="docker logs --since $1${2:+ --until $2} agentgateway 2>&1" a deployments='' log rc
  for a in agent vision audio embedding; do
    deployments+="$a=${CLIENTS_DEPLOYMENT[$a]} "
  done
  _clients_log laptop "ssh -n $CLIENTS_HOST '$remote' | the request lines with overflow=\"azure\" or gen_ai.provider.name=azure, counted per route and status"
  # The log is read whole before it is counted, so a log that wasn't read gives no count, rather
  # than counts of nothing that read as nothing sent to Azure. It is held, never printed.
  # shellcheck disable=SC2029 # The command is built on the laptop, with no secret in it.
  log=$(ssh -n "$CLIENTS_HOST" "$remote") || {
    rc=$?
    echo "reading the gateway log failed (ssh exit $rc); no count" | _clients_say azure_count
    return "$rc"
  }
  awk -v since="$1" -v until="${2:-now}" -v deployments="$deployments" '
      BEGIN { n = split(deployments, d, " "); for (i = 1; i <= n; i++) { split(d[i], kv, "="); ord[i] = kv[1]; dep[kv[1]] = kv[2] } }
      /[ \t]request / {
        answered = index($0, " overflow=\"azure\"") > 0
        if (!answered && $0 !~ / gen_ai\.provider\.name=azure( |$)/) next
        alias = "?"; st = "-"
        if (match($0, / route=default\/[a-z]+ /)) alias = substr($0, RSTART + 15, RLENGTH - 16)
        if (match($0, / http\.status=[0-9]+/)) st = substr($0, RSTART + 13, RLENGTH - 13)
        if (!answered) { unanswered[alias]++; nu++; next }
        total++; per[alias]++; status[alias, st]++; if (st == 429) limited++; else if (st ~ /^[24][0-9][0-9]$/) counted++
      }
      END {
        printf "Azure answered %d requests from %s to %s\n", total, since, until
        for (i = 1; i <= n; i++) {
          a = ord[i]; line = ""
          for (k in status) { split(k, ks, SUBSEP); if (ks[1] == a) line = line (line ? ", " : "") ks[2] " x" status[k] }
          printf "  %s (%s): %d%s%s\n", a, dep[a], per[a], (line ? ": " line : ""), (unanswered[a] ? sprintf("; %d sent with no reply from Azure", unanswered[a]) : "")
        }
        printf "  toward the cap of 300: %d (2xx, and 4xx other than 429); 429, reported apart: %d\n", counted, limited
        if (limited) printf "  STOP: Azure answered 429 %d times; the task stops and escalates\n", limited
      }' <<<"$log" | _clients_say azure_count
  return "${PIPESTATUS[0]}"
}

budget_status() {
  (($# <= 1)) || {
    echo 'usage: budget_status [<key>]' >&2
    return 2
  }
  [[ $# == 0 || $1 =~ ^[a-z0-9-]+$ ]] || {
    echo "budget_status: $1 isn't a key name" >&2
    return 2
  }
  # -f: an error reply fails the call rather than reaching jq as a body with no budgets in it.
  local remote="curl -fsS --max-time 5 'http://127.0.0.1:$AGW_UI_PORT/api/budgets/status${1:+?apiKeyName=$1}'"
  _clients_log laptop "ssh -n $CLIENTS_HOST \"$remote\" | jq -r '.budgets[] | one line each'"
  # shellcheck disable=SC2029 # The command is built on the laptop, with no secret in it.
  ssh -n "$CLIENTS_HOST" "$remote" |
    jq -r '.budgets | sort_by(.apiKeyName)[]
      | "\(.apiKeyName) \(.name): used \(.usage.used) of \(.limit.amount) \(.limit.unit), exceeded \(.usage.exceeded), \(.onBudgetExceeded); window ends \(if .window.end then (.window.end / 1000 | localtime | strftime("%H:%M:%S")) else "never" end)"' |
    _clients_say budget_status
  local st=("${PIPESTATUS[@]}")
  return $((st[0] ? st[0] : st[1]))
}

request_log() {
  (($# <= 1)) || {
    echo 'usage: request_log [<count>]' >&2
    return 2
  }
  local count=${1:-10}
  [[ $count =~ ^[1-9][0-9]*$ ]] || {
    echo 'request_log: <count> is a positive integer' >&2
    return 2
  }
  local query
  query="select to_char(completed_at at time zone 'UTC', 'HH24:MI:SS') as completed_utc,
  http_status as status, attributes_json->>'agw.api_key.name' as key, agentgateway_user as ui_user,
  gen_ai_provider_name as provider, gen_ai_request_model as model, input_tokens as input,
  output_tokens as output, total_tokens as total, duration_ms, has_payload
  from request_logs order by completed_at desc limit $count;
select count(*) as payload_rows from request_log_payloads;"
  # ON_ERROR_STOP: psql reading a script on stdin exits 0 after a failed statement without it.
  _clients_log laptop "ssh $CLIENTS_HOST 'docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -v ON_ERROR_STOP=1 -P pager=off' <<< \"${query//$'\n'/ }\""
  ssh "$CLIENTS_HOST" 'docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -v ON_ERROR_STOP=1 -P pager=off' \
    <<<"$query" | _clients_say request_log
  return "${PIPESTATUS[0]}"
}

logged() {
  (($# == 1)) || {
    echo 'usage: logged <command, as one string>' >&2
    return 2
  }
  _clients_log laptop "$1"
  (cd "$CLIENTS_ROOT" && bash -c "$1") 2>&1 |
    tee -a "$CLIENTS_ROOT/$CLIENTS_STATE/commands-$(date +%F).log"
  return "${PIPESTATUS[0]}"
}

mkdir -p "$CLIENTS_ROOT/$CLIENTS_STATE"
_clients_log laptop "source scripts/clients-lib.sh"
