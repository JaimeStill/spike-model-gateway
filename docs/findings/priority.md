# priority

What answers when a row is down or full, and how the gateway ranks, limits, and charges each key's
work: overflow from each row to its own Azure AI Foundry deployment under the same alias, per-key
priority, request-rate buckets and token budgets, and embedding held to 34 requests a second
(evidence 5–7 of [`context/README.md`](../../context/README.md#the-evidence)). This finding holds
slice 1, the setup; slice 2, the overflow and benchmark C; slice 3, the keys and limits and
benchmarks A, B, and D; and slice 4, the walkthrough the architect ran.

In short, after slices 1–4:

- **Evidence 5:** the embedding route held a global 34 requests a second, and refused the rest
  with 429 and `Retry-After: 1`. Beside it, audio held its real-time factor: RTFx median 5.38,
  against the floor of 5.
- **Evidence 6:** each key has its own request-rate bucket and token budget, kept in Postgres. A
  stream sent without `include_usage` was charged to its key, and a budget count survived a
  gateway restart. Every request writes a metadata row and no content. The UI's Logs and
  Analytics pages show those rows, but its sidebar doesn't link them on this config: they load
  by URL.
  - Chat held its floor beside bulk vision: agent ITL median 47.05 ms.
  - Priority by key cut interactive vision's median latency from 11.87 s to 10.47 s on a
    saturated row. That misses the 10 s mark by 0.47 s, because vLLM's priority orders only the
    waiting queue.
- **Evidence 7:** with its row down, each alias was answered by its Azure deployment under the
  alias, marked as overflow, and returned to its row after. Under saturation, a row's 503 with
  eviction sends nearly the whole load to Azure (benchmark C). Through the Framework's reboot
  (behavior 11), audio and embedding were answered by Azure while it was locked. After the
  reported unlock, `/health` came in about 4 s (embedding) and 49 s (audio), and each row answered
  again the first request sent to it, about 57 s and 58 s after the unlock, when the recovery loop
  started; each time is a lower bound. A powered-down host costs each attempt a connect timeout of
  about 11 s, so audio's large body got two 503s before its row was evicted. On overflow, audio
  in a Responses request is refused by the gateway itself, whose typed parser has no audio input
  part; Chat Completions with audio passes on Azure (the audio rerun, after the review).

Azure has answered 189 of the task's 300 requests: none in slice 3, 3 in the walkthrough, and 6 in
the audio rerun after the review, one of them the gateway's own refusal ("The Azure count").
After the review the rows run vLLM v0.34.0 and passed a smoke check; the benchmarks ran on
v0.33.0 and are not rerun. Postgres was recreated on every deploy until `gateway/compose.sh` turned
off buildx's default attestation, which Compose v5.2.0 ignores `provenance: false` for ("Why
Postgres was recreated").
"Answer for this task", below, gives what the gateway does and doesn't do.

- **Measured:** from the laptop. Slice 1 ran 2026-11-16 13:05–13:56 local time, slice 2
  14:17–14:41, slice 3 16:15–16:40; the walkthrough ran 2026-11-17 05:37–05:53, and the readings
  after the review 06:10–06:57. Every command the helpers logged is under "Commands as run".
- **Path:** slices 1 and 2 ran over Tailscale's DERP relay, 51–52 ms; slice 3 ran on a direct
  path, 1–2 ms, and 2026-11-17 on a direct path, 0–1 ms. Only cells run in the same session compare.
- **Gateway:** agentgateway v1.7.0, `cr.agentgateway.dev/agentgateway:v1.7.0`, on gb10-2, with its
  Postgres (`postgres:18.7-alpine`) in one compose project
  ([`gateway/compose.yml`](../../gateway/compose.yml)), configured from
  [`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml).
- **Rows:** vLLM v0.33.0, each row serving its alias as its only model name, from
  spike-model-engines `host/` at `2950b83`, the merge of its pull request #18, for slices 1–4 and
  every benchmark. After the review, vLLM v0.34.0 from `aaf19ed`, the merge of #19, with the same
  flags; the logged reading at 06:57:39 on 2026-11-17 found every row on v0.34.0, its flags
  unchanged, and its `/health` 200 ("spike-model-engines current (behavior 1)"). Only the
  post-upgrade smoke check ran on it.
- **Cloud:** Azure AI Foundry, the spike's own resource group and AIServices account in eastus2,
  SKU S0, one deployment per alias ("Azure AI Foundry", below).
- **Sources:** agentgateway at the `v1.7.0` tag (`schema/config.md`, `crates/agentgateway/src/`,
  `crates/llm/src/`). **[src]** marks a reading of the source that no doc states.
- **Kept out:** no address, key, key hash, Azure account or resource group name, or other secret.
  The Azure helper's command lines show the expressions that read the key and account name, never
  their values. A quoted access log line has the caller's address replaced with `<laptop>` and the
  Azure host with `<account>`. Raw output stays untracked under `.state/priority/`.

## The question and its evidence

The brief's behaviors, each with the evidence it proves and the slice that shows it:

| Behaviors | What they show | Evidence | Slice |
| --- | --- | --- | --- |
| 1, 2 | spike-model-engines current; the agent, vision, and audio rows refuse with 503 once twice their cap is in flight (agent 24, vision 32, audio 8), embedding unlimited, and agent and vision schedule by priority | 6, 7 | 1 |
| 3 | an Azure AI Foundry deployment per alias, each answering one direct request | 7 | 1 |
| 4 | the gateway and Postgres as one compose project on gb10-2, restarting with the host | 6 | 1 |
| 5, 6 | two priority groups per alias, typed request formats, streamed usage, and `/v1/models` answered by the gateway | 7 | 2 |
| 7, 8 | a row down: each alias answered by Azure under the alias, marked as overflow, and back to its row after; nothing fails over between hosts | 7 | 2 |
| 9 | a row full: two 503s evict it, for 5 s the first time and longer each time after, a retry sends a request at most 3 times, and benchmark C reads what reaches Azure | 7 | 2 |
| 10 | go-ai's and infer's tiers through the rows-down overlay, and the infer CLI | 7 | 2 |
| 11 | the Framework down until `/health` after its LUKS unlock | 7 | 4 |
| 12 | per alias, the cloud model, its processing scope, and its parity gaps | 7 | 2 |
| 13–16 | per-key priority, request-rate buckets, token budgets in Postgres over a fixed clock hour, and the request log | 6 | 3 |
| 17 | embedding held to 34 requests a second | 5 | 3 |
| 18–20 | at most 300 Azure-answered requests, the records, currency and the check | — | all |

### Answer for this task

**What agentgateway does natively on route `ai`.** Overflow: each alias's backend holds its row
and then its Azure deployment as priority groups, and a row evicted after 2 failures goes to Azure
while it is out, under the alias, marked by a header and in the access log: 5 s the first time,
and 5 s times the evictions so far each time after, with no cap, until a reload clears the count.
503s are retried for bodies up to 64 KiB, a request sent at most 3 times. Priority: it sets
vLLM's `priority` per key on the rows' providers, and vLLM orders its waiting queue by it. Limits: a request-rate bucket per key and route, and a global one, such as
embedding's 34 a second, each refusing with 429 and `Retry-After`. Budgets: a token budget per key
per clock hour in Postgres, Block or Audit, charging streams and surviving restarts. Every request
writes a metadata row, which the UI's Logs and Analytics pages show.

**What it can't do.** It can't overflow a single request when a row is full: Azure answers only
once the row is evicted, so the requests that evict it get 503 unless retried, a large body never
is, and a powered-down host costs each attempt about 11 s first. Nothing caps what an eviction
sends: every request in an eviction's window goes to Azure, nearly the whole load under
saturation (benchmark C), and nothing caps how long the windows grow. Priority goes no further
than queue order: a running request shares the batch, so interactive vision missed 10 s by 0.47 s
beside bulk. A budget's `rolling: 1h` is a fixed UTC
clock hour, not a sliding window. The UI doesn't link Logs or Analytics on route `ai`, and
agentgateway logs no eviction. The uncapped eviction growth, the fixed window, and the missing
links are entries in the watch register, [`docs/watch.md`](../watch.md). agentgateway's `azure`
provider builds neither the verified Foundry host nor its path, so each deployment is a `custom`
provider.

**The parity gaps that decide which workloads may leave the self-hosted machines** ("Per alias:
the cloud model and its parity", behavior 12): agent and embedding are processed within the data
zone, vision and audio globally. agent's tool-calling workloads break on Azure (`tool_choice:
required` refused, a named function ignored). Embedding's vectors come from another space, so
nothing indexed by the row may be searched with them. Audio serves only Chat Completions with
audio in, and vision needs `max_completion_tokens` and no reasoning effort `none`. Which
workloads leave is the architect's call in `answer`.

What each piece of evidence has shown:

| Evidence | Result after slices 1–4 | Still open |
| --- | --- | --- |
| 5, embedding held beside audio | The global 34/1s bucket admitted 34 of a 40-request burst and 34.0 a second under 160 in flight, refusing the rest with 429 and `Retry-After: 1`. Audio inside it: RTFx median 5.38, 43 of 64 at 5 or more, so the floor meets and no paced bucket is needed (benchmark A). | — |
| 6, keys ranked, limited, and charged | bulk refused by its own bucket (429, `retry-after: 59`) and by its Block budget (429 `budget_exceeded`, `retry-after: 2609`), while go-ai kept answering. A stream without `include_usage` was charged 128 tokens. bulk's count of 44 survived a gateway restart. Request log: metadata only, 0 payload rows. Benchmark B: agent ITL median 47.05 ms beside bulk vision. Benchmark D: interactive vision median latency 10.47 s with priority, 11.87 s without. The UI's Logs page listed each request with its key as the user and its provider, with prompt logging off; Analytics totalled tokens and calls. The sidebar doesn't link either on route `ai`; both load by URL (walkthrough step 5). | — |
| 7, overflow when a row is down or full | Every alias answered by Azure under its alias with the rows down, and by its row once the overlay was removed. Under saturation, a row's 503 with eviction sent nearly the whole load to Azure (C-agent). With the Framework rebooted and locked, audio and embedding were answered by Azure; after the unlock, `/health` came in about 4 s (embedding) and 49 s (audio), and each row answered the first request sent to it, about 57 s and 58 s after the unlock, when the recovery loop started; each time is a lower bound (behavior 11). Parity gaps per alias are recorded. | — |

## Method

**Steps.** The session runs every host step over Tailscale SSH with no root, each through the step
helpers, [`scripts/clients-lib.sh`](../../scripts/clients-lib.sh) and
[`scripts/measure-lib.sh`](../../scripts/measure-lib.sh), or the deploy,
[`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh), which log each command to
`.state/priority/commands-<date>.log` before it runs. The architect runs the root steps (host
updates, the gb10-2 and Framework reboots, the LUKS unlock) and the Azure walk, Foundry's first.

**Overflow.** Each alias route's `ai` backend has two priority groups: the alias's row, then its
Azure deployment. A request goes to the first group with a provider not evicted, so Azure answers
only while the row is out, and only for its own alias: nothing fails over between hosts. The row's
health policy evicts it after two consecutive unhealthy replies, a 503 or a failed connection.
The first eviction lasts 5 s, and each later one 5 s times the number of evictions so far, 10 s,
15 s, and on, with no cap, until a config reload builds the backends again and clears the count
(`http/health.rs`) [src]. A route retry, `attempts: 2`, makes up to 2 more attempts on 503, each
after a 20 ms backoff (the slice 2 escalation, below), so a request is sent at most 3 times: the
architect's decision at review (2026-11-17), amending behavior 9's "a route retry of 2
attempts", is that `attempts` counts the retries, not the sends. Chat Completions,
embeddings, Messages, and Responses are typed request formats, so the gateway names each
deployment as the model and builds its path; the rest stay `detect`. Each alias's `/v1/models` is
answered by the gateway itself. Every reply Azure answers carries `x-gateway-overflow: azure`, and
the access log records it on that request's line as `overflow="azure"`. The config's comments
give each field and its source.

**The Azure provider's shape.** Each deployment was verified at
`https://<account>.services.ai.azure.com/openai/v1/<path>`, with the account's key in `api-key` and
the deployment's name as the model. agentgateway's `azure` provider builds neither that host nor
that path (`crates/llm/src/azure.rs`) [src]:

| `resourceType` | Host | Path |
| --- | --- | --- |
| `foundry` (`aiServices` is its alias) | `<account>.services.ai.azure.com` | `/api/projects/<project>/openai/v1/...`, a Foundry project's, which the account has none of |
| `openAI` | `<account>.openai.azure.com` | `/openai/v1/...` |

So each Azure provider is an OpenAI-compatible `custom` provider, every field documented in
`schema/config.md`: `hostOverride` at the verified host on 443, `pathPrefix: /openai/v1`,
`backendTLS: {}` (a host override drops the provider's default TLS), `backendAuth.key` with
`location.header.name: api-key`, `custom.model` set to the deployment, and `custom.formats` listing
only what that deployment serves. `providerOverride: azure` makes the access log's
`gen_ai.provider.name` read `azure` on its requests. Rejected: the `azure` provider's `openAI` type
at `<account>.openai.azure.com`, a host no deployment was verified on.

**Laptop check.** Before any deploy, the config was rendered with the deploy's own overlay code and
validated with the pinned image on the laptop, base and `rows-down`, and then run on the laptop
against a mock upstream, untracked, with nothing sent to any host or to Azure. Against the mock,
the gateway answered each `/v1/models` itself, sent a row-down request to the Azure provider with
the deployment as the model, `/openai/v1/<path>`, `api-key`, and the overflow header, set 768
dimensions on embeddings, added `include_usage` to a stream, kept vLLM's own fields and image and
audio parts on a row's request, and returned to the row about 5 s after an eviction. Two readings
bear on slice 2: an eviction reaches the load balancer through a spawned task, so a retry sent with
no backoff still found the evicted row, and the request whose 503s evicted it got its 503; and,
with no health policy of its own, the Azure provider was evicted for 3 s by a single 5xx, under
agentgateway's default for several groups. Escalation 1, below, answered both.

**The Azure cap.** Azure answers at most 300 requests in the task. After each step that can
overflow, the session reads `azure_count <since>`, which counts the access log lines marked
`overflow="azure"` per alias, so per deployment, and per status, and flags any 429 from Azure, a
stop condition. Only synthetic and test-fixture content is sent to Azure.

**Benchmark C.** Resized to Azure's capacity (escalation 1, below), and run as C-agent only: one
GuideLLM cell through the gateway, run with `cell <name> <scenario> cap <alias>` and read with
`overflow_read <name>`, [`bench/overflow-agent.yaml`](../../bench/overflow-agent.yaml), 28
concurrent single-turn chats for 60 s. C-agent breached the task's Azure stop rule, and the
architect dropped C-vision (escalation 2, below): its scenario,
[`bench/overflow-vision.yaml`](../../bench/overflow-vision.yaml), is kept and was never run.

## Slice 1 · setup

### The hosts

The architect ran the session-start updates (`apt full-upgrade`) on both GB10s; neither needed a
reboot. gb10-1 kept 3 phased updates (`distro-info`, `python3-distro-info`, `snapd`). The
Framework's one pending update waits for slice 4's reboot. Compose v5.2.0 was already on both GB10s,
so no install was needed. Read at 13:05:30 (before) and 13:20:44 (after), untracked under
`.state/priority/`:

| Host | Rows | Kernel | NVIDIA driver | Docker | Updates pending, before → after |
| --- | --- | --- | --- | --- | --- |
| gb10-1 | agent, 8000 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 12 → 3 |
| gb10-2 | vision, 8000; the gateway, 3000 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 9 → 0 |
| framework | audio, 8001; embedding, 8002 | 7.2.15-1-omarchy | — | — | 1, deferred to slice 4 (not read after) |

The laptop's path to every host was Tailscale's DERP relay (nyc), 51–52 ms, with no direct
connection (13:05:30). The 13:20:44 read's `git -C ~/spike-model-engines` found no checkout there:
the hosts keep it at `~/repos/spike-model-engines`, where the pull below ran.

The Framework's Docker version wasn't read at setup, and its stack wasn't read after its update in
the walkthrough's reboot; nor was the laptop's path to each host on 2026-11-17, the walkthrough's
day. The session reads them after the review:

- **The Framework's Docker version and stack after its update** (06:10:40): up 20 minutes since
  the walkthrough's reboot, kernel 7.2.15-1-omarchy, 0 updates pending, Docker 29.9.2, and
  `vllm-audio` and `vllm-embed` up, both still on v0.33.0 before the engines' bump below.
- **The laptop's path to each host on 2026-11-17** (06:10:40): direct to all three, gb10-1 and
  gb10-2 in 1 ms and the Framework in 0 s, as `tailscale ping` rounds it. The walkthrough's day
  ran on a direct path, as slice 3 did.

### spike-model-engines current (behavior 1)

Behavior 1 asks for spike-model-engines current at setup, its currency reporting only held items
and its check passing. That reading was not logged: the engines' `mise run currency` and `mise run
check` at setup, and the commands of the engines upgrade that brought its uv to 0.13.8, ran
outside the helpers, so no command or output is in the command log, and this finding can't quote
them. Only the pull and the row updates below are logged.

The review (2026-11-17) bumped the engines again: uv 0.13.9, vLLM v0.33.0 → v0.34.0, and
llama.cpp b12098 → b12464, ending the hold, through a second `host/` pull request, with the rows
restarted and a smoke check after (the goal record's decision). The task's benchmarks ran on
v0.33.0 and are not rerun. The session's readings, the rows' restarts and the smoke check logged
through the helpers:

- **The engines' currency after the upgrade:** spike-model-engines pull request #19, merged as
  `aaf19ed`: uv 0.13.9, llama.cpp b12464 (the hold ended), vLLM v0.34.0, the ROCm 7.2 fallback
  removed, and the four standing rows added to its `models.md`. vLLM v0.34.0 publishes no
  `-rocm72` image (vLLM #61939), so the fallback had nothing to pin; the architect chose removal.
  In spike-model-engines, `mise run check` passes and `mise run currency` reports only the two
  Python holds; the session ran both outside the helpers, so neither is in the command log.
- **The rows on v0.34.0:** all three hosts pulled `aaf19ed`, and the rows' updates started at
  06:19:36, the Framework building its audio image first. The three hosts pulled at once over the
  site's 118 Mbps link, so the Framework's 5.47 GB base layer came down at about 4 MB/s until the
  GB10s' pulls ended, then at about 12.5 MB/s. The session's own poll, outside the helpers and not
  logged, found all four rows' `/health` answering by 06:39:55, before the smoke check below. The
  logged reading at 06:57:39 (`docker inspect` of each `vllm` container, and each row's `/health`)
  shows every row on v0.34.0 with its flags unchanged:

  | Host | Container | Image | Started (UTC) | Flags | `/health` |
  | --- | --- | --- | --- | --- | --- |
  | gb10-1 | `vllm` | `vllm/vllm-openai:v0.34.0` | 11:37:25Z | `--max-num-queued-reqs 24 --scheduling-policy priority` | 200 |
  | gb10-2 | `vllm-vision` | `vllm/vllm-openai:v0.34.0` | 11:36:16Z | `--max-num-queued-reqs 32 --scheduling-policy priority` | 200 |
  | framework | `vllm-embed` | `vllm/vllm-openai-rocm:v0.34.0` | 11:37:23Z | neither flag | 200 (8002) |
  | framework | `vllm-audio` | `spike-model-engines/vllm-openai-rocm-audio:v0.34.0` | 11:37:22Z | `--max-num-queued-reqs 8` | 200 (8001) |
- **The post-upgrade smoke check** (06:40:06–06:44:24), every check passing:

  | Check | Result | Time |
  | --- | --- | --- |
  | `row_burst` one past each limit | agent 24 × 200 and 1 × 503, vision 32 and 1, audio 8 and 1 | 06:40:06–06:42:08 |
  | `/v1/models` on each `/<alias>/v1` | each lists its alias | 06:42:58 |
  | a request to each alias | agent "ready"; an agent stream carries 1 usage chunk; vision "Red" for the red PNG; audio "The access code is 7429."; embedding 2 vectors of 768; no reply carries the overflow header | 06:42:58–06:43:03 |
  | go-ai's tier, all four roles | 20 passed, 0 failed, 1 skipped; the key is not in its log | 06:43:09–06:44:02 |
  | infer's tier, all four roles | 13 passed, 0 failed, 1 skipped; the key is not in its log | 06:44:02–06:44:24 |
  | `azure_count` since 06:40:00 | 0 | 06:44:24 |

  The benchmarks aren't rerun, and a rerun on v0.34.0 could differ from slice 3's: v0.34.0 brings
  an extensible KV cache, a default block size of 64, and a cache fix for the DGX Spark, the GB10s'
  platform, each of which can move throughput and latency.
- **Scope: the engines' `models.md`.** Pull request #19's commit `683b78e` added the four standing
  rows to spike-model-engines' `docs/engines/vllm/models.md`. That file is outside `host/`, which
  is all experiment.hosting owns there, and outside the upgrade the goal record decided. The
  session asked for it from the standards reviewer's finding, without the architect's decision; it
  is raised in the session brief.

### The rows' limits

spike-model-engines pull request #18, merged as `2950b83`, gives the agent, vision, and audio rows
their queue limits, twice each cap (agent 24, vision 32, audio 8), and priority scheduling on agent
and vision; embedding has no limit. All three hosts pulled it at 13:21:26 and the rows were updated
at once. Agent, vision, and audio restarted under their new flags; embedding's flags were unchanged,
so its update reported "nothing changed". All four answered `/health` by 13:30:05, agent last, and
each container's flags were confirmed with `docker inspect`.

A burst one past each limit, straight to the row with no key, every request held in flight
(`row_burst`, 512 tokens each, `ignore_eos`):

| Row | Requests | 200 | 503 | Time |
| --- | --- | --- | --- | --- |
| agent | 25 | 24 | 1 | 13:30:22 |
| vision | 33 | 32 | 1 | 13:31:37 |
| audio | 9 | 8 | 1 | 13:32:23 |

The first `row_burst` call (13:30:15) answered `row_burst: command not found`, from a shell that
had sourced the helpers before `row_burst` was added; sourcing them again fixed it.

### Azure AI Foundry

The architect created the resource group and the AIServices account (eastus2, S0) and its
deployments from the az CLI, the walk the session led. The subscription's quota for `gpt-5.4-mini`
was 0 in every SKU in eastus2, so the session escalated, and vision overflows to `gpt-5-mini`
instead (the goal record's decision). Three soft-deleted accounts from other projects held
`gpt-5-mini`'s quota until the architect purged them.

The architect's az commands were not logged: they ran in the architect's own terminal, outside
the helpers, so none is quoted under "Commands as run". The deployments' SKUs and capacities are
read back from Azure after the review, to confirm the table below:

- **The deployments' SKUs and capacities, as Azure reports them** (06:10:38, `az cognitiveservices
  account deployment list`): `gpt-oss-120b` DataZoneStandard 50, `gpt-5-mini` GlobalStandard 10,
  `gpt-audio-mini` GlobalStandard 10, and `text-embedding-3-small` DataZoneStandard 10, each
  `Succeeded`, as the table below has them. The table output printed no model or version column,
  though the query named both, so the versions below stay the ones read at setup.

| Alias | Deployment | Version | SKU | Capacity |
| --- | --- | --- | --- | --- |
| agent | `gpt-oss-120b` | — | DataZoneStandard | 50 |
| vision | `gpt-5-mini` | 2025-08-07 | GlobalStandard | 10 |
| audio | `gpt-audio-mini` | 2025-12-15 | GlobalStandard | 10 |
| embedding | `text-embedding-3-small` | — | DataZoneStandard | 10 |

One direct request each, past the gateway (`az_curl`, 13:48:46–13:48:59):

- `gpt-oss-120b` answered "ready".
- `gpt-5-mini` answered "red" for a 1×1 red PNG.
- `gpt-audio-mini` refused a text-only chat: "This model requires that either input content or
  output modality contain audio". Sent go-ai's test fixture `integration/testdata/phrase.wav`, it
  answered "The access code is 7429." A text-only chat to the audio alias is a parity gap, recorded
  in slice 2, not worked around.
- `text-embedding-3-small` returned a vector of 768 dimensions, asked with `dimensions: 768`.

Azure requests so far: 5 of 300.

### The compose stack

The first compose deploy ran 13:49:04–13:49:19. It created Postgres's password (`secret
postgres-password: created`), validated the config, removed the `docker run` container of the
same name, built the Postgres image from `postgres:18.7-alpine`, and started the project: Postgres
healthy first, then agentgateway. agentgateway ran its migrations into Postgres, creating
`budget_usage`, `request_logs`, `request_log_payloads`, and
`_agentgateway_request_log_migrations`.

The stack follows `~/architecture`'s compose convention (go-web-service's `compose/README.md`):
one file per service group, Postgres from its own Dockerfile whose FROM line is the pin, a health
check, a named volume, and mise up, down, and reset tasks. Two exceptions, both in
[`gateway/agentgateway.yml`](../../gateway/agentgateway.yml)'s header:

- **agentgateway's image is pulled, not built.** Its pin stays in
  [`gateway/agentgateway/deploy.env`](../../gateway/agentgateway/deploy.env), where the deploy
  validates each config copy with that image before moving it into place, and where `mise run
  currency` compares it with agentgateway's latest release.
- **The config is bind-mounted read-only, not baked into an image.** The deploy renders it on the
  laptop with each key's hash and each secret substituted, so it can't be committed into a build
  context, and agentgateway reloads it in place when a new copy is moved in, so a config-only
  deploy, such as an overlay or a key's revocation, needs no restart. The directory is mounted,
  not the file, so the rename that moves a copy into place reaches the container. Fields under the
  config's top-level `config` section are read only at start, so `gateway/compose.sh` hashes that
  section into a label, and a change there recreates the container.

The read-only mount is a pending edit for the experiment's intake to weigh for the capstone's
stack.

Every earlier check passed on the stack (13:49:36–13:51:34):

| Check | Result |
| --- | --- |
| `/v1/models` on each `/<alias>/v1` | each lists its alias alone |
| a request to each alias | all four answer |
| no key | 401 |
| `/agent/v1/../metrics`, `/agent/v1/load` | 404, off the allow-list |
| go-ai's tier, all four roles | 20 passed, 0 failed, 1 skipped; the key is not in its log |
| infer's tier, all four roles | 13 passed, 0 failed, 1 skipped; the key is not in its log |
| the released infer, no model set | each alias's `infer models` lists that alias, and `infer chat` picks it |

The one skip in each tier is transcription, which no row serves.

### The reboot

The architect rebooted gb10-2 at 13:52:43. The stack came back unattended: the gateway answered 401
to a keyless request at 13:53:26, and the vision row answered 200 at 13:56:30. Postgres's named
volume kept its 178 `request_logs` rows (13:56:33).

## Slice 2 · overflow

Slice 2 ran 14:17–14:41, from the laptop through the step helpers, with every command under
"Commands as run". It deployed three configs: `4ed570c`, the overflow, at 14:17; `01e6c4d`,
escalation 1's answers, at 14:32; and `2ba52b8`, escalation 2's, at 14:40. Each deploy left the
agentgateway container running and reloaded its config in place. Each also recreated the Postgres
container, though its definition hadn't changed. `request_logs` kept its rows: 183 at 14:17.
Slice 3's deploys and the walkthrough's did the same.

**Why Postgres was recreated.** The deploy runs `compose up --build`, and BuildKit attached a new
provenance attestation manifest to each build: the deploy's output read `exporting attestation
manifest` with a new digest each time. The attestation records the build's own times. Every build
exported the same image manifest (`sha256:86224ba1…`) and config (`sha256:f04b3a0b…`), but
gb10-2's Docker 29.6.2 keeps images in the containerd image store
(`io.containerd.snapshotter.v1`), where an image's id is the digest of the index that lists the
manifest and its attestation. So the id changed on every build of an unchanged Dockerfile, and
compose recreates a container whose image id changed: the container's `com.docker.compose.image`
label is the last build's index, `sha256:5d0aafb2…`, which `docker image ls --tree` shows over
the `linux/arm64` manifest `86224ba12265`.

The first fix, after the review, set `provenance: false` and `sbom: false` under Postgres's
`build:` in [`gateway/postgres.yml`](../../gateway/postgres.yml). It claimed the cause fixed, and
it wasn't: the deploys after it (06:19:44, 06:29:49, and 06:29:57 on 2026-11-17) still exported
an attestation manifest, each with a new digest, and each recreated Postgres. Compose v5.2.0,
gb10-2's, drops both fields when it writes the bake definition it hands to `buildx bake`: its
`toBakeAttest` adds an `attest` entry for `true` or for options, and nothing for `false`, so
buildx applies its default, a provenance attestation. On gb10-2, `gateway/compose.sh build
--print postgres` prints a target with no `attest`, and `docker buildx history inspect` lists the
build's `https://slsa.dev/provenance/v1` attachment. The laptop's Compose 5.6.1 prints
`type=provenance,disabled=true` and `type=sbom,disabled=true` for the same fields, and its Docker
keeps the classic image store, where an image's id is its config's digest and an attestation
doesn't move it, so the laptop's check didn't test what gb10-2 runs.

Not the cause: Postgres's environment and `--build` itself. `postgres.env` is written on every
deploy with the same password, except after a rotation, and compose compares its content, not the
file. `gateway/compose.sh` exports the deploying user, the tailnet addresses, and the `config`
section's hash, none of which varies between runs, and only agentgateway's label reads the last.
agentgateway's `com.docker.compose.config-hash` equals `compose.sh config --hash agentgateway`.
Postgres's (`b00e555a…`) differs from `config --hash postgres` (`463891e4…`), which a read-only
check can't explain: compose computes it in `up` after the build. It held steady between the two
deploys below, since compose recreates a container whose config hash changed, and the second left
Postgres running.

The fix: [`gateway/compose.sh`](../../gateway/compose.sh) exports
`BUILDX_NO_DEFAULT_ATTESTATIONS=1`, which compose passes on to `buildx bake` with the rest of its
environment, so a build with no `attest` gets none. `provenance: false` and `sbom: false` stay,
for a Compose that honours them. A cached build of an unchanged Dockerfile then exports one
manifest and no index, so its id is that manifest's digest each time, and `up` leaves the
container alone; a changed Dockerfile still rebuilds it.

The fix holds. Two plain deploys ran back to back on gb10-2 after it, at 06:52:29 and 06:52:33 on
2026-11-17, through the helpers ("Commands as run"). Neither build exported an attestation: each
printed `exporting manifest sha256:86224ba1…` and `exporting config sha256:f04b3a0b…`, with no
`exporting attestation manifest` and no `exporting manifest list`. The first recreated Postgres
once more (`Container gateway-postgres-1 Recreate`), as expected, since its image id moved from the
manifest list to the manifest. The second printed `Container gateway-postgres-1 Running`, not
`Recreate`. The container's `Created` time, 2026-11-17T11:52:30.708Z, and its image,
`sha256:86224ba12265…`, were the same after both deploys; the session read them outside the
helpers, so that reading isn't in the command log.

### Rows up (behaviors 5, 6, 8)

With `4ed570c` deployed and every row up (14:17:35–14:19:25):

| Check | Result |
| --- | --- |
| `/v1/models` on each `/<alias>/v1` | answered by the gateway, each listing its alias alone |
| a request to each alias | 200, with no `x-gateway-overflow` header |
| a streamed chat without `include_usage` | ends with a usage chunk: the typed `completions` route adds it |
| embeddings | 768 dimensions |
| no key; `/agent/v1/load` | 401; 404, off the allow-list |
| go-ai's tier, all four roles | 20 passed, 0 failed, 1 skipped |
| infer's tier, all four roles | 13 passed, 0 failed, 1 skipped |

The one skip in each tier is transcription, which no row serves. Three questions went to the
architect here, before benchmark C ("Escalation 1", below). Their answers were deployed as
`01e6c4d` at 14:32, and agent and vision answered a request each on their rows at 14:32:43.

### A row down (behaviors 7, 8)

The `rows-down` probe overlay
([`probes/rows-down.yaml`](../../gateway/agentgateway/probes/rows-down.yaml)) points every row's
provider at port 8009 on its own host, where nothing listens (checked on all three hosts at
14:17:24). The rows keep running. It was deployed at 14:32:54, and each alias was asked once:

- **agent:** 200 from `gpt-oss-120b`, with `x-gateway-overflow: azure`.
- **vision:** first a 400. `gpt-5-mini` refuses `max_tokens`: "Unsupported parameter: 'max_tokens'
  is not supported with this model. Use 'max_completion_tokens' instead." Sent again with
  `max_completion_tokens`, it answered 200, "pink", for a red 1×1 PNG. The vision row answers the
  same PNG "Red".
- **audio, go-ai's fixture clip:** 503 twice, then 200, "The access code is 7429." The body is
  258,652 bytes, past the 64 KiB the gateway buffers for a retry, so it isn't retried. Each
  attempt fails its connection to the row ("connection refused"), and the row is evicted only
  after 2 failures in a row. So the first two requests got the row's 503, and the third reached
  Azure.
- **audio, text only:** 400. `gpt-audio-mini` requires audio: "This model requires that either
  input content or output modality contain audio."
- **embedding:** 200 from `text-embedding-3-small`, 768 dimensions.

Every reply Azure answered carried the overflow header, and the access log named the Azure
provider on its line (`gen_ai.provider.name=azure`, `overflow="azure"`). No request went to
another alias's row or deployment.

**Back to the rows.** The overlay was removed by a plain deploy at 14:36:52. At the first check,
14:37:03, all four aliases answered from their rows, and `azure_count` read 0 from 14:36:52. A
config reload builds the backends again, so it clears the eviction state: no row waited out an
eviction.

### The tiers on Azure (behavior 10)

go-ai's and infer's tiers ran through the `rows-down` overlay with their base URLs and keys
unchanged (14:33:31–14:36:36). Transcription is skipped in both, as in every run.

**go-ai: 10 passed, 10 failed, 1 skipped.** The failures:

| Test | Cause |
| --- | --- |
| `TestFunctionCallRoundTrip`, `TestStreamFunctionCall`, `TestReasoningRoundTrip`, `TestStreamReasoningRoundTrip` (all three formats each), `TestToolChoice/allowed_tools_required` | `gpt-oss-120b` refuses `tool_choice: required`: 400, "Request included unsupported tool use. tool_choice 'required' is not supported for the model." (`UnsupportedToolUse`) |
| `TestToolChoice/named_function` | `gpt-oss-120b` ignores a named function and answers in text: 0 function calls |
| `TestChatUnknownModelIsAPIError` (all three formats) | an unknown model name succeeds, since the Azure provider sets the deployment as the model |
| `TestStreamText/messages` | a translated Messages stream reports 0 input tokens |
| `TestChatIncompleteAtMaxOutputTokens/responses` | a Responses reply cut off at its limit gives the reason `max_tokens`, where go-ai expects `max_output_tokens` |
| `TestAudioInResponsesRefused`, `TestTranscribeChat` | a large audio body gets 503 ("connection refused") while the row isn't yet evicted, as above. Rerun after the review with the row evicted first: `TestTranscribeChat` passes on Azure, and `TestAudioInResponsesRefused` fails, refused by the gateway itself (below) |

Responses itself passed on agent (`TestChat/responses`). The brief expected it to fail on agent,
since `gpt-oss-120b` serves Chat Completions only. The gateway translates a Responses request into
Chat Completions for that provider, as it does Messages.

**The audio rerun, after the review** (06:29:48–06:29:57). With `rows-down` deployed,
`audio_rerun p5-audio` warmed the audio row's eviction with two text-only chats before each of
go-ai's two audio tests, then ran the test alone. Each warm-up reached Azure, marked as overflow,
and got Azure's 400 for a text-only chat, the gap recorded in slice 1; the first was Azure's on its
third send, after the row's two refused connections evicted it. Then:

- `TestTranscribeChat` passed on Azure: 1 passed, 0 failed.
- `TestAudioInResponsesRefused` failed: 0 passed, 1 failed. The test sends audio in a Responses
  request and wants the endpoint's own 400. The gateway answered 400 itself, in 4 ms, before
  anything reached Azure: "failed to process LLM request: failed to parse Responses request: data
  did not match any variant of untagged enum InputParam" (`reason=InvalidRequest` on its access
  log line). agentgateway v1.7.0's typed Responses parser has no variant for an audio input part,
  so on overflow, audio in a Responses request is refused by the gateway, with the gateway's
  message, not Azure's: a parity finding for audio (behavior 12), watched with #4185's typed
  parsing ([`docs/watch.md`](../watch.md), "agentgateway always-passthrough for `llm` models").

With the rows up the same test passes, the row's vLLM refusing with its own 400. The config
explains the difference. The route's `ai.routes` names `/v1/responses` as `responses` on both
groups alike, so the row's request is classified as typed Responses too; what differs is the
provider's `formats`. The row's provider lists `responses` (`&row-formats`), so the request passes
through to the row unchanged. The Azure provider lists only `completions`, so the gateway
translates a Responses request into Chat Completions for it, as it does for agent above, and the
translation parses the whole input into its typed form, where the audio part fails. That the
pass-through doesn't parse the input the same way is a reading of the config and the error, not
of the source.

**infer: 9 passed, 4 failed, 1 skipped.** Beside the gaps above, it adds:

- go-ai's stream parsers reject two of Azure's streams. The Chat Completions parser rejects
  Azure's chat stream, whose first chunk has an empty reply id ("chunk of reply
  \"chatcmpl-…\" in the stream of reply \"\""). The Responses parser rejects how Azure adds a
  reasoning item ("reasoning item \"rs_…\" is added with content"). They fail
  `TestChatReasoningEffort`, `TestChatImage`, and part of `TestChatIncompleteAtMaxTokens`. Each is
  to be found at its root and fixed in a v1.ai.client hotfix task, with no gateway workaround (the
  goal record's decision).
- `gpt-5-mini` refuses reasoning effort `none`: "Unsupported value: 'none' is not supported with
  the 'gpt-5-mini-2025-08-07' model. Supported values are: 'minimal', 'low', 'medium', and
  'high'."
- `gpt-oss-120b` gives no reasoning item at `--reasoning low` through Messages: "reasoning items =
  0 at --reasoning low".
- A Messages stream at `--max-tokens 16` on agent "did not exit within 15s"
  (`TestChatIncompleteAtMaxTokens/messages`). It hasn't recurred in three reruns since, and its
  cause is open ("Addendum 2026-11-19 · the 16-token Messages stall", below).
- `TestTranscribeChat` gets the large-audio 503, as in go-ai's tier.

The released infer CLI, setting no model, picked each alias on Azure: each base URL's `infer
models` listed its alias alone, and `infer chat` on agent answered.

Azure's count after the tiers was 76 since 14:32:54, so 81 in the task with slice 1's 5. That
includes 13 400s on agent and 3 on vision, from the refusals above.

### Benchmark C-agent (behavior 9)

C-agent ran once, resized (escalation 1), with the rows up and `01e6c4d` deployed: `cell bc-agent
overflow-agent cap agent`, 28 concurrent single-turn chats of 512 tokens in and 128 out, 60 s,
from 14:37:10 to 14:38:31. Read with `summarize` and `overflow_read`:

| Reading | Value |
| --- | --- |
| GuideLLM's replies | 2xx ×60, 400 ×99, 429 ×2845, 3 with no status (the row's "engine is currently busy" inside a stream); 24 incomplete at the end |
| answered by the row | 89 (200 ×87, and 2 with no status) |
| answered by Azure | 2,944: 429 ×2845, 400 ×99, no 2xx |
| 503 from the row to the client | 0 |
| refused requests retried | 18, with 20 retries; all 18 reached Azure |
| eviction windows | about 28 a minute: an estimate from the log's order, assuming each window lasted 5 s, where each eviction in fact lasts longer than the one before (Method) |
| first refusal | 0.7 s after the benchmark's start |
| the row | running median 12, max 12; waiting median 0, max 12 |
| gateway CPU, median / max | 4.54% / 5.91% of one core; memory 80.5 / 83.1 MiB |

So a refused request does reach Azure: the 20 ms backoff lets the eviction land before the retry.
But under saturation the row's 503 with eviction sends nearly the whole load to Azure. Each
eviction opens a window in which every new request goes to the Azure group: 5 s the first time,
and 5 s times the evictions so far each time after, with no cap, until a reload clears the
count. Azure's `gpt-oss-120b` throttled within seconds, and its 429s didn't evict it under the health policy
then deployed. So it stayed in rotation and answered the alias's load with 429s. Every 429 carried
`Retry-After: 1`.

**The 99 400s.** The access log keeps no error body, and GuideLLM 0.8.1 keeps only the status.
The probable cause is the request itself. Every non-429 reply from Azure in the run was a 400, with
no 2xx, while a plain chat to the same deployment answered 200 minutes before. GuideLLM 0.8.1 adds
two vLLM fields to every fixed-length chat request, `ignore_eos: true` and `stop: null`, beside
`max_completion_tokens` (`guidellm/backends/openai/request_handlers.py`, 1183–1185). The 400s
point at Azure refusing one of them. This is not confirmed, since no reply body was kept.

The run breached the task's stop rule (Azure's 429s, and a count past the cap). The session
stopped and escalated (escalation 2, below). C-vision did not run.

### Per alias: the cloud model and its parity (behavior 12)

| Alias | Cloud model | SKU, processing scope | Parity gaps seen |
| --- | --- | --- | --- |
| agent | `gpt-oss-120b` | DataZoneStandard: within the data zone | refuses `tool_choice: required` and ignores a named function; an unknown model name succeeds; Responses is translated to Chat Completions, and a reply cut off at its limit reports `max_tokens`; a translated Messages stream reports 0 input tokens, and one at a 16-token limit didn't end within 15 s on 2026-11-16, not seen since ("Addendum 2026-11-19 · the 16-token Messages stall"); no reasoning item at low effort through Messages; Azure's chat stream opens with an empty reply id and Responses adds its reasoning item in a form go-ai rejects (go-ai's to fix) |
| vision | `gpt-5-mini` 2025-08-07 | GlobalStandard: processed globally | refuses `max_tokens` (wants `max_completion_tokens`) and reasoning effort `none`; an unknown model name succeeds; the stream gaps above; called a red PNG "pink" where the row said "Red" |
| audio | `gpt-audio-mini` 2025-12-15 | GlobalStandard: processed globally | refuses a text-only chat; serves Chat Completions only; audio in a Responses request is refused by the gateway itself on overflow (400, "failed to parse Responses request"), where the row refuses it with its own message (the audio rerun); an audio body over 64 KiB isn't retried, so it gets the row's 503 until 2 failures evict the row, each after about 11 s when the Framework is powered down (walkthrough) |
| embedding | `text-embedding-3-small` | DataZoneStandard: within the data zone | another vector space at the same 768 dimensions; every reply is marked as overflow; with the Framework powered down, the first overflowed request took about 23 s (walkthrough) |

Which workloads may leave the self-hosted machines is the architect's call in `answer`. These
gaps are its inputs: agent and embedding stay within the data zone, while vision and audio are
processed globally. Only synthetic and test-fixture content was sent to Azure: the helpers'
prompts, a 1×1 PNG, go-ai's `phrase.wav` fixture, and GuideLLM's synthetic text. The walkthrough
(slice 4) added the audio and embedding rows' times through a host power-down; the table is
complete for the task.

### The Azure count

Counted from the access log after each step that can overflow, through the whole task:

| Step | Azure-answered | Toward the cap |
| --- | --- | --- |
| slice 1, direct | 5 | 5 |
| rows-down probes and the tiers, 14:32:54–14:36:38 | 76 (agent 50, vision 20, audio 2, embedding 4) | 76 |
| benchmark C-agent | 2,944 (429 ×2845, 400 ×99) | 99 |
| slice 3 | 0 | 0 |
| the walkthrough, 2026-11-17, steps 3 and 6 | 3 (agent 1, audio 1, embedding 1; all 200) | 3 |
| total before the audio rerun | 3,028 | 183 of 300 |
| the audio rerun, after the review, 06:29:52–06:29:56 | 6 (audio: 400 ×5, 200 ×1) | 6 |
| the post-upgrade smoke check, 06:40:00–06:44:24 | 0 | 0 |
| total | 3,034 | 189 of 300 |

The cap counts Azure's 2xx and its 4xx other than 429, since Azure refuses a 429 without
processing it (escalation 2). Azure's 2,845 429s are reported apart. Of the audio rerun's five
400s, four are Azure's refusals of the text-only warm-ups; the fifth is the gateway's own refusal
of `TestAudioInResponsesRefused`'s request, logged against the Azure provider and marked as
overflow though it never reached Azure. `azure_count` counts it, so the total overstates Azure's
by one, on the cap's safe side.

### Escalation 1 (2026-11-16)

Slice 2's rows-up checks passed; three questions went to the architect before benchmark C, and
were answered:

- **Retry backoff: 20 ms.** An eviction reaches the load balancer through a spawned task
  (`types/loadbalancer.rs`, `finish_request`) [src], so it lands asynchronously, and a retry sent
  with no backoff reaches the row again: on the laptop mock, the request whose two 503s evicted the
  row got its third 503 from the row. With 20 ms the same request went to Azure on its third
  attempt. The route retry (`&retry-503`) now sets `backoff: 20ms`. Benchmark C-agent showed it
live: all 18 refused requests it retried reached Azure.
- **Azure provider health: the rows' policy.** Each `<alias>-azure` provider now carries
  `&row-health`: two 503s or failed connections in a row evict it, for 5 s the first time. It had
  none, so agentgateway's default for several groups held: one 5xx or failed connection evicted it
  for 3 s.
  A 429 doesn't evict it; escalation 2, below, adds it.
- **Benchmark C sized to Azure's capacity.** gpt-5-mini has 10 units, about 10,000 tokens a minute,
  and gpt-oss-120b 50 units, about 50,000 tokens a minute. The briefed loads, C-agent's sessions of
  an 8,192-token first turn and C-vision's 1440p images, would pass them within seconds of an
  overflow, and a 1440p body is past the 64 KiB the gateway retries, so a refused request could
  never reach Azure. C-agent now sends single-turn prompts of 512 tokens, 128 out, at 28
  concurrent for 60 s; C-vision a synthetic 720p JPEG (base64 21 to 46 KB in GuideLLM 0.8.1) beside
  200 text tokens, 100 out, at 36 concurrent for 60 s, so the row fills on concurrency and each
  vision body is retried. Each cell stops early if Azure answers 429: no GuideLLM 0.8.1 constraint
  tells a 429 from the row's 503s (`max_errors` and the error-rate constraints count every errored
  request), so the session watches `azure_count` and the access log and interrupts the run by hand.

The implementer's earlier checks "on the mock" used a throwaway Python mock upstream in the
session's scratchpad, never committed: an exception to the experiment's no-authored-Python rule,
which the architect was told about.

### Escalation 2 (2026-11-16)

Benchmark C-agent breached the stop rule, and the architect decided:

- **C-vision is dropped, and C-agent is recorded as run.** Under saturation, a row's 503 with
  eviction sends nearly the whole load to Azure. C-vision would show the same at gpt-5-mini's 10
  units.
- **Azure groups also evict on 429.** Each `<alias>-azure` provider now carries `&azure-health`: a
  503, a 429, or a failed connection, 2 in a row, evicts it, for 5 s the first time, so a
  throttling Azure leaves rotation. It was deployed as `2ba52b8` at 14:40:43 and passes
  `--validate-only`. It is not shown live: a live 429 needs Azure to throttle (about 60 counted requests on one deployment), and
  agentgateway logs no eviction.
- **The cap counts 2xx and non-429 4xx.** The count is 180 of 300 after C, with Azure's 429s
  reported apart. `azure_count` prints both.

## Slice 3 · keys and limits

Slice 3 ran 16:15–16:40, from the laptop through the step helpers, with every command under
"Commands as run". It deployed the config at `a69766b`:

- a fourth key, bulk, beside architect, bench, and go-ai;
- vLLM's `priority` set from the key's name on the agent and vision rows' providers alone, 0 for
  an interactive key and 10 for bulk (`&row-priority`), so no request to Azure carries it;
- a request-rate bucket per key on each route (`&key-rates`): bulk 600 a minute, the others
  1,200;
- a token budget per key, kept in Postgres over each clock hour: bulk Blocks at 1,000,000, the
  others Audit at 5,000,000 (the window: "bulk's budget Block (behavior 15)", below);
- embedding's global 34 requests a second.

The config's comments give each field and its source.

### The path and the deploy

The laptop's path to every host changed. At 16:15:59 `tailscale ping` answered on a direct path,
1–2 ms, where slices 1 and 2 had only the DERP relay, 51–52 ms: the architect was back on the
LAN. Slice 3's cells compare only with each other, never with the earlier slices' or tasks'.

The deploy ran at 16:15:59. It created bulk's key (`key bulk: created`), kept the other three,
validated the config, and reloaded it in place. As in slice 2, it also recreated the Postgres
container, and the request log kept its rows. `azure_count` read 0 from 16:15:59.

### The request log (behavior 16)

`request_log` at 16:16:14 read the newest rows of `request_logs` in Postgres. The newest was
slice 3's stream on agent:

| Completed (UTC) | Status | Key | UI user | Provider | Model | Input | Output | Total | Duration ms | Payload |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 21:16:10 | 200 | go-ai | go-ai | custom | agent | 75 | 53 | 128 | 1528 | f |

The four rows under it were C-agent's, from 19:38:23 UTC. Three of them have no token counts:
requests probably cut off when the benchmark ended. `payload_rows` was 0: with `llm: metadata`
no prompt or completion is kept. The UI's Logs and Analytics pages, which read this table, are
the walkthrough's step 5.

### A stream charged to its key (behavior 15)

`budget_status go-ai` read `used 0 of 5000000 Tokens, exceeded false, Audit; window ends
17:00:00` at 16:16:08. Then go-ai sent a streamed chat to agent with no `include_usage`. Its
stream carried one usage chunk, which the typed `completions` route adds. At 16:16:11 the
budget read `used 128`, the stream's total tokens, charged to go-ai.

### bulk's bucket (behavior 14)

The `bulk-rate-low` overlay
([`probes/bulk-rate-low.yaml`](../../gateway/agentgateway/probes/bulk-rate-low.yaml)) lowers
bulk's bucket to 2 requests a minute. It was deployed at 16:16:22. At 16:16:26, on vision:

| Request | Key | Status | Retry-After |
| --- | --- | --- | --- |
| 1 | bulk | 200 | — |
| 2 | bulk | 200 | — |
| 3 | bulk | 429 | 59 |
| 4 | go-ai | 200 | — |

So bulk was refused by its own bucket while go-ai kept answering on the same alias. The 429 is
the gateway's own: the row never saw the request, and nothing went to Azure.

### bulk's budget Block (behavior 15)

The `bulk-budget-low` overlay
([`probes/bulk-budget-low.yaml`](../../gateway/agentgateway/probes/bulk-budget-low.yaml)) lowers
bulk's budget to 1 token, keeping its count. It was deployed at 16:16:27, with bulk already
charged 44 tokens in the hour by the bucket probe's two answered requests. At 16:16:30, on
vision:

- bulk, twice: 429, `retry-after: 2609`, the seconds left in the clock hour, with the body
  `{"error":{"message":"budget exceeded","type":"rate_limit_error","code":"budget_exceeded"}}`;
- go-ai: 200.

`budget_status bulk` read `used 44 of 1 Tokens, exceeded true, Block; window ends 17:00:00` at
16:16:31. The session then ran `docker restart agentgateway` on gb10-2, and at 16:16:36 the
budget read the same, `used 44`: the count was written to `budget_usage` and read back at start.
A plain deploy at 16:16:36 removed the overlay.

**The window is a fixed clock hour.** Behavior 15 asked for budgets over a rolling window.
agentgateway v1.7.0's `rolling: 1h` is a fixed window aligned to the Unix epoch, so each UTC clock
hour: the count starts again at each hour, a key can spend up to twice its budget across an hour's
boundary, and a Block's `Retry-After` is the time to the next hour, as the 2609 above was. v1.7.0
has no sliding window. The architect's decision at review (2026-11-17) amends behavior 15 to the
fixed clock hour, records it here, and makes a sliding window a want for `answer`'s gateway
document, tracked in [`docs/watch.md`](../watch.md).

### Embedding's limit (behavior 17)

At 16:16:47, 40 embedding requests at once with the bench key: 34 answered 200, and 6 got 429
with `retry-after: 1`. The bucket admits a burst of 34, then 34 a second.

### Benchmark A: embedding limited, audio beside it (evidence 5)

The anchors ran first, O-audio alone, direct and then through the gateway with the bench key.
Then `a-embed`, C-embed at 160 in flight for 90 s through the gateway with the bench key, from
16:17:59. Inside it, from 16:18:19, `a-audio-in` was O-audio through the gateway with the go-ai
key, in a second terminal.

| Cell | Path, key | Requests | TTFT ms median | ITL ms median | RTFx median (min; at 5 or more) | Gateway CPU median |
| --- | --- | --- | --- | --- | --- | --- |
| `a-audio-d` | direct | 64 of 64 | 225.9 | 51.94 | 5.28 (3.05; 39 of 64) | — |
| `a-audio-g` | gateway, bench | 64 of 64 | 153.23 | 45.69 | 6.46 (3.48; 54 of 64) | 1.29% |
| `a-audio-in` | gateway, go-ai, inside `a-embed` | 64 of 64 | 168.49 | 54.14 | 5.38 (2.99; 43 of 64) | 8.43% |

`a-embed`:

- GuideLLM: 2xx ×3094, 429 ×33813; request latency median 98.06 ms.
- The gateway's log: 36,723 requests, 200 ×3060 (34.0 a second over 90 s) and 429 ×33663, every
  429 with `Retry-After: 1`.
- The embedding row: running and waiting 0 in all 18 samples.
- The gateway: CPU median 7.78%, max 9.50% of one core; memory median 50.9 MiB.

Audio's RTFx median held at 5.38 beside the limited embedding load, so the floor (median ≥5)
meets, and a 34/1s bucket's burst needs no paced bucket in its place. The gateway anchor ran
faster than the direct one, so these single runs bound audio's figures; they don't measure the
gateway's overhead, which the agentgateway and routing tasks did.

**The wait-loop slip.** After starting the two runs, the session waited for both to end with a
`pgrep` loop. `pgrep -f` matched the loop's own command line, so the wait never saw the runs
end: both had ended by 16:19:59, and the session's next step, `rtfx`, ran at 16:28:07. The wait
wasn't logged, since it ran outside the helpers. The runs weren't affected: each was read from
its own files.

### Benchmark B: chat beside bulk vision (evidence 6)

The anchors ran first, O-agent alone, direct and through the gateway with the bench key. Then
`b-bulk`, C-vision at 20 concurrent for 150 s with the bulk key, from 16:32:22. Inside it, from
16:32:42, `b-agent-in` was O-agent with the go-ai key.

| Cell | Path, key | Requests | TTFT ms median (p95) | ITL ms median (p95) | Latency ms median | Gateway CPU median |
| --- | --- | --- | --- | --- | --- | --- |
| `b-agent-d` | agent, direct | 15 ok, 4 incomplete of 19 | 562.69 (8091.91) | 47.63 (52.52) | 25089.2 | — |
| `b-agent-g` | agent, gateway, bench | 15 ok, 4 incomplete of 19 | 558.17 (8080.75) | 48.54 (51.98) | 25817.76 | 0.68% |
| `b-agent-in` | agent, gateway, go-ai, inside `b-bulk` | 16 ok, 4 incomplete of 20 | 595.84 (8103.13) | 47.05 (54.81) | 24654.71 | 3.46% |
| `b-bulk` | vision, gateway, bulk | 249 ok, 16 incomplete of 265 | 3248.69 (8198.94) | 72.61 (83.05) | 10413.24 | 2.60% |

Chat holds its floor: agent's ITL median beside bulk vision was 47.05 ms, against ≤100 ms, and
within 1.5 ms of both anchors (47.63 direct, 48.54 through the gateway). Its TTFT median was
33 ms above the direct anchor's. The gateway's CPU rose from 0.68% for agent alone to 3.46% with both runs through it. With one direct
run there is no direct spread, so each change is read against the two anchors. Each O-agent
run's 4 incomplete requests are the sessions still running at its 110 s end.

**What B tests.** Vision and agent are rows on different hosts, so B shows that the gateway adds
no interference across purposes under bulk load. It doesn't test priority on a shared row;
benchmark D does.

### Benchmark D: priority on vision (evidence 6)

`d-bulk` ran C-vision at 20 concurrent for 120 s with the bulk key, from 16:35:14. Inside it,
from 16:35:29, `d-int` ran O-vision at 1 concurrent with the go-ai key. Then the `priority-flat`
overlay ([`probes/priority-flat.yaml`](../../gateway/agentgateway/probes/priority-flat.yaml)),
which sends every key at bulk's priority, was deployed at 16:37:35, and the same pair ran again
as the control: `d-bulk-flat` from 16:37:39, `d-int-flat` from 16:37:54. A plain deploy at
16:39:53 removed the overlay.

| Cell | Key, priority | Requests | TTFT ms median (p95) | ITL ms median | Latency ms median (p95) |
| --- | --- | --- | --- | --- | --- |
| `d-bulk` | bulk, 10 | 185 ok, 20 incomplete of 205 | 3542.71 (9305.12) | 70.28 | 10647.92 (16252.79) |
| `d-int` | go-ai, 0 | 7 ok, 1 incomplete of 8 | 2613.53 (6752.29) | 75.34 | 10466.56 (14782.4) |
| `d-bulk-flat` | bulk, 10 | 185 ok, 20 incomplete of 205 | 3547.73 (9307.47) | 70.32 | 10671.54 (16247.24) |
| `d-int-flat` | go-ai, 10 (flat) | 7 ok, 1 incomplete of 8 | 3545.27 (9321.47) | 70.02 | 11871.36 (16254.58) |

The gateway's CPU median was 2.3–2.8% in each run.

Priority cut interactive vision's median latency by 1.40 s, from 11.87 s to 10.47 s, and its
TTFT median by 0.93 s, from 3.55 s to 2.61 s. Bulk's own figures didn't move. With priority, the
interactive median missed the ≤10 s mark by 0.47 s, on 7 requests.

**Why priority stops there.** vLLM's priority orders only the waiting queue. It takes the
interactive request ahead of bulk's waiting requests, which is the TTFT cut. Once running, the
request shares the batch with bulk's 20 streams, and decodes at their pace: about 75 ms a token
for 100 tokens, about 7.5 s. TTFT plus that decoding is the ~10.5 s median.

This is a finding about what priority buys on a saturated row: a place at the head of the queue,
not a share of the batch. The brief makes 10 s what D informs, not a stop rule. Holding
interactive latency under bulk load needs something beyond priority, such as a cap on bulk's
concurrency. That is for `answer`'s gateway document.

### The Azure count

Azure answered no request in slice 3. `azure_count` read 0 after the deploy and after each
benchmark, and the gateway's log over all of 16:15:59–16:40:00 holds no line marked
`overflow="azure"` and none sent to the Azure provider. The count stays 180 of 300.

## Slice 4 · walkthrough

The architect runs the walkthrough from the repository root on the laptop, one step at a time.
Every command goes through the helpers, so each lands in
`.state/priority/commands-<date>.log`. Each step's expected result comes from slices 1–3. Steps 3
and 6 send requests to Azure: about 2 in step 3, and at most about 55 in step 6. That keeps the
count, 180 before the walk, under 300. An Azure 429, or a row still overflowing after step 6's loop, stops
the walk for the session to escalate.

1. **Source the helpers.** This starts the day's command log and marks the walk's start, for
   `azure_count`.

   ```sh
   source scripts/clients-lib.sh
   W0=$(date -Iseconds)
   ```

   Expected: one line, `+ <time> laptop: source scripts/clients-lib.sh`.

2. **An alias's `/models`, answered by the gateway.** The gateway answers each alias's
   `/v1/models` itself, whether the row is up or not, so a client that takes the one listed
   model gets the alias during an overflow too.

   ```sh
   gw_curl architect -sS "$(gw_base audio)/models"
   ```

   Expected: `{"object":"list","data":[{"id":"audio","object":"model","owned_by":"gateway"}]}`.
   `owned_by` is `gateway`: a row's answer would read `vllm`.

3. **A row-down overflow.** The `rows-down` overlay points every row's provider at a closed port
   on its own host. agent is answered by its Azure deployment under the alias, and a deploy
   without the overlay returns it to its row. This costs about 2 Azure requests.

   ```sh
   logged "mise run agentgateway-deploy rows-down"
   gw_curl architect -sS -D - -o .state/priority/walk-down-agent.json -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Reply with the word ready."}],"max_tokens":64}' "$(gw_base agent)/chat/completions" | grep -iE '^(HTTP|x-gateway-overflow)'
   logged "jq -c '{model, content: .choices[0].message.content}' .state/priority/walk-down-agent.json"
   logged "mise run agentgateway-deploy"
   gw_curl architect -sS -D - -o .state/priority/walk-up-agent.json -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Reply with the word ready."}],"max_tokens":256}' "$(gw_base agent)/chat/completions" | grep -iE '^(HTTP|x-gateway-overflow)'
   logged "jq -c '{model, content: .choices[0].message.content}' .state/priority/walk-up-agent.json"
   azure_count "$W0"
   ```

   Expected:
   - the first deploy prints `overlay rows-down: applied` and `Configuration is valid!`;
   - `HTTP/1.1 200 OK` and `x-gateway-overflow: azure`, then `{"model":"gpt-oss-120b","content":"ready"}`;
   - the second deploy applies no overlay;
   - `HTTP/1.1 200 OK` with no overflow header, then `{"model":"agent",...}`: the agent row
     again. A reload clears the eviction, so the row answers at once;
   - `azure_count`: agent 1 or 2, every one 200, and no 429.

4. **A budget Block.** The `bulk-budget-low` overlay lowers bulk's budget to 1 token and keeps
   its count. The request that crosses a budget is answered, and the next one is refused. So
   when bulk has used nothing in the current hour, its first request gets 200 and is charged,
   and the second gets the 429.

   ```sh
   logged "mise run agentgateway-deploy bulk-budget-low"
   gw_curl bulk -sS -D - -H 'Content-Type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8}' "$(gw_base vision)/chat/completions" | grep -iE '^(HTTP|retry-after)|^\{"error'
   gw_curl bulk -sS -D - -H 'Content-Type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8}' "$(gw_base vision)/chat/completions" | grep -iE '^(HTTP|retry-after)|^\{"error'
   gw_curl go-ai -sS -D - -o /dev/null -H 'Content-Type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8}' "$(gw_base vision)/chat/completions" | grep -iE '^HTTP'
   budget_status bulk
   logged "mise run agentgateway-deploy"
   budget_status bulk
   ```

   Expected:
   - the deploy prints `overlay bulk-budget-low: applied`;
   - bulk's first request: `HTTP/1.1 200 OK` when bulk has used nothing in the current hour,
     otherwise as the second;
   - bulk's second: `HTTP/1.1 429 Too Many Requests`, a `retry-after` of the seconds to the next
     hour, and `{"error":{"message":"budget exceeded","type":"rate_limit_error","code":"budget_exceeded"}}`;
   - go-ai: `HTTP/1.1 200 OK`;
   - `budget_status bulk`: `used <n> of 1 Tokens, exceeded true, Block; window ends <the next
     hour>`;
   - after the plain deploy: `used <n> of 1000000 Tokens, exceeded false, Block`, the same count.

   Nothing goes to Azure: the 429 is the gateway's own.

5. **The request log in the UI.** The UI is published on gb10-2's loopback only and reached
   through an SSH tunnel. Its Logs and Analytics pages read the request log in Postgres. In a
   second terminal, from the repository root:

   ```sh
   source scripts/clients-lib.sh
   logged "mise run gateway:ui"
   ```

   Then open the two pages by URL in a browser, http://localhost:3001/ui/llm/logs and
   http://localhost:3001/ui/llm/analytics. The UI's sidebar doesn't link them, since the config
   has no `llm` section ("Results", step 5). In the first terminal, the same rows as text:

   ```sh
   request_log 8
   ```

   Expected:
   - the tunnel holds its terminal and prints nothing;
   - Logs lists the walk's requests, newest first. Each row has its key's name as the user, the
     provider (`azure` for step 3's overflow, `custom` for a row), the model, tokens, and
     duration, and no prompt or completion;
   - Analytics totals requests and tokens per key and model;
   - `request_log 8` shows the same rows, every `has_payload` `f`, and `payload_rows` 0.

   Record no address or Azure host the pages show. Then Ctrl-C in the second terminal to close
   the tunnel.

6. **LAST: the Framework reboot (root).** Behavior 11: while the Framework is rebooted and
   LUKS-locked, audio and embedding are answered by Azure. After the unlock, the session times
   each row's `/health` and the first request each row answers again.

   1. The session checks that no overlay is live, and marks the step's start:

      ```sh
      logged "ssh gb10-2 head -1 '~/gateway/agentgateway/config.yaml'"
      W6=$(date -Iseconds)
      ```

      Expected: `# overlays: none`.

   2. **The architect, at the Framework:** apply its one pending update, then reboot:

      ```sh
      omarchy update
      sudo reboot
      ```

      The session logs it when the architect says it was issued, as slice 1 logged gb10-2's
      reboot:

      ```sh
      _clients_log "framework (architect)" "omarchy update, then sudo reboot (issued <HH:MM:SS>)"
      ```

   3. **While it is down and locked,** the session sends one request to each alias. Audio sends
      go-ai's `phrase.wav` fixture with `max_completion_tokens`, the model renamed to the alias.
      Embedding sends one small input.

      ```sh
      gw_curl architect -sS -D - -o .state/priority/walk-fw-audio.json -H 'Content-Type: application/json' -d @<(jq -c '.model = "audio"' .state/priority/assets/audio-probe.json) "$(gw_base audio)/chat/completions" | grep -iE '^(HTTP|x-gateway-overflow)'
      gw_curl architect -sS -D - -o .state/priority/walk-fw-embed.json -H 'Content-Type: application/json' -d '{"model":"embedding","input":"ready"}' "$(gw_base embedding)/embeddings" | grep -iE '^(HTTP|x-gateway-overflow)'
      logged "jq -c '{model, content: .choices[0].message.content}' .state/priority/walk-fw-audio.json; jq -c '{model, dims: (.data[0].embedding | length)}' .state/priority/walk-fw-embed.json"
      azure_count "$W6"
      ```

      Expected:
      - Embedding: `HTTP/1.1 200 OK`, `x-gateway-overflow: azure`, and
        `{"model":"text-embedding-3-small","dims":768}`.
      - Audio: `HTTP/1.1 200 OK`, `x-gateway-overflow: azure`, and "The access code is 7429."
      - The first large audio request may get 503 before the row is evicted. Its body is past the
        64 KiB the gateway retries, and the row is evicted only after 2 failed connections in a
        row. Send it again, up to twice, until the header shows. A connection to a host that is
        down may take seconds to fail.
      - The log shows the audio body as `-d @/dev/fd/63`, as in slice 2.
      - `azure_count`: audio and embedding, 1 each, all 200, and no 429.

   4. **The poll.** The session starts it before the unlock and leaves it running. It prints
      each row's first `/health` 200 with its time:

      ```sh
      logged 'for p in 8001 8002; do ( until [[ $(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://framework:$p/health) == 200 ]]; do sleep 1; done; echo "framework:$p /health 200 at $(date -Is)" ) & done; wait'
      ```

   5. **The architect unlocks LUKS at the Framework's console.** The session logs it the moment
      the architect says so:

      ```sh
      _clients_log "framework (architect)" "LUKS unlocked at the console (<HH:MM:SS>)"
      ```

      Expected, from the poll: `framework:8001 /health 200 at <time>` and `framework:8002 /health
      200 at <time>`, each some time after the unlock, once Docker and the row's vLLM have
      started.

   6. **The first request each row answers again.** Once both `/health` lines are in, a
      `gw_curl` per alias every 5 s, at most 24 times. Each alias stops at its first 200 with no
      overflow header:

      ```sh
      left="embedding audio"
      for i in $(seq 24); do
        for a in $left; do
          if [[ $a == audio ]]; then
            h=$(gw_curl architect -sS -D - -o /dev/null -H 'Content-Type: application/json' -d @<(jq -c '.model = "audio"' .state/priority/assets/audio-probe.json) "$(gw_base audio)/chat/completions" | tr -d '\r' | grep -iE '^(HTTP|x-gateway-overflow)' | paste -sd' ')
          else
            h=$(gw_curl architect -sS -D - -o /dev/null -H 'Content-Type: application/json' -d '{"model":"embedding","input":"ready"}' "$(gw_base embedding)/embeddings" | tr -d '\r' | grep -iE '^(HTTP|x-gateway-overflow)' | paste -sd' ')
          fi
          echo "$(date +%T) $a: $h"
          [[ $h == 'HTTP/1.1 200 OK' ]] && left=${left/$a/}
        done
        [[ -z ${left// /} ]] && break
        sleep 5
      done
      logged 'ssh -n gb10-2 "docker logs --timestamps --since '"$W6"' agentgateway 2>&1" | awk "/ route=default\/(audio|embedding) / { o = \$1; for (i = 2; i <= NF; i++) if (\$i ~ /^(route|http\.status|gen_ai\.provider\.name|overflow)=/) o = o \" \" \$i; print o }" | tail -n 20'
      azure_count "$W6"
      ```

      Expected:
      - Each alias's lines read `HTTP/1.1 200 OK x-gateway-overflow: azure` while the row is
        still evicted, then `HTTP/1.1 200 OK` alone. The time of that line, which is also its
        `gw_curl` line in the command log, is the first request the row answered again.
      - The log read prints each request's time, route, status, provider, and overflow marker,
        and nothing else: no address or endpoint. The rows' answers read
        `gen_ai.provider.name=custom` with no `overflow`. Azure's read
        `gen_ai.provider.name=azure overflow="azure"`.
      - `azure_count`: the step's Azure answers, each 200, at most about 55, and no 429.
      - If either alias still overflows after the 24th try, the row is still evicted outside an
        overflow step. The task's stop rule applies: the session stops and escalates.

### Results

The architect ran the walk on 2026-11-17, 05:37:50–05:52:44, from the laptop, with every command
under "Commands as run". Each of its four deploys validated the config and reloaded it in place,
the agentgateway container staying up; each also recreated the Postgres container, as in slices 2
and 3 (the cause, and its fix after the review: slice 2, "Why Postgres was recreated").

**Step 1.** One line, `+ 2026-11-17T05:37:50-05:00 laptop: source scripts/clients-lib.sh`.

**Step 2.** At 05:38:04, audio's `/models` answered
`{"object":"list","data":[{"id":"audio","object":"model","owned_by":"gateway"}]}`: the gateway's
answer, not the row's.

**Step 3.** As expected:

| Time | Command | Result |
| --- | --- | --- |
| 05:38:39 | deploy `rows-down` | `overlay rows-down: applied`, `Configuration is valid!` |
| 05:39:00 | agent, rows down | 200, `x-gateway-overflow: azure`; `{"model":"gpt-oss-120b","content":"ready"}` |
| 05:39:20 | plain deploy | no overlay applied, `Configuration is valid!` |
| 05:39:54 | agent, rows up | 200, no overflow header; `{"model":"agent","content":"ready"}` |
| 05:40:08 | `azure_count` | agent 1, 200 ×1; 0 429 |

**Step 4.** `bulk-budget-low` was deployed at 05:40:27 (`overlay bulk-budget-low: applied`).
bulk's first request, at 05:40:47, got 200: the budget's window had rolled to the 05:00 hour,
with nothing used, so this was the request that crosses the budget. It was charged 22 tokens. go-ai
got 200 at 05:40:53. `budget_status bulk` then read `used 22 of 1 Tokens, exceeded true, Block;
window ends 06:00:00` (05:41:07), and after the plain deploy at 05:41:15, `used 22 of 1000000
Tokens, exceeded false, Block` (05:41:24): the same count under the restored budget. bulk's second
request, which would have shown the 429, wasn't run; slice 3 showed it live ("bulk's budget
Block"). The walkthrough's step 4 text now says the first request is 200 when bulk has used
nothing in the current hour.

**Step 5.** The tunnel opened at 05:42:17. The UI's sidebar showed no Logs or Analytics link. It
links them only when the config has an `llm` section (`hasLlm`, `ui/src/components/Shell.tsx`,
102) [src], and the route `ai` form this config uses has none. The pages load by URL, at
`/ui/llm/logs` and `/ui/llm/analytics`, and the walkthrough's step 5 now gives both.

- **Logs** listed each request with its key's name as the user and its provider, and the note
  "Prompt logging is off". Step 3's overflow read: provider Azure, model `gpt-oss-120b`, 73 tokens
  in, 27 out, 805 ms, user architect, client curl.
- **Analytics** showed $0.0023, 2,429,559 tokens, and 7,386 calls over the last 24 hours. The
  cost is unexplained, since the config sets no model catalog or prices. It is probably
  agentgateway's built-in pricing for an Azure model; that is unverified.
- `request_log 8` wasn't run; slice 3's read of the same table ("The request log") showed
  `payload_rows` 0.

The watch register, [`docs/watch.md`](../watch.md), now has an entry for it: **the UI links Logs
and Analytics only when an `llm` section exists.** A capability wanted from agentgateway: the links
shown for a config whose request log comes from route `ai` backends.

**Step 6, the Framework reboot (behavior 11).** No overlay was live (`# overlays: none`), and
`W6` was 2026-11-17T05:48:38-05:00.

| Time | Event |
| --- | --- |
| 05:49:51 | the architect reported `omarchy update` and `sudo reboot` done; both Framework rows' `/health` read 000 |
| 05:49:57 → 05:50:08 | audio: 503 after about 11 s, a row attempt (`gen_ai.provider.name=custom`) |
| 05:50:08 → 05:50:19 | audio again: 503 after about 11 s; the row's second failure evicts it |
| 05:50:19 → 05:50:21 | audio again: 200, `x-gateway-overflow: azure`, from `gpt-audio-mini-2025-12-15`: "The text in the clip is: \"The access code is 7429.\"" |
| 05:50:21 → 05:50:44 | embedding: 200, `x-gateway-overflow: azure`, after about 23 s, from `text-embedding-3-small` at 768 dimensions |
| 05:50:44 | `azure_count` since `W6`: audio 1, embedding 1, each 200; 0 429 |
| 05:50:52 | the `/health` poll started |
| 05:51:45 | the architect reported the LUKS unlock; the unlock itself was a little earlier |
| 05:51:49 | `framework:8002 /health 200`, embedding |
| 05:52:34 | `framework:8001 /health 200`, audio |
| 05:52:42 | embedding: 200 from its row, the recovery loop's first request |
| 05:52:43 | audio: 200 from its row, the loop's first request |
| 05:52:44 | `azure_count` since `W6`: still 2, each 200; 0 429 |

The log read printed the six audio and embedding requests since `W6`: the two 503s and the two
rows' answers as `gen_ai.provider.name=custom` with no `overflow`, and Azure's two as
`gen_ai.provider.name=azure overflow="azure"`.

Behavior 11's two times, from the reported unlock at 05:51:45:

| Row | Unlock to `/health` 200 | Unlock to the first request answered again |
| --- | --- | --- |
| embedding, 8002 | ≥ 4 s (05:51:49) | ≥ 57 s (05:52:42), the recovery loop's first try |
| audio, 8001 | ≥ 49 s (05:52:34) | ≥ 58 s (05:52:43), the recovery loop's first try |

Each time is a lower bound. The real unlock came a little before 05:51:45, when the architect
reported it, so each time is a little longer than shown. And the first answers came when the
recovery loop started, its first try on each alias, which the session started once both
`/health` lines were in: they show that each row answered by then, not when it first could, and
embedding's row may have answered well before 57 s. spike-model-layout recorded audio's start at
68.7 s after the passphrase. Each row answered the first request sent to it, so neither waited
out an eviction: by then the rows' eviction windows from 05:50 had long passed.

**A powered-down host costs a connect timeout per attempt.** In slice 2 the rows-down overlay
pointed at a closed port, and each attempt was refused at once. A host that is powered down
doesn't refuse: each attempt waits out a connect timeout, about 11 s here, before it counts as a
failure. Audio's 258,652-byte body is past the 64 KiB the gateway retries, so it isn't retried,
and its first two requests each got a 503 after about 11 s until the two failures evicted the row.
Embedding's small body is retried, and its 23 s is consistent with two timed-out attempts on the
row before the retry reached Azure, though the log doesn't show the attempts. So during a host's
power-down the first callers of each alias wait about 11 s per attempt, and large bodies get 503s.

**The walk's Azure count** was 3, all 200 and no 429: agent 1 in step 3, and audio 1 and
embedding 1 in step 6. The task's count is 183 of 300, with Azure's 2,845 429s, all from
benchmark C-agent, reported apart.

## After the review

The spec review (2026-11-17) left readings that need the hosts, which the session took after it,
06:10–06:57, each through the helpers so it lands in the command log, except where said. Beside
those under slice 1 (the hosts, the Azure deployments, and the engines' upgrade), these:

- **The audio rerun (behavior 10):** go-ai's two audio tests, rerun with the rows down after
  warming the audio row's eviction, so they record Azure's answer rather than the row's 503 (the
  goal record's decision). Run with `rows-down` deployed, as `audio_rerun <name>`
  ([`scripts/clients-lib.sh`](../../scripts/clients-lib.sh)), then a plain deploy, 06:29:48–06:29:57.
  `TestTranscribeChat` passed on Azure; `TestAudioInResponsesRefused` failed, refused by the
  gateway's own Responses parser before Azure, a parity finding for audio. Each warm-up got
  Azure's 400 for a text-only chat. Azure: 6 (audio 400 ×5, 200 ×1), one of them the gateway's
  refusal; the task's total is 189 of 300 ("The tiers on Azure" and "The Azure count", slice 2).
- **The watch run** (06:19:48, `mise run watch`, `checked 2026-11-17T11:19Z`): it passes, and no
  line differs from its record. The three entries added at review are present and read for the
  first time: the UI's Logs and Analytics links (agentgateway#3860 open, and Shell.tsx's
  `Boolean(config.data.llm)` present, each as recorded), and the budgets' sliding window and the
  eviction growth without a cap, which list no lines to check.
- **The Postgres password's rotation:** a reviewer's diff printed the password into a local
  transcript, through a comment the deploy filled; the deploy now refuses a secret marker in a
  comment, and the comment holds none. Rotated with `pg_password_rotate`, then a plain deploy,
  which recreates agentgateway once (its `config` section's hash changes) and Postgres once (its
  environment changes). `pg_password_rotate` ran 06:19:43–06:19:44, and the deploy after it, at
  06:19:44, recreated both containers. `request_logs` held 7,392 rows when read after the
  rotation's deploy, and 7,402 when read after the smoke check's five curl requests through the
  gateway, before the tiers. A later read-only count found 7,397 rows started before 06:40:00, 5
  from 06:40:00 to 06:43:09, and 82 after, 7,484 in all. So the gateway connects and writes with
  the rotated password. All three counts were read outside the helpers. Postgres was recreated
  again by the deploys at 06:29:49 and 06:29:57, with nothing changed: the attestation the first
  fix didn't remove (slice 2, "Why Postgres was recreated").
- **Postgres's fix confirmed** (06:52:29 and 06:52:33): two plain deploys back to back; the first
  recreated Postgres once more, the second left it running, and neither build exported an
  attestation (slice 2, "Why Postgres was recreated").
- **The rows' reading** (06:57:39): each row's image, start time, and flags, and its `/health`,
  all four on v0.34.0 and answering 200 (slice 1, "spike-model-engines current (behavior 1)").
- **The watch run at the end** (06:57:40, `mise run watch`, `checked 2026-11-17T11:57Z`): it
  passes, every line as recorded, and each entry's last-checked line in
  [`docs/watch.md`](../watch.md) is taken from it. The task's start-of-task read,
  `checked 2026-11-16T16:34Z`, was taken before the brief's approval, so it isn't in a priority
  command log.
- **Currency and the check (behavior 20)**, the gateway's own, at review: `mise run currency`
  prints only `mise.bench.toml: python 3.14.10 -> 3.15.2`, the bench tools' held Python, and exits
  1, since [`scripts/currency.sh`](../../scripts/currency.sh) exits 1 for any line it prints, held
  or not. agentgateway's image pin and the compose FROM pin print nothing, so they are current.
  `mise run check` exits 0.

## Addendum 2026-11-19 · the 16-token Messages stall

On 2026-11-16, infer's `TestChatIncompleteAtMaxTokens/messages` sent a Messages stream at
`--max-tokens 16` to agent through the `rows-down` overlay, and it "did not exit within 15s" ("The
tiers on Azure", slice 2). It hasn't recurred in three reruns since: go-ai's on 2026-11-17, the
answer task's on 2026-11-18, and this one on 2026-11-19. Its cause stays open. One reading of it is
ruled out: that the gateway sends Azure an unstreamed request.

### 2026-11-17: go-ai's rerun

go-ai's azure-streams task reran the case through `rows-down` (go-ai `0eb0842`, "record:
v1.ai.client, azure-streams slice 5 classified", in its goal record,
`context/goals/v1.ai.client.md`). `gpt-oss-120b` answered a streamed Messages request at
`max_tokens` 16 in 1.3 s, ending in `message_stop` (`stop_reason` `max_tokens`) and closing the
connection, and infer ended on it, as incomplete. Replayed offline with the connection held open
30 s after `message_stop`, infer, at the branch and at `tools/infer/v0.1.0`, ended at
`message_stop` within 5 ms. So the stall wasn't go-ai's; the record left it to "the gateway's or
Azure's". The record also saw `azureai-fe-is-streaming: False` on Azure's reply, and read it as
the gateway sending Azure an unstreamed Chat Completions request and building the Messages stream
from the whole reply, so that a longer reply would stall until Azure finished. And it found the
translated stream's `message_start` reporting 0 input tokens, and its `message_delta` the real
count.

### 2026-11-18: the answer task's pass

With `rows-down` deployed, infer's `TestChatIncompleteAtMaxTokens/messages` passed in both stream
modes, in 0.26 s and 0.24 s ([`docs/findings/answer.md`](answer.md), line 216, the row "the
16-token Messages stall on agent").

### 2026-11-19: a timed stream

From the laptop, 09:38–09:43 local time: agentgateway v1.7.0 on gb10-2 with the `rows-down`
overlay, so agent is answered by its Foundry deployment, `gpt-oss-120b`, in eastus2. Each send is
one `messages_stream <alias> <max tokens> <prompt>`
([`scripts/clients-lib.sh`](../../scripts/clients-lib.sh)): one streamed Messages request through
the gateway on the alias, each line of the stream stamped with its arrival. Its verdict, from its
header comment: "streams" when the text deltas cover at least half of the reply's span, from the
first event to `message_stop`; "arrives whole" when every event lands within the last tenth of the
total; otherwise "mixed"; and "too short to tell" with fewer than two text deltas. The raw
captures are under `.state/max-tokens-note/`, untracked. The line numbers below are of the
task's command log, `.state/max-tokens-note/commands-2026-11-19.log`.

**The header, direct to Azure** (lines 17–24). Two chat requests to the deployment past the
gateway, "Count upward from 1, one number a line.", `max_tokens` 32 each:

| `stream` | Status | `content-type` | `azureai-fe-is-streaming` |
| --- | --- | --- | --- |
| `true` | HTTP/2 200 | `text/event-stream; charset=utf-8` | `False` |
| `false` | HTTP/2 200 | `application/json` | `False` |

So the header doesn't show whether a request was streamed. It reads `False` either way.

**A long reply, first try** (lines 211–253). "Count upward from 1, one number a line.",
`max_tokens` 1024, 3 sends. The model kept each reply short: it stopped at 20, asked how many, or
stopped at 100. Totals 1.054, 0.748, and 1.330 s; text deltas 6, 9, and 21; the verdict "mixed"
each time. Inconclusive: too little text to tell a stream from a whole reply.

**A long reply, to a fixed target** (lines 742–783). "Count from 1 to 300, one number per line,
nothing else.", `max_tokens` 1024, 3 sends, each counting to 300 and ending `end_turn`. Times in
seconds from the send:

| Send | First event | First text delta | Last text delta | Text span | `message_stop` | Text deltas, of all deltas | Output tokens |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 0.372 | 0.574 | 1.362 | 0.788 | 1.362 | 61 of 84 | 676 |
| 2 | 0.222 | 0.658 | 1.279 | 0.621 | 1.279 | 61 of 76 | 661 |
| 3 | 0.200 | 0.654 | 1.120 | 0.466 | 1.120 | 61 of 92 | 703 |

The text deltas by arrival, as count@ms from the send:

- send 1: 1@573, 1@666, 10@667, 10@757, 8@841, 8@887, 3@906, 5@954, 8@1033, 7@1361;
- send 2: 27@657–659, 8@757–758, 8@832–833, 2@857–858, 6@926–927, 10@1278;
- send 3: 37@654–656, 24@1117–1119.

The verdict was "streams" each time. The text arrives in bursts spread over the reply's second or
so, never all at the end. Each reply carried `x-gateway-overflow: azure`, `server: istio-envoy`,
and `azureai-fe-is-streaming: False`. Each `message_start` reported 0 input tokens, and its
`message_delta` the real count: 83 here, 78 in the first try, and 72 in the 16-token case below,
as on 2026-11-17.

**The 16-token case** (lines 262–331). "Name a primary color.", `max_tokens` 16, 5 sends. Every
one ended `stop_reason` `max_tokens` with 16 output tokens, all of them reasoning: thinking deltas
and no text deltas, so each verdict was "too short to tell". Totals 1.064, 0.665, 1.876, 0.486,
and 0.448 s. `message_delta` and `message_stop` arrived within 1 ms of the last delta every time.
Nothing was held, and the stall didn't recur. The fourth and fifth sends started in the same
second and so share a folder, where the fifth's captures replaced the fourth's. The log keeps the
fourth's summary, and the helper's folder names carry milliseconds since (`07da3da`).

**Back to the rows.** Each overlay was removed by a plain deploy (lines 340 and 792 onward), and
one `messages_stream agent 64` after each was answered by the row, `overflow: none` (lines 521–534
and 973–986).

**The Azure count.** 13 of the task's cap of 20: 11 through the gateway, agent's, all 200
(`azure_count` since the first deploy, lines 987–1000), and the 2 direct requests above, counted
by hand. No 429.

### The translation, read in the source

For the Azure provider, which lists only `completions`, agentgateway v1.7.0 translates a Messages
request into Chat Completions and the reply's chunks back into Messages events, in module
`from_messages` of `crates/llm/src/conversion/completions.rs`
([at the `v1.7.0` tag](https://github.com/agentgateway/agentgateway/blob/v1.7.0/crates/llm/src/conversion/completions.rs))
[src]:

- The request keeps the client's `stream` (line 1264) and, when streaming, asks for usage with
  `stream_options.include_usage` (1276–1283).
- `translate_stream` (286 onward) turns each chunk into Messages events as it arrives.
  `message_start` goes out on the first chunk, built from the chunk's id and model, with no usage
  (608–615): hence its 0 input tokens.
- A usage chunk is kept (621–623), and so is a finish reason (741). `message_delta`, which carries
  the input tokens from the usage, and `message_stop` go out once both have arrived (745–747), or
  at `[DONE]`, which forces them (597–598). `flush_message_end` builds the two (483–555).

So the translated stream is a stream. The one place it holds events back is its end: until a
finish reason and a usage chunk have both arrived, or `[DONE]`.

### What it leaves

- The unstreamed-request reading is ruled out. The header reads `False` on a request streamed
  directly to Azure too, the source keeps the client's `stream`, and the overflowed long replies
  stream.
- A held `message_stop` stays a candidate: had Azure sent its finish reason and then been slow
  with its usage chunk or `[DONE]`, the gateway would hold `message_delta` and `message_stop` until
  one came. It wasn't seen. In 5 sends at 16 tokens both came within 1 ms of the last delta.
- The 2026-11-16 stall's cause stays open. It hasn't recurred in three reruns: 2026-11-17,
  2026-11-18, and 2026-11-19.

### To repeat it

The walkthrough was waived, so these steps stand in for it. From the repository root on the
laptop, through the helpers, so each command lands in the day's command log. It sends 1 request to
Azure.

```sh
source scripts/clients-lib.sh
logged "mise run agentgateway-deploy rows-down"
messages_stream agent 1024 "Count from 1 to 300, one number per line, nothing else."
logged "mise run agentgateway-deploy"
```

Expected:

- the first deploy prints `overlay rows-down: applied` and `Configuration is valid!`;
- `messages_stream` prints `status: HTTP/1.1 200 OK; overflow: x-gateway-overflow: azure`, about
  61 text deltas from about 0.6 s to 1.4 s, `message_stop` with the last of them, and
  `verdict: streams`;
- the second deploy applies no overlay, and agent is answered by its row again.

### Commands as run, 2026-11-19

The commands that matter, as logged, from `.state/max-tokens-note/commands-2026-11-19.log`: the
control, each deploy, the first `messages_stream` of each case, and each `azure_count`. The two
direct requests are the Azure helper's, `az_curl`, logged as the curl it runs, and `azure_count`
is logged as its read of the access log (lines 254, 332, 784, and 987). Each
`mise run agentgateway-deploy` is followed in the log by the deploy's own `+` lines, and each
`messages_stream` by its curl and its summary. The output stays in the log.

```text
+ 2026-11-19T09:38:53-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-19T09:38:53-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -o /dev/null -D .state/max-tokens-note/control/stream-true.headers.txt -H content-type: application/json -d {"model":"gpt-oss-120b","stream":true,"max_tokens":32,"messages":[{"role":"user","content":"Count upward from 1, one number a line."}]}
+ 2026-11-19T09:38:54-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -o /dev/null -D .state/max-tokens-note/control/stream-false.headers.txt -H content-type: application/json -d {"model":"gpt-oss-120b","stream":false,"max_tokens":32,"messages":[{"role":"user","content":"Count upward from 1, one number a line."}]}
+ 2026-11-19T09:38:56-05:00 laptop: grep -iH -e '^HTTP/' -e '^azureai-fe-is-streaming' .state/max-tokens-note/control/stream-true.headers.txt .state/max-tokens-note/control/stream-false.headers.txt
+ 2026-11-19T09:39:05-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-19T09:39:05-05:00 laptop: mise run agentgateway-deploy rows-down
+ 2026-11-19T09:39:12-05:00 laptop: messages_stream agent 1024 'Count upward from 1, one number a line.'
+ 2026-11-19T09:39:31-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-19T09:39:31-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-19T09:39:05 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-19T09:39:35-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-19T09:39:35-05:00 laptop: messages_stream agent 16 'Name a primary color.'
+ 2026-11-19T09:39:40-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-19T09:39:31 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-19T09:39:49-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-19T09:39:49-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-19T09:42:02-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-19T09:42:02-05:00 laptop: mise run agentgateway-deploy rows-down
+ 2026-11-19T09:42:05-05:00 laptop: messages_stream agent 1024 'Count from 1 to 300, one number per line, nothing else.'
+ 2026-11-19T09:42:09-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-19T09:41:41 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-19T09:42:13-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-19T09:42:13-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-19T09:43:28-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-19T09:39:05 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

## Commands as run

Every command the logs hold, as logged, with its time, from
`.state/priority/commands-2026-11-16.log` (slices 1–3) and `commands-2026-11-17.log` (the
walkthrough and the readings after the review). The output stays there, untracked. After the
review, these ran outside the helpers, so they aren't here: the engines' `mise run currency` and
`mise run check`; the hosts' `git pull` of `aaf19ed`; the session's `/health` poll of the rows that
found them answering by 06:39:55; the comparison of the Postgres container's `Created` time and
image across the 06:52 deploys; and the `request_logs` counts. The two host reads were logged as `<time>,
laptop: <command>`, the rest as `+ <time> <host>: <command>`. The helpers log curl's arguments
joined by spaces, so a JSON body shows without its shell quotes, and an audio body read from a
process substitution as `-d @/dev/fd/63`. The `mise run agentgateway-deploy` line is followed by
the deploy's own `+` lines, from its output, appended to the log by `tee -a`. The architect's
reboots and unlock are logged as theirs. The walkthrough's step 6 recovery loop logged only the
`gw_curl` requests of its one pass, since both rows answered on its first try.

### 2026-11-16 · the hosts

```text
13:05:30, laptop: { date -Is; for h in gb10-1 gb10-2; do echo "== $h"; timeout 60 ssh -o BatchMode=yes $h 'apt list --upgradable 2>/dev/null | grep -vc "^Listing"; uname -r; docker --version; docker compose version 2>&1 | head -1; ls /var/run/reboot-required 2>&1 | tail -1; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'; done; echo "== framework"; timeout 60 ssh -o BatchMode=yes framework 'checkupdates 2>/dev/null | wc -l; uname -r; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'; for h in gb10-1 gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done; } 2>&1 | tee .state/priority/stack-$(date +%F).txt
13:20:44, laptop: { date -Is; for h in gb10-1 gb10-2; do echo "== $h"; timeout 60 ssh -o BatchMode=yes $h 'uptime -p; apt list --upgradable 2>/dev/null | grep -vc "^Listing"; uname -r; nvidia-smi --query-gpu=driver_version --format=csv,noheader; docker --version; ls /var/run/reboot-required 2>&1 | tail -1; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"; git -C ~/spike-model-engines log --oneline -1'; done; for hp in gb10-1:8000 gb10-2:8000 framework:8001 framework:8002 gb10-2:3000; do printf "%s health " $hp; curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$hp/health; done; } 2>&1 | tee .state/priority/stack-after-$(date +%F).txt
```

### 2026-11-16 · the engines pull and the row updates

```text
+ 2026-11-16T13:21:26-05:00 gb10-1,gb10-2,framework: cd ~/repos/spike-model-engines && git pull --ff-only
+ 2026-11-16T13:21:26-05:00 gb10-2: cd ~/repos/spike-model-engines && time VLLM_MODEL=gemma-4-26B-A4B-NVFP4-vision-gb10 host/engines vllm update
+ 2026-11-16T13:21:26-05:00 gb10-1: cd ~/repos/spike-model-engines && time VLLM_MODEL=gpt-oss-120b-agent-fp8 host/engines vllm update
+ 2026-11-16T13:21:26-05:00 framework: cd ~/repos/spike-model-engines && time VLLM_MODEL=gemma-4-E4B-it-audio-framework host/engines vllm update && time VLLM_MODEL=granite-embedding-english-r2-framework host/engines vllm update
```

### 2026-11-16 · the row bursts

```text
+ 2026-11-16T13:30:12-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:30:15-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:30:15-05:00 laptop: row_burst agent 25
+ 2026-11-16T13:30:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:30:22-05:00 laptop: for i in $(seq 25); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://gb10-1:8000/v1/chat/completions & done | sort | uniq -c
+ 2026-11-16T13:31:37-05:00 laptop: for i in $(seq 33); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://gb10-2:8000/v1/chat/completions & done | sort | uniq -c
+ 2026-11-16T13:32:23-05:00 laptop: for i in $(seq 9); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"audio","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://framework:8001/v1/chat/completions & done | sort | uniq -c
```

### 2026-11-16 · the Azure deployments, direct

```text
+ 2026-11-16T13:48:46-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:48:46-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"gpt-oss-120b","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":64}
+ 2026-11-16T13:48:47-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"gpt-5-mini","messages":[{"role":"user","content":[{"type":"text","text":"What color is this image? One word."},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"}}]}],"max_completion_tokens":256}
+ 2026-11-16T13:48:49-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"gpt-audio-mini","modalities":["text"],"messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":32}
+ 2026-11-16T13:48:49-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/embeddings"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"text-embedding-3-small","input":"ready","dimensions":768}
+ 2026-11-16T13:48:59-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:48:59-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d @.state/priority/assets/audio-probe.json
```

### 2026-11-16 · the compose deploy

```text
+ 2026-11-16T13:49:04-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:49:04-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T13:49:04-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T13:49:05-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T13:49:06-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T13:49:06-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T13:49:07-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T13:49:07-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T13:49:08-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T13:49:08-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T13:49:09-05:00 gb10-2: docker rm --force agentgateway
+ 2026-11-16T13:49:10-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T13:49:19-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
```

### 2026-11-16 · the checks on the stack

```text
+ 2026-11-16T13:49:36-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T13:49:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":64} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T13:49:40-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T13:49:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"embedding","input":["gateway","routing"]} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-16T13:49:42-05:00 laptop: curl -s -o /dev/null -w '%{http_code}\n' http://gb10-2:3000/agent/v1/models
+ 2026-11-16T13:49:42-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3000/agent/v1/../metrics
+ 2026-11-16T13:49:42-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3000/agent/v1/load
```

### 2026-11-16 · the tiers and the infer CLI

```text
+ 2026-11-16T13:49:49-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:49:49-05:00 laptop: git -C ~/architecture/go-ai worktree add --detach .state/priority/go-ai tools/infer/v0.1.0
+ 2026-11-16T13:49:49-05:00 laptop: GOBIN=.state/priority/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.1.0 && .state/priority/bin/infer version
+ 2026-11-16T13:49:51-05:00 laptop: goai_tier compose-goai agent vision audio embedding
+ 2026-11-16T13:49:51-05:00 laptop: cd .state/priority/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/compose-goai.log
+ 2026-11-16T13:50:51-05:00 laptop: infer_tier compose-infer agent vision audio embedding
+ 2026-11-16T13:50:51-05:00 laptop: cd .state/priority/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/compose-infer.log
+ 2026-11-16T13:51:22-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer Say ready.
+ 2026-11-16T13:51:30-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/vision/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/audio/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/embedding/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:31-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer chat Reply with the word ready.
+ 2026-11-16T13:51:34-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:51:34-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer chat Reply with the word ready.
```

### 2026-11-16 · the reboot

```text
+ 2026-11-16T13:52:53-05:00 gb10-2 (architect): sudo reboot (issued 13:52:43)
+ 2026-11-16T13:56:33-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:56:33-05:00 laptop: ssh -o BatchMode=yes gb10-2 'uptime -p; ~/gateway/compose.sh ps --format "{{.Name}} {{.Status}}"; docker exec gateway-postgres-1 psql -U agentgateway -d agentgateway -Atc "select count(*) from request_logs"'
+ 2026-11-16T13:56:34-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":64} http://gb10-2:3000/vision/v1/chat/completions
```

### 2026-11-16 · the overflow deploy and the rows-up checks

```text
+ 2026-11-16T14:17:24-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:17:24-05:00 laptop: for h in gb10-1 gb10-2 framework; do ssh -o BatchMode=yes $h 'ss -ltn | grep -c ":8009 "'; done
+ 2026-11-16T14:17:26-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T14:17:26-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T14:17:27-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T14:17:27-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T14:17:28-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T14:17:28-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T14:17:29-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T14:17:30-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T14:17:30-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T14:17:31-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T14:17:35-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T14:17:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T14:17:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T14:17:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T14:17:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T14:17:46-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:17:46-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-up-agent.json -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T14:17:49-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T14:17:51-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-up-vision.json -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":[{"type":"text","text":"What color is this image? One word."},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"}}]}],"max_tokens":64} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T14:17:52-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-up-audio.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T14:17:53-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-up-embed.json -H Content-Type: application/json -d {"model":"embedding","input":["gateway","routing"]} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-16T14:17:53-05:00 laptop: curl -s -o /dev/null -w '%{http_code}\n' http://gb10-2:3000/agent/v1/models
+ 2026-11-16T14:17:53-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3000/agent/v1/load
+ 2026-11-16T14:17:58-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:17:58-05:00 laptop: goai_tier p2-up-goai agent vision audio embedding
+ 2026-11-16T14:17:58-05:00 laptop: cd .state/priority/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/p2-up-goai.log
+ 2026-11-16T14:18:57-05:00 laptop: infer_tier p2-up-infer agent vision audio embedding
+ 2026-11-16T14:18:57-05:00 laptop: cd .state/priority/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/p2-up-infer.log
```

### 2026-11-16 · escalation 1's deploy

```text
+ 2026-11-16T14:32:33-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:32:33-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T14:32:33-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T14:32:34-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T14:32:35-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T14:32:35-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T14:32:36-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T14:32:37-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T14:32:37-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T14:32:38-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T14:32:39-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T14:32:42-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T14:32:43-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T14:32:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
```

### 2026-11-16 · the rows-down overlay and the tiers on Azure

```text
+ 2026-11-16T14:32:54-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:32:54-05:00 laptop: mise run agentgateway-deploy rows-down
+ 2026-11-16T14:32:54-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T14:32:54-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T14:32:55-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T14:32:56-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T14:32:56-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T14:32:57-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T14:32:58-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T14:32:58-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T14:32:59-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T14:33:02-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T14:33:03-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-agent.json -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Reply with the word ready."}],"max_tokens":64} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T14:33:05-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-vision.json -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":[{"type":"text","text":"What color is this image? One word."},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"}}]}],"max_tokens":256} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T14:33:05-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-audio.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T14:33:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-audio-text.json -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_tokens":32} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T14:33:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-embed.json -H Content-Type: application/json -d {"model":"embedding","input":["gateway","routing"]} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-16T14:33:06-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T14:32:54-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-16T14:33:19-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:33:19-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-vision2.json -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":[{"type":"text","text":"What color is this image? One word."},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"}}]}],"max_completion_tokens":256} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T14:33:21-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-audio1.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T14:33:22-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p2-down-audio2.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T14:33:24-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T14:32:54-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-16T14:33:31-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:33:31-05:00 laptop: goai_tier p2-down-goai agent vision audio embedding
+ 2026-11-16T14:33:31-05:00 laptop: cd .state/priority/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/p2-down-goai.log
+ 2026-11-16T14:35:11-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T14:32:54-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-16T14:35:33-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:35:33-05:00 laptop: infer_tier p2-down-infer agent vision audio embedding
+ 2026-11-16T14:35:33-05:00 laptop: cd .state/priority/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/p2-down-infer.log
+ 2026-11-16T14:36:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer models
+ 2026-11-16T14:36:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/vision/v1 .state/priority/bin/infer models
+ 2026-11-16T14:36:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/audio/v1 .state/priority/bin/infer models
+ 2026-11-16T14:36:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/embedding/v1 .state/priority/bin/infer models
+ 2026-11-16T14:36:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer chat Reply with the word ready.
+ 2026-11-16T14:36:37-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T14:32:54-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-16 · back to the rows

