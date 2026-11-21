# The agentgateway configuration

This page gives the reasoning behind
[`gateway/agentgateway/config.yaml`](../gateway/agentgateway/config.yaml) and its probe overlays,
[`gateway/agentgateway/probes/`](../gateway/agentgateway/probes/), one section per part of the
config and per YAML anchor. Each part of the config points at its section with a `See` line. The requirements the configuration runs, and the findings that prove them, are in
[`gateway.md`](gateway.md).

**Sources.** agentgateway at the `v1.7.0` tag: its docs (`schema/config.md`, `schema/cel.md`,
`llm/configuration-modes.md`, `observability/access-logs/view.md`) and its source
(`crates/agentgateway/src/`, `crates/llm/src/`). **[src]** marks a reading of the source that no doc
states.

## The deployed copy

agentgateway v1.7.0 in front of the four vLLM rows, run on gb10-2 in the gateway's compose project
([`gateway/compose.yml`](../gateway/compose.yml)), which mounts the deployed copy's directory
read-only at /config; [`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh)
renders the copy and deploys the project. agentgateway watches the file and reloads it in place, so
a deploy that changes only this file needs no restart. Fields under `config` are read once, at
start.

## The routing form

The routing form serves the four aliases: one route per alias on the `consumer` gateway, port 3000,
each with an inline `ai` backend. Each alias's base URL is http://gb10-2:3000/<alias>/v1, which the
route rewrites to /v1 and sends to its row, or, while the row is evicted, to its Azure AI Foundry
deployment under the same alias ([Overflow groups](#overflow-groups)); its /v1/models is answered
by the gateway, listing that alias alone, whether the row is up or not. agentgateway's docs
recommend this form for path-based LLM routing (`llm/configuration-modes.md`). Task `routing`
trialled the `llm` section, one port an alias, and it passed, but the gateway stays on the
documented form while `llm` converges; the trial is in [`findings/routing.md`](findings/routing.md),
and [`watch.md`](watch.md) tracks what would move the gateway to `llm`.

## Serving paths

A consumer key reaches the serving endpoints only, the eight paths of the allow-list on each route
(`&not-serving`): /v1/models, chat/completions, completions, messages, responses, embeddings,
audio/transcriptions, and audio/translations. Every other path is answered 404 once the key is
admitted: by the route itself under /<alias>/v1, and as an unrouted path anywhere else. vLLM's root
routes (/metrics, /health, /tokenize, /docs) are among those refused. A missing, unknown, or revoked
key gets 401 on every path, before anything else.

The route's `directResponse` is read after the rewrite: route policies run in a fixed order, the URL
rewrite before the direct response (`proxy/httpproxy.rs`, `apply_request_policies`). An exact path
match can't do this: a prefix rewrite needs a prefix match (`http/filters.rs`). The first entry
whose condition holds answers:

- /v1/models, the alias alone, in OpenAI's list shape, from the gateway itself, whether the row is
  up or not, so a client that takes the one listed model (go-ai's tier, infer) gets the alias during
  an overflow too;
- any path off the serving allow-list, 404. /v1/models/<id> is left out: no client here reads one
  model.

## Admin API and UI

The admin API and its UI listen on the container's own loopback (`adminAddr`): no published port
reaches it. The config file is the only source of configuration (`storage.mode: readOnly`). The UI
reads it and can't write it: a save answers 403, so no key or route is ever created outside git.

The UI, read-only, has its own gateway and port, `ui` on 3001, published on gb10-2's loopback only
and reached through an SSH tunnel ([`stack.md`](stack.md#operating-the-stack)). It isn't the
consumer gateway, which isn't named `default`: the UI attaches itself to a gateway of that name when
`ui.gateways` is unset. The admin API's debug and shutdown endpoints stay on `adminAddr`.

## Database

The compose project's Postgres ([`gateway/postgres.yml`](../gateway/postgres.yml)), reached by its
service name on the project's network, keeps the request log and token budgets. agentgateway
connects at start, and compose starts it only once Postgres is healthy. The password is committed
only as a secret marker naming postgres-password, in the URL, which
[`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh) replaces in the copy it sends
with the password it keeps untracked under .state/agentgateway/. A comment never holds a marker: the
deploy refuses one.

## Tracing

