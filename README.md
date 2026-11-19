# spike-model-gateway

Which gateway fronts the workstations' vLLM rows, and how is access to the model APIs restricted
without the tailnet? A spike of `experiment.hosting` in the Standards Lab reference architecture;
it gives evidence and decides nothing.

Its working context starts at [`context/README.md`](context/README.md).

## The answer

**Question:** Which gateway fronts the self-hosted vLLM layout, and with what access control?

**Answer:** agentgateway v1.7.0 on its route `ai` form, one base URL per purpose alias, with
gateway-issued keys that reach the serving endpoints only, per-key priority, buckets, and budgets,
embedding held to 34 requests a second by 429 and `Retry-After`, and overflow to Azure AI Foundry
for agent and vision only; admission on vLLM's `/metrics` stays a gap.

The decision and its configuration, as requirements for v1.ai.hosting, are in
[`docs/gateway.md`](docs/gateway.md), and the gateway comparison behind it in
[`docs/comparison.md`](docs/comparison.md). The evidence, numbered as
[`context/README.md`](context/README.md#the-evidence) frames it:

1. **Pass-through.** Chat, streaming, Messages, Responses, vision, audio, and embeddings pass
   through under purpose aliases with no answer crossed, each on its own `/<alias>/v1` whose
   `/models` lists exactly that alias. Against the same GuideLLM cells sent direct, the gateway
   adds nothing beyond run noise to agent, vision, or audio, and at most 3.4 ms (median) to an
   embedding request, the extra hop included, for under 3% of one core and under 35 MiB. Proven
   by [`agentgateway.md`](docs/findings/agentgateway.md), "Behavior 3" and slice 2's "Results"
   (vLLM v0.33.0, 2026-11-13), and the route `ai` and `llm` forms measured equal within noise in
   [`routing.md`](docs/findings/routing.md), "Behavior 9: the overhead cells" (2026-11-16).
2. **Keys and routes.** The gateway issues the keys; a missing, unknown, or revoked key gets 401,
   and a revoked key's running stream finishes. Only the eight serving paths are routed, so no
   vLLM management route is open to a consumer key. agentgateway doesn't normalize dot segments,
   so hardening is a requirement. Proven by [`agentgateway.md`](docs/findings/agentgateway.md),
   "Behavior 4" and "Behavior 5" (2026-11-13), and [`routing.md`](docs/findings/routing.md),
   "Realignment on route `ai`" (2026-11-16); a running demo, `mise run agentgateway-deploy`, whose
   deploy creates and revokes keys.
3. **Caps.** Past each cap, vLLM queues and never refuses, so a client sees only a longer wait
   (agent's ITL reached 108 ms at 16 sessions). Each row now refuses with 503 at twice its cap,
   which evicts it. The gateway's own refusals are 429 with `Retry-After` and `x-ratelimit-*` (a
   bucket) and 503 with no `Retry-After` (the in-flight limit, logged only in `requests_shed`).
   Proven by [`agentgateway.md`](docs/findings/agentgateway.md), "Behavior 8: the cap cells" and
   "Behavior 9: the probes" (2026-11-13), and [`priority.md`](docs/findings/priority.md), "The
   rows' limits" (2026-11-16).
4. **Admission.** agentgateway reads no row's `/metrics` and queues nothing itself: a gap, on
   paper, with what could fill it, and no candidate does it natively. Proven on paper by
   [`agentgateway.md`](docs/findings/agentgateway.md), "The paper inventory", and
   [`comparison.md`](docs/comparison.md), "Scoring".
5. **Embedding limit.** A global 34/1s bucket admitted 34 of a 40-request burst and 34.0 a second
   under 160 in flight, refusing the rest with 429 and `Retry-After: 1`; audio beside it held RTFx
   median 5.38 against its floor of 5. Proven by [`priority.md`](docs/findings/priority.md),
   "Embedding's limit (behavior 17)" and "Benchmark A: embedding limited, audio beside it
   (evidence 5)" (vLLM v0.33.0, 2026-11-16).
6. **Priority.** Each key has its own request-rate bucket and token budget per UTC clock hour in
   Postgres, charging streams and surviving a restart; bulk was refused by its bucket and its
   Block budget while go-ai kept answering. Chat held its floor beside bulk vision (agent ITL
   median 47.05 ms). Priority by key cut interactive vision's median latency from 11.87 s to
   10.47 s on a saturated row, 0.47 s short of 10 s, since vLLM's priority orders only the
   waiting queue. Proven by [`priority.md`](docs/findings/priority.md), "Slice 3 · keys and
   limits", "Benchmark B: chat beside bulk vision (evidence 6)", and "Benchmark D:
   priority on vision (evidence 6)" (vLLM v0.33.0, 2026-11-16); the `bulk-rate-low`,
   `bulk-budget-low`, and `priority-flat` overlays are its running demos.
7. **Overflow.** With a row down, each alias was answered by its Foundry deployment under the
   alias, marked `x-gateway-overflow: azure`, and returned to its row after; nothing failed over
   between hosts. Under saturation, a row's 503s with eviction sent nearly the whole load to
   Azure. Through the Framework's reboot, Azure answered its aliases until the LUKS unlock; each
   row answered again about 57 s and 58 s after it. Per alias, the parity gaps decide which
   workloads may leave: overflow is for agent (within the data zone) and vision (processed
   globally) only. Proven by [`priority.md`](docs/findings/priority.md), "A row down (behaviors 7,
   8)", "Benchmark C-agent (behavior 9)", "Per alias: the cloud model and its parity (behavior 12)",
   and slice 4's "Results" (2026-11-16 and 2026-11-17); a running demo, `mise run
   agentgateway-deploy rows-down`.
8. **Clients at go-ai v0.3.0.** go-ai's and infer's whole tiers passed through the gateway on all
   four aliases at `tools/infer/v0.2.0`, and again at the helpers' pin, `tools/infer/v0.3.0` (26
   and 19 passed, 0 failed, each time). The rest was measured at v0.2.0; v0.3.0 changes neither
   retry nor the formats. On Azure, every fix go-ai claimed for priority's discrepancies passed,
   and each declared gap skipped before sending. go-ai's live retry proof (its design finding 17):
   it retries the gateway's 429 and 503 and honours `Retry-After`; in the rate-limit case it needed
   one attempt more than the first `Retry-After` implied, which reads as rounded down. Proven by
   [`answer.md`](docs/findings/answer.md), "Step 2 · rows up (behavior 3)", "The revalidation
   (behaviors 4, 5)", and "Step 5 · the retry proof (behaviors 6–8)" (vLLM v0.34.0, 2026-11-18),
   and "At v0.3.0" (2026-11-19); by tests, [`retry/`](retry/retry_test.go), which `mise run check`
   vets; and the helpers `goai_tier`, `infer_tier`, and `retry_case` as running demos.
9. **Traces.** Each request through a row is one trace, the row's span the child of the gateway's;
   an overflowed request's trace has no row span; no span holds prompt or completion content; and
   each row's startup trace gives its cold start by phase, 13.0–50.0 s. Proven by
   [`answer.md`](docs/findings/answer.md), "Slice 2 · traces" (2026-11-18); a running demo,
   `mise run gateway:grafana`, with the helpers' `traces`.
10. **On paper.** The gateway comparison, LiteLLM as the feature reference beside Bifrost, Agent
    Router, Kong, Portkey, Helicone, and TensorZero (archived), with vLLM's production-stack
    router, Kubernetes portability, JWT/OIDC, production's Azure Container Apps routing, IL6, and a
    cheaper chat tier: nothing on paper beats agentgateway for this layout. In
    [`docs/comparison.md`](docs/comparison.md), every claim cited to its source, read 2026-11-18.
11. **The decision.** agentgateway fronts the stack, with its configuration as requirements for
    v1.ai.hosting, priority's gaps, and the notes for the intake, in
    [`docs/gateway.md`](docs/gateway.md).

Gaps in the answer, each in [`docs/gateway.md`](docs/gateway.md): admission on `/metrics`; a
sliding budget window; priority beyond queue order; a queue limit that counts every key alike;
eviction that sends nearly the whole load to Azure under saturation, with no cap on its growth; no
retry of a body over 64 KiB; the UI's Logs and Analytics reached only by URL; and the route `ai`
deprecation risk, watched in [`docs/watch.md`](docs/watch.md).
