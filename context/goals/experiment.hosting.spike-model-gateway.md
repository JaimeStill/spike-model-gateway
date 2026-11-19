# goal · experiment.hosting.spike-model-gateway

- **State:** brief ready
- **Task:** answer
- **Branch:** answer

## Tasks

1. [x] agentgateway
2. [x] routing
3. [x] priority
4. [ ] answer
5. [ ] max-tokens-note

## Task brief · answer

```
Goal          experiment.hosting.spike-model-gateway · task 4/4 · answer
Branch        answer
Repos         spike-model-gateway (root); spike-model-engines, host/ only,
              through one pull request that cites this task's finding
Problem       Priority settled the gateway's form, but the spike can't
              answer yet:
              - The step helpers pin go-ai's tools/infer/v0.1.0, and
                currency doesn't see it. v1.ai.client released go-ai
                v0.2.0 and tools/infer/v0.2.0 to fix the discrepancies
                priority found, and nothing has checked those fixes
                through the gateway.
              - v1.ai.client's acceptance handed this spike go-ai's live
                retry proof (its design finding 17): retry proven against
                the gateway's 429, 503, and Retry-After. Today only unit
                tests prove it.
              - The gateway exports no traces, so nobody can see a
                request's path through the gateway to its row.
              - The paper sections, the gateway document, README's
                answer, and the answer section don't exist yet.
              This is the spike's last task, so its merge syncs the
              answer into the coordinator.

              New tool: the OpenTelemetry Collector, the vendor-neutral
              agent that receives telemetry over OTLP, processes it, and
              exports it to backends. It runs as one service in the
              gateway's compose stack on gb10-2. agentgateway and the four
              vLLM rows send it spans over OTLP gRPC, and it forwards them
              to Tempo, which stores them; you search them in Grafana.
              Tempo and Grafana are pinned as go-web-service's
              observability profile pins them, so they count as known
              tools. In slice 2 the session walks you through the
              Collector: what its receivers, processors, exporters, and
              pipelines do, and what one trace looks like from the
              gateway down to a row.
Behaviors
  Clients at go-ai v0.2.0 (evidence 8)
  1. The step helpers run go-ai's and infer's tiers from a worktree at
     tools/infer/v0.2.0, and install the released infer at v0.2.0. Each
     tier run clears every role's MODEL and PROFILE beside its base URL
     and credentials. It also sets each alias's profile for what answers
     it:
     - rows up: the agent row's documented vLLM 0.34.0 profile;
     - rows down, agent: {"completions":{"no_tool_choice_required":true}};
     - rows down, vision: {"completions":{"refused_efforts":["none",
       "xhigh","max"]},"responses":{"refused_efforts":["none","xhigh"]}}.
     infer called by hand clears INFER_PROFILE. A probe that needs a
     single send passes --retries 1, since infer now retries by default.
     State and the command log go under this task's own state directory.
  2. `mise run currency` reports the helpers' go-ai tag when a newer
     tools/infer tag exists, and reports nothing for it at v0.2.0.
  3. With the rows up, go-ai's and infer's whole tiers pass through the
     gateway on all four aliases. Any failure is a finding, and no Azure
     request is sent.
  4. With the rows-down overlay, the tests that failed in priority rerun
     as a -run selection, then the audio rerun runs. The finding records
     each priority discrepancy beside the go-ai or infer change that
     claims it, the expected result, and the result:
     Expected to pass (go-ai's fixes):
     - Azure's chat stream whose first chunk has an empty id (v0.1.1);
     - a Responses reasoning item added with content (v0.1.1);
     - reasoning_tokens at the usage's top level (v0.1.1);
     - TestStreamText/messages: a translated Messages stream's input
       tokens, read from message_delta (v0.2.0).
     Expected as a declared skip (UnsupportedError, Declared true):
     - tool_choice required on agent completions: the function-call,
       reasoning round-trip, and allowed_tools-required tests;
     - effort none on vision.
     Expected as the provider's or the gateway's error passed through:
     - tool_choice required on agent Messages and Responses, which the
       gateway translates for Azure;
     - a named function ignored;
     - an unknown model accepted;
     - Responses' incomplete reason max_tokens;
     - audio in a Responses request, refused by the gateway;
     - the 16-token Messages stall;
     - gpt-audio-mini's refusal of a text-only chat.
     TestTranscribeChat passes after the audio rerun's warm-up.
  5. A change that claims a fix but still fails is recorded in the
     finding, and a pending edit for v1.ai.client names it. It doesn't
     stop the task unless a tier can't run at all.
  Retry proof (go-ai's finding 17)
  6. A Go test in the spike imports go-ai v0.2.0 from the module proxy,
     read-only, and builds its client with ai.New over an *http.Client
     that records every attempt: status, headers, body marker, and time.
     The policy is infer's default: 3 attempts, 500 ms base, 30 s most.
     The key comes from its file and never appears in argv or output. A
     case passes only if:
     - every refused attempt carries a marker only the gateway sends;
     - a later attempt of the same call answers 200;
     - the wait before it is at least the refusal's Retry-After, if any.
     `mise run check` vets it.
  7. The four cases, each with the rows up and no request to Azure:
     a. the rate-limit-agent overlay: a 429 with Retry-After and
        x-ratelimit-*, retried, then 200 from the agent row;
     b. embedding's global 34/s limit, hit with a 40-request burst:
        each 429 (Retry-After 1, x-ratelimit-*) is retried, then 200;
     c. the in-flight-1 overlay, with the test holding one request
        open: a 503 "request limit exceeded" with no Retry-After,
        retried after backoff, then 200;
     d. the bulk-rate-low overlay: a Retry-After past the 30 s maximum
        is returned at once, not retried.
     A header timeout or an idle-close seen in a run is recorded. A
     case that fails follows behavior 5's rule.
  8. Each case is cross-checked against the gateway: the access log's
     retry_after lines for the 429s, and requests_shed for the 503s.
     The stats port, 15020, is published on gb10-2's loopback and read
     over SSH.
  Traces (evidence 9)
  9. The gateway's compose stack adds three service groups, each built
     from its own Dockerfile whose FROM line is its pin, all at
     go-web-service's pins:
     - the Collector, 0.165.0: its OTLP gRPC port published on gb10-2's
       tailnet address, with its health check unpublished;
     - Tempo, 3.1.1: unpublished, with a named volume;
     - Grafana, 13.3.1: on 127.0.0.1:3002, with Tempo provisioned as
       its datasource.
     A mise task tunnels Grafana to the laptop's localhost:3002.
     `mise run currency` reads the three pins, the stack restarts with
     the host unattended, and every earlier check still passes.
  10. agentgateway exports traces to the Collector, with random sampling
      on. A request through each alias appears in Grafana as a trace.
  11. The host/ pull request adds optional per-row tracing: the
      Collector's endpoint on gb10-2, gb10-2 resolved at run time, and
      a service name per alias. Detailed traces stay off. Once it is
      merged, the four standing rows restart with tracing on (the
      Framework by container restart, no reboot), and each serves again
      with /health 200.
  12. A request through a row shows the row's span as a child of the
      gateway's span, carried by traceparent. An overflowed request has
      no row span. No span holds prompt or completion content; the
      finding records the attributes read.
  Paper and answer (evidence 10, 11)
  13. The gateway comparison takes LiteLLM as the feature reference,
      beside Bifrost, Agent Router, Kong, Portkey, Helicone, and
      TensorZero (archived). It also covers vLLM's production-stack
      router, Kubernetes portability, JWT/OIDC, production's Azure
      Container Apps routing, IL6, and a cheaper chat tier. The session
      researches each on the web; every claim cites its source with the
      date read, and nothing is tried live. Each candidate is weighed
      against the spike's six question bullets.
  14. The gateway document gives the decision and its configuration as
      requirements for v1.ai.hosting:
      - overflow only for agent and vision, none for audio or embedding,
        and none under IL6;
      - dot-segment hardening;
      - authenticated OTLP ingress, and trace sampling below 100%;
      - the embedding overflow marker;
      - embedding's 429 with Retry-After in place of "queues or
        overflows";
      - admission on /metrics, a gap on paper.
      It also lists priority's gaps:
      - a sliding budget window wanted;
      - priority orders only the waiting queue;
      - the queue limit counts every key alike;
      - eviction sends nearly the whole load to Azure under saturation,
        and its growth has no cap;
      - no retry of a body over 64 KiB, and about 11 s per attempt to a
        powered-down host;
      - the UI's Logs and Analytics reached only by URL;
      - the route `ai` deprecation risk, with the watch register as its
        guard.
  15. README's "The answer" states the question, the one-line answer,
      and evidence 1–11, each with where it is proven.
  16. The goal record's pending edits:
      - add the answer section for ai-hosting.md, in the answer-section
        format;
      - drop the two v1.ai.client edits that have landed;
      - fold the two roadmap summary edits into the gateway document and
        the answer section, then drop them;
      - add an edit moving the live retry proof from v1.ai.client's
        acceptance to this spike, with go-ai's finding 17 left for
        v1.ai.client to update;
      - add an edit keeping the Foundry account and its four deployments
        until v1.ai.client's acceptance ships, with experiment.hosting's
        intake deleting them;
      - add an edit for the OTLP authentication and sampling
        requirements.
  Records
  17. Azure answers at most 80 requests in the task, counted from the
      access log after each step that can overflow and recorded in the
      finding.
  18. The task's finding records versions, each host's stack, the
      laptop's path to each host, and every command quoted from the
      logs as run. It holds no address, key, Azure resource name, or
      secret, and raw output stays untracked.
  19. Both repositories' `mise run currency` report only held items,
      and both checks pass. The watch register is read and updated at
      the start and end of the task.
Test seams    each alias's base URL on the gateway as the laptop reaches it
              (go-ai's and infer's tiers and the retry test, through the
              step helpers); the access log, requests_shed, and Grafana's
              trace search; `mise run check` and `mise run currency`
Slices
  1 Clients: behaviors 1–8. All the session's: the helpers' move, the
    rows-up tiers, the rows-down selection and the audio rerun, the
    overlay deploys, and the retry test. Yours: the host updates at
    session start (root).
    Demo:
    - the rows-up tiers pass at v0.2.0;
    - the revalidation table, each discrepancy with its expected and
      actual result;
    - the four retry cases, with their access-log and requests_shed
      cross-checks.
  2 Traces: behaviors 9–12. The session walks you through the
    Collector; its first walk is yours. The session runs the compose
    deploy, the host/ pull request and its merge, the row restarts, and
    the reads.
    Demo:
    - a trace in Grafana from the gateway's span down to the agent row's
      span;
    - an overflowed trace with no row span.
  3 Paper and answer: behaviors 13–16. All the session's.
    Demo: the comparison, the gateway document, README's answer, and the
    answer section.
  4 Walkthrough: you run it from the finding:
    - one rows-up tier run at v0.2.0;
    - one retry case;
    - a trace in Grafana over the tunnel;
    - a read of the gateway document and README's answer.
    Behaviors 17–19 hold throughout.
Benchmarks    none. A new benchmark is an escalation.
Azure cap     At most 80 Azure-answered requests in the whole task: 2xx and
              non-429 4xx, with 429s reported apart. Only the rows-down
              selection, the audio rerun, and the walkthrough send to
              Azure. The session stops and escalates when:
              - a step would take the count past 80;
              - Azure answers 429 for its own capacity (never retried
                around);
              - a row stays evicted outside an overflow step;
              - any content other than synthetic or test-fixture data
                would be sent to Azure.
Guided        Yours:
              - the session-start host updates (root);
              - the Collector's first walk in slice 2;
              - slice 4's walkthrough.
              The session's, over Tailscale SSH with no root, each step in
              your view and logged through the helpers: compose deploys
              and overlays, the host/ pull request, row restarts, tiers,
              the retry test, trace reads, and web research.
Out of scope  any change to go-ai (finding 17's edit is v1.ai.client's);
              vLLM's detailed traces; metrics and logs through the
              Collector; tracing from go-ai or infer clients (the
              cross-service-tracing goal's); a connection-failure retry
              case; an agentgateway upgrade; spike-model-engines outside
              host/; deleting the Foundry account; any benchmark; a live
              trial of another gateway; ~/docs content to Azure
Door          two-way, except what reached Azure:
              - the helpers, the retry test, the overlays, and the compose
                services are in git;
              - the host/ pull request can be reverted, and the rows
                restarted without tracing;
              - Tempo's and Grafana's volumes can be dropped;
              - the sync's coordinator pull request can be reverted.
              One-way: the Azure spend, and the test content sent to Azure
              under its data-processing terms.
Sync          coordinator:
              - ai-hosting.md: the answer section for spike-model-gateway
                under "Answers · experiment.hosting", and the intake
                notes from the pending edits;
              - roadmap.toml: remove experiment.hosting.spike-model-gateway
                from active and delete its table; update v1.ai.client's
                acceptance summary for the retry proof moved here; add
                the v1.ai.hosting notes.
              go-ai: locked by v1.ai.client, so finding 17's update joins
              that goal as a task in the coordinator commit.
              next: none — run `marathon intake experiment.hosting`
```

