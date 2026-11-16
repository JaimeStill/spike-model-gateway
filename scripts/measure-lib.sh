#!/usr/bin/env bash
# The step helpers for the GuideLLM cells: the agentgateway task's overhead cells (its slice 2,
# behavior 7) and cap cells (its slice 3, behavior 8), and the routing task's overhead cells,
# adapted from spike-model-layout's scripts/measure-lib.sh (`cell`, `watch`, `summarize`) and kept
# to what these cells need: no host loads or memory floors. Sourced from the repository root on the
# laptop, then called one step at a time in the architect's view:
#
#   source scripts/measure-lib.sh
#
#   cell <name> <scenario> <direct|gateway|cap> <alias>
#                     one GuideLLM run of bench/<scenario>.yaml against the alias's row (direct)
#                     or its base URL on the gateway (gateway, cap), http://gb10-2:3000/<alias>/v1
#                     with the port from gateway/agentgateway/deploy.env, into
#                     .state/priority/cells/<name>/; on a gateway or cap run, the gateway
#                     container's CPU and memory sampled on gb10-2. A cap run is a gateway run
#                     that also samples the row's running and waiting requests from its /metrics,
#                     read direct from the row, and afterwards reads each of the run's requests
#                     from the gateway's access log
#   summarize <name>  a run's requests and errors, TTFT, ITL and request latency (median, p95),
#                     and on a gateway run the container's CPU and memory during the benchmark; on
#                     a cap run, per level, every reply's status, any Retry-After, and the row's
#                     running and waiting counts, then latency growth from the first level to the
#                     second
#   compare <direct-1> <gateway> <direct-2>
#                     behavior 7's reading: each figure's spread between the two direct runs
#                     beside what the gateway run adds over their mean
#   overflow_read <name>
#                     benchmark C's reading of a cap run (the priority task's behavior 9), from its
#                     gateway-requests.tsv and result.json: the replies the row and Azure each
#                     answered, per status; the 503s the row returned to the client; the requests
#                     the route retried, and whether any of them reached Azure; the eviction
#                     windows, an estimate, and their rate a minute; and the time from the
#                     benchmark's start to the row's first refusal
#
# No helper runs a benchmark on its own or chains runs: `cell` runs exactly one.
#
# The command log. Each helper call and each command it runs is appended to
# .state/priority/commands-<YYYY-MM-DD>.log, and printed to stderr, as
# `+ <ISO time> <host>: <command>`, the form the deploy script prints; what a helper reports
# follows as `= <ISO time> <helper>: <line>`. The finding's "Commands as run" quotes that log.
#
# The key. A gateway run sends the bench key, read from .state/agentgateway/keys/bench, which the
# deploy creates. It reaches GuideLLM only in its environment, as GUIDELLM__SPEC__BACKEND__API_KEY,
# read with bash's `$(<file)` inside the run's subshell, with xtrace off there: never in a process's
# argv, never printed, and logged only as that expression. GuideLLM 0.8.1 holds it as a pydantic
# SecretStr (OpenAIHTTPBackendArgs.api_key), which every dump of its config writes as "**********",
# the result JSON's included, and adds the Bearer header only when it sends a request, so no
# request record carries it. After a gateway run, `cell` searches the run's files for the key,
# reading the pattern from the key file (`grep -F -f`), and says whether it was found. A direct run
# sends no key: the rows take none, and the key is the gateway's alone.
#
# A cap run's statuses and Retry-After. GuideLLM 0.8.1 records a refused request as errored, with
# its error as `repr` of httpx's HTTPStatusError (scheduler/worker.py), which names the status
# ("Server error '503 Service Unavailable' for url ...") and none of the reply's headers; a
# successful request passed raise_for_status, so it was 2xx. So the status comes from GuideLLM, and
# Retry-After from the gateway's access log: after the run, `cell` reads the log lines of the
# alias's route inside the run's time (`docker logs --timestamps --since --until` on gb10-2) into
# gateway-requests.tsv, keeping each line's time, status, path, `retry_after` and `overflow`, two
# fields gateway/agentgateway/config.yaml adds to every line, and `retry.attempt`, the attempt that
# answered when the route retried; the caller's address, the endpoint (an overflow's names the
# Azure account), and every other field stay out.
#
# Benchmark C's reading (overflow_read). Each line is one client request, its last attempt: the
# row's reply if `overflow` is empty, Azure's if it is "azure". A line with `retry.attempt` n had n
# earlier attempts refused (a 503 or a failed connection), each to the row unless the row was
# already evicted. agentgateway logs no eviction and exports no metric of one (v1.7.0,
# types/loadbalancer.rs), so the eviction windows are estimated from the lines in time order: a
# window starts at an Azure-answered line that follows a row-answered one. A line's time is when the
# request ended, so a long stream that started before a window can end inside it: the estimate is
# coarse, and is labelled so. The row's first refusal is the earliest line with a 503 from the row,
# a retry, or an Azure answer, timed from the benchmark's start in result.json.
#
# Settings, each an environment variable read when a helper runs:
#   MEASURE_STATS_EVERY  seconds between gateway and row samples (default 5)
#   MEASURE_CELL_CAP     a run's cap, given to timeout (default 10m)

