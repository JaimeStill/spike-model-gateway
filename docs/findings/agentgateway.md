# agentgateway

What agentgateway v1.7.0 does in front of the four vLLM rows, run as a container on gb10-2. The
finding covers pass-through under purpose aliases, gateway-issued keys, what the gateway adds to
latency and what it costs in CPU and memory, the fence that leaves it the only path to the rows,
what a client sees at each row's cap, and what agentgateway lacks for admission and overflow
(evidence 1–4 and 8 of [`context/README.md`](../../context/README.md#the-evidence)).

- **Measured:** from 2026-11-13. Each slice's section gives the date and time of its runs.
- **Gateway:** agentgateway v1.7.0, the official image `cr.agentgateway.dev/agentgateway:v1.7.0`
  (released 2026-10-27, published for arm64), configured from
  [`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml).
- **Engine:** vLLM v0.33.0: `vllm/vllm-openai:v0.33.0` on the GB10s;
  `vllm/vllm-openai-rocm:v0.33.0` (embedding) and spike-model-engines' own
  `vllm-openai-rocm-audio:v0.33.0` build (audio) on the Framework. The rows serve from
  spike-model-engines `host/` at `261879e`, the merge of its pull request #17, which serves each
  row under its alias as its only model name.
- **Bench:** GuideLLM 0.8.1 from the laptop (`mise.bench.toml`).
- **Network path:** the laptop reaches all three hosts directly over Tailscale, with no relay
  (`tailscale ping`, 2026-11-13 11:09 and again at 11:26, after the host updates). The gateway
  reaches the rows from gb10-2 over the tailnet. No tailnet or LAN address is recorded here.

The hosts, as read on 2026-11-13 after the morning's updates (raw read-outs untracked under
`.state/agentgateway/`):

| Host | Purpose (row, port) | Kernel | NVIDIA driver | Docker | Tailscale |
| --- | --- | --- | --- | --- | --- |
| gb10-1 | agent, 8000 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 1.104.7 |
| gb10-2 | vision, 8000; the gateway, 3000 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 1.104.7 |
| framework | audio, 8001; embedding, 8002 | 7.2.15-1-omarchy | — | 29.9.2 | 1.104.2 |

Each row publishes its port on its host's tailnet address only.

## agentgateway

agentgateway is an open-source proxy for AI traffic, written in Rust, and a Linux Foundation
project under the Apache-2.0 license. It fronts LLM providers, MCP servers, and agent-to-agent
traffic. It runs standalone from one YAML file, as here, or in Kubernetes behind its Gateway API
controller. This task is its first use in the experiment, and it is the task's one new tool.

**How it is set up here.** One container on gb10-2, from the official image, started with
`--restart unless-stopped` so it comes back with the host. It reads one file, `config.yaml`, from a
directory mounted read-only, and watches the file: a changed file is reloaded in place with no
restart, so deploying a config change (a route, a key revoked) never drops the connections that
are running. Settings under `config:` are read once, at start. The image runs as the deploying
user. [`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh)
(`mise run agentgateway-deploy`) copies the file, validates it with the pinned image, moves it into
place, and creates the container only when its image or flags change.

**What it provides, as used in this task:**

- **Path routes.** A route matches a path prefix and rewrites it before forwarding. Each alias's
  base URL, `/<alias>/v1`, is a route to its row's `/v1`.
- **LLM pass-through that reads usage.** A route whose backend is an `ai` provider is LLM traffic.
  Its route type decides what agentgateway does with a request: translate between API formats,
  answer itself, or pass through. The `detect` route type forwards the request unchanged and reads
  the model and token usage from the reply, streamed or not, for its logs, metrics, and rate limits.
- **Consumer API keys.** An `apiKey` policy in `strict` mode admits only requests with a listed
  key, read from the `Authorization: Bearer` header by default and removed before forwarding. A key
  is listed by its sha256 hash, with metadata naming it.
- **Limits** (probed in slice 3): request-rate and token-rate limits per route or per key, and a
  global in-flight limit.
- **Admin API and UI.** On the container's own loopback, port 15000, by default. The UI can also be
  served on a gateway of its own; here it is read-only (`config.storage.mode: readOnly`), so a save
  from the UI answers 403 and git stays the only source of configuration.

## The configuration

[`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml), with the image and
ports in [`gateway/agentgateway/deploy.env`](../../gateway/agentgateway/deploy.env). It validates
against v1.7.0's JSON schema (`schema/config.json` at the `v1.7.0` tag, checked with
check-jsonschema on 2026-11-13). The schema doesn't check a `keyHash`'s format or a backend's host;
the deploy's `--validate-only` run with the pinned image does, and the live bring-up proves the
rest.

**The routing form.** agentgateway has a simple `llm` section and a routing form (`gateways` and
`routes`). The `llm` section serves its models under one path prefix, and the four aliases need four
base URLs, so the config uses the routing form. (The older `binds` and `listeners` form is
deprecated in v1.7.0 in favour of `gateways` and `routes`.)

**Detect pass-through.** Each alias route sets `policies.ai.routes: {"*": detect}`, so every path
under it is the `detect` route type: forwarded as is, with usage read from the reply. Without a
route-type map, a routing-form `ai` backend parses every path as Chat Completions, and a path mapped
to the `models` route type is answered by agentgateway itself with 501. With `"*": detect`,
`/v1/models` reaches the row, which lists exactly its alias. Sources at `v1.7.0`:

- The docs' "Passthrough" page (`documentation/llm/api-types/passthrough.md`): in the routing form,
  pass-through is configured by mapping the `*` path to a route type, and `detect` is the
  pass-through that "still extract[s] token usage and rate-limit data".
- `crates/agentgateway/src/llm/policy/mod.rs`, `resolve_route`: the map is matched by path suffix,
  with `*` last; with no match and no `*`, the route type is `completions`.
- `crates/agentgateway/src/proxy/httpproxy.rs`: `resolve_llm_route_type` falls back to
  `Completions` when a route has no map, and the `RouteType::Models` arm answers 501
  ("Route 'Models' not implemented").
- `crates/agentgateway/src/llm/mod.rs`, `set_default_path`: a `detect` request keeps its path
  unless the provider sets a `pathPrefix`; and `process_detect_request` forwards the body as sent.

The backend is a `custom` provider with no `formats`, which the docs recommend over `openAI` for an
OpenAI-compatible server (`integrations/llm/providers/custom.md`): it translates nothing.
`hostOverride` names the row by short host name and port, and with a host override agentgateway adds
no TLS, so it speaks plain HTTP to the row over the tailnet.

**Nothing else is routed.** The four routes match `/<alias>/v1` and below. Any other path, vLLM's
root routes among them (`/metrics`, `/health`, `/tokenize`, `/docs`), matches no route, so it
should answer 404 once a key is admitted and 401 without one; slice 1 checks both.

**Keys on the gateway.** The `apiKey` policy sits on the `consumer` gateway, not on each route: a
gateway policy runs before a route is chosen (`types/local.rs` attaches it in
`PolicyPhase::Gateway`), so it covers all four routes and every unrouted path, and the key list is
written once, so a key is revoked by deleting one entry.

**The ports.**

- **3000, the consumer port**, published on gb10-2's tailnet address only (`--publish
  "$(tailscale ip -4):3000:3000"`, evaluated on gb10-2). It is clear of the vision row's 8000 on
  the same host and the Framework's 8001 and 8002; of LiteLLM's default 4000, since both gateways
  run on gb10-2 in task `litellm`; and of llama.cpp's 8080, inert on the hosts. It is the port of
  agentgateway's own routing examples.
- **3001, the UI**, on a gateway of its own (`ui.gateways: ui`), published on gb10-2's loopback only
  and reached through an SSH tunnel. The consumer gateway isn't named `default`, since the UI
  attaches itself to a gateway of that name when `ui.gateways` is unset.
- **15000, the admin API**, on the container's loopback only (`config.adminAddr`), as the docs
  advise: its debug, config-dump, and shutdown endpoints are unauthenticated. No published port
  reaches it. The stats (15020) and readiness (15021) ports listen inside the container and are not
  published.

**Short host names in the container.** The container runs on Docker's default bridge, whose DNS
comes from the host's resolver configuration. Whether that resolves `gb10-1` and `framework` through
MagicDNS is not known before the bring-up, so the session checks it first, read-only (below). If it
doesn't, the container gets each row's host from gb10-2 at start, with `--add-host
"gb10-1:$(tailscale ip -4 gb10-1)"` and `--add-host "framework:$(tailscale ip -4 framework)"`,
still with no address written down.

## Keys

Each consumer key is a random 256-bit value, written as 64 hex characters, and lives in the
architect's keeper or in `.state/agentgateway/keys/`, untracked. Only its hash is committed, in
`config.yaml`, as `keyHash: sha256:<hex>`: the lowercase hex sha256 of the key's exact characters,
with no newline, which is how agentgateway hashes a presented key (`APIKeyHash::from_raw_key` in
`crates/agentgateway/src/http/apikey.rs`). `sha256sum` of agentgateway's own test key gives the hash
its tests expect. A consumer sends the key as `Authorization: Bearer <key>`.

On the laptop, from the repository root, for each key named in `config.yaml`:

```sh
mkdir -p .state/agentgateway/keys && chmod 700 .state/agentgateway/keys
for name in architect bench go-ai revoke-test; do
  key=.state/agentgateway/keys/$name
  [ -e "$key" ] || (umask 077 && openssl rand -hex 32 > "$key")
  printf '%s sha256:%s\n' "$name" "$(printf %s "$(cat "$key")" | sha256sum | cut -d' ' -f1)"
done
```

A key file that exists is kept, so a rerun prints the same hashes. Each printed hash replaces its
name's all-zero placeholder in `config.yaml`, which matches no key; the config is committed with
the hashes, then deployed. To revoke a key, delete its entry and deploy: the reload takes effect
with no restart, and requests already running finish.

## Slice 1 · bring-up and pass-through

Behaviors 1–5 and 14. The host updates and row restarts of 2026-11-13 come first, under
"Commands as run". Behavior 14, `mise run currency` reporting the agentgateway pin, holds:
`gateway/agentgateway/deploy.env: agentgateway <pin> -> <latest>` when the pin is behind its
latest GitHub release, nothing when current; on 2026-11-13 it reports only the held Python.

### Before the walk

The session runs these read-only checks. Each row lists exactly its alias (behavior 1), from the
laptop:

```sh
for row in agent:gb10-1:8000 vision:gb10-2:8000 audio:framework:8001 embedding:framework:8002; do
  printf '%s: ' "${row%%:*}"; curl -sS "http://${row#*:}/v1/models" | jq -r '[.data[].id] | join(",")'
done
```

Whether a container on gb10-2 resolves the rows' short names, with an image gb10-2 already holds:

```sh
ssh gb10-2 'for h in gb10-1 gb10-2 framework; do docker run --rm --entrypoint getent vllm/vllm-openai:v0.33.0 hosts "$h" >/dev/null && echo "$h resolves" || echo "$h does not resolve"; done'
```

### The walk

The architect's first walk of agentgateway, by hand, the steps `mise run agentgateway-deploy` takes
afterwards. On the laptop, from the repository root, generate the keys and put their hashes in
`config.yaml` ("Keys"), then:

```sh
ssh gb10-2
```

On gb10-2:

```sh
docker pull cr.agentgateway.dev/agentgateway:v1.7.0
mkdir -p ~/agentgateway
```

On the laptop, copy the config:

```sh
ssh gb10-2 'cat > ~/agentgateway/config.yaml' < gateway/agentgateway/config.yaml
```

On gb10-2, validate it with the image, start the container, and read its log. The label is the
hash the deploy script gives these flags, so its next run finds this container current and only
refreshes the config.

```sh
docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml --validate-only
docker run --detach --name agentgateway --restart unless-stopped --user "$(id -u):$(id -g)" --publish "$(tailscale ip -4):3000:3000" --publish 127.0.0.1:3001:3001 --volume "$HOME/agentgateway:/config:ro" --add-host "gb10-1:$(tailscale ip -4 gb10-1)" --add-host "gb10-2:$(tailscale ip -4 gb10-2)" --add-host "framework:$(tailscale ip -4 framework)" --label spike.spec=e1d1d93a9f78 cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml
docker logs agentgateway
docker port agentgateway | sed "s/$(tailscale ip -4)/<tailnet>/"
```

The log names the config file it loaded and watches, and the ports it bound. `docker port` shows
3000 on the tailnet address and 3001 on 127.0.0.1, and nothing for 15000.

On the laptop, the first requests: with no key, then with the architect's key, listing the agent
alias's models and sending a chat.

```sh
curl -sS -o /dev/null -w '%{http_code}\n' http://gb10-2:3000/agent/v1/models
curl -sS -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" http://gb10-2:3000/agent/v1/models | jq -r '.data[].id'
curl -sS -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256}' http://gb10-2:3000/agent/v1/chat/completions | jq '{model, content: .choices[0].message.content, usage}'
```

The first answers 401, the second `agent`, and the third a reply with its token usage. On gb10-2,
`docker logs --tail 3 agentgateway` shows the chat's log line, with the model and the token usage
that detect read from the reply.

The admin UI, through an SSH tunnel to gb10-2's loopback, from the laptop; then open
<http://localhost:3001/ui> in a browser and stop the tunnel with Ctrl-C when done:

```sh
ssh -N -L 3001:127.0.0.1:3001 gb10-2
```

Neither the UI nor the admin API is on the consumer port, from the laptop: the first answers 404,
and the second prints 000, since nothing on gb10-2 listens on 15000.

```sh
curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" http://gb10-2:3000/ui
curl -sS -m 5 -o /dev/null -w '%{http_code}\n' http://gb10-2:15000/ui
```

### After the walk

The session, through each alias with a valid key, against the same request sent direct: agent chat,
streamed chat, Messages, and Responses; vision chat with an image; audio chat with an audio clip;
embeddings; each alias's `/models`. Then no key, an unknown key, and `revoke-test` revoked (its
entry deleted and deployed, with a request running across the reload); vLLM's root routes and
agentgateway's admin paths with a consumer key, and a dot-segment path such as
`/agent/v1/../../metrics` sent with `curl --path-as-is`.

Results: pending.

## Slice 2 · overhead

Behavior 7: the overhead cells, direct, gateway, direct per purpose, while the laptop still reaches
the rows. Pending.

## Slice 3 · fence, caps, probes, go-ai and infer, inventory

Behaviors 6 and 8–13: the fence, the cap cells, the 429 and 503 probes, go-ai's integration tier and
infer through the gateway, and the paper inventory of what agentgateway provides for overflow and
for admission on vLLM's live metrics. Pending.

## Slice 4 · walkthrough

The architect's walkthrough from this finding: an alias's `/models`, a chat with and without a key,
a revoked key, a direct row request refused, and the gateway container's read-outs. Pending.

## Commands as run

Every command run, exactly as run, with its time, from `.state/agentgateway/commands-*.log`; the
output stays there, untracked.

### 2026-11-13 · host updates and row restarts

The architect's root steps, before the session's: on gb10-1 and gb10-2, in tmux,

```sh
sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y && cat /var/run/reboot-required 2>/dev/null; echo "exit $?"
```

which upgraded 14 packages on each, Tailscale and libc among them, and asked for a restart on
gb10-1; both GB10s were then rebooted (`sudo reboot`). On the Framework, `omarchy update`, with no
reboot. The session's, once spike-model-engines' pull request #17 was merged:

```text
+ 2026-11-13T11:26:17-05:00 gb10-1: git -C ~/repos/spike-model-engines pull --ff-only -q && git -C ~/repos/spike-model-engines log --oneline -1
+ 2026-11-13T11:26:17-05:00 gb10-2: git -C ~/repos/spike-model-engines pull --ff-only -q && git -C ~/repos/spike-model-engines log --oneline -1
+ 2026-11-13T11:26:17-05:00 framework: git -C ~/repos/spike-model-engines pull --ff-only -q && git -C ~/repos/spike-model-engines log --oneline -1
+ 2026-11-13T11:26:34-05:00 gb10-1: cd ~/repos/spike-model-engines && time VLLM_MODEL=gpt-oss-120b-agent-fp8 host/engines vllm update
+ 2026-11-13T11:26:34-05:00 gb10-2: cd ~/repos/spike-model-engines && time VLLM_MODEL=gemma-4-26B-A4B-NVFP4-vision-gb10 host/engines vllm update
+ 2026-11-13T11:26:34-05:00 framework: cd ~/repos/spike-model-engines && time VLLM_MODEL=gemma-4-E4B-it-audio-framework host/engines vllm update
+ 2026-11-13T11:26:34-05:00 framework: cd ~/repos/spike-model-engines && time VLLM_MODEL=granite-embedding-english-r2-framework host/engines vllm update
```

Each host's checkout came to `261879e`, and each update restarted its row's container under the
row's new flags, exiting 0.
