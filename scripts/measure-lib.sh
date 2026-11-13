#!/usr/bin/env bash
# The agentgateway task's step helpers for its overhead cells (slice 2, behavior 7), adapted from
# spike-model-layout's scripts/measure-lib.sh (`cell`, `watch`, `summarize`) and kept to what these
# cells need: no host loads, memory floors, or readouts of the rows. Sourced from the repository
# root on the laptop, then called one step at a time in the architect's view:
#
#   source scripts/measure-lib.sh
#
#   cell <name> <scenario> <direct|gateway> <alias>
#                     one GuideLLM run of bench/<scenario>.yaml against the alias's row (direct)
#                     or its base URL on the gateway, into .state/agentgateway/cells/<name>/; on a
#                     gateway run, the gateway container's CPU and memory sampled on gb10-2
#   summarize <name>  a run's requests and errors, TTFT, ITL and request latency (median, p95),
#                     and on a gateway run the container's CPU and memory during the benchmark
#   compare <direct-1> <gateway> <direct-2>
#                     behavior 7's reading: each figure's spread between the two direct runs
#                     beside what the gateway run adds over their mean
#
# No helper runs a benchmark on its own or chains runs: `cell` runs exactly one.
#
# The command log. Each helper call and each command it runs is appended to
# .state/agentgateway/commands-<YYYY-MM-DD>.log, and printed to stderr, as
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
# Settings, each an environment variable read when a helper runs:
#   MEASURE_STATS_EVERY  seconds between gateway samples (default 5)
#   MEASURE_CELL_CAP     a run's cap, given to timeout (default 10m)

if ! (return 0 2>/dev/null); then
  echo 'measure-lib.sh is sourced, not run: source scripts/measure-lib.sh' >&2
  exit 2
fi

MEASURE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Relative to the root: every command runs from there, so the log names no home directory.
MEASURE_STATE=.state/agentgateway
MEASURE_KEY=$MEASURE_STATE/keys/bench
MEASURE_GATEWAY_HOST=gb10-2
MEASURE_GATEWAY=http://$MEASURE_GATEWAY_HOST:3000

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
  local usage='usage: cell <name> <scenario> <direct|gateway> <alias>'
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
    gateway)
      url=$MEASURE_GATEWAY/$alias/v1
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
      if [[ $target == gateway ]]; then
        GUIDELLM__SPEC__BACKEND__API_KEY=$(<"$MEASURE_KEY")
        export GUIDELLM__SPEC__BACKEND__API_KEY
      fi
      exec "${run[@]}"
    ) >"$dir/guidellm.log" 2>&1 &
    pid=$!
    trap 'kill -TERM "$pid" 2>/dev/null' INT TERM
    # GuideLLM's own output, followed in the terminal until it exits.
    tail -n +1 -f --pid="$pid" "$dir/guidellm.log" &

    # The gateway sampler, on a gateway run only: the container's CPU (100% is one core) and
    # memory, one `docker stats --no-stream` on gb10-2 at each interval, until GuideLLM exits. A
    # failed read is a row of dashes, so a gap shows. summarize keeps the samples inside the
    # benchmark's time.
    if [[ $target == gateway ]]; then
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
  {
    case $rc in
      0) echo "$name: exit 0" ;;
      124) echo "$name: exit 124, the ${MEASURE_CELL_CAP:-10m} cap hit" ;;
      *) echo "$name: exit $rc" ;;
    esac
    if [[ $target == gateway ]]; then
      if grep -rqsF -f "$MEASURE_ROOT/$MEASURE_KEY" "$MEASURE_ROOT/$dir"; then
        echo "$name: THE KEY IS IN $dir; delete it before anything is shared"
      else
        echo "$name: the key is in none of $dir's files"
      fi
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
    fi
    [[ ! -f $dir/exit ]] || echo "  exit $(<"$dir/exit")"
  } | _measure_say summarize
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

mkdir -p "$MEASURE_ROOT/$MEASURE_STATE/cells"
_measure_log laptop "source scripts/measure-lib.sh"
