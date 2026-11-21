# spike-model-gateway

spike-model-gateway settles the gateway that sits between consumers and the workstations' vLLM
rows: gb10-1 serves the agent, gb10-2 vision, and the Framework audio and embedding, one row per
purpose with no failover. agentgateway, an Agentic AI Foundation project, is tried live from gb10-2.
LiteLLM, Bifrost, Agent Router, vLLM's production-stack router, and the rest are weighed on paper.
It gives evidence for the gateway v1.ai.hosting builds. The spike decides nothing itself.

The spike answers for experiment.hosting, and the coordinator's roadmap,
`standards-lab/roadmap/index.toml`, holds its work. Its question is framed in
`standards-lab/context/ai-hosting.md`. spike-model-layout's `docs/layout.md`, "Requirements for
spike-model-gateway", gives the requirements. Each capability in detail, the tasks in the order
they ran, and the repositories the spike reads are in
[`docs/capabilities.md`](../docs/capabilities.md).

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
   GuideLLM cells sent direct, in one session. Finding:
   [`agentgateway.md`](../docs/findings/agentgateway.md),
   [`routing.md`](../docs/findings/routing.md).
2. **Keys and routes.** Keys are issued by the gateway, and a missing or revoked key is refused. No
   vLLM management route is open to a consumer key. The network path to the rows is production's
   concern, for the networking and platform teams. Finding:
   [`agentgateway.md`](../docs/findings/agentgateway.md).
3. **Caps.** At each cap (agent 12, vision 16, audio 4, embedding 128): what queues, and what
   returns 429 or 503 with Retry-After, against go-ai's retry set. Finding:
   [`agentgateway.md`](../docs/findings/agentgateway.md).
4. **Admission.** Admission on vLLM's `/metrics` against static caps: what agentgateway does
   natively. Finding: [`agentgateway.md`](../docs/findings/agentgateway.md).
5. **Embedding limit.** Embedding held to 34 requests a second while audio holds RTFx ≥5. Finding:
   [`priority.md`](../docs/findings/priority.md).
6. **Priority.** Per-consumer budgets, rate limits, and priority: chat holds its floor while a bulk
   key saturates vision, and an interactive key's vision request ranks ahead of bulk's on the same
   row. Finding: [`priority.md`](../docs/findings/priority.md).
7. **Overflow.** Overflow to Azure AI Foundry under the same alias when a row is down or full; no
   failover between hosts; the Framework treated as down until `/health` answers after its LUKS
   unlock; and which workloads may leave the self-hosted machines. Finding:
   [`priority.md`](../docs/findings/priority.md).
8. **go-ai.** go-ai's integration tier, unchanged, through the gateway, with each `AI_*_BASE_URL`
   set to its purpose URL, and the released `infer` CLI's one-listed-model fallback. Finding:
   [`agentgateway.md`](../docs/findings/agentgateway.md),
   [`routing.md`](../docs/findings/routing.md), [`answer.md`](../docs/findings/answer.md).
9. **Traces.** agentgateway's OpenTelemetry traces. Finding:
   [`answer.md`](../docs/findings/answer.md).
10. **On paper.** A gateway comparison with LiteLLM as the feature reference (not tried live: its
    2026 supply-chain compromises and advisories, a Python runtime, single-vendor governance),
    Bifrost, Agent Router, Kong, Portkey, Helicone, and TensorZero (archived); vLLM's
    production-stack router, Kubernetes portability, JWT/OIDC, production's Azure Container Apps
    routing, IL6, and a cheaper chat tier. Finding: [`answer.md`](../docs/findings/answer.md), with
    the paper in [`comparison.md`](../docs/comparison.md).
11. **The decision.** Whether a gateway fronts the stack, which one, and its access control, with
    its configuration as requirements for v1.ai.hosting. Finding:
    [`answer.md`](../docs/findings/answer.md), with the paper in [`gateway.md`](../docs/gateway.md).

## Capability map

- **Gateway stack** (built): [`gateway/compose.yml`](../gateway/compose.yml), deployed by
  [`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh); reasoning in
  [`docs/stack.md`](../docs/stack.md).
- **Overflow, keys, priority, and limits** (built): [`docs/gateway.md`](../docs/gateway.md),
  configured in [`gateway/agentgateway/config.yaml`](../gateway/agentgateway/config.yaml), reasoning
  in [`docs/agentgateway-config.md`](../docs/agentgateway-config.md).
- **Traces** (built): [`docs/stack.md`](../docs/stack.md#the-collector).
- **Probe overlays** (built): [`gateway/agentgateway/probes/`](../gateway/agentgateway/probes/).
- **Retry test** (built): [`retry/`](../retry/), reasoning in [`docs/retry.md`](../docs/retry.md).
- **Step helpers** (built): [`scripts/`](../scripts/), reasoning in
  [`docs/scripts.md`](../docs/scripts.md); the GuideLLM cells in [`bench/`](../bench/README.md),
  sized in [`docs/bench.md`](../docs/bench.md).
- **Watch register** (built): [`docs/watch.md`](../docs/watch.md).
- **Gateway document and comparison** (built): [`docs/gateway.md`](../docs/gateway.md) and
  [`docs/comparison.md`](../docs/comparison.md).

## Rules

The experiment's rules, `standards-lab/docs/ai-hosting.md#experiment-rules`, govern every session.
