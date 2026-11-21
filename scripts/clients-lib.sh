#!/usr/bin/env bash
# The client steps through the gateway, each with a gateway-issued key: go-ai's integration tier
# and infer's, the released infer CLI, and curl, for the routing task's behavior checks and probes
# (and the agentgateway and priority tasks' before it), and the answer task's Go retry test.
# Sourced from the repository root on the laptop, then
# called one step at a time in the architect's view:
#
#   source scripts/clients-lib.sh
#
#   gw_base <alias>   the alias's base URL on the gateway, http://gb10-2:3000/<alias>/v1, the port
#                     read from gateway/agentgateway/deploy.env
#   goai_checkout     a worktree of go-ai at tools/infer/v0.3.1, detached, under
#                     .state/max-tokens-note/go-ai-v0.3.1, a path of its own per release, so a
#                     pin's move never reuses the last release's worktree; go-ai's own working
#                     tree is not touched
#   infer_install     the released infer, `go install ...tools/infer/cmd/infer@v0.3.1`, into
#                     .state/max-tokens-note/bin
#   goai_tier [-run <regexp>] <name> <alias>...
#                     go-ai's integration tier, from the worktree, with each alias's role set to
#                     its base URL on the gateway and its profile for CLIENTS_TARGET (below);
#                     output in .state/max-tokens-note/clients/<name>.log; with -run, only the
#                     tests `go test -run <regexp>` selects
#   infer_tier [-run <regexp>] <name> <alias>...
#                     infer's integration tier the same way, from the worktree's tools/infer
#   priority_rerun <name>
#                     the tests priority's finding lists as failing on Azure, rows down, rerun:
#                     goai_tier -run with CLIENTS_PRIORITY_GOAI_FAILED as <name>-goai, then
#                     infer_tier -run with CLIENTS_PRIORITY_INFER_FAILED as <name>-infer, each on
#                     all four aliases (below)
#   infer_at <alias> <infer argument>...
#                     the released infer, INFER_BASE_URL at the alias's base URL, no model and no
#                     profile; infer v0.3.1 sends each request up to 3 times by default
#   infer_once <alias> <infer argument>...
#                     infer_at with `--retries 1` first, so each request is sent exactly once: for
#                     a probe that reads one reply's status
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
#   audio_rerun <name>
#                     go-ai's two audio tests on Azure, with the rows-down overlay deployed: for
#                     each of TestAudioInResponsesRefused and TestTranscribeChat, two small
#                     text-only audio requests to warm the audio row's eviction, then the test
#                     alone, as goai_tier -run '^<test>$' <name>-<test> audio; then azure_count
#                     since the first warm-up (below)
#   pg_password_rotate
#                     a new Postgres password: created on the laptop as
#                     .state/agentgateway/postgres-password.next, set on gb10-2 with ALTER USER
#                     through psql in the Postgres container, then moved over
#                     .state/agentgateway/postgres-password; a deploy then sends it (below)
#   retry_case <case> the spike's Go retry test (retry/), one case: rate-limit-agent,
#                     embedding-burst, in-flight-1, or bulk-rate-low; output in
#                     .state/max-tokens-note/retry/<case>-<time>.log, and its per-attempt table
#                     beside it as <case>-<time>.tsv (below)
#   requests_shed     agentgateway's requests_shed metric, the in-flight limit's refusals, read
#                     from its stats port on gb10-2's loopback over SSH, read-only (below)
#   traces [-q <traceql>] [-n <count>] [<since>]
#   traces -t <trace id>...
#                     the traces Tempo holds on gb10-2: the newest <count> (20 by default) that
#                     the TraceQL query selects ({} by default, every trace) since <since>, any
#                     time `date -d` reads, such as '10 min ago' (15 minutes by default); or, with
#                     -t, the traces named. For each, its id, then each span in start order,
#                     indented under its parent: the service, the span's name, kind, id,
#                     parent, and duration in ms (its end less its start, to 0.1 ms), then its
#                     attribute keys, never their values; read-only (below)
#   messages_stream <alias> <max tokens> <prompt>
#                     one streamed Messages request, stream true, through the gateway on the
#                     alias with the architect key, the prompt as the one user message; under
#                     .state/max-tokens-note/stream/<alias>-<max tokens>-<time>: raw.tsv, each line
#                     of the stream with its arrival in microseconds from the send; events.tsv,
#                     each SSE event's arrival, name, and a content_block_delta's delta type;
#                     headers.txt, the reply's status line and response headers; and the summary
#                     printed and logged: status, the overflow marker, the time to the first event,
#                     to the first and last text delta, to message_delta and message_stop, the
#                     gaps from the last text delta to those two, the total, and the verdict
#                     (below)
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
# tools/infer/v0.3.1); infer has no flag for INFER_TOKEN or INFER_HEADER. After each tier run, the
# helper searches its log for the key (`grep -F -f` the key file) and says whether it was found.
#
# The target and the profiles (the answer task). Each tier run clears every role's base URL,
# credential, model, and profile from the caller's shell, then sets each named alias's profile,
# AI_<ROLE>_PROFILE, for what answers the alias: CLIENTS_TARGET=rows-up, the rows, or rows-down,
# the Azure deployments under the rows-down overlay. A tier refuses to run without one of the two.
# A profile declares what the deployment refuses, so a scenario it can't serve skips, naming the
# gap, rather than failing (go-ai's integration/doc.go at tools/infer/v0.3.1). Rows up: the agent
# row's vLLM 0.34.0 profile exactly as that doc.go gives it; go-ai documents none for the vision,
# audio, or embedding row, so they get none. Rows down: gpt-oss-120b's refusal of tool_choice
# required on agent, gpt-5-mini's refused efforts on vision, and none on audio or embedding.
# infer_at clears INFER_PROFILE, so a manual call is the spec's form.
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
# toward the cap is Azure's 2xx and its 4xx other than 429; its 429s, refused without being
# processed, are printed apart (the architect's decision after benchmark C-agent, 2026-11-16). The
# cap is the task's, CLIENTS_AZURE_CAP: 20 in the max-tokens-note task (the answer task's was 80,
# priority's 300); azure_count prints one step's count, and the finding sums the steps.
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
# The audio rerun (the priority task's behavior 10, rerun after the review, 2026-11-17). go-ai's
# two audio tests send a body past the 64 KiB the gateway buffers for a retry, so each is sent
# once: while the audio row isn't evicted, it gets the row's 503 (a failed connection under
# rows-down), not Azure's answer. A small text-only request is retried, so its failed attempts
# evict the row and its last attempt reaches Azure, which answers 400 (gpt-audio-mini requires
# audio); two are sent, so the row is evicted whatever its state. An eviction lasts 5 s times the
# evictions so far (config.yaml, &row-health), and `go test` takes seconds to start, so each test
# runs alone, right after its own warm-up. About 6 Azure requests in all: 4 warm-up 400s and the
# 2 tests'. The helper refuses to run unless the deployed copy's first line names rows-down.
#
# The priority rerun. The tests are those docs/findings/priority.md lists as failing on Azure, in
# "The tiers on Azure" and "Per alias", rows down: top-level names, since one `go test -run` can't
# select a subtest of one test beside another whole, so a test's passing subtests run too. Each
# name was checked at tools/infer/v0.2.0 with `git grep 'func <Test>('`: none was renamed or moved
# out of its tier.
#
# The retry test (the answer task). retry_case runs retry/'s one test for the case, in a go test
# of its own, with RETRY_CASE naming it, so its test runs and the others skip; each case expects
# its overlay or condition live: rate-limit-agent and in-flight-1 their probes overlays, bulk-rate-
# low its overlay and the bulk key, and embedding-burst the embedding route's global bucket of 34
# a second in the deployed config. The helper refuses to run unless the deployed copy's first line
# names the case's overlay, or, for embedding-burst, names none of the three. The key reaches the
# test as a path, RETRY_KEY_FILE, which the test reads itself; the key is never in argv, and the
# helper searches the log and the table for it after the run, as after a tier run.
#
# requests_shed. agentgateway's stats port, 15020, serves its Prometheus metrics, published on
# gb10-2's loopback only (gateway/agentgateway.yml); requests_shed counts the requests the
# in-flight limit refused, which leave no access log line (probes/in-flight-1.yaml).
#
# The traces (the answer task's behaviors 10 to 12). Tempo publishes no port (gateway/tempo.yml),
# so traces reads its HTTP API from inside the compose network: `docker exec` of curl in the
# Grafana container, which has it, against tempo:3200, over SSH. A search is /api/search with a
# TraceQL query and a time range in Unix seconds; each trace is /api/v2/traces/<id>, whose span
# and parent ids Tempo gives in base64, printed in hex as a traceparent carries them. A span whose
# parent is in another service is the check that a row's span is the gateway's child; a parent the
# trace doesn't hold, a caller's own traceparent, is marked "(not in trace)". Only keys are printed,
# since a span's values may name the caller's address or an overflow's endpoint, the Azure
# account's host, as the access log does; a span name that names a host under azure.com has it
# replaced, since an outbound span is named for its host. Search finds a trace only once Tempo has
# made it searchable, tens of seconds after it arrives; -t reads one at once.
#
# The timed stream (the max-tokens-note task). messages_stream measures whether a Messages stream
# that overflows to Azure streams or arrives whole, and whether message_stop is held after the
# text ends (docs/findings/priority.md, the --max-tokens 16 stall). The key reaches curl as
# gw_curl's does, in the config curl reads from its stdin; curl runs with -N, so each line leaves
# it as it arrives, and the bash loop it pipes into stamps each line with $EPOCHREALTIME, read in
# the same subshell as the send's own stamp, taken just before curl starts. No --trace or
# --trace-time: both print the request's headers, the key among them. -D keeps the response's
# headers only. Each file is searched for the key after the send, as after a tier run. The
# summary gives the same times for the deltas of any type, since a reply cut off at a few tokens
# may hold reasoning (thinking deltas) and no text. The verdict reads the text deltas against the
# reply's span, from the first event to message_stop: "streams" when the deltas cover at least
# half of it, "arrives whole" when every event, the first to message_stop, lands within the last
# tenth of the total, else "mixed"; with fewer than two text deltas, "too short to tell".
#
# The Postgres password's rotation. The value is created like the deploy creates it (openssl rand
# -hex 32, 0600), and reaches psql only on its stdin, in `ALTER USER ... WITH PASSWORD` written by
# printf, a builtin, through ssh and `docker exec -i`: never in a process's argv, printed, or
# logged; psql's own output is printed with the value replaced, and with VERBOSITY terse, so an
# error doesn't echo the statement. psql connects over the container's local socket, which the
# image trusts, so the change needs no old password. A .next file left by a rotation that stopped
# is used again rather than replaced, since Postgres may already hold it. Live connections keep
# working; agentgateway's new ones need the new password, so deploy at once after:
# `mise run agentgateway-deploy` sends it in the config and postgres.env, which recreates the
# agentgateway container once (its `config` section's hash changes) and the Postgres container
# once (its environment changes; Postgres reads the variable only when it initializes the volume).
#
# The command log. Each helper call and each command it runs is appended to
# .state/max-tokens-note/commands-<YYYY-MM-DD>.log and printed to stderr as
# `+ <ISO time> <host>: <command>`, the form measure-lib.sh and the deploy script print.
#
# See docs/scripts.md#the-client-helpers

