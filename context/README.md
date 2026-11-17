# spike-model-gateway

spike-model-gateway settles the gateway that sits between consumers and the workstations' vLLM
rows: gb10-1 serves the agent, gb10-2 vision, and the Framework audio and embedding, one row per
purpose with no failover. agentgateway, an Agentic AI Foundation project, is tried live from gb10-2.
LiteLLM, Bifrost, Agent Router, vLLM's production-stack router, and the rest are weighed on paper. It gives evidence for the gateway
v1.ai.hosting builds. The spike decides nothing itself.

The spike is the sub-goal `experiment.hosting.spike-model-gateway` in the coordinator's roadmap,
`standards-lab/context/roadmap.toml`, where its tasks live. Its question is framed in
`standards-lab/context/ai-hosting.md`, under "Experiment: experiment.hosting", which holds the
experiment's rules and the answers of the earlier spikes. spike-model-layout's `docs/layout.md`,
"Requirements for spike-model-gateway", gives the requirements.

## The question

Which gateway fronts the self-hosted vLLM layout, and with what access control?

- It admits requests on each row's live `/metrics` per purpose floor, and queues past each cap.
- It holds embedding to 34 requests a second.
- It issues per-consumer keys with budgets, rate limits, and priority, so the capstone's chat stays
  responsive during a ~/docs-scale processing run.
- It names purposes by alias (agent, vision, audio, embedding). Each alias has its own base URL,
  `/<alias>/v1` on the gateway's one consumer port, whose `/models` lists only that alias, so go-ai
  and the `infer` CLI work unchanged.
- It overflows to Azure AI Foundry under the same alias when a purpose is full or its host is down.
- A consumer key reaches serving routes only, so no serving API manages models. Making the gateway
  the only network path to the rows is production's concern, for the networking and platform teams;
  in dev the rows stay reachable directly on the tailnet.

## The answer