if ! (return 0 2>/dev/null); then
  echo 'measure-lib.sh is sourced, not run: source scripts/measure-lib.sh' >&2
  exit 2
fi

MEASURE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Relative to the root: every command runs from there, so the log names no home directory.
MEASURE_STATE=.state/priority
MEASURE_KEY=.state/agentgateway/keys/bench
MEASURE_GATEWAY_HOST=gb10-2

# The consumer port, deploy.env's AGW_PORT.
# shellcheck disable=SC1091 # check.sh runs shellcheck without -x; deploy.env is assignments.
source "$MEASURE_ROOT/gateway/agentgateway/deploy.env"

# Each alias's row, as host:port, and the tokenizer GuideLLM counts its tokens with (spike-model-
# layout's, for the model each row serves).
declare -gA MEASURE_ROW=(
  [agent]=gb10-1:8000
  [vision]=gb10-2:8000
  [audio]=framework:8001
  [embedding]=framework:8002
)
declare -gA MEASURE_TOKENIZER=(
  [agent]=openai/gpt-oss-120b
  [vision]=google/gemma-4-26B-A4B-it
  [audio]=google/gemma-4-E4B-it
  [embedding]=ibm-granite/granite-embedding-english-r2
)

# Appends `+ <time> <host>: <command>` to the day's log and prints it to stderr.
_measure_log() {
  printf '+ %s %s: %s\n' "$(date -Iseconds)" "$1" "$2" |
    tee -a "$MEASURE_ROOT/$MEASURE_STATE/commands-$(date +%F).log" >&2
}

# Copies its input to stdout, and each non-empty line to the day's log as
# `= <time> <helper>: <line>`.
_measure_say() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
    [[ -z $line ]] ||
      printf '= %s %s: %s\n' "$(date -Iseconds)" "$1" "$line" \
        >>"$MEASURE_ROOT/$MEASURE_STATE/commands-$(date +%F).log"
  done
}

