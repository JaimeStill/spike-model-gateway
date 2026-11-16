# goal · experiment.hosting.spike-model-gateway

- **State:** building
- **Task:** routing
- **Branch:** routing

## Tasks

1. [x] agentgateway
2. [ ] routing
3. [ ] priority
4. [ ] answer

## Task brief · routing

```
Problem       agentgateway serves the four aliases through route `ai`
              backends, which its UI labels "legacy". Upstream has
              deprecated a form without parity before (`binds`, #3204)
              and has no deprecation policy (#2767). Its new features
              (virtual models, per-key model lists) live only in the
              `llm` section. priority needs the form settled first.
Behaviors
  1. The `llm` section serves each alias on its own port (agent 3010,
     vision 3011, audio 3012, embedding 3013); each base URL's
     /models lists exactly its alias.
  2. Each alias's row answers chat, streamed chat with usage,
     Messages, Responses, vision chat, audio chat, multipart
     transcription, and embeddings; a model named on another alias's
     port is refused with 403.
  3. go-ai's and infer's integration tiers pass with only base URLs
     and keys changed, and infer with no model sends to the one
     listed.
  4. With a valid key, a path outside the serving endpoints is
     refused: 403 on the alias ports, 404 on the route form. A
     missing or revoked key gets 401 on every port.
  5. A request-rate limit on one alias alone answers 429 with
     Retry-After there while the other aliases keep answering.
  6. The configuration passes the pinned image's validation and uses
     only documented fields.
  7. Verdict: `llm` stays only if 1–6 all hold; otherwise the config
     returns to route `ai` (/<alias>/v1 on one port, other paths
     404), and the finding lists each unmet behavior with its
     evidence for the architect's upstream issue.
  8. Every access-log line carries the reply's Retry-After without
     an overlay, and the 503 probe still applies on its own.
  9. If `llm` stays: O-embed and O-vision run direct, route `ai`,
     `llm`, direct, back to back in one session; each figure is
     reported beside the direct runs' spread, and an `llm` figure
     beyond route `ai` by more than it is flagged for the architect.
  10. A watch register tracks any dependency for anticipated
      capabilities, deprecations, and other changes; a read-only
      check prints each entry's upstream issues and PRs and its
      watched release fields beside the recorded values. First
      entries: route `ai`'s deprecation risk; `llm` gaining
      per-prefix model lists or several prefixes; on a fallback, the
      release carrying always-passthrough (#4185).
  11. The base-URL choice is recorded in the spike's documents, with
      coordinator pending edits: the deprecation risk for
      v1.ai.hosting, and the register as a shared feature.
Test seams    the gateway's consumer ports over HTTP through the step
              helpers (curl, go-ai's tier, infer, GuideLLM); the watch
              check's output
Slices
  1. The `llm` trial: alias ports beside route `ai`, the allow-list
     on both forms, the log field; behaviors 1, 2, 4, 5, 6, 8 and an
     interim verdict
  2. Tiers through the surviving form (3), the final verdict (7),
     and, if `llm` stays, the benchmark (9)
  3. Settle and record: losing form deleted, helpers and documents on
     the winner, the watch register and its check, the finding, the
     pending edits (10, 11)
  4. Walkthrough, run by the architect from the finding
Out of scope  priority's overflow, budgets, include_usage, embedding's
              34 rps limit; dot-segment hardening (answer); filing the
              upstream issue (the architect's); any spike-model-engines
              host/ change; an agentgateway upgrade; deprecation checks
              in currency; any benchmark beyond behavior 9
Door          two-way: one config file, the losing form is a deletion,
              and the port change only recreates the container
```

## Progress

slices 0/4 committed · standards — · spec — · editor —

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
  set in deploy.env, and the helpers map each alias to its port.
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

## Pending edits

- coordinator · experiment.hosting intake: spike-model-engines' `docs/engines/vllm/api.md` and
  `models.md` are stale since its pull request #17: requests to the four standing rows now name the
  alias, while the guide's examples send the Hugging Face repository. This spike changes only
  `host/` there, so the fix is left to the experiment's intake.