The answer is in the top-level [`README.md`](../README.md#the-answer).

## The evidence

1. **Pass-through.** Chat, streaming, embeddings, and audio pass through under purpose aliases with
   no answer crossed, each on its own `/<alias>/v1` whose `/models` lists exactly that alias. The
   gateway's added TTFT, ITL, and latency, and its CPU and memory, are measured against the same
   GuideLLM cells sent direct, in one session.
2. **Keys and routes.** Keys are issued by the gateway, and a missing or revoked key is refused.
   No vLLM management route is open to a consumer key. The network path to the rows is
   production's concern, for the networking and platform teams.
3. **Caps.** At each cap (agent 12, vision 16, audio 4, embedding 128): what queues, and what
   returns 429 or 503 with Retry-After, against go-ai's retry set.
4. **Admission.** Admission on vLLM's `/metrics` against static caps: what agentgateway does
   natively.
5. **Embedding limit.** Embedding held to 34 requests a second while audio holds RTFx ≥5.
6. **Priority.** Per-consumer budgets, rate limits, and priority: chat holds its floor while a
   bulk key saturates vision, and an interactive key's vision request ranks ahead of bulk's on the
   same row.
7. **Overflow.** Overflow to Azure AI Foundry under the same alias when a row is down or full; no
   failover between hosts; the Framework treated as down until `/health` answers after its LUKS
   unlock; and which workloads may leave the self-hosted machines.
8. **go-ai.** go-ai's integration tier, unchanged, through the gateway, with each `AI_*_BASE_URL`
   set to its purpose URL, and the released `infer` CLI's one-listed-model fallback.
9. **Traces.** agentgateway's OpenTelemetry traces.
10. **On paper.** A gateway comparison with LiteLLM as the feature reference (not tried live: its
    supply-chain compromise and 2026 advisories, a Python runtime, single-vendor governance),
    Bifrost, Agent Router, Kong, Portkey, Helicone, and TensorZero (archived); vLLM's
    production-stack router, Kubernetes portability, JWT/OIDC,
    production's Azure Container Apps routing, IL6, and a cheaper chat tier.
11. **The decision.** Whether a gateway fronts the stack, which one, and its access control, with
    its configuration as requirements for v1.ai.hosting.

## Rules

The experiment's rules, in `ai-hosting.md`, govern every session. In short:

- **One new tool per task**, explained in its brief and walkthrough. A task has at most four
  slices, and the last is a walkthrough the architect runs before the next task is planned.
- **Guided sessions.** The session runs routine host steps that need no root over Tailscale SSH,
  and records them. Root steps, a new tool's first walk, and the last slice's walkthrough are the
  architect's.
- **Benchmarks.** GuideLLM 0.8.1 runs from the laptop (`mise.bench.toml`). Each run is agreed in
  its task's plan round and takes at most 10 minutes unless the brief decides otherwise.
- **Comparisons.** Only cells run in the same session compare. Every gateway cell has a direct
  anchor cell, and a task that compares against an earlier gateway reruns that gateway's anchor
  cell.
- **Engines.** The rows serve from spike-model-engines' `host/`. This spike changes it only through
  pull requests.
- **The dev gateway** runs on gb10-2. Claude-model workloads stay off the gateway.

## Capabilities

- **Gateway bring-up:** `mise run agentgateway-deploy`
  ([`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh)) deploys the gateway's
  compose project ([`gateway/compose.yml`](../gateway/compose.yml)), agentgateway and its Postgres,
  to gb10-2, with the config from [`gateway/agentgateway/`](../gateway/agentgateway/config.yaml)
  bind-mounted read-only, and reloads that config in place. It publishes the consumer port, 3000,
  on gb10-2's tailnet address, where one route per alias, each with an inline `ai` backend, serves
  `/<alias>/v1`. `mise run gateway:up`, `gateway:down`, and `gateway:reset` start the stack, stop
  it, and stop it and drop Postgres's volume, on gb10-2 over SSH. `mise run gateway:ui` tunnels the
  gateway's UI to the laptop's `localhost:3001`.
- **Overflow:** each alias route's `ai` backend holds two priority groups, the alias's row and then
  its Azure AI Foundry deployment, so Azure answers the alias, marked by an `x-gateway-overflow:
  azure` header, while the row is evicted after two 503s or failed connections. The routes type
  Chat Completions, Messages, Responses, and embeddings, and the gateway answers each alias's
  `/v1/models` itself.
- **Per-key priority and limits:** each key's name sets vLLM's request priority on the agent and
  vision rows, bulk behind the interactive keys. Each key has a request-rate bucket on each route
  and a token budget per UTC clock hour, kept in Postgres (Block on bulk, Audit on the others),
  which charges streams too. The embedding route holds a global 34 requests a second. Every
  request writes a metadata row, with no content, to the request log in Postgres, which the UI's
  Logs and Analytics pages show.
- **Gateway keys:** the deploy creates each key the config names, kept untracked on the deploying
  machine, and sends gb10-2 a copy with each key's hash. Removing a name and deploying revokes it.
  Secrets (Postgres's password, the Azure account's key and names) are markers in the config, filled
  in the same copy from untracked files.
- **Probe overlays:** `gateway/agentgateway/probes/` holds one-off config changes that the deploy
  applies to the copy it sends: `rate-limit-agent`, a request-rate limit on the agent route alone;
  `in-flight-1`, the in-flight limit at 1; `key-header`, keys read from `x-api-key`; `rows-down`,
  every row's provider at a closed port, so each alias overflows to Azure; `bulk-rate-low` and
  `bulk-budget-low`, bulk's request bucket and token budget lowered; and `priority-flat`, every
  key at bulk's priority on the rows. A deploy without them removes them. Each reply's Retry-After
  is in the access log without an overlay.
- **Step helpers:** [`scripts/measure-lib.sh`](../scripts/measure-lib.sh) runs and reads the
  GuideLLM cells in [`bench/`](../bench/README.md), and
  [`scripts/clients-lib.sh`](../scripts/clients-lib.sh) runs go-ai's and infer's tiers, the infer
  CLI, and curl through the gateway, each with a key read from its file. `gw_base <alias>` prints
  an alias's base URL, and `logged <command>` runs and logs a step that prints no key.
  `az_curl` sends one request straight to an Azure AI Foundry deployment, and `row_burst` sends a
  burst straight to a row. `azure_count` counts the requests Azure answered, from the gateway's
  access log; `budget_status` reads each key's token budget; and `request_log` reads the request
  log in Postgres. `audio_rerun` reruns go-ai's two audio tests on Azure with the audio row
  evicted first, and `pg_password_rotate` rotates Postgres's password. measure-lib.sh's
  `overflow_read` and `rtfx` read a cell's overflow and audio's real-time factor. The helpers keep
  their state and command log under `.state/priority/`.
- **Watch register:** [`docs/watch.md`](../docs/watch.md) tracks each dependency's anticipated
  capabilities, deprecations, and other changes. Its agentgateway entries track whether route
  `ai`, which the gateway relies on, is deprecated, and whether the `llm` section can serve several
  base URLs on one port, which would move the gateway to it. `mise run watch` is its read-only
  check of the entries' upstream issues and pull requests and release fields. It runs at every
  task's PLAN as its own block, beside `mise run currency` and separate from it.
- **Planned:** admission on `/metrics` (a gap on paper, for `answer`'s gateway document), OpenTelemetry traces through a Collector, and the gateway
  document, the decision and its configuration as requirements for v1.ai.hosting.

## Path

The tasks, in the order they run, each with the evidence it proves:

1. `agentgateway`: agentgateway v1.7.0 on gb10-2, with each row serving under its alias through a
   spike-model-engines `host/` pull request (evidence 1–4, 8). Its finding is
   [`docs/findings/agentgateway.md`](../docs/findings/agentgateway.md).
2. `routing`: trialled agentgateway's `llm` section, one port per alias, in place of the inline
   `ai` route backends its UI labels "legacy". The trial passed, and the go-ai and infer tiers
   passed through it unchanged (evidence 1, 8). The gateway then realigned on route `ai`, because
   agentgateway's docs recommend the routing form for path-based LLM routing; the `llm` form is
   under watch in [`docs/watch.md`](../docs/watch.md). Its finding is
   [`docs/findings/routing.md`](../docs/findings/routing.md), with the realignment under
   "Realignment on route `ai`".
3. `priority`: on agentgateway alone, on the route `ai` form, with Postgres beside it in one
   compose stack: overflow to Azure AI Foundry when a row is down or full, per-key priority,
   request-rate buckets, and token budgets counting streamed usage, the request log, embedding's
   limit, and the Framework down until `/health` (evidence 5–7). Its finding is
   [`docs/findings/priority.md`](../docs/findings/priority.md).
4. `answer`: traces through an OpenTelemetry Collector, the paper sections with the gateway
   comparison, the gateway document (dot-segment hardening among its requirements), and the
   answer (evidence 9–11).

## References

The spike reads these repositories and never writes to them, with one exception. experiment.hosting
owns spike-model-engines while the experiment runs, so this spike lists it in its repos and changes
its `host/` through pull requests, each citing the finding behind it. Each repository is a key in
the coordinator's `references.toml`, with its local checkout in `references.local.toml`:

- `spike-model-engines`: the rows' scripts and presets in `host/`.
- `spike-model-layout`: the requirements for this spike, the bench readers, and the step helpers.
- `spike-model-hosting`: the tool-reliability findings (bounded resample, parse-5xx fallback).
- `spike-hosting-upgrades`: the host descriptors.
- `go-ai`: the retry set and the integration tier.
