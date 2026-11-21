# The scripts

The reasoning behind the scripts in [`scripts/`](../scripts/) that their names and headers don't
carry, one section per script; each script's header says what it does and how it is run, and
points at its section with a `See` line. [`gateway/compose.sh`](../gateway/compose.sh) points at
[`stack.md`](stack.md) instead.

## The deploy

[`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh), in the order it runs.

- **Keys.** agentgateway's hash of a presented key is the sha256 of its exact characters, no
  newline, as lowercase hex (`APIKeyHash::from_raw_key`). The key reaches sha256sum through
  printf, a builtin, so it is never in a process's argv.
- **Postgres's password** is created like a key, once, and reused: Postgres reads it only when it
  first initializes its volume, so it must not change after, except through `pg_password_rotate`
  ([The client helpers](#the-client-helpers)), which changes it in Postgres first; the next deploy
  then sends the new one.
- **The Azure account's name** is read from .state/azure/account.env as assignments, not sourced:
  each value is the line's text after `=`, quotes stripped.
- **Secret characters.** A secret's value is substituted into YAML and a URL as it is, so it may
  hold only A-Z, a-z, 0-9, `.`, `_`, and `-`.
- **A secret marker in a comment** is refused on the copy's lines before any is rendered. The line
  is named by its number in the copy before its overlays header, which is config.yaml's own number
  when no overlay applies, and printed as committed, so it holds the marker's name and no secret.
- **The copy** is rendered in bash, not by sed, so no hash or secret is in a command's argv. It is
  written only under .state/, which is untracked, and removed on exit, as is Postgres's env file. A
  line may name more than one secret; the last is replaced first, and one with no value stays for
  the next check to refuse.
- **Unrendered markers.** A marker left over, or a keyHash that isn't a full hash, would deploy a
  key list that admits no one under that name, or a secret that isn't one, so the deploy stops
  before anything is sent, printing only the markers' names. The keyHash check is one grep, not two
  piped: under pipefail, the first one's SIGPIPE when `-q` stops reading early would fail the
  pipeline and pass a bad keyHash.
- **The project** goes as gateway/ holds it, with deploy.env as the project's .env; the trace
  services' build contexts go whole, each directory as its image copies it.
- **Validation** runs as the container reads the copy: as the deploying user, its directory mounted
  read-only. It parses the config and connects to nothing, Postgres included.
- **The container from before compose** holds the name and the ports compose's agentgateway takes,
  and carries no compose project label, which is how the deploy tells it apart.

## The step helpers

[`scripts/measure-lib.sh`](../scripts/measure-lib.sh).

- **Paths** under .state/ are relative to the root: every command runs from there, so the log names
  no home directory.
- **The seed.** Each run takes its own seed, from its name, so a run's synthetic prompts and images
  are its own: GuideLLM's default seed, 42, would send each run the last one's, and the row's prefix
  cache would serve the gateway run and the second direct run what the first direct run sent. The
  audio cell's clips come from a dataset, the same in every run, which no seed changes.
- **The run.** The run, the terminal's view of it, and the samplers share one foreground subshell,
  so Ctrl-C reaches them all; timeout puts GuideLLM in a process group of its own, so the trap passes
  the interrupt on to it, and timeout stops GuideLLM. A wait an interrupt cut short is waited again,
  for GuideLLM's own status.
- **The samplers.** The row sampler, on a cap run, reads the row's own /metrics direct from the
  laptop (the rows stay reachable directly), each figure the sum over the row's engines of vLLM's
  gauge. The gateway sampler, on a gateway or cap run, takes one `docker stats --no-stream` on
  gb10-2 an interval: CPU, where 100% is one core, and memory. A failed read is a row of dashes, so
  a gap shows. `summarize` keeps the samples inside the benchmark's time, since GuideLLM's start-up
  before it is idle, and reads memory as docker's usage before the slash, in MiB.
- **The figures.** Every time is in ms (GuideLLM keeps request latency in seconds); an embedding run
  has latency alone, its TTFT and ITL being 0.
- **The key search.** grep's exit 1 is "not found"; any other failure is no answer, and says so.
- **The access log.** Each alias has its own route, so a line is the alias's by the route it names,
  `route=default/<alias>`, and the run's by its key. A line with no key_name, logged before
  config.yaml added it or refused 401, is kept. A log that wasn't read fails the step, since it
  would otherwise pass as a run the gateway logged no request of.
- **A cap run's levels** give every reply's status as GuideLLM saw it (2xx for each successful
  request; an errored one's read from its error) and as the gateway logged it. The gateway's
  /models lines, GuideLLM's backend check, are left out of every count, `overflow_read`'s included;
  docker's RFC 3339 times, all UTC, sort as text.
- **compare**, per figure (the medians and p95s of TTFT, ITL, and request latency): the two direct
  runs' spread, |d1 - d2|, and what the gateway run adds over their mean, g - (d1 + d2) / 2,
  "within" when that is no larger than the spread and "beyond" when it is.
- **rtfx** takes each level's median, interpolated linearly between the two nearest ranks, leaving
  out a request with no clip; the median, not the mean, is what the floor is judged by. A run jq
  can't read fails the call, rather than leaving a name with no figure under it.

## The client helpers

[`scripts/clients-lib.sh`](../scripts/clients-lib.sh).

- **State.** Each task keeps its state and log in its own folder, `CLIENTS_STATE`, so an earlier
  task's, such as .state/answer, is left as that task left it. Paths are relative to the root, and
  `retry_case`'s to retry/, where go test runs, so the log names no home directory.
- **go-ai's release**, tools/infer/v0.3.1, carries per-role models and profiles in both tiers,
  infer's default retry policy, and `infer models`' root column. Its base module is v0.4.0, which
  the retry test requires ([`retry/go.mod`](../retry/go.mod)). v0.4.0 and v0.3.0 are additive over
  v0.2.0, where the retry cases and the rows-down revalidation were measured: they change neither
  retry, the formats, nor the profiles (both CHANGELOGs at the tags).
- **The profiles.** The agent row's, rows up, is vLLM 0.34.0 serving gpt-oss-120b exactly as go-ai's
  integration/doc.go at tools/infer/v0.3.1 gives it, each field backed there by a recording of that
  row. Rows down, Azure's gpt-oss-120b refuses tool_choice required
  ([`findings/priority.md`](findings/priority.md), "The tiers on Azure"), and Azure's gpt-5-mini
  refuses effort none ("Per alias") and lists minimal through high as its supported values, so each
  format's efforts above high are declared refused too.
- **infer's retries.** `infer_at` clears infer's retry settings from the caller's shell, so infer
  keeps its default, 3 attempts, unless a flag says otherwise. `infer_once`'s `--retries` is
  infer's root flag, so it goes before the command (go-ai's tools/infer/README.md, "Retries", at
  tools/infer/v0.3.1).
- **Reads that fail.** `azure_count` reads the log whole before it counts it, so a log that wasn't
  read gives no count, rather than counts of nothing that read as nothing sent to Azure; the log is
  held, never printed. `budget_status` and `requests_shed` run curl with `-f`, so an error reply
  fails the call rather than reaching jq or grep as a body with nothing in it. `request_log` runs
  psql with ON_ERROR_STOP, without which psql reading a script on stdin exits 0 after a failed
  statement.
- **traces** quotes the TraceQL query once, for the remote shell, before docker exec passes it to
  curl. One docker exec reads every trace, each body ended by a newline, so jq reads one a line.
- **messages_stream** names each send's folder to the millisecond and makes it with plain mkdir, so
  two sends in one second never share a folder. The send's stamp is taken after the logging, so the
  log's own time isn't counted. `$EPOCHREALTIME` is seconds and six digits of microseconds, so
  without the point it is microseconds.

## Currency

[`scripts/currency.sh`](../scripts/currency.sh).

- An image tag needs at least one dot to count as a release, so a bare build number never sorts
  above one.
- The client helpers' go-ai tag is read from its assignment line in clients-lib.sh, since the
  library is sourced only, into the architect's shell.

## The watch

[`scripts/watch.sh`](../scripts/watch.sh).

- `load_tag` and `load_file` set globals rather than print, so the reads they cache outlive the
  call. A file read that fails may leave gh's error body behind; it is removed, so no later line
  reads it.
- A read that failed, an empty value now, always differs, even from an empty recorded value.
- A release holds a commit when GitHub's compare of the commit to the tag is ahead or identical;
  behind or diverged, it doesn't.
