# agentgateway

What agentgateway v1.7.0 does in front of the four vLLM rows, run as a container on gb10-2. The
finding covers pass-through under purpose aliases, gateway-issued keys, what the gateway adds to
latency and what it costs in CPU and memory, what a client sees at each row's cap, and what
agentgateway lacks for admission and overflow (evidence 1–4 and 8 of
[`context/README.md`](../../context/README.md#the-evidence)).

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
- **Log lines:** agentgateway's access log carries `src.addr`, the caller's tailnet address, so any
  log line quoted here has it replaced with `<laptop>`. No key, key prefix, or key hash is quoted.

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
(`mise run agentgateway-deploy`) fills each consumer key's hash into a copy of the file ("Keys"),
copies that, validates it with the pinned image, moves it into place, and creates the container
only when its image or flags change.

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

Each consumer key is a random 256-bit value, written as 64 hex characters, kept on the deploying
machine in `.state/agentgateway/keys/<name>`, untracked (the directory 0700, each file 0600).
Only the key names are committed. In `config.yaml` each entry's `keyHash` is the marker
`sha256:@@<name>@@`, beside `metadata: name: <name>`, so the entries are the list of keys that
exist. A consumer sends its key as `Authorization: Bearer <key>`.

agentgateway lists a key by `keyHash: sha256:<hex>`: the lowercase hex sha256 of the key's exact
characters, with no newline, which is how it hashes a presented key (`APIKeyHash::from_raw_key` in
`crates/agentgateway/src/http/apikey.rs`). `sha256sum` of agentgateway's own test key gives the hash
its tests expect.

[`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh) fills the hashes in on each
deploy, before it sends anything. It reads the names from the markers, creates any key the machine
lacks (`openssl rand -hex 32`) and reuses any it has, and renders a copy of `config.yaml` with each
marker replaced by its key's `sha256:<hex>`, in a temporary file under `.state/agentgateway/`,
removed on exit. It stops, sending nothing, if a marker or a `keyHash` that isn't a full hash is
left in the copy. That copy, not the committed file, goes to gb10-2. It prints each name as
`key <name>: created` or `key <name>: existing`, and no key or hash. Because existing keys are
reused, a re-run renders the same copy.

Adding an entry and deploying issues a key. Removing an entry and deploying revokes that key: the
reload takes effect with no restart, and requests already running finish.

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

The architect's first walk of agentgateway. First read
[`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh), then, on the laptop, from
the repository root, run it once:

```sh
mise run agentgateway-deploy
```

It prints `key <name>: created` for each of the four keys and each command it runs on gb10-2, and
ends with the container's `docker ps` line.

**What the deploy does underneath.** The same steps by hand, for reading the mechanics; the walk
doesn't run them. On the laptop, for each name in `config.yaml`, create the key if it is missing,
then render a copy with each marker replaced by its key's hash and send it:

```sh
mkdir -p .state/agentgateway/keys && chmod 700 .state/agentgateway/keys
name=architect; key=.state/agentgateway/keys/$name
[ -e "$key" ] || (umask 077 && openssl rand -hex 32 > "$key")
hash=$(printf %s "$(cat "$key")" | sha256sum | cut -d' ' -f1)
# ...and so for each name, replacing sha256:@@<name>@@ with sha256:$hash in a copy under .state/
ssh gb10-2 'mkdir -p ~/agentgateway && cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.yaml
```

On gb10-2, pull the image, validate the copy with it, move it into place, and start the container.
The label is the hash the deploy script gives these flags, so its next run finds this container
current and only refreshes the config.

```sh
docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
docker run --detach --name agentgateway --restart unless-stopped --user "$(id -u):$(id -g)" --publish "$(tailscale ip -4):3000:3000" --publish 127.0.0.1:3001:3001 --volume "$HOME/agentgateway:/config:ro" --add-host "gb10-1:$(tailscale ip -4 gb10-1)" --add-host "gb10-2:$(tailscale ip -4 gb10-2)" --add-host "framework:$(tailscale ip -4 framework)" --label spike.spec=e1d1d93a9f78 cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml
```

**Reading what it did.** On gb10-2:

```sh
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

The key isn't logged, though the gateway has now read it in each request: on the laptop, search
the container's log for the first 8 characters of the architect's key, which prints nothing.

```sh
ssh gb10-2 docker logs agentgateway 2>&1 | grep -F "$(cut -c1-8 .state/agentgateway/keys/architect)"
```

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

### Results

Run on 2026-11-13: the host updates from 11:09 to 11:26, the row restarts at 11:26–11:27, the
deploy and the architect's walk from 13:29, the session's probes from 13:37 to 13:39, and gb10-2's
reboot from 16:05 to 16:12. Every
command, as run, is under "Commands as run"; the requests quoted here are the session's, from the
laptop, where `$GW` is `http://gb10-2:3000`, `$K` the architect's key, and `$R` revoke-test's.

**The hosts, at session start.** On the GB10s the architect's `apt full-upgrade` upgraded 14
packages each, libc6 and tailscale among them, run in tmux; gb10-1 asked for a restart, and both
GB10s were rebooted. On the Framework, `omarchy update` upgraded gliff and mise-bin, with no
reboot. After the updates the GB10s run kernel 7.0.0-1025-nvidia, driver 580.178.04, Docker
29.6.2, and Tailscale 1.104.7, and the Framework Tailscale 1.104.2 (the table above). Every
`tailscale ping` from the laptop is direct, at 1 ms or less, before and after. gb10-1 still lists 3
phased apt updates (distro-info, python3-distro-info, snapd), held back by Ubuntu's phasing.

**Behavior 1: each row serves its alias.** spike-model-engines pull request #17, merged as
`261879e`, adds `--served-model-name` to the four standing rows, and its LICENSE. Each host pulled
it and restarted its rows with `host/engines vllm update` at 11:26–11:27, each update exiting 0 in
under 2 s. Counted from 11:27:23, when polling started, each row answered healthy with its
`/v1/models` listing exactly its alias: embedding at 0 s (`["embedding"]`), audio at 20 s
(`["audio"]`), vision at 130 s (`["vision"]`), and agent at 411 s (`["agent"]`).

**Behavior 2: the deploy, its listeners, and the UI.**

- **Short names.** A container on gb10-2's default bridge resolves none of `gb10-1`, `gb10-2`, and
  `framework`, so the deploy passes each row's host with `--add-host`, as "Short host names in the
  container" provides.
- **The deploy.** `mise run agentgateway-deploy` created the four keys, pulled the image (digest
  `sha256:60216aafb03d…`), validated the rendered copy ("Configuration is valid!"), moved it into
  place, and started the container with label `spike.spec=e1d1d93a9f78`.
- **The listeners**, from `docker logs agentgateway`: the config loaded from and watched at
  `/config/config.yaml`; the consumer gateway on 3000, published on the tailnet address; the UI on
  3001, published on loopback; the admin API on 127.0.0.1:15000 and [::1]:15000 inside the
  container; readiness on [::]:15021 and stats on [::]:15020 inside the container, unpublished.
  The log also warns that no session key is set, which concerns MCP sessions, unused here.
- **`docker port`** shows only `3000/tcp -> <tailnet>:3000` and `3001/tcp -> 127.0.0.1:3001`.
- **From the laptop,** 15000 is refused (`000`), and `/ui` on 3000, with a key, answers 404.
- **The UI** through `ssh -N -L 3001:127.0.0.1:3001 gb10-2`, over Tailscale SSH, shows the
  read-only mode banner, the warning "UI is exposed without authentication", 2 gateways, and 4
  routes.
- **Restart, unattended: shown by a reboot.** The architect rebooted gb10-2 (`sudo reboot`, time
  not recorded) while the laptop polled the gateway's `/agent/v1/models` and the vision row's
  `/health` every 5 s from 16:05:04. Both stopped answering at 16:09:02, and gb10-2 booted at
  16:09:18 (`uptime -s`). The gateway answered again at 16:09:38, 36 s after it went down, with no
  step by anyone: Docker restarted the container under its `restart=unless-stopped` policy
  (`started=2026-11-13T21:09:29Z`, `restarts=0`), and the live config read `# overlays: none`. The
  vision row's `/health` answered at 16:12:14, 192 s after down. At 16:12:20–21 every
  `/<alias>/v1/models` listed its alias, and a keyless request got 401.

**Gap: the UI has no authentication of its own.** Access to it rests on gb10-2's loopback and SSH
to gb10-2, nothing else. Authenticating the UI with JWT or OIDC is on the paper list for slice 3's
inventory.

**Behavior 3: pass-through under each alias.**

- **Models.** Every `/<alias>/v1/models` lists exactly its alias: `["agent"]`, `["vision"]`,
  `["audio"]`, `["embedding"]`.
- **Agent.** A chat (the walk's, "Hello there, wonderful dear friend!", 73 tokens in and 198 out,
  181 of them reasoning); a streamed chat, 43 `data:` events; Messages, `"stop_reason":"end_turn"`
  with the text `"Red."`; and Responses, `"status":"completed"` with the text `"Mars."`.
- **Vision** read `"GATEWAY 7319"` from a generated 1280×720 JPEG.
- **Audio** transcribed a 6 s clip as "And um, this is what we're going to be doing over the next";
  the same request sent direct to the row gave the same text without the comma. (The first attempt
  passed the clip as a jq argument, which the laptop's shell refused as too long, so nothing was
  sent; the rerun reads it with `--rawfile`.)
- **Embedding.** 2 inputs, 2 vectors of 768 dimensions.
- **No crossing aliases.** A chat naming `vision` sent to `/agent/v1` reached the agent row, which
  refused it: "The model `vision` does not exist. Valid aliases: agent." The route decides the row,
  and the row serves only its alias.
- **Direct, at review.** The same requests sent direct to the rows, with no key, ran at
  15:18:56–15:19:03, after the slices, at review. Each answered as through the gateway:
  - agent chat: "Hello, how are you today?", 163 tokens;
  - agent stream: 43 `data:` events, the same as through the gateway;
  - Messages: "Red.", `end_turn`;
  - Responses: "Mars.", `completed`;
  - vision: "GATEWAY 7319", 300 tokens, the same as through the gateway;
  - embedding: 2 vectors of 768.

  The agent's replies and token counts differ from the gateway's in wording and in the reasoning
  tokens sampled, as any two runs do. Audio was compared direct at 13:37:23, above.
- **Usage read by detect.** The gateway's log line for the walk's chat carries `protocol=llm`,
  `op=chat`, `model=agent`, and the token usage read from the reply: 73 in, 198 out, 181
  reasoning, in 5,576 ms. The `/models` request's line names `route=default/agent` and
  `endpoint=gb10-1:8000`.

**Behavior 4: keys and revocation.**

- **Refused.** No key, an empty Bearer (`Authorization: Bearer `), and a random 64-hex key all get
  401. The log line for the walk's keyless request gives `reason=APIKeyAuth` ("no API Key found")
  in 0 ms and names no route: the gateway policy refuses before routing.
- **Revocation, first run.** A long streamed chat on revoke-test started at 13:38:00 and finished
  at 13:38:41, before the revoke at 13:38:45, so it shows nothing about requests in flight. The
  revoke-test request sent within a second of the deploy still got 200: the gateway logged
  `loaded config` at 13:38:46.914, just under 1 s after the move, and the request beat the
  reload. From the reload on, the key gets 401, as the second run shows.
  The entry was then restored and deployed again, and revoke-test readmitted (200), for a second
  run.
- **Revocation, second run, during a stream.** The same streamed chat on revoke-test, started at
  13:39:15. At 13:39:21 it had 206 `data:` events; the entry was deleted and deployed; at 13:39:24
  the stream stood at 305 events, and a new request on the same key got 401. The stream ran on to
  1,341 events and ended with `"finish_reason":"stop"`, curl exiting 0 at 13:39:53. A revoke
  refuses new requests on the key and lets the running one finish.
- **revoke-test stays revoked.** Its entry is removed from
  [`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml) and deployed; the
  key file stays on the laptop and is listed nowhere.

**Behavior 5: nothing but the four aliases is routed.**

- **Unrouted paths.** With a valid key, `/metrics`, `/health`, `/version`, `/tokenize`, `/docs`,
  `/openapi.json`, `/v1/models`, `/agent/metrics`, `/agent/health`, and `/AGENT/v1/models` all get
  404 "route not found" from the gateway: route matching is case-sensitive, and an alias's routes
  start at `/<alias>/v1`.
- **Without a key,** `/metrics` gets 401: the key policy runs before routing, so an unrouted path
  is refused the same as a routed one.
- **Dot segments.** `/agent/v1/../../metrics`, `/agent/v1/%2e%2e/%2e%2e/metrics`, and
  `/agent/v1/..%2f..%2fmetrics`, sent with `curl --path-as-is`, also got 404, but not from the
  gateway (below).

**Finding: agentgateway does not normalize dot segments.** All three dot-segment paths matched the
agent route and were forwarded to gb10-1 (log `route=default/agent endpoint=gb10-1:8000`); the
404 is the row's. Nothing is exposed today, because vLLM doesn't resolve those paths to its root
routes, but that is what protects `/metrics` and the rest through the agent route, not the gateway.
The paper inventory in slice 3 weighs the hardening: an authorization rule in agentgateway's native
CEL, or a regex path match on each route, refusing `..` and its encodings (`%2e%2e`, `%2f`) before
a request is routed. No network rule could cover it either, since these requests come from the
gateway itself.

**The key is never logged.** A search of the full container log for the first 8 characters of the
architect's key, after the walk's requests, found nothing (grep exit 1).

**Behavior 14: currency.** `mise run currency` reports only python, which is held; the agentgateway
pin is current.

## Slice 2 · overhead

Behavior 7: the overhead cells, direct, gateway, direct per purpose, the direct runs sent from the
laptop to each row. Run on 2026-11-13 from 13:55 to 14:14; the results are under "Results" below.

### The plan

Four cells, one a purpose, each run three times in one session, purpose by purpose: direct to the
row, then through the gateway, then direct again. Every run is GuideLLM 0.8.1 from the laptop, the
model sent as the alias and its tokenizer given separately. The loads are spike-model-layout's
targets, and the scenarios are copied from the files it ran them with
([`bench/README.md`](../../bench/README.md)). The runs need the rows otherwise idle.

| Run | Scenario | Target | Base URL | Load |
| --- | --- | --- | --- | --- |
| `o-agent-d1`, `o-agent-d2` | `overhead-agent` | direct | `http://gb10-1:8000/v1` | 4-turn synthetic sessions, 8,192 tokens then 512 a turn, 512 out a turn; 4 concurrent; 110 s |
| `o-agent-g` | `overhead-agent` | gateway | `http://gb10-2:3000/agent/v1` | as above |
| `o-vision-d1`, `o-vision-d2` | `overhead-vision` | direct | `http://gb10-2:8000/v1` | a synthetic 1440p JPEG and 200 text tokens, 100 out; 4 concurrent; 90 s |
| `o-vision-g` | `overhead-vision` | gateway | `http://gb10-2:3000/vision/v1` | as above |
| `o-audio-d1`, `o-audio-d2` | `overhead-audio` | direct | `http://framework:8001/v1` | LibriSpeech dummy clips as 16 kHz WAV in chat with the card's prompt, at most 256 out; 4 concurrent; 30 s or 64 requests |
| `o-audio-g` | `overhead-audio` | gateway | `http://gb10-2:3000/audio/v1` | as above |
| `o-embed-d1`, `o-embed-d2` | `overhead-embed` | direct | `http://framework:8002/v1` | 512 synthetic tokens; a constant 34 requests a second; 60 s |
| `o-embed-g` | `overhead-embed` | gateway | `http://gb10-2:3000/embedding/v1` | as above |

Twelve runs, about 15 minutes of load in all (agent 330 s, vision 270 s, audio at most 90 s,
embedding 180 s), plus GuideLLM's start-up before each, its tokenizer and data read from the
laptop's caches; each is capped at 10 minutes.

**The helpers.** [`scripts/measure-lib.sh`](../../scripts/measure-lib.sh), adapted from
spike-model-layout's: `cell` runs one scenario against one target, `summarize` reads a run, and
`compare` reads a cell's three runs (below). Every helper call and the commands it runs are
appended to `.state/agentgateway/commands-<date>.log`, the log "Commands as run" quotes.

**The key.** A gateway run sends the `bench` key, which the deploy created in slice 1. `cell` reads
it from `.state/agentgateway/keys/bench` with bash's `$(<file)`, inside the run's subshell with
xtrace off, into GuideLLM's environment as `GUIDELLM__SPEC__BACKEND__API_KEY`. It is never in a
process's argv, and the log shows only the expression. GuideLLM 0.8.1 reads that variable into its
backend's `api_key`, a pydantic `SecretStr` (`schemas/backends/openai_http.py`), which every dump
of the run's config writes as `"**********"`, the result JSON's and the console's alike; it adds
the `Authorization: Bearer` header only as it sends each request (`backends/openai/http.py`,
`_build_headers`), so no request record carries it. GuideLLM's own CLI flag,
`--backend kind=openai_http,api_key=...`, would put the key in argv, so it is not used. After each
gateway run, `cell` searches the run's files for the key, reading the pattern from the key file
(`grep -F -f`), and prints whether it was found. A direct run sends no key.

**Same requests both ways.** GuideLLM checks the backend before a run with `GET <target>/health`,
the target's `/v1` cut off. Through the gateway that is `/<alias>/health`, which no route serves
(404, slice 1), so each scenario points the check at `/v1/models`, direct and through the gateway
alike; through the gateway it also proves the key before any load is sent. Each run has its own
seed, from its name (`--seed kind=static,value=<cksum of the name>`): with GuideLLM's default seed
every run would send the same synthetic prompts and images, and the row's prefix cache would serve
the gateway run and the second direct run what the first sent. The audio clips come from a dataset
and are the same in every run, so in O-audio the rows' prefix cache may favour the later runs;
`o-audio-d2` against `o-audio-d1` shows how much.

**Two things the cells share with the layout.** The gateway runs on gb10-2 beside the vision row,
so in O-vision the gateway's CPU comes from the vision row's host. And the agent cell completes
few requests in 110 s (spike-model-layout's run at 4 completed 12), so its p95s rest on few
samples; its medians are the reading.

### The steps

The session runs these, one at a time, in the architect's view, on the laptop from the repository
root. First, read-only: each row lists its alias, and the gateway
container's idle CPU and memory.

```sh
for row in agent:gb10-1:8000 vision:gb10-2:8000 audio:framework:8001 embedding:framework:8002; do
  printf '%s: ' "${row%%:*}"; curl -sS "http://${row#*:}/v1/models" | jq -r '[.data[].id] | join(",")'
done
ssh gb10-2 docker stats --no-stream agentgateway
```

Then the helpers, and the twelve runs, each cell's three back to back and read together:

```sh
source scripts/measure-lib.sh

cell o-agent-d1 overhead-agent direct agent
cell o-agent-g overhead-agent gateway agent
cell o-agent-d2 overhead-agent direct agent
compare o-agent-d1 o-agent-g o-agent-d2

cell o-vision-d1 overhead-vision direct vision
cell o-vision-g overhead-vision gateway vision
cell o-vision-d2 overhead-vision direct vision
compare o-vision-d1 o-vision-g o-vision-d2

cell o-audio-d1 overhead-audio direct audio
cell o-audio-g overhead-audio gateway audio
cell o-audio-d2 overhead-audio direct audio
compare o-audio-d1 o-audio-g o-audio-d2

cell o-embed-d1 overhead-embed direct embedding
cell o-embed-g overhead-embed gateway embedding
cell o-embed-d2 overhead-embed direct embedding
compare o-embed-d1 o-embed-g o-embed-d2
```

Each `cell` follows GuideLLM's output in the terminal and ends with its exit, the key check on a
gateway run, and `summarize`. Ctrl-C stops a run; a stopped or failed run is rerun under a new
name (`o-agent-g2`), since `cell` refuses a name it has used.

### How the result is read

Per behavior 7, the gateway's cost is read against run noise, figure by figure: the median and p95
of TTFT, ITL, and request latency (embedding: request latency only, since an embedding has no
tokens to stream). `compare` prints, for each:

- **the spread**, `|d1 − d2|`, the two direct runs' difference: what the same load gives twice;
- **what the gateway adds**, `g − (d1 + d2) / 2`, the gateway run against the mean of the direct
  runs around it, so a drift across the three runs is split, not charged to the gateway;
- **within** when what it adds is no larger than the spread: at this load the gateway's cost is
  indistinguishable from run noise; **beyond** when it is larger: the finding states the added
  figure as the gateway's cost, in ms and as a share of the direct mean.

A run with errored requests, or a cell where the two direct runs disagree widely, is reported as
such before any reading of it. Beside each gateway run, the container's CPU and memory during the
benchmark: `summarize` gives the samples' median and maximum CPU (docker's figure, 100% being one
of gb10-2's cores) and memory (MiB), counting only the samples inside the benchmark's own start
and end, so GuideLLM's start-up, when the gateway idles, is left out.

### Where the samples land

Untracked, under `.state/agentgateway/`:

- `cells/<run>/result.json`: GuideLLM's result, every request's timings;
- `cells/<run>/guidellm.log`: GuideLLM's console output;
- `cells/<run>/exit`: the run's exit status;
- `cells/<run>/gateway-stats.tsv`, gateway runs only: one row each 5 s
  (`MEASURE_STATS_EVERY`) from `docker stats --no-stream` on gb10-2: the epoch, the time, the
  container's CPU and memory, a row of dashes where a read failed;
- `commands-<date>.log`: every helper call and command, and what `cell`, `summarize`, and
  `compare` printed.

### Results

Run on 2026-11-13: the pre-checks at 13:55:41, the twelve runs from 13:55:49 to 14:13:53, each
cell's three back to back, purpose by purpose, as planned. Every command, as run, is under
"Commands as run". The figures are `summarize`'s and `compare`'s, read again from each run's
`result.json` after the session.

**The pre-checks.** Each row listed exactly its alias, direct from the laptop: `["agent"]`,
`["vision"]`, `["audio"]`, `["embedding"]`. The gateway container, idle, used 0.03% CPU and
17.22 MiB of memory.

**The runs.** All twelve exited 0, under the 10-minute cap, with no errored request. The bench key
was in none of the four gateway runs' files (`cell`'s search, after each). Requests completed per
run:

| Cell | d1 | g | d2 | Note |
| --- | --- | --- | --- | --- |
| agent | 15 | 16 | 16 | 4 incomplete each, the sessions running when the 110 s ended |
| vision | 72 | 80 | 80 | 4 incomplete each, as for agent |
| audio | 64 | 64 | 64 | the 64-request limit, reached in under 30 s |
| embedding | 2,041 | 2,040 | 2,041 | g: 1 incomplete at the end of the 60 s |

**The figures.** Medians and p95s in ms. "Spread" is `|d1 − d2|`; "gateway adds" is
`g − (d1 + d2) / 2`; the last column is `compare`'s reading.

| Alias | Figure | d1 | g | d2 | Spread | Gateway adds | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- |
| agent | TTFT median | 562.53 | 545.98 | 566.72 | 4.18 | −18.64 | beyond |
| agent | TTFT p95 | 8,061.91 | 8,059.71 | 8,069.98 | 8.07 | −6.24 | within |
| agent | ITL median | 48.49 | 46.98 | 46.69 | 1.81 | −0.61 | within |
| agent | ITL p95 | 53.03 | 54.28 | 53.91 | 0.88 | 0.81 | within |
| agent | latency median | 25,365.82 | 24,697.56 | 24,425.59 | 940.23 | −198.15 | within |
| agent | latency p95 | 32,418.99 | 31,939.17 | 32,298.33 | 120.66 | −419.49 | beyond |
| vision | TTFT median | 405.10 | 1,129.10 | 1,128.09 | 722.99 | 362.50 | within |
| vision | TTFT p95 | 436.51 | 1,167.26 | 1,133.55 | 697.04 | 382.23 | within |
| vision | ITL median | 41.61 | 33.53 | 33.72 | 7.89 | −4.14 | within |
| vision | ITL p95 | 41.93 | 35.11 | 35.21 | 6.72 | −3.46 | within |
| vision | latency median | 4,530.36 | 4,443.34 | 4,461.89 | 68.47 | −52.78 | within |
| vision | latency p95 | 4,559.96 | 4,510.19 | 4,504.18 | 55.78 | −21.88 | within |
| audio | TTFT median | 226.57 | 155.07 | 157.57 | 69.00 | −37.01 | within |
| audio | TTFT p95 | 425.18 | 206.53 | 202.69 | 222.49 | −107.40 | within |
| audio | ITL median | 52.20 | 45.61 | 45.55 | 6.65 | −3.27 | within |
| audio | ITL p95 | 57.00 | 47.66 | 47.70 | 9.30 | −4.69 | within |
| audio | latency median | 1,038.95 | 853.20 | 857.59 | 181.37 | −95.07 | within |
| audio | latency p95 | 2,356.93 | 1,880.24 | 1,917.52 | 439.41 | −256.98 | within |
| embedding | latency median | 10.17 | 13.53 | 10.05 | 0.12 | 3.42 | beyond |
| embedding | latency p95 | 11.27 | 15.56 | 10.93 | 0.34 | 4.46 | beyond |

**The gateway's CPU and memory**, from the samples inside each gateway run's benchmark (CPU in
docker's figure, 100% being one of gb10-2's cores):

| Gateway run | Samples | CPU % median / max | Memory MiB median / max |
| --- | --- | --- | --- |
| `o-agent-g` | 18 | 0.71 / 0.98 | 19.5 / 20.3 |
| `o-vision-g` | 15 | 1.61 / 2.25 | 21.3 / 22.9 |
| `o-audio-g` | 2 | 1.49 / 1.76 | 29.6 / 34.2 |
| `o-embed-g` | 9 | 2.49 / 2.70 | 22.4 / 23.7 |

No sample failed. The audio run's benchmark lasted 17 s, so its two samples are a glimpse, not a
profile. At its most the gateway used under 3% of one core and under 35 MiB, against 0.03% and
17.22 MiB idle.

**Agent: nothing measurable.** Two figures fall "beyond the spread", the TTFT median (−18.64 ms
against a 4.18 ms spread) and the request latency p95 (−419.49 ms against 120.66 ms), and both are
negative: the gateway run was faster. They are run noise the two direct runs happened not to show,
not a cost, and not a gain worth reading into. Every other
figure is within the spread. As planned, the p95s rest on 15 or 16 requests a run; the medians are
the reading, and the gateway's median TTFT and ITL sit at or below both direct runs'.

**Vision: the direct runs disagree, so request latency is the reading.** `o-vision-d1` had a TTFT
median of 405 ms and an ITL median of 41.6 ms; `o-vision-g` and `o-vision-d2` had about 1,128 ms and
33.6 ms. Request latency was flat across all three: 4.53, 4.44, and 4.46 s. The token counts are the
same in every run, 479 prompt and 100 output tokens a request, with no reasoning and no cached
tokens, so the difference is among the direct runs themselves, not the gateway's: `compare` reads
every figure "within", but against a TTFT spread of 723 ms that says little.

The session's interpretation, not proven by these runs: at a fixed concurrency of 4 with requests of
equal length, the four streams either stay staggered, each prefill interleaved with the others'
decoding, which gives a lower TTFT and a higher ITL, or fall into lockstep, all four prefilling
together and then decoding together, which gives a higher TTFT and a lower ITL. `o-vision-d1` ran
staggered and the next two in lockstep; the request takes the same time either way. Request
latency is therefore the stable vision figure: the gateway adds −53 ms to the median against a
68 ms spread, and −22 ms to the p95 against 56 ms, so nothing measurable. The gateway shares gb10-2
with the vision row, and its CPU there peaked at 2.25%.

**Audio: all within the spread.** `o-audio-d1` was slower on every figure, and `o-audio-g` and
`o-audio-d2` agree closely (latency median 853 against 858 ms). The audio clips come from a dataset
and are the same in every run, so warm caches on the row likely favour the later runs, as the plan
expected; that is the d1 to d2 spread, and it sets a wide band (69 ms on the TTFT median). Within
it, the gateway run matches the direct run after it, so no cost shows at this load.

**Embedding: the one measurable overhead.** On requests of about 10 ms, the gateway adds 3.42 ms to
the median (spread 0.12 ms), about 34% of the direct mean, and 4.46 ms to the p95 (spread 0.34 ms),
about 40%. That figure includes the extra network hop: direct, the laptop reaches the Framework;
through the gateway, the laptop reaches gb10-2, which reaches the Framework. It is the cost of the
gateway path, and so bounds agentgateway's own cost from above. On the other three purposes,
whose requests take hundreds of ms to seconds, the same few ms are lost in the run noise.

**What the cells settle.** Per the architect, these runs are a baseline and reject nothing. At
these loads agentgateway adds no cost distinguishable from run noise to agent, vision, or audio,
and at most 3.4 ms (median) to 4.5 ms (p95) to an embedding request, the hop included, for under
3% of one core and under 35 MiB of memory.

## Slice 3 · caps, probes, go-ai and infer, inventory

Behaviors 8–13: the cap cells, the 429 and 503 probes, go-ai's integration tier and infer through
the gateway, and the paper inventory of what agentgateway provides for overflow and for admission
on vLLM's live metrics. Behavior 6 is removed: by the architect's decision of 2026-11-13 (goal
record, "Decisions"), the rows stay reachable directly on the tailnet, and securing the path to
them in production belongs to the networking and platform teams. The cap cells use that direct
reach to read each row's `/metrics`. Run on 2026-11-13 from 14:43 to 14:59; the results are under
"Results" below, and the inventory, drafted from v1.7.0's docs and source, has its probe cells
filled from them.

### The cap cells

Four cells, gateway only, each one GuideLLM run of two levels, the levels run back to back within
the run. Observational: nothing stands at the caps on the gateway, so each cell shows what a client
sees there. The requests are the overhead cells', with each run's own seed
([`bench/README.md`](../../bench/README.md)).

| Run | Scenario | Base URL | Levels | Load a level |
| --- | --- | --- | --- | --- |
| `c-agent` | `cap-agent` | `http://gb10-2:3000/agent/v1` | 12, 16 sessions | O-agent's 4-turn sessions; 110 s |
| `c-vision` | `cap-vision` | `http://gb10-2:3000/vision/v1` | 16, 20 streams | O-vision's image and 200 tokens, 100 out; 60 s |
| `c-audio` | `cap-audio` | `http://gb10-2:3000/audio/v1` | 4, 8 streams | O-audio's clips; 30 s or 64 requests |
| `c-embed` | `cap-embed` | `http://gb10-2:3000/embedding/v1` | 128, 160 in flight | O-embed's 512 tokens; 60 s |

About 8.7 minutes of load in all (agent 220 s, vision 120 s, audio at most 60 s, embedding 120 s),
plus GuideLLM's start-up before each run; each run is capped at 10 minutes. C-embed holds a
number of requests in flight where O-embed sent a constant rate, since the cap is a count in
flight.

**What a cap run records.** `cell <name> <scenario> cap <alias>` in
[`scripts/measure-lib.sh`](../../scripts/measure-lib.sh) is a gateway run, with the bench key, the
gateway's CPU and memory sampled as in slice 2, and three more records, all untracked in the run's
directory:

- **`row-metrics.tsv`**: every 5 s, the row's own `/metrics`, read direct from the laptop, and the
  sums over its engines of `vllm:num_requests_running` and `vllm:num_requests_waiting`.
- **Each reply's status, as GuideLLM saw it.** GuideLLM 0.8.1 keeps every request in
  `result.json` (no sampling by default). A successful request passed `raise_for_status`, so it was
  2xx; an errored one keeps its error as `repr` of httpx's `HTTPStatusError`
  (`scheduler/worker.py`), which names the status (`Server error '503 Service Unavailable' for url
  ...`) and none of the reply's headers. A request still running when a level ends is counted
  incomplete, with no reply.
- **`gateway-requests.tsv`**: after the run, the gateway's access log lines of the alias's route
  inside the run's time (`docker logs --timestamps --since --until` on gb10-2), kept as time,
  status, path, and `retry_after`. The overlay `access-log` adds that field, each reply's
  `Retry-After` header, since GuideLLM keeps no header. The caller's address and every other field
  are left out.

`summarize` reads, per level: GuideLLM's replies by status; the gateway log's requests by status,
with how many carried a Retry-After and its values; the row's running and waiting counts (median,
max) from the samples inside the level; and then latency growth from the first level to the
second, TTFT, ITL, and request latency medians (embedding: latency only), in ms and as a ratio.

**What to expect.** vLLM admits up to its `max-num-seqs` sequences into a batch and queues the
rest (`num_requests_waiting`); it refuses none for load and sets no Retry-After. Past a row's cap,
a client should see only 200s, with the waiting count above 0 and latency, TTFT first, growing
with it. A non-2xx reply, or a Retry-After, in a cap run is a finding in itself.

### The probes

Each probe is configured, run, and removed with a deploy-time overlay, so the committed
[`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml) stays probe-free.

**The overlay mechanism.** [`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh)
takes the names of overlays, each `gateway/agentgateway/probes/<name>.yaml`, and applies them, in
the order given, to the copy it sends gb10-2, never to `config.yaml`. A deploy without one sends
`config.yaml` alone, which is how an overlay is removed; either way a re-run renders the same copy.
An overlay holds sections opened by a directive comment: `#@ append` adds its lines at the end, as
top-level sections, and refuses a top-level key the copy already has; `#@ after <line>` inserts its
lines after the one line equal to `<line>`, and refuses none or several. Plain bash on the lines,
with no YAML tool: the laptop's `yq` is the Python wrapper of jq, and the spike runs no Python. The
copy's first line names its overlays (`# overlays: none` without), so `ssh gb10-2 head -1
~/agentgateway/config.yaml` reads what is live; the deploy's `--validate-only` run checks each
copy before it is moved into place, and agentgateway reloads it with no restart.

| Overlay | What it sets | Source |
| --- | --- | --- |
| [`access-log`](../../gateway/agentgateway/probes/access-log.yaml) | an access log field, `retry_after`, each reply's `Retry-After` | `frontendPolicies.accessLog.add`; docs `observability/access-logs/view.md` |
| [`rate-limit-agent`](../../gateway/agentgateway/probes/rate-limit-agent.yaml) | a request-rate limit on the agent route: 2 requests, 2 more every 10 s, one bucket for every caller | a top-level `policies` entry, `target.route` agent, `localRateLimit`; `http/localratelimit.rs` |
| [`in-flight-1`](../../gateway/agentgateway/probes/in-flight-1.yaml) | the global in-flight limit at 1 | `frontendPolicies.http.maxConcurrentRequests`; `proxy/gateway.rs` |
| [`key-header`](../../gateway/agentgateway/probes/key-header.yaml) | the consumer gateway reads its keys from `x-api-key` | `apiKey.location.header.name`, inserted after `    apiKey:` |

`access-log` and `in-flight-1` both set `frontendPolicies`, so they don't combine; the deploy
refuses the pair.

**What the source says each answers.** From v1.7.0 (`crates/agentgateway/src/`):

- **The rate limit**: 429, `ProxyError::RateLimitExceeded`, with `x-ratelimit-limit`,
  `x-ratelimit-remaining`, `x-ratelimit-reset`, and `retry-after`, the seconds to the bucket's next
  refill and at least 1 (`proxy/mod.rs`, the error's response; `http/localratelimit.rs`,
  `status`). An admitted reply also carries the `x-ratelimit-*` headers. It is a route policy,
  applied after the key and the route and before any backend (below).
- **The in-flight limit**: 503 "request limit exceeded" with no Retry-After
  (`ProxyError::RequestLimitExceeded`, `proxy/mod.rs`). It is counted per bind, each gateway's
  port, and checked as a request arrives on a connection, before the key, the route, or any
  backend (`proxy/gateway.rs`, `request_admission`), so even a keyless request gets 503 while the
  limit is full, and the refusal leaves no access log line, only the `requests_shed` metric. A
  connection reads the frontend policies when it opens, so the probe's curls, each a new
  connection, see the reload.

**Read against go-ai's retry set** (408, 429, 502, 503, 504; Retry-After in seconds or an HTTP
date): both refusals are in it. The 429's `retry-after` is whole seconds, which go-ai reads; its
wait replaces go-ai's backoff, and one longer than the client's max delay ends the retries
(infer's README, "Retries"). The 503 has no Retry-After, so go-ai backs off on its own schedule.

**Whether a gateway refusal triggers failover.** None can. In `proxy/httpproxy.rs`, `proxy()`
runs the gateway policies (the key), selects the route, applies the route's request policies
(apiKey, budget, authorization, request-rate limits), and only then reads the backend's policies
and calls `make_backend_call`, which resolves a virtual model, selects a provider or endpoint, and
sets the access log's `endpoint` (`l.endpoint = Some(backend_call.target...)`). A 401 or a
request-rate 429 returns before that: no endpoint is chosen, no health or eviction is recorded,
and no backend is tried, so there is nothing to fail over from. The in-flight 503 is earlier
still. The one exception is a `type: tokens` rate limit, charged after the provider is chosen; this
config has none. The probe confirms it: the 429's log line has no `endpoint=` field, where every
forwarded request's has one.

**Infer's retry run.** The released infer, `tools/infer/v0.1.0`, with `--retries 3
--retry-base-delay 500ms --retry-max-delay 15s`, against the agent route with `rate-limit-agent`
deployed and its bucket emptied first: its first request gets 429 with a Retry-After of at most
10 s, which is under the 15 s max delay, so infer waits it out and the retry succeeds. The gateway
log shows the 429, its `retry_after`, and the 200 that follows.

### go-ai's tier, infer's tier, and the infer CLI

**The release.** go-ai's per-role credentials, `AI_<ROLE>_TOKEN` and `AI_<ROLE>_HEADER`, arrived in
both tiers with `tools/infer/v0.1.0` (`84b41dd`), not at `v0.1.0`, whose tier has no credentials.
Between the two tags the base module's code is unchanged: only `integration/` (the new
`credentials_test.go`, `doc.go`, `endpoint_test.go`), the README, `go.work`, `mise.toml`, and lint
config differ. So both tiers run from a detached worktree of go-ai at `tools/infer/v0.1.0`, under
`.state/agentgateway/go-ai`, with `GOWORK=off` as go-ai's `mise run integration` sets it: go-ai's
tier tests v0.1.0's code, and infer's builds `cmd/infer` against the released `go-ai v0.1.0` its
`go.mod` requires. go-ai's own working tree is not touched; the worktree is removed with `git -C
~/architecture/go-ai worktree remove`. The CLI is the released module, `go install
github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.1.0`, into `.state/agentgateway/bin`.

**The invocation.** Each tier is `go test -race -tags integration -count=1 -v ./integration/...`,
as go-ai's `mise run integration` runs it, from the worktree's root (go-ai's) or `tools/infer`
(infer's). Each role's `AI_<ROLE>_BASE_URL` is `http://gb10-2:3000/<alias>/v1`, its
`AI_<ROLE>_TOKEN` the `go-ai` key, sent as Bearer; `AI_TRANSCRIPTION_BASE_URL` is unset, so
transcription's route-mode scenarios skip. infer's tier maps each role's variables onto
`INFER_BASE_URL`, `INFER_TOKEN`, and `INFER_HEADER` in the built program's environment, never its
argv.

**The helpers.** [`scripts/clients-lib.sh`](../../scripts/clients-lib.sh), sourced: `goai_checkout`,
`infer_install`, `goai_tier <name> <alias>...`, `infer_tier <name> <alias>...`, `infer_at <alias>
<args>`, and `gw_curl <key> <curl args>`. Each reads its key from `.state/agentgateway/keys/<name>`
with `$(<file)` inside a subshell into the environment of the one process that sends it: the
tiers' `AI_<ROLE>_TOKEN` (or `_HEADER`), infer's `INFER_TOKEN` (or `INFER_HEADER`), or curl's
config on its stdin (`printf 'header = "Authorization: Bearer %s"\n' "$(<key)" | curl -K -`,
printf being a builtin). No key is in any argv, printed, or logged; the command log shows the
expression. The tiers clear every role's variables first, so only the named roles run, and after
each run the helper searches its log for the key. With `CLIENTS_KEY_IN=header` the same helpers
send `x-api-key: <key>` instead, through `AI_<ROLE>_HEADER`, `INFER_HEADER`, or the curl header.

**The header case**, once: `key-header` deployed, go-ai's tier on the embedding role alone with
`AI_EMBEDDING_HEADER='x-api-key: <key>'` from the key file, and `AI_EMBEDDING_TOKEN` unset; a
Bearer request gets 401 meanwhile. A deploy without the overlay restores Bearer.

**The CLI** (behavior 11): `infer_at <alias> models`, then `chat` on agent, vision, and audio, and
`embed` on embedding, with `INFER_TOKEN` from the go-ai key and no `INFER_MODEL`: each command
lists the alias's models first and sends to the one listed.

**If the key isn't carried** (behavior 12): should either tier or the CLI fail to send the key
when slice 3 runs, a 401 in the gateway's log where a 200 was due, behaviors 10 and 11 move to
`priority`; the finding and the goal record say so, and slice 3 completes without them.

### The steps

The session runs these one at a time, in the architect's view, on the laptop from the repository
root. Times are estimates.

1. **Pre-checks** (under 1 min), read-only: each row lists its alias, direct; the gateway's idle
   CPU and memory; the live overlays.

   ```sh
   for row in agent:gb10-1:8000 vision:gb10-2:8000 audio:framework:8001 embedding:framework:8002; do
     printf '%s: ' "${row%%:*}"; curl -sS --max-time 5 "http://${row#*:}/v1/models" | jq -c '[.data[].id]'
   done
   ssh gb10-2 docker stats --no-stream agentgateway
   ssh gb10-2 head -1 '~/agentgateway/config.yaml'
   ```

2. **The cap cells** (about 12 min: 8.7 of load, the rest start-up). The `access-log` overlay
   first, so the gateway's log carries each reply's Retry-After; then the four runs.

   ```sh
   scripts/agentgateway-deploy.sh access-log
   source scripts/measure-lib.sh
   cell c-agent cap-agent cap agent
   cell c-vision cap-vision cap vision
   cell c-audio cap-audio cap audio
   cell c-embed cap-embed cap embedding
   ```

3. **The clients' preparation** (about 1 min, the module downloads included):

   ```sh
   source scripts/clients-lib.sh
   goai_checkout
   infer_install
   ```

4. **The 429 probe and infer's retry run** (about 2 min). Deploy the rate limit beside the log
   field; send four requests in a row and read their headers; read the 429's log line; then empty
   the bucket and run infer with retries.

   ```sh
   scripts/agentgateway-deploy.sh access-log rate-limit-agent
   for i in 1 2 3 4; do gw_curl architect -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models | grep -iE '^(HTTP|retry-after|x-ratelimit)'; done
   ssh gb10-2 'docker logs --since 2m agentgateway 2>&1' | grep 'route=default/agent' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/' | tail -4
   gw_curl architect -sS -o /dev/null -w '%{http_code}\n' http://gb10-2:3000/agent/v1/models; gw_curl architect -sS -o /dev/null -w '%{http_code}\n' http://gb10-2:3000/agent/v1/models
   time infer_at agent --retries 3 --retry-base-delay 500ms --retry-max-delay 15s chat "Name a primary color."
   ssh gb10-2 'docker logs --since 1m agentgateway 2>&1' | grep 'route=default/agent' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/' | tail -4
   ```

   Expected: two 200s with `x-ratelimit-*`, then 429s with `retry-after` and `x-ratelimit-*`; the
   429's log line with `http.status=429`, its `retry_after`, and no `endpoint=`; infer waiting out
   the Retry-After, then answering, exit 0.

5. **The 503 probe** (about 1 min). Deploy the in-flight limit alone (it replaces the two
   overlays above); hold one request open with a long streamed chat; send a second with a key and
   a third without; then count the log's 503 lines, which should be 0.

   ```sh
   scripts/agentgateway-deploy.sh in-flight-1
   gw_curl architect -sS -N -o .state/agentgateway/inflight-stream.txt -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Write a 400-word story about a lighthouse."}],"max_tokens":1500}' http://gb10-2:3000/agent/v1/chat/completions &
   sleep 3
   gw_curl architect -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models | grep -iE '^(HTTP|retry-after)'
   curl -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models | grep -iE '^(HTTP|retry-after)'
   wait
   ssh gb10-2 'docker logs --since 2m agentgateway 2>&1' | grep -c 'http.status=503'
   ```

   Expected: both answer `HTTP/1.1 503` with no `retry-after`; the stream ends normally.

6. **Probes removed** (under 1 min): deploy with no overlay, and confirm.

   ```sh
   scripts/agentgateway-deploy.sh
   ssh gb10-2 head -1 '~/agentgateway/config.yaml'
   gw_curl architect -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models | grep -iE '^(HTTP|x-ratelimit)'
   ```

   Expected: `# overlays: none`; a 200 with no `x-ratelimit-*` header.

7. **go-ai's tier and infer's tier** (about 10 min, the agent's reasoning scenarios most of it):

   ```sh
   goai_tier goai-tier agent vision audio embedding
   infer_tier infer-tier agent vision audio embedding
   ```

   Expected: every scenario passes; transcription's route mode skips, naming
   `AI_TRANSCRIPTION_BASE_URL`; the key in neither log.

8. **The header case** (about 1 min):

   ```sh
   scripts/agentgateway-deploy.sh key-header
   gw_curl architect -sS -o /dev/null -w '%{http_code} bearer\n' http://gb10-2:3000/embedding/v1/models
   CLIENTS_KEY_IN=header goai_tier goai-tier-header embedding
   scripts/agentgateway-deploy.sh
   gw_curl architect -sS -o /dev/null -w '%{http_code} bearer restored\n' http://gb10-2:3000/embedding/v1/models
   ```

   Expected: 401 for Bearer under the overlay; the embedding scenarios pass through the header;
   200 once Bearer is restored.

9. **The infer CLI** (about 2 min):

   ```sh
   for a in agent vision audio embedding; do infer_at "$a" models; done
   infer_at agent chat "Name a planet."
   infer_at vision chat "Say hello in three words."
   infer_at audio chat "Say hello in three words."
   infer_at embedding embed "first passage" "second passage" | jq -c length
   ```

   Expected: each `models` prints its alias alone; each chat a reply and its usage; two vectors of
   768.

10. **Clean-up**: `git -C ~/architecture/go-ai worktree remove .state/agentgateway/go-ai` from the
    repository root, once the results are read.

### Where the results land

Untracked, under `.state/agentgateway/`: each cap run's `cells/<run>/` (`result.json`,
`guidellm.log`, `exit`, `gateway-stats.tsv`, `row-metrics.tsv`, `gateway-requests.tsv`); each
tier's `clients/<run>.log`; `inflight-stream.txt`; and `commands-<date>.log`, every helper call and
command, which "Commands as run" quotes.

### Settle live

- **The rate limit's target.** The top-level policy names the route `agent` in namespace
  `default`, as the access log names it (`route=default/agent`). The schema requires the
  namespace and `--validate-only` doesn't check that a target exists, so the first 429 confirms it
  attached; four 200s mean it did not.
- **The `retry_after` field.** The docs read request headers in access log fields; that
  `response.headers["retry-after"]` reads a gateway-made 429's header, and what it logs when there
  is none, is seen in step 4 and in the cap runs' `gateway-requests.tsv`.
- **The gateway's log under C-embed** may run to tens of thousands of lines; `docker logs --since
  --until` reads only the run's window.
- **How the gateway logs requests GuideLLM cancels** at a level's end: the gateway log may count
  them under some status (a client close) where GuideLLM counts them incomplete.
- **`go install ...@v0.1.0`** reads the module proxy. Should it fail, infer is built from the
  worktree instead (`cd .state/agentgateway/go-ai/tools/infer && GOWORK=off go build -o
  ../../../bin/infer ./cmd/infer`), the same code, whose `infer version` reports a development
  build.

### Results

Run on 2026-11-13: the pre-checks at 14:43:31, the access-log overlay deployed at 14:43:38, the cap
cells from 14:43:46 to 14:54:45, the clients prepared at 14:55:29, the probes from 14:55:43 to
14:57:11, the tiers and the header case from 14:57:16 to 14:58:53, the infer CLI at 14:59:05, and
the clean-up at 14:59:14. Every command, as run, is under "Commands as run". The figures are
`summarize`'s, read again from each run's files after the session; the probes' replies and log
lines are as the session read them.

**The pre-checks.** Each row listed exactly its alias, direct from the laptop: `["agent"]`,
`["vision"]`, `["audio"]`, `["embedding"]`. The gateway container, idle, used 0.08% CPU and
19.43 MiB of memory. The live config's first line was its schema comment, not an overlay line: it
was deployed in slice 1, before the overlay mechanism existed. The `access-log` overlay was then
deployed (`overlay access-log: applied`, "Configuration is valid!", reloaded in place).

**Behavior 8: the cap cells.** All four runs exited 0, and the bench key was in none of their files.
Every reply was 200: GuideLLM errored no request, the gateway logged no 429 or 503, and no reply
carried a Retry-After. Nothing is refused at any cap: past the cap, requests wait inside vLLM, and
the client sees only a longer wait. Per level, GuideLLM's requests, the gateway log's, and the
row's counts from its `/metrics` samples (5 s apart, inside the level); latencies are medians in
ms, with the p95 of request latency:

| Cell | Level | GuideLLM ok / errored / incomplete | Gateway log | Running median (max) | Waiting median (max) | TTFT | ITL | Latency median / p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| agent | 12 | 16 / 0 / 12 | 200 ×28 | 12 (12) | 0 (9) | 9,821.64 | 91.97 | 65,477.57 / 70,028.32 |
| agent | 16 | 12 / 0 / 16 | 200 ×28 | 12 (12) | 4 (14) | 15,765.00 | 108.28 | 72,518.57 / 75,447.90 |
| vision | 16 | 96 / 0 / 16 | 200 ×112 | 14 (16) | 0 (0) | 2,466.96 | 64.08 | 9,272.73 / 9,374.53 |
| vision | 20 | 96 / 0 / 20 | 200 ×116 | 15.5 (16) | 4 (4) | 3,249.00 | 72.27 | 10,395.23 / 16,418.35 |
| audio | 4 | 64 / 0 / 0 | 200 ×64 | 3.5 (4) | 0 (0) | 153.42 | 45.66 | 856.63 / 1,922.13 |
| audio | 8 | 64 / 0 / 0 | 200 ×64 | 3.5 (4) | 4 (4) | 962.75 | 45.80 | 1,808.29 / 3,268.97 |
| embedding | 128 | 11,279 / 0 / 128 | 200 ×11,279; blank ×128 | 0 (0) | 0 (0) | — | — | 670.77 / 679.11 |
| embedding | 160 | 5,434 / 0 / 0 | 200 ×5,434; blank ×2 | 0 (0) | 0 (0) | — | — | 21.65 / 752.86 |

- **Agent** runs at its cap of 12 at the first level, with up to 9 waiting. At 16, 12 run and the
  rest wait (median 4, up to 14): TTFT grows ×1.61, ITL ×1.18, to 108 ms, past the agent's 100 ms
  floor, and request latency ×1.11. Each level completes few requests in 110 s, so the medians are
  the reading.
- **Vision** at 16 runs at most 16 with none waiting; its median latency, 9.27 s, is inside
  vision's 10 s floor. At 20, 16 run and 4 wait: TTFT grows ×1.32, ITL ×1.13, and latency ×1.12,
  to a median of 10.4 s and a p95 of 16.4 s.
- **Audio** at 4 runs at most 4 with none waiting. At 8, 4 wait: TTFT grows ×6.28, to 963 ms, ITL
  stays flat (45.8 ms), and latency grows ×2.11, to 1.81 s. The wait lands before the first token.
- **Embedding** completed about 188 requests a second at 128 in flight, at 671 ms median and
  679 ms p95. At 160 it completed 5,434, about 91 a second, at 21.65 ms median and 753 ms p95:
  throughput halved and latency split in two, the opposite of a row past its cap. The session's
  interpretation, not proven by these runs: the 160 level is bound by the client, GuideLLM on the
  laptop not keeping 160 requests in flight, so it is no reading of the row. No other benchmark
  was run to settle it.
- **The embedding row's gauges.** `vllm:num_requests_running` and `vllm:num_requests_waiting` read
  0 in every 5 s sample of both levels, although the row exposes both metrics, while 128 requests
  were in flight. The likely reading, unproven: vLLM's pooling runner doesn't update those gauges
  as the generate runner does. An admission rule on those gauges would see an idle embedding row.
- **Cancelled requests in the gateway's log.** The requests GuideLLM cancels at a level's end, which
  it counts incomplete, the gateway logged with a blank status on the embedding route (128 and
  2). On agent and vision, whose replies stream, the gateway logged all of a level's requests as
  200, the incomplete ones among them, their reply having begun.

The gateway's CPU and memory, from the samples inside each run's benchmark:

| Cap run | Samples | CPU % median / max | Memory MiB median / max |
| --- | --- | --- | --- |
| `c-agent` | 38 | 0.70 / 1.29 | 22.3 / 25.1 |
| `c-vision` | 21 | 1.71 / 4.46 | 27.5 / 31.0 |
| `c-audio` | 6 | 1.31 / 1.54 | 35.4 / 42.1 |
| `c-embed` | 22 | 5.45 / 7.97 | 63.2 / 76.9 |

No sample failed. At its busiest, about 188 embedding requests a second, the gateway used under 8%
of one core and under 77 MiB.

**The clients' preparation.** `goai_checkout` added a detached worktree of go-ai at
`tools/infer/v0.1.0` (`84b41dd`) under `.state/agentgateway/go-ai`; go-ai's own working tree was
not touched. `infer_install` installed infer v0.1.0 with `go install` into
`.state/agentgateway/bin`, from the module proxy, so the fallback build was not needed.

**Behavior 9: the probes.**

- **429.** The `access-log` and `rate-limit-agent` overlays (2 requests, refilled every 10 s, on
  route `default/agent`); the four requests in a row:
  - Requests 1 and 2 got 200, with `x-ratelimit-limit` 2, `x-ratelimit-remaining` 1 and then 0, and
    `x-ratelimit-reset` 8.
  - Requests 3 and 4 got `429 Too Many Requests`, with `retry-after` 8 and the `x-ratelimit-*`
    headers. The policy attached to the route named `default/agent`.
  - The 429's log line carries `reason=RateLimit duration=0ms retry_after="8"` and no `endpoint=`:
    no backend was selected, so a gateway refusal triggers no failover. The `retry_after` field
    reads the header of a reply the gateway made itself.
- **infer's retry run.** Against the drained bucket, infer with `--retries 3 --retry-base-delay
  500ms --retry-max-delay 15s`: its `/models` request got 429 with `retry_after="1"` twice, and it
  waited about 1 s each time; then 200 on `/models` and 200 on the chat, which answered "Red.",
  completed. 3.1 s in all, exit 0. go-ai's retry honours the gateway's Retry-After.
- **503.** The `in-flight-1` overlay alone. With the stream holding the one slot, a request with a
  key and one without both got `503 Service Unavailable`, with no Retry-After: the limit is checked
  before the key.
  - infer with `--retries 2` stopped with `infer models: ai: models: 503 Service Unavailable:
    request limit exceeded`. go-ai retries a 503 with its own backoff, since there is no
    Retry-After to wait, and each attempt met the held slot.
  - The stream ran on to 1,499 `data:` events and ended with `"finish_reason":"length"`.
  - **Observability gap: a shed request is invisible in the log.** The access log had 0 lines for
    the 503s. Only the `requests_shed` metric, per the source, counts them.
- **Overlays removed** at 14:57:08: the live config's first line read `# overlays: none`, and a
  request got 200 with no `x-ratelimit-*` header.

**Behavior 10: go-ai's tier and infer's tier.**

- **go-ai's tier**, through the gateway on agent, vision, audio, and embedding, each role's key in
  `AI_<ROLE>_TOKEN`: 20 passed, 0 failed, 1 skipped (`TestTranscribeRoute`,
  `AI_TRANSCRIPTION_BASE_URL` unset), in 51.9 s. It covered the function-call round trip,
  streamed and not, in Chat Completions, Messages, and Responses; tool choice (a named function in
  all three, allowed tools required, and `none`); reasoning round trips; structured output; the
  image description; and `TestTranscribeChat`, the audio chat. The key was not in the log.
- **infer's tier**: 13 passed, 0 failed, 1 skipped (`TestTranscribeRoute`; `TestModels`'
  `AI_TRANSCRIPTION_BASE_URL` subtest skipped too), in 23.1 s, `TestCredentials` and
  `TestEndpoint_MapsCredentials` among the passes. The key was not in the log.
- **The header case.** The `key-header` overlay (the key read from `x-api-key`):
  - A Bearer request got 401: the gateway reads the key from one location only.
  - `CLIENTS_KEY_IN=header goai_tier goai-tier-header embedding` reported 18 passed, 0 failed, 3
    skipped. Most of those 18 pass in 0.00 s: their roles are unset, so each skips inside its
    subtests while the top-level test reports PASS, and four, the credentials tests, need no role's
    endpoint. `TestEmbed` ran (0.03 s), and the gateway logged 5
    `/embedding/v1/embeddings` and 7 `/embedding/v1/models` requests, all 200: the key went in
    `x-api-key` through `AI_EMBEDDING_HEADER`.
  - Bearer restored: `# overlays: none`, and a Bearer request got 200.

**Behavior 11: the infer CLI**, with `INFER_TOKEN` and no `INFER_MODEL`:

- `models` on each alias listed only that alias.
- `chat` on agent answered "Mars.", completed, 112 tokens, 29 of them reasoning; on vision, "Hello
  to you!"; on audio, "Hello there now.".
- `embed` on embedding returned two vectors of 768. The session's `jq` summary of the output hit a
  parse error on one line of infer's output, explained by the recapture below.

Recaptured at 15:19:10–15:19:12, after the slices, at review, with output and errors together
(`2>&1`) in `.state/agentgateway/clients/infer-cli-1519.txt`, which holds no key:

- `models` on each alias listed only that alias.
- `chat` on agent answered "Mars.", completed, 122 tokens, 39 of them reasoning.
- `embed` printed two JSON arrays of 768, one per line, then a plain line, `usage: 8 input tokens,
  8 total tokens`. That line isn't JSON: it is the line `jq` failed to parse.

**Note for v1.ai.client:** whether infer writes the `usage:` line to stdout or stderr is unverified,
since the capture took both. If it is stdout, a JSON consumer piping `infer embed` breaks on it. This
is a note, not a verified fix.

**Behavior 12** did not trigger: both tiers and the CLI carried the key, in Bearer and in the
header, so behaviors 10 and 11 stay in this task.

**Behavior 13: the paper inventory**, below, with its probe cells filled from these results and
its marks unchanged. What the probes add:

- A gateway refusal, the rate limit's 429 or the in-flight limit's 503, is answered before backend
  selection, with no endpoint, so it triggers no failover.
- The in-flight limit's 503 is logged nowhere.
- vLLM queues past every cap and never refuses (the cap cells), so a full row triggers no
  eviction.

**The clean-up.** The go-ai worktree was removed at 14:59:14, with the worktree's absolute path
(under "Commands as run").

**go-ai fixes for v1.ai.client** (item 7 of its readiness questions): none found. Both tiers and
the CLI ran unchanged through the gateway, Bearer and header alike, and go-ai's retry handled the
gateway's 429 as its Retry-After asks.

### On demand: the refusals for v1.ai.client's acceptance

v1.ai.client's acceptance can see a gateway refusal live with the same overlays, from the laptop
at the repository root; each step reloads the gateway in place, with no restart.

1. **Apply** one overlay: `scripts/agentgateway-deploy.sh access-log rate-limit-agent` for the
   429, or `scripts/agentgateway-deploy.sh in-flight-1` for the 503 (the two don't combine, since
   `access-log` and `in-flight-1` both set `frontendPolicies`). `ssh gb10-2 head -1
   '~/agentgateway/config.yaml'` names what is live.
2. **Trip** it. The 429: send three requests to `/agent/v1/models` within 10 s (step 4's `gw_curl`
   loop); the third gets 429 with `retry-after`, and a client run against the drained bucket sees
   it. The 503: hold the one slot with a long streamed chat (step 5's), then send the client's
   request, with or without a key.
3. **Remove** it: `scripts/agentgateway-deploy.sh` with no overlay; the first line reads
   `# overlays: none`, and a request gets 200 with no `x-ratelimit-*` header (step 6).

### The paper inventory

What agentgateway v1.7.0 provides for (a) capacity overflow to Azure AI Foundry and (b) admission
on vLLM's live metrics, from its docs and source, with the probe cells filled from slice 3's runs.
Docs paths are under `website/content/docs/standalone/latest/` unless named otherwise, source
paths under `crates/agentgateway/src/`, both at the `v1.7.0` tag. "Std" is standalone, this
spike's mode.

**Three established facts it starts from.**

- **The `llm` section is one prefix.** Virtual models (failover, weighted, conditional, callout)
  exist only in the `llm` section (`types/local.rs`, `LocalLLMConfig.virtual_models`), and its
  `pathPrefix` is a single string, one internal route `llm:request` ("You can set only one
  prefix", `documentation/llm/about.md`). The per-alias base URLs, `/<alias>/v1`, are the routing
  form, which has no virtual models; the UI labels its inline `ai` backends "legacy LLM backend"
  (`ui/src/traffic.ts`), though v1.7.0's code, schema, and docs deprecate nothing. Using virtual
  models means one shared prefix routed by model name, which `priority` weighs against per-alias
  base URLs.
- **Dot segments aren't normalized.** Routing matches the raw path (`http/route.rs`,
  `matches_request`; `proxy/httpproxy.rs`, `normalize_uri` sets only scheme and authority), as
  slice 1 saw. Hardening is native: a regex path match (`matches: - path: {regex: ...}`, a full
  anchored match; `documentation/configuration/traffic-management/matching.md`) or a CEL
  `authorization` rule with `deny` (`documentation/configuration/security/http-authz.md`)
  refusing `..` and its encodings before routing.
- **A full row never refuses.** vLLM queues past `max-num-seqs` (`num_requests_waiting`) rather
  than answering 429 or 503, so nothing agentgateway classifies as unhealthy ever comes back from
  a busy row; eviction and failover never see load, only failures. The cap cells confirm it: only
  200s past every cap.

**The mechanisms.**

| Mechanism | What it does | Where (Std) | Source and docs |
| --- | --- | --- | --- |
| Priority groups | Providers grouped; traffic goes to the first group with an endpoint not evicted, so it spills over only when the whole group is evicted, not when it is slow or busy; within a group, P2C on a health and latency score | routing form `ai.groups[].providers[]`; `llm` section, a failover virtual model's `targets[].priority` | `types/loadbalancer.rs`, `EndpointSet::best_bucket`; `llm/mod.rs`, `select_provider`; `documentation/llm/virtual-models.md` |
| Eviction on 5xx | An unhealthy reply evicts the endpoint: by default a 5xx or a connection failure; `consecutiveFailures` or `healthThreshold` set the bar, else one reply evicts; repeats multiply the duration, unbounded. Default eviction (3 s) only when a backend has more than one group | `health: {unhealthyExpression, eviction: {duration, consecutiveFailures, healthThreshold, restoreHealth}}` on backends, providers, `llm.models[]` | `http/health.rs`; `telemetry/log.rs`, `default_unhealthy_for_status`; `llm/mod.rs`, `AIBackend::new` |
| `unhealthyExpression` on 429 | A CEL expression that replaces the default classification, e.g. `response.code == 429 \|\| response.code >= 500` | as above | `http/health.rs`; tests in `proxy/httpproxy.rs` |
| Retry-After eviction | A 429's `Retry-After` (seconds or date, then `retry-after-ms`, `x-ratelimit-reset*`) sets the eviction's length when `eviction.duration` is unset; an explicit `duration` wins. The Kubernetes failover page says the reverse; the code and the standalone page agree | as above | `http/outlierdetection.rs`, `retry_after`; `http/health.rs`, `eviction_decision`; `documentation/llm/virtual-models.md`; `docs/kubernetes/latest/documentation/llm/failover.md` |
| Route retries | `retry: {attempts, backoff, codes, condition}`; each attempt selects the provider or endpoint again (same route backend), so a retry can move to another group once the first is evicted. Sleeps a fixed `backoff`, never a Retry-After; bodies over 64 KiB aren't retried, which leaves out vision images and audio clips | routing form `routes[].policies.retry`; not in the `llm` section's policies | `http/retry/mod.rs`; `proxy/httpproxy.rs` (`MAX_BUFFERED_BYTES`); `documentation/configuration/resiliency/retries.md` |
| Virtual models | `failover` (priorities), `weighted`, `conditional` (CEL `when`), and `callout` (an HTTP service picks the model, with `failureMode` failClosed or a fallback model, and a cache) | `llm` section only | `types/local.rs`, `LocalLLMVirtualModelRouting`; `llm/router_callout.rs`; `documentation/llm/virtual-models.md` |
| Endpoint picker | Gateway API Inference Extension: an external picker (EPP, ext_proc) chooses the endpoint, reading the model servers' metrics itself; agentgateway forwards to the endpoint it returns. Fail-closed only | routing form, on a `service` backend only (`policies.inferenceRouting.endpointPicker`); Std as a sidecar, or Kubernetes `InferencePool` | `http/ext_proc.rs`, `InferenceRouting`; `types/local.rs`, `validate_inference_routing_scope`; `documentation/llm/inference/_index.md`; `examples/llm-standalone-epp/` |
| In-flight limit | Per bind; 503, no Retry-After, before auth and routing | `frontendPolicies.http.maxConcurrentRequests` | `proxy/gateway.rs`; `proxy/admission.rs`; schema only, no standalone page |
| Rate limits | Local token buckets (`requests` or `tokens`, per CEL `key`, e.g. per consumer key), or Envoy's rate limit service; 429 with Retry-After and `x-ratelimit-*` | `localRateLimit`, `remoteRateLimit` on routes, `llm.policies`, top-level `policies` | `http/localratelimit.rs`, `http/remoteratelimit.rs`; `documentation/configuration/resiliency/rate-limits.md` |
| Budgets | Per key, USD or tokens over an epoch-aligned window; `Block` answers 429 with Retry-After at the window's reset. Needs `config.database.url` | `apiKey.keys[].budgets[]` | `http/budget/mod.rs`; `documentation/llm/cost-controls/budget-limits/per-key.md` |

**The probes, read into it** (slice 3's runs, under "Results" above):

| Probe | Expected from source | Seen |
| --- | --- | --- |
| Rate limit on agent | 429, `retry-after` ≤ 10, `x-ratelimit-*`; no `endpoint=` in the log | As expected: `429 Too Many Requests` with `retry-after` 8 and `x-ratelimit-*`; the log line `reason=RateLimit duration=0ms retry_after="8"` with no `endpoint=`. The refusal is answered before backend selection, so it triggers no failover |
| In-flight limit 1 | 503, no Retry-After, also without a key; no log line | As expected: `503 Service Unavailable` with no Retry-After, with a key and without; 0 access log lines. A shed request is logged nowhere |
| infer with retries | waits the Retry-After, then 200, exit 0 | As expected: two 429s with `retry_after="1"`, about 1 s waited after each, then 200; 3.1 s, exit 0 |
| Cap cells | only 2xx; `num_requests_waiting` above 0 past each cap; no Retry-After | Only 200s and no Retry-After in all four cells; waiting above 0 past the cap on agent, vision, and audio (the embedding row's gauges read 0 throughout). vLLM queues past every cap and never refuses, so a full row triggers no eviction |

**The requirements.** Per requirement, the brief's mark, `gap` or `none` (`none` when a native
mechanism covers it, named in the notes), and what could fill it, native or existing tools first
and an authored extension or callout last, with any partial cover noted there.

| Requirement | agentgateway v1.7.0 | Mark | What could fill it, and notes |
| --- | --- | --- | --- |
| Admission on `/metrics` per purpose floor: refuse or redirect a request when the row's live load (running, waiting, KV cache) passes a floor set per purpose | Nothing reads a backend's `/metrics`. The endpoint picker does, outside agentgateway, and it chooses among replicas of one model; its standard pickers score by queue and KV cache, not per-purpose floors. The in-flight limit is one count per port, not per purpose or row; a per-route rate limit counts requests a second, not concurrency | gap | 1. A per-row in-flight count set to each row's cap, if one could be scoped per route: v1.7.0 has none, so it is a gap even before metrics. 2. An existing EPP (the Inference Extension's) with its saturation thresholds, as a sidecar in standalone mode, on a `service` backend per row: native wiring, existing tool, but replica selection, not purpose admission. 3. An `extAuthz` or `extProc` service that reads `/metrics` and refuses past the floor (authored, last resort). |
| Queueing past caps: hold requests at the gateway when a row is full, rather than pass them on or refuse | Nothing queues: the in-flight limit refuses at once (503), and vLLM queues behind it. The row's own queue is the only one | gap | vLLM's queue is the native one (`num_requests_waiting`), bounded only by its timeouts; a gateway-side queue would be authored. The cap cells measure how vLLM's queue grows. |
| Capacity overflow to Foundry on GPU pressure or max sessions | Failover moves traffic only when a group is evicted, and eviction sees only unhealthy replies. A full vLLM row answers 200 slowly, so pressure never evicts it. With a gateway refusal in front (an in-flight or rate limit), the refusal is answered before backend selection, so it can't spill over either. A conditional virtual model routes on request attributes, not row load; a callout could route on load, but would need the load from elsewhere | gap | Partial with a callout (2. below). 1. Make the row refuse when full, so eviction can act: a vLLM-side limit that answers 429 or 503 with Retry-After past max sessions, then `unhealthyExpression` on 429 and Retry-After eviction move the next requests to a Foundry group (all native once the row refuses; whether vLLM can be made to refuse is for `priority`). 2. A virtual model's `callout` to a small service reading `/metrics` that names the local or Foundry model (native hook, authored service). 3. Route retries can't carry it: they don't wait out Retry-After and skip bodies over 64 KiB. All in the `llm` section, so all need one shared prefix. |
| Overflow on host down | A down row gives connection failures or 5xx, which evict by default; with the row and Foundry in priority groups, traffic moves to Foundry until the eviction ends, then returns; a route retry sends the failed request on. For the routing form, `ai.groups` provides this without the `llm` section | none | Native: priority groups with eviction (routing form `ai.groups`, or a failover virtual model), plus a route retry on 502, 503, 504 and connection failure for the request that met the failure. Probed live in `priority`. |
| Per-key token budgets on streamed traffic: count each key's tokens on streams as on other requests | Budgets and `tokens` rate limits count the usage read from the reply. On detect pass-through a stream carries usage only if the client sent `stream_options.include_usage`, so a stream without it counts no tokens (slice 4's streamed chat logged none). The `completions` route type sets it on every stream, but this config's `"*": detect` skips that | gap | Partial: a stream is counted only when its client sends `include_usage`. 1. Clients send `include_usage` (GuideLLM already does). 2. An `ai` policy `transformations` entry that sets `stream_options` on streamed requests under detect (native, unverified). 3. Map `/v1/chat/completions` to the `completions` route type, which injects it (native; vision and audio content through it unverified). Details under slice 4's "Results". |

**What `priority` inherits.** The live overflow cells (Foundry, capped) depend on the shared
prefix question: virtual models and callout are `llm`-section only; `ai.groups` priority groups
and route retries work in the routing form with per-alias base URLs. Host-down overflow needs only
the routing form; pressure overflow needs a refusal the gateway can see, which today neither vLLM
nor agentgateway gives on load.

## Slice 4 · walkthrough

The architect's walkthrough of the gateway as it stands after slice 3, run on the laptop from the
repository root, one step at a time. It changes nothing on the hosts except in step 8, which is
optional and leaves the configuration as it found it. Results are recorded under "Results" below,
filled after the walk.

1. **What agentgateway is.** An open-source proxy for AI traffic, here one container on gb10-2
   that serves each alias's base URL, `/<alias>/v1`, as a route to its row, admitting only
   requests with a listed consumer key and reading each reply's model and token usage. It is set
   up from one YAML file, deployed by `scripts/agentgateway-deploy.sh` and reloaded in place on
   change; what it provides is under [agentgateway](#agentgateway-1), and how it is configured
   under [The configuration](#the-configuration).

2. **The live config and the container.** Purpose: confirm no probe overlay is live and the
   container is up, with its consumer port on the tailnet and its UI port on loopback.

   ```sh
   ssh gb10-2 head -1 '~/agentgateway/config.yaml'
   ssh gb10-2 "docker ps --filter name=agentgateway --format '{{.Names}}  {{.Image}}  {{.Status}}'"
   ssh gb10-2 'docker port agentgateway | sed "s/$(tailscale ip -4)/<tailnet>/"'
   ```

   Expected: `# overlays: none`; one line, `agentgateway  cr.agentgateway.dev/agentgateway:v1.7.0
   Up ...`; `3000/tcp -> <tailnet>:3000` and `3001/tcp -> 127.0.0.1:3001`, and nothing for 15000.
   (`docker ps` is given a format without its ports column, which would show the tailnet address.)

3. **Each alias's models.** Purpose: each base URL reaches its own row, which lists its alias
   alone.

   ```sh
   for a in agent vision audio embedding; do
     printf '%s: ' "$a"; curl -sS -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" "http://gb10-2:3000/$a/v1/models" | jq -r '[.data[].id] | join(",")'
   done
   ```

   Expected: `agent: agent`, `vision: vision`, `audio: audio`, `embedding: embedding`.

4. **A chat on agent, without a key and with one.** Purpose: the key policy refuses a request
   with no key, and passes a keyed one through with its usage.

   ```sh
   curl -sS -o /dev/null -w '%{http_code}\n' -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256}' http://gb10-2:3000/agent/v1/chat/completions
   curl -sS -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256}' http://gb10-2:3000/agent/v1/chat/completions | jq '{model, content: .choices[0].message.content, usage}'
   ```

   Expected: `401`; then `model` `agent`, a short reply, and `usage` with its prompt, completion,
   and total tokens.

5. **The revoked key.** Purpose: a key whose entry was removed from the configuration is refused,
   though its file is still on the laptop. `revoke-test` was revoked in slice 1.

   ```sh
   curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat .state/agentgateway/keys/revoke-test)" http://gb10-2:3000/agent/v1/models
   ```

   Expected: `401`.

6. **An unrouted path.** Purpose: a valid key reaches only the alias routes; vLLM's `/metrics`
   isn't one.

   ```sh
   curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" http://gb10-2:3000/metrics
   ```

   Expected: `404`, the gateway's "route not found": an alias's routes start at `/<alias>/v1`.

7. **The gateway's read-outs.** Purpose: what the gateway costs at rest, and what it logged for
   the walk's requests.

   ```sh
   ssh gb10-2 docker stats --no-stream agentgateway
   ssh gb10-2 'docker logs --tail 6 agentgateway 2>&1' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/'
   ```

   Expected: one `docker stats` line with the container's CPU % near 0 and its memory use; then
   the log's last lines, the walk's latest requests, each with its `http.status`: the agent
   route's lines name `route=default/agent`, and the keyed chat's line its model and token usage.
   Each reads `src.addr=<laptop>`, and none carries a key.

8. **Optional: the 429 on demand.** Purpose: see a gateway refusal live, as v1.ai.client's
   acceptance would; the steps are under
   [On demand: the refusals for v1.ai.client's acceptance](#on-demand-the-refusals-for-v1aiclients-acceptance).
   Apply the rate limit on agent (2 requests, refilled every 10 s), trip it with three requests
   within 10 s, then deploy with no overlay to remove it.

   ```sh
   scripts/agentgateway-deploy.sh rate-limit-agent
   for i in 1 2 3; do curl -sS -o /dev/null -D - -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" http://gb10-2:3000/agent/v1/models | grep -iE '^(HTTP|retry-after)'; done
   scripts/agentgateway-deploy.sh
   ssh gb10-2 head -1 '~/agentgateway/config.yaml'
   ```

   Expected: the deploy prints `overlay rate-limit-agent: applied` and reloads in place; two
   `HTTP/1.1 200`, then `HTTP/1.1 429` with a `retry-after` of 10 or less; after the second
   deploy, `# overlays: none`.

### Results

Run on 2026-11-13 by the architect, from about 15:05 to 15:09 local (20:05–20:09Z), on the laptop
from the repository root. The outputs are as the architect pasted them, with the log's `src.addr`
redacted. Steps 2 to 7 went as expected; step 8 was not run.

- **Step 2: the live config and the container.** `# overlays: none`; one container,
  `agentgateway  cr.agentgateway.dev/agentgateway:v1.7.0  Up 2 hours`; `3000/tcp -> <tailnet>:3000`
  and `3001/tcp -> 127.0.0.1:3001`, and nothing for 15000.
- **Step 3: each alias's models.** `agent: agent`, `vision: vision`, `audio: audio`,
  `embedding: embedding`.
- **Step 4: a chat on agent.** Without a key, `401`. With the architect's key, `model` `agent`, the
  reply "Hello, wonderful friend! Welcome home.", and `usage` of 73 prompt, 200 completion, and 273
  total tokens, 182 of them reasoning.
- **The streaming question.** At step 4 the architect asked whether streams work through the
  gateway. The session pointed to the evidence so far: slice 1's streamed chat and revocation
  stream, and the streamed GuideLLM cells of slices 2 and 3. It then gave a streamed chat on agent
  (`curl -N`, `"stream": true`, `max_tokens` 300), which the architect ran: it streamed, and the
  gateway logged it at 20:07:28Z with status 200 in 1,352 ms, but with no `gen_ai.usage` fields
  (the command is quoted under "Commands as run"). See the finding below.
- **Step 5: the revoked key.** `401`; the log line reads "api key authentication failure: invalid
  credentials".
- **Step 6: an unrouted path.** `404`, route not found.
- **Step 7: the gateway's read-outs.** `docker stats`: 0.07% CPU, 57.63 MiB of memory, 353 MB in
  and 360 MB out over the network since start, 29 processes. The last 6 log lines were the walk's
  requests, each with `src.addr=<laptop>` and no key:

  | Time (Z) | Status | Request | Log line |
  | --- | --- | --- | --- |
  | 20:06:49 | 401 | chat, no key | no API Key found |
  | 20:07:00 | 200 | chat, keyed | `model=agent`, 73 in, 200 out, 182 reasoning, 5,590 ms |
  | 20:07:28 | 200 | streamed chat, `max_tokens` 300 | 1,352 ms, no usage fields |
  | 20:07:44 | 401 | revoke-test | invalid credentials |
  | 20:08:04 | 404 | `/metrics` | route not found |
  | 20:08:31 | 404 | `/metrics` | route not found |

- **Step 8: not run.** It was optional, and slice 3 already showed the 429 live (the rate-limit
  probe under slice 3's "Results").
- **Keys in argv.** The walk's commands, slice 1's and this one's, pass a key as
  `-H "Authorization: Bearer $(cat …)"`, which puts the key in curl's argv on the laptop while it
  runs; nothing reached the repository. Future walks should feed the header on stdin with
  `curl -K -`, as the client helpers do.

**Finding: a streamed request carries no token usage in the gateway's log unless the client sends
`stream_options: {"include_usage": true}`.** vLLM adds a usage chunk to a stream only when the
request asks for it, and detect pass-through forwards the body as sent and reads usage from the
reply, so a stream that didn't ask has no usage for it to read. The architect's streamed chat at
20:07:28Z sent no `stream_options` and logged no `gen_ai.usage` fields, while the non-streamed chat
at 20:07:00Z logged its tokens. The streamed GuideLLM cells of slices 2 and 3 never met this case:
GuideLLM 0.8.1 sends `stream_options` with `include_usage: true` on every streamed chat
(`guidellm/backends/openai/request_handlers.py`), and every chat, vision, and audio cell's
`result.json` records it on its requests.

The consequence for `priority`: per-key token budgets and `tokens` rate limits count from the usage
the gateway reads, so on streamed traffic they need `include_usage`, sent by every client or
injected by the gateway. agentgateway v1.7.0 can inject it natively, by two routes, both read from
the docs and source at `v1.7.0` and neither tried live:

- **The `completions` route type injects it always.** `process_completions_request`
  (`crates/agentgateway/src/llm/mod.rs`) sets `stream_options.include_usage` to true on every
  streamed Chat Completions request, overriding a client's `false`, "because the token counts come
  from the usage data" (`documentation/llm/api-types/completions.md`, "Usage in streamed replies";
  the v1.7 release notes make it unconditional). This spike's routes map `"*": detect`, which skips
  it; mapping `/v1/chat/completions` to `completions` ahead of `*` would bring it back, but the
  request is then parsed and re-serialized as Chat Completions, and whether vision's and audio's
  content parts pass through intact is unverified.
- **On detect, an `ai` policy's `transformations` can set it.** `process_detect_request` applies the
  policy's body mutations (`defaults`, `overrides`, `transformations`) to a JSON body
  (`Policy::apply_request_body_mutations`, `crates/agentgateway/src/llm/policy/mod.rs`), and a
  transformation is a CEL expression per top-level field over the body, `llmRequest`
  (`documentation/llm/transformations.md`). A `stream_options` transformation conditioned on
  `llmRequest.stream` would add it to streams only; `overrides` would add it to every request,
  non-streamed ones too, which vLLM may refuse. The expression, and what it sends on a
  non-streamed request, are unverified. Detect parses the body only when its `Content-Type` is
  `application/json`.

## Commands as run

Every command the logs hold, exactly as logged, with its time, from
`.state/agentgateway/commands-*.log`, in lines that start `+`; the output stays there, untracked.
The commands that never reached the log are quoted too, in lines that start `~`, under a heading
that says they were recovered from the session's transcript, not from the command log. Their text
is verbatim from the transcript. Their times come from the session's tool output (local time) or
from the gateway's access log (UTC, marked `Z`), and otherwise read "time not recorded". Where the
recovery shortened a command with `...`, the line is quoted as given and marked "shortened in the
recovery". The architect's walks are also under their slices' sections, slice 1's under "The walk"
and slice 4's in its steps.

### 2026-11-13 · host updates and row restarts

**Recovered from the session's transcript, not from the command log**: the session's read of the
stack at session start, and of the hosts' engines clones, from the laptop:

```text
~ 11:09:06, laptop: { date -Is; for h in gb10-1 gb10-2; do echo "== $h"; timeout 60 ssh -o BatchMode=yes $h 'apt list --upgradable 2>/dev/null | grep -vc "^Listing"; uname -r; nvidia-smi --query-gpu=driver_version --format=csv,noheader; docker --version; ls /var/run/reboot-required 2>&1 | tail -1; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"; git -C ~/spike-model-engines log --oneline -1 2>/dev/null || ls ~ | head'; done; echo "== framework"; timeout 60 ssh -o BatchMode=yes framework 'checkupdates 2>/dev/null | wc -l; uname -r; pacman -Q docker 2>/dev/null; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"; git -C ~/spike-model-engines log --oneline -1 2>/dev/null || ls ~ | head'; for h in gb10-1 gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done; } 2>&1 | tee .state/agentgateway/stack-$(date +%F).txt
~ time not recorded (11:1x), laptop: for h in gb10-1 gb10-2 framework; do echo "== $h"; ssh -o BatchMode=yes $h 'git -C ~/repos/spike-model-engines log --oneline -1; git -C ~/repos/spike-model-engines status -sb | head -2; cat ~/repos/spike-model-engines/host/vllm.env 2>/dev/null | grep -E "^VLLM_MODEL"'; done
```

The architect's root steps, recovered from the session's transcript as the architect ran them,
times not recorded (between 11:10 and 11:25): on gb10-1 and gb10-2, in tmux,

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

**Recovered from the session's transcript, not from the command log**: the post-update read before
the row restarts, the readiness poll after them (its first line at 11:27:23), and the row health
check, from the laptop:

```text
~ 11:26:08, laptop: { date -Is; for h in gb10-1 gb10-2; do echo "== $h"; timeout 60 ssh -o BatchMode=yes $h 'uptime -p; apt list --upgradable 2>/dev/null | grep -vc "^Listing"; uname -r; tailscale version | head -1; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'; done; echo "== framework"; timeout 60 ssh -o BatchMode=yes framework 'checkupdates 2>/dev/null | wc -l; uname -r; tailscale version | head -1; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'; for hp in gb10-1:8000 gb10-2:8000 framework:8001 framework:8002; do printf "%s health " $hp; curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$hp/health; done; for h in gb10-1 gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done; } 2>&1 | tee .state/agentgateway/stack-after-$(date +%F).txt
~ after 11:26:08, laptop: ssh -o BatchMode=yes gb10-1 'apt list --upgradable 2>/dev/null | grep -v ^Listing'
~ about 11:27:20, laptop: start=$(date +%s); declare -A up; while [ ${#up[@]} -lt 4 ] && [ $(( $(date +%s)-start )) -lt 1500 ]; do for hp in gb10-1:8000 gb10-2:8000 framework:8001 framework:8002; do [ -n "${up[$hp]:-}" ] && continue; if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://$hp/health)" = 200 ]; then up[$hp]=1; echo "$(date -Is) $hp healthy after $(( $(date +%s)-start ))s of polling: $(curl -s --max-time 5 http://$hp/v1/models | jq -c '[.data[].id]')"; fi; done; sleep 10; done | tee -a .state/agentgateway/rows-ready-$(date +%F).txt
~ time not recorded (about 11:38), laptop: for hp in gb10-1:8000 gb10-2:8000 framework:8001 framework:8002; do printf "%s health %s models " $hp "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://$hp/health)"; curl -s --max-time 5 http://$hp/v1/models | jq -c '[.data[].id]'; done
```

### 2026-11-13 · short names, the deploy, and the walk

Whether a container on gb10-2 resolves the rows' short names (none does):

```text
+ 2026-11-13T11:39:44-05:00 gb10-2: for h in gb10-1 gb10-2 framework; do docker run --rm --entrypoint getent vllm/vllm-openai:v0.33.0 hosts "$h" >/dev/null && echo "$h resolves" || echo "$h does not resolve"; done; grep -E "^(nameserver|search)" /etc/resolv.conf | sed -E "s/[0-9.]+$/<ns>/; s/search .*/search <tailnet domains>/"
```

**Recovered from the session's transcript, not from the command log**: the resolver check behind
`--add-host`, from the laptop:

```text
~ time not recorded (about 13:00), laptop: ssh -o BatchMode=yes gb10-2 'grep -c "^nameserver 127.0.0.53" /etc/resolv.conf; docker run --rm --entrypoint cat vllm/vllm-openai:v0.33.0 /etc/resolv.conf | grep -E "^nameserver" | sed -E "s/[0-9.]+$/<ns>/"; for h in gb10-1 framework; do tailscale ip -4 $h >/dev/null && echo "$h: tailscale ip ok"; done'
```

The architect's walk, step 1, from the laptop: `mise run agentgateway-deploy`, which logs
`[agentgateway-deploy] $ scripts/agentgateway-deploy.sh`, prints `key <name>: created` for the four
keys, and runs:

```text
+ 2026-11-13T13:29:53-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-13T13:29:54-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.irSc5x.yaml
+ 2026-11-13T13:29:54-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-13T13:29:57-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-13T13:29:58-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-13T13:29:58-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-13T13:29:58-05:00 gb10-2: docker run --detach --name agentgateway --restart unless-stopped --user "$(id -u):$(id -g)" --publish "$(tailscale ip -4):3000:3000" --publish 127.0.0.1:3001:3001 --volume "$HOME/agentgateway:/config:ro" --add-host "gb10-1:$(tailscale ip -4 gb10-1)" --add-host "gb10-2:$(tailscale ip -4 gb10-2)" --add-host "framework:$(tailscale ip -4 framework)" --label spike.spec=e1d1d93a9f78 cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml
+ 2026-11-13T13:29:58-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
```

**Recovered from the session's transcript, not from the command log**: the architect's walk from the
laptop, the deploy's invocation first (its commands are the `+` lines above), with times from the
gateway's access log:

```text
~ 18:29:53Z-18:29:58Z (13:29:53 local), laptop: mise run agentgateway-deploy 2>&1 | tee -a .state/agentgateway/commands-$(date +%F).log
~ time not recorded, gb10-2: docker logs agentgateway ; docker port agentgateway | sed "s/$(tailscale ip -4)/<tailnet>/"
~ 18:32:41Z (13:32:41 local), laptop: curl -sS -o /dev/null -w '%{http_code}\n' http://gb10-2:3000/agent/v1/models
~ 18:32:52Z (13:32:52 local), laptop: curl -sS -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" http://gb10-2:3000/agent/v1/models | jq -r '.data[].id'
~ 18:33:07Z (13:33:07 local), laptop: curl -sS -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256}' http://gb10-2:3000/agent/v1/chat/completions | jq '{model, content: .choices[0].message.content, usage}'
~ time not recorded, laptop: ssh gb10-2 docker logs --tail 3 agentgateway
~ time not recorded, laptop: ssh gb10-2 docker logs agentgateway 2>&1 | grep -F "$(cut -c1-8 .state/agentgateway/keys/architect)"
~ time not recorded, laptop: curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" http://gb10-2:3000/ui
~ time not recorded, laptop: curl -sS -m 5 -o /dev/null -w '%{http_code}\n' http://gb10-2:15000/ui
~ time not recorded, laptop: ssh -N -L 3001:127.0.0.1:3001 gb10-2
```

### 2026-11-13 · pass-through, refusals, and unrouted paths

From the laptop, with `$GW` the consumer base URL and `$K` the architect's key. A first loop over
the unrouted paths at 13:37:32 single-quoted `$GW/<path>`, so curl rejected each URL locally and
sent nothing; the loop at 13:37:38 reran it correctly. The first audio request, at 13:37:15,
failed on the laptop (jq's argument list too long) and sent nothing; the next two read the clip
with `--rawfile`, through the gateway and direct to the row.

```text
+ 2026-11-13T13:37:03-05:00 laptop: curl -sS -H "Authorization: Bearer $K" $GW/agent/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:37:03-05:00 laptop: curl -sS -H "Authorization: Bearer $K" $GW/vision/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:37:03-05:00 laptop: curl -sS -H "Authorization: Bearer $K" $GW/audio/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:37:03-05:00 laptop: curl -sS -H "Authorization: Bearer $K" $GW/embedding/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:37:03-05:00 laptop: curl -sS -N -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200}' $GW/agent/v1/chat/completions | grep -c '^data: '
+ 2026-11-13T13:37:04-05:00 laptop: curl -sS -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"model":"agent","max_tokens":300,"messages":[{"role":"user","content":"Name a primary color."}]}' $GW/agent/v1/messages | jq -c '{type, model, stop_reason, text: [.content[] | select(.type=="text") | .text], usage}'
+ 2026-11-13T13:37:06-05:00 laptop: curl -sS -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"model":"agent","max_output_tokens":300,"input":"Name a planet."}' $GW/agent/v1/responses | jq -c '{object, model, status, text: [.output[] | select(.type=="message") | .content[].text], usage: .usage.total_tokens}'
+ 2026-11-13T13:37:14-05:00 laptop: jq -n --arg img "data:image/jpeg;base64,$(base64 -w0 .state/agentgateway/assets/text.jpg)" '{model:"vision",max_tokens:100,messages:[{role:"user",content:[{type:"image_url",image_url:{url:$img}},{type:"text",text:"What text is in this image? Answer with the text only."}]}]}' | curl -sS -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d @- $GW/vision/v1/chat/completions | jq -c '{model, text: .choices[0].message.content, usage: .usage.total_tokens}'
+ 2026-11-13T13:37:15-05:00 laptop: jq -n --arg wav "$(base64 -w0 .state/agentgateway/assets/clip-6s.wav)" '{model:"audio",max_tokens:256,messages:[{role:"user",content:[{type:"input_audio",input_audio:{data:$wav,format:"wav"}},{type:"text",text:"Transcribe this audio."}]}]}' | curl -sS -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d @- $GW/audio/v1/chat/completions | jq -c '{model, text: .choices[0].message.content, usage: .usage.total_tokens}'
+ 2026-11-13T13:37:15-05:00 laptop: curl -sS -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"model":"embedding","input":["agentgateway passes requests through.","A second sentence."]}' $GW/embedding/v1/embeddings | jq -c '{model, n: (.data|length), dims: (.data[0].embedding|length), usage}'
+ 2026-11-13T13:37:22-05:00 laptop: base64 -w0 .state/agentgateway/assets/clip-6s.wav > .state/agentgateway/assets/clip-6s.b64; jq -n --rawfile wav .state/agentgateway/assets/clip-6s.b64 '{model:"audio",max_tokens:256,messages:[{role:"user",content:[{type:"input_audio",input_audio:{data:$wav,format:"wav"}},{type:"text",text:"Transcribe this audio."}]}]}' | curl -sS -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d @- $GW/audio/v1/chat/completions | jq -c '{model, text: .choices[0].message.content, usage: .usage.total_tokens}'
+ 2026-11-13T13:37:23-05:00 laptop: jq -n --rawfile wav .state/agentgateway/assets/clip-6s.b64 '{model:"audio",max_tokens:256,messages:[{role:"user",content:[{type:"input_audio",input_audio:{data:$wav,format:"wav"}},{type:"text",text:"Transcribe this audio."}]}]}' | curl -sS -H 'Content-Type: application/json' -d @- http://framework:8001/v1/chat/completions | jq -c '{model, text: .choices[0].message.content}'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(openssl rand -hex 32)" $GW/agent/v1/models
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer ' $GW/agent/v1/models
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /metrics\n' -H "Authorization: Bearer $K" '$GW/metrics'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /health\n' -H "Authorization: Bearer $K" '$GW/health'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /version\n' -H "Authorization: Bearer $K" '$GW/version'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /tokenize\n' -H "Authorization: Bearer $K" '$GW/tokenize'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /docs\n' -H "Authorization: Bearer $K" '$GW/docs'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /openapi.json\n' -H "Authorization: Bearer $K" '$GW/openapi.json'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /v1/models\n' -H "Authorization: Bearer $K" '$GW/v1/models'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/metrics\n' -H "Authorization: Bearer $K" '$GW/agent/metrics'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/health\n' -H "Authorization: Bearer $K" '$GW/agent/health'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/v1/../../metrics\n' -H "Authorization: Bearer $K" '$GW/agent/v1/../../metrics'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/v1/%2e%2e/%2e%2e/metrics\n' -H "Authorization: Bearer $K" '$GW/agent/v1/%2e%2e/%2e%2e/metrics'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/v1/..%2f..%2fmetrics\n' -H "Authorization: Bearer $K" '$GW/agent/v1/..%2f..%2fmetrics'
+ 2026-11-13T13:37:32-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /AGENT/v1/models\n' -H "Authorization: Bearer $K" '$GW/AGENT/v1/models'
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /metrics\n' -H "Authorization: Bearer $K" "$GW/metrics"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /health\n' -H "Authorization: Bearer $K" "$GW/health"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /version\n' -H "Authorization: Bearer $K" "$GW/version"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /tokenize\n' -H "Authorization: Bearer $K" "$GW/tokenize"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /docs\n' -H "Authorization: Bearer $K" "$GW/docs"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /openapi.json\n' -H "Authorization: Bearer $K" "$GW/openapi.json"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /v1/models\n' -H "Authorization: Bearer $K" "$GW/v1/models"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/metrics\n' -H "Authorization: Bearer $K" "$GW/agent/metrics"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/health\n' -H "Authorization: Bearer $K" "$GW/agent/health"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/v1/../../metrics\n' -H "Authorization: Bearer $K" "$GW/agent/v1/../../metrics"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/v1/%2e%2e/%2e%2e/metrics\n' -H "Authorization: Bearer $K" "$GW/agent/v1/%2e%2e/%2e%2e/metrics"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /agent/v1/..%2f..%2fmetrics\n' -H "Authorization: Bearer $K" "$GW/agent/v1/..%2f..%2fmetrics"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS --path-as-is -o /dev/null -w '%{http_code} /AGENT/v1/models\n' -H "Authorization: Bearer $K" "$GW/AGENT/v1/models"
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} /metrics no key\n' $GW/metrics
+ 2026-11-13T13:37:38-05:00 laptop: curl -sS -H "Authorization: Bearer $K" -H 'Content-Type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' $GW/agent/v1/chat/completions | jq -c '{error: .error.message}'
```

**Recovered from the session's transcript, not from the command log**: the read of the gateway's log
after these requests:

```text
~ 13:37:38 or after, laptop: ssh -o BatchMode=yes gb10-2 'docker logs --since 2m agentgateway 2>&1' | grep -E "metrics|AGENT" | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/' | cut -c1-260
```

### 2026-11-13 · revocation

From the laptop, with `$R` revoke-test's key. The 13:39:15 stream is the 13:38:00 request
again, logged abbreviated; it ran detached, and curl exited 0 at 13:39:53.

```text
+ 2026-11-13T13:38:00-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} revoke-test before\n' -H "Authorization: Bearer $R" $GW/agent/v1/models
+ 2026-11-13T13:38:00-05:00 laptop: (curl -sS -N -H "Authorization: Bearer $R" -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Write a 600-word story about a lighthouse."}],"max_tokens":2000}' $GW/agent/v1/chat/completions > .state/agentgateway/revoke-stream.txt; echo "stream curl exit $? at $(date -Iseconds)" >> .state/agentgateway/revoke-stream.txt) &
+ 2026-11-13T13:38:45-05:00 laptop: grep -n -A2 'name: revoke-test' gateway/agentgateway/config.yaml | head -3; sed -i '/keyHash: sha256:@@revoke-test@@/,+2d' gateway/agentgateway/config.yaml; grep -c revoke-test gateway/agentgateway/config.yaml
+ 2026-11-13T13:38:45-05:00 laptop: mise run agentgateway-deploy 2>&1 | grep -E '^key|unchanged|docker ps|Up '
+ 2026-11-13T13:38:46-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-13T13:38:46-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} revoke-test after\n' -H "Authorization: Bearer $R" $GW/agent/v1/models
+ 2026-11-13T13:38:46-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} architect after\n' -H "Authorization: Bearer $K" $GW/agent/v1/models
+ 2026-11-13T13:38:46-05:00 laptop: grep -c '^data: ' .state/agentgateway/revoke-stream.txt; grep -o '"finish_reason":"[a-z]*"' .state/agentgateway/revoke-stream.txt | tail -1; tail -2 .state/agentgateway/revoke-stream.txt
+ 2026-11-13T13:39:12-05:00 laptop: git checkout gateway/agentgateway/config.yaml && mise run agentgateway-deploy 2>&1 | grep -E '^key|unchanged'
+ 2026-11-13T13:39:15-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} revoke-test readmitted\n' -H "Authorization: Bearer $R" $GW/agent/v1/models
+ 2026-11-13T13:39:15-05:00 laptop: curl -sS -N -H "Authorization: Bearer $R" ... '{"model":"agent","stream":true,..."Write a 600-word story about a lighthouse."...,"max_tokens":2000}' $GW/agent/v1/chat/completions > .state/agentgateway/revoke-stream.txt &  (detached)
+ 2026-11-13T13:39:21-05:00 laptop: grep -c '^data: ' .state/agentgateway/revoke-stream.txt
+ 2026-11-13T13:39:21-05:00 laptop: sed -i '/keyHash: sha256:@@revoke-test@@/,+2d' gateway/agentgateway/config.yaml && mise run agentgateway-deploy 2>&1 | grep -E '^key|unchanged'
+ 2026-11-13T13:39:24-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} revoke-test new request after revoke\n' -H "Authorization: Bearer $R" $GW/agent/v1/models
+ 2026-11-13T13:39:24-05:00 laptop: grep -c '^data: ' .state/agentgateway/revoke-stream.txt
+ 2026-11-13T13:39:53-05:00 laptop: grep -c '^data: ' .state/agentgateway/revoke-stream.txt; grep -o '"finish_reason":"[a-z]*"' .state/agentgateway/revoke-stream.txt | tail -1; tail -1 .state/agentgateway/revoke-stream.txt
```

**Recovered from the session's transcript, not from the command log**: the 13:39:15 stream exactly
as run, which the log holds abbreviated, and the reads after the second revoke:

```text
~ 13:39:15, laptop: curl -sS -N -H "Authorization: Bearer $R" -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Write a 600-word story about a lighthouse."}],"max_tokens":2000}' $GW/agent/v1/chat/completions > .state/agentgateway/revoke-stream.txt 2>&1 &
~ about 13:40, laptop (shortened in the recovery): R=$(cat .state/agentgateway/keys/revoke-test); curl -sS -o /dev/null -w '%{http_code} revoke-test now\n' -H "Authorization: Bearer $R" http://gb10-2:3000/agent/v1/models; ssh -o BatchMode=yes gb10-2 'docker logs --since 5m agentgateway 2>&1 | grep -v "request gateway" | tail; ...'
```

### 2026-11-13 · the overhead cells

From the laptop, from the repository root: the pre-checks, then the twelve runs and the four
readings. Each `cell` line is followed by the GuideLLM command it ran, and on a gateway run the
sampling of the container on gb10-2; the bench key appears only as the expression that reads it.
Each `cell` also ran `summarize`, whose lines are in the log, not here.

```text
+ 2026-11-13T13:55:41-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T13:55:41-05:00 laptop: curl -sS --max-time 5 http://gb10-1:8000/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:55:41-05:00 laptop: curl -sS --max-time 5 http://gb10-2:8000/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:55:41-05:00 laptop: curl -sS --max-time 5 http://framework:8001/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:55:41-05:00 laptop: curl -sS --max-time 5 http://framework:8002/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T13:55:41-05:00 laptop: ssh gb10-2 docker stats --no-stream agentgateway
+ 2026-11-13T13:55:49-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T13:55:49-05:00 laptop: cell o-agent-d1 overhead-agent direct agent
+ 2026-11-13T13:55:49-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-1:8000/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=2383091769 --output kind=json,path=.state/agentgateway/cells/o-agent-d1/result.json --disable-console-interactive > .state/agentgateway/cells/o-agent-d1/guidellm.log 2>&1
+ 2026-11-13T13:58:01-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T13:58:01-05:00 laptop: cell o-agent-g overhead-agent gateway agent
+ 2026-11-13T13:58:01-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/agent/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=3452232323 --output kind=json,path=.state/agentgateway/cells/o-agent-g/result.json --disable-console-interactive > .state/agentgateway/cells/o-agent-g/guidellm.log 2>&1
+ 2026-11-13T13:58:01-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/o-agent-g/gateway-stats.tsv
+ 2026-11-13T14:00:15-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:00:15-05:00 laptop: cell o-agent-d2 overhead-agent direct agent
+ 2026-11-13T14:00:15-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-1:8000/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=4242556906 --output kind=json,path=.state/agentgateway/cells/o-agent-d2/result.json --disable-console-interactive > .state/agentgateway/cells/o-agent-d2/guidellm.log 2>&1
+ 2026-11-13T14:02:19-05:00 laptop: compare o-agent-d1 o-agent-g o-agent-d2
+ 2026-11-13T14:02:26-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:02:26-05:00 laptop: cell o-vision-d1 overhead-vision direct vision
+ 2026-11-13T14:02:26-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8000/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=2559911716 --output kind=json,path=.state/agentgateway/cells/o-vision-d1/result.json --disable-console-interactive > .state/agentgateway/cells/o-vision-d1/guidellm.log 2>&1
+ 2026-11-13T14:04:18-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:04:18-05:00 laptop: cell o-vision-g overhead-vision gateway vision
+ 2026-11-13T14:04:18-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=761397208 --output kind=json,path=.state/agentgateway/cells/o-vision-g/result.json --disable-console-interactive > .state/agentgateway/cells/o-vision-g/guidellm.log 2>&1
+ 2026-11-13T14:04:18-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/o-vision-g/gateway-stats.tsv
+ 2026-11-13T14:06:19-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:06:19-05:00 laptop: cell o-vision-d2 overhead-vision direct vision
+ 2026-11-13T14:06:19-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8000/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=3934157047 --output kind=json,path=.state/agentgateway/cells/o-vision-d2/result.json --disable-console-interactive > .state/agentgateway/cells/o-vision-d2/guidellm.log 2>&1
+ 2026-11-13T14:08:03-05:00 laptop: compare o-vision-d1 o-vision-g o-vision-d2
+ 2026-11-13T14:08:29-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:08:29-05:00 laptop: cell o-audio-d1 overhead-audio direct audio
+ 2026-11-13T14:08:29-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8001/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-audio.yaml --backend kind=openai_http,model=audio --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it --seed kind=static,value=2201218434 --output kind=json,path=.state/agentgateway/cells/o-audio-d1/result.json --disable-console-interactive > .state/agentgateway/cells/o-audio-d1/guidellm.log 2>&1
+ 2026-11-13T14:08:59-05:00 laptop: cell o-audio-g overhead-audio gateway audio
+ 2026-11-13T14:08:59-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/audio/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-audio.yaml --backend kind=openai_http,model=audio --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it --seed kind=static,value=995812550 --output kind=json,path=.state/agentgateway/cells/o-audio-g/result.json --disable-console-interactive > .state/agentgateway/cells/o-audio-g/guidellm.log 2>&1
+ 2026-11-13T14:08:59-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/o-audio-g/gateway-stats.tsv
+ 2026-11-13T14:09:30-05:00 laptop: cell o-audio-d2 overhead-audio direct audio
+ 2026-11-13T14:09:30-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8001/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-audio.yaml --backend kind=openai_http,model=audio --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it --seed kind=static,value=4057510481 --output kind=json,path=.state/agentgateway/cells/o-audio-d2/result.json --disable-console-interactive > .state/agentgateway/cells/o-audio-d2/guidellm.log 2>&1
+ 2026-11-13T14:09:56-05:00 laptop: compare o-audio-d1 o-audio-g o-audio-d2
+ 2026-11-13T14:10:05-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:10:05-05:00 laptop: cell o-embed-d1 overhead-embed direct embedding
+ 2026-11-13T14:10:05-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=3070919766 --output kind=json,path=.state/agentgateway/cells/o-embed-d1/result.json --disable-console-interactive > .state/agentgateway/cells/o-embed-d1/guidellm.log 2>&1
+ 2026-11-13T14:11:19-05:00 laptop: cell o-embed-g overhead-embed gateway embedding
+ 2026-11-13T14:11:19-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/embedding/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=1713866626 --output kind=json,path=.state/agentgateway/cells/o-embed-g/result.json --disable-console-interactive > .state/agentgateway/cells/o-embed-g/guidellm.log 2>&1
+ 2026-11-13T14:11:19-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/o-embed-g/gateway-stats.tsv
+ 2026-11-13T14:12:38-05:00 laptop: cell o-embed-d2 overhead-embed direct embedding
+ 2026-11-13T14:12:38-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=3319913349 --output kind=json,path=.state/agentgateway/cells/o-embed-d2/result.json --disable-console-interactive > .state/agentgateway/cells/o-embed-d2/guidellm.log 2>&1
+ 2026-11-13T14:13:53-05:00 laptop: compare o-embed-d1 o-embed-g o-embed-d2
```

### 2026-11-13 · the firewall reads

**Recovered from the session's transcript, not from the command log**: between slices 2 and 3, about
14:20–14:40, times not recorded, the session read the firewall state behind the fence the architect
then removed (behavior 6), read-only and without root, from the laptop. The last command's output
carried tailnet addresses unredacted, so no output of these reads is quoted here.

```text
~ time not recorded, laptop: gh release list -R chaifeng/ufw-docker --limit 3; ssh -o BatchMode=yes framework 'pacman -Qi ufw-docker 2>/dev/null | grep -E "^(Name|Version|Repository|URL)"; pacman -Qo $(command -v ufw-docker) 2>/dev/null; command -v ufw-docker'; for h in gb10-1 gb10-2; do ssh -o BatchMode=yes $h 'echo "== $(hostname)"; dpkg-query -W ufw 2>/dev/null || echo "ufw not installed"; command -v ufw-docker || echo "no ufw-docker"; systemctl is-enabled ufw 2>&1; systemctl is-active ufw 2>&1'; done
~ time not recorded, laptop (shortened in the recovery): for h in gb10-1 gb10-2 framework; do ssh -o BatchMode=yes $h 'echo "== $(hostname)"; grep -E "^ENABLED" /etc/ufw/ufw.conf; grep -E "^DEFAULT_(INPUT|FORWARD|OUTPUT)_POLICY" /etc/default/ufw; ...'; done
~ time not recorded, laptop: ssh -o BatchMode=yes framework 'grep -E "^### tuple|^-A" /etc/ufw/user.rules | grep "^### tuple"' | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?/<v4>/g'
~ time not recorded, laptop (shortened in the recovery): for h in gb10-1 gb10-2; do ssh -o BatchMode=yes $h 'echo "== $(hostname)"; ip -br link | awk "{print \$1, \$2}" | grep -v -E "^(veth|lo )"; ss -Hltn ...'; done
```

### 2026-11-13 · the cap cells, probes, go-ai and infer

From the laptop, from the repository root, `$(<.state/agentgateway/keys/<name>)` being the only
form in which a key appears. A deploy is logged by the commands it runs on gb10-2, after its
`key <name>: existing` and `overlay <name>: applied` lines (in the log, not here): the access-log
overlay at 14:43:38; `access-log rate-limit-agent` at 14:55:43; `in-flight-1` at 14:56:15; none at
14:57:08; `key-header` at 14:58:46; and none at 14:58:50. `cell` logs the GuideLLM command it runs
and its samplers, and `summarize`'s lines, printed twice for each run, stay in the log. The
commands run outside the helpers follow the log's lines, recovered from the session's transcript.

```text
+ 2026-11-13T14:43:31-05:00 laptop: for row in agent:gb10-1:8000 vision:gb10-2:8000 audio:framework:8001 embedding:framework:8002; do printf "%s: " "${row%%:*}"; curl -sS --max-time 5 "http://${row#*:}/v1/models" | jq -c "[.data[].id]"; done; ssh gb10-2 docker stats --no-stream agentgateway; ssh gb10-2 head -1 "~/agentgateway/config.yaml"
+ 2026-11-13T14:43:38-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-13T14:43:38-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.OpqmkN.yaml
+ 2026-11-13T14:43:38-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-13T14:43:38-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-13T14:43:38-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-13T14:43:38-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-13T14:43:38-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-13T14:43:46-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:43:46-05:00 laptop: cell c-agent cap-agent cap agent
+ 2026-11-13T14:43:46-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/agent/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/cap-agent.yaml --backend kind=openai_http,model=agent --tokenizer kind=huggingface_auto,model=openai/gpt-oss-120b --seed kind=static,value=2489647318 --output kind=json,path=.state/agentgateway/cells/c-agent/result.json --disable-console-interactive > .state/agentgateway/cells/c-agent/guidellm.log 2>&1
+ 2026-11-13T14:43:46-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/c-agent/gateway-stats.tsv
+ 2026-11-13T14:43:46-05:00 laptop: every 5 s while it runs: curl -sS --max-time 3 http://gb10-1:8000/metrics, the sums of vllm:num_requests_running and vllm:num_requests_waiting >> .state/agentgateway/cells/c-agent/row-metrics.tsv
+ 2026-11-13T14:47:58-05:00 laptop: ssh -n gb10-2 'docker logs --timestamps --since 1794599026 --until 1794599279 agentgateway 2>&1' | the lines of route=default/agent as time, status, path, retry_after > .state/agentgateway/cells/c-agent/gateway-requests.tsv
+ 2026-11-13T14:48:02-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:48:10-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:48:10-05:00 laptop: cell c-vision cap-vision cap vision
+ 2026-11-13T14:48:10-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/cap-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=1282260406 --output kind=json,path=.state/agentgateway/cells/c-vision/result.json --disable-console-interactive > .state/agentgateway/cells/c-vision/guidellm.log 2>&1
+ 2026-11-13T14:48:10-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/c-vision/gateway-stats.tsv
+ 2026-11-13T14:48:10-05:00 laptop: every 5 s while it runs: curl -sS --max-time 3 http://gb10-2:8000/metrics, the sums of vllm:num_requests_running and vllm:num_requests_waiting >> .state/agentgateway/cells/c-vision/row-metrics.tsv
+ 2026-11-13T14:51:01-05:00 laptop: ssh -n gb10-2 'docker logs --timestamps --since 1794599290 --until 1794599462 agentgateway 2>&1' | the lines of route=default/vision as time, status, path, retry_after > .state/agentgateway/cells/c-vision/gateway-requests.tsv
+ 2026-11-13T14:51:09-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:51:09-05:00 laptop: cell c-audio cap-audio cap audio
+ 2026-11-13T14:51:09-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/audio/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/cap-audio.yaml --backend kind=openai_http,model=audio --tokenizer kind=huggingface_auto,model=google/gemma-4-E4B-it --seed kind=static,value=3023674224 --output kind=json,path=.state/agentgateway/cells/c-audio/result.json --disable-console-interactive > .state/agentgateway/cells/c-audio/guidellm.log 2>&1
+ 2026-11-13T14:51:09-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/c-audio/gateway-stats.tsv
+ 2026-11-13T14:51:09-05:00 laptop: every 5 s while it runs: curl -sS --max-time 3 http://framework:8001/metrics, the sums of vllm:num_requests_running and vllm:num_requests_waiting >> .state/agentgateway/cells/c-audio/row-metrics.tsv
+ 2026-11-13T14:51:59-05:00 laptop: ssh -n gb10-2 'docker logs --timestamps --since 1794599469 --until 1794599520 agentgateway 2>&1' | the lines of route=default/audio as time, status, path, retry_after > .state/agentgateway/cells/c-audio/gateway-requests.tsv
+ 2026-11-13T14:52:07-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-13T14:52:07-05:00 laptop: cell c-embed cap-embed cap embedding
+ 2026-11-13T14:52:07-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/embedding/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/cap-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=726206947 --output kind=json,path=.state/agentgateway/cells/c-embed/result.json --disable-console-interactive > .state/agentgateway/cells/c-embed/guidellm.log 2>&1
+ 2026-11-13T14:52:07-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/agentgateway/cells/c-embed/gateway-stats.tsv
+ 2026-11-13T14:52:07-05:00 laptop: every 5 s while it runs: curl -sS --max-time 3 http://framework:8002/metrics, the sums of vllm:num_requests_running and vllm:num_requests_waiting >> .state/agentgateway/cells/c-embed/row-metrics.tsv
+ 2026-11-13T14:54:45-05:00 laptop: ssh -n gb10-2 'docker logs --timestamps --since 1794599527 --until 1794599686 agentgateway 2>&1' | the lines of route=default/embedding as time, status, path, retry_after > .state/agentgateway/cells/c-embed/gateway-requests.tsv
+ 2026-11-13T14:55:24-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:55:29-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:55:29-05:00 laptop: git -C ~/architecture/go-ai worktree add --detach .state/agentgateway/go-ai tools/infer/v0.1.0
+ 2026-11-13T14:55:29-05:00 laptop: GOBIN=.state/agentgateway/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.1.0 && .state/agentgateway/bin/infer version
+ 2026-11-13T14:55:43-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:55:43-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-13T14:55:43-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.O1B0Ki.yaml
+ 2026-11-13T14:55:43-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-13T14:55:43-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-13T14:55:43-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-13T14:55:43-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-13T14:55:43-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-13T14:55:45-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:55:45-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:55:45-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:55:45-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:55:53-05:00 laptop: source scripts/clients-lib.sh
```

From here to 14:58:53, the client helpers log each command with its arguments joined, which loses
curl's quoting: a `-w` format, a `-H` header, or a `-d` body shows without the quotes it ran with.

```text
+ 2026-11-13T14:56:02-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:56:02-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:56:02-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/agentgateway/bin/infer --retries 3 --retry-base-delay 500ms --retry-max-delay 15s chat Name a primary color.
+ 2026-11-13T14:56:15-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:56:15-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-13T14:56:15-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.EGdhnk.yaml
+ 2026-11-13T14:56:15-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-13T14:56:15-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-13T14:56:15-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-13T14:56:15-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-13T14:56:15-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-13T14:56:17-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -o .state/agentgateway/inflight-stream.txt -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Write a 400-word story about a lighthouse."}],"max_tokens":1500} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-13T14:56:20-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:57:08-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:57:08-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-13T14:57:08-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.jSgSpz.yaml
+ 2026-11-13T14:57:08-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-13T14:57:08-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-13T14:57:09-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-13T14:57:09-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-13T14:57:09-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-13T14:57:11-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-13T14:57:16-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:57:16-05:00 laptop: goai_tier goai-tier agent vision audio embedding
+ 2026-11-13T14:57:16-05:00 laptop: cd .state/agentgateway/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/agentgateway/clients/goai-tier.log
+ 2026-11-13T14:58:15-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:58:15-05:00 laptop: infer_tier infer-tier agent vision audio embedding
+ 2026-11-13T14:58:15-05:00 laptop: cd .state/agentgateway/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/agentgateway/clients/infer-tier.log
+ 2026-11-13T14:58:46-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:58:46-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-13T14:58:46-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.gAnnsL.yaml
+ 2026-11-13T14:58:46-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-13T14:58:46-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-13T14:58:46-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-13T14:58:46-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-13T14:58:46-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-13T14:58:49-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} bearer\n http://gb10-2:3000/embedding/v1/models
+ 2026-11-13T14:58:49-05:00 laptop: goai_tier goai-tier-header embedding
+ 2026-11-13T14:58:49-05:00 laptop: cd .state/agentgateway/go-ai/. && AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_HEADER='x-api-key: '$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/agentgateway/clients/goai-tier-header.log
+ 2026-11-13T14:58:50-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-13T14:58:50-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.uAd7Du.yaml
+ 2026-11-13T14:58:50-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-13T14:58:50-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-13T14:58:50-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-13T14:58:50-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-13T14:58:50-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-13T14:58:53-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} bearer restored\n http://gb10-2:3000/embedding/v1/models
+ 2026-11-13T14:59:05-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T14:59:05-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T14:59:05-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/vision/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T14:59:05-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/audio/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T14:59:05-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/embedding/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T14:59:05-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/agentgateway/bin/infer chat Name a planet.
+ 2026-11-13T14:59:07-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/vision/v1 .state/agentgateway/bin/infer chat Say hello in three words.
+ 2026-11-13T14:59:07-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/audio/v1 .state/agentgateway/bin/infer chat Say hello in three words.
+ 2026-11-13T14:59:07-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/embedding/v1 .state/agentgateway/bin/infer embed first passage second passage
+ 2026-11-13T14:59:14-05:00 laptop: git -C ~/architecture/go-ai worktree remove .state/agentgateway/go-ai
= 2026-11-13T14:59:18-05:00 note: the clean-up ran as: git -C ~/architecture/go-ai worktree remove ~/experiments/spike-model-gateway/.state/agentgateway/go-ai
```

**Recovered from the session's transcript, not from the command log**: the commands run outside the
helpers. First the embedding cap cell's inspection, then the read of the gateway's log in the 429
probe, the read after infer's retry run, the 503 probe as run, line by line (with the probe's
keyless curl and infer's `--retries 2` run against the in-flight limit), and the header case's
check:

```text
~ time not recorded (about 14:55), laptop (shortened in the recovery): grep -E "completed \||elapsed=" .state/agentgateway/cells/c-embed/guidellm.log ...; curl -s --max-time 5 http://framework:8002/metrics | grep -E "^vllm:num_requests_(running|waiting)" | head
~ 14:55:45, laptop: ssh gb10-2 'docker logs --since 1m agentgateway 2>&1' | grep 'route=default/agent' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/' | tail -4 | cut -c1-330
~ 14:56:05, laptop: ssh gb10-2 'docker logs --since 1m agentgateway 2>&1' | grep 'route=default/agent' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/' | tail -4 | grep -oE '^[^ ]+|http.path=[^ ]+|http.status=[0-9]+|endpoint=[^ ]+|retry_after="[0-9]+"' | paste -sd' ' | sed 's/ 2026/\n2026/g'
~ 14:56:15, laptop: scripts/agentgateway-deploy.sh in-flight-1 2>&1 | tee -a $L | grep -E "overlay|valid|reloads|rror"; sleep 2
~ 14:56:15, laptop: gw_curl architect -sS -N -o .state/agentgateway/inflight-stream.txt -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Write a 400-word story about a lighthouse."}],"max_tokens":1500}' http://gb10-2:3000/agent/v1/chat/completions >/dev/null 2>&1 &
~ 14:56:15, laptop: sleep 3
~ 14:56:15, laptop: gw_curl architect -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models 2>&1 | grep -iE '^(HTTP|retry-after)'
~ 14:56:15, laptop: curl -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models | grep -iE '^(HTTP|retry-after)'
~ 14:56:15, laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 timeout 20 .state/agentgateway/bin/infer --retries 2 --retry-base-delay 500ms --retry-max-delay 2s models 2>&1 | tail -2
~ 14:56:15, laptop: wait; echo "-- stream: $(grep -c '^data: ' .state/agentgateway/inflight-stream.txt) events, $(grep -o '"finish_reason":"[a-z]*"' .state/agentgateway/inflight-stream.txt | tail -1)"
~ 14:56:15, laptop: echo "-- 503 lines in log: $(ssh gb10-2 'docker logs --since 2m agentgateway 2>&1' | grep -c 'http.status=503')"
~ 14:58:5x, laptop: grep -E "^(=== RUN|--- (PASS|SKIP|FAIL)).*[Ee]mbed|^    --- .*[Ee]mbed|[Ee]mbed.*\([0-9.]+s\)" .state/agentgateway/clients/goai-tier-header.log | head; grep -E "^--- PASS" .state/agentgateway/clients/goai-tier-header.log | grep -v "(0.00s)"; ssh gb10-2 'docker logs --since 3m agentgateway 2>&1' | grep 'route=default/embedding' | grep -oE 'http.path=[^ ]+ http.version=[^ ]+ http.status=[0-9]+' | sort | uniq -c
```

The clean-up's `+` line is the planned form; the note after it records that the removal ran with
the worktree's absolute path:

```sh
git -C ~/architecture/go-ai worktree remove ~/experiments/spike-model-gateway/.state/agentgateway/go-ai
```

### 2026-11-13 · the walkthrough

**Recovered from the session's transcript, not from the command log**, with times from the gateway's
access log: the architect ran step 2's three commands joined on one line, time not recorded; steps 3
to 7 as written under "Slice 4 · walkthrough" (step 3's loop, time not recorded; step 4's keyless
chat at 20:06:49Z and keyed chat at 20:07:00Z; step 5's revoke-test at 20:07:44Z; step 6's
`/metrics` at 20:08:04Z and again at 20:08:31Z; step 7's `docker stats` and `docker logs --tail 6`,
time not recorded); and, between steps 4 and 5, the streamed chat the session gave in reply to the
architect's question:

```text
~ time not recorded, laptop: ssh gb10-2 head -1 '~/agentgateway/config.yaml' ; ssh gb10-2 "docker ps --filter name=agentgateway --format '{{.Names}}  {{.Image}}  {{.Status}}'" ; ssh gb10-2 'docker port agentgateway | sed "s/$(tailscale ip -4)/<tailnet>/"'
~ 20:07:28Z (15:07:28 local), laptop: curl -sS -N -H "Authorization: Bearer $(cat .state/agentgateway/keys/architect)" -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 10."}],"max_tokens":300}' http://gb10-2:3000/agent/v1/chat/completions
```

### 2026-11-13 · after the reviews

From the laptop, after the slices, at review: behavior 3's requests direct to the rows and
behavior 2's restart read-out (15:18:56–15:19:03), then the infer CLI recapture (15:19:10–15:19:12),
whose helper logs each command with its arguments joined:

```text
+ 2026-11-13T15:18:56-05:00 laptop: curl -sS -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256}' http://gb10-1:8000/v1/chat/completions | jq -c '{model, content: .choices[0].message.content, usage: .usage.total_tokens}'
+ 2026-11-13T15:18:59-05:00 laptop: curl -sS -N -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200}' http://gb10-1:8000/v1/chat/completions | grep -c '^data: '
+ 2026-11-13T15:19:00-05:00 laptop: curl -sS -H 'Content-Type: application/json' -d '{"model":"agent","max_tokens":300,"messages":[{"role":"user","content":"Name a primary color."}]}' http://gb10-1:8000/v1/messages | jq -c '{type, model, stop_reason, text: [.content[] | select(.type=="text") | .text], usage}'
+ 2026-11-13T15:19:01-05:00 laptop: curl -sS -H 'Content-Type: application/json' -d '{"model":"agent","max_output_tokens":300,"input":"Name a planet."}' http://gb10-1:8000/v1/responses | jq -c '{object, model, status, text: [.output[] | select(.type=="message") | .content[].text], usage: .usage.total_tokens}'
+ 2026-11-13T15:19:03-05:00 laptop: jq -n --arg img "data:image/jpeg;base64,$(base64 -w0 .state/agentgateway/assets/text.jpg)" '{model:"vision",max_tokens:100,messages:[{role:"user",content:[{type:"image_url",image_url:{url:$img}},{type:"text",text:"What text is in this image? Answer with the text only."}]}]}' | curl -sS -H 'Content-Type: application/json' -d @- http://gb10-2:8000/v1/chat/completions | jq -c '{model, text: .choices[0].message.content, usage: .usage.total_tokens}'
+ 2026-11-13T15:19:03-05:00 laptop: curl -sS -H 'Content-Type: application/json' -d '{"model":"embedding","input":["agentgateway passes requests through.","A second sentence."]}' http://framework:8002/v1/embeddings | jq -c '{model, n: (.data|length), dims: (.data[0].embedding|length), usage}'
+ 2026-11-13T15:19:03-05:00 laptop: ssh gb10-2 "docker inspect agentgateway --format '{{.Config.Image}} restart={{.HostConfig.RestartPolicy.Name}} started={{.State.StartedAt}}'; systemctl is-enabled docker; uptime -s"
+ 2026-11-13T15:19:10-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-13T15:19:10-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T15:19:10-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/vision/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T15:19:10-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/audio/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T15:19:10-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/embedding/v1 .state/agentgateway/bin/infer models
+ 2026-11-13T15:19:10-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/agent/v1 .state/agentgateway/bin/infer chat Name a planet.
+ 2026-11-13T15:19:12-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3000/embedding/v1 .state/agentgateway/bin/infer embed first passage second passage
```

**Recovered from the session's transcript, not from the command log**: the wrapper the recapture ran
in, which wrote its output to `.state/agentgateway/clients/infer-cli-1519.txt`:

```text
~ 15:19, laptop: O=.state/agentgateway/clients/infer-cli-$(date +%H%M).txt; { for a in agent vision audio embedding; do echo "-- $a models"; infer_at "$a" models; done; echo "-- agent chat"; infer_at agent chat "Name a planet."; echo "-- embedding embed"; infer_at embedding embed "first passage" "second passage"; } > $O 2>&1
```

### 2026-11-13 · the reboot of gb10-2

From the laptop: the watcher, logged by its one-line description, which ran from 16:05:04 across
the architect's reboot of gb10-2 (`sudo reboot`, a root step, time not recorded) and wrote each
change of state to `.state/agentgateway/reboot-2026-11-13.txt`; then the read-outs after it, with
`$GW` the consumer base URL:

```text
+ 2026-11-13T16:05:04-05:00 laptop: watch every 5 s: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -o /dev/null -w %{http_code} --max-time 3 http://gb10-2:3000/agent/v1/models; curl -s -o /dev/null -w %{http_code} --max-time 3 http://gb10-2:8000/health
+ 2026-11-13T16:12:20-05:00 laptop: ssh gb10-2 "uptime -s; docker inspect agentgateway --format 'restart={{.HostConfig.RestartPolicy.Name}} started={{.State.StartedAt}} restarts={{.RestartCount}}'; docker ps --format '{{.Names}} {{.Status}}'; head -1 ~/agentgateway/config.yaml"
+ 2026-11-13T16:12:20-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS $GW/agent/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T16:12:20-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS $GW/vision/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T16:12:20-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS $GW/audio/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T16:12:21-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS $GW/embedding/v1/models | jq -c '[.data[].id]'
+ 2026-11-13T16:12:21-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} keyless\n' $GW/agent/v1/models
```