## Progress

- slice 1 clients: done (33b1d34, 5e7c70b, 494fc50, 3bc100a, f8c028d). Rows-up tiers pass;
  every priority discrepancy revalidated as expected (the 16-token Messages stall no longer
  occurs); the four retry cases pass with cross-checks; Azure 48 of 80, no 429.
- slice 2 traces: done (d1f58f2, spike-model-engines #20, 2bf8e69, 8efb871). The Collector,
  Tempo, and Grafana run in gb10-2's stack; each alias's trace nests the row's span under the
  gateway's; an overflowed trace has no row span; each row sends a startup trace; Azure 50 of 80.
- slice 3 paper: done (b9efae9 comparison, 5a7d880 gateway document, README answer, answer section).
- slice 4 walkthrough: waived by the architect. Reviews, editor pass, and brief done.
- review escalation 1: clients at go-ai v0.3.0 (3e26eca). Rows-up tiers rerun at
  `tools/infer/v0.3.0`: 26 and 19 passed, 0 failed; Azure 0.
- standards review: the retry test's output and skips, and the retry policy as run (ada5a2b,
  b3ea1a0).
- spec review: the retry test's 429 marker names the gateway's three headers exactly (9ab26e4);
  gaps closed in the answer, the finding, and the watch register (e7c919b).