```text
+ 2026-11-16T14:36:52-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:36:52-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T14:36:52-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T14:36:52-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T14:36:53-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T14:36:54-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T14:36:54-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T14:36:55-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T14:36:56-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T14:36:56-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T14:36:57-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T14:37:00-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T14:37:01-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Hi"}],"max_completion_tokens":8} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T14:37:01-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_completion_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T14:37:02-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Hi"}],"max_completion_tokens":8} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T14:37:02-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"embedding","input":"ready"} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-16T14:37:03-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T14:36:52-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-16 · benchmark C-agent

```text
+ 2026-11-16T14:37:10-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T14:37:10-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:37:10-05:00 laptop: cell bc-agent overflow-agent cap agent
+ 2026-11-16T14:37:10-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/agent/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overflow-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=494185694 --output kind=json,path=.state/priority/cells/bc-agent/result.json --disable-console-interactive > .state/priority/cells/bc-agent/guidellm.log 2>&1
+ 2026-11-16T14:37:10-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/bc-agent/gateway-stats.tsv
+ 2026-11-16T14:37:10-05:00 laptop: every 5 s while it runs: curl -sS --max-time 3 http://gb10-1:8000/metrics, the sums of vllm:num_requests_running and vllm:num_requests_waiting >> .state/priority/cells/bc-agent/row-metrics.tsv
+ 2026-11-16T14:38:29-05:00 laptop: ssh -n gb10-2 'docker logs --timestamps --since 1794857830 --until 1794857910 agentgateway 2>&1' | the lines of route=default/agent as time, status, path, retry_after, overflow, retry_attempt > .state/priority/cells/bc-agent/gateway-requests.tsv
+ 2026-11-16T14:38:31-05:00 laptop: overflow_read bc-agent
+ 2026-11-16T14:38:32-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T14:37:10-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-16 · escalation 2's deploy