if ! (return 0 2>/dev/null); then
  echo 'clients-lib.sh is sourced, not run: source scripts/clients-lib.sh' >&2
  exit 2
fi

CLIENTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLIENTS_STATE=.state/max-tokens-note
CLIENTS_KEYS=.state/agentgateway/keys
CLIENTS_AZURE=.state/azure
CLIENTS_HOST=gb10-2
CLIENTS_AZURE_CAP=20
CLIENTS_GOAI_REPO=$HOME/architecture/go-ai
CLIENTS_GOAI_TAG=tools/infer/v0.3.1
CLIENTS_WORKTREE=$CLIENTS_STATE/go-ai-${CLIENTS_GOAI_TAG##*/}
CLIENTS_INFER=$CLIENTS_STATE/bin/infer

# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env is assignments.
source "$CLIENTS_ROOT/gateway/agentgateway/deploy.env"

declare -gA CLIENTS_ROLE=(
  [agent]=AGENT
  [vision]=VISION
  [audio]=AUDIO
  [embedding]=EMBEDDING
)

declare -gA CLIENTS_DEPLOYMENT=(
  [agent]=gpt-oss-120b
  [vision]=gpt-5-mini
  [audio]=gpt-audio-mini
  [embedding]=text-embedding-3-small
)

declare -gA CLIENTS_PROFILE=(
  [rows-up:agent]='{"completions":{"refused_efforts":["none","minimal","xhigh","max"],"no_allowed_tools":true},"responses":{"refused_efforts":["none","xhigh"],"no_allowed_tools":true,"resend_reasoning_text":true},"messages":{"refused_efforts":["none","xhigh","max"]}}'
  [rows-down:agent]='{"completions":{"no_tool_choice_required":true}}'
  [rows-down:vision]='{"completions":{"refused_efforts":["none","xhigh","max"]},"responses":{"refused_efforts":["none","xhigh"]}}'
)

CLIENTS_PRIORITY_GOAI_FAILED='^(TestFunctionCallRoundTrip|TestStreamFunctionCall|TestReasoningRoundTrip|TestStreamReasoningRoundTrip|TestToolChoice|TestChatUnknownModelIsAPIError|TestStreamText|TestChatIncompleteAtMaxOutputTokens|TestAudioInResponsesRefused|TestTranscribeChat)$'
CLIENTS_PRIORITY_INFER_FAILED='^(TestChatReasoningEffort|TestChatImage|TestChatIncompleteAtMaxTokens|TestTranscribeChat)$'

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

_clients_say() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
    [[ -z $line ]] ||
      printf '= %s %s: %s\n' "$(date -Iseconds)" "$1" "$line" \
        >>"$CLIENTS_ROOT/$CLIENTS_STATE/commands-$(date +%F).log"
  done
}

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
  _clients_log laptop "GOBIN=$CLIENTS_STATE/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@${CLIENTS_GOAI_TAG##*/} && $CLIENTS_INFER version"
  (
    cd "$CLIENTS_ROOT" || exit
    GOBIN=$CLIENTS_ROOT/$CLIENTS_STATE/bin go install \
      github.com/standards-lab/go-ai/tools/infer/cmd/infer@${CLIENTS_GOAI_TAG##*/} &&
      "$CLIENTS_INFER" version
  )
}

