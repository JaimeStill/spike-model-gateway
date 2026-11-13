# goal · experiment.hosting.spike-model-gateway

- **State:** building
- **Task:** agentgateway
- **Branch:** agentgateway

## Tasks

1. [ ] agentgateway
2. [ ] litellm
3. [ ] priority
4. [ ] answer

## Task brief · agentgateway

```
Problem       The four vLLM rows (gb10-1 agent, gb10-2 vision, the Framework audio
              and embedding) are reachable by anyone on the tailnet, under their
              Hugging Face model names, with no consumer keys. The spike can't
              weigh a gateway until one stands in front of them. agentgateway
              v1.7.0 is this task's one new tool: a Rust proxy for LLM traffic,
              run as a container on gb10-2, configured from one file in this
              repository. It gives path routes, consumer API keys, LLM
              pass-through that still reads token usage, and rate and in-flight
              limits. This task puts it in front of the rows with a per-purpose
              base URL and gateway-issued keys, measures what it adds, and inventories what it lacks for admission
              and overflow (evidence 1–4 and 8).
Behaviors     1. spike-model-engines' host/ pull request serves each standing row
                 under its alias as its only model name: gpt-oss-120b-agent-fp8
                 as agent, gemma-4-26B-A4B-NVFP4-vision-gb10 as vision,
                 gemma-4-E4B-it-audio-framework as audio, and
                 granite-embedding-english-r2-framework as embedding. It adds
                 go-core's Apache-2.0 LICENSE at the repository root and cites
                 this task's finding. Once it is merged and the rows restarted,
                 each row's own model list names exactly its alias.
              2. agentgateway v1.7.0 runs on gb10-2 as a container from its
                 official image. It restarts with the host unattended, and its
                 port is published on gb10-2's tailnet address only. Its admin
                 API and UI are not reachable on the consumer port.
              3. Each alias has its own base URL on the gateway, /<alias>/v1,
                 and that URL's /models lists exactly that alias. Requests reach
                 the row unchanged (detect pass-through). Through each alias,
                 with a valid key, these succeed as a direct request does:
                 agent: chat, streamed chat, Messages, and Responses;
                 vision: chat with an image; audio: chat with an audio clip;
                 embedding: embeddings. No request to one alias's URL reaches
                 another purpose's row.
              4. Every alias route requires a gateway-issued key, sent as a
                 Bearer token. No key, an unknown key, or a revoked key gets 401
                 and never reaches a row. Keys are random 256-bit values kept on
                 the deploying machine; only their names are committed, in the
                 gateway config in this repository, and the deploy step creates
                 any missing key and fills each name's sha256 hash into the copy
                 it sends to gb10-2. Removing a name and deploying revokes that
                 key with no restart; requests already running finish.
              5. Through the gateway, a consumer key reaches only routes under
                 /<alias>/v1. vLLM's root routes (metrics, health, tokenize, any
                 management or dev route) and agentgateway's admin API can't be
                 reached with a consumer key.
              6. (Removed by the architect, 2026-11-13: no host firewall. The
                 rows stay reachable directly on the tailnet. This task proves
                 traffic routes through the gateway; securing the path to the
                 rows in production belongs to the networking and platform
                 teams.)
              7. The overhead cells run in one session, purpose
                 by purpose, each direct, gateway, direct. The finding gives the
                 gateway's added TTFT, ITL, and request latency (embedding:
                 latency only) against the spread between the two direct runs,
                 and the gateway container's CPU and memory during its runs.
              8. The cap cells run through the gateway. The
                 finding records, per purpose and level, every reply's status and
                 any Retry-After, the row's running and waiting counts, and
                 latency growth past the cap. Observational: a starting point
                 that rejects nothing. Nothing stands at the caps on the gateway.
              9. Two one-off probes, each configured, run, and removed: a
                 per-route request-rate limit answers 429 with Retry-After and
                 x-ratelimit headers; the global in-flight limit answers 503 with
                 no Retry-After. The finding reads each against go-ai's retry set
                 (408, 429, 502, 503, 504; Retry-After in seconds or HTTP date)
                 and states whether a gateway refusal triggers any failover. With
                 infer released, infer with retries set waits out the 429's
                 Retry-After and then succeeds.
              10. go-ai's integration tier runs unchanged through the gateway:
                  agent, vision, audio, and embedding each at its /<alias>/v1,
                  each role's key in AI_<ROLE>_TOKEN (Bearer), transcription
                  unset; infer's tier runs the same way. Every scenario set
                  passes; transcription skips. Once, one role sends its key
                  through AI_<ROLE>_HEADER instead, against a gateway key
                  location set to that header, then restored to Bearer.
              11. The released infer CLI, with a key in INFER_TOKEN and
                  INFER_BASE_URL at each /<alias>/v1, sets no model; it picks the
                  one model each alias lists, and models, chat, and embed answer
                  through the gateway.
              12. If go-ai's tiers or infer tools/infer/v0.1.0 (per-role
                  AI_<ROLE>_TOKEN and AI_<ROLE>_HEADER in both tiers,
                  INFER_HEADER in the CLI) fail to carry the key when slice 3
                  runs, behaviors 10 and 11 move to
                  `priority`; the finding and the goal record say so, and slice 3
                  completes without them.
              13. The finding holds a paper inventory, from agentgateway v1.7.0's
                  docs and source plus the probes, of what it provides natively
                  for (a) capacity overflow to Azure AI Foundry and (b) admission
                  on vLLM's live metrics: priority groups, eviction on 5xx and
                  classified replies, Retry-After eviction, route retries, virtual
                  models and callout routing, the endpoint picker. Per
                  requirement it marks gap or none and names what could fill each
                  gap: native or existing tools first, an authored extension or
                  callout service only as a last resort.
              14. `mise run currency` reports the agentgateway image pin against
                  agentgateway's latest GitHub release, nothing when current;
                  beside it only held items (Python 3.14.10).
              15. The finding records what was measured, when, on which versions
                  (agentgateway, vLLM, GuideLLM), each host's stack, and each
                  host's network path from the laptop as direct or relay only. It
                  quotes every command run, exactly as run, with its time. It
                  holds no tailnet or LAN address, no tailnet name beyond short
                  host names, no key, no secret; raw output stays untracked.
              16. `mise run check` passes.
Test seams    each alias's base URL on the gateway, as a consumer reaches it from
              the laptop; `mise run check` and `mise run currency`
Slices        No upgrade slice: this repository reports only Python, held at
              3.14.10; spike-model-engines' llama.cpp pins held at b12098, its
              native Python held, its uv outside host/.
              1 The host/ pull request (behavior 1), merged; rows restarted by the
                session. agentgateway's container up on gb10-2 with the four
                alias routes and strict keys; the architect walks this bring-up
                first. Pass-through per alias; keyless and revoked refused; no
                root routes. The currency pin. (behaviors 1–5, 14)
              2 The overhead cells, direct, gateway, direct per purpose, while the
                laptop still reaches the rows. (behavior 7)
              3 The cap cells; the 429 and 503 probes; go-ai's tier and infer
                through the gateway, or their move to priority; the paper
                inventory. (behaviors 8–13)
              4 The walkthrough the architect runs from the finding: an alias's
                /models, a chat with and without a key, a revoked key, the
                gateway's container read-outs.
                (behaviors 15, 16 hold throughout)
Benchmarks    Every cell: GuideLLM 0.8.1 from the laptop, the model sent as the
              alias, its tokenizer given separately, built and run a step at a
              time in the architect's view; each run at most 10 min.
              Overhead cells (slice 2), each run direct, gateway, direct; they
              inform the gateway's added TTFT, ITL, latency, CPU and memory
              against run noise.
                O-agent: 4-turn synthetic conversations, 8,192-token first prompt
                  then 512 a turn, 512 out a turn; concurrent 4; 110 s.
                O-vision: synthetic 1440p JPEG + 200 text tokens, 100 out;
                  concurrent 4; 90 s.
                O-audio: LibriSpeech dummy clips as 16 kHz WAV in chat with the
                  model card's transcription prompt, ≤256 out; concurrent 4;
                  30 s or 64 requests.
                O-embed: 512 synthetic tokens; constant 34 req/s; 60 s.
              Cap cells (slice 3), gateway only, two levels each; they inform
              what a client sees at and past each cap; observational.
                C-agent: concurrent 12 and 16; 110 s a level.
                C-vision: concurrent 16 and 20; 60 s a level.
                C-audio: concurrent 4 and 8; 30 s or 64 requests a level.
                C-embed: concurrent 128 and 160; 60 s a level.
              No other benchmark runs; a new or widened one is an escalation.
Guided        The architect's: the session-start host updates (root);
              agentgateway's first walk in slice 1; slice 4's walkthrough. The session runs over Tailscale
              SSH with no root: the image pull, container start and reloads, row
              restarts through host/, read-outs, cells and probes, each step in
              the architect's view.
Out of scope  LiteLLM; Azure AI Foundry overflow live; the endpoint picker live;
              per-key budgets, priority, and embedding's 34 req/s limit; traces
              and the OpenTelemetry Collector; tuning caps, engine flags, or the
              layout; any change to go-ai (the hotfix is v1.ai.client's);
              spike-model-engines outside host/ and its LICENSE (guides, uv,
              llama.cpp pins); Kubernetes
Door          two-way: the container can be removed, the host/ pull request
              reverted, the ufw rules deleted, and the gateway config is in git
              (a committed key hash is revoked by removing it)
```

## Progress

slices 3/4 committed (slice 1: 48027e3; slice 2: 4b55cc6, 93405a0; slice 3: 64ced85, a5882ea) · standards — · spec — · editor —

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

## Pending edits

- coordinator · roadmap: `goals.experiment.hosting.spike-model-gateway`'s summary drops "and is
  the only network path to the rows" as a dev requirement, noting that production's network
  security belongs to the networking and platform teams; its `agentgateway` task's proof drops "a
  direct tailnet request to a row fails" (architect, 2026-11-13).
