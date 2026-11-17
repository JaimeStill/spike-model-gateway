# goal · experiment.hosting.spike-model-gateway

- **State:** brief ready
- **Task:** priority
- **Branch:** priority

## Tasks

1. [x] agentgateway
2. [x] routing
3. [ ] priority
4. [ ] answer

## Task brief · priority

```
Goal          experiment.hosting.spike-model-gateway · task 3/4 · priority
Branch        priority
Repos         spike-model-gateway (root); spike-model-engines, host/ only,
              through one pull request that cites this task's finding
Problem       The gateway fronts the four rows with keys and per-alias base
              URLs, but it can't yet show evidence 5–7:
              - Nothing holds embedding to 34 req/s beside audio.
              - No key's work ranks ahead of another's, and no budget
                counts a stream's tokens.
              - Nothing answers when a row is down or full: the rows queue
                without bound and never refuse.
              v1.ai.client's acceptance is waiting on this task, so that
              the gateway's final form is settled first.

              New tool: Azure AI Foundry, Microsoft's hosted model service.
              It is an AIServices account in a resource group, with one
              deployment per model, each at a capacity measured in requests
              and tokens per minute. Each deployment serves an
              OpenAI-compatible v1 API, reached with the account's key. You
              set it up from the az CLI in slice 1, which the session walks
              you through. It gives each alias a cloud deployment that takes
              over, under the same alias, when the alias's row can't answer.
Behaviors
  Setup
  1. spike-model-engines is current: its uv is at 0.13.8, and its
     currency reports only held items (llama.cpp b12098, held against
     b12407; native Python; vLLM's release-name artifact). Its check
     passes.
  2. The host/ pull request:
     - the agent, vision, and audio rows refuse with 503 once twice
       their cap is in flight (agent 24, vision 32, audio 8);
       embedding gets no limit;
     - the agent and vision rows schedule by request priority.
     Once it is merged and the rows have restarted, a direct request
     past the limit gets 503.
  3. Azure AI Foundry: the spike has its own resource group and
     AIServices account in eastus2, with four deployments:
       gpt-oss-120b (agent, capacity 50)
       gpt-5.4-mini (vision, 10)
       gpt-audio-mini 2025-12-15 (audio, 10)
       text-embedding-3-small (embedding, 10)
     Each uses DataZoneStandard where the model offers it, and
     GlobalStandard otherwise. The key and the resource name stay
     untracked on the deploying machine and reach gb10-2 only in the
     deployed copy, as the gateway keys do. Each deployment answers
     one direct request.
  4. The gateway and Postgres run as one compose project on gb10-2,
     to ~/architecture's compose convention:
     - one file per service group;
     - Postgres from its own Dockerfile, its FROM line the pin, with a
       health check and a named volume;
     - mise up, down, and reset tasks.
     The gateway's config is bind-mounted read-only, an exception to
     the convention recorded in the finding, so it still reloads in
     place. The stack restarts with the host unattended, and every
     check from earlier tasks still passes on it.
  Overflow (evidence 7)
  5. Each alias route has two priority groups, its row and then its
     Azure deployment, with Azure's key on that provider alone:
     - Chat Completions, Messages, Responses, and embeddings are typed
       request formats; the rest stay detect.
     - A stream carries usage whether or not the client asks.
     - With the rows up, the pass-through matrix still passes.
  6. The gateway answers each alias's /v1/models itself, listing
     exactly that alias, whether its row is up or not.
  7. A row down: with a probe overlay that makes every row
     unreachable, each alias is answered by its Azure deployment under
     the alias. Removing the overlay returns each alias to its row.
     The access log names the provider that answered. Nothing fails
     over between hosts.
  8. Embedding overflow returns 768-dimension vectors. Every reply
     Azure answers carries a response header marking it as overflow,
     and a reply from a row doesn't.
  9. A row full: two consecutive 503s evict the row for 5 s, and a
     route retry of 2 attempts on 503, with no backoff, re-sends a
     body up to 64 KiB. Benchmark C records whether a refused request
     reaches Azure.
  10. go-ai's and infer's integration tiers run through the rows-down
      overlay with their base URLs and keys unchanged, and each
      scenario's result is recorded:
      - Responses fails on agent and audio, a parity gap, because
        neither cloud model serves it.
      - Any failure from a model difference is a parity finding.
      - Transcription is skipped.
      The released infer CLI, setting no model, picks the alias that
      /models lists.
  11. The Framework down until /health: while it is rebooted and
      locked, audio and embedding are answered by Azure. After the
      unlock, the finding records the time from the unlock to the
      rows' /health, and to the first request a row answers again.
  12. The finding records, per alias, the cloud model, its SKU's
      processing scope, and its parity gaps: which workloads may leave
      the self-hosted machines. Only synthetic and test-fixture content
      is sent to Azure.
  Keys and limits (evidence 5, 6)
  13. A new key, bulk, joins architect, bench, and go-ai. On the agent
      and vision rows, each key's requests carry a priority that ranks
      interactive keys ahead of bulk. It is set on the row's provider
      alone, so no request to Azure carries it.
  14. Each key has its own request-rate bucket. A probe shows bulk
      refused with 429 while another key keeps answering on the same
      alias.
  15. Token budgets are kept in Postgres: Block on bulk, Audit on the
      others, over a rolling window. A streamed chat sent without
      include_usage is charged to its key. A probe that lowers bulk's
      budget gets 429 with Retry-After. A count survives a gateway
      restart.
  16. Every request writes a metadata row to Postgres (usage, timing,
      the key's name) and no prompt or completion content. The UI's
      Logs and Analytics pages read it over the SSH tunnel.
  17. The embedding route holds a global 34 req/s limit and answers
      429 with Retry-After past it.
  Records
  18. Azure answers at most 300 requests in the task, counted from the
      access log per deployment and recorded in the finding.
  19. The finding records versions, each host's stack, the laptop's
      path to each host, and every command quoted from the logs as
      run. It holds no address, key, Azure resource name, or secret,
      and raw output stays untracked.
  20. `mise run currency` reports agentgateway's image pin and the
      compose FROM pins, with nothing trailing beyond held items.
      `mise run check` passes. The watch register is read and updated
      at the start and end of the task.
Test seams    each alias's base URL on the gateway as the laptop reaches it
              (curl, go-ai's and infer's tiers, the infer CLI, GuideLLM,
              all through the step helpers); in slice 1, each row and
              Azure deployment directly; `mise run check` and
              `mise run currency`
Slices
  1 Setup: behaviors 1–4. The session runs the engines upgrade, the
    host/ pull request and its merge, the row restarts, the compose
    stack's deploy, and the checks. It walks you through the Azure
    account first: what each az step creates, what it costs, and what
    it provides. You run the az steps; they are Foundry's first walk.
    Yours too: the host updates at session start, and the compose
    plugin's install if gb10-2 lacks it (root).
    Demo:
    - a direct request past a row's limit gets 503;
    - each Foundry deployment answers directly;
    - the gateway on compose passes the matrix.
  2 Overflow: behaviors 5–10 and 12, then benchmark C. All the
    session's.
    Demo:
    - every alias answered by Azure under its alias with the rows
      down, and by its row again once they're back;
    - the tiers' results recorded.
  3 Keys and limits: behaviors 13–17, then benchmarks A, B, and D. All
    the session's.
    Demo:
    - bulk refused while another key answers;
    - a stream charged to its key;
    - audio's RTFx beside the embedding limit.
  4 Walkthrough: you run it from the finding:
    - an alias's /models;
    - a row-down overflow;
    - a budget Block;
    - the request log in the UI;
    - the Framework reboot as the last step (root).
    The session pauses at the reboot until you are home to unlock the
    Framework, and the task stays unshipped until behavior 11's reading
    is in. Behaviors 18–20 hold throughout.
Benchmarks    Every run: GuideLLM 0.8.1 from the laptop, the model sent as
              the alias with its tokenizer given separately, each seeded
              from its name, built and run a step at a time in your view,
              at most 10 min. Two runs at once use two terminals. Only
              cells in the same session compare.
  A Embedding limited, audio beside it (slice 3; evidence 5):
    - through the gateway, C-embed at 160 in flight for 90 s, held to
      34 req/s;
    - O-audio (4 streams, 30 s or 64 requests) starting inside it;
    - anchor: O-audio alone, direct and through the gateway.
    It informs whether a 34/1s bucket's burst lets audio hold its RTFx
    median ≥5. A miss escalates to a paced bucket.
  B Chat beside bulk vision (slice 3; evidence 6):
    - the bulk key runs C-vision at 20 concurrent for 150 s;
    - the go-ai key runs O-agent (4 sessions, 110 s) inside it;
    - anchor: O-agent alone, direct and through the gateway.
    It informs whether chat holds its floor (agent ITL ≤100 ms), and
    the change in TTFT, ITL, and the gateway's CPU against the direct
    spread.
  C Overflow when full (slice 2; evidence 7):
    - through the gateway, C-agent at 28 sessions for 60 s, then
      C-vision at 36 concurrent for 60 s.
    It reads 503s per row, requests Azure answered, whether a refused
    request reached Azure, evictions per minute, and vision's time to
    its 503 (vLLM #58192). It informs whether a row's 503 with eviction
    is a usable "full" signal.
  D Priority on vision (slice 3; evidence 6):
    - the bulk key runs C-vision at 20 concurrent for 120 s;
    - an interactive key runs O-vision at 1 concurrent inside it;
    - control: the same pair, with the interactive run sent at bulk's
      priority.
    It informs whether interactive vision's median latency stays ≤10 s
    with priority, and how far it moves without.
  No other benchmark runs; a new or widened one is an escalation.
Azure cap     At most 300 Azure-answered requests in the whole task,
              counted from the access log after each step that can
              overflow. The deployments' capacities are a hard stop. The
              session stops and escalates when:
              - a step would take the count past 300;
              - Azure answers 429 for its own capacity (never retried
                around);
              - a row stays evicted outside an overflow step;
              - any content other than synthetic or test-fixture data
                would be sent to Azure.
              Only the rows-down overlay, benchmark C, the probes, and the
              walkthrough send requests to Azure.
Guided        Yours:
              - the session-start host updates (root);
              - the Azure walk in slice 1, Foundry's first walk;
              - any compose install (root);
              - slice 4's walkthrough;
              - the Framework's reboot and LUKS unlock.
              The session's, over Tailscale SSH with no root, each step in
              your view and logged through the helpers: the engines
              upgrade, row restarts, compose deploys and reloads,
              overlays, probes, tiers, cells, and read-outs.
Out of scope  transcription through the gateway (no row serves it); a
              gateway-side queue; admission on /metrics; traces and the
              OpenTelemetry Collector, the paper comparison, and
              dot-segment hardening (answer); USD budgets and a model
              catalog; an agentgateway upgrade; any change to go-ai;
              spike-model-engines outside host/ and its upgrade; ~/docs
              content to Azure; Bifrost
Door          two-way, except what reached Azure:
              - the gateway config and overlays are in git;
              - the host/ pull request can be reverted;
              - the compose move can go back to docker run, and Postgres's
                volume can be dropped;
              - a key is revoked by removing its name and deploying;
              - the Azure account and deployments can be deleted.
              One-way: the Azure spend, and the test content sent to Azure
              under its data-processing terms.
```

