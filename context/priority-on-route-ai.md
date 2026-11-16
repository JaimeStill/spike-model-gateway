# What route `ai` offers task `priority`

This note maps each of task `priority`'s needs to what agentgateway v1.7.0 offers on the routing
form the gateway runs: one route per alias, each with an inline `ai` backend. It is research for
priority's plan round, not validated work: nothing here has run except where marked live.

- **Sources:** agentgateway/website `main` (the latest docs, 1.7.x), read 2026-11-16, and
  agentgateway's source and `schema/config.md` at the `v1.7.0` tag. Doc paths are the website's
  standalone pages, except where marked Kubernetes. **[src]** marks a reading of the source that
  no doc states.
- **Assumes** the rows keep queueing when full rather than answering 429 or 503, as vLLM does.

## Overflow to Azure when a row is down

Native. An `ai` backend takes priority groups, `routes[].backends[].ai.groups[].providers[]`
(`schema/config.md`, 5245ff); when every provider in a group is evicted, requests go to the next
group. Only the Kubernetes docs show it (`assets/agw-docs/pages/agentgateway/llm/failover.md`, tab
"Self-hosted primary, cloud fallback"); the standalone failover docs cover the `llm` section's
virtual models alone (`documentation/llm/virtual-models.md`).

- **Eviction.** With more than one group and no health policy, a single 5xx or connection failure
  evicts the provider for 3 s, longer on repeats (`llm/mod.rs:88-98`; `http/health.rs`,
  `DEFAULT_EVICTION_SECS`, multiplicative backoff with no cap). A provider's
  `policies.health.{unhealthyExpression, eviction}` (`schema/config.md`, 5356–5362) replaces the
  defaults, and is needed to evict on 429 or 503; `eviction: {}` keeps the default timing. The
  Kubernetes docs call the expression `unhealthyCondition`.
- **Retry.** A route retry, `routes[].policies.retry` (4975), reaches the next group only once the
  failing provider is evicted; the provider is chosen again on each attempt
  (`proxy/httpproxy.rs:2647-2690`) [src].
- **Shape [src].** `ai:` parses as groups only when `groups` is its only key
  (`types/local.rs:1573-1602`), so `ai.routes`, `backendAuth`, health, and the model name go on
  each provider's `policies` or on the route's. Azure's key goes on its own provider: a
  route-level `backendAuth` would reach the vLLM row too. The fixture
  `crates/agentgateway/src/types/local_tests/llm_config.yaml` shows per-provider `backendAuth`.
- **Model name.** Each provider's `provider.<type>.model` replaces the client's model; Azure's is
  `azure: {resourceName, resourceType: foundry|openAI, projectName, model: <deployment>}`
  (`integrations/llm/providers/azure.md`).
- **Typed route types [src].** Under `detect`, the gateway neither rewrites the path to the
  provider's API path (`llm/mod.rs:1349-1386`) nor sets the provider's model in a JSON body, only
  in a multipart one (`proxy/httpproxy.rs:2935-2944`, `model_router.rs:1093`). So overflow to Azure
  needs chat typed `completions` and embeddings typed `embeddings`.

## Overflow when a row is full

Nothing documented on the routing form. A provider can be evicted on load only if the row answers
429 or 503 when full, through `unhealthyExpression: "response.code == 429 || response.code == 503"`
with eviction and a route retry on those codes; the whole row then leaves for the eviction time.
vLLM queues instead, so nothing signals until a timeout. The alternatives don't fit:

- Providers in one group share load by latency with a pending-request penalty
  (`load-balancing.md`; `types/loadbalancer.rs:1056`), which
  sends Azure traffic always, not on overflow.
- Weighted route backends are static; conditional and callout virtual models are `llm`-only; an
  `ext_proc` destination applies only to `dynamic:` backends; the Inference Gateway's
  `inferenceRouting` targets services, not `ai` providers; and
  `frontendPolicies.http.maxConcurrentRequests` refuses across the whole port.

## Streamed usage

Under `"*": detect`, a streamed chat carries usage only if the client sends
`stream_options.include_usage`: `process_detect_request` forwards the body unchanged and parses
usage only when present (`llm/mod.rs:2186`; `crates/llm/src/types/detect.rs`) [src]. The docs
and the 1.7 release notes say Chat Completions streams always include usage, with no caveat for
the route type. The realignment
confirmed it live: without `include_usage` the stream had no usage chunk, and its access log line
no `gen_ai.usage.*` fields ([`docs/findings/routing.md`](../docs/findings/routing.md),
"Realignment on route `ai`"). Non-streamed replies carry usage.

The `completions` route type sets `include_usage` on every stream
(`llm/mod.rs:1801-1830`). The keys of `routes[].policies.ai.routes` are path suffixes, matched
longest first with `*` last (`llm/policy/mod.rs:794-809`), so priority can weigh:

```yaml
ai:
  routes:
    /v1/chat/completions: completions
    /v1/embeddings: embeddings
    "*": detect
```

A `custom` provider must then list `completions` and `embeddings` in `custom.formats`. The docs
show the same pattern with `passthrough` (`documentation/llm/api-types/passthrough.md`). The always-passthrough
entry in [`docs/watch.md`](../docs/watch.md) applies once a route type is typed.

## Per-key rate limits

Native: `routes[].policies.localRateLimit[]` (`schema/config.md`, 4668–4675;
`documentation/configuration/resiliency/rate-limits.md`, "Routing-based" tabs) takes `maxTokens`,
`tokensPerFill`, `fillInterval`, `type: requests|tokens`, and a CEL `key`. `key: apiKey.name`
gives each key its own bucket, since a key's metadata fields are flattened into `apiKey`
(`cel.md:51`). Each rule holds up to 65,536 buckets, per gateway process.
`budget-limits/rate-limit.md` still says a local limit is gateway-wide rather than per user, which
`key` contradicts.

## Budgets

Native on the route's own `apiKey` policy, though only the `llm` docs show it:
`routes[].policies.apiKey.keys[].budgets[]` (`schema/config.md`, 4783–4790), each with `name`,
`limit {unit: USD|Tokens, amount}`, `window {rolling}`, and `onBudgetExceeded: Block|Audit`.

- It needs `config.database` and each key's `metadata.name`; a USD limit also needs
  `config.modelCatalog`.
- A reply is charged after it completes, so an exhausted budget blocks the next request. One
  counter exists per key and budget (`http/budget/mod.rs:298`), and a charge needs total tokens or
  a cost (`budget/mod.rs:493-506`) [src]: a streamed `detect` request without `include_usage` is
  never charged.
- The budget must sit on the route's inline `apiKey` (`types/local.rs:5729-5739`) [src]: a
  top-level policy targeting a route with `apiKey` fails until #3827 (open) merges.

## Priority

Nothing native for `ai` backends. Prompt criticality exists only in the Inference Gateway's
endpoint picker (EPP), on Kubernetes or as a standalone sidecar. Separate per-key buckets and
conditional limits can stand in for it.

## Embedding at 34 requests a second

A request limit on the embedding route: `localRateLimit: [{maxTokens: 34, tokensPerFill: 34,
fillInterval: 1s, type: requests}]`. It allows a burst of 34, answers 429 past it, and counts per
gateway process.