- gb10-2 reboot: every container came back unattended, each alias answered 200 through the
  gateway with a whole 3-span trace, and the config still read `# overlays: none` (2026-11-19).
- editor pass; brief next.

## Decisions

- plan: the question is rewritten around the vLLM layout: one row per purpose, no failover.
- plan: agentgateway and LiteLLM are tried live. Agent Router stays on paper: it is
  Kubernetes-first, and `aigw run` is for local testing. vLLM's production-stack router stays on
  paper: it balances replicas of one model. Kubernetes portability is on paper too, since both live
  gateways have a Kubernetes path.
- plan: the dev gateway runs on gb10-2. It has 65 GiB of headroom against gb10-1's 2.7, it reboots
  unattended, and the capstone's compose stack runs there next.
- plan: model management is fenced only. Consumer keys reach serving routes alone, and row
  lifecycle stays with `host/` over SSH and with experiment.admin.
- plan: spike-model-engines is a rolling spike for the experiment, so it joins this spike's repos.
  The `agentgateway` task rebinds the rows behind the gateway through a `host/` pull request.
- plan: overflow to Azure AI Foundry runs live, with a capped request count. A deployment and key
  are needed before `priority`.
- plan: kind context; `mise run check`; `mise run currency`; no gate.
- plan: overhead is measured with the same GuideLLM cells sent direct and through the gateway, in
  one session.
- plan: the order is agentgateway, litellm, priority (both gateways in one session), answer.
- plan: LiteLLM's Postgres counts as known, not as a new tool. Cerebro plans a Postgres cache too.
- plan: consumers name purpose aliases (agent, vision, audio, embedding). Each alias has its own
  base URL, `/<alias>/v1`, whose `/models` lists only that alias, so go-ai's integration tier and
  the `infer` CLI's one-listed-model fallback work unchanged. Rejected: one shared `/v1` with
  `--model` required of every client.
- plan: go-ai's integration tier runs through the gateway, and go-ai stays read-only. The `infer`
  CLI is used once it is released, as a published version.
- plan: agentgateway's `host/` pull request to spike-model-engines also adds go-core's Apache-2.0
  `LICENSE` there, per the spike repository convention (standards-lab `context/README.md`,
  "Experiments"); this spike holds spike-model-engines.
- agentgateway: held python at 3.14.10, declining 3.15.2: torchcodec 0.17.0, which GuideLLM
  0.8.1's audio extra needs, publishes no cp315 wheel.
- agentgateway: held spike-model-engines' llama.cpp (gb10, strix-halo) at b12098, declining b12316:
  llama.cpp is inert and kept for reference; vLLM is the engine.
- plan: agentgateway runs as a container on gb10-2. Alias routes are detect pass-through, so each
  row serves under its alias as its model name, set in spike-model-engines' `host/`.
- plan: the fence is ufw with ufw-docker on all three hosts, admitting the row ports on tailscale0
  only from gb10-2. gb10-2's vision row stays on its tailnet address. No tailnet identifier or
  secret is recorded anywhere.
- plan: consumer key hashes are committed in the gateway config. The cap cells are observational
  and reject nothing; nothing stands at the caps beyond one-off 429 and 503 probes.
- plan: overflow and `/metrics` admission go on paper in agentgateway's finding, as a gap
  inventory: native or existing tools first, an authored extension or callout only as a last
  resort.
- plan: go-ai's integration tier and infer prove pass-through in agentgateway, on go-ai's
  `tools/infer/v0.1.0`, which added per-role `AI_<ROLE>_TOKEN` and `AI_<ROLE>_HEADER` to both
  tiers and `INFER_HEADER` to the CLI over `Options.Header`. Rejected: a key in each base URL's
  user-info, a bandaid around go-ai.
- plan: the architect has security reservations about LiteLLM after the October 2026 supply-chain
  compromise (LiteLLM advisories 2026-09-30, 2026-10-27, 2026-11-12). Task `litellm`'s plan round
  1 opens by deciding whether it stays, changes, or is replaced.
- agentgateway: key issuance is scripted in the deploy step: the committed config names its keys
  only, and the deploy creates any missing key under `.state/` and fills each name's hash into the
  copy sent to gb10-2. It amends round 2's committed hashes (behavior 4): the running config is the
  same, and no hash enters git history. Rejected: a key step that writes hashes into the committed
  config, which publishes each deployment's hashes and makes a second deployer rewrite them.
- agentgateway: the UI labels inline `ai` route backends "legacy LLM backend" (ui/src/traffic.ts);
  v1.7.0's code, schema, and docs don't deprecate them. agentgateway's newer features (providers,
  virtual models: failover, weighted, conditional, callout) live in the `llm` section, which takes
  one path prefix. Slice 3's paper inventory records the risk and that `priority` may weigh
  per-alias base URLs against one shared `/v1` routed by model name.
- agentgateway: behavior 6, the ufw fence, is removed (architect, 2026-11-13). This task proves
  traffic routes through the gateway; securing the path to the rows in production belongs to the
  networking and platform teams. No host firewall changes, so in dev the rows stay reachable
  directly on the tailnet and the gateway is not the only network path. It supersedes round 2's
  ufw decision. Rejected: ufw with ufw-docker on the GB10s and narrowed Framework rules, as
  overhead the spike doesn't need.
- agentgateway: behavior 15 amended (architect, 2026-11-13): the finding quotes every command the
  command log holds and those recovered from the session's transcript; times that weren't recorded
  read "time not recorded", 4 recovered lines are marked shortened, and the client helpers' lines
  lose curl's quoting since the helpers log their arguments joined. Later tasks log every command,
  the walks included, through the helpers.
- agentgateway: behavior 2's unattended restart is shown by a reboot of gb10-2 (architect,
  2026-11-13), not taken from the restart policy alone.
- agentgateway: the brief's Door line follows behaviors 4 and 6 as amended (no ufw rules; a key is
  revoked by removing its name and deploying).
- agentgateway: the container gets each row's host with `--add-host` from `tailscale ip -4` on
  gb10-2, since Docker's default bridge resolves none of the short names; no address is written down.
- agentgateway: probes are overlays the deploy applies to the copy it sends gb10-2, never to the
  committed config, with plain bash directives, since the laptop's `yq` is the Python wrapper of jq.
- agentgateway: a cap run reads Retry-After from the gateway's access log, through the `access-log`
  overlay, since GuideLLM 0.8.1 keeps no reply header.
- agentgateway: each GuideLLM run is seeded from its name, so the row's prefix cache doesn't serve a
  later run the prompts an earlier one sent.
- agentgateway: go-ai's and infer's tiers ran from a detached go-ai worktree at
  `tools/infer/v0.1.0`, since the `v0.1.0` tag's tier carries no credentials; go-ai's working tree
  is untouched.
- plan: LiteLLM is dropped as a live candidate (architect, 2026-11-13): its supply-chain compromise
  and 2026 advisories, a Python runtime whose Rust port isn't production-ready, and single-vendor
  governance, where agentgateway and Agent Router are Agentic AI Foundation projects. It stays on
  paper as the feature reference in `answer`'s gateway comparison, beside Bifrost, Agent Router,
  Kong, Portkey, Helicone, and TensorZero (archived). Rejected: Bifrost live in litellm's place,
  unless agentgateway can't close priority's gaps natively.