## Progress

slices 4/4 committed · standards ✓ · spec ✓ (13 gaps closed) · editor ✓

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

## Pending edits

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
  `routing` where it passed, is the fallback.
- coordinator · experiment.hosting intake: propose the watch register as a shared feature for the
  infrastructure repositories (architect, 2026-11-16): one entry per dependency for anticipated
  capabilities, deprecations, and other changes that would affect the infrastructure we maintain,
  with a read-only `gh` check run at each PLAN beside currency.
- coordinator · roadmap: priority's summary names what it built: on the route `ai` form, each
  alias's `/<alias>/v1` (whose `/models` the gateway answers, listing only that alias) overflows to
  its own Azure AI Foundry deployment when its row is down or full, with at most 300
  Azure-answered requests; per-key priority on the agent and vision rows, request-rate buckets, and
  token budgets per UTC clock hour in Postgres, counting streamed usage; the request log; and
  embedding held to 34 requests a second, all in one compose stack with Postgres on gb10-2.
- coordinator · roadmap: `answer`'s summary lists the gateway document's requirements and gaps
  that priority adds to dot-segment hardening (spike-model-gateway `docs/findings/priority.md`,
  "Answer for this task", and `docs/watch.md`):
  - a sliding budget window, wanted: v1.7.0's `rolling: 1h` is a fixed UTC clock hour;
  - the embedding overflow marker, which a client that stores vectors must honour;
  - priority orders only vLLM's waiting queue (interactive vision missed 10 s by 0.47 s beside
    bulk), so holding interactive latency under bulk load needs more, such as a cap on bulk's
    concurrency;
  - vLLM's queue limit counts every key alike, so a bulk flood also refuses interactive requests;
  - under saturation a row's 503 with eviction sends nearly the whole load to Azure, and
    eviction's growth has no cap;
  - a body over 64 KiB isn't retried, and a powered-down host costs each attempt about 11 s;
  - the UI's Logs and Analytics load only by URL on route `ai`;
  - which workloads may leave the self-hosted machines, from the per-alias parity gaps: agent and
    embedding are processed within the data zone, vision and audio globally.