cell() {
  local usage='usage: cell <name> <scenario> <direct|gateway|cap> <alias>'
  if (($# != 4)); then
    echo "$usage" >&2
    return 2
  fi
  local name=$1 scenario=$2 target=$3 alias=$4 url rc
  local dir=$MEASURE_STATE/cells/$name
  if [[ -z ${MEASURE_ROW[$alias]-} ]]; then
    echo "cell: unknown alias $alias (agent, vision, audio, embedding)" >&2
    return 2
  fi
  if [[ ! -f $MEASURE_ROOT/bench/$scenario.yaml ]]; then
    echo "cell: no bench/$scenario.yaml" >&2
    return 2
  fi
  case $target in
    direct) url=http://${MEASURE_ROW[$alias]}/v1 ;;
    gateway | cap)
      url=http://$MEASURE_GATEWAY_HOST:$AGW_PORT/$alias/v1
      if [[ ! -s $MEASURE_ROOT/$MEASURE_KEY ]]; then
        echo "cell: no key at $MEASURE_KEY; run mise run agentgateway-deploy first" >&2
        return 2
      fi
      ;;
    *)
      echo "$usage" >&2
      return 2
      ;;
  esac
  if [[ -e $MEASURE_ROOT/$dir ]]; then
    echo "cell: $dir exists; name each run once (a rerun takes a new name)" >&2
    return 2
  fi
  mkdir -p "$MEASURE_ROOT/$dir"

  # Each run its own seed, from its name, so a run's synthetic prompts and images are its own:
  # GuideLLM's default seed, 42, would send each run the last one's, and the row's prefix cache
  # would serve the gateway run and the second direct run what the first direct run sent. The audio
  # cell's clips come from a dataset, the same in every run, which no seed changes.
  local seed
  seed=$(printf %s "$name" | cksum)
  seed=${seed%% *}
  local -a run=(timeout "${MEASURE_CELL_CAP:-10m}" mise exec -- guidellm run
    -c "bench/$scenario.yaml"
    --backend "kind=openai_http,model=$alias"
    --tokenizer "kind=huggingface_auto,model=${MEASURE_TOKENIZER[$alias]}"
    --seed "kind=static,value=$seed"
    --output "kind=json,path=$dir/result.json"
    --disable-console-interactive)
  local keyed=
  [[ $target == direct ]] || keyed="GUIDELLM__SPEC__BACKEND__API_KEY=\$(<$MEASURE_KEY) "
  _measure_log laptop "cell $*"
  _measure_log laptop "${keyed}GUIDELLM__SPEC__BACKEND__TARGET=$url MISE_ENV=bench ${run[*]} > $dir/guidellm.log 2>&1"
  [[ $target == direct ]] ||
    _measure_log laptop "every ${MEASURE_STATS_EVERY:-5} s while it runs: ssh -n $MEASURE_GATEWAY_HOST \"docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway\" >> $dir/gateway-stats.tsv"
  [[ $target != cap ]] ||
    _measure_log laptop "every ${MEASURE_STATS_EVERY:-5} s while it runs: curl -sS --max-time 3 http://${MEASURE_ROW[$alias]}/metrics, the sums of vllm:num_requests_running and vllm:num_requests_waiting >> $dir/row-metrics.tsv"
  local since
  since=$(date +%s)

  # The run, the terminal's view of it, and the sampler, in one foreground subshell, so Ctrl-C
  # reaches them all; timeout puts GuideLLM in a process group of its own, so the trap passes the
  # interrupt on to it, and timeout stops GuideLLM.
  (
    { set +x; } 2>/dev/null
    cd "$MEASURE_ROOT" || exit
    # The key enters this inner subshell's environment only, and GuideLLM's from it.
    (
      export MISE_ENV=bench GUIDELLM__SPEC__BACKEND__TARGET=$url
      unset GUIDELLM__SPEC__BACKEND__API_KEY
      if [[ $target != direct ]]; then
        GUIDELLM__SPEC__BACKEND__API_KEY=$(<"$MEASURE_KEY")
        export GUIDELLM__SPEC__BACKEND__API_KEY
      fi
      exec "${run[@]}"
    ) >"$dir/guidellm.log" 2>&1 &
    pid=$!
    trap 'kill -TERM "$pid" 2>/dev/null' INT TERM
    # GuideLLM's own output, followed in the terminal until it exits.
    tail -n +1 -f --pid="$pid" "$dir/guidellm.log" &

    # The row sampler, on a cap run only, in the background beside the gateway sampler: the row's
    # requests running and waiting, read from its own /metrics, direct from the laptop (the rows
    # stay reachable directly), at each interval, until GuideLLM exits. Each is the sum over the
    # row's engines of vLLM's gauge. A failed read is a row of dashes.
    if [[ $target == cap ]]; then
      printf 'epoch\ttime\trunning\twaiting\n' >"$dir/row-metrics.tsv"
      while kill -0 "$pid" 2>/dev/null; do
        line=$(curl -sS --max-time 3 "http://${MEASURE_ROW[$alias]}/metrics" 2>/dev/null |
          awk '/^vllm:num_requests_running[{ ]/ { r += $NF; n++ }
            /^vllm:num_requests_waiting[{ ]/ { w += $NF; n++ }
            END { if (n) printf "%g|%g", r, w }') || line=
        [[ -n $line ]] || line='-|-'
        printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$(date +%T)" "${line%%|*}" "${line#*|}" \
          >>"$dir/row-metrics.tsv"
        sleep "${MEASURE_STATS_EVERY:-5}"
      done &
    fi

    # The gateway sampler, on a gateway run only: the container's CPU (100% is one core) and
    # memory, one `docker stats --no-stream` on gb10-2 at each interval, until GuideLLM exits. A
    # failed read is a row of dashes, so a gap shows. summarize keeps the samples inside the
    # benchmark's time.
    if [[ $target != direct ]]; then
      printf 'epoch\ttime\tcpu\tmemory\n' >"$dir/gateway-stats.tsv"
      while kill -0 "$pid" 2>/dev/null; do
        line=$(ssh -n "$MEASURE_GATEWAY_HOST" \
          "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" 2>/dev/null) ||
          line='-|-'
        printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$(date +%T)" "${line%%|*}" "${line#*|}" \
          >>"$dir/gateway-stats.tsv"
        sleep "${MEASURE_STATS_EVERY:-5}"
      done
    fi
    # A wait an interrupt cut short is waited again, for GuideLLM's own status.
    wait "$pid"
    rc=$?
    while kill -0 "$pid" 2>/dev/null; do
      wait "$pid"
      rc=$?
    done
    wait
    exit "$rc"
  )
  rc=$?
  echo "$rc" >"$MEASURE_ROOT/$dir/exit"
  [[ $target != cap ]] || _measure_requests "$name" "$alias" "$since" "$(($(date +%s) + 1))"
  {
    case $rc in
      0) echo "$name: exit 0" ;;
      124) echo "$name: exit 124, the ${MEASURE_CELL_CAP:-10m} cap hit" ;;
      *) echo "$name: exit $rc" ;;
    esac
    # grep's 1 is "not found"; any other failure is no answer, and says so.
    if [[ $target != direct ]]; then
      grep -rqF -f "$MEASURE_ROOT/$MEASURE_KEY" "$MEASURE_ROOT/$dir" 2>/dev/null
      case $? in
        0) echo "$name: THE KEY IS IN $dir; delete it before anything is shared" ;;
        1) echo "$name: the key is in none of $dir's files" ;;
        *) echo "$name: THE KEY SEARCH FAILED in $dir; search it before anything is shared" ;;
      esac
    fi
  } | _measure_say cell
  summarize "$name"
  return "$rc"
}

