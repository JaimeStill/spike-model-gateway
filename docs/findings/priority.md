# priority

What answers when a row is down or full, and how the gateway ranks, limits, and charges each key's
work: overflow from each row to its own Azure AI Foundry deployment under the same alias, per-key
priority, request-rate buckets and token budgets, and embedding held to 34 requests a second
(evidence 5–7 of [`context/README.md`](../../context/README.md#the-evidence)). This finding holds
slice 1, the setup; slice 2, the overflow and benchmark C; slice 3, the keys and limits and
benchmarks A, B, and D; and the walkthrough the architect runs as slice 4.

- **Measured:** 2026-11-16, from the laptop. Slice 1 ran 13:05–13:56 local time. Every command is
  under "Commands as run".
- **Gateway:** agentgateway v1.7.0, `cr.agentgateway.dev/agentgateway:v1.7.0`, on gb10-2, with its
  Postgres (`postgres:18.7-alpine`) in one compose project
  ([`gateway/compose.yml`](../../gateway/compose.yml)), configured from
  [`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml).
- **Rows:** vLLM v0.33.0, each row serving its alias as its only model name, from
  spike-model-engines `host/` at `2950b83`, the merge of its pull request #18.
- **Cloud:** Azure AI Foundry, the spike's own resource group and AIServices account in eastus2,
  SKU S0, one deployment per alias ("Azure AI Foundry", below).
- **Sources:** agentgateway at the `v1.7.0` tag (`schema/config.md`, `crates/agentgateway/src/`,
  `crates/llm/src/`). **[src]** marks a reading of the source that no doc states.
- **Kept out:** no address, key, key hash, Azure account or resource group name, or other secret.
  The Azure helper's command lines show the expressions that read the key and account name, never
  their values. A quoted access log line has the caller's address replaced with `<laptop>` and the
  Azure host with `<account>`. Raw output stays untracked under `.state/priority/`.

## The question and its evidence

The brief's behaviors, each with the evidence it proves and the slice that shows it:

| Behaviors | What they show | Evidence | Slice |
| --- | --- | --- | --- |
| 1, 2 | spike-model-engines current; the agent, vision, and audio rows refuse with 503 once twice their cap is in flight (agent 24, vision 32, audio 8), embedding unlimited, and agent and vision schedule by priority | 6, 7 | 1 |
| 3 | an Azure AI Foundry deployment per alias, each answering one direct request | 7 | 1 |
| 4 | the gateway and Postgres as one compose project on gb10-2, restarting with the host | 6 | 1 |
| 5, 6 | two priority groups per alias, typed request formats, streamed usage, and `/v1/models` answered by the gateway | 7 | 2 |
| 7, 8 | a row down: each alias answered by Azure under the alias, marked as overflow, and back to its row after; nothing fails over between hosts | 7 | 2 |
| 9 | a row full: two 503s evict it for 5 s, and benchmark C reads what reaches Azure | 7 | 2 |
| 10 | go-ai's and infer's tiers through the rows-down overlay, and the infer CLI | 7 | 2 |
| 11 | the Framework down until `/health` after its LUKS unlock | 7 | 4 |
| 12 | per alias, the cloud model, its processing scope, and its parity gaps | 7 | 2 |
| 13–16 | per-key priority, request-rate buckets, token budgets in Postgres, and the request log | 6 | 3 |
| 17 | embedding held to 34 requests a second | 5 | 3 |
| 18–20 | at most 300 Azure-answered requests, the records, currency and the check | — | all |

## Method

**Steps.** The session runs every host step over Tailscale SSH with no root, each through the step
helpers, [`scripts/clients-lib.sh`](../../scripts/clients-lib.sh) and
[`scripts/measure-lib.sh`](../../scripts/measure-lib.sh), or the deploy,
[`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh), which log each command to
`.state/priority/commands-2026-11-16.log` before it runs. The architect runs the root steps (host
updates, the gb10-2 reboot) and the Azure walk, Foundry's first.

**Overflow.** Each alias route's `ai` backend has two priority groups: the alias's row, then its
Azure deployment. A request goes to the first group with a provider not evicted, so Azure answers
only while the row is out, and only for its own alias: nothing fails over between hosts. The row's
health policy evicts it after two consecutive unhealthy replies, a 503 or a failed connection, for
5 s; a route retry makes up to 2 more attempts on 503, with no backoff. Chat Completions,
embeddings, Messages, and Responses are typed request formats, so the gateway names each
deployment as the model and builds its path; the rest stay `detect`. Each alias's `/v1/models` is
answered by the gateway itself. Every reply Azure answers carries `x-gateway-overflow: azure`, and
the access log records it on that request's line as `overflow="azure"`. The config's comments
give each field and its source.

**The Azure provider's shape.** Each deployment was verified at
`https://<account>.services.ai.azure.com/openai/v1/<path>`, with the account's key in `api-key` and
the deployment's name as the model. agentgateway's `azure` provider builds neither that host nor
that path (`crates/llm/src/azure.rs`) [src]:

| `resourceType` | Host | Path |
| --- | --- | --- |
| `foundry` (`aiServices` is its alias) | `<account>.services.ai.azure.com` | `/api/projects/<project>/openai/v1/...`, a Foundry project's, which the account has none of |
| `openAI` | `<account>.openai.azure.com` | `/openai/v1/...` |

So each Azure provider is an OpenAI-compatible `custom` provider, every field documented in
`schema/config.md`: `hostOverride` at the verified host on 443, `pathPrefix: /openai/v1`,
`backendTLS: {}` (a host override drops the provider's default TLS), `backendAuth.key` with
`location.header.name: api-key`, `custom.model` set to the deployment, and `custom.formats` listing
only what that deployment serves. `providerOverride: azure` makes the access log's
`gen_ai.provider.name` read `azure` on its requests. Rejected: the `azure` provider's `openAI` type
at `<account>.openai.azure.com`, a host no deployment was verified on.

**Laptop check.** Before any deploy, the config was rendered with the deploy's own overlay code and
validated with the pinned image on the laptop, base and `rows-down`, and then run on the laptop
against a mock upstream, untracked, with nothing sent to any host or to Azure. Against the mock,
the gateway answered each `/v1/models` itself, sent a row-down request to the Azure provider with
the deployment as the model, `/openai/v1/<path>`, `api-key`, and the overflow header, set 768
dimensions on embeddings, added `include_usage` to a stream, kept vLLM's own fields and image and
audio parts on a row's request, and returned to the row about 5 s after an eviction. Two readings
bear on slice 2: an eviction reaches the load balancer through a spawned task, so a retry sent with
no backoff still found the evicted row, and the request whose 503s evicted it got its 503; and a
5xx from the Azure provider evicts it for 3 s under agentgateway's default for several groups.

**The Azure cap.** Azure answers at most 300 requests in the task. After each step that can
overflow, the session reads `azure_count <since>`, which counts the access log lines marked
`overflow="azure"` per alias, so per deployment, and per status, and flags any 429 from Azure, a
stop condition. Only synthetic and test-fixture content is sent to Azure.

**Benchmark C.** Two GuideLLM cells through the gateway, run with `cell <name> <scenario> cap
<alias>` and read with `overflow_read <name>`: C-agent,
[`bench/overflow-agent.yaml`](../../bench/overflow-agent.yaml), 28 sessions for 60 s; then
C-vision, [`bench/overflow-vision.yaml`](../../bench/overflow-vision.yaml), 36 concurrent for 60 s.

## Slice 1 · setup

### The hosts

The architect ran the session-start updates (`apt full-upgrade`) on both GB10s; neither needed a
reboot. gb10-1 kept 3 phased updates (`distro-info`, `python3-distro-info`, `snapd`). The
Framework's one pending update waits for slice 4's reboot. Compose v5.2.0 was already on both GB10s,
so no install was needed. Read at 13:05:30 (before) and 13:20:44 (after), untracked under
`.state/priority/`:

| Host | Rows | Kernel | NVIDIA driver | Docker | Updates pending, before → after |
| --- | --- | --- | --- | --- | --- |
| gb10-1 | agent, 8000 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 12 → 3 |
| gb10-2 | vision, 8000; the gateway, 3000 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 9 → 0 |
| framework | audio, 8001; embedding, 8002 | 7.2.15-1-omarchy | — | — | 1, deferred to slice 4 (not read after) |

The laptop's path to every host was Tailscale's DERP relay (nyc), 51–52 ms, with no direct
connection (13:05:30). The 13:20:44 read's `git -C ~/spike-model-engines` found no checkout there:
the hosts keep it at `~/repos/spike-model-engines`, where the pull below ran.

### The rows' limits

spike-model-engines pull request #18, merged as `2950b83`, gives the agent, vision, and audio rows
their queue limits, twice each cap (agent 24, vision 32, audio 8), and priority scheduling on agent
and vision; embedding has no limit. All three hosts pulled it at 13:21:26 and the rows were updated
at once. Agent, vision, and audio restarted under their new flags; embedding's flags were unchanged,
so its update reported "nothing changed". All four answered `/health` by 13:30:05, agent last, and
each container's flags were confirmed with `docker inspect`.

A burst one past each limit, straight to the row with no key, every request held in flight
(`row_burst`, 512 tokens each, `ignore_eos`):

| Row | Requests | 200 | 503 | Time |
| --- | --- | --- | --- | --- |
| agent | 25 | 24 | 1 | 13:30:22 |
| vision | 33 | 32 | 1 | 13:31:37 |
| audio | 9 | 8 | 1 | 13:32:23 |

The first `row_burst` call (13:30:15) answered `row_burst: command not found`, from a shell that
had sourced the helpers before `row_burst` was added; sourcing them again fixed it.

### Azure AI Foundry

The architect created the resource group and the AIServices account (eastus2, S0) and its
deployments from the az CLI, the walk the session led. The subscription's quota for `gpt-5.4-mini`
was 0 in every SKU in eastus2, so the session escalated, and vision overflows to `gpt-5-mini`
instead (the goal record's decision). Three soft-deleted accounts from other projects held
`gpt-5-mini`'s quota until the architect purged them.

| Alias | Deployment | Version | SKU | Capacity |
| --- | --- | --- | --- | --- |
| agent | `gpt-oss-120b` | — | DataZoneStandard | 50 |
| vision | `gpt-5-mini` | 2025-08-07 | GlobalStandard | 10 |
| audio | `gpt-audio-mini` | 2025-12-15 | GlobalStandard | 10 |
| embedding | `text-embedding-3-small` | — | DataZoneStandard | 10 |

One direct request each, past the gateway (`az_curl`, 13:48:46–13:48:59):

- `gpt-oss-120b` answered "ready".
- `gpt-5-mini` answered "red" for a 1×1 red PNG.
- `gpt-audio-mini` refused a text-only chat: "This model requires that either input content or
  output modality contain audio". Sent go-ai's test fixture `integration/testdata/phrase.wav`, it
  answered "The access code is 7429." A text-only chat to the audio alias is a parity gap, recorded
  in slice 2, not worked around.
- `text-embedding-3-small` returned a vector of 768 dimensions, asked with `dimensions: 768`.

Azure requests so far: 5 of 300.

### The compose stack

The first compose deploy ran 13:49:04–13:49:19. It created Postgres's password (`secret
postgres-password: created`), validated the config, removed the `docker run` container of the
same name, built the Postgres image from `postgres:18.7-alpine`, and started the project: Postgres
healthy first, then agentgateway. agentgateway ran its migrations into Postgres, creating
`budget_usage`, `request_logs`, `request_log_payloads`, and
`_agentgateway_request_log_migrations`.

Every earlier check passed on the stack (13:49:36–13:51:34):

| Check | Result |
| --- | --- |
| `/v1/models` on each `/<alias>/v1` | each lists its alias alone |
| a request to each alias | all four answer |
| no key | 401 |
| `/agent/v1/../metrics`, `/agent/v1/load` | 404, off the allow-list |
| go-ai's tier, all four roles | 20 passed, 0 failed, 1 skipped; the key is not in its log |
| infer's tier, all four roles | 13 passed, 0 failed, 1 skipped; the key is not in its log |
| the released infer, no model set | each alias's `infer models` lists that alias, and `infer chat` picks it |

The one skip in each tier is transcription, which no row serves.

### The reboot

The architect rebooted gb10-2 at 13:52:43. The stack came back unattended: the gateway answered 401
to a keyless request at 13:53:26, and the vision row answered 200 at 13:56:30. Postgres's named
volume kept its 178 `request_logs` rows (13:56:33).

## Slice 2 · overflow

Pending.

## Slice 3 · keys and limits

Pending.

## Slice 4 · walkthrough

Pending.

## Commands as run

Every command the log holds, as logged, with its time, from
`.state/priority/commands-2026-11-16.log`. The output stays there, untracked. The two host reads
were logged as `<time>, laptop: <command>`, the rest as `+ <time> <host>: <command>`. The helpers
log curl's arguments joined by spaces, so a JSON body shows without its shell quotes. The
`mise run agentgateway-deploy` line is followed by the deploy's own `+` lines, from its output,
appended to the log by `tee -a`. The architect's reboot is logged as theirs.

### 2026-11-16 · the hosts

```text
13:05:30, laptop: { date -Is; for h in gb10-1 gb10-2; do echo "== $h"; timeout 60 ssh -o BatchMode=yes $h 'apt list --upgradable 2>/dev/null | grep -vc "^Listing"; uname -r; docker --version; docker compose version 2>&1 | head -1; ls /var/run/reboot-required 2>&1 | tail -1; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'; done; echo "== framework"; timeout 60 ssh -o BatchMode=yes framework 'checkupdates 2>/dev/null | wc -l; uname -r; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'; for h in gb10-1 gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done; } 2>&1 | tee .state/priority/stack-$(date +%F).txt
13:20:44, laptop: { date -Is; for h in gb10-1 gb10-2; do echo "== $h"; timeout 60 ssh -o BatchMode=yes $h 'uptime -p; apt list --upgradable 2>/dev/null | grep -vc "^Listing"; uname -r; nvidia-smi --query-gpu=driver_version --format=csv,noheader; docker --version; ls /var/run/reboot-required 2>&1 | tail -1; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"; git -C ~/spike-model-engines log --oneline -1'; done; for hp in gb10-1:8000 gb10-2:8000 framework:8001 framework:8002 gb10-2:3000; do printf "%s health " $hp; curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$hp/health; done; } 2>&1 | tee .state/priority/stack-after-$(date +%F).txt
```

### 2026-11-16 · the engines pull and the row updates

```text
+ 2026-11-16T13:21:26-05:00 gb10-1,gb10-2,framework: cd ~/repos/spike-model-engines && git pull --ff-only
+ 2026-11-16T13:21:26-05:00 gb10-2: cd ~/repos/spike-model-engines && time VLLM_MODEL=gemma-4-26B-A4B-NVFP4-vision-gb10 host/engines vllm update
+ 2026-11-16T13:21:26-05:00 gb10-1: cd ~/repos/spike-model-engines && time VLLM_MODEL=gpt-oss-120b-agent-fp8 host/engines vllm update
+ 2026-11-16T13:21:26-05:00 framework: cd ~/repos/spike-model-engines && time VLLM_MODEL=gemma-4-E4B-it-audio-framework host/engines vllm update && time VLLM_MODEL=granite-embedding-english-r2-framework host/engines vllm update
```

### 2026-11-16 · the row bursts

```text
+ 2026-11-16T13:30:12-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:30:15-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:30:15-05:00 laptop: row_burst agent 25
+ 2026-11-16T13:30:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:30:22-05:00 laptop: for i in $(seq 25); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://gb10-1:8000/v1/chat/completions & done | sort | uniq -c
+ 2026-11-16T13:31:37-05:00 laptop: for i in $(seq 33); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://gb10-2:8000/v1/chat/completions & done | sort | uniq -c
+ 2026-11-16T13:32:23-05:00 laptop: for i in $(seq 9); do curl -s -o /dev/null -w '%{http_code}\n' -H 'content-type: application/json' -d '{"model":"audio","messages":[{"role":"user","content":"Count upward from 1, one number a line."}],"max_tokens":512,"ignore_eos":true}' http://framework:8001/v1/chat/completions & done | sort | uniq -c
```

### 2026-11-16 · the Azure deployments, direct

```text
+ 2026-11-16T13:48:46-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:48:46-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"gpt-oss-120b","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":64}
+ 2026-11-16T13:48:47-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"gpt-5-mini","messages":[{"role":"user","content":[{"type":"text","text":"What color is this image? One word."},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"}}]}],"max_completion_tokens":256}
+ 2026-11-16T13:48:49-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"gpt-audio-mini","modalities":["text"],"messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":32}
+ 2026-11-16T13:48:49-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/embeddings"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d {"model":"text-embedding-3-small","input":"ready","dimensions":768}
+ 2026-11-16T13:48:59-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:48:59-05:00 laptop: printf 'header = "api-key: %s"\nurl = "https://%s.services.ai.azure.com/openai/v1/chat/completions"\n' "$(<.state/azure/key)" "$(sed -n 's/^AZURE_ACCOUNT=//p' .state/azure/account.env | tr -d \"\')" | curl -K - -s -H content-type:application/json -d @.state/priority/assets/audio-probe.json
```

### 2026-11-16 · the compose deploy

```text
+ 2026-11-16T13:49:04-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:49:04-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T13:49:04-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-16T13:49:05-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-16T13:49:06-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-16T13:49:06-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-16T13:49:07-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T13:49:07-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T13:49:08-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-16T13:49:08-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-16T13:49:09-05:00 gb10-2: docker rm --force agentgateway
+ 2026-11-16T13:49:10-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-16T13:49:19-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
```

### 2026-11-16 · the checks on the stack

```text
+ 2026-11-16T13:49:36-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T13:49:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T13:49:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":64} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T13:49:40-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d @/dev/fd/63 http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T13:49:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"embedding","input":["gateway","routing"]} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-16T13:49:42-05:00 laptop: curl -s -o /dev/null -w '%{http_code}\n' http://gb10-2:3000/agent/v1/models
+ 2026-11-16T13:49:42-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3000/agent/v1/../metrics
+ 2026-11-16T13:49:42-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3000/agent/v1/load
```

### 2026-11-16 · the tiers and the infer CLI

```text
+ 2026-11-16T13:49:49-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:49:49-05:00 laptop: git -C ~/architecture/go-ai worktree add --detach .state/priority/go-ai tools/infer/v0.1.0
+ 2026-11-16T13:49:49-05:00 laptop: GOBIN=.state/priority/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.1.0 && .state/priority/bin/infer version
+ 2026-11-16T13:49:51-05:00 laptop: goai_tier compose-goai agent vision audio embedding
+ 2026-11-16T13:49:51-05:00 laptop: cd .state/priority/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/compose-goai.log
+ 2026-11-16T13:50:51-05:00 laptop: infer_tier compose-infer agent vision audio embedding
+ 2026-11-16T13:50:51-05:00 laptop: cd .state/priority/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/priority/clients/compose-infer.log
+ 2026-11-16T13:51:22-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer Say ready.
+ 2026-11-16T13:51:30-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/vision/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/audio/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:30-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/embedding/v1 .state/priority/bin/infer models
+ 2026-11-16T13:51:31-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer chat Reply with the word ready.
+ 2026-11-16T13:51:34-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:51:34-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/priority/bin/infer chat Reply with the word ready.
```

### 2026-11-16 · the reboot

```text
+ 2026-11-16T13:52:53-05:00 gb10-2 (architect): sudo reboot (issued 13:52:43)
+ 2026-11-16T13:56:33-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T13:56:33-05:00 laptop: ssh -o BatchMode=yes gb10-2 'uptime -p; ~/gateway/compose.sh ps --format "{{.Name}} {{.Status}}"; docker exec gateway-postgres-1 psql -U agentgateway -d agentgateway -Atc "select count(*) from request_logs"'
+ 2026-11-16T13:56:34-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T13:56:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":64} http://gb10-2:3000/vision/v1/chat/completions
```