- coordinator · experiment.hosting intake: spike-model-layout's `docs/layout.md` requirement 3
  says traffic past embedding's 34 req/s limit "queues or overflows". agentgateway answers it with
  429 and Retry-After instead, and the client waits. `answer`'s gateway document records this.
- coordinator · v1.ai.hosting: cloud embedding replies carry an overflow marker
  (`x-gateway-overflow: azure`) and come from another vector space (text-embedding-3-small at 768
  dimensions). A client that stores vectors must refuse or re-route a marked reply. This is a
  gateway-document requirement.
- coordinator · v1.ai.hosting: vLLM's queue limit counts every key alike, so a bulk flood also
  refuses interactive requests, which then overflow. Under saturation a row's 503 with eviction
  sends nearly the whole load to Azure, and agentgateway's eviction multiplier has no cap, so after
  a long outage or overload a row can stay out for minutes after it is back.
- coordinator · v1.ai.client: acceptance can run once priority ships and the hotfix task below is
  done. The gateway's form is settled: typed routes, `/models` answered by the gateway, overflow to
  Foundry, and per-key priority, buckets, and budgets.
- coordinator · experiment.hosting intake: the gateway's compose stack bind-mounts its config
  read-only, an exception to `~/architecture`'s convention, for the intake to weigh for the
  capstone's stack. Its `gateway/compose.sh` also exports `BUILDX_NO_DEFAULT_ATTESTATIONS=1`:
  Compose v5.2.0 ignores `provenance: false`, and on Docker's containerd image store each build's
  new attestation changes the image id, so compose recreates the built service on every `up
  --build`. The convention may want the same.
