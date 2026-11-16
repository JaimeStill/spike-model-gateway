# routing

Whether agentgateway's `llm` section can serve the four aliases the way the inline route `ai`
backends do, which agentgateway's UI labels "legacy". The task trials `llm` live beside route `ai`,
keeps it only if behaviors 1–6 of the task brief all hold, and otherwise returns to route `ai`
(evidence 1 and 8 of [`context/README.md`](../../context/README.md#the-evidence)). This finding
holds slice 1, the trial; slices 2 and 3 add the tiers, the final verdict, and the settled form.

- **Measured:** 2026-11-16, 07:54–07:59 local time, from the laptop. Every command is under
  "Commands as run".
- **Gateway:** agentgateway v1.7.0, `cr.agentgateway.dev/agentgateway:v1.7.0`, on gb10-2,
  configured from [`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml).
- **Rows:** as in the agentgateway task's finding
  ([`agentgateway.md`](agentgateway.md)): vLLM v0.33.0, each row serving its alias as its only
  model name, from spike-model-engines `host/` at `261879e`.
- **Sources:** agentgateway at the `v1.7.0` tag (`crates/agentgateway/src/`, `crates/llm/src/`, and
  `schema/config.json`), and the website's CEL reference, `reference/cel/latest/cel-context.html`.
- **Log lines:** each quoted access log line has the caller's address replaced with `<laptop>`. No
  key, key prefix, or key hash is quoted, and no tailnet address or name.

## The trial

Both forms run at once on gb10-2, from one config, for the length of the task:

| Form | Base URL | Port | Where the alias is chosen |
| --- | --- | --- | --- |
| route `ai` | `http://gb10-2:3000/<alias>/v1` | 3000 | the path: one route per alias |
| `llm` | `http://gb10-2:<port>/v1` | agent 3010, vision 3011, audio 3012, embedding 3013 | the port: one listener per alias |

**The `llm` form.** The `llm` section serves its models under one path prefix, on every gateway it
is attached to. Four aliases with one base URL each need four distinct prefixes, which `llm` can't
give, so the aliases are told apart by port instead: four gateways, `agent`, `vision`, `audio`,
and `embedding`, with `llm.gateways` naming all four and no `pathPrefix`.

- **Models.** One `llm.models` entry per alias, named as the alias, a `custom` provider at
  `params.baseUrl: http://<row host>:<row port>/v1`, with `formats` completions, messages,
  responses, and embeddings, and `passthrough: detect`.
- **One alias per port.** Each model has `authorization: {rules: [{require: proxy.listener.name ==
  "<alias>"}]}`. The model router lists, and routes to, only the models whose authorization passes
  for the request (`llm/model_router.rs`: `model_list_response` and `resolve_concrete_model` both
  filter by `model_authorized`). So a port's `/v1/models` lists its own alias, and a request naming
  another alias's model gets 403 `model_authorization_denied`.
- **Keys and paths.** `llm.policies.apiKey` lists the same keys as the consumer gateway, with the
  same `sha256:@@<name>@@` markers. The deploy reads each name once (`sort -u`), so a key is issued
  or revoked in both lists by one deploy. `llm.policies.authorization` requires `request.path` to be
  one of the eight serving paths. The `llm` route matches every path on its ports (`/` prefix;
  `types/local.rs`, `convert_llm_config`), and its policies run on every request in a fixed order,
  the key before the authorization (`proxy/httpproxy.rs`, `apply_request_policies`). So a missing
  key gets 401 on any path, and a keyed request for any other path gets 403.

**The serving paths**, on both forms: `/v1/models`, `/v1/chat/completions`, `/v1/completions`,
`/v1/messages`, `/v1/responses`, `/v1/embeddings`, `/v1/audio/transcriptions`, and
`/v1/audio/translations`. `/v1/models/<id>` is left out. No client here reads a single model, and
the rows don't serve it. Leaving it out of both forms keeps their allow-lists the same.

**The route form's allow-list.** Each alias route keeps its `pathPrefix: /<alias>/v1` and its
`urlRewrite` to `/v1`, and gains a conditional `directResponse`: status 404 when the rewritten path
is not a serving path. The URL rewrite runs before the direct response (`apply_request_policies`),
so the condition reads `/v1/...`, the same list as the `llm` form's. Any path outside
`/<alias>/v1` matches no route and gets 404, as before. The brief's exact path matches can't keep
the rewrite: a prefix rewrite needs a prefix match ("path prefix rewrite requires a PathPrefix
route match", `http/filters.rs`).

**The access log field.** `frontendPolicies.accessLog.add.retry_after` is now in the base config,
so every access log line carries the reply's `Retry-After` without an overlay. A reply without one
leaves the field out. The `access-log` overlay is retired. `in-flight-1` now inserts its
`http.maxConcurrentRequests` under `frontendPolicies:` with an `#@ after` directive, so it no
longer collides with the log field.

**The deploy.** [`deploy.env`](../../gateway/agentgateway/deploy.env) gains `AGW_ALIAS_PORTS`, the
alias-to-port map. [`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh)
publishes each of those ports on `$(tailscale ip -4)`, evaluated on gb10-2, the same way as 3000.
The new flags recreated the container once, at 07:54:44, with label `spike.spec=31931f6bd174`.
Every later deploy reloaded the config in place.

**The helpers.** [`scripts/clients-lib.sh`](../../scripts/clients-lib.sh) and
[`scripts/measure-lib.sh`](../../scripts/measure-lib.sh) read the alias-to-port map from
`deploy.env`, and take `GATEWAY_FORM`, `llm` (the default) or `route`, for the base URL.
`gw_base <alias>` prints the base URL. State and the command log are under `.state/routing/`;
keys stay in `.state/agentgateway/keys/`.

**The 429 probe on `llm`.** [`probes/rate-limit-agent-llm.yaml`](../../gateway/agentgateway/probes/rate-limit-agent-llm.yaml)
is a top-level policy targeting the `llm` route, `internal/llm:request`, with a conditional
`localRateLimit`: 2 requests, refilled every 10 s, when `proxy.listener.name == "agent"`.
`llm.policies.localRateLimit` takes no condition, so a limit set there would hold all four
aliases. The route's name is the one the access log prints (`route=internal/llm:request`), and
agentgateway's docs show it only in example log lines (`standalone/llm/arize.md`).

## Results · slice 1

### Interim verdict

| Behavior | Result | Evidence |
| --- | --- | --- |
| 1. Each port's `/v1/models` lists exactly its alias | pass | `["agent"]`, `["vision"]`, `["audio"]`, `["embedding"]` on 3010–3013 at 07:55:12. The route form lists the same at 07:54:48. |
| 2. The pass-through matrix on each port; another alias's model refused with 403 | pass (one row gap) | Every request answers on both forms, and on 3010 `model: vision` gets 403 `model_authorization_denied`. The audio row serves no `/v1/audio/transcriptions` (404 direct, route, and `llm` alike); the gateway forwarded it. |
| 4. Non-serving paths refused (403 `llm`, 404 route); missing or revoked key 401 everywhere | pass | 9 paths on 3010 get 403, 7 paths on 3000 get 404; no key gets 401 on all five ports; `bench` revoked gets 401 on all five ports and 200 once restored |
| 5. A rate limit on one alias alone: 429 with Retry-After there, the others answer | pass | 3010: 200, 200, then 429 `retry-after: 3` twice; 3011 200 throughout, and 3012, 3013, and route `agent` 200 |
| 6. The pinned image validates the config; documented fields only | pass | `Configuration is valid!` on every deploy. An undocumented field is refused: ``gateways.agent: unknown field `undocumentedField` ``. Every field is in `schema/config.json`, and `proxy.listener.name` is in the CEL reference. |
| 8. `retry_after` on every log line with no overlay; the 503 probe alone | pass | `retry_after="3"` on the `llm` 429s and `="7"` on the route 429. With `in-flight-1` alone, a second request on 3010 gets 503, with or without a key, while 3011 and 3000 answer 200. |

**Interim verdict: `llm` holds behaviors 1, 2, 4, 5, and 6, so the config stays on both forms**,
and slice 2 runs the tiers through `llm` (behavior 3). Nothing fell back. Three settings differ from
the brief's sketch, and each is needed for `llm` to route at all: the rule's CEL variable, audio's
formats, and the base URL's `/v1`, all below.

### Behavior 1: one alias per port

The first deploy, with each model's rule `proxy.gateway.name == "<alias>"`, listed nothing:
`{"object":"list","data":[]}` on all four ports (07:54:48). The access log shows why. Standalone
agentgateway makes each entry under `gateways` a listener of one gateway, `default`:

```text
2026-11-16T12:54:48.803136Z	info	request gateway=default/default listener=agent route=internal/llm:request src.addr=<laptop> http.method=GET http.host=gb10-2 http.path=/v1/models http.version=HTTP/1.1 http.status=200 protocol=llm reason=DirectResponse duration=0ms
```

So `proxy.gateway.name` is `default` on every port, and every model's rule failed. The CEL
reference documents `proxy.listener.name` beside it. With the rules on `proxy.listener.name`
(deployed 07:55:08), each port lists exactly its alias. `/v1/models` on the `llm` form is answered
by agentgateway itself from its model list (`reason=DirectResponse`, no `endpoint=`), not by the
row as on the route form.

### Behavior 2: the pass-through matrix

The agentgateway task's requests, on each form (`llm` from 07:55:28, route from 07:56:37):

| Request | `llm` | route `ai` |
| --- | --- | --- |
| agent chat | "Hello, great to see you!", 73 in, 82 out | "Hello there, nice to meet.", 73 in, 89 out |
| agent stream, `include_usage` | 47 `data:` events, usage in the last chunk | 48 events, usage in the last chunk |
| agent Messages | "Red.", `end_turn` | "Red.", `end_turn` |
| agent Responses | "Mars.", `completed` | "Mars.", `completed` |
| vision, the 1280×720 JPEG | "GATEWAY 7319", 300 tokens | "GATEWAY 7319", 300 tokens |
| audio chat, the 6 s clip | "And um this is what we're going to be doing over the next", 182 tokens | the same text, 182 tokens |
| embeddings, 2 inputs | 2 vectors of 768 | 2 vectors of 768 |
| `model: vision` at the agent's base URL | 403 "Model authorization denied" | 404 from the row: "The model `vision` does not exist" |
| multipart transcription on audio | 404 `{"detail":"Not Found"}` from the row | the same |

The audio chat sent direct to the row gave "And um this is just what we're going to be doing over
the next", one word apart, as any two samples are.

**Audio needed `formats`.** The brief's sketch gave the audio model no `formats`. Audio chat then
failed with 400 (07:55:41 and 07:55:49):

```text
failed to process LLM request: unsupported conversion: from Completions to provider custom (supported: [])
```

agentgateway classifies a request by its path before it looks at the model's `passthrough`.
`/v1/chat/completions`, `/v1/messages`, `/v1/responses`, and `/v1/embeddings` are their own route
types, and only paths it doesn't classify take `passthrough` (`llm/model_router.rs`:
`SERVING_ENDPOINTS`, and `resolve_concrete_model`'s `classify_route(...).unwrap_or(passthrough)`).
So audio's chat is a Completions request, which a custom provider must list in `formats`. With the
same four formats as the others (deployed 07:56:18), audio chat answers. The audio paths are
`detect` either way.

**Transcription is the row's gap, not the gateway's.** The audio row answers
`/v1/audio/transcriptions` with 404 `{"detail":"Not Found"}` when sent direct, so it serves no
transcription endpoint. Through `llm` the gateway still read the multipart `model` field and
forwarded the request to `framework:8001`. The row answered 404:

```text
2026-11-16T12:55:41.942525Z	info	request gateway=default/default listener=audio route=internal/llm:request endpoint=framework:8001 src.addr=<laptop> http.method=POST http.host=gb10-2 http.path=/v1/audio/transcriptions http.version=HTTP/1.1 http.status=404 protocol=llm gen_ai.operation.name=transcription gen_ai.provider.name=custom gen_ai.request.model=audio agw.ai.original_model=audio duration=7ms
```

The same multipart request naming `vision` on 3012 got 403 "Model authorization denied", so the
router reads a multipart model and holds it to the port. The architect decides whether behavior 2
needs a row that serves transcription.

**The base URL's `/v1`.** `params.baseUrl` is the upstream base path, and a format's path is
appended to it. The schema's own example: `https://api.openai.com/v1` sends completions to
`/v1/chat/completions`, `https://api.openai.com` to `/chat/completions`. `apply_base_url` sets the
path prefix to `/` for a bare host, which would send chat to the row's `/chat/completions`, a path
vLLM doesn't serve. Each base URL ends in `/v1`. A `detect` request keeps its own path
(`set_default_path` strips and re-adds `/v1` for a custom provider).

**What the `llm` form does differently.**

- **It parses each request in a listed format**, and re-serializes the reply: the chat reply's
  fields come back reordered, with the same content.
- **It adds usage to every stream.** For a streamed chat it sets `stream_options.include_usage`
  whether or not the client asked (`llm/mod.rs`, `process_completions_request`: "We always set
  it"). The same stream without `include_usage` carried one usage chunk through `llm`, none
  through the route form, and none direct (07:59:51). That is one extra final SSE event, and the
  gateway reads the stream's tokens from it.
- **It logs the usage it reads** on each line, as the route form does: `gen_ai.usage.input_tokens=73
  gen_ai.usage.output_tokens=82 gen_ai.usage.reasoning_tokens=65` for the agent chat.

### Behavior 4: paths and keys

With the architect's key (07:57:04):

- **On 3010, 403** "authorization failed" for `/v1/tokenize`, `/tokenize`, `/metrics`, `/health`,
  `/v1/models/agent`, `/v1/rerank`, `/v1/audio/speech`, `/v1/images/generations`, and `/docs`.
  Each is refused before any backend: `reason=Authorization`, no `endpoint=`.
- **On 3000, 404** for `/agent/v1/tokenize`, `/agent/v1/models/agent`, `/agent/v1/rerank`, and
  `/agent/v1/audio/speech`, from the route's direct response (`route=default/agent
  reason=DirectResponse`, no `endpoint=`). `/metrics`, `/agent/metrics`, and `/tokenize` match no
  route and also get 404.

Every serving path still answers on both forms: the matrix above ran after this config was
deployed.

**Without a key**, 401 on `:3000/agent/v1/models`, `:3000/metrics`, `/v1/models` on each of
3010–3013, and `:3010/tokenize`.

**Revocation.** The `bench` entry was deleted from both key lists and deployed at 07:57:23. The
config reloaded in place, and `bench` got 401 on all five ports while the architect's key still
got 200. The entries were restored and deployed at 07:57:27, and `bench` got 200 again on 3000,
3010, and 3013. A search of the container's whole log for each key, read from its key file
(`grep -cF -f`), found none of the three (07:59:07).

### Behavior 5: a rate limit on one alias

The `rate-limit-agent-llm` overlay was deployed at 07:57:36 and validated. Requests alternated
between 3010 and 3011 from 07:57:44:

```text
HTTP/1.1 200 OK x-ratelimit-limit: 2 x-ratelimit-remaining: 1 x-ratelimit-reset: 3
3011: 200
HTTP/1.1 200 OK x-ratelimit-limit: 2 x-ratelimit-remaining: 0 x-ratelimit-reset: 3
3011: 200
HTTP/1.1 429 Too Many Requests x-ratelimit-limit: 2 x-ratelimit-remaining: 0 x-ratelimit-reset: 3 retry-after: 3
3011: 200
HTTP/1.1 429 Too Many Requests x-ratelimit-limit: 2 x-ratelimit-remaining: 0 x-ratelimit-reset: 3 retry-after: 3
3011: 200
```

and then 3000's route `agent`, 3012, and 3013 answered 200. The limit holds the agent's port
alone. It is attached by the route's logged name, `internal/llm:request`, which the probe needs and
the committed config doesn't name. It shows the limit is possible without a separate route per
alias; priority settles how its limits are attached.

### Behavior 6: validation and documented fields

Every deploy's `--validate-only` run with the pinned image printed `Configuration is valid!`: the
trial config at 07:54:43, each change after it, and each overlay. Does the validation refuse a
field the schema doesn't document? A throwaway overlay, never committed, put `undocumentedField:
true` under the `agent` gateway (07:59:20). The run refused it, and the deploy sent nothing on:

```text
Error: gateways.agent: unknown field `undocumentedField` at line 78 column 5
```

The live config still read `# overlays: none`. Every field the config uses is defined in v1.7.0's
`schema/config.json`, CEL included: `request.path` and `proxy.listener.name` are in the CEL
reference. Two YAML anchors (`&formats`, `&not-serving`) share repeated blocks, and agentgateway
reads them as written. The `llm` route's name is in the docs only as log output.

### Behavior 8: Retry-After in the log, and the 503 probe

- **The 429s** on the `llm` form logged `retry_after="3"` with no access-log overlay deployed (live:
  `# overlays: rate-limit-agent-llm`):

  ```text
  2026-11-16T12:57:44.424772Z	error	request gateway=default/default listener=agent route=internal/llm:request src.addr=<laptop> http.method=GET http.host=gb10-2 http.path=/v1/models http.version=HTTP/1.1 http.status=429 protocol=http error="rate limit exceeded" reason=RateLimit duration=0ms retry_after="3"
  ```

  The route form's own probe, `rate-limit-agent`, gave `retry_after="7"` on its 429 (07:58:00).
  Lines for replies without a Retry-After leave the field out.
- **The 503 probe alone.** With `in-flight-1` deployed (07:58:06), the live config's
  `frontendPolicies` read `http: maxConcurrentRequests: 1` above the `accessLog` field. A streamed
  agent chat held 3010's one slot from 07:58:15. A second request on 3010 got `503 Service
  Unavailable`, with no Retry-After, and so did one without a key. 3011 and 3000 answered 200,
  since the limit counts per port. The stream ran to 1,200 tokens, `finish_reason: length`, 200.
  The deploy at 07:59:03 removed the overlay (`# overlays: none`), and every alias listed itself on
  both forms.

## Commands as run

Every command the log holds, as logged, with its time, from `.state/routing/commands-2026-11-16.log`,
in lines that start `+`. The output stays there, untracked. `gw_curl` logs curl's arguments joined
by spaces, so its JSON bodies show without their shell quotes. Each `mise run agentgateway-deploy`
line is followed by the deploy's own `+` lines, from its output, appended to the log by `tee -a`.
The `cp` that restored the config after the revocation is logged as `cp <the copy saved before the
edit>`, since the copy's path was in the session's scratch directory. Sourcing the helpers is
logged too, once per step.

### 2026-11-16 · the deploy, and the `/models` lists

The route form before the deploy, the trial's deploy (the container recreated for the new ports),
the empty lists, the access log read, and the redeploy with `proxy.listener.name`:

```text
+ 2026-11-16T07:54:39-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:54:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:54:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T07:54:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T07:54:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T07:54:39-05:00 gb10-2: head -1 ~/agentgateway/config.yaml; docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:54:43-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:54:43-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T07:54:43-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:54:43-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.6Vri2m.yaml
+ 2026-11-16T07:54:43-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:54:43-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:54:43-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:54:43-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:54:43-05:00 gb10-2: docker rm --force agentgateway
+ 2026-11-16T07:54:44-05:00 gb10-2: docker run --detach --name agentgateway --restart unless-stopped --user "$(id -u):$(id -g)" --publish "$(tailscale ip -4):3000:3000" --publish "$(tailscale ip -4):3010:3010" --publish "$(tailscale ip -4):3011:3011" --publish "$(tailscale ip -4):3012:3012" --publish "$(tailscale ip -4):3013:3013" --publish 127.0.0.1:3001:3001 --volume "$HOME/agentgateway:/config:ro" --add-host "gb10-1:$(tailscale ip -4 gb10-1)" --add-host "gb10-2:$(tailscale ip -4 gb10-2)" --add-host "framework:$(tailscale ip -4 framework)" --label spike.spec=31931f6bd174 cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml
+ 2026-11-16T07:54:44-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:54:48-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3010/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3011/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3012/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3013/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T07:54:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3010/v1/models
+ 2026-11-16T07:54:53-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:54:53-05:00 gb10-2: docker logs --since 2m agentgateway 2>&1 | grep -F 'http.path=/v1/models' | tail -2 | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/'
+ 2026-11-16T07:55:08-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:55:08-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T07:55:08-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:55:08-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.1LrMKD.yaml
+ 2026-11-16T07:55:08-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:55:08-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:55:09-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:55:09-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:55:09-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:55:12-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3010/v1/models
+ 2026-11-16T07:55:12-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3011/v1/models
+ 2026-11-16T07:55:12-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3012/v1/models
+ 2026-11-16T07:55:12-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3013/v1/models
```

### 2026-11-16 · the pass-through matrix

The request bodies built on the laptop, the `llm` form's matrix, the audio failure and the row's
transcription 404, the redeploy with audio's formats, then the route form's matrix, the audio chat
direct, the multipart request naming `vision`, and the access log read:

```text
+ 2026-11-16T07:55:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:55:22-05:00 laptop: cp .state/agentgateway/assets/{text.jpg,clip-6s.wav,clip-6s.b64} .state/routing/assets/ && jq -n --rawfile img <(base64 -w0 .state/routing/assets/text.jpg) '{model:"vision",max_tokens:100,messages:[{role:"user",content:[{type:"image_url",image_url:{url:("data:image/jpeg;base64,"+$img)}},{type:"text",text:"What text is in this image? Answer with the text only."}]}]}' > .state/routing/assets/vision.json && jq -n --rawfile wav .state/routing/assets/clip-6s.b64 '{model:"audio",max_tokens:256,messages:[{role:"user",content:[{type:"input_audio",input_audio:{data:$wav,format:"wav"}},{type:"text",text:"Transcribe this audio."}]}]}' > .state/routing/assets/audio.json
+ 2026-11-16T07:55:28-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:55:28-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T07:55:31-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"stream_options":{"include_usage":true},"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T07:55:33-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","max_tokens":300,"messages":[{"role":"user","content":"Name a primary color."}]} http://gb10-2:3010/v1/messages
+ 2026-11-16T07:55:34-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","max_output_tokens":300,"input":"Name a planet."} http://gb10-2:3010/v1/responses
+ 2026-11-16T07:55:41-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:55:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d @.state/routing/assets/vision.json http://gb10-2:3011/v1/chat/completions
+ 2026-11-16T07:55:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d @.state/routing/assets/audio.json http://gb10-2:3012/v1/chat/completions
+ 2026-11-16T07:55:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -F model=audio -F file=@.state/routing/assets/clip-6s.wav http://gb10-2:3012/v1/audio/transcriptions
+ 2026-11-16T07:55:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"embedding","input":["agentgateway passes requests through.","A second sentence."]} http://gb10-2:3013/v1/embeddings
+ 2026-11-16T07:55:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"hi"}],"max_tokens":5} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T07:55:49-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:55:49-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -H Content-Type: application/json -d @.state/routing/assets/audio.json http://gb10-2:3012/v1/chat/completions
+ 2026-11-16T07:55:49-05:00 laptop: curl -sS -w '\n%{http_code}\n' -F model=audio -F file=@.state/routing/assets/clip-6s.wav http://framework:8001/v1/audio/transcriptions
+ 2026-11-16T07:55:49-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -F model=audio -F file=@.state/routing/assets/clip-6s.wav http://gb10-2:3000/audio/v1/audio/transcriptions
+ 2026-11-16T07:56:18-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:56:18-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T07:56:18-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:56:18-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.X3VoLY.yaml
+ 2026-11-16T07:56:18-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:56:18-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:56:19-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:56:19-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:56:19-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:56:22-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -H Content-Type: application/json -d @.state/routing/assets/audio.json http://gb10-2:3012/v1/chat/completions
+ 2026-11-16T07:56:22-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3010/v1/models
+ 2026-11-16T07:56:22-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3011/v1/models
+ 2026-11-16T07:56:22-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3012/v1/models
+ 2026-11-16T07:56:22-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3013/v1/models
+ 2026-11-16T07:56:37-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:56:37-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T07:56:40-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"stream_options":{"include_usage":true},"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T07:56:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","max_tokens":300,"messages":[{"role":"user","content":"Name a primary color."}]} http://gb10-2:3000/agent/v1/messages
+ 2026-11-16T07:56:42-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","max_output_tokens":300,"input":"Name a planet."} http://gb10-2:3000/agent/v1/responses
+ 2026-11-16T07:56:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d @.state/routing/assets/vision.json http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-16T07:56:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d @.state/routing/assets/audio.json http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-16T07:56:45-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"embedding","input":["agentgateway passes requests through.","A second sentence."]} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-16T07:56:45-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"hi"}],"max_tokens":5} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T07:56:45-05:00 laptop: curl -sS -H 'Content-Type: application/json' -d @.state/routing/assets/audio.json http://framework:8001/v1/chat/completions | jq -c '{model, text: .choices[0].message.content}'
+ 2026-11-16T07:56:46-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d @.state/routing/assets/audio.json http://gb10-2:3012/v1/chat/completions
+ 2026-11-16T07:56:46-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -F model=vision -F file=@.state/routing/assets/clip-6s.wav http://gb10-2:3012/v1/audio/transcriptions
+ 2026-11-16T07:56:51-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:56:51-05:00 gb10-2: docker logs --since 2026-11-16T12:55:25Z --until 2026-11-16T12:56:50Z agentgateway 2>&1 | grep -F 'route=internal/llm:request' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/'
```

### 2026-11-16 · paths, keys, and revocation

```text
+ 2026-11-16T07:57:04-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /v1/tokenize\n http://gb10-2:3010/v1/tokenize
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /tokenize\n http://gb10-2:3010/tokenize
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /metrics\n http://gb10-2:3010/metrics
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /health\n http://gb10-2:3010/health
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /v1/models/agent\n http://gb10-2:3010/v1/models/agent
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /v1/rerank\n http://gb10-2:3010/v1/rerank
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /v1/audio/speech\n http://gb10-2:3010/v1/audio/speech
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /v1/images/generations\n http://gb10-2:3010/v1/images/generations
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3010 /docs\n http://gb10-2:3010/docs
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3000 /agent/v1/tokenize\n http://gb10-2:3000/agent/v1/tokenize
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3000 /agent/v1/models/agent\n http://gb10-2:3000/agent/v1/models/agent
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3000 /agent/v1/rerank\n http://gb10-2:3000/agent/v1/rerank
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3000 /agent/v1/audio/speech\n http://gb10-2:3000/agent/v1/audio/speech
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3000 /metrics\n http://gb10-2:3000/metrics
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3000 /agent/metrics\n http://gb10-2:3000/agent/metrics
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} 3000 /tokenize\n http://gb10-2:3000/tokenize
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n http://gb10-2:3010/v1/tokenize
+ 2026-11-16T07:57:04-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n http://gb10-2:3000/agent/v1/tokenize
+ 2026-11-16T07:57:04-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} no key http://gb10-2:3000/agent/v1/models\n' http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:57:04-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} no key http://gb10-2:3000/metrics\n' http://gb10-2:3000/metrics
+ 2026-11-16T07:57:04-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} no key http://gb10-2:3010/v1/models\n' http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:04-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} no key http://gb10-2:3011/v1/models\n' http://gb10-2:3011/v1/models
+ 2026-11-16T07:57:04-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} no key http://gb10-2:3012/v1/models\n' http://gb10-2:3012/v1/models
+ 2026-11-16T07:57:04-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} no key http://gb10-2:3013/v1/models\n' http://gb10-2:3013/v1/models
+ 2026-11-16T07:57:04-05:00 laptop: curl -sS -o /dev/null -w '%{http_code} no key http://gb10-2:3010/tokenize\n' http://gb10-2:3010/tokenize
+ 2026-11-16T07:57:11-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:11-05:00 gb10-2: docker logs --since 3m agentgateway 2>&1 | grep -E 'http.path=/(agent/v1/tokenize|v1/tokenize) ' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/' | tail -2
+ 2026-11-16T07:57:11-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench before http://gb10-2:3000/agent/v1/models\n http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:57:11-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench before http://gb10-2:3010/v1/models\n http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:11-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench before http://gb10-2:3011/v1/models\n http://gb10-2:3011/v1/models
+ 2026-11-16T07:57:11-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench before http://gb10-2:3012/v1/models\n http://gb10-2:3012/v1/models
+ 2026-11-16T07:57:12-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench before http://gb10-2:3013/v1/models\n http://gb10-2:3013/v1/models
+ 2026-11-16T07:57:16-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:16-05:00 laptop: sed -i '/- keyHash: sha256:@@bench@@/,+2d' gateway/agentgateway/config.yaml
+ 2026-11-16T07:57:23-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:23-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T07:57:23-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:57:23-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.6xGFnU.yaml
+ 2026-11-16T07:57:23-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:57:23-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:57:24-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:57:24-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:57:24-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:57:27-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench revoked http://gb10-2:3000/agent/v1/models\n http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:57:27-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench revoked http://gb10-2:3010/v1/models\n http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:27-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench revoked http://gb10-2:3011/v1/models\n http://gb10-2:3011/v1/models
+ 2026-11-16T07:57:27-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench revoked http://gb10-2:3012/v1/models\n http://gb10-2:3012/v1/models
+ 2026-11-16T07:57:27-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench revoked http://gb10-2:3013/v1/models\n http://gb10-2:3013/v1/models
+ 2026-11-16T07:57:27-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code} architect still admitted 3010\n http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:27-05:00 laptop: cp <the copy saved before the edit> gateway/agentgateway/config.yaml
+ 2026-11-16T07:57:27-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T07:57:27-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:57:27-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.sDEjKG.yaml
+ 2026-11-16T07:57:27-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:57:27-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:57:27-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:57:28-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:57:28-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:57:31-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench restored http://gb10-2:3000/agent/v1/models\n http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:57:31-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench restored http://gb10-2:3010/v1/models\n http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:31-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/bench)" | curl -K - -sS -o /dev/null -w %{http_code} bench restored http://gb10-2:3013/v1/models\n http://gb10-2:3013/v1/models
```

### 2026-11-16 · the probes

`rate-limit-agent-llm`, its log read, the route form's `rate-limit-agent`, then `in-flight-1` and
its held stream (the stream is the `gw_curl` at 07:58:15):

```text
+ 2026-11-16T07:57:36-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:36-05:00 laptop: mise run agentgateway-deploy rate-limit-agent-llm
+ 2026-11-16T07:57:36-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:57:36-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.FUr5vw.yaml
+ 2026-11-16T07:57:36-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:57:37-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:57:37-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:57:37-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:57:37-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:57:44-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3011: %{http_code}\n http://gb10-2:3011/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3011: %{http_code}\n http://gb10-2:3011/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3011: %{http_code}\n http://gb10-2:3011/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3010/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3011: %{http_code}\n http://gb10-2:3011/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3000 route agent: %{http_code}\n http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3012: %{http_code}\n http://gb10-2:3012/v1/models
+ 2026-11-16T07:57:44-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3013: %{http_code}\n http://gb10-2:3013/v1/models
+ 2026-11-16T07:57:49-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:49-05:00 gb10-2: docker logs --since 2026-11-16T12:57:43Z --until 2026-11-16T12:57:47Z agentgateway 2>&1 | grep -F 'http.path=/v1/models' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/'
+ 2026-11-16T07:57:49-05:00 gb10-2: head -1 ~/agentgateway/config.yaml
+ 2026-11-16T07:57:56-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:57:56-05:00 laptop: mise run agentgateway-deploy rate-limit-agent
+ 2026-11-16T07:57:56-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:57:56-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.L4C8af.yaml
+ 2026-11-16T07:57:56-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:57:56-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:57:57-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:57:57-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:57:57-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:58:00-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:58:00-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:58:00-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:58:00-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w route vision: %{http_code}\n http://gb10-2:3000/vision/v1/models
+ 2026-11-16T07:58:01-05:00 gb10-2: docker logs --since 10s agentgateway 2>&1 | grep -F 'http.status=429' | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/'
+ 2026-11-16T07:58:06-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:58:06-05:00 laptop: mise run agentgateway-deploy in-flight-1
+ 2026-11-16T07:58:06-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:58:06-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.2bLArw.yaml
+ 2026-11-16T07:58:06-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:58:06-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:58:07-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:58:07-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:58:07-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:58:07-05:00 gb10-2: sed -n '1p;/^frontendPolicies:/,/^gateways:/p' ~/agentgateway/config.yaml
+ 2026-11-16T07:58:15-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:58:15-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -o .state/routing/assets/inflight-stream.txt -w stream: %{http_code}\n -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Write a 300-word story about a lighthouse."}],"max_tokens":1200} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T07:58:17-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -D - http://gb10-2:3010/v1/models
+ 2026-11-16T07:58:17-05:00 laptop: curl -sS -o /dev/null -w '3010 no key: %{http_code}\n' http://gb10-2:3010/v1/models
+ 2026-11-16T07:58:17-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3011 with key: %{http_code}\n http://gb10-2:3011/v1/models
+ 2026-11-16T07:58:17-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3000 with key: %{http_code}\n http://gb10-2:3000/agent/v1/models
```

### 2026-11-16 · after the probes

The overlays removed, both forms' lists, the key search, the undocumented field refused, the stale
copy removed, and the stream usage comparison:

```text
+ 2026-11-16T07:59:03-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:59:03-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T07:59:03-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:59:03-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.FFnUBP.yaml
+ 2026-11-16T07:59:03-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:59:03-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:59:04-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T07:59:04-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T07:59:04-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T07:59:07-05:00 gb10-2: head -1 ~/agentgateway/config.yaml
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3010/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/agent/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3011/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/vision/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3012/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/audio/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3013/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3000/embedding/v1/models
+ 2026-11-16T07:59:07-05:00 laptop: ssh gb10-2 'docker logs agentgateway 2>&1' | grep -cF -f .state/agentgateway/keys/architect
+ 2026-11-16T07:59:07-05:00 laptop: ssh gb10-2 'docker logs agentgateway 2>&1' | grep -cF -f .state/agentgateway/keys/bench
+ 2026-11-16T07:59:07-05:00 laptop: ssh gb10-2 'docker logs agentgateway 2>&1' | grep -cF -f .state/agentgateway/keys/go-ai
+ 2026-11-16T07:59:20-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:59:20-05:00 laptop: mise run agentgateway-deploy zz-undocumented (a throwaway overlay, never committed: '    undocumentedField: true' after '  agent:')
+ 2026-11-16T07:59:20-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T07:59:20-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.3zyoxx.yaml
+ 2026-11-16T07:59:20-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T07:59:20-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T07:59:21-05:00 gb10-2: head -1 ~/agentgateway/config.yaml; ls ~/agentgateway
+ 2026-11-16T07:59:26-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:59:26-05:00 gb10-2: rm ~/agentgateway/config.yaml.next
+ 2026-11-16T07:59:48-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T07:59:48-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 3."}],"max_tokens":120} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T07:59:50-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 3."}],"max_tokens":120} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-16T07:59:51-05:00 laptop: curl -sS -N -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 3."}],"max_tokens":120}' http://gb10-1:8000/v1/chat/completions | grep -c '"usage":{'
```