```text
+ 2026-11-16T14:40:43-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T14:40:43-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T14:40:43-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T14:40:44-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T14:40:45-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T14:40:46-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T14:40:46-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T14:40:47-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T14:40:48-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T14:40:49-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T14:40:49-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T14:40:53-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
```

### 2026-11-16 · slice 3: the path and the deploy

```text
+ 2026-11-16T16:15:59-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:15:59-05:00 laptop: for h in gb10-1 gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done
+ 2026-11-16T16:15:59-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T16:15:59-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T16:15:59-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T16:15:59-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T16:15:59-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T16:15:59-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T16:15:59-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T16:16:00-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T16:16:00-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T16:16:00-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T16:16:03-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T16:16:03-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T16:15:59-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-16 · the request log and a stream charged to its key

```text
+ 2026-11-16T16:16:07-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:16:07-05:00 laptop: ssh gb10-2 'docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -P pager=off' <<< "select to_char(completed_at at time zone 'UTC', 'HH24:MI:SS') as completed_utc,   http_status as status, attributes_json->>'agw.api_key.name' as key, agentgateway_user as ui_user,   gen_ai_provider_name as provider, gen_ai_request_model as model, input_tokens as input,   output_tokens as output, total_tokens as total, duration_ms, has_payload   from request_logs order by completed_at desc limit 5; select count(*) as payload_rows from request_log_payloads;"
+ 2026-11-16T16:16:08-05:00 laptop: ssh -n gb10-2 "curl -sS --max-time 5 'http://127.0.0.1:3001/api/budgets/status?apiKeyName=go-ai'" | jq -r '.budgets[] | one line each'
+ 2026-11-16T16:16:08-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/go-ai)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T16:16:11-05:00 laptop: ssh -n gb10-2 "curl -sS --max-time 5 'http://127.0.0.1:3001/api/budgets/status?apiKeyName=go-ai'" | jq -r '.budgets[] | one line each'
+ 2026-11-16T16:16:14-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:16:14-05:00 laptop: ssh gb10-2 'docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -P pager=off' <<< "select to_char(completed_at at time zone 'UTC', 'HH24:MI:SS') as completed_utc,   http_status as status, attributes_json->>'agw.api_key.name' as key, agentgateway_user as ui_user,   gen_ai_provider_name as provider, gen_ai_request_model as model, input_tokens as input,   output_tokens as output, total_tokens as total, duration_ms, has_payload   from request_logs order by completed_at desc limit 5; select count(*) as payload_rows from request_log_payloads;"
```

### 2026-11-16 · bulk's bucket and budget, and the restart

```text
+ 2026-11-16T16:16:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:16:22-05:00 laptop: mise run agentgateway-deploy bulk-rate-low
+ 2026-11-16T16:16:22-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T16:16:22-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T16:16:22-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T16:16:22-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T16:16:22-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T16:16:23-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T16:16:23-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T16:16:23-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T16:16:23-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T16:16:26-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T16:16:26-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bulk)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T16:16:26-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bulk)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T16:16:26-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bulk)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T16:16:26-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/go-ai)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T16:16:27-05:00 laptop: mise run agentgateway-deploy bulk-budget-low
+ 2026-11-16T16:16:27-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T16:16:27-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T16:16:27-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T16:16:27-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T16:16:27-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T16:16:27-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T16:16:27-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T16:16:27-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T16:16:27-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T16:16:30-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T16:16:30-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bulk)" | curl -K - -sS -D - -o .state/priority/p3-budget.json -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T16:16:30-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bulk)" | curl -K - -sS -D - -o .state/priority/p3-budget.json -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T16:16:30-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/go-ai)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T16:16:31-05:00 laptop: ssh -n gb10-2 "curl -sS --max-time 5 'http://127.0.0.1:3001/api/budgets/status?apiKeyName=bulk'" | jq -r '.budgets[] | one line each'
+ 2026-11-16T16:16:31-05:00 laptop: ssh -o BatchMode=yes gb10-2 'docker restart agentgateway >/dev/null && echo restarted'
+ 2026-11-16T16:16:36-05:00 laptop: ssh -n gb10-2 "curl -sS --max-time 5 'http://127.0.0.1:3001/api/budgets/status?apiKeyName=bulk'" | jq -r '.budgets[] | one line each'
+ 2026-11-16T16:16:36-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T16:16:36-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T16:16:36-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T16:16:36-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T16:16:36-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T16:16:36-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T16:16:36-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T16:16:37-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T16:16:37-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T16:16:37-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T16:16:40-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
```

### 2026-11-16 · embedding's burst

```text
+ 2026-11-16T16:16:47-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:16:47-05:00 laptop: for i in $(seq 40); do printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -s -o /dev/null -D - -H 'Content-Type: application/json' -d '{"model":"embedding","input":"ready"}' http://gb10-2:3000/embedding/v1/embeddings | grep -iE '^HTTP/|^retry-after' | tr -d '\r' | paste -sd' ' & done | sort | uniq -c
```

### 2026-11-16 · benchmark A

```text
+ 2026-11-16T16:16:51-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T16:16:51-05:00 laptop: cell a-audio-d overhead-audio direct audio
+ 2026-11-16T16:16:51-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8001/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-audio.yaml --backend kind=openai_http,model=audio --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it --seed kind=static,value=1343236474 --output kind=json,path=.state/priority/cells/a-audio-d/result.json --disable-console-interactive > .state/priority/cells/a-audio-d/guidellm.log 2>&1
+ 2026-11-16T16:17:23-05:00 laptop: cell a-audio-g overhead-audio gateway audio
+ 2026-11-16T16:17:23-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/audio/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-audio.yaml --backend kind=openai_http,model=audio --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it --seed kind=static,value=586905257 --output kind=json,path=.state/priority/cells/a-audio-g/result.json --disable-console-interactive > .state/priority/cells/a-audio-g/guidellm.log 2>&1
+ 2026-11-16T16:17:23-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/a-audio-g/gateway-stats.tsv
+ 2026-11-16T16:17:59-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T16:17:59-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:17:59-05:00 laptop: cell a-embed limited-embed cap embedding
+ 2026-11-16T16:17:59-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/embedding/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/limited-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=2617946231 --output kind=json,path=.state/priority/cells/a-embed/result.json --disable-console-interactive > .state/priority/cells/a-embed/guidellm.log 2>&1
+ 2026-11-16T16:17:59-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/a-embed/gateway-stats.tsv
+ 2026-11-16T16:17:59-05:00 laptop: every 5 s while it runs: curl -sS --max-time 3 http://framework:8002/metrics, the sums of vllm:num_requests_running and vllm:num_requests_waiting >> .state/priority/cells/a-embed/row-metrics.tsv
+ 2026-11-16T16:18:19-05:00 laptop: cell a-audio-in overhead-audio gateway audio go-ai
+ 2026-11-16T16:18:19-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/go-ai) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/audio/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-audio.yaml --backend kind=openai_http,model=audio --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it --seed kind=static,value=2828409129 --output kind=json,path=.state/priority/cells/a-audio-in/result.json --disable-console-interactive > .state/priority/cells/a-audio-in/guidellm.log 2>&1
+ 2026-11-16T16:18:19-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/a-audio-in/gateway-stats.tsv
+ 2026-11-16T16:19:49-05:00 laptop: ssh -n gb10-2 'docker logs --timestamps --since 1794863879 --until 1794863990 agentgateway 2>&1' | the lines of route=default/embedding and key_name="bench" as time, status, path, retry_after, overflow, retry_attempt, key_name > .state/priority/cells/a-embed/gateway-requests.tsv
+ 2026-11-16T16:28:07-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T16:28:07-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:28:07-05:00 laptop: rtfx a-audio-d a-audio-g a-audio-in
+ 2026-11-16T16:28:07-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T16:17:59-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-16 · benchmark B