agentgateway traces each request (the answer task's behavior 10): it exports a span over OTLP gRPC
to the compose project's OpenTelemetry Collector, reached by its service name on the project's network
([`gateway/otel-collector.yml`](../gateway/otel-collector.yml)), which forwards it to Tempo.
`randomSampling` starts a trace for every request that arrives without one; one that arrives with a
sampled traceparent is traced under it, `clientSampling`'s default. agentgateway sends the
request's traceparent on to the row, whose own span is then its child when the row traces
(spike-model-engines' host/vllm.env, `VLLM_TRACE`).

No prompt or completion content is added: agentgateway sends none by default (its
examples/llm-telemetry/tracing/openllmetry.yaml at v1.7.0: "By default, prompt and completions are
not sent"), and this config adds no tracing field and no `frontendPolicies.tracing` attribute. A
span may hold the caller's address and the endpoint, an overflow's the Azure account's host, as the
access log line does, so the trace reads print attribute keys, not values
([`scripts/clients-lib.sh`](../scripts/clients-lib.sh), `traces`). Read only at start: the config
section's hash label recreates the container when it changes
([`stack.md`](stack.md#agentgateway)).

## Access log

Every request's access log line carries fields of the reply's headers and of the key, each empty or
absent when there is none. Log fields only; they change no routing or limit
(`observability/access-logs/view.md`).

- `retry_after`, the reply's Retry-After: the only place a client's 429 or 503 shows it to a
  reader, since GuideLLM keeps a refused request's status but none of its headers.
- `overflow`, the reply's overflow marker: "azure" on every reply an Azure deployment answered, set
  by that provider's response header policy (`&overflow-marker`, [Azure provider](#azure-provider)),
  which the log reads after it applies. Beside the route, which names the alias and so the
  deployment, it is what the Azure request count reads
  ([`scripts/clients-lib.sh`](../scripts/clients-lib.sh), `azure_count`). `gen_ai.provider.name`,
  logged on every LLM request, reads `azure` there too (`providerOverride`), and `custom` on a
  row's. `endpoint` names the Azure account's host, so a quoted line has it replaced.
- `key_name`, the name of the key the request was admitted with (its `metadata.name`, which
  agentgateway flattens into `apiKey`; `schema/cel.md`), absent on a 401. It tells two runs on one
  alias apart, such as benchmark D's bulk and interactive runs, and shows which key a probe's 429
  refused ([`scripts/measure-lib.sh`](../scripts/measure-lib.sh) reads it).

## Request log

Every request also writes one row of `request_logs` in `config.database`, which the UI's Logs and
Analytics pages read. `llm: metadata` stores the request's metadata, usage, timing, and cost, and no
prompt or completion content: no `request_log_payloads` row is written (`telemetry/log.rs`,
`database_llm_payload`) [src]. The row carries every field of the access log line, the key's name
among them as `agw.api_key.name`, which agentgateway adds itself (`telemetry/log.rs`,
`api_key_name`) [src]; `agentgateway.user` is set to the key's name too, so it fills the row's
indexed `agentgateway_user` column, the user the UI's Logs and Analytics filter and group by
(`telemetry/log_store.rs`, `promoted_attribute_column`) [src]. A row also holds the caller's
address and the endpoint, as the access log line does, so a quoted row names its columns.

## Keys

The consumer port is published on gb10-2's tailnet address
([`deploy.env`](../gateway/agentgateway/deploy.env)). Every request on the port needs a
gateway-issued key, sent as a Bearer token, before any route is chosen: a missing, unknown, or
revoked key gets 401, on alias routes and unrouted paths alike. The key is removed before the
request is forwarded, so no row sees it.

Each key is a random 256-bit value kept on the deploying machine, under
.state/agentgateway/keys/<name>, untracked. Only the key names are committed: each entry's
`keyHash` is the marker `sha256:@@<name>@@`, and
[`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh) creates any missing key, then
sends gb10-2 a copy of the config with each marker replaced by its key's `sha256:<hex>`; a marker
never reaches gb10-2. Adding an entry and deploying issues a key; removing one and deploying revokes
it with no restart ([`findings/agentgateway.md`](findings/agentgateway.md), "Keys").

Four keys: architect, bench, and go-ai are interactive, and bulk is for batch work. Each key's
`metadata.name` is what every per-key policy reads: its priority on the agent and vision rows
([Priority by key](#priority-by-key)), its request-rate bucket on each route
([Request-rate buckets](#request-rate-buckets)), and its budget ([Token budgets](#token-budgets)).

## Token budgets

Each key has one budget, `tokens`, charged after each LLM reply with the reply's total tokens, input
and output (`http/budget/mod.rs`, `settle`) [src]. A streamed Chat Completions reply is charged too,
whether or not the client sent `include_usage`: the routes type it as `completions`, which adds
`include_usage` to every stream ([Typed formats](#typed-formats)). The counter is checked before
each request, so the request that crosses the limit is answered and charged, and the next one is
refused. Block refuses it with 429 and a Retry-After of the seconds left in the window; Audit only
logs `API key budget exceeded` and lets it through (`http/budget/mod.rs`, `check`; `proxy/mod.rs`)
[src]. The counters live in memory and are written to `config.database`'s `budget_usage` table every
5 s and at shutdown, and read back at start, so a count survives a gateway restart
(`http/budget/database.rs`) [src]. A budget is keyed by its key's hash and its name, so a reload
that changes a limit keeps the count; one that changes the window or the unit starts it again
(`BudgetCounter::configure`) [src]. Budgets on the gateway's own apiKey policy take effect as a
route's do: the gateway's policies are attached with the budget policy, and its budget runs right
after its key check (`types/local.rs`; `proxy/httpproxy.rs`, the gateway's request policies) [src].

The window: `rolling: 1h`, agentgateway's name for a fixed window aligned to the Unix epoch, here
each UTC clock hour, not a sliding one (`schema/config.md`), so a count starts again at each hour
and a Block's Retry-After is the time to the next hour. bulk Blocks at 1,000,000 tokens an hour:
above benchmarks B and D together, about 760 bulk vision requests (B's 150 s and D's two 120 s runs
at about 1.9 requests a second at 20 concurrent, 116 a minute in the agentgateway task's c-vision)
of about 580 tokens each (479 prompt, 100 output), some 440,000 tokens, run within one hour. The
interactive keys Audit at 5,000,000 an hour (`&audit-budget`): benchmark A's C-embed alone, 34
requests a second of 512 tokens for 90 s, is about 1,570,000. The
[bulk-budget-low](#bulk-budget-low) probe overlay lowers bulk's to 1 token, so its next request is
refused.

## Overflow groups

One route per alias. Each matches /<alias>/v1 and below, rewrites that prefix to /v1, and sends the
request to one `ai` backend of two priority groups: the alias's row first, then its Azure AI Foundry
deployment. A request goes to the first group with a provider not evicted, so Azure answers only
while the row is out: nothing fails over between hosts, only from a row to its own deployment (docs:
the Kubernetes failover page, "Self-hosted primary, cloud fallback"; standalone, `schema/config.md`
`routes[].backends[].ai.groups`). `groups` must be the `ai` backend's only key, or it parses as one
provider (`types/local.rs`, `LocalAIBackend`) [src], so the row's host and every policy sit on each
provider.

The route policies are the same on all four, anchored on agent's: the serving-path allow-list
([Serving paths](#serving-paths)) with /v1/models answered by the gateway, typed request formats,
a retry, and a request-rate bucket per key, each in its section below.

## Typed formats

Chat Completions, embeddings, Messages, and Responses are parsed as such (`&typed`), so the gateway
sets each provider's model in the body and its path (`detect` does neither for a JSON body:
`llm/mod.rs` `set_default_path`; `proxy/httpproxy.rs`) [src], and adds
`stream_options.include_usage` to every Chat Completions stream, so a stream's usage is read whether
or not the client asks (`llm/mod.rs`) [src]. The keys are path suffixes, matched longest first with
"*" last (`llm/policy/mod.rs`, `resolve_route`) [src]; the rest stay `detect`.

## Retry

A retry (`&retry-503`): up to 2 more attempts on a 503 or a failed connection, each after a 20 ms
backoff (`backoff`, a duration; `http/retry/mod.rs`) [src]. The provider is chosen again on each
attempt (`proxy/httpproxy.rs`) [src], so a retry reaches Azure once the row is evicted. An eviction
reaches the load balancer through a spawned task (`types/loadbalancer.rs`, `finish_request`) [src],
so a retry sent at once can still find the row; the backoff lets the eviction land, so the refused
request itself is carried to Azure. Against a mock row on the laptop, with no backoff the request
whose two 503s evicted the row got its third 503 from the row, and with 20 ms it went to Azure on
its third attempt; C-agent showed it live, 18 of 18. A body is buffered for a retry only up to
64 KiB (`MAX_BUFFERED_BYTES`); a larger one, such as a 1440p image, is sent once, unretried [src].

## Request-rate buckets

A request-rate bucket per key (`&key-rates` on agent, vision, and audio; embedding has its own,
[Embedding limits](#embedding-limits)): `localRateLimit` with `key: apiKey.name`, so each key's
requests draw on a bucket of their own, and one key's refusals leave another's untouched
(`schema/config.md`; the docs'
[Rate limiting](https://agentgateway.dev/docs/standalone/latest/documentation/configuration/resiliency/rate-limits/)
page, "Routing-based") (`http/localratelimit.rs`, `bucket`) [src]. A bucket counts requests, once
per client request, before the retry (`proxy/httpproxy.rs`) [src], and past it the gateway answers
429 with Retry-After and `x-ratelimit-*` itself; the row never sees the request, so a 429 evicts
nothing and sends nothing to Azure. The first entry whose condition holds is the request's
(`conditional`): bulk's, 600 requests a minute, then every other key's, 1,200 a minute, each a full
minute's worth at once and refilled each minute. Neither binds in normal use or the benchmarks:
bulk's heaviest is benchmark B's C-vision, 20 concurrent at about 1.9 requests a second (the
agentgateway task's c-vision at 20), 116 a minute; an interactive key's is O-audio, 64 requests in
about 20 s. The [bulk-rate-low](#bulk-rate-low) probe overlay lowers bulk's to 2 a minute, so
bulk's third request in a minute is refused while another key answers. Buckets are local to the
gateway process, and a reload that changes a rule starts it full.

## Row provider

The row's provider (`&row-formats`, `&row-health`): a custom provider at the row's host and port
over plain HTTP on the tailnet, listing the four typed formats, so each passes through unchanged; it
keeps the client's model, the alias, which each row serves as its only model name. Its health
policy (`&row-health`) marks a reply unhealthy on 503, the row's refusal once twice its cap is in
flight (`--max-num-queued-reqs`, spike-model-engines host/), or on a failed connection, where there
is no reply, so no `response.code` (`proxy/httpproxy.rs`, `finalize_attempt_for_retry`) [src]; two
in a row evict the row for 5 s, and each later eviction is longer, 5 s times the times it has been
evicted, with no cap (`http/health.rs`) [src].

## Priority by key

Priority by key (`&row-priority`, on the agent and vision rows' providers only): each request's body
is given vLLM's `priority` field from the key's name, 0 for an interactive key and 10 for bulk. Both
rows schedule by priority (`--scheduling-policy priority`, spike-model-engines host/), where a lower
value is served first, so interactive work is taken ahead of bulk's waiting requests.
`ai.transformations` sets a body field from a CEL expression after the request is parsed
(`schema/config.md`, `policies.ai.transformations`), and the expression reads the key: a provider's
policies are registered once the provider is chosen, before the request's snapshot, which keeps the
key's claims, so `apiKey.name` is in the expression's context (`proxy/httpproxy.rs`, "Provider
policies are only known once a provider is selected"; `cel/types.rs`, `new_llm`) [src]. The
provider's `ai` policy is merged field by field with the route's (`&typed`), so the route's `routes`
still apply (`store/binds.rs`) [src]. An expression that fails, such as one with no key, leaves the
field out (`llm/policy/mod.rs`, `apply_request_body_mutations`) [src].

It sits on the row's provider, not the route, so a request the Azure provider answers never carries
it: each attempt of a retry starts again from the client's body (`proxy/httpproxy.rs`, the retry
loop) [src], and the Azure provider has no transformation. On the laptop, against a capturing mock
row, bulk's chat reached the row with `"priority":10`, go-ai's with `0`, the audio row's with none,
and bulk's chat sent while the row was unreachable reached the Azure provider with none. vLLM reads
`priority` on Chat Completions, Completions, and Responses; the field is set on every typed request
to these two rows, Messages too, which the benchmarks and probes don't send. The
[priority-flat](#priority-flat) probe overlay sets every key to bulk's 10, benchmark D's control.

## Azure provider

The Azure provider (`&azure-policies`, `&azure-health`, `&overflow-marker`): an OpenAI-compatible
custom provider at the spike's Foundry account, https://<account>.services.ai.azure.com/openai/v1/<path>,
the endpoint each deployment was verified on, with the account's key in `api-key` (`backendAuth`)
on this provider alone, so no row ever sees it. agentgateway's `azure` provider reaches neither that
host and path: its `foundry` resource type builds /api/projects/<project>/openai/v1/ (a Foundry
project, which the account has none of), and `openAI` builds <account>.openai.azure.com
(`crates/llm/src/azure.rs`) [src]. A host override drops the provider's default TLS, so
`backendTLS: {}` restores it, with SNI and Host from the host (`proxy/httpproxy.rs`,
`apply_auto_hostname`) [src]. The account's name and key are committed only as the secret markers
azure-account and azure-key, which
[`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh) fills from .state/azure/ in
the copy it sends.

Each provider names its deployment as the model, lists only the formats that deployment serves (a
Messages request is translated to one of them; `llm/mod.rs`, `CHAT_TRANSLATIONS`) [src], and sets
`providerOverride: azure`, so the access log's `gen_ai.provider.name` reads `azure` on every request
Azure answers, and `custom` on a row's. Every reply from it carries `x-gateway-overflow: azure`
(`&overflow-marker`); a row's reply never does.

Its health policy is the row's, with a 429 added (`&azure-health`): two 503s, 429s, or failed
connections in a row evict it for 5 s, then 5 s times the evictions so far, with no cap, as a row's,
where agentgateway's default for an `ai` backend of several groups would evict it on one 5xx or
failed connection, for 3 s (`llm/mod.rs`; `http/health.rs`) [src]. The 429 is there because Azure
answers 429 when a deployment's capacity is spent, and benchmark C-agent (2026-11-16) showed an
Azure group that stays in rotation while it throttles takes the alias's whole load during each row
eviction. With both groups evicted, the load balancer picks an evicted provider rather than none
(`types/loadbalancer.rs`) [src], so a request can then reach a row that is still out; on the laptop,
a 502 the gateway made of a reply it couldn't parse evicted the mock Azure provider, and the next
request went to the refused row.

## Azure deployments

Each alias's deployment, and the formats it serves:

- agent: gpt-oss-120b, DataZoneStandard: Chat Completions only; Messages is translated to it.
- vision: gpt-5-mini 2025-08-07, GlobalStandard: Chat Completions and Responses; Messages is
  translated to Responses, the first translation listed for it.
- audio: gpt-audio-mini 2025-12-15, GlobalStandard: Chat Completions only, and only with audio in or
  out; a text-only chat is refused, a parity gap the finding records.
- embedding: text-embedding-3-small, DataZoneStandard: embeddings only.

## Embedding limits

Embedding's limits: the global 34 requests a second (the first rule, with no key, so every caller
shares its one bucket), and a bucket per key. The global bucket holds 34 and gets 34 back each
second, so it admits a burst of 34 and then 34 a second, and answers 429 with Retry-After past it
(`http/localratelimit.rs`; `proxy/mod.rs`) [src]. Its 429 is the gateway's own, before any backend,
so it evicts nothing and sends nothing to Azure. The per-key bucket is twice the global, so the
global binds first for any one key, and a request either rule refuses counts against neither
(`RateLimits::apply`) [src]. Embedding's clients send many small requests a second, so its key
buckets refill each second, where the chat routes' refill each minute
([Request-rate buckets](#request-rate-buckets)).

## Embedding dimensions

The row's vectors are 768 long (granite-embedding-english-r2), and text-embedding-3-small's are
1,536 unless asked: every request to Azure is set to 768, whatever the client sent, so an overflow
vector is the row's length. Its values are still from another vector space; the overflow marker
tells a client that stores vectors to refuse or re-route it.

## Probe overlays

Each overlay in [`gateway/agentgateway/probes/`](../gateway/agentgateway/probes/) is applied by
`scripts/agentgateway-deploy.sh <overlay>` to the copy it sends, never to config.yaml itself, and
removed by a deploy without it; the deploy script's header describes the `#@` directives.

### bulk-budget-low

The budget probe (the priority task's behavior 15): bulk's token budget lowered from 1,000,000
tokens an hour to 1, so once bulk has been charged any tokens in the current hour, its next request
is refused with 429 and a Retry-After of the seconds left in the hour; the budget is Block. The
request that crosses it is answered: a budget is checked before a request and charged after its
reply (`http/budget/mod.rs`) [src]. The count is kept: a changed limit keeps a budget's counter, so
bulk's tokens so far in the hour count against the 1. It replaces the one line of bulk's amount in
config.yaml's gateway apiKey policy. Once removed, bulk is admitted again, its count unchanged. Its
429 is the gateway's own, so it sends nothing to Azure.

### bulk-rate-low

The per-key bucket probe (the priority task's behavior 14): bulk's request-rate bucket on the agent,
vision, and audio routes lowered from 600 requests a minute to 2, so bulk's third request within a
minute is answered 429 with Retry-After by the gateway, while another key's bucket, 1,200 a minute,
keeps answering on the same alias. Each route's bucket is its own, so bulk has 2 a minute on each.
It replaces the two lines of bulk's entry in config.yaml's `&key-rates`, which the vision and audio
routes alias. A rule's buckets start full when a reload changes it. Its 429 is the gateway's own, so
it evicts nothing and sends nothing to Azure.

### in-flight-1

The 503 probe: the global in-flight limit, `frontendPolicies.http.maxConcurrentRequests`, at 1, so a
second request while one runs is refused. It counts per bind (each gateway's port), HTTP/1 requests
and HTTP/2 streams alike, and is checked as a request arrives on a connection, before any key,
route, or backend: the refusal is 503 "request limit exceeded" with no Retry-After, and leaves no
access log line, only the `requests_shed` metric (`crates/agentgateway/src/proxy/gateway.rs`,
`request_admission`; `proxy/mod.rs`). A connection takes the frontend policies live when it opens,
so the probe's curls, each a new connection, see it once the reload lands. Inserted into
config.yaml's `frontendPolicies`, beside its access log field.

### key-header

The one-off header case (the agentgateway task's behavior 10): the consumer gateway reads each key
from the `x-api-key` header, the whole value, in place of `Authorization: Bearer <key>`. The same
keys are admitted; a Bearer request gets 401 while it is applied. Inserted into config.yaml's
gateway apiKey policy, beside its mode and keys (`apiKey.location.header`: name and an optional
prefix; `schema/config.md`). Removing it restores Bearer.

### priority-flat

Benchmark D's control (the priority task's behavior 13): every key's requests carry bulk's priority,
10, on the agent and vision rows, so an interactive request is scheduled as bulk's are. The rows'
priority comes from config.yaml's `&row-priority`, a CEL expression on the key's name; this overlay
replaces it with the constant 10, on both rows' providers at once, since the vision row's is an
alias of the agent row's. A request to Azure still carries none. Removing it restores priority by
key. It sends nothing to Azure.

### rate-limit-agent

The 429 probe (the agentgateway task's behavior 9, and the answer task's retry case
rate-limit-agent): a local request-rate limit on the agent route, small enough that a handful of
requests trips it. Its bucket holds 2 requests and gets 2 back every 10 s, so the third request
within a 10 s window answers 429 with `retry-after` (the seconds to the next refill, at least 1) and
`x-ratelimit-limit`, `-remaining`, and `-reset`; an admitted reply carries the `x-ratelimit-*`
headers too (`crates/agentgateway/src/proxy/mod.rs`, ProxyError's response;
`http/localratelimit.rs`). No `key`, so every caller of the route shares the one bucket.

It is the first entry of the route's own `localRateLimit` (`&key-rates`), its condition always true,
so every request's bucket is this one, ahead of the per-key entries (the first entry whose condition
holds is the request's); the config's check refuses an entry with no condition anywhere but last. A
top-level policy attached to route default/agent doesn't apply: the route's inline
`localRateLimit` takes its place, so every reply carried the go-ai key's bucket, x-ratelimit-limit
1200 (the answer task, 2026-11-18). The vision and audio
routes alias `&key-rates`, so the probe limits each of them too, each route with a bucket of its
own; the retry case sends to agent alone. Its 429 is the gateway's own, so it evicts nothing and
sends nothing to Azure; each reply's Retry-After is in the access log without an overlay
([Access log](#access-log)).

### rows-down

The row-down probe (the priority task's behavior 7, and the tiers' overflow run, behavior 10): every
row's provider points at a closed port on its own host, 8009, which no row or service listens on, so
each connection to a row is refused while the rows themselves keep running. A refused connection is
unhealthy to each row's health policy ([Row provider](#row-provider)); after two in a row the row is
evicted, and each alias is answered by its Azure AI Foundry deployment under the alias, as when a
row is really down. The row's host stays its own, so nothing fails over between hosts. The overlay
replaces each row provider's `hostOverride`, a key YAML can't hold twice, with a `replace`
directive. A deploy without it returns each alias to its row once the row's eviction ends (5 s,
longer after repeated evictions).

Every request sent while it is applied reaches Azure and counts against the task's cap of
Azure-answered requests: 300 in the priority task, 80 in the answer task
([`scripts/clients-lib.sh`](../scripts/clients-lib.sh), `azure_count`).