# The figures of one benchmark in a result JSON, one line each, every time in ms (GuideLLM keeps
# request latency in seconds); an embedding run has latency alone, its TTFT and ITL being 0.
# shellcheck disable=SC2016 # jq's variables.
_MEASURE_JQ='
def r: . * 100 | round / 100;
def mp(k): "\(.median * k | r) / \(.percentiles.p95 * k | r)";
.config.spec.backend as $b | .benchmarks[] | .metrics as $m | .config.strategy as $s
| ($b.request_format == "/v1/embeddings") as $embed
| (if $s.streams then "\($s.streams) streams" else "rate \($s.rate)/s" end) as $load
| "\($b.model) at \($b.target), \($load): requests ok \($m.request_totals.successful), errored \($m.request_totals.errored), incomplete \($m.request_totals.incomplete) of \($m.request_totals.total)",
  (if $embed then empty else
    "  TTFT ms median / p95: \($m.time_to_first_token_ms.successful | mp(1)); ITL ms: \($m.inter_token_latency_ms.successful | mp(1))" end),
  "  request latency ms median / p95: \($m.request_latency.successful | mp(1000))",
  ([.requests.errored[].info.error] | group_by(.) | map("  error x\(length): \(.[0])") | .[])'

summarize() {
  local name=${1:?usage: summarize <name>}
  local dir=$MEASURE_ROOT/$MEASURE_STATE/cells/$name start end
  {
    if [[ ! -f $dir/result.json ]]; then
      echo "$name: no result.json"
    else
      jq -r "$_MEASURE_JQ" "$dir/result.json"
      if [[ -f $dir/gateway-stats.tsv ]]; then
        start=$(jq '[.benchmarks[].start_time] | min' "$dir/result.json")
        end=$(jq '[.benchmarks[].end_time] | max' "$dir/result.json")
        # Samples inside the benchmark's time only; GuideLLM's start-up before it is idle. Memory
        # is docker's usage before the slash, in MiB.
        awk -F'\t' -v s="$start" -v e="$end" '
          function mib(v,  n) { n = v + 0
            if (v ~ /GiB/) n *= 1024; else if (v ~ /KiB/) n /= 1024; else if (v !~ /MiB/) n /= 1048576
            return n }
          function med(a, k,  i, j, t) { for (i = 2; i <= k; i++) for (j = i; j > 1 && a[j-1] > a[j]; j--) { t = a[j]; a[j] = a[j-1]; a[j-1] = t }
            return k % 2 ? a[(k+1)/2] : (a[k/2] + a[k/2+1]) / 2 }
          NR > 1 && $1 >= s && $1 <= e { if ($3 == "-") { miss++; next }
            k++; c[k] = $3 + 0; split($4, u, " / "); m[k] = mib(u[1]); if (c[k] > cmax) cmax = c[k]; if (m[k] > mmax) mmax = m[k] }
          END { if (!k) { printf "  gateway: no samples inside the benchmark (%d failed)\n", miss; exit }
            printf "  gateway: %d samples in the benchmark (%d failed); CPU %% median %.2f, max %.2f; memory MiB median %.1f, max %.1f\n",
              k, miss, med(c, k), cmax, med(m, k), mmax }' "$dir/gateway-stats.tsv"
      fi
      [[ ! -f $dir/row-metrics.tsv ]] || _measure_cap_levels "$dir"
    fi
    [[ ! -f $dir/exit ]] || echo "  exit $(<"$dir/exit")"
  } | _measure_say summarize
}