```text
+ 2026-11-16T16:28:13-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T16:28:13-05:00 laptop: cell b-agent-d overhead-agent direct agent
+ 2026-11-16T16:28:13-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-1:8000/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=603902497 --output kind=json,path=.state/priority/cells/b-agent-d/result.json --disable-console-interactive > .state/priority/cells/b-agent-d/guidellm.log 2>&1
+ 2026-11-16T16:30:15-05:00 laptop: cell b-agent-g overhead-agent gateway agent
+ 2026-11-16T16:30:15-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/agent/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=1360367090 --output kind=json,path=.state/priority/cells/b-agent-g/result.json --disable-console-interactive > .state/priority/cells/b-agent-g/guidellm.log 2>&1
+ 2026-11-16T16:30:15-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/b-agent-g/gateway-stats.tsv
+ 2026-11-16T16:32:22-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T16:32:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:32:22-05:00 laptop: cell b-bulk bulk-vision-150 gateway vision bulk
+ 2026-11-16T16:32:22-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bulk) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/bulk-vision-150.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=3354227353 --output kind=json,path=.state/priority/cells/b-bulk/result.json --disable-console-interactive > .state/priority/cells/b-bulk/guidellm.log 2>&1
+ 2026-11-16T16:32:22-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/b-bulk/gateway-stats.tsv
+ 2026-11-16T16:32:42-05:00 laptop: cell b-agent-in overhead-agent gateway agent go-ai
+ 2026-11-16T16:32:42-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/go-ai) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/agent/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=2879027479 --output kind=json,path=.state/priority/cells/b-agent-in/result.json --disable-console-interactive > .state/priority/cells/b-agent-in/guidellm.log 2>&1
+ 2026-11-16T16:32:42-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/b-agent-in/gateway-stats.tsv
+ 2026-11-16T16:35:07-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T16:32:22-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-16 · benchmark D

```text
+ 2026-11-16T16:35:14-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T16:35:14-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T16:35:14-05:00 laptop: cell d-bulk bulk-vision-120 gateway vision bulk
+ 2026-11-16T16:35:14-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bulk) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/bulk-vision-120.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=1625235272 --output kind=json,path=.state/priority/cells/d-bulk/result.json --disable-console-interactive > .state/priority/cells/d-bulk/guidellm.log 2>&1
+ 2026-11-16T16:35:14-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/d-bulk/gateway-stats.tsv
+ 2026-11-16T16:35:29-05:00 laptop: cell d-int interactive-vision gateway vision go-ai
+ 2026-11-16T16:35:29-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/go-ai) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/interactive-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=2062406523 --output kind=json,path=.state/priority/cells/d-int/result.json --disable-console-interactive > .state/priority/cells/d-int/guidellm.log 2>&1
+ 2026-11-16T16:35:29-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/d-int/gateway-stats.tsv
+ 2026-11-16T16:37:35-05:00 laptop: mise run agentgateway-deploy priority-flat
+ 2026-11-16T16:37:35-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T16:37:35-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T16:37:35-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T16:37:35-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T16:37:35-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T16:37:35-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T16:37:36-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T16:37:36-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T16:37:36-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T16:37:39-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T16:37:39-05:00 laptop: cell d-bulk-flat bulk-vision-120 gateway vision bulk
+ 2026-11-16T16:37:39-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bulk) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/bulk-vision-120.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=3277908895 --output kind=json,path=.state/priority/cells/d-bulk-flat/result.json --disable-console-interactive > .state/priority/cells/d-bulk-flat/guidellm.log 2>&1
+ 2026-11-16T16:37:39-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/d-bulk-flat/gateway-stats.tsv
+ 2026-11-16T16:37:54-05:00 laptop: cell d-int-flat interactive-vision gateway vision go-ai
+ 2026-11-16T16:37:54-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/go-ai) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/interactive-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=3403424441 --output kind=json,path=.state/priority/cells/d-int-flat/result.json --disable-console-interactive > .state/priority/cells/d-int-flat/guidellm.log 2>&1
+ 2026-11-16T16:37:54-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/priority/cells/d-int-flat/gateway-stats.tsv
+ 2026-11-16T16:39:53-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T16:39:54-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T16:39:54-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T16:39:54-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T16:39:54-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T16:39:54-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T16:39:54-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T16:39:54-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T16:39:54-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T16:39:54-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T16:39:57-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-16T16:39:57-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-16T16:35:14-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-17 · walkthrough steps 1–3: the helpers, `/models`, and a row-down overflow