- plan: task `routing` replaces `litellm`: agentgateway's config off the legacy inline `ai` route
  form, the base-URL choice, and other config optimizations, before priority builds on it.
- plan: `priority` runs on agentgateway alone and adds budgets counting streamed requests' usage;
  the dot-segment hardening goes to `answer`'s gateway document as a requirement.
- plan: the "only network path" pending edit is applied in this plan's coordinator pull request.
- plan: v1.ai.client's acceptance waits on this spike's `priority` task, so the models are stable
  before the client uses them again (architect, 2026-11-13; standards-lab org#155, reverting
  org#154's change to that sentence).
- plan: priority's brief is planned in its own `start` session, not here.

- routing: a serving-endpoint allow-list (models, chat/completions, completions, messages,
  responses, embeddings, audio/transcriptions, audio/translations) applies to whichever form
  wins. Every other path is refused: 404 on route `ai`. On the `llm` form only an authorization
  rule can refuse a path, so 403 is accepted there. A missing key stays 401.
- routing: the access log's `retry_after` is committed in the base config. The access-log
  overlay is retired, and the in-flight overlay inserts with an `after` directive.
- routing: the `llm` section is trialled live for the four aliases. If it can't be set up
  cleanly and route as wanted, the config falls back to route `ai` until `llm` can do what
  route `ai` does. The deprecation risk stays in view:
  - route `ai` is UI-labelled "legacy";
  - the docs moved to `llm` (website#1091);
  - `binds` was deprecated without parity (#3204);
  - agentgateway has no deprecation policy (#2767).
- routing: if the trial falls short, the session supplies the evidence and the architect files
  the upstream issue in their own words, per agentgateway's code of conduct.
- routing: in the `llm` form, each alias gets its own gateway and port. The `llm` section is
  attached to all four, and each model's `authorization` requires `proxy.gateway.name ==
  "<alias>"`. Route `ai` keeps serving on 3000 during the trial, and falling back is a deletion.
  - Rejected: one shared `/v1` with a key per purpose, which splits every consumer four ways.
  - Rejected: per-alias routes into the internal `llm:router` backend, an undocumented name.
- routing: the alias ports are 3010 agent, 3011 vision, 3012 audio, and 3013 embedding. They are
  set in deploy.env, and the helpers map each alias to its port. Superseded by the realignment on route `ai`.
- routing: the trial passes only if all of (a)–(f) hold:
  - (a) each base URL lists exactly its alias;
  - (b) the full pass-through matrix works, and a model named at another alias's port is refused;
  - (c) the tiers pass with only base URLs and keys changed;
  - (d) non-serving paths are refused, and a missing key gets 401;
  - (e) a rate limit holds on one alias alone;
  - (f) the config validates using documented fields only.
- routing: if `llm` passes, O-embed (60 s, 34 requests a second) and O-vision (90 s, 4
  concurrent, 1440p) each run direct, route `ai`, `llm`, then direct, in one session. An `llm`
  figure beyond route `ai` by more than the direct runs' spread is reported for the architect's
  call, not an automatic fail.
- routing: a coordinator pending edit for v1.ai.hosting records the deprecation risk and points
  at the watch register.
- routing: a watch register, separate from currency, tracks any dependency's anticipated
  capabilities, deprecations, and other changes. The architect wants it to become a general
  feature for the infrastructure we maintain.
  - Its read-only check, `mise run watch`, runs at every task's PLAN as its own block.
  - It is a script like currency.sh, using `gh` and `jq`, so it is not a new tool.
  - Rejected: a schema check inside currency, which would mix version gaps with upstream risk.
- routing: behavior 2's transcription line is met by the gateway's handling only (architect, 2026-11-16, "but we should at least verify it"): the audio row (Gemma 4 E4B, vLLM v0.33.0) registers no `/v1/audio/*` route, since `Gemma4ForConditionalGeneration` doesn't implement `SupportsTranscription`; both forms forward the full multipart body (the row's `/metrics` counts its Content-Length) and `llm` refuses a wrong-alias model with 403. A row that serves transcription needs a different model, such as Gemma 3n.
- routing: the overhead cells ran on Tailscale's DERP relay (architect, 2026-11-16: "we have to be okay with the idea that we're not always going to be on the direct network path"); the laptop's network had no direct path (netcheck MappingVariesByDestIP true). `llm` against route `ai` is the comparable figure, since both share the path. Rejected: waiting for a direct path, and running GuideLLM from gb10-1.
- routing: the verdict is `llm`: behaviors 1–6 hold. The one flagged figure, vision's median request latency `llm` +2.45 ms over route `ai` against a 1.78 ms direct spread, is accepted by the architect (2026-11-16) as noise-sized on a 4.7 s request. Superseded by the realignment on route `ai`.
- routing: each model's authorization reads `proxy.listener.name`, not `proxy.gateway.name`: standalone agentgateway makes each `gateways` entry a listener of one gateway, `default`. Every model lists all four formats, audio included, since agentgateway classifies `/v1/chat/completions` before `passthrough`. The route form keeps its prefix match and refuses off-list paths with a conditional `directResponse` 404, since a prefix rewrite needs a prefix match.
- routing: before any upstream issue, the session searched every agentgateway issue and pull request (2026-11-16). Only one gap has nothing upstream: several model routers per listener in standalone `llm`, which Kubernetes has (agentgateway#2973). The finding's "For an upstream feature request" holds the facts for the architect to file it in their own words. Per-model limits are agentgateway#4307's (comment there if priority needs them), typed parsing is #4185's, and `/models` scoping is closed (#2719).
- routing: the watch register keeps the always-passthrough entry (#4185) although the trial
  passed, where the brief named it only on a fallback: `llm` parses chat, Messages, Responses, and
  embeddings as typed requests and adds `include_usage` to streams, so the release carrying #4185
  is re-checked before any upgrade.
- routing: the architect reopened routing after it shipped (2026-11-16) and realigned the gateway
  on route `ai`. The docs recommend routing-based configuration for path-based LLM routing
  (`llm/configuration-modes.md`, edited 2026-11-10). The MCP docs call the `mcp` section and route
  `mcp` backends "not a different feature", though the UI labels both inline forms "legacy". No
  upstream issue or discussion asks for `llm` per prefix. Upstream's strategy is still converging,
  so the gateway stays on the documented form, the watch register tracks it, and there is no
  upstream engagement for now. Rejected: filing the #2973-parity request now.
- routing: the realignment ran no benchmark, since slice 2 measured both forms equal within noise,
  and revoked no key again, since slice 1 proved revocation on the same, unchanged route form.
- routing: on route `ai` with `"*": detect`, a streamed chat carries no usage unless the client
  sends `include_usage` (realignment, live). priority weighs typing `/v1/chat/completions` as
  `completions`, which forces `include_usage`, and `/v1/embeddings` as `embeddings`, which Azure
  overflow needs too (`gateway/agentgateway/config.yaml`, `&typed`).

- priority: the Azure resource is the spike's own resource group and AIServices account, set up
  by the architect from a walk in the setup slice (R1 Q1).
- priority: all four aliases overflow to Foundry at parity with the rows, and go-ai and infer are
  exercised on cloud-answered responses. This supersedes agent-only (R1 Q2; R2 Q1, Q2).
- priority: a full row refuses with vLLM's `--max-num-queued-reqs`, so eviction moves its traffic
  to Azure; Bifrost stays on paper. Priority groups with eviction are the standard pattern; vLLM's
  503 as the "full" signal is this design's own, and vLLM #58192 delays vision's 503 (R1 Q3).
- priority: Azure answers at most 300 requests in the task, with each deployment's capacity as a
  hard stop. This supersedes 50 (R1 Q4; R2 Q11).
- priority: per-key priority comes from vLLM's priority scheduling on agent and vision, set by the
  gateway on the row provider only, with per-key rate limits beside it (R1 Q5).
- priority: Chat Completions, embeddings, Messages, and Responses are typed request formats on all
  four routes (R1 Q6; R2 Q5).
- priority: budgets and the request log live in Postgres, in one compose stack with the gateway on
  gb10-2, to `~/architecture`'s convention; Compose and Postgres are known tools. This supersedes
  SQLite (R1 Q7; R2 Q13).
- priority: Azure AI Foundry is the task's one new tool (R1 Q8).
- priority: embedding is held by a global 34/1s limit answering 429 with Retry-After; a paced
  bucket is an escalation (R1 Q9).
- priority: the Framework-down evidence is a real reboot with the architect's LUKS unlock, as the
  walkthrough's last step, where the session pauses (R1 Q10; R2 Q16).
- priority: benchmarks A, B, and D run as briefed (R1 Q11, Q12; R2 Q10).
- priority: the cloud models are gpt-oss-120b, gpt-5-mini 2025-08-07 (GlobalStandard, capacity
  10, so vision overflow is processed globally), and gpt-audio-mini 2025-12-15 (R2 Q1, amended by
  the architect, 2026-11-16, slice 1 escalation: gpt-5.4-mini has 0 quota in every eastus2 SKU;
  the architect purged three soft-deleted accounts that held gpt-5-mini's quota).
- priority: embedding overflows under its alias to text-embedding-3-small at 768 dimensions,
  marked by a header, and the marker is a gateway-document requirement (R2 Q2).
- priority: transcription is out of scope (R2 Q3).
- priority: the gateway answers each alias's `/v1/models` itself (R2 Q4).
- priority: the tiers reach Azure through a rows-down probe overlay (R2 Q6).
- priority: 2 consecutive 503s evict a row for 5 s, and a route retry on 503 waits 20 ms, since
  eviction lands asynchronously and an immediate retry reached the row again (R2 Q7, amended by
  the architect, 2026-11-16, slice 2 escalation).
- priority: the queue limits are twice each cap (agent 24, vision 32, audio 8), and embedding has
  none (R2 Q8).
- priority: the request log stores metadata only (R2 Q12).
- priority: the engines upgrade and the `host/` pull request fold into the setup slice, keeping
  four slices (R2 Q14).
- priority: held spike-model-engines' llama.cpp at b12098, declining b12407: inert, kept for
  reference (R2 Q15). The review's engines bump ended the hold (below).
- priority: confirmed at approval (architect, 2026-11-16): DataZoneStandard where the model offers
  it, GlobalStandard otherwise; the Azure resource name stays untracked, filled in at deploy; the
  budget Block is shown by an overlay that lowers bulk's budget.
- priority: Postgres is pinned at `18.7-alpine`, the latest `-alpine` tag; crane reads the compose
  FROM pin, a known tool from go-web-service's currency.
- priority: in the compose stack, agentgateway runs from its image pin, not a Dockerfile, keeps
  `container_name: agentgateway` for the helpers, and is recreated only when its `config:` section
  changes (a hash label); tailnet addresses are looked up on gb10-2 at run time, and Postgres
  publishes no port.
- priority: each Azure deployment is a `custom` provider at the verified Foundry host and
  `/openai/v1` path, since agentgateway's `azure` provider builds neither. Rejected: the `azure`
  provider's `openAI` type, on a host no deployment was verified on.
- priority: the limits' values: vLLM priority 0 for the interactive keys and 10 for bulk; request
  buckets of 600 a minute for bulk and 1,200 for the others; budgets of 1,000,000 tokens an hour,
  Block, for bulk and 5,000,000, Audit, for the others, each sized above the benchmarks' use
  (`gateway/agentgateway/config.yaml`).
- priority: each Azure provider gets the rows' health policy, 2 consecutive 503s or failed
  connections evicting it for 5 s, so one Azure error doesn't leave the alias without a healthy
  group (architect, 2026-11-16, slice 2 escalation).
- priority: each Azure provider is also evicted on 429 (`&azure-health`), so a throttling Azure
  leaves rotation (architect, 2026-11-16, escalation 2).
- priority: benchmark C is sized to Azure's capacity (C-agent 512 in, 128 out, 28 concurrent;
  C-vision a sub-64 KiB image, 36 concurrent; 60 s each, stopped on an Azure 429). C-agent ran once
  and breached the Azure stop rule: 2,944 requests reached Azure in 60 s (429 ×2845, 400 ×99, no
  2xx), since each eviction sent the whole load to a throttling Azure group. It is recorded as run,
  and C-vision is dropped (R2 Q9, amended by the architect, 2026-11-16, escalations 1 and 2).
- priority: the Azure cap counts Azure's 2xx and its 4xx other than 429, which are reported apart
  since Azure refuses them unprocessed (architect, 2026-11-16, escalation 2). Amends behavior 18.
- priority: Azure stream incompatibilities in go-ai are fixed at their root in a v1.ai.client
  hotfix task that blocks v1.ai.client's remaining tasks, never by a gateway transformation
  (architect, 2026-11-16).
- priority: budgets use agentgateway v1.7.0's `rolling: 1h`, a fixed UTC clock hour, since v1.7.0
  has no sliding window; it is a finding and a watch entry, and a sliding window is a want for
  `answer`'s gateway document (architect, 2026-11-17, review). Amends behavior 15.
- priority: the route retry's `attempts: 2` means 2 retries, so a request is sent at most 3 times
  (architect, 2026-11-17, review). Amends behavior 9.
- priority: go-ai's two audio tests are rerun with the rows down after warming the audio row's
  eviction, about 6 Azure requests, so behavior 10 records Azure's answer, not the row's 503
  (architect, 2026-11-17, review).
- priority: the review's currency bump (architect, 2026-11-17): the gateway's uv to 0.13.9, and
  spike-model-engines' uv to 0.13.9, vLLM v0.33.0 to v0.34.0, and llama.cpp b12098 to b12464,
  through a second `host/` pull request (#19), with row restarts and a smoke check (queue-limit
  bursts, the pass-through matrix, the tiers). The benchmarks ran on v0.33.0 and are not rerun.
- priority: spike-model-engines' ROCm 7.2 fallback is removed, since vLLM v0.34.0 publishes no
  `-rocm72` image (#61939); the Framework runs the default ROCm 10.0 build, as it did throughout
  (architect, 2026-11-17). Rejected: a fallback pinned to v0.33.0-rocm72.
- priority: the Postgres password is rotated, since a reviewer's diff printed it into a local
  transcript, and the deploy refuses a secret marker in a comment (architect, 2026-11-17, review).
- priority: `gateway/compose.sh` exports `BUILDX_NO_DEFAULT_ATTESTATIONS=1`, since Compose v5.2.0
  drops `provenance: false` and each build's new attestation changed Postgres's image id and
  recreated it on every deploy; `provenance: false` and `sbom: false` stay for a Compose that
  honours them (session, after the review).
- priority: pull request #19 also added the four standing rows to spike-model-engines'
  `docs/engines/vllm/models.md`, outside `host/`, from the standards reviewer's finding, without
  the architect's decision (session; raised in the session brief).
- priority: the mock upstream behind the laptop checks was throwaway Python in the session's
  scratchpad, never committed, an exception to the experiment's no-authored-Python rule that the
  architect was told of (session, slice 2).
- answer: Azure cap 80 for the task, counted as priority counted, stop on any Azure 429 (R1 Q1).
- answer: rows-down revalidation reruns only priority's failing tests plus the audio rerun; full
  tiers rows-up (R1 Q2).
- answer: the v0.2.0 move and revalidation are slice 1 (R1 Q3).
- answer: a claimed fix that still fails is recorded with a pending edit to v1.ai.client (R1 Q4).
- answer: Tempo and Grafana at go-web-service's pins behind the Collector (R1 Q5).
- answer: no benchmark (R1 Q7).
- answer: the gateway document allows overflow for agent and vision only; none under IL6 (R1 Q8).
- answer: the session researches and cites the comparison; no live trial (R1 Q9).
- answer: the Foundry account is kept; the intake deletes it (R1 Q10).
- answer: drop the landed v1.ai.client edits; fold the roadmap summary edits into the answer (R1 Q11).
- answer: currency watches the helpers' go-ai tag (R1 Q12).
- answer: the vLLM rows' own spans are added through one host/ PR and restarts (R1 Q6; R2 Q1).
- answer: one Collector on gb10-2's tailnet; authenticated OTLP is a production requirement (R2 Q2).
- answer: retry proof is a Go test importing go-ai v0.2.0 with a recording client; go vet in check;
  Go 1.27.4 pinned (R2 Q3), all four cases (R2 Q4), stats port on loopback (R2 Q5), a failing case
  is recorded with a pending edit (R2 Q6).
- answer: slices are clients, traces, paper, walkthrough (R2 Q7).
- answer: go-ai's acceptance handed this spike finding 17's live retry proof (architect,
  2026-11-18).
- answer: every priority discrepancy is revalidated at v0.2.0 before the answer completes
  (architect, 2026-11-18).
- answer: the helpers and retry/ move to go-ai v0.3.0 and tools/infer v0.3.0, released by go-ai's
  acceptance during the task; the rows-up tiers rerun at v0.3.0, and the retry cases and the
  rows-down revalidation stay proven at v0.2.0, since v0.3.0 changes neither retry nor the formats
  (architect, 2026-11-18, review escalation 1).
- answer: in-flight-1's retry case keeps 5 attempts against a jitter race in the test, not in go-ai;
  its run needed 2 (architect, 2026-11-18, review escalation 2). Amends behavior 6.
- answer: the tracing command goes into spike-model-engines' vLLM guide through the intake, not here
  (architect, 2026-11-18, review escalation 3).
- answer: go-ai's sync (standards-lab 00c1ef5, 2026-11-18) added task `max-tokens-note` after
  `answer` and already moved the live retry proof here in go-ai's finding 17 and ai-strategy.md, so
  `answer` doesn't sync, its retry-proof pending edit is dropped, and the `root` edit goes to
  v1.ai.hosting alone, v1.ai.client having synced (session, 2026-11-19).
- answer: the walkthrough was waived; the architect followed every slice live (architect,
  2026-11-18).
- answer: the three Critical Dell firmware upgrades (BIOS 5.0.0, EC 0x02000d00, PD 0x00000519)
  were applied to both GB10s at session start, gb10-1 first (architect, 2026-11-18, escalation 1).
- answer: rate-limit-agent's bucket moved into the agent route's own `conditional` rate limits,
  since the route's `localRateLimit` replaced the overlay's top-level policy (session, slice 1).
- answer: gb10-2 was rebooted to show behavior 9 live, not accepted on restart policy (architect,
  2026-11-19, spec review).

## Pending edits

- coordinator · experiment.hosting intake: spike-model-engines' vLLM guide
  (`docs/engines/vllm/update.md`) gains per-row tracing, from #20: `VLLM_TRACE=on VLLM_MODEL=<row
  id> host/engines vllm update` adds `--otlp-traces-endpoint grpc://gb10-2:4317`
  (`VLLM_TRACE_COLLECTOR`), `--add-host gb10-2:<tailnet address>` resolved at run time, and
  `OTEL_SERVICE_NAME=vllm-<alias>`; the same update without `VLLM_TRACE` turns it off. Its
  STANDARDS.md wants every command run in a guide, and this spike changes only `host/` there
  (architect, 2026-11-18, review escalation 3). Also a `host/` gap: `vllm update` compares only the
  image and the command, so a changed collector address or alias in `--add-host` or
  `OTEL_SERVICE_NAME` doesn't restart a traced row.

- coordinator · v1.ai.hosting: metrics and logs through the same Collector into the full LGTM stack
  (architect, 2026-11-18), on go-web-service's observability profile (its Collector, contrib
  0.165.0, with Loki, Tempo, Mimir, and Grafana). One central Collector takes every service's
  telemetry:
  - traces pushed over OTLP, as agentgateway and the four rows do in this spike;
  - metrics by its `prometheus` receiver scraping agentgateway's stats port (15020) and each vLLM
    row's `/metrics` (queue depth, KV cache, latency histograms), exported to Mimir;
  - container logs by Docker's `fluentd` logging driver on each service (dual logging keeps
    `docker logs`), sent across hosts to the Collector's `fluentforward` receiver (24224), with a
    `transform` processor mapping each container's tag to its `service.name`, so Grafana's
    trace-to-logs link searches the name Tempo uses. A per-host `filelog` agent is the
    alternative.
  Joining the gateway's 503s and evictions to a row's queue and KV cache is the evidence the
  `/metrics` admission gap needs. Unverified: whether agentgateway v1.7.0's access log carries the
  trace id (if so, go-web-service's `json_parser` trace operators apply), and whether vLLM's
  histograms carry exemplars; vLLM's plain-text logs carry no trace id.
- coordinator · ai-hosting.md, Answers · experiment.hosting: add the section below after "Answer ·
  experiment.hosting.spike-model-layout". It folds in priority's and answer's roadmap summaries.

  ```markdown
  ### Answer · experiment.hosting.spike-model-gateway

  **Question:** Which gateway fronts the self-hosted vLLM layout, and with what access control?

  **Answer:** agentgateway v1.7.0 on its route `ai` form, one base URL per purpose alias, with
  gateway-issued keys that reach the serving endpoints only, per-key priority, buckets, and
  budgets, embedding held to 34 requests a second by 429 and `Retry-After`, and overflow to Azure
  AI Foundry for agent and vision only; admission on vLLM's `/metrics` stays a gap.

  The gateway runs on gb10-2 in one compose stack with Postgres (budgets and the request log) and
  the OpenTelemetry Collector, Tempo, and Grafana (traces). Each alias (agent, vision, audio,
  embedding) has its own `/<alias>/v1`, whose `/models` the gateway answers with that alias alone.
  Making the gateway the only network path to the rows is production's concern, for the networking
  and platform teams. The decision and its configuration, as requirements for v1.ai.hosting, are
  in [docs/gateway.md](https://github.com/JaimeStill/spike-model-gateway/blob/main/docs/gateway.md).
  Each item names the finding that proves it and the running demo or test that reproduces it: the
  helpers are `scripts/clients-lib.sh`'s and, for the GuideLLM cells, `scripts/measure-lib.sh`'s.

  1. Pass-through. Chat, streaming, Messages, Responses, vision, audio, and embeddings pass through
     under purpose aliases with no answer crossed, each `/models` listing exactly its alias. The
     gateway adds nothing beyond run noise to agent, vision, or audio, and at most 3.4 ms (median)
     to an embedding request, the extra hop included, for under 3% of one core and under 35 MiB.
     Proven by measured runs:
     [agentgateway](https://github.com/JaimeStill/spike-model-gateway/blob/main/docs/findings/agentgateway.md),
     "Behavior 3" and slice 2 (agentgateway v1.7.0, vLLM v0.33.0, 2026-11-13); route `ai` and the
     `llm` form equal within noise in
     [routing](https://github.com/JaimeStill/spike-model-gateway/blob/main/docs/findings/routing.md),
     "Behavior 9: the overhead cells" (2026-11-16). Running demos: `goai_tier` and `infer_tier`
     for the pass-through on all four aliases, and `cell` with `bench/overhead-*.yaml`, direct and
     through the gateway, read with `compare`, for the overhead.
  2. Keys and routes. The gateway issues the keys; a missing, unknown, or revoked key gets 401, and
     a revoked key's running stream finishes. Only the eight serving paths are routed, so no vLLM
     management route is open to a consumer key. agentgateway doesn't normalize dot segments, so
     hardening is a requirement. Proven by measured runs: agentgateway, "Behavior 4" and
     "Behavior 5" (2026-11-13); routing, "Realignment on route `ai`" (2026-11-16). Running demo:
     `mise run agentgateway-deploy`, whose deploy creates and revokes keys.
  3. Caps. Past each cap vLLM queues, so a client sees a longer wait (agent ITL 108 ms at 16
     sessions). Past its queue limit, twice its cap (agent 24, vision 32, audio 8), each row
     refuses with 503, which evicts it. The gateway's own refusals are 429 with `Retry-After` and
     `x-ratelimit-*`, and the in-flight limit's 503 with none, logged only in `requests_shed`.
     Proven by measured runs: agentgateway, "Behavior 8: the cap cells" and "Behavior 9: the
     probes" (2026-11-13);
     [priority](https://github.com/JaimeStill/spike-model-gateway/blob/main/docs/findings/priority.md),
     "The rows' limits" (2026-11-16). Running demos: `cell` with `bench/cap-*.yaml` for the caps,
     and `retry_case rate-limit-agent` and `retry_case in-flight-1`, each after `mise run
     agentgateway-deploy <case>` deploys its probe, for the gateway's refusals.
  4. Admission. agentgateway reads no row's `/metrics` and queues nothing itself, and no candidate
     does it natively: a gap, on paper. On paper: agentgateway, "The paper inventory", and
     [the comparison](https://github.com/JaimeStill/spike-model-gateway/blob/main/docs/comparison.md),
     "Scoring".
  5. Embedding limit. A global 34/1s bucket admitted 34 of a 40-request burst and 34.0 a second
     under 160 in flight, refusing the rest with 429 and `Retry-After: 1`; audio beside it held
     RTFx median 5.38 against its floor of 5. Past the limit the client waits, in place of the
     layout's "queue or overflow". Proven by measured runs: priority, "Embedding's limit (behavior
     17)" and benchmark A (vLLM v0.33.0, 2026-11-16). Running demos: `retry_case embedding-burst`,
     in the base config, for the burst, and `cell` with `bench/limited-embed.yaml` beside audio's
     cell, read with `rtfx`, for benchmark A.
  6. Priority. Each key has a request-rate bucket and a token budget per UTC clock hour in
     Postgres, charging streams and surviving a restart, and every request writes a metadata row
     with no content. Chat held its floor beside bulk vision (agent ITL median 47.05 ms). Priority
     by key cut interactive vision's median latency from 11.87 s to 10.47 s on a saturated row,
     0.47 s short of 10 s, since vLLM's priority orders only the waiting queue. Proven by measured
     runs: priority, slice 3 and benchmarks B and D (vLLM v0.33.0, 2026-11-16). Running demos: the
     `bulk-rate-low`, `bulk-budget-low`, and `priority-flat` overlays, each deployed with `mise run
     agentgateway-deploy <overlay>`, with `retry_case bulk-rate-low` and `budget_status`; and
     `cell` with `bench/bulk-vision-*.yaml` and `bench/interactive-vision.yaml` for benchmarks B
     and D.
  7. Overflow. With a row down, each alias was answered by its own Foundry deployment under the
     alias, marked `x-gateway-overflow: azure`, and returned to its row after; nothing failed over
     between hosts. Under saturation, a row's 503s with eviction sent nearly the whole load to
     Azure (2,944 requests in 60 s), and eviction's growth has no cap. Through the Framework's
     reboot, Azure answered its aliases until the LUKS unlock. The parity gaps decide which
     workloads may leave: agent (`gpt-oss-120b`, within the data zone) and vision (`gpt-5-mini`,
     processed globally) overflow; audio (`gpt-audio-mini`, global, refuses a text-only chat) and
     embedding (`text-embedding-3-small`, another vector space) never do, and nothing overflows
     under IL6. Proven by measured runs: priority, "A row down", benchmark C-agent, "Per alias",
     and the walkthrough (2026-11-16 and 2026-11-17). Running demos: `mise run agentgateway-deploy
     rows-down` for a row down, and `cell` with `bench/overflow-agent.yaml`, read with
     `overflow_read`, for saturation. The Framework's reboot is proven only by measured runs:
     priority, the walkthrough's results.
  8. Clients at go-ai v0.3.0. go-ai's and infer's whole tiers passed through the gateway on all
     four aliases at `tools/infer/v0.2.0`, and again at the helpers' pin, `tools/infer/v0.3.0` (26
     and 19 passed, 0 failed, each time). The rest was measured at v0.2.0; v0.3.0 changes neither
     retry nor the formats. On Azure every fix go-ai claimed passed, and each declared gap skipped
     before sending. go-ai's live retry proof (its design finding 17): it retries the gateway's 429
     and 503 and honours `Retry-After`, and in the rate-limit case needed one attempt more than the
     first `Retry-After` implied, which reads as rounded down. Proven by measured runs:
     [answer](https://github.com/JaimeStill/spike-model-gateway/blob/main/docs/findings/answer.md),
     "Step 2 · rows up", "The revalidation", and "Step 5 · the retry proof" (vLLM v0.34.0,
     2026-11-18), and "At v0.3.0" (2026-11-19). Tests: the Go tests in `retry/`, each live case
     run by `retry_case <case>`. Running demos: `goai_tier` and `infer_tier` for the tiers, and
     `priority_rerun` and `audio_rerun` with `CLIENTS_TARGET=rows-down` after `mise run
     agentgateway-deploy rows-down` for the revalidation.
  9. Traces. Each request through a row is one trace, the row's span the child of the gateway's;
     an overflowed request's trace has no row span; no span holds prompt or completion content;
     and each row's startup trace gives its cold start by phase, 13.0–50.0 s. The stack, traces
     included, came back from a reboot of gb10-2 with no one touching it. Production needs
     authenticated OTLP ingress and sampling below 100%. Proven by measured runs: answer, "Slice 2
     · traces" (2026-11-18), with the reboot under "The unattended restart (behavior 9)"
     (2026-11-19). Running demos: `mise run gateway:grafana`, and the helpers' `traces`.
  10. On paper. LiteLLM as the feature reference, beside Bifrost, Agent Router, Kong, Portkey,
      Helicone, and TensorZero (archived), with vLLM's production-stack router, Kubernetes
      portability, JWT/OIDC, production's Container Apps routing, IL6, and a cheaper chat tier:
      nothing on paper beats agentgateway for this layout. LiteLLM had two supply-chain
      compromises in 2026; Container Apps is in audit scope for FedRAMP High and IL2, not IL6; and
      keyless Foundry through agentgateway's `azure` provider with a managed identity is unproven
      here. Every claim cited, read 2026-11-18. On paper: the comparison.
  11. The decision. agentgateway fronts the stack, with its configuration as requirements for
      v1.ai.hosting, priority's gaps, and the intake's notes. On paper:
      [docs/gateway.md](https://github.com/JaimeStill/spike-model-gateway/blob/main/docs/gateway.md).

  Gaps in the answer:

  - Admission on `/metrics`, and queueing at the gateway: nothing reads a row's load.
  - A sliding budget window is wanted: v1.7.0's `rolling: 1h` is a fixed UTC clock hour.
  - Priority orders only vLLM's waiting queue; holding interactive latency under bulk load needs
    more, such as a cap on bulk's concurrency.
  - vLLM's queue limit counts every key alike, so a bulk flood also refuses interactive requests.
  - Under saturation eviction sends nearly the whole load to Azure, and its growth has no cap.
  - A body over 64 KiB isn't retried, and each attempt to a powered-down host costs about 11 s.
  - The UI's Logs and Analytics are reached only by URL on route `ai`.
  - Route `ai` may be deprecated: the watch register, `docs/watch.md`, guards it, and the `llm`
    form, which passed its live trial, is the fallback.
  - The gateway's `Retry-After` reads as rounded down, so a client allows one attempt more.

  [The answer](https://github.com/JaimeStill/spike-model-gateway#the-answer) ·
  [spike-model-gateway](https://github.com/JaimeStill/spike-model-gateway)
  ```
- coordinator · experiment.hosting intake: spike-model-engines' `docs/engines/vllm/api.md` is
  stale since its pull request #17. Its examples send the Hugging Face repository as `"model"`
  (`nvidia/Gemma-4-26B-A4B-NVFP4`, `openai/gpt-oss-120b`, `ibm-granite/granite-embedding-english-r2`)
  and its opening names the pin's default row, while each host now stands on a standing row that
  serves only its alias (agent, vision, audio, embedding), so requests to a standing row name the
  alias. This spike changes only `host/` there, so the fix is the intake's. `models.md`, "The rows",
  already lists the four standing rows with their queue limits and scheduling policy (#19,
  `683b78e`).
- coordinator · v1.ai.hosting: the gateway runs route `ai` backends, the form agentgateway's docs
  recommend for path-based LLM routing. The UI labels them "legacy", and since 1.7 the Kubernetes
  model form is called the recommended one (#4307); agentgateway has no deprecation policy (#2767,
  closed as premature), and it deprecated `binds` without parity (#3204). spike-model-gateway's
  watch register (`docs/watch.md`) tracks route `ai`, and the `llm` form, trialled in task
  `routing` where it passed, is the fallback (`docs/gateway.md`, "Priority's gaps").
- coordinator · experiment.hosting intake: propose the watch register as a shared feature for the
  infrastructure repositories (architect, 2026-11-16): one entry per dependency for anticipated
  capabilities, deprecations, and other changes that would affect the infrastructure we maintain,
  with a read-only `gh` check run at each PLAN beside currency.
- coordinator · experiment.hosting intake: spike-model-layout's `docs/layout.md` requirement 3
  says traffic past embedding's 34 req/s limit "queues or overflows". agentgateway answers it with
  429 and `Retry-After: 1` instead, and the client waits; embedding never overflows. The gateway
  document records this as its requirement 6 (`docs/gateway.md`).
- coordinator · v1.ai.hosting: embedding gets no Azure group, since cloud embedding replies come
  from another vector space (text-embedding-3-small at 768 dimensions). Every Azure-answered reply
  carries an overflow marker (`x-gateway-overflow: azure`); should a deployment give embedding an
  Azure group, a client that stores vectors must refuse or re-route a marked reply
  (`docs/gateway.md`, requirements 8 and 9).
- coordinator · v1.ai.hosting: vLLM's queue limit counts every key alike, so a bulk flood also
  refuses interactive requests, which then overflow. Under saturation a row's 503 with eviction
  sends nearly the whole load to Azure, and agentgateway's eviction multiplier has no cap, so after
  a long outage or overload a row can stay out for minutes after it is back (`docs/gateway.md`,
  "Priority's gaps").
- coordinator · experiment.hosting intake: the gateway's compose stack bind-mounts its config
  read-only, an exception to `~/architecture`'s convention, for the intake to weigh for the
  capstone's stack. Its `gateway/compose.sh` also exports `BUILDX_NO_DEFAULT_ATTESTATIONS=1`:
  Compose v5.2.0 ignores `provenance: false`, and on Docker's containerd image store each build's
  new attestation changes the image id, so compose recreates the built service on every `up
  --build`. The convention may want the same (`docs/gateway.md`, "Operational notes for the
  intake").
- coordinator · experiment.hosting intake: the Foundry account and its four deployments are kept
  for the intake, which deletes them; v1.ai.client's acceptance, the reason they were kept, has
  shipped (standards-lab 00c1ef5).
- coordinator · v1.ai.hosting: authenticated OTLP ingress and sampling below 100% are production
  requirements. The spike's Collector takes spans on gb10-2's tailnet address unauthenticated, and
  the gateway and rows sample every request (spike-model-gateway `docs/findings/answer.md`, "For
  production"; `docs/gateway.md`, requirement 10).
- coordinator · v1.ai.hosting: through the gateway, each alias's `/models` is the
  gateway's own answer, `{"id":"<alias>","object":"model","owned_by":"gateway"}`, so go-ai
  v0.3.0's `Model.Native` and `infer models`' root column carry no served model, while the row's
  own listing gives `root` (`openai/gpt-oss-120b` on gb10-1). Whether to pass `root` through or
  keep it hidden is v1.ai.hosting's call, and a consumer reading `Native` through the gateway gets
  no `root` (spike-model-gateway `docs/findings/answer.md`, "At v0.3.0";
  `docs/gateway.md`, requirement 1).
- coordinator · v1.ai.hosting: a measured cold start. vLLM's startup traces give each row's cold
  start by phase, read from its `Overall Loading` trace: weights' load, model preparation, KV cache
  allocation, and warmup. The agent's 46.2 s is led by its 17.8 s weights' load, audio's 50.0 s by
  its 20.5 s warmup; vision 31.3 s, embedding 13.0 s, one restart each with the weights cached
  (spike-model-gateway `docs/findings/answer.md`, "The rows' startup traces and cold start"). A
  candidate for v1.ai.hosting's restart and capacity notes, in place of an estimate.
