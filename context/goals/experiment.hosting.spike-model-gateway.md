# goal · experiment.hosting.spike-model-gateway

- **State:** brief ready
- **Task:** routing (realign)
- **Branch:** routing-realign

## Tasks

1. [x] agentgateway
2. [x] routing
3. [ ] priority
4. [ ] answer

## Task brief · routing (realign)

Reopened by the architect (2026-11-16) after shipping, instead of planning a new task: the
gateway returns to route `ai`, the form agentgateway's docs recommend for path-based LLM routing
(`llm/configuration-modes.md`, edited 2026-11-10: "custom, path-based routing (e.g., `/openai`,
`/anthropic`)" → routing-based configuration). Behaviors: each alias on `http://gb10-2:3000/<alias>/v1`
listing only its alias; the serving-path allow-list answering 404; a missing or revoked key 401;
`retry_after` in the base access log; probes, helpers, and cap-cell reader on the route form;
go-ai's and infer's tiers pass through it; the `llm` section and alias ports removed; the watch
register turned around (route `ai` relied on; `llm` parity as the migration trigger, with the docs
as counter-evidence to the deprecation reading); the finding records the realignment. No
benchmark: slice 2 measured both forms equal within noise. Door: two-way.

## Progress

realign: implementer ✓ (2b06f94, 5f08907) · docs research ✓ (context/priority-on-route-ai.md) · standards ✓ (316a2dd, 9e1ba5c; network path 018d135) · spec ✓ (all met; revoked-key wording 82c328a) · editor ✓

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
  overflow needs too (`context/priority-on-route-ai.md`).

## Pending edits

- coordinator · experiment.hosting intake: spike-model-engines' `docs/engines/vllm/api.md` and
  `models.md` are stale since its pull request #17: requests to the four standing rows now name the
  alias, while the guide's examples send the Hugging Face repository. This spike changes only
  `host/` there, so the fix is left to the experiment's intake.
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
- coordinator · roadmap: the per-alias base URL stays `/<alias>/v1`, whose `/models` lists only
  that alias, served by route `ai`, the docs' routing form; priority's summary "in the form
  routing settles" can name the route `ai` form.