_clients_tier() {
  local kind=$1 sub=$2 run='' alias rc
  shift 2
  local usage="usage: ${kind}_tier [-run <regexp>] <name> <alias>..."
  if [[ ${1-} == -run ]]; then
    [[ -n ${2-} ]] || {
      echo "$usage" >&2
      return 2
    }
    run=$2
    shift 2
  fi
  local name=${1-}
  shift
  local run_arg=() run_shown=''
  if [[ -n $run ]]; then
    run_arg=(-run "$run")
    run_shown="-run '$run' "
  fi
  [[ -n $name && $# -gt 0 ]] || {
    echo "$usage" >&2
    return 2
  }
  for alias in "$@"; do
    [[ -n ${CLIENTS_ROLE[$alias]-} ]] || {
      echo "${kind}_tier: unknown alias $alias (agent, vision, audio, embedding)" >&2
      return 2
    }
  done
  local target=${CLIENTS_TARGET-}
  [[ $target == rows-up || $target == rows-down ]] || {
    echo "${kind}_tier: set CLIENTS_TARGET to rows-up or rows-down, what answers the aliases, for their profiles" >&2
    return 2
  }
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
    [[ -z ${CLIENTS_PROFILE[$target:$alias]-} ]] ||
      shown+="AI_${CLIENTS_ROLE[$alias]}_PROFILE='${CLIENTS_PROFILE[$target:$alias]}' "
  done
  _clients_log laptop "CLIENTS_TARGET=$target ${kind}_tier ${run_shown}$name $*"
  _clients_log laptop "cd $CLIENTS_WORKTREE/$sub && ${shown}GOWORK=off go test -race -tags integration -count=1 -v ${run_shown}./integration/... 2>&1 | tee $out"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT/$CLIENTS_WORKTREE/$sub" || exit
    for v in "${CLIENTS_ROLE[@]}" TRANSCRIPTION; do
      unset "AI_${v}_BASE_URL" "AI_${v}_TOKEN" "AI_${v}_HEADER" "AI_${v}_MODEL" "AI_${v}_PROFILE"
    done
    key=$(<"$CLIENTS_ROOT/$CLIENTS_KEYS/go-ai") || return
    for alias in "$@"; do
      export "AI_${CLIENTS_ROLE[$alias]}_BASE_URL=$(gw_base "$alias")"
      if [[ $cred == HEADER ]]; then
        export "AI_${CLIENTS_ROLE[$alias]}_HEADER=x-api-key: $key"
      else
        export "AI_${CLIENTS_ROLE[$alias]}_TOKEN=$key"
      fi
      [[ -z ${CLIENTS_PROFILE[$target:$alias]-} ]] ||
        export "AI_${CLIENTS_ROLE[$alias]}_PROFILE=${CLIENTS_PROFILE[$target:$alias]}"
    done
    unset key
    export GOWORK=off
    go test -race -tags integration -count=1 -v "${run_arg[@]}" ./integration/... 2>&1 |
      tee "$CLIENTS_ROOT/$out"
    exit "${PIPESTATUS[0]}"
  )
  rc=$?
  {
    echo "$name: exit $rc"
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

priority_rerun() {
  (($# == 1)) || {
    echo 'usage: priority_rerun <name>' >&2
    return 2
  }
  local rc=0
  goai_tier -run "$CLIENTS_PRIORITY_GOAI_FAILED" "$1-goai" agent vision audio embedding || rc=$?
  infer_tier -run "$CLIENTS_PRIORITY_INFER_FAILED" "$1-infer" agent vision audio embedding || rc=$?
  return "$rc"
}

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
    unset INFER_TOKEN INFER_HEADER INFER_MODEL INFER_PROFILE \
      INFER_RETRIES INFER_RETRY_BASE_DELAY INFER_RETRY_MAX_DELAY
    key=$(<"$CLIENTS_KEYS/go-ai") || return
    if [[ $cred == INFER_HEADER ]]; then
      export INFER_HEADER="x-api-key: $key"
    else
      export INFER_TOKEN=$key
    fi
    unset key
    INFER_BASE_URL=$(gw_base "$alias") || return
    export INFER_BASE_URL
    exec "$CLIENTS_INFER" "$@"
  )
}

infer_once() {
  (($# >= 2)) || {
    echo 'usage: infer_once <alias> <infer argument>...' >&2
    return 2
  }
  local alias=$1
  shift
  infer_at "$alias" --retries 1 "$@"
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
  local body
  body=$(printf '{"model":"%s","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":%d,"ignore_eos":true}' "$alias" "$tokens") || return
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
  # shellcheck disable=SC2029 # The command is built on the laptop, with no secret in it.
  log=$(ssh -n "$CLIENTS_HOST" "$remote") || {
    rc=$?
    echo "reading the gateway log failed (ssh exit $rc); no count" | _clients_say azure_count
    return "$rc"
  }
  awk -v since="$1" -v until="${2:-now}" -v deployments="$deployments" -v cap="$CLIENTS_AZURE_CAP" '
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
        printf "  toward the cap of %d: %d (2xx, and 4xx other than 429); 429, reported apart: %d\n", cap, counted, limited
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
  _clients_log laptop "ssh $CLIENTS_HOST 'docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -v ON_ERROR_STOP=1 -P pager=off' <<< \"${query//$'\n'/ }\""
  ssh "$CLIENTS_HOST" 'docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -v ON_ERROR_STOP=1 -P pager=off' \
    <<<"$query" | _clients_say request_log
  return "${PIPESTATUS[0]}"
}

audio_rerun() {
  (($# == 1)) || {
    echo 'usage: audio_rerun <name>' >&2
    return 2
  }
  local name=$1 live since t rc=0
  _clients_log laptop "ssh -n $CLIENTS_HOST head -1 '~/gateway/agentgateway/config.yaml'"
  # shellcheck disable=SC2088 # The tilde expands on gb10-2.
  live=$(ssh -n "$CLIENTS_HOST" head -1 '~/gateway/agentgateway/config.yaml') || return
  echo "$live" | _clients_say audio_rerun
  [[ $live =~ ^'# overlays: '(.*\ )?rows-down(\ .*)?$ ]] || {
    echo "audio_rerun: rows-down isn't deployed; run logged \"mise run agentgateway-deploy rows-down\" first" |
      _clients_say audio_rerun
    return 2
  }
  since=$(date -Iseconds) || return
  for t in TestAudioInResponsesRefused TestTranscribeChat; do
    for _ in 1 2; do
      gw_curl architect -sS -D - -o /dev/null -H 'Content-Type: application/json' \
        -d '{"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16}' \
        "$(gw_base audio)/chat/completions" | tr -d '\r' | grep -iE '^(HTTP|x-gateway-overflow)' |
        paste -sd' ' | _clients_say audio_rerun
    done
    goai_tier -run "^$t\$" "$name-$t" audio || rc=$?
  done
  azure_count "$since"
  return "$rc"
}

pg_password_rotate() {
  (($# == 0)) || {
    echo 'usage: pg_password_rotate' >&2
    return 2
  }
  local cur=.state/agentgateway/postgres-password
  local next=$cur.next
  local remote='docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -q -v ON_ERROR_STOP=1 -v VERBOSITY=terse'
  [[ -s $CLIENTS_ROOT/$cur ]] || {
    echo "pg_password_rotate: no password at $cur; nothing to rotate" >&2
    return 2
  }
  _clients_log laptop "pg_password_rotate"
  if [[ -s $CLIENTS_ROOT/$next ]]; then
    echo "$next exists, from a rotation that stopped; it is used again" | _clients_say pg_password_rotate
  else
    _clients_log laptop "(umask 077 && openssl rand -hex 32 > $next)"
    (umask 077 && openssl rand -hex 32 >"$CLIENTS_ROOT/$next") || return
  fi
  _clients_log laptop "printf \"ALTER USER agentgateway WITH PASSWORD '%s';\\n\" \"\$(<$next)\" | ssh $CLIENTS_HOST '$remote'"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT" || exit
    pw=$(<"$next") || return
    [[ $pw =~ ^[0-9a-f]{64}$ ]] || {
      echo "$next isn't 64 hex characters; nothing was changed"
      exit 2
    }
    rc=0
    # shellcheck disable=SC2029 # The command is built on the laptop, with no secret in it.
    out=$(printf "ALTER USER agentgateway WITH PASSWORD '%s';\n" "$pw" | ssh "$CLIENTS_HOST" "$remote" 2>&1) || rc=$?
    [[ -z $out ]] || printf '%s\n' "${out//$pw/<new password>}"
    exit "$rc"
  ) | _clients_say pg_password_rotate
  local rc=${PIPESTATUS[0]}
  if ((rc != 0)); then
    echo "pg_password_rotate: ALTER USER failed (exit $rc); $next is kept, and Postgres may hold it" |
      _clients_say pg_password_rotate
    return "$rc"
  fi
  _clients_log laptop "mv $next $cur"
  mv "$CLIENTS_ROOT/$next" "$CLIENTS_ROOT/$cur" || return
  echo "postgres-password: rotated in Postgres on $CLIENTS_HOST and in $cur; deploy now: logged \"mise run agentgateway-deploy\"" |
    _clients_say pg_password_rotate
}

retry_case() {
  (($# == 1)) || {
    echo 'usage: retry_case <rate-limit-agent | embedding-burst | in-flight-1 | bulk-rate-low>' >&2
    return 2
  }
  local c=$1 test key=go-ai overlay='' live rc
  case $c in
    rate-limit-agent) test=TestRateLimitAgent overlay=rate-limit-agent ;;
    embedding-burst) test=TestEmbeddingBurst ;;
    in-flight-1) test=TestInFlight1 overlay=in-flight-1 ;;
    bulk-rate-low) test=TestBulkRateLow key=bulk overlay=bulk-rate-low ;;
    *)
      echo "retry_case: unknown case $c (rate-limit-agent, embedding-burst, in-flight-1, bulk-rate-low)" >&2
      return 2
      ;;
  esac
  _clients_key_ok "$key" || return
  _clients_log laptop "ssh -n $CLIENTS_HOST head -1 '~/gateway/agentgateway/config.yaml'"
  # shellcheck disable=SC2088 # The tilde expands on gb10-2.
  live=$(ssh -n "$CLIENTS_HOST" head -1 '~/gateway/agentgateway/config.yaml') || return
  echo "$live" | _clients_say retry_case
  if [[ -n $overlay ]]; then
    [[ $live =~ ^'# overlays: '(.*\ )?$overlay(\ .*)?$ ]]
  else
    [[ $live == '# overlays: none' ]]
  fi || {
    echo "retry_case: $c needs ${overlay:-no overlay} deployed; run logged \"mise run agentgateway-deploy${overlay:+ $overlay}\" first" |
      _clients_say retry_case
    return 2
  }
  local stamp out table
  stamp=$(date +%Y%m%dT%H%M%S) || return
  out=$CLIENTS_STATE/retry/$c-$stamp.log
  table=$CLIENTS_STATE/retry/$c-$stamp.tsv
  mkdir -p "$CLIENTS_ROOT/$CLIENTS_STATE/retry"
  local env="RETRY_CASE=$c RETRY_KEY_FILE=../$CLIENTS_KEYS/$key RETRY_KEY_IN=${CLIENTS_KEY_IN:-bearer}"
  env+=" RETRY_AGENT_BASE_URL=$(gw_base agent) RETRY_EMBEDDING_BASE_URL=$(gw_base embedding)"
  env+=" RETRY_TABLE=../$table"
  _clients_log laptop "retry_case $c"
  _clients_log laptop "cd retry && $env go test -count=1 -timeout 5m -v -run '^$test\$' . 2>&1 | tee $out"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT/retry" || exit
    # shellcheck disable=SC2086 # $env is the assignments above, none with a space.
    env $env go test -count=1 -timeout 5m -v -run "^$test\$" . 2>&1 | tee "$CLIENTS_ROOT/$out"
    exit "${PIPESTATUS[0]}"
  )
  rc=$?
  {
    echo "$c: exit $rc"
    local f
    for f in "$out" "$table"; do
      [[ -e $CLIENTS_ROOT/$f ]] || {
        echo "$c: no $f"
        continue
      }
      grep -qF -f "$CLIENTS_ROOT/$CLIENTS_KEYS/$key" "$CLIENTS_ROOT/$f" 2>/dev/null
      case $? in
        0) echo "$c: THE KEY IS IN $f; delete it before anything is shared" ;;
        1) echo "$c: the key is not in $f" ;;
        *) echo "$c: THE KEY SEARCH FAILED on $f; search it before anything is shared" ;;
      esac
    done
  } | _clients_say retry_case
  return "$rc"
}

