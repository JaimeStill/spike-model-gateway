# spike-model-gateway

spike-model-gateway settles the gateway that sits between consumers and the workstations' vLLM
rows: gb10-1 serves the agent, gb10-2 vision, and the Framework audio and embedding, one row per
purpose with no failover. agentgateway and LiteLLM are tried live from gb10-2. Agent Router, vLLM's
production-stack router, and the rest are weighed on paper. It gives evidence for the gateway
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
  `/<alias>/v1`, whose `/models` lists only that alias.
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
4. **Admission.** Admission on vLLM's `/metrics` against static caps: what each gateway does
   natively.
5. **Embedding limit.** Embedding held to 34 requests a second while audio holds RTFx ≥5.
6. **Priority.** Per-consumer budgets, rate limits, and priority: chat holds its floor while a
   bulk key saturates vision.
7. **Overflow.** Overflow to Azure AI Foundry under the same alias; no failover between hosts; the
   Framework treated as down until `/health` answers after its LUKS unlock; and which workloads may
   leave the self-hosted machines.
8. **go-ai.** go-ai's integration tier, unchanged, through the gateway, with each `AI_*_BASE_URL`
   set to its purpose URL, and the released `infer` CLI's one-listed-model fallback.
9. **Traces.** Each gateway's OpenTelemetry traces.
10. **On paper.** Agent Router, vLLM's production-stack router, Kubernetes portability, JWT/OIDC,
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
  ([`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh)) deploys agentgateway to
  gb10-2 from [`gateway/agentgateway/`](../gateway/agentgateway/config.yaml) and reloads its
  config in place.
- **Gateway keys:** the deploy creates each key the config names, kept untracked on the deploying
  machine, and sends gb10-2 a copy with each key's hash. Removing a name and deploying revokes it.
- **Probe overlays:** `gateway/agentgateway/probes/` holds one-off config changes (an access log
  field, a rate limit, an in-flight limit, a key header) that the deploy applies to the copy it
  sends; a deploy without them removes them.
- **Step helpers:** [`scripts/measure-lib.sh`](../scripts/measure-lib.sh) runs and reads the
  GuideLLM cells in [`bench/`](../bench/README.md), and
  [`scripts/clients-lib.sh`](../scripts/clients-lib.sh) runs go-ai's and infer's tiers, the infer
  CLI, and curl through the gateway, each with a key read from its file.
- **Planned:** LiteLLM's bring-up, admission on `/metrics`, per-key priority and budgets,
  embedding's rate limit, Azure AI Foundry overflow, OpenTelemetry traces through a Collector, and
  the gateway document, the decision and its configuration as requirements for v1.ai.hosting.

## Path

The tasks, in the order they run, each with the evidence it proves:

1. `agentgateway`: agentgateway v1.7.0 on gb10-2, with each row serving under its alias through a
   spike-model-engines `host/` pull request (evidence 1–4, 8). Its finding is
   [`docs/findings/agentgateway.md`](../docs/findings/agentgateway.md).
2. `litellm`: LiteLLM with Postgres virtual keys, on the same cells, with an agentgateway anchor
   cell (evidence 1–4, 8).
3. `priority`: Azure AI Foundry overflow, with priority and budgets on both gateways in one session
   (evidence 5–7).
4. `answer`: traces through an OpenTelemetry Collector, the paper sections, the gateway document,
   and the answer (evidence 9–11).

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
