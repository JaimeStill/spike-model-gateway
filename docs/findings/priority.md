# priority

What answers when a row is down or full, and how the gateway ranks, limits, and charges each key's
work: overflow from each row to its own Azure AI Foundry deployment under the same alias, per-key
priority, request-rate buckets and token budgets, and embedding held to 34 requests a second
(evidence 5–7 of [`context/README.md`](../../context/README.md#the-evidence)). This finding holds
slice 1, the setup; slice 2, the overflow and benchmark C; slice 3, the keys and limits and
benchmarks A, B, and D; and the walkthrough the architect runs as slice 4.

- **Measured:** 2026-11-16, from the laptop. Slice 1 ran 13:05–13:56 local time, slice 2
  14:17–14:41. Every command is under "Commands as run".
- **Gateway:** agentgateway v1.7.0, `cr.agentgateway.dev/agentgateway:v1.7.0`, on gb10-2, with its
  Postgres (`postgres:18.7-alpine`) in one compose project
  ([`gateway/compose.yml`](../../gateway/compose.yml)), configured from
  [`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml).
- **Rows:** vLLM v0.33.0, each row serving its alias as its only model name, from
  spike-model-engines `host/` at `2950b83`, the merge of its pull request #18.
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
| 9 | a row full: two 503s evict it for 5 s, and benchmark C reads what reaches Azure | 7 | 2 |
| 10 | go-ai's and infer's tiers through the rows-down overlay, and the infer CLI | 7 | 2 |
| 11 | the Framework down until `/health` after its LUKS unlock | 7 | 4 |
| 12 | per alias, the cloud model, its processing scope, and its parity gaps | 7 | 2 |
| 13–16 | per-key priority, request-rate buckets, token budgets in Postgres, and the request log | 6 | 3 |
| 17 | embedding held to 34 requests a second | 5 | 3 |
| 18–20 | at most 300 Azure-answered requests, the records, currency and the check | — | all |

## Method

**Steps.** The session runs every host step over Tailscale SSH with no root, each through the step
helpers, [`scripts/clients-lib.sh`](../../scripts/clients-lib.sh) and
[`scripts/measure-lib.sh`](../../scripts/measure-lib.sh), or the deploy,
[`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh), which log each command to
`.state/priority/commands-2026-11-16.log` before it runs. The architect runs the root steps (host
updates, the gb10-2 reboot) and the Azure walk, Foundry's first.

**Overflow.** Each alias route's `ai` backend has two priority groups: the alias's row, then its
Azure deployment. A request goes to the first group with a provider not evicted, so Azure answers
only while the row is out, and only for its own alias: nothing fails over between hosts. The row's
health policy evicts it after two consecutive unhealthy replies, a 503 or a failed connection, for
5 s; a route retry makes up to 2 more attempts on 503, each after a 20 ms backoff (the slice 2
escalation, below). Chat Completions,
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
no backoff still found the evicted row, and the request whose 503s evicted it got its 503; and a
5xx from the Azure provider evicts it for 3 s under agentgateway's default for several groups.

**The Azure cap.** Azure answers at most 300 requests in the task. After each step that can
overflow, the session reads `azure_count <since>`, which counts the access log lines marked
`overflow="azure"` per alias, so per deployment, and per status, and flags any 429 from Azure, a
stop condition. Only synthetic and test-fixture content is sent to Azure.

**Benchmark C.** Two GuideLLM cells through the gateway, run with `cell <name> <scenario> cap
<alias>` and read with `overflow_read <name>`: C-agent,
[`bench/overflow-agent.yaml`](../../bench/overflow-agent.yaml), 28 concurrent for 60 s; then
C-vision, [`bench/overflow-vision.yaml`](../../bench/overflow-vision.yaml), 36 concurrent for 60 s,
each sized to Azure's capacity (the slice 2 escalation, below).

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
container, though its definition hadn't changed. `request_logs` kept its rows: 183 at 14:17. Why
compose recreates Postgres on each deploy is still open, and slice 3's deploys will do the same.

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
| `TestAudioInResponsesRefused`, `TestTranscribeChat` | a large audio body gets 503 ("connection refused") while the row isn't yet evicted, as above |

Responses itself passed on agent (`TestChat/responses`). The brief expected it to fail on agent,
since `gpt-oss-120b` serves Chat Completions only. The gateway translates a Responses request into
Chat Completions for that provider, as it does Messages.

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
  (`TestChatIncompleteAtMaxTokens/messages`).
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
| eviction windows | about 28 a minute, estimated from the log's order |
| first refusal | 0.7 s after the benchmark's start |
| the row | running median 12, max 12; waiting median 0, max 12 |
| gateway CPU, median / max | 4.54% / 5.91% of one core; memory 80.5 / 83.1 MiB |

So a refused request does reach Azure: the 20 ms backoff lets the eviction land before the retry.
But under saturation the row's 503 with eviction sends nearly the whole load to Azure. Each
eviction opens a 5 s window in which every new request goes to the Azure group. Azure's
`gpt-oss-120b` throttled within seconds, and its 429s didn't evict it under the health policy
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
| agent | `gpt-oss-120b` | DataZoneStandard: within the data zone | refuses `tool_choice: required` and ignores a named function; an unknown model name succeeds; Responses is translated to Chat Completions, and a reply cut off at its limit reports `max_tokens`; a translated Messages stream reports 0 input tokens, and one at a 16-token limit didn't end within 15 s; no reasoning item at low effort through Messages; Azure's chat stream opens with an empty reply id and Responses adds its reasoning item in a form go-ai rejects (go-ai's to fix) |
| vision | `gpt-5-mini` 2025-08-07 | GlobalStandard: processed globally | refuses `max_tokens` (wants `max_completion_tokens`) and reasoning effort `none`; an unknown model name succeeds; the stream gaps above; called a red PNG "pink" where the row said "Red" |
| audio | `gpt-audio-mini` 2025-12-15 | GlobalStandard: processed globally | refuses a text-only chat; serves Chat Completions only; an audio body over 64 KiB isn't retried, so it gets the row's 503 until 2 failures evict the row |
| embedding | `text-embedding-3-small` | DataZoneStandard: within the data zone | another vector space at the same 768 dimensions; every reply is marked as overflow |

Which workloads may leave the self-hosted machines is the architect's call in `answer`. These
gaps are its inputs: agent and embedding stay within the data zone, while vision and audio are
processed globally. Only synthetic and test-fixture content was sent to Azure: the helpers'
prompts, a 1×1 PNG, go-ai's `phrase.wav` fixture, and GuideLLM's synthetic text.

### The Azure count

Counted from the access log after each step that can overflow:

| Step | Azure-answered | Toward the cap |
| --- | --- | --- |
| slice 1, direct | 5 | 5 |
| rows-down probes and the tiers, 14:32:54–14:36:38 | 76 (agent 50, vision 20, audio 2, embedding 4) | 76 |
| benchmark C-agent | 2,944 (429 ×2845, 400 ×99) | 99 |
| total | 3,025 | 180 of 300 |

The cap counts Azure's 2xx and its 4xx other than 429, since Azure refuses a 429 without
processing it (escalation 2). Azure's 2,845 429s are reported apart.

### Escalation 1 (2026-11-16)

Slice 2's rows-up checks passed; three questions went to the architect before benchmark C, and
were answered:

- **Retry backoff: 20 ms.** An eviction reaches the load balancer through a spawned task
  (`types/loadbalancer.rs`, `finish_request`) [src], so it lands asynchronously, and a retry sent
  with no backoff reaches the row again: on the laptop mock, the request whose two 503s evicted the
  row got its third 503 from the row. With 20 ms the same request went to Azure on its third
  attempt. The route retry (`&retry-503`) now sets `backoff: 20ms`; benchmark C is to show it live.
- **Azure provider health: the rows' policy.** Each `<alias>-azure` provider now carries
  `&row-health`: two 503s or failed connections in a row evict it for 5 s. It had none, so
  agentgateway's default for several groups held: one 5xx or failed connection evicted it for 3 s.
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
  503, a 429, or a failed connection, 2 in a row, evicts it for 5 s, so a throttling Azure leaves
  rotation. It was deployed as `2ba52b8` at 14:40:43 and passes `--validate-only`. It is not shown
  live: a live 429 needs Azure to throttle (about 60 counted requests on one deployment), and
  agentgateway logs no eviction.
- **The cap counts 2xx and non-429 4xx.** The count is 180 of 300 after C, with Azure's 429s
  reported apart. `azure_count` prints both.

## Slice 3 · keys and limits

Pending.

## Slice 4 · walkthrough

Pending.

## Commands as run

Every command the log holds, as logged, with its time, from
`.state/priority/commands-2026-11-16.log`. The output stays there, untracked. The two host reads
were logged as `<time>, laptop: <command>`, the rest as `+ <time> <host>: <command>`. The helpers
log curl's arguments joined by spaces, so a JSON body shows without its shell quotes. The
`mise run agentgateway-deploy` line is followed by the deploy's own `+` lines, from its output,
appended to the log by `tee -a`. The architect's reboot is logged as theirs.

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