# A cap run's requests as the gateway logged them, read after the run: the access log lines of the
# alias's route between two epochs, each kept as its time (docker's, UTC), status, path, the
# `retry_after` and `overflow` fields config.yaml adds, empty when the reply had neither header, and
# `retry.attempt`, empty when the request wasn't retried. The rest of each line, the caller's
# address and the endpoint among it, is left out. Each alias has its own route, so a line is the
# alias's by the route the access log names, `route=default/<alias>`.
_measure_requests() {
  local name=$1 alias=$2 since=$3 until=$4
  local out=$MEASURE_STATE/cells/$name/gateway-requests.tsv
  local remote="docker logs --timestamps --since $since --until $until agentgateway 2>&1"
  _measure_log laptop "ssh -n $MEASURE_GATEWAY_HOST '$remote' | the lines of route=default/$alias as time, status, path, retry_after, overflow, retry_attempt > $out"
  {
    printf 'time\tstatus\tpath\tretry_after\toverflow\tretry_attempt\n'
    # shellcheck disable=SC2029 # The command is built on the laptop, with no secret in it.
    ssh -n "$MEASURE_GATEWAY_HOST" "$remote" |
      awk -v route=" route=default/$alias " 'index($0, route) {
        st = ""; p = ""; ra = ""; of = ""; rt = ""
        if (match($0, / http\.status=[0-9]+/)) st = substr($0, RSTART + 13, RLENGTH - 13)
        if (match($0, / http\.path=[^ ]+/)) p = substr($0, RSTART + 11, RLENGTH - 11)
        if (match($0, / retry_after=[^ ]+/)) ra = substr($0, RSTART + 13, RLENGTH - 13)
        if (match($0, / overflow="[a-z]+"/)) of = substr($0, RSTART + 11, RLENGTH - 12)
        if (match($0, / retry\.attempt=[0-9]+/)) rt = substr($0, RSTART + 15, RLENGTH - 15)
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, st, p, ra, of, rt }'
  } >"$MEASURE_ROOT/$out"
  printf '%s: %d request lines from the gateway log\n' "$name" \
    "$(($(wc -l <"$MEASURE_ROOT/$out") - 1))" | _measure_say cell
}

