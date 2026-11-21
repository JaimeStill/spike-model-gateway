# The gateway

The spike's decision and its configuration, written as requirements for v1.ai.hosting (evidence 11
of [`context/README.md`](../context/README.md#the-evidence)). Each requirement cites the finding
that proved it, or says that it stands on paper. The spike's configuration,
[`gateway/agentgateway/config.yaml`](../gateway/agentgateway/config.yaml), deployed by `mise run
agentgateway-deploy`, runs these requirements with two differences, each named where it applies:
it still overflows audio and embedding to Azure, which requirement 8 forbids, and it has no
dot-segment hardening, which requirement 4 asks for.

## The decision

**agentgateway v1.7.0 fronts the four vLLM rows, on its route `ai` form, with one base URL per
purpose alias.**

- **The gateway.** agentgateway v1.7.0 (`cr.agentgateway.dev/agentgateway:v1.7.0`), an Apache-2.0
  proxy in Rust, a Linux Foundation project hosted by the Agentic AI Foundation. It runs in one
  compose stack with Postgres, which keeps its budgets and request log, and with the OpenTelemetry
  Collector, Tempo, and Grafana, which carry its traces.
- **The form.** One route per alias, each with an inline `ai` backend. agentgateway's docs
  recommend this routing form for path-based LLM routing
  ([`routing.md`](findings/routing.md), "Realignment on route `ai`"). The `llm` section passed a
  live trial in task `routing` and is the fallback ("The deprecation risk", below).
- **The base URLs.** Each purpose has its own, `/<alias>/v1` on the gateway's one consumer port
  (agent, vision, audio, embedding), whose `/models` lists that alias alone. go-ai and the infer
  CLI work through it with only the base URL and key changed
  ([`agentgateway.md`](findings/agentgateway.md), "Behavior 3"; [`answer.md`](findings/answer.md),
  "Step 2 · rows up (behavior 3)", and at go-ai v0.3.0, "At v0.3.0"). One thing
  doesn't come through: the served model's `root` (requirement 1, "`root` through the gateway").
- **Access control without the tailnet.** Gateway-issued keys that reach the serving endpoints
  only. Making the gateway the only network path to the rows is production's concern, for the
  networking and platform teams; in dev the rows stay reachable directly on the tailnet.
- **Why agentgateway.** It is the only candidate the spike weighed that has shown five of the six
  question bullets live, and the only one whose open-source edition serves per-alias base URLs,
  each with its own `/models` ("The comparison", below).

## Requirements for v1.ai.hosting

### Routes and keys

1. **One route per alias on route `ai`.** Each route matches `/<alias>/v1`, rewrites it to `/v1`,
   and sends it to the alias's row. The gateway answers each alias's `/v1/models` itself, listing
   that alias alone, whether the row is up or not. Chat Completions, Messages, Responses, and
   embeddings are typed request formats, so the gateway sets each provider's model and path, and
   adds `include_usage` to every Chat Completions stream. Proven:
   [`agentgateway.md`](findings/agentgateway.md), "Behavior 3";
   [`routing.md`](findings/routing.md), "Realignment on route `ai`";
   [`priority.md`](findings/priority.md), "Answer for this task".

   **`root` through the gateway.** The clients work unchanged through the gateway (above, "The
   base URLs"), but each alias's `/models` is the gateway's own answer,
   `{"id":"<alias>","object":"model","owned_by":"gateway"}`, so go-ai v0.3.0's `Model.Native` and
   `infer models`' root column carry no served model, while the row's own listing gives `root`
   (`openai/gpt-oss-120b` on gb10-1). Whether to pass `root` through or keep it hidden is
   v1.ai.hosting's call, and v1.ai.client should know that `Native` carries no `root` through the
   gateway. Proven: [`answer.md`](findings/answer.md), "At v0.3.0".
2. **Gateway-issued keys, by hash.** The committed config names each key; the deploy creates a
   missing key, keeps it untracked, and fills its hash into the copy it sends. Removing a name and
   deploying revokes the key: new requests on it get 401, and a running stream finishes. A
   missing, empty, or unknown key gets 401 before routing. Proven:
   [`agentgateway.md`](findings/agentgateway.md), "Behavior 4".
3. **Serving endpoints only.** Each route allows the eight serving paths (`/v1/models`,
   `chat/completions`, `completions`, `messages`, `responses`, `embeddings`,
   `audio/transcriptions`, `audio/translations`) and answers every other path 404. vLLM's root
   routes (`/metrics`, `/health`, `/tokenize`, `/docs`) are refused, so no consumer key manages a
   model. The admin API stays on the container's loopback, and the UI is read-only. Proven:
   [`agentgateway.md`](findings/agentgateway.md), "Behavior 5";
   [`routing.md`](findings/routing.md), "Realignment on route `ai`".
4. **Dot-segment hardening.** agentgateway doesn't normalize dot segments:
   `/agent/v1/../../metrics`, `/agent/v1/%2e%2e/%2e%2e/metrics`, and `/agent/v1/..%2f..%2fmetrics`
   matched the agent route and reached gb10-1. vLLM's own 404 is what protects its root routes
   there, not the gateway. v1.ai.hosting refuses `..` and its encodings (`%2e%2e`, `%2f`) before
   routing, natively: a CEL `authorization` rule with `deny`, or an anchored regex path match on
   each route. A network rule can't cover it, since these requests come from the gateway itself.
   Proven: [`agentgateway.md`](findings/agentgateway.md), "Behavior 5" and "The paper inventory".
   The hardening itself is on paper: the spike didn't configure it.

### Limits and priority

5. **Per-key priority, buckets, and budgets.** Each key's name sets vLLM's request `priority` on
   the agent and vision rows (0 for the interactive keys, 10 for bulk). Each key has a
   request-rate bucket on each route (600 a minute for bulk, 1,200 for the others), answered with
   429, `Retry-After`, and `x-ratelimit-*` by the gateway, so a bucket's refusal evicts nothing
   and sends nothing to Azure. Each key has a token budget per hour in Postgres (1,000,000, Block,
   for bulk; 5,000,000, Audit, for the others), which charges streams and survives a restart.
   Every request writes a metadata row to the request log, with no content. Proven:
   [`priority.md`](findings/priority.md), "Slice 3 · keys and limits" and "Benchmark D: priority
   on vision (evidence 6)". Priority's gaps are below.
6. **Embedding past 34 requests a second answers 429 with `Retry-After: 1`, and the client
   waits.** A global 34/1s bucket on the embedding route admits a burst of 34, then 34 a second,
   and refuses the rest. Beside it, audio held RTFx median 5.38 against its floor of 5, so no paced
   bucket is needed. go-ai v0.2.0 retries each 429 after its `Retry-After` and gets 200. This
   replaces spike-model-layout's requirement 3, "Requests past the rate queue or overflow"
   ([`docs/layout.md`](https://github.com/JaimeStill/spike-model-layout/blob/main/docs/layout.md#requirements-for-spike-model-gateway)):
   the gateway neither queues nor overflows them. Proven:
   [`priority.md`](findings/priority.md), "Embedding's limit (behavior 17)" and "Benchmark A:
   embedding limited, audio beside it (evidence 5)"; [`answer.md`](findings/answer.md), "Step 5 ·
   the retry proof (behaviors 6–8)", case b.
7. **Each row refuses when full, and its refusals evict it.** Each row's vLLM queue limit is twice
   its cap (agent 24, vision 32, audio 8; embedding none), past which it answers 503. Two 503s or
   failed connections in a row evict the row for 5 s, and each later eviction is longer. A route
   retry on 503 waits 20 ms and sends a request at most 3 times (`attempts: 2`). Proven:
   [`priority.md`](findings/priority.md), "The rows' limits" and "Benchmark C-agent (behavior 9)";
   the retry and eviction values in [`config.yaml`](../gateway/agentgateway/config.yaml)
   (`&retry-503`, `&row-health`).

### Overflow

8. **Overflow to Azure AI Foundry for agent and vision only.** Each of the two aliases' `ai`
   backends holds two priority groups, its row and then its own Foundry deployment, so Azure
   answers under the alias while the row is evicted. Each Azure provider is evicted on two 503s,
   429s, or failed connections in a row, so a throttling deployment leaves rotation. Nothing fails
   over between hosts. Proven with a row down: [`priority.md`](findings/priority.md), "A row down
   (behaviors 7, 8)"; with the Framework rebooted and locked, "Results" under "Slice 4 ·
   walkthrough".
   - **agent** overflows to `gpt-oss-120b`, DataZoneStandard, processed within the data zone.
   - **vision** overflows to `gpt-5-mini` 2025-08-07, GlobalStandard, processed globally.
   - **Never audio.** `gpt-audio-mini` is processed globally, refuses a text-only chat, and serves
     Chat Completions only. On overflow, audio in a Responses request is refused by the gateway's
     own typed parser (400, "failed to parse Responses request").
   - **Never embedding.** `text-embedding-3-small` at 768 dimensions is another vector space, so
     nothing the row indexed may be searched with its vectors.
   - **Never under IL6.** Each alias keeps only its row's group, and a down row answers with its
     failure ([`comparison.md`](comparison.md), "IL6").

   The spike overflowed all four aliases, to gather the parity evidence
   ([`priority.md`](findings/priority.md), "Per alias: the cloud model and its parity (behavior
   12)"); the restriction to agent and vision is the answer task's decision (goal record, R1 Q8).
9. **The embedding overflow marker.** Every reply an Azure deployment answers carries
   `x-gateway-overflow: azure`, and the access log records it. Embedding gets no Azure group
   (requirement 8); should a deployment give it one, as the spike's did, a client that stores
   vectors must refuse or re-route a marked reply. Proven: [`priority.md`](findings/priority.md),
   "A row down (behaviors 7, 8)".

### Traces

10. **Authenticated OTLP ingress, and sampling below 100%.** The spike's Collector takes spans on
    gb10-2's tailnet address with no authentication, and both agentgateway and the rows sample
    every request. Production authenticates the receiver (mTLS or a bearer token) or binds it where
    only the gateway and the rows reach it, and samples at a ratio, or by tail at the Collector.
    Proven: [`answer.md`](findings/answer.md), "For production".

    What the traces showed ([`answer.md`](findings/answer.md), "Slice 2 · traces"):

    - **A request through a row is one trace of 3 spans.** The gateway's server span, its client
      span to the row, and the row's `llm_request` as that client span's child, carried by
      `traceparent`. Each row's tracing is optional, on through spike-model-engines' `host/`
      (`VLLM_TRACE=on`).
    - **No span holds content.** The gateway's and the rows' spans carry usage, latency, and
      routing keys only: no `gen_ai.prompt`, `gen_ai.completion`, or message key. A span may hold
      the caller's address and the endpoint, an overflow's the Azure account's host.
    - **An overflowed trace has no row span.** Each refused attempt to the row and Azure's answer
      is its own client span under the one server span.
    - **vLLM's startup traces give each row's cold start by phase.** From `Overall Loading`: agent
      46.2 s (its weights' load 17.8 s), vision 31.3 s, audio 50.0 s (warmup 20.5 s), embedding
      13.0 s, one restart each, weights cached. They cover the engine's start, not the
      container's before it ("The rows' startup traces and cold start").

### Clients

11. **The live retry proof.** go-ai v0.2.0, at infer's default policy (3 attempts, 500 ms base,
    30 s most), retries the gateway's 429 and 503 and honours `Retry-After`: a rate limit's 429s
    retried after their `Retry-After`, then 200; embedding's 429s, `Retry-After: 1`, each retried
    once, then 200; the in-flight limit's 503, with no `Retry-After`, retried after go-ai's
    backoff, then 200 (its test allows 5 attempts, for the jitter, and used 2); and a
    `Retry-After` past the 30 s most returned at once. Proven:
    [`answer.md`](findings/answer.md), "Step 5 · the retry proof (behaviors 6–8)", by the retry
    test in [`retry/`](../retry/retry_test.go), cross-checked against the access log and
    `requests_shed`. This is go-ai's design finding 17, handed to this spike by v1.ai.client's
    acceptance.
12. **The gateway's `Retry-After` is rounded down, so a client allows one attempt more.** In the
    rate-limit case, the first 429 said `Retry-After: 2`; go-ai waited 2,001 ms and got a second
    429 saying 1; it waited 1,000 ms more and got 200 on its third and last attempt. The bucket's
    `Retry-After` reads as the whole seconds to its refill, rounded down, so waiting exactly that
    long can be refused once more. The times bear this out; agentgateway's source wasn't read.
    Embedding's 429s, at `Retry-After: 1`, each passed on the first retry. A client policy sized
    from the arithmetic alone has no attempt to spare. Proven: [`answer.md`](findings/answer.md),
    "Step 5 · the retry proof (behaviors 6–8)", case a.
13. **Clients declare the Azure deployments' gaps.** At go-ai v0.2.0, a profile declares what a
    provider refuses, so the request is refused before sending: agent's
    `{"completions":{"no_tool_choice_required":true}}` and vision's refused efforts. Every fix go-ai
    claimed for the Azure streams passed through the gateway. Proven:
    [`answer.md`](findings/answer.md), "The revalidation (behaviors 4, 5)".

### Admission

14. **Admission on `/metrics` is a gap, on paper.** Nothing in agentgateway reads a row's
    `/metrics`, and nothing queues at the gateway; vLLM queues behind it, up to its queue limit
    (requirement 7). The in-flight limit is one count per port, answered 503 with no
    `Retry-After`, and logged nowhere but `requests_shed`. What could fill it, native or existing
    first: the Inference Extension's endpoint picker, which selects replicas rather than admits
    by purpose; then an authored `extAuthz` or `extProc` service reading `/metrics`. The embedding
    row's running and waiting gauges read 0 under load, so an admission rule on them would see an
    idle row. No candidate in the comparison does it natively; Agent Router comes closest, through
    the llm-d endpoint picker on Kubernetes. Proven: [`agentgateway.md`](findings/agentgateway.md),
    "The paper inventory" and "Behavior 8: the cap cells"; [`comparison.md`](comparison.md),
    "Scoring".

## Priority's gaps

What agentgateway v1.7.0 doesn't do for priority, each with its finding and, where it has one,
its watch entry in [`watch.md`](watch.md):

- **A sliding budget window is wanted.** v1.7.0's `rolling: 1h` is a fixed UTC clock hour: a count
  starts again at each hour, a key can spend twice its budget across the boundary, and a Block's
  `Retry-After` is the time to the next hour (`retry-after: 2609`). Watch: "agentgateway budgets
  over a sliding window". Finding: [`priority.md`](findings/priority.md), "bulk's budget Block
  (behavior 15)".
- **Priority orders only vLLM's waiting queue.** Interactive vision beside a saturating bulk key
  missed 10 s by 0.47 s with priority (10.47 s, against 11.87 s without): the request jumps the
  queue, then shares the batch with bulk's streams. Holding interactive latency under bulk load
  needs more, such as a cap on bulk's concurrency. Finding: [`priority.md`](findings/priority.md),
  "Benchmark D: priority on vision (evidence 6)".
- **The queue limit counts every key alike.** vLLM's `--max-num-queued-reqs` doesn't know a key,
  so a bulk flood also refuses interactive requests, which then overflow. Finding:
  [`priority.md`](findings/priority.md), "The rows' limits" and "Answer for this task".
- **Under saturation, eviction sends nearly the whole load to Azure, and its growth has no cap.** A
  full row's 503s evict it, and every request in the eviction's window goes to Azure: in
  benchmark C-agent, 2,944 requests reached Azure in 60 s, the row answering 89. Each eviction
  lasts 5 s times the evictions so far, with no cap until a reload, so after a long outage or
  overload a row can stay out for minutes after it is back. Watch: "agentgateway eviction growth
  without a cap". Finding: [`priority.md`](findings/priority.md), "Benchmark C-agent (behavior 9)".
- **A body over 64 KiB isn't retried, and each attempt to a powered-down host costs about 11 s.**
  The gateway buffers 64 KiB for a retry, so vision images and audio clips get the row's 503 until
  two failures evict it; with the Framework powered down, each of those attempts waited out a
  connect timeout. Finding: [`priority.md`](findings/priority.md), "A row down (behaviors 7, 8)" and
  "Per alias: the cloud model and its parity (behavior 12)".
- **The UI's Logs and Analytics are reached only by URL.** The sidebar links them only when the
  config has an `llm` section, so on route `ai` they load at `/ui/llm/logs` and
  `/ui/llm/analytics`. Watch: "agentgateway UI links Logs and Analytics only with an `llm`
  section". Finding: [`priority.md`](findings/priority.md), "Results" under "Slice 4 ·
  walkthrough".
- **The route `ai` deprecation risk.** The UI labels inline `ai` backends "legacy", the client
  docs moved to the `llm` section (website#1091), and since 1.7 the Kubernetes model form is the
  recommended one (#4307); agentgateway has no deprecation policy (#2767) and deprecated `binds`
  without parity (#3204). The docs still recommend the routing form for path-based routing. The
  guard is the watch register, `mise run watch` at every task's PLAN ("agentgateway route `ai`
  backends deprecated"); the fallback is the `llm` form, one port per alias, which passed its live
  trial ([`routing.md`](findings/routing.md), "Final verdict" and "Realignment on route `ai`").

**The gateway's own translation gaps on overflow,** for an upstream issue the architect files, not
go-ai's to fix: a Responses reply cut off at its limit reports `incomplete_details.reason`
`max_tokens`, where the API says `max_output_tokens`; an unknown model name succeeds, since the
Azure provider sets the deployment as the model; and audio in a Responses request is refused by
the typed parser (requirement 8). Finding: [`answer.md`](findings/answer.md), "The revalidation
(behaviors 4, 5)".

## The comparison

[`comparison.md`](comparison.md) weighs agentgateway against LiteLLM, the feature reference, and
Bifrost, Agent Router, Kong AI Gateway, Portkey, Helicone, and TensorZero, on the six question
bullets, from sources read on 2026-11-18. Its conclusion: nothing on paper beats agentgateway for
this layout. The nearest rivals are Agent Router, Kubernetes-first and scoping `/models` by host;
Bifrost, with its admin API open by default and critical RCEs; and LiteLLM, whose 2026 record
stands against it. What would change the decision: production moving to Kubernetes with replicas
per purpose, agentgateway deprecating route `ai` without parity, admission on `/metrics` becoming
a hard requirement, or an advisory against agentgateway's LLM path.

It corrects three framings the spike started from:

- **LiteLLM had two supply-chain compromises in 2026, not one.** In March, litellm 1.82.7 and
  1.82.8 on PyPI carried a credential stealer; on 2026-10-21, litellm 1.107.0 was published by
  LiteLLM's own pipeline after an attacker took an owner's token. The advisories of 2026-09-30,
  2026-10-27, and 2026-11-12 are separate ([`comparison.md`](comparison.md), "Candidates").
- **Azure Container Apps is in audit scope for FedRAMP High and DoD IL2, not IL6.** Production's
  Container Apps routing service doesn't carry over to IL6, which needs another host for it, such
  as AKS ([`comparison.md`](comparison.md), "IL6").
- **Keyless Foundry is unproven here.** agentgateway documents reaching Azure OpenAI from
  Container Apps with a managed identity, through its `azure` provider. The spike used `custom`
  providers with a key, since the `azure` provider builds neither the verified Foundry host nor its
  path ([`comparison.md`](comparison.md), "Production's Azure Container Apps routing").

## The layout's requirements

How the answer meets spike-model-layout's requirements for this spike
([`docs/layout.md`](https://github.com/JaimeStill/spike-model-layout/blob/main/docs/layout.md#requirements-for-spike-model-gateway)):

| Layout requirement | The answer |
| --- | --- |
| 1. Admission on the engines' live signals, per purpose floor | A gap, on paper (requirement 14) |
| 2. Queueing past each row's cap | vLLM queues past each cap up to twice it, then refuses with 503, which evicts the row (requirement 7). The gateway itself queues nothing. One host serves the agent, so a session's turns stay on it |
| 3. Embedding at most 34 requests a second | Held by a global bucket; past it, 429 with `Retry-After: 1` and the client waits, in place of "queue or overflow" (requirement 6) |
| 4. Overflow to cloud models | agent and vision only, when the row is down or evicted as full (requirement 8). Audio, with no headroom above its target of 4, refuses past its queue limit and doesn't overflow |
| 5. Model management only through the gateway, never a serving API | Consumer keys reach the serving endpoints only (requirement 3), with dot-segment hardening (requirement 4). Row lifecycle stays with `host/` and experiment.admin |
| 6. No failover | Each alias's backend holds its row and at most its Azure deployment; nothing routes to another host's row ([`priority.md`](findings/priority.md), "A row down (behaviors 7, 8)") |
| 7. The Framework down until its console unlock | While it was locked, its rows' failed connections evicted them and Azure answered audio and embedding. After the reported unlock, `/health` came in about 4 s (embedding) and 49 s (audio), and each row answered the first request sent to it about 57 s and 58 s after, each a lower bound ([`priority.md`](findings/priority.md), "Results" under "Slice 4 · walkthrough"). With requirement 8, a locked Framework's aliases answer with the row's failure instead |

## Operational notes for the intake

- **The compose stack's config bind-mount.** The gateway's config is bind-mounted read-only into
  its container, an exception to `~/architecture`'s compose convention, for the intake to weigh for
  the capstone's stack ([`gateway/compose.yml`](../gateway/compose.yml)).
- **`BUILDX_NO_DEFAULT_ATTESTATIONS=1`.** [`gateway/compose.sh`](../gateway/compose.sh) exports it:
  Compose v5.2.0 ignores `provenance: false`, and on Docker's containerd image store each build's
  new attestation changes the image id, so compose recreated the built service on every `up
  --build`. The convention may want the same ([`priority.md`](findings/priority.md), "Why Postgres
  was recreated").
- **The Foundry account is kept.** The spike's Azure AI Foundry account and its four deployments
  stay until v1.ai.client's acceptance ships; experiment.hosting's intake deletes them.
- **Which workloads may leave the self-hosted machines,** from the per-alias parity gaps
  ([`priority.md`](findings/priority.md), "Per alias: the cloud model and its parity (behavior
  12)"; [`answer.md`](findings/answer.md), "The revalidation (behaviors 4, 5)"):
  - **agent,** within the data zone: tool-calling workloads that need `tool_choice: required` or a
    named function break on Azure (refused, or ignored), and a Messages request at low effort gives
    no reasoning item. go-ai v0.2.0 declares the `required` gap on Chat Completions; Messages and
    Responses pass Azure's 400 through.
  - **vision,** processed globally, so its overflowed content leaves the data zone: it refuses
    `max_tokens` (wanting `max_completion_tokens`) and reasoning effort `none`, which the profile
    declares on Chat Completions and Responses but not Messages; and it called a red PNG "pink"
    where the row said "Red".
  - **audio and embedding** stay on the Framework (requirement 8).
- **The cold start.** vLLM's startup traces give each row's cold start by phase (requirement 10),
  a measured figure for v1.ai.hosting's restart and capacity notes.