requests_shed() {
  (($# == 0)) || {
    echo 'usage: requests_shed' >&2
    return 2
  }
  local remote='curl -fsS --max-time 5 http://127.0.0.1:15020/metrics'
  _clients_log laptop "ssh -n $CLIENTS_HOST '$remote' | grep requests_shed"
  ssh -n "$CLIENTS_HOST" "$remote" | grep -E '^(# (HELP|TYPE) )?[a-z_]*requests_shed' |
    _clients_say requests_shed
  local st=("${PIPESTATUS[@]}")
  return $((st[0] ? st[0] : st[1]))
}

_clients_traces_print() {
  jq -r '
    def b64hex:
      if test("^[0-9a-f]+$") then . else
        [explode[] | select(. != 61)
          | if . >= 97 then . - 71 elif . >= 65 then . - 65 elif . >= 48 then . + 4
            elif . == 43 then 62 else 63 end]
        | [range(0; length; 4) as $i | .[$i:$i + 4]]
        | map(. as $g | (reduce range(0; 4) as $i (0; . * 64 + ($g[$i] // 0))) as $v
            | [($v / 65536 | floor) % 256, ($v / 256 | floor) % 256, $v % 256][0:($g | length) - 1])
        | add // []
        | map(. as $b | "0123456789abcdef" | .[($b / 16 | floor):($b / 16 | floor) + 1] + .[$b % 16:$b % 16 + 1])
        | join("")
      end;
    def safe: gsub("[A-Za-z0-9.-]+\\.azure\\.com"; "<azure host>");
    [.trace.resourceSpans[]?
      | ([.resource.attributes[]? | select(.key == "service.name") | .value.stringValue][0] // "?") as $svc
      | .scopeSpans[]?.spans[]?
      | {svc: $svc, id: (.spanId | b64hex), parent: ((.parentSpanId // "") | b64hex),
         trace: (.traceId | b64hex), name: (.name | safe),
         kind: ((.kind // "") | sub("^SPAN_KIND_"; "") | ascii_downcase),
         start: (.startTimeUnixNano | tonumber), end: (.endTimeUnixNano | tonumber),
         keys: [.attributes[]?.key]}]
    | sort_by(.start) as $spans
    | ($spans | map({key: .id, value: .parent}) | from_entries) as $up
    | ($spans | map({key: .id, value: .svc}) | from_entries) as $svcs
    | def depth($id): if ($up[$id] // "") == "" or $up[$up[$id]] == null then 0 else 1 + depth($up[$id]) end;
    if ($spans | length) == 0 then "trace: no spans" else
      "trace \($spans[0].trace): \($spans | length) spans, services \([$spans[].svc] | unique | join(", "))",
      ($spans[] | ("  " * (depth(.id) + 1)) as $in
        | "\($in)\(.svc) \"\(.name)\" \(.kind) span \(.id) parent \(
            if .parent == "" then "none (root)"
            elif $up[.parent] == null then "\(.parent) (not in trace)"
            elif $svcs[.parent] != .svc then "\(.parent) (\($svcs[.parent]))"
            else .parent end), \((.end - .start) / 1e5 | round / 10) ms",
          "\($in)  keys: \(.keys | join(", "))")
    end'
}

traces() {
  local OPTIND opt query='{}' count=20 ids=() since='15 min ago' start end
  while getopts q:n:t: opt; do
    case $opt in
      q) query=$OPTARG ;;
      n) count=$OPTARG ;;
      t) ids+=("$OPTARG") ;;
      *)
        echo 'usage: traces [-q <traceql>] [-n <count>] [<since>] | traces -t <trace id>...' >&2
        return 2
        ;;
    esac
  done
  shift $((OPTIND - 1))
  if ((${#ids[@]})); then
    ids+=("$@")
  else
    (($# <= 1)) || {
      echo 'usage: traces [-q <traceql>] [-n <count>] [<since>]' >&2
      return 2
    }
    since=${1:-$since}
  fi
  [[ $count =~ ^[1-9][0-9]*$ ]] || {
    echo 'traces: <count> is a positive integer' >&2
    return 2
  }
  local id
  for id in "${ids[@]}"; do
    [[ $id =~ ^[0-9a-f]{1,32}$ ]] || {
      echo "traces: $id isn't a trace id, 32 hex digits" >&2
      return 2
    }
  done
  local exec="docker exec gateway-grafana-1"
  if ((${#ids[@]} == 0)); then
    start=$(date -d "$since" +%s) || {
      echo "traces: date -d can't read $since" >&2
      return 2
    }
    end=$(date +%s) || return
    local remote
    remote="$exec curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode $(printf %q "q=$query") --data-urlencode limit=$count --data-urlencode start=$start --data-urlencode end=$end" || return
    _clients_log laptop "ssh -n $CLIENTS_HOST \"$remote\" | jq -r '.traces[].traceID'"
    # shellcheck disable=SC2029 # The command is built on the laptop, with no secret in it.
    mapfile -t ids < <(ssh -n "$CLIENTS_HOST" "$remote" | jq -r '.traces[]?.traceID') || return
    if ((${#ids[@]} == 0)); then
      echo "no trace matches $query since $(date -d "@$start" -Iseconds)" | _clients_say traces
      return 0
    fi
  fi
  # shellcheck disable=SC2089,SC2090 # The quotes are the remote shell's, the string sent as written.
  local fetch="$exec sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/\$id && echo || exit; done' sh ${ids[*]}"
  _clients_log laptop "ssh -n $CLIENTS_HOST \"$fetch\" | spans, parents, and attribute keys"
  # shellcheck disable=SC2029 # The command is built on the laptop, with no secret in it.
  ssh -n "$CLIENTS_HOST" "$fetch" | _clients_traces_print | _clients_say traces
  local st=("${PIPESTATUS[@]}")
  return $((st[0] ? st[0] : st[1]))
}

messages_stream() {
  (($# == 3)) || {
    echo 'usage: messages_stream <alias> <max tokens> <prompt>' >&2
    return 2
  }
  local alias=$1 tokens=$2 prompt=$3 key=architect
  [[ $alias != embedding && -n ${CLIENTS_ROLE[$alias]-} ]] || {
    echo "messages_stream: no Messages route for $alias (agent, vision, audio)" >&2
    return 2
  }
  [[ $tokens =~ ^[1-9][0-9]*$ ]] || {
    echo 'messages_stream: <max tokens> is a positive integer' >&2
    return 2
  }
  _clients_key_ok "$key" || return
  local header='Authorization: Bearer '
  [[ ${CLIENTS_KEY_IN:-bearer} != header ]] || header='x-api-key: '
  local body url dir
  body=$(jq -cn --arg m "$alias" --argjson n "$tokens" --arg p "$prompt" \
    '{model: $m, max_tokens: $n, stream: true, messages: [{role: "user", content: $p}]}') || return
  url=$(gw_base "$alias")/messages || return
  dir=$CLIENTS_STATE/stream/$alias-$tokens-$(date +%Y%m%dT%H%M%S.%3N) || return
  mkdir -p "$CLIENTS_ROOT/$CLIENTS_STATE/stream" && mkdir "$CLIENTS_ROOT/$dir" || return
  _clients_log laptop "messages_stream $alias $tokens '$prompt'"
  _clients_log laptop "t0=\$EPOCHREALTIME; printf 'header = \"$header%s\"\\n' \"\$(<$CLIENTS_KEYS/$key)\" | curl -K - -sN -D $dir/headers.txt -H 'content-type: application/json' -d '$body' $url | while IFS= read -r line; do t=\$EPOCHREALTIME; printf '%d\\t%s\\n' \$((\${t/./} - \${t0/./})) \"\${line%\$'\\r'}\"; done > $dir/raw.tsv"
  (
    { set +x; } 2>/dev/null
    cd "$CLIENTS_ROOT" || exit
    t0=$EPOCHREALTIME
    # shellcheck disable=SC2059 # The format is built from a fixed header name.
    printf "header = \"$header%s\"\n" "$(<"$CLIENTS_KEYS/$key")" |
      curl -K - -sN -D "$dir/headers.txt" -H 'content-type: application/json' -d "$body" "$url" |
      while IFS= read -r line || [[ -n $line ]]; do
        t=$EPOCHREALTIME
        printf '%d\t%s\n' $((${t/./} - ${t0/./})) "${line%$'\r'}"
      done >"$dir/raw.tsv"
    rc=${PIPESTATUS[1]}
    t1=$EPOCHREALTIME
    printf 'curl_exit\t%d\ntotal_us\t%d\n' "$rc" $((${t1/./} - ${t0/./})) >"$dir/total.tsv"
    exit "$rc"
  )
  local rc=$?
  awk -F '\t' '
      $2 ~ /^event: / { if (ev != "") print at "\t" ev "\t" dt; at = $1; ev = substr($2, 8); dt = "" }
      $2 ~ /^data: / && ev == "content_block_delta" && match($2, /"delta": *\{ *"type": *"[a-z_]+"/) {
        dt = substr($2, RSTART, RLENGTH); sub(/.*"type": *"/, "", dt); sub(/"$/, "", dt)
      }
      END { if (ev != "") print at "\t" ev "\t" dt }' \
    "$CLIENTS_ROOT/$dir/raw.tsv" >"$CLIENTS_ROOT/$dir/events.tsv"
  {
    echo "$dir: curl exit $rc"
    awk -F '\t' -v hdr="$CLIENTS_ROOT/$dir/headers.txt" '
        FNR == NR { if ($1 == "total_us") total = $2; next }
        { n++; if (n == 1) first = $1 }
        $2 == "content_block_delta" { if (!ad) fa = $1; la = $1; ad++ }
        $2 == "content_block_delta" && $3 == "text_delta" { if (!td) ft = $1; lt = $1; td++ }
        $2 == "message_delta" && md == "" { md = $1 }
        $2 == "message_stop" && ms == "" { ms = $1 }
        function s(us) { return us == "" ? "-" : sprintf("%.3f s", us / 1e6) }
        END {
          while ((getline line < hdr) > 0) {
            sub(/\r$/, "", line)
            if (line ~ /^HTTP\//) status = line
            if (tolower(line) ~ /^x-gateway-overflow:/) ov = line
          }
          printf "status: %s; overflow: %s\n", (status ? status : "none"), (ov ? ov : "none")
          printf "events: %d; text deltas: %d; deltas of any type: %d\n", n, td, ad
          printf "first event %s; first text delta %s; last text delta %s; text span %s\n", s(first), s(ft), s(lt), (td ? s(lt - ft) : "-")
          printf "message_delta %s; message_stop %s; total %s\n", s(md), s(ms), s(total)
          printf "last text delta to message_delta %s, to message_stop %s\n", (td && md != "" ? s(md - lt) : "-"), (td && ms != "" ? s(ms - lt) : "-")
          printf "any delta: first %s, last %s; last to message_delta %s, to message_stop %s\n", s(fa), s(la), (ad && md != "" ? s(md - la) : "-"), (ad && ms != "" ? s(ms - la) : "-")
          end = (ms != "" ? ms : total)
          if (td < 2) v = "too short to tell"
          else if (lt - ft >= (end - first) / 2) v = "streams"
          else if (first >= 0.9 * total) v = "arrives whole"
          else v = "mixed"
          printf "verdict: %s\n", v
        }' "$CLIENTS_ROOT/$dir/total.tsv" "$CLIENTS_ROOT/$dir/events.tsv"
    local f
    for f in raw.tsv events.tsv headers.txt total.tsv; do
      grep -qF -f "$CLIENTS_ROOT/$CLIENTS_KEYS/$key" "$CLIENTS_ROOT/$dir/$f" 2>/dev/null
      case $? in
        0) echo "THE KEY IS IN $dir/$f; delete it before anything is shared" ;;
        1) echo "the key is not in $dir/$f" ;;
        *) echo "THE KEY SEARCH FAILED on $dir/$f; search it before anything is shared" ;;
      esac
    done
  } | _clients_say messages_stream
  return "$rc"
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