- coordinator · v1.ai.client: add a hotfix task, run ahead of v1.ai.client's remaining tasks,
  which wait on it (architect, 2026-11-16: "always fix problems at their root and avoid hiding them
  behind band aids"). It fixes go-ai, at `tools/infer/v0.1.0`, wherever go-ai is at fault in
  reading Azure AI Foundry's streams, with no gateway workaround:
  - its Chat Completions parser rejects a chunk with an empty reply id, which Azure's chat streams
    start with: `format/completions/decode.go:365-369` fixes the reply id from the first chunk, and
    Azure's first chunk has an empty id (likely its content-filter preamble, with no choices);
  - its Responses parser rejects how Azure adds a reasoning item:
    `format/responses/stream.go:308-321` rejects an output item added with content, and
    `protocol/accumulator.go:222-232` has the same assumption.

  The task first records a raw stream straight from Foundry and confirms each root cause against
  it and the OpenAI spec. Three gaps are the gateway's, not go-ai's to fix (an upstream issue is
  the architect's to file): `incomplete_details.reason` of `max_tokens`, 0 input tokens on a
  translated Messages stream, and, on overflow, audio in a Responses request refused by
  agentgateway's typed Responses parser (400, "untagged enum InputParam"). It also weighs the other
  Foundry gaps, which are model differences rather than go-ai's faults: gpt-oss-120b refuses
  `tool_choice: required` and ignores a named function; gpt-5-mini refuses `max_tokens` and
  reasoning effort `none`; gpt-audio-mini refuses a text-only chat (spike-model-gateway
  `docs/findings/priority.md`, "The tiers on Azure" and "Per alias"). This edit goes through a
  coordinator `plan` session, since BUILD doesn't change the coordinator.