# A cap run's levels, each benchmark of its result.json in turn: every reply's status, as GuideLLM
# saw it (2xx for each successful request; an errored one's status read from its error) and as the
# gateway logged it, with any Retry-After; the row's running and waiting requests (median, max)
# from the samples inside the level's time; then latency growth from the first level to the
# second. The gateway's /models lines, GuideLLM's backend check, are left out of its counts.
# shellcheck disable=SC2016 # jq's variables.
_MEASURE_CAP_JQ='
.benchmarks[] | .config.strategy.streams as $n
| "\($n)\t\(.start_time)\t\(.end_time)\t"
  + ([(range(.metrics.request_totals.successful) | "2xx"),
      (.requests.errored[].info.error | [capture("(?<s>[1-5][0-9][0-9]) ")][0].s // "no status")]
     | group_by(.) | map("\(.[0]) x\(length)") | join(", "))'
# shellcheck disable=SC2016 # jq's variables.
_MEASURE_GROWTH_JQ='
def r: . * 100 | round / 100;
(.config.spec.backend.request_format == "/v1/embeddings") as $embed
| if (.benchmarks | length) < 2 then "  growth: one level only" else
  .benchmarks[0] as $a | .benchmarks[1] as $b
  | ((if $embed then [] else [["time_to_first_token_ms", 1], ["inter_token_latency_ms", 1]] end) + [["request_latency", 1000]])[] as [$f, $k]
  | ($a.metrics[$f].successful.median * $k) as $x | ($b.metrics[$f].successful.median * $k) as $y
  | "  growth \($a.config.strategy.streams) to \($b.config.strategy.streams): \($f | sub("_ms$"; "")) median ms \($x | r) to \($y | r), \(($y - $x) | r) (x\(if $x > 0 then $y / $x | r else "-" end))"
  end'

_measure_cap_levels() {
  local dir=$1 n s e statuses iso_s iso_e
  while IFS=$'\t' read -r n s e statuses; do
    echo "  level $n: GuideLLM replies ${statuses:-none}"
    iso_s=$(date -u -d "@${s%.*}" +%Y-%m-%dT%H:%M:%S)
    iso_e=$(date -u -d "@$((${e%.*} + 1))" +%Y-%m-%dT%H:%M:%S)
    if [[ -f $dir/gateway-requests.tsv ]]; then
      awk -F'\t' -v s="$iso_s" -v e="$iso_e" '
        NR > 1 && substr($1, 1, 19) >= s && substr($1, 1, 19) < e && $3 !~ /\/models$/ {
          k++; st[$2]++; if ($4 != "" && $4 != "\"\"") { ra++; v[$4]++ } }
        END { line = ""; for (c in st) line = line (line ? ", " : "") c " x" st[c]
          printf "  level gateway log: %d requests, %s; Retry-After on %d", k, (k ? line : "none"), ra
          for (x in v) printf " (%s x%d)", x, v[x]
          printf "\n" }' "$dir/gateway-requests.tsv"
    fi
    awk -F'\t' -v s="$s" -v e="$e" '
      function med(a, k,  i, j, t) { for (i = 2; i <= k; i++) for (j = i; j > 1 && a[j-1] > a[j]; j--) { t = a[j]; a[j] = a[j-1]; a[j-1] = t }
        return k % 2 ? a[(k+1)/2] : (a[k/2] + a[k/2+1]) / 2 }
      NR > 1 && $1 >= s && $1 <= e { if ($3 == "-") { miss++; next }
        k++; r[k] = $3 + 0; w[k] = $4 + 0; if (r[k] > rmax) rmax = r[k]; if (w[k] > wmax) wmax = w[k] }
      END { if (!k) { printf "  level row: no samples inside the level (%d failed)\n", miss; exit }
        printf "  level row: %d samples (%d failed); running median %g, max %g; waiting median %g, max %g\n",
          k, miss, med(r, k), rmax, med(w, k), wmax }' "$dir/row-metrics.tsv"
  done < <(jq -r "$_MEASURE_CAP_JQ" "$dir/result.json")
  jq -r "$_MEASURE_GROWTH_JQ" "$dir/result.json"
}

# Behavior 7's reading, per figure: the two direct runs, their spread |d1 - d2|, the gateway run,
# and what it adds over the direct runs' mean, g - (d1 + d2) / 2; "within" when that is no larger
# than the spread, "beyond" when it is. Medians and p95s of TTFT, ITL, and request latency, all in
# ms; an embedding run, latency alone.
# shellcheck disable=SC2016 # jq's variables.
_MEASURE_COMPARE_JQ='
def r: . * 100 | round / 100;
def fig($p): .benchmarks[0].metrics | getpath($p);
($d1[0].config.spec.backend.request_format == "/v1/embeddings") as $embed
| ((if $embed then [] else [["time_to_first_token_ms", 1], ["inter_token_latency_ms", 1]] end) + [["request_latency", 1000]])[] as [$f, $k]
| (["median"], ["percentiles", "p95"]) as $q
| ([$f, "successful"] + $q) as $p
| ($d1[0] | fig($p) * $k) as $a | ($d2[0] | fig($p) * $k) as $b | ($g[0] | fig($p) * $k) as $c
| (($a - $b) | fabs) as $spread | ($c - ($a + $b) / 2) as $added
| "\($f | sub("_ms$"; "")) \($q[-1]) ms: direct \($a | r), \($b | r), spread \($spread | r); gateway \($c | r), adds \($added | r), \(if ($added | fabs) <= $spread then "within" else "beyond" end) the spread"'

compare() {
  if (($# != 3)); then
    echo 'usage: compare <direct-1> <gateway> <direct-2>' >&2
    return 2
  fi
  local cells=$MEASURE_ROOT/$MEASURE_STATE/cells n
  for n in "$@"; do
    [[ -f $cells/$n/result.json ]] || {
      echo "compare: no result.json for $n" >&2
      return 2
    }
  done
  _measure_log laptop "compare $*"
  jq -nr --slurpfile d1 "$cells/$1/result.json" --slurpfile g "$cells/$2/result.json" \
    --slurpfile d2 "$cells/$3/result.json" "$_MEASURE_COMPARE_JQ" | _measure_say compare
}

overflow_read() {
  local name=${1:?usage: overflow_read <name>}
  local dir=$MEASURE_ROOT/$MEASURE_STATE/cells/$name start end iso_s iso_e
  for f in gateway-requests.tsv result.json; do
    [[ -f $dir/$f ]] || {
      echo "overflow_read: no $f in $MEASURE_STATE/cells/$name; run it with cell ... cap <alias>" >&2
      return 2
    }
  done
  if ! head -1 "$dir/gateway-requests.tsv" | grep -q $'\toverflow\t'; then
    echo "overflow_read: $MEASURE_STATE/cells/$name was read before the overflow column; nothing to read" >&2
    return 2
  fi
  _measure_log laptop "overflow_read $name"
  start=$(jq '[.benchmarks[].start_time] | min' "$dir/result.json")
  end=$(jq '[.benchmarks[].end_time] | max' "$dir/result.json")
  iso_s=$(date -u -d "@${start%.*}" +%Y-%m-%dT%H:%M:%S)
  iso_e=$(date -u -d "@$((${end%.*} + 1))" +%Y-%m-%dT%H:%M:%S)
  # The lines inside the benchmark, the gateway's /models lines (GuideLLM's backend check) left out,
  # in time order; docker's RFC 3339 times, all UTC, sort as text.
  tail -n +2 "$dir/gateway-requests.tsv" | sort |
    awk -F'\t' -v s="$iso_s" -v e="$iso_e" -v secs="$(( ${end%.*} - ${start%.*} ))" '
      substr($1, 1, 19) < s || substr($1, 1, 19) >= e || $3 ~ /\/models$/ { next }
      {
        k++; src = ($5 == "azure") ? "azure" : "row"
        by[src, $2]++; n[src]++
        if (src == "row" && $2 == 503) row503++
        if ($6 != "") { retried++; tries += $6; if (src == "azure") rescued++ }
        if (src == "azure" && last != "azure") windows++
        last = src
        if (!first && ((src == "row" && $2 == 503) || $6 != "" || src == "azure")) first = $1
      }
      END {
        if (!k) { print "  no request lines inside the benchmark"; exit }
        for (x in n) {
          line = ""
          for (key in by) { split(key, ks, SUBSEP); if (ks[1] == x) line = line (line ? ", " : "") ks[2] " x" by[key] }
          printf "  answered by %s: %d (%s)\n", x, n[x], line
        }
        printf "  503 from the row to the client: %d\n", row503
        printf "  retried: %d requests, %d retries; of them answered by Azure: %d, so a refused request %s Azure\n",
          retried, tries, rescued, (rescued ? "reached" : "did not reach")
        printf "  eviction windows (estimated from the log order): %d in %d s, %.1f a minute\n",
          windows, secs, (secs ? windows * 60 / secs : 0)
        printf "  first refusal: %s\n", (first ? first : "none")
      }' | while IFS= read -r line; do
      # The first refusal'"'"'s time, as seconds from the benchmark'"'"'s start.
      if [[ $line == '  first refusal: '* && $line != *none ]]; then
        t=${line#'  first refusal: '}
        line="  first refusal: $(awk -v a="$(date -u -d "$t" +%s.%N)" -v b="$start" 'BEGIN { printf "%.1f", a - b }') s after the benchmark's start ($t)"
      fi
      printf '%s\n' "$line"
    done | { echo "$name: benchmark C"; cat; } | _measure_say overflow_read
}

mkdir -p "$MEASURE_ROOT/$MEASURE_STATE/cells"
_measure_log laptop "source scripts/measure-lib.sh"
