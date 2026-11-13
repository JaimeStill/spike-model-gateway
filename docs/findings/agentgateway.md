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
deploy and the architect's walk from 13:29, the session's probes from 13:37 to 13:39. Every
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
a request is routed. Behavior 6's firewall doesn't cover this: it admits the gateway as the rows'
one source, and these requests come from the gateway.

**The key is never logged.** A search of the full container log for the first 8 characters of the
architect's key, after the walk's requests, found nothing (grep exit 1).

**Behavior 14: currency.** `mise run currency` reports only python, which is held; the agentgateway
pin is current.

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

### 2026-11-13 · short names, the deploy, and the walk

Whether a container on gb10-2 resolves the rows' short names (none does):

```text
+ 2026-11-13T11:39:44-05:00 gb10-2: for h in gb10-1 gb10-2 framework; do docker run --rm --entrypoint getent vllm/vllm-openai:v0.33.0 hosts "$h" >/dev/null && echo "$h resolves" || echo "$h does not resolve"; done; grep -E "^(nameserver|search)" /etc/resolv.conf | sed -E "s/[0-9.]+$/<ns>/; s/search .*/search <tailnet domains>/"
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

The walk's further steps, `docker logs` and `docker port` on gb10-2, the first requests, the
key search, the 404 and refused probes, and the UI tunnel, are the commands under "The walk" above,
run by the architect as written there.

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

### 2026-11-13 · revocation

From the laptop, with `$R` revoke-test's key. The 13:39:15 stream is the 13:38:00 request
again, logged abbreviated; it ran detached, and curl exited 0 at 13:39:53.

```text
+ 2026-11-13T13:38:00-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} revoke-test before\n' -H "Authorization: Bearer $R" $GW/agent/v1/models
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
