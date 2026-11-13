# goal · experiment.hosting.spike-model-gateway

- **State:** idle
- **Task:** none
- **Branch:** none

## Tasks

1. [x] agentgateway
2. [ ] routing
3. [ ] priority
4. [ ] answer

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
- plan: the "only network path" pending edit is applied in this plan's coordinator pull request,
  and v1.ai.client's acceptance now waits on agentgateway (shipped), not the whole spike.
- plan: priority's brief is planned in its own `start` session, not here.

## Pending edits

- coordinator · experiment.hosting intake: spike-model-engines' `docs/engines/vllm/api.md` and
  `models.md` are stale since its pull request #17: requests to the four standing rows now name the
  alias, while the guide's examples send the Hugging Face repository. This spike changes only
  `host/` there, so the fix is left to the experiment's intake.
