# Capabilities, path, and references

The spike's built capabilities in detail, the tasks it ran in order, and the repositories it reads.

## Capabilities

- **The gateway document and the comparison:** [`docs/gateway.md`](../docs/gateway.md) holds the
  decision and its configuration as requirements for v1.ai.hosting, priority's gaps, and the notes
  for the intake. [`docs/comparison.md`](../docs/comparison.md) weighs agentgateway against
  LiteLLM and the other candidates on paper, every claim cited to its source.
- **Gateway bring-up:** `mise run agentgateway-deploy`
  ([`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh)) deploys the gateway's
  compose project ([`gateway/compose.yml`](../gateway/compose.yml)) to gb10-2: agentgateway, its
  Postgres, and the OpenTelemetry Collector, Tempo, and Grafana that carry its traces. The config
  from [`gateway/agentgateway/`](../gateway/agentgateway/config.yaml) is bind-mounted read-only,
  and the deploy reloads it in place. The deploy publishes the consumer port, 3000, on gb10-2's
  tailnet address, where one route per alias, each with an inline `ai` backend, serves
  `/<alias>/v1`. agentgateway's stats port, 15020, stays on gb10-2's loopback. Every container
  restarts with the host unless it was stopped. `mise run gateway:up`, `gateway:down`, and
  `gateway:reset` start the stack, stop it, and stop it and drop its volumes (Postgres's, Tempo's,
  and Grafana's), on gb10-2 over SSH. `mise run gateway:ui` tunnels the gateway's UI to the
  laptop's `localhost:3001`, and `mise run gateway:grafana` tunnels Grafana to `localhost:3002`.
- **Overflow:** each alias route's `ai` backend holds two priority groups, the alias's row and then
  its Azure AI Foundry deployment, so Azure answers the alias, marked by an `x-gateway-overflow:
  azure` header, while the row is evicted after two 503s or failed connections. The spike's config
  overflows all four aliases; the gateway document allows agent and vision only
  ([`docs/gateway.md`](../docs/gateway.md), requirement 8).
  The routes type Chat Completions, Messages, Responses, and embeddings, and the gateway answers
  each alias's `/v1/models` itself.
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
- **Traces:** agentgateway sends a span for every request over OTLP gRPC to the Collector, which
  listens on gb10-2's tailnet address, port 4317, and forwards each span to Tempo. A row started
  with `VLLM_TRACE=on` through spike-model-engines' `host/` sends its own spans there too, so a
  request through a row is one trace, the row's `llm_request` span under the gateway's. No span
  holds prompt or completion content. Grafana's Explore page searches Tempo, and the helpers'
  `traces` prints each span's attribute keys, never their values.
- **Probe overlays:** `gateway/agentgateway/probes/` holds one-off config changes that the deploy
  applies to the copy it sends: `rate-limit-agent`, a bucket of 2 requests refilled every 10 s and
  shared by every key, as the first entry of the agent route's own per-key rate limits (the vision
  and audio routes share those rules, so each gets such a bucket of its own); `in-flight-1`, the
  in-flight limit at 1; `key-header`, keys read from `x-api-key`; `rows-down`, every row's provider
  at a closed port, so each alias overflows to Azure; `bulk-rate-low` and `bulk-budget-low`, bulk's
  request bucket and token budget lowered; and `priority-flat`, every key at bulk's priority on the
  rows. A deploy without them removes them. The deployed copy's first line names its overlays,
  `# overlays: none` without them. Each reply's Retry-After is in the access log without an overlay.
- **The retry test:** [`retry/`](../retry/retry_test.go) is a Go module that imports go-ai v0.4.0
  from the module proxy and records every attempt its client sends. Its four live cases,
  `rate-limit-agent`, `embedding-burst`, `in-flight-1`, and `bulk-rate-low`, each check what go-ai
  does with one of the gateway's 429s or 503s and its `Retry-After`. `retry_case <case>` runs one
  against the gateway; `mise run check` vets the module and runs its tests, every live case
  skipping.
- **Step helpers:** [`scripts/measure-lib.sh`](../scripts/measure-lib.sh) runs and reads the
  GuideLLM cells in [`bench/`](../bench/README.md), keeping its state and command log under
  `.state/priority/`. measure-lib.sh's `overflow_read` and `rtfx` read a cell's overflow and
  audio's real-time factor. [`scripts/clients-lib.sh`](../scripts/clients-lib.sh) runs the client
  steps through the gateway, each with a key read from its file, keeping its state and command log
  under `.state/max-tokens-note/`:
  - `goai_checkout` makes a worktree of go-ai at `tools/infer/v0.3.1`, and `infer_install`
    installs the released infer v0.3.1.
  - `goai_tier` and `infer_tier` run go-ai's and infer's integration tiers, with each alias's
    profile for `CLIENTS_TARGET` (`rows-up` or `rows-down`). `priority_rerun` reruns the tests
    priority's finding lists as failing on Azure, and `audio_rerun` reruns go-ai's two audio tests
    on Azure with the audio row evicted first.
  - `infer_at` and `infer_once` run the infer CLI, and `gw_curl` runs curl with a key. `gw_base
    <alias>` prints an alias's base URL.
  - `retry_case` runs one case of the retry test, and `requests_shed` reads the in-flight limit's
    refusals from the stats port.
  - `az_curl` sends one request straight to an Azure AI Foundry deployment, and `row_burst` sends
    a burst straight to a row. `azure_count` counts the requests Azure answered, from the
    gateway's access log; `budget_status` reads each key's token budget; `request_log` reads the
    request log in Postgres; and `traces` reads the traces in Tempo.
  - `messages_stream <alias> <max tokens> <prompt>` sends one streamed Messages request through
    the gateway and times each event from the send, to show whether the stream arrives as it is
    generated or whole.
  - `pg_password_rotate` rotates Postgres's password, and `logged <command>` runs and logs a step
    that prints no key.
- **Watch register:** [`docs/watch.md`](../docs/watch.md) tracks each dependency's anticipated
  capabilities, deprecations, and other changes. Its agentgateway entries track whether route
  `ai`, which the gateway relies on, is deprecated, and whether the `llm` section can serve several
  base URLs on one port, which would move the gateway to it. `mise run watch` is its read-only
  check of the entries' upstream issues and pull requests and release fields. It runs at every
  task's PLAN as its own block, beside `mise run currency` and separate from it. `mise run
  currency` also reports the helpers' go-ai tag and the retry module's go-ai version behind their
  latest.

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
4. `answer`: the clients at go-ai's `tools/infer` releases through the gateway, go-ai's live
   retry proof, traces through an OpenTelemetry Collector, the gateway comparison, and the gateway
   document with the answer (evidence 8–11). Its finding is
   [`docs/findings/answer.md`](../docs/findings/answer.md); the paper is
   [`docs/comparison.md`](../docs/comparison.md) and [`docs/gateway.md`](../docs/gateway.md).

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