```text
+ 2026-11-17T05:37:50-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T05:38:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-17T05:38:39-05:00 laptop: mise run agentgateway-deploy rows-down
+ 2026-11-17T05:38:39-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T05:38:39-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T05:38:39-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T05:38:39-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T05:38:40-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T05:38:40-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T05:38:40-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T05:38:40-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T05:38:40-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T05:38:43-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-17T05:39:00-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/walk-down-agent.json -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Reply with the word ready."}],"max_tokens":64} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-17T05:39:14-05:00 laptop: jq -c '{model, content: .choices[0].message.content}' .state/priority/walk-down-agent.json
+ 2026-11-17T05:39:20-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-17T05:39:20-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T05:39:20-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T05:39:20-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T05:39:20-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T05:39:20-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T05:39:20-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T05:39:21-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T05:39:21-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T05:39:21-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T05:39:24-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-17T05:39:54-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/walk-up-agent.json -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Reply with the word ready."}],"max_tokens":256} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-17T05:40:02-05:00 laptop: jq -c '{model, content: .choices[0].message.content}' .state/priority/walk-up-agent.json
+ 2026-11-17T05:40:08-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-17T05:37:56-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-17 · walkthrough steps 4 and 5: a budget Block and the UI

```text
+ 2026-11-17T05:40:27-05:00 laptop: mise run agentgateway-deploy bulk-budget-low
+ 2026-11-17T05:40:27-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T05:40:27-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T05:40:28-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T05:40:28-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T05:40:28-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T05:40:28-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T05:40:28-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T05:40:28-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T05:40:28-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T05:40:31-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-17T05:40:47-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bulk)" | curl -K - -sS -D - -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-17T05:40:53-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/go-ai)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-17T05:41:07-05:00 laptop: ssh -n gb10-2 "curl -sS --max-time 5 'http://127.0.0.1:3001/api/budgets/status?apiKeyName=bulk'" | jq -r '.budgets[] | one line each'
+ 2026-11-17T05:41:15-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-17T05:41:15-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T05:41:15-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T05:41:15-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T05:41:15-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T05:41:15-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T05:41:15-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T05:41:15-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T05:41:15-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T05:41:15-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T05:41:18-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-17T05:41:24-05:00 laptop: ssh -n gb10-2 "curl -sS --max-time 5 'http://127.0.0.1:3001/api/budgets/status?apiKeyName=bulk'" | jq -r '.budgets[] | one line each'
+ 2026-11-17T05:42:11-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T05:42:17-05:00 laptop: mise run gateway:ui
```

### 2026-11-17 · walkthrough step 6: the Framework reboot

```text
+ 2026-11-17T05:48:38-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T05:48:38-05:00 laptop: ssh gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-17T05:49:51-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T05:49:51-05:00 framework (architect): omarchy update, then sudo reboot (reported done by 05:49:51)
+ 2026-11-17T05:49:57-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/walk-fw-audio.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T05:50:08-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/walk-fw-audio.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T05:50:19-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/walk-fw-audio.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T05:50:21-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/walk-fw-embed.json -H Content-Type: application/json -d {"model":"embedding","input":"ready"} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-17T05:50:44-05:00 laptop: jq -c '{model, content: .choices[0].message.content}' .state/priority/walk-fw-audio.json; jq -c '{model, dims: (.data[0].embedding | length)}' .state/priority/walk-fw-embed.json
+ 2026-11-17T05:50:44-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-17T05:48:38-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-17T05:50:52-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T05:50:52-05:00 laptop: for p in 8001 8002; do ( until [[ $(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://framework:$p/health) == 200 ]]; do sleep 1; done; echo "framework:$p /health 200 at $(date -Is)" ) & done; wait
+ 2026-11-17T05:51:45-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T05:51:45-05:00 framework (architect): LUKS unlocked at the console (reported by 05:51:45)
+ 2026-11-17T05:52:42-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T05:52:42-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"embedding","input":"ready"} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-17T05:52:42-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T05:52:43-05:00 laptop: ssh -n gb10-2 "docker logs --timestamps --since 2026-11-17T05:48:38-05:00 agentgateway 2>&1" | awk "/ route=default\/(audio|embedding) / { o = \$1; for (i = 2; i <= NF; i++) if (\$i ~ /^(route|http\.status|gen_ai\.provider\.name|overflow)=/) o = o \" \" \$i; print o }" | tail -n 8
+ 2026-11-17T05:52:44-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-17T05:48:38-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-17 · after the review: the Azure deployments, the Framework, and the path

```text
+ 2026-11-17T06:10:38-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T06:10:38-05:00 laptop: az cognitiveservices account deployment list -g "$(sed -n "s/^AZURE_RG=//p" .state/azure/account.env)" -n "$(sed -n "s/^AZURE_ACCOUNT=//p" .state/azure/account.env)" --query "[].{deployment:name,model:model.name,version:model.version,sku:sku.name,capacity:sku.capacity,state:properties.provisioningState}" -o table
+ 2026-11-17T06:10:40-05:00 laptop: ssh -o BatchMode=yes framework 'uptime -p; uname -r; checkupdates 2>/dev/null | wc -l; docker --version; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'
+ 2026-11-17T06:10:40-05:00 laptop: for h in gb10-1 gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done
```

### 2026-11-17 · after the review: the rows' updates to v0.34.0

```text
+ 2026-11-17T06:19:36-05:00 gb10-1: cd ~/repos/spike-model-engines && time VLLM_MODEL=gpt-oss-120b-agent-fp8 host/engines vllm update
+ 2026-11-17T06:19:36-05:00 gb10-2: cd ~/repos/spike-model-engines && time VLLM_MODEL=gemma-4-26B-A4B-NVFP4-vision-gb10 host/engines vllm update
+ 2026-11-17T06:19:36-05:00 framework: cd ~/repos/spike-model-engines && time docker build -t spike-model-engines/vllm-openai-rocm-audio:v0.34.0 host/vllm-rocm-audio && time VLLM_MODEL=gemma-4-E4B-it-audio-framework host/engines vllm update && time VLLM_MODEL=granite-embedding-english-r2-framework host/engines vllm update
```

### 2026-11-17 · after the review: the password's rotation, its deploy, and the watch run

```text
+ 2026-11-17T06:19:43-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T06:19:43-05:00 laptop: pg_password_rotate
+ 2026-11-17T06:19:43-05:00 laptop: (umask 077 && openssl rand -hex 32 > .state/agentgateway/postgres-password.next)
+ 2026-11-17T06:19:43-05:00 laptop: printf "ALTER USER agentgateway WITH PASSWORD '%s';\n" "$(<.state/agentgateway/postgres-password.next)" | ssh gb10-2 'docker exec -i gateway-postgres-1 psql -U agentgateway -d agentgateway -q -v ON_ERROR_STOP=1 -v VERBOSITY=terse'
+ 2026-11-17T06:19:44-05:00 laptop: mv .state/agentgateway/postgres-password.next .state/agentgateway/postgres-password
+ 2026-11-17T06:19:44-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-17T06:19:44-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T06:19:44-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T06:19:44-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T06:19:44-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T06:19:44-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T06:19:44-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T06:19:44-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T06:19:44-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T06:19:44-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T06:19:48-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-17T06:19:48-05:00 laptop: mise run watch
```

### 2026-11-17 · after the review: the audio rerun

```text
+ 2026-11-17T06:29:48-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T06:29:48-05:00 laptop: mise run agentgateway-deploy rows-down
+ 2026-11-17T06:29:48-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T06:29:48-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T06:29:48-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T06:29:48-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T06:29:49-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T06:29:49-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T06:29:49-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T06:29:49-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T06:29:49-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T06:29:52-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-17T06:29:52-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-17T06:29:52-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T06:29:53-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T06:29:53-05:00 laptop: goai_tier -run '^TestAudioInResponsesRefused$' p5-audio-TestAudioInResponsesRefused audio
+ 2026-11-17T06:29:53-05:00 laptop: cd .state/priority/go-ai/. && AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v -run '^TestAudioInResponsesRefused$' ./integration/... 2>&1 | tee .state/priority/clients/p5-audio-TestAudioInResponsesRefused.log
+ 2026-11-17T06:29:53-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T06:29:53-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T06:29:53-05:00 laptop: goai_tier -run '^TestTranscribeChat$' p5-audio-TestTranscribeChat audio
+ 2026-11-17T06:29:53-05:00 laptop: cd .state/priority/go-ai/. && AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v -run '^TestTranscribeChat$' ./integration/... 2>&1 | tee .state/priority/clients/p5-audio-TestTranscribeChat.log
+ 2026-11-17T06:29:56-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-17T06:29:52-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-17T06:29:56-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-17T06:29:57-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T06:29:57-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T06:29:57-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T06:29:57-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T06:29:57-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T06:29:57-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T06:29:57-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T06:29:57-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T06:29:57-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T06:30:00-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
```

### 2026-11-17 · after the review: the post-upgrade smoke check

```text
+ 2026-11-17T06:40:06-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T06:40:06-05:00 laptop: for i in $(seq 25); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://gb10-1:8000/v1/chat/completions & done | sort | uniq -c
+ 2026-11-17T06:41:22-05:00 laptop: for i in $(seq 33); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://gb10-2:8000/v1/chat/completions & done | sort | uniq -c
+ 2026-11-17T06:42:08-05:00 laptop: for i in $(seq 9); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"audio","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://framework:8001/v1/chat/completions & done | sort | uniq -c
+ 2026-11-17T06:42:58-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-17T06:42:58-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-17T06:42:58-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-17T06:42:58-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-17T06:42:58-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p6-agent.json -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Reply with the word ready."}],"max_tokens":256} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-17T06:42:59-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-17T06:43:01-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p6-vision.json -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":[{"type":"text","text":"What color is this image? One word."},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"}}]}],"max_tokens":64} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-17T06:43:02-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p6-audio.json -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-17T06:43:03-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o .state/priority/p6-embed.json -H Content-Type: application/json -d {"model":"embedding","input":["gateway","routing"]} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-17T06:43:09-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T06:43:09-05:00 laptop: goai_tier p6-goai agent vision audio embedding
+ 2026-11-17T06:43:09-05:00 laptop: cd .state/priority/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/p6-goai.log
+ 2026-11-17T06:44:02-05:00 laptop: infer_tier p6-infer agent vision audio embedding
+ 2026-11-17T06:44:02-05:00 laptop: cd .state/priority/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/p6-infer.log
+ 2026-11-17T06:44:24-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-17T06:40:00-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-17 · after the review: two deploys back to back, for Postgres

```text
+ 2026-11-17T06:52:29-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T06:52:29-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-17T06:52:29-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T06:52:29-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T06:52:29-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T06:52:29-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T06:52:29-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T06:52:29-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T06:52:29-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T06:52:29-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T06:52:29-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T06:52:32-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-17T06:52:33-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-17T06:52:33-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-17T06:52:33-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-17T06:52:33-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-17T06:52:33-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-17T06:52:33-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-17T06:52:33-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-17T06:52:33-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-17T06:52:33-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-17T06:52:33-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-17T06:52:35-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
```

### 2026-11-17 · after the review: the rows' reading and the watch run

```text
+ 2026-11-17T06:57:39-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-17T06:57:39-05:00 laptop: for h in gb10-1 gb10-2 framework; do ssh -o BatchMode=yes $h "docker inspect --format \"{{.Name}} {{.Config.Image}} {{.State.StartedAt}} {{join .Args \\\" \\\"}}\" \$(docker ps -q --filter name=vllm)" | grep -oE "^\S* \S* \S*|--max-num-queued-reqs [0-9]*|--scheduling-policy \S*" | paste -sd" " | sed "s/^/$h /"; done; for hp in gb10-1:8000 gb10-2:8000 framework:8001 framework:8002; do printf "%s /health " $hp; curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://$hp/health; done
+ 2026-11-17T06:57:40-05:00 laptop: mise run watch
```
