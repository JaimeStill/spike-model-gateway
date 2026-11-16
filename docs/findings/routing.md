# routing

Whether agentgateway's `llm` section can serve the four aliases the way the inline route `ai`
backends do, which agentgateway's UI labels "legacy". The task trials `llm` live beside route `ai`,
keeps it only if behaviors 1–6 of the task brief all hold, and otherwise returns to route `ai`
(evidence 1 and 8 of [`context/README.md`](../../context/README.md#the-evidence)). This finding
holds slice 1, the trial; slice 2, the tiers, the final verdict, and the overhead cells; slice 3,
the settled form, the base-URL choice, and the watch register; and the walkthrough the architect
runs as slice 4.

- **Measured:** 2026-11-16, 07:54–07:59 local time, from the laptop, and the transcription
  verification at 09:06–09:08; slice 2 at 09:13–09:30, on Tailscale's relay ("The network
  path"); slice 3 at 09:37–09:41. Every command is under "Commands as run".
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
`deploy.env`, and take `GATEWAY_FORM`, `llm` (the default) or `route`, for the base URL (removed
in slice 3, with the route form).
`gw_base <alias>` prints the base URL. State and the command log are under `.state/routing/`;
keys stay in `.state/agentgateway/keys/`.

**The 429 probe on `llm`.** `probes/rate-limit-agent-llm.yaml`, renamed
[`probes/rate-limit-agent.yaml`](../../gateway/agentgateway/probes/rate-limit-agent.yaml) in slice
3, is a top-level policy targeting the `llm` route, `internal/llm:request`, with a conditional
`localRateLimit`: 2 requests, refilled every 10 s, when `proxy.listener.name == "agent"`.
`llm.policies.localRateLimit` takes no condition, so a limit set there would hold all four
aliases. The route's name is the one the access log prints (`route=internal/llm:request`), and
agentgateway's docs show it only in example log lines (`standalone/llm/arize.md`).

## Results · slice 1

### Interim verdict

| Behavior | Result | Evidence |
| --- | --- | --- |
| 1. Each port's `/v1/models` lists exactly its alias | pass | `["agent"]`, `["vision"]`, `["audio"]`, `["embedding"]` on 3010–3013 at 07:55:12. The route form lists the same at 07:54:48. |
| 2. The pass-through matrix on each port; another alias's model refused with 403 | pass; transcription by the gateway's handling only | Every request answers on both forms, and on 3010 `model: vision` gets 403 `model_authorization_denied`. Transcription: the gateway delivers the multipart request to the audio row whole on both forms (192,398 bytes in, 192,398 at the row) and refuses `model: vision` on 3012 with 403, but no row serves transcription at vLLM v0.33.0: Gemma 4 doesn't implement it ("Transcription, verified"). |
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
router reads a multipart model and holds it to the port. The architect counts behavior 2's
transcription line as met by the gateway's handling only (2026-11-16), and asked for it verified:
"Transcription, verified", below.

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

### Transcription, verified

Behavior 2's transcription line is met by the gateway's handling only (architect, 2026-11-16):
the gateway delivers the request to the right row, and no row serves transcription at vLLM
v0.33.0. Three facts, checked at 09:06–09:08, with no host changed and no row restarted.

**1. The audio row registers no transcription route.** Its own route list,
`GET framework:8001/openapi.json` (09:06:48), has 23 paths and no `/v1/audio/*`: the `/v1` ones are
`chat/completions`, `chat/completions/batch`, `completions`, `decisions`, `messages`,
`messages/count_tokens`, `models`, `responses` (with its `{response_id}` and `cancel`), and
`systemone`. `/v1/models` lists `audio`, root `google/gemma-4-E4B-it`, and `/version` is `0.33.0`.
The row's start log says so too (container `vllm-audio`, 11-13):

```text
(APIServer pid=1) INFO 11-13 16:26:41 [model.py:744] Resolved architecture: Gemma4ForConditionalGeneration
(APIServer pid=1) INFO 11-13 16:27:37 [entry.py:135] Supported tasks: ['generate']
```

**2. Why: Gemma 4 doesn't implement transcription at v0.33.0.** vLLM registers the transcription
and translation routers only for a model whose supported tasks include `transcription`, and a
model has that task only when its class implements `SupportsTranscription`. Read at the `v0.33.0`
tag, commit `4ba787ec99`, the commit the row's image is built from (spike-model-engines
`host/vllm.env`, and `host/vllm-rocm-audio/Dockerfile`, which builds on
`vllm/vllm-openai-rocm:v0.33.0`):

- `vllm/entrypoints/launchers/api_server/routers.py`: `if "transcription" in supported_tasks or
  "realtime" in supported_tasks:` calls `register_speech_to_text_api_routers`.
- `vllm/entrypoints/speech_to_text/factories.py`: that function includes the transcription and
  translation routers only `if "transcription" in supported_tasks`.
- `vllm/v1/worker/gpu/model_states/interface.py`, `get_supported_generation_tasks`: appends
  `transcription` only `if supports_transcription(self.model)`, which is
  `getattr(model, "supports_transcription", False)`, the class attribute the
  `SupportsTranscription` protocol sets (`vllm/model_executor/models/interfaces.py`).
- `vllm/model_executor/models/gemma4_mm.py`: `Gemma4ForConditionalGeneration`, the architecture
  the row resolves (`registry.py`), implements `SupportsMultiModal`, `SupportsQuant`,
  `SupportsPP`, `SupportsLoRA`, `SupportsEagle3`, and `SupportsEncoderCudaGraph`, not
  `SupportsTranscription`, and the file never names transcription.
- `vllm/model_executor/models/gemma3n_mm.py`: the older family's
  `Gemma3nForConditionalGeneration` does implement `SupportsTranscription`. A Gemma 3n row would
  register the route; Gemma 4 E4B can't.

No server flag adds the task: it comes from the model class alone. No release follows v0.33.0
yet, and `gemma4_mm.py` on vLLM's main branch (`a4910b4128`, 2026-11-16) still doesn't implement
`SupportsTranscription`.

**3. The gateway delivers the multipart request whole.** The same multipart request (`model`, and
the 192,078-byte 6 s WAV as `file`) was sent direct, through route `ai`, through `llm`, and naming
`vision` on 3012 (09:08:18–09:08:20). The row's `/metrics` counts each request whose path matches
no route under `handler="none"`, with its `Content-Length` (prometheus-fastapi-instrumentator's
default metrics, which `vllm/entrypoints/serve/instrumentator/metrics.py` installs), read before and
after each request:

| Request | Reply | Laptop sent (`size_upload`) | At the row: requests, `Content-Length` |
| --- | --- | --- | --- |
| direct, `framework:8001` | 404 `{"detail":"Not Found"}` | 130,854 | +1, 192,398 |
| route `ai`, `:3000/audio/v1/...` | 404 `{"detail":"Not Found"}` | 192,398 | +1, 192,398 |
| `llm`, `:3012/v1/...` | 404 `{"detail":"Not Found"}` | 192,398 | +1, 192,398 |
| `llm`, `:3012`, `model=vision` | 403 `model_authorization_denied` | 192,399 | +0 |

The request is 192,398 bytes on both forms, sent whole by the laptop and arriving at the row with
the same length. Direct, the row answers 404 before it reads the body, so curl stops uploading
after 130,854 bytes; the gateway reads the whole body to find the multipart `model`, so the laptop
sends all of it. The `vision` request is one byte longer for its model name, is refused by the
gateway, and never reaches the row. The row's counter stood at 3 requests and 577,194 bytes before,
three times 192,398: slice 1's three forwarded transcriptions arrived the same way. The row never
reads a body on an unregistered path, so the evidence is the length the row received, not its
bytes.

The gateway's lines for the three gateway requests (09:08:29), both forms forwarding to the row as
a `transcription` for `audio`, and the `vision` request answered by the gateway itself:

```text
2026-11-16T14:08:19.608242Z	info	request gateway=default/default listener=consumer route=default/audio endpoint=framework:8001 src.addr=<laptop> http.method=POST http.host=gb10-2 http.path=/audio/v1/audio/transcriptions http.version=HTTP/1.1 http.status=404 protocol=llm gen_ai.operation.name=transcription gen_ai.provider.name=custom gen_ai.request.model=audio duration=611ms
2026-11-16T14:08:20.296515Z	info	request gateway=default/default listener=audio route=internal/llm:request endpoint=framework:8001 src.addr=<laptop> http.method=POST http.host=gb10-2 http.path=/v1/audio/transcriptions http.version=HTTP/1.1 http.status=404 protocol=llm gen_ai.operation.name=transcription gen_ai.provider.name=custom gen_ai.request.model=audio agw.ai.original_model=audio duration=304ms
2026-11-16T14:08:20.962891Z	info	request gateway=default/default listener=audio route=internal/llm:request src.addr=<laptop> http.method=POST http.host=gb10-2 http.path=/v1/audio/transcriptions http.version=HTTP/1.1 http.status=403 protocol=llm agw.ai.original_model=vision reason=DirectResponse duration=275ms
```

and the row's own log over the same window, three POSTs, the caller's address replaced with
`<client>`:

```text
INFO:     <client> - "POST /v1/audio/transcriptions HTTP/1.1" 404 Not Found
INFO:     <client> - "POST /v1/audio/transcriptions HTTP/1.1" 404 Not Found
INFO:     <client> - "POST /v1/audio/transcriptions HTTP/1.1" 404 Not Found
```

The access log carries no request size, and no probe overlay adds one, so the size is the row's.

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

## Results · slice 2

### Final verdict

| Behavior | Result | Evidence |
| --- | --- | --- |
| 1, 2, 4, 5, 6 | pass | slice 1, above |
| 3. go-ai's and infer's tiers pass with only base URLs and keys changed; infer with no model sends to the one listed | pass | go-ai 20 passed, 0 failed, 1 skipped; infer 13 passed, 0 failed, 1 skipped; the one skip in each is the transcription route, which no row serves. `infer models` lists exactly its alias on each port, and a modelless `chat` or `embed` answers on each. |
| 7. `llm` stays only if 1–6 all hold | **`llm` stays** | behaviors 1–6 all hold |
| 9. O-embed and O-vision, direct, route `ai`, `llm`, direct | run; one figure flagged | every run exited 0 with no errored request; the `llm` − route `ai` difference is within the direct runs' spread on every figure but two: embedding's p95, beyond in `llm`'s favour, and vision's request latency median, +2.45 ms against a 1.78 ms spread, flagged below |

**Behaviors 1–6 all hold, so the `llm` section stays**, served beside route `ai` as in the trial.
Slice 3 settles the form. Nothing fell back, and no tier ran on route `ai`.

Architect's call on the flagged figure (2026-11-16): accepted. 2.45 ms on a 4.7 s request is
noise-sized, beside a TTFT difference inside its spread and no ITL change, and on the relay a
1.78 ms spread is tighter than the path's own jitter. The `llm` section stays.

### Behavior 3: the tiers and the infer CLI

go-ai's tier and infer's tier ran from a detached worktree of go-ai at `tools/infer/v0.1.0`
(09:13:42), with all four roles on the `llm` form's base URLs, `http://gb10-2:3010/v1` to
`http://gb10-2:3013/v1`, and the `go-ai` key. Nothing else changed from the agentgateway task's
runs. The helpers' summaries:

```text
= 2026-11-16T09:14:52-05:00 goai_tier: goai-llm: exit 0
= 2026-11-16T09:14:52-05:00 goai_tier: goai-llm: the key is not in .state/routing/clients/goai-llm.log
= 2026-11-16T09:14:52-05:00 goai_tier: goai-llm: 20 passed, 0 failed, 1 skipped (top-level tests)
= 2026-11-16T09:15:28-05:00 infer_tier: infer-llm: exit 0
= 2026-11-16T09:15:28-05:00 infer_tier: infer-llm: the key is not in .state/routing/clients/infer-llm.log
= 2026-11-16T09:15:28-05:00 infer_tier: infer-llm: 13 passed, 0 failed, 1 skipped (top-level tests)
```

The one skip in each is `TestTranscribeRoute`, for want of a transcription endpoint to point it at.
go-ai's, as logged (infer's reads the same, from `media_test.go:56`):

```text
    transcribe_test.go:53: AI_TRANSCRIPTION_BASE_URL is unset: set it to the endpoint's API root, such as http://localhost:8000/v1
--- SKIP: TestTranscribeRoute (0.00s)
```

`AI_TRANSCRIPTION_BASE_URL` is left unset because no row serves transcription at vLLM v0.33.0
("Transcription, verified", above). The same subtest of `TestModels` skips for the same reason.
`TestTranscribeChat`, audio through chat on 3012, passes in both tiers. A search of each tier's log
for each of the three keys, read from its key file, finds none.

**The released infer, with no `--model`.** `infer` v0.1.0, installed from its tag with `go
install`, ran against each port with only `INFER_BASE_URL` and `INFER_TOKEN` set (09:15:35–09:15:37):

- `infer models` listed exactly the port's alias on each of 3010–3013: `agent`, `vision`,
  `audio`, `embedding`.
- `infer chat` answered on agent, vision, and audio, each sent to the one model its port lists.
- `infer embed "gateway routing"` on embedding returned one vector of 768 values.

Those four steps' output was read live and is not kept on disk; the commands are under "Commands as
run".

### The network path

**Every slice-2 request crossed Tailscale's DERP relay.** On this network the laptop had no direct
path to either host. The stack record at 09:15:51 (`.state/routing/stack-2026-11-16.txt`):

```text
direct connection not established
pong from gb10-2 (<addr>) via DERP(nyc) in 55ms
direct connection not established
pong from framework (<addr>) via DERP(nyc) in 53ms
```

Ten pings each at 09:16:03 went the same way, through DERP(nyc): 54–55 ms to gb10-2 and 60–81 ms
to the Framework. `tailscale netcheck` reported `MappingVariesByDestIP: true`, a hard NAT, so no
direct path could be made from this network. The agentgateway task's cells ran on a direct path,
at 1 ms or under ([agentgateway.md](agentgateway.md): "Every `tailscale ping` from the laptop is
direct, at 1 ms or less, before and after").

**The architect's decision** (2026-11-16, an escalation answered during BUILD): run the cells now,
on the relay. "We have to be okay with the idea that we're not always going to be on the direct
network path."

**What the relay does to the reading.** Each form's runs cross a different set of legs:

| Cell | Direct runs | Gateway runs, both forms |
| --- | --- | --- |
| embedding | laptop → Framework, on the relay | laptop → gb10-2, on the relay, then gb10-2 → Framework |
| vision | laptop → gb10-2, on the relay | laptop → gb10-2, on the relay; the row is on gb10-2 itself |

- **Embedding: gateway against direct is not the gateway's overhead.** The direct runs cross the
  laptop's relay leg to the Framework; the gateway runs cross its relay leg to gb10-2 and then
  gb10-2's own leg to the Framework, whose path this session did not record. The two relay legs
  differ by several ms and jitter independently, so `compare`'s gateway-against-direct figures
  for embedding measure the paths as much as the gateway.
- **Route `ai` against `llm` is the comparable figure.** Both forms run in one container on gb10-2
  and reach the same row over the same legs. Their difference is the reading for behavior 9, set
  beside the direct runs' spread as the measure of run-to-run noise.
- **Vision: all four runs share the laptop's one relay leg to gb10-2.** The gateway's extra hop is
  inside gb10-2, from the container to the row on the same host.

The relay sets the scale too: an embedding request took about 78 ms here, against about 10 ms on
the agentgateway task's direct path.

**The host stack** at 09:15:51, from the same record: gb10-2 on kernel `7.0.0-1025-nvidia`, running
`agentgateway` (`cr.agentgateway.dev/agentgateway:v1.7.0`) and `vllm-vision`
(`vllm/vllm-openai:v0.33.0`); the Framework on kernel `7.2.15-1-omarchy`, running `vllm-embed`
(`vllm/vllm-openai-rocm:v0.33.0`) and `vllm-audio`
(`spike-model-engines/vllm-openai-rocm-audio:v0.33.0`). Both benchmarked rows answered `/version`
with `0.33.0`.

### Behavior 9: the overhead cells

Run on 2026-11-16: O-embed from 09:17:30 to 09:22:49, then O-vision from 09:22:56 to 09:29:57, each
cell's four runs back to back in the order direct-1, route `ai`, `llm`, direct-2.
[`overhead-embed.yaml`](../../bench/overhead-embed.yaml) holds a constant 34 requests a second of
512 prompt tokens for 60 s; [`overhead-vision.yaml`](../../bench/overhead-vision.yaml) holds 4
concurrent streams of a 1440p JPEG, 200 prompt and 100 output tokens, for 90 s. Each seed comes
from the run's name. All eight runs exited 0, under the 10-minute cap, with no errored request,
and the bench key was in none of the four gateway runs' files. The figures are `summarize`'s, read
again from each run's `result.json` after the session, and match the log.

**O-embed.** Latency in ms; the gateway's CPU in docker's figure, 100% being one of gb10-2's cores,
from the samples inside the benchmark:

| Run | Base URL | Requests ok / errored / incomplete | Latency median | Latency p95 | Gateway CPU % median / max | Gateway memory MiB median / max |
| --- | --- | --- | --- | --- | --- | --- |
| `r-embed-direct-1` | `http://framework:8002/v1` | 2,039 / 0 / 2 | 77.69 | 89.05 | | |
| `r-embed-route` | `http://gb10-2:3000/embedding/v1` | 2,038 / 0 / 2 | 73.95 | 153.92 | 2.86 / 3.47 (9 samples) | 30.8 / 33.6 |
| `r-embed-llm` | `http://gb10-2:3013/v1` | 2,039 / 0 / 2 | 77.70 | 108.32 | 2.73 / 3.42 (9 samples) | 31.6 / 32.3 |
| `r-embed-direct-2` | `http://framework:8002/v1` | 2,039 / 0 / 2 | 83.12 | 118.56 | | |

**O-vision.** TTFT, ITL, and latency in ms:

| Run | Base URL | Requests ok / errored / incomplete | TTFT median / p95 | ITL median / p95 | Latency median / p95 | Gateway CPU % median / max | Gateway memory MiB median / max |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `r-vision-direct-1` | `http://gb10-2:8000/v1` | 72 / 0 / 4 | 1,411.91 / 1,628.77 | 33.43 / 35.09 | 4,717.01 / 5,102.50 | | |
| `r-vision-route` | `http://gb10-2:3000/vision/v1` | 72 / 0 / 4 | 1,370.89 / 1,426.46 | 33.77 / 35.21 | 4,719.01 / 4,778.92 | 1.96 / 2.38 (14 samples) | 30.3 / 31.8 |
| `r-vision-llm` | `http://gb10-2:3011/v1` | 72 / 0 / 4 | 1,379.32 / 1,559.32 | 33.61 / 35.35 | 4,721.46 / 4,833.84 | 1.52 / 2.59 (14 samples) | 32.4 / 34.7 |
| `r-vision-direct-2` | `http://gb10-2:8000/v1` | 72 / 0 / 4 | 1,370.33 / 1,426.39 | 33.73 / 35.26 | 4,715.23 / 4,758.03 | | |

The incomplete requests are those running when each benchmark's time ended: 2 an embedding run, 4
a vision run, one per stream. No gateway sample failed. At its most the gateway used under 3.5% of
one core and under 35 MiB, on either form.

**`compare`, each gateway run against the direct pair** (09:30:00–09:30:01). "Adds" is
`gateway − (direct-1 + direct-2) / 2`, and "spread" is `|direct-1 − direct-2|`:

```text
+ 2026-11-16T09:30:00-05:00 laptop: compare r-embed-direct-1 r-embed-route r-embed-direct-2
= 2026-11-16T09:30:00-05:00 compare: request_latency median ms: direct 77.69, 83.12, spread 5.43; gateway 73.95, adds -6.45, beyond the spread
= 2026-11-16T09:30:00-05:00 compare: request_latency p95 ms: direct 89.05, 118.56, spread 29.51; gateway 153.92, adds 50.12, beyond the spread
+ 2026-11-16T09:30:00-05:00 laptop: compare r-embed-direct-1 r-embed-llm r-embed-direct-2
= 2026-11-16T09:30:00-05:00 compare: request_latency median ms: direct 77.69, 83.12, spread 5.43; gateway 77.7, adds -2.7, within the spread
= 2026-11-16T09:30:00-05:00 compare: request_latency p95 ms: direct 89.05, 118.56, spread 29.51; gateway 108.32, adds 4.51, within the spread
+ 2026-11-16T09:30:01-05:00 laptop: compare r-vision-direct-1 r-vision-route r-vision-direct-2
= 2026-11-16T09:30:01-05:00 compare: time_to_first_token median ms: direct 1411.91, 1370.33, spread 41.58; gateway 1370.89, adds -20.23, within the spread
= 2026-11-16T09:30:01-05:00 compare: time_to_first_token p95 ms: direct 1628.77, 1426.39, spread 202.37; gateway 1426.46, adds -101.12, within the spread
= 2026-11-16T09:30:01-05:00 compare: inter_token_latency median ms: direct 33.43, 33.73, spread 0.3; gateway 33.77, adds 0.19, within the spread
= 2026-11-16T09:30:01-05:00 compare: inter_token_latency p95 ms: direct 35.09, 35.26, spread 0.18; gateway 35.21, adds 0.04, within the spread
= 2026-11-16T09:30:01-05:00 compare: request_latency median ms: direct 4717.01, 4715.23, spread 1.78; gateway 4719.01, adds 2.89, beyond the spread
= 2026-11-16T09:30:01-05:00 compare: request_latency p95 ms: direct 5102.5, 4758.03, spread 344.46; gateway 4778.92, adds -151.35, within the spread
+ 2026-11-16T09:30:01-05:00 laptop: compare r-vision-direct-1 r-vision-llm r-vision-direct-2
= 2026-11-16T09:30:01-05:00 compare: time_to_first_token median ms: direct 1411.91, 1370.33, spread 41.58; gateway 1379.32, adds -11.79, within the spread
= 2026-11-16T09:30:01-05:00 compare: time_to_first_token p95 ms: direct 1628.77, 1426.39, spread 202.37; gateway 1559.32, adds 31.75, within the spread
= 2026-11-16T09:30:01-05:00 compare: inter_token_latency median ms: direct 33.43, 33.73, spread 0.3; gateway 33.61, adds 0.03, within the spread
= 2026-11-16T09:30:01-05:00 compare: inter_token_latency p95 ms: direct 35.09, 35.26, spread 0.18; gateway 35.35, adds 0.18, within the spread
= 2026-11-16T09:30:01-05:00 compare: request_latency median ms: direct 4717.01, 4715.23, spread 1.78; gateway 4721.46, adds 5.34, beyond the spread
= 2026-11-16T09:30:01-05:00 compare: request_latency p95 ms: direct 5102.5, 4758.03, spread 344.46; gateway 4833.84, adds -96.42, within the spread
```

For embedding these are path readings, not the gateway's cost, as above. For vision both forms'
request latency median reads "beyond" a spread of 1.78 ms, route `ai` by 2.89 ms and `llm` by
5.34 ms.

**`llm` against route `ai`, the behavior-9 reading.** "`llm` − route" is `llm`'s figure minus route
`ai`'s, in ms; a positive difference is `llm` slower. "Spread" is the direct runs' spread, as above:

| Cell | Figure | Route `ai` | `llm` | `llm` − route | Spread | Reading |
| --- | --- | --- | --- | --- | --- | --- |
| embedding | latency median | 73.95 | 77.70 | +3.75 | 5.43 | within |
| embedding | latency p95 | 153.92 | 108.32 | −45.60 | 29.51 | beyond, in `llm`'s favour |
| vision | TTFT median | 1,370.89 | 1,379.32 | +8.43 | 41.58 | within |
| vision | TTFT p95 | 1,426.46 | 1,559.32 | +132.86 | 202.37 | within |
| vision | ITL median | 33.77 | 33.61 | −0.16 | 0.30 | within |
| vision | ITL p95 | 35.21 | 35.35 | +0.14 | 0.18 | within |
| vision | latency median | 4,719.01 | 4,721.46 | +2.45 | 1.78 | **beyond: flagged** |
| vision | latency p95 | 4,778.92 | 4,833.84 | +54.92 | 344.46 | within |

The gateway's CPU median: embedding, route `ai` 2.86% and `llm` 2.73%; vision, route `ai` 1.96% and
`llm` 1.52%. Its memory median: embedding 30.8 and 31.6 MiB, vision 30.3 and 32.4 MiB. Neither form
costs measurably more to run.

**Embedding's p95 is relay jitter, not a form property.** Route `ai`'s p95, 153.92 ms, is above
both direct runs' p95s, 89.05 and 118.56 ms, while its median, 73.95 ms, is below both direct
medians. A tail that wide on the run with the lowest median is what jitter on the relay legs
gives. Read as a property of either form, it would favour `llm`; it is read as neither.

**The flagged figure: vision's request latency median.** `llm` took 2.45 ms longer than route
`ai` at the median, against a 1.78 ms spread between the direct runs. That is about 0.05% of a
4.72 s request, and the spread it exceeds is itself 0.04%. Both forms read "beyond" the direct runs
on this figure, by 2.89 and 5.34 ms, and every other vision figure, TTFT and ITL included, is
within. Per behavior 9, an `llm` figure beyond route `ai` by more than the spread is the
architect's call, not a fail.

## Results · slice 3

### The settled form

**The `llm` section serves the four aliases; route `ai` is deleted.** Behaviors 1–6 held, the
tiers passed, and the architect accepted the one flagged overhead figure, so the losing form went:
from [`config.yaml`](../../gateway/agentgateway/config.yaml), the `consumer` gateway on 3000, its
key list, the four routes, and their shared allow-list; from
[`deploy.env`](../../gateway/agentgateway/deploy.env) and the deploy, `AGW_PORT` and the 3000
publish. The keys now live in one list, `llm.policies.apiKey`, with the same
`sha256:@@<name>@@` markers. The header comment describes the one form.

- **Probes.** The route form's `rate-limit-agent` is deleted, and `rate-limit-agent-llm` takes its
  name, [`probes/rate-limit-agent.yaml`](../../gateway/agentgateway/probes/rate-limit-agent.yaml).
  [`key-header`](../../gateway/agentgateway/probes/key-header.yaml) still inserts after the line
  `    apiKey:`, now `llm.policies.apiKey`'s and the only such line; only its comment changed.
  `in-flight-1` inserts under `frontendPolicies:`, unchanged. No overlay was deployed. The deploy
  has no dry path, so each was rendered on the laptop the deploy's way, its markers replaced with a
  placeholder hash, and validated with the pinned image there (`docker run ... --validate-only`;
these laptop runs went through no helper, so their exact commands are not recorded):
  `key-header` alone, and `rate-limit-agent` with `in-flight-1`, each "Configuration is valid!".
  `apiKey.location` is a field of `LocalAPIKeys` in v1.7.0's schema, the type `llm.policies.apiKey`
  takes, and a field added under it is refused (``llm.policies: unknown field `bogusField` ``).
- **Helpers.** [`scripts/clients-lib.sh`](../../scripts/clients-lib.sh) and
  [`scripts/measure-lib.sh`](../../scripts/measure-lib.sh) drop `GATEWAY_FORM`: one form leaves
  nothing to choose, and `gw_base <alias>` is `http://gb10-2:<port>/v1`. measure-lib's cap-cell
  reader picked access log lines by the route form's `route=default/<alias>`. The `llm` section
  serves every alias through one route, so it now picks `listener=<alias>
  route=internal/llm:request`. Read over the smoke test's window (09:37:41), it found the agent
  port's two lines, `/v1/models` and `/v1/chat/completions`, both 200. clients-lib gains
  `logged <command>`, which runs a step that prints no key, such as the deploy, a keyless curl, or
  `mise run watch`, and puts the command and its output in the day's log, so the walkthrough runs
  every command through the helpers.

### The base URLs

Each alias's base URL is its own port's `/v1`, and its `/v1/models` lists that alias alone:

| Alias | Base URL |
| --- | --- |
| agent | `http://gb10-2:3010/v1` |
| vision | `http://gb10-2:3011/v1` |
| audio | `http://gb10-2:3012/v1` |
| embedding | `http://gb10-2:3013/v1` |

A consumer changes only the base URL and the key, as the tiers showed (behavior 3).

- **Rejected: one shared `/v1` with a key per purpose.** The `llm` section could serve every alias
  at one base URL and hold each key to its purpose, but a consumer that uses more than one alias
  would then hold a key for each, every consumer split four ways.
- **Rejected: per-alias routes into `llm`'s internal router.** Routes on one port matching
  `/<alias>/v1` could forward into the `llm` section through its internal `llm:router` backend,
  but that name is undocumented and could change in any release without notice.
- **What would bring `/<alias>/v1` back:** `llm.pathPrefix` is one string at v1.7.0, one prefix
  for every attached gateway. If `llm` gains several prefixes, or a model list per prefix, the
  aliases could share one port again. [`docs/watch.md`](../watch.md) watches the schema field.

### The deprecation risk

The gateway moved to `llm` ahead of a likely deprecation of route `ai`, on this evidence, read at
v1.7.0:

- **The UI labels it legacy.** `ui/src/traffic.ts` names an inline `ai` backend "legacy LLM
  backend" (and an inline `mcp` one "legacy MCP backend").
- **The docs moved.** website#1091 rewrote the Claude Code and Claude Desktop client pages from
  `routes[].backends[].ai` to the `llm` section, closing agentgateway#3655, "Docs result in legacy
  backend configuration".
- **A form has been deprecated without parity before.** `binds` is deprecated in favour of
  `gateways` and `routes` (the schema's own description: "Deprecated; usage of `gateways` and
  `routes` is recommended instead"), while `gateways` can't yet express `tunnelProtocol: connect`
  or `mode: internal` (#3204, open).
- **There is no deprecation policy.** #2767, "Define a project deprecation policy", was closed:
  "it may be a bit premature to establish a dep policy at this point with the project."
- **The schema doesn't mark route `ai` yet.** The route backend's `ai` variant has no
  description at v1.7.0, where `binds`' says "Deprecated".

[`docs/watch.md`](../watch.md), the watch register, now tracks it. Its read-only check,
`mise run watch` ([`scripts/watch.sh`](../../scripts/watch.sh)), runs at every task's PLAN as its
own block, separate from `mise run currency`. Three entries:

- **Deprecation: agentgateway route `ai` backends.** Upstream #4307, #3204, #2767, #3655, and
  website#1091; watched, whether the `ai` variant's description mentions deprecation (`[false]`;
  `[]` if the variant is removed) and the UI's "legacy LLM backend" (present).
- **Capability: `llm` serving several base URLs on one port.** Upstream #2973; watched,
  `llm.pathPrefix`'s type (`"string"`).
- **Capability: always-passthrough (#4185).** Merged 2026-10-27, after v1.7.0's tag. At v1.7.0
  `passthrough` covers only paths agentgateway doesn't classify, so `llm` parses the typed
  requests and adds `include_usage` to streams (behavior 2); #4185, marked breaking, makes it pass
  through always. Watched, whether the latest release holds its merge commit (absent). Before an
  upgrade that carries it, the gateway's body handling is checked again.

The first run, at 09:40, read every line as recorded, at v1.7.0:

```text
checked 2026-11-16T14:40Z
agentgateway route `ai` backends deprecated
  agentgateway/agentgateway#3204: recorded open, now open
  agentgateway/agentgateway#2767: recorded closed, now closed
  agentgateway/agentgateway#3655: recorded closed, now closed
  agentgateway/website#1091: recorded merged, now merged
  agentgateway/agentgateway@v1.7.0 schema/config.json [.["$defs"].LocalRouteBackend.oneOf[] | select(.properties.ai) | .description // "" | test("deprecated"; "i")] | any: recorded false, now false
  agentgateway/agentgateway@v1.7.0 ui/src/traffic.ts "legacy LLM backend": recorded present, now present
agentgateway `llm` serving several base URLs on one port
  agentgateway/agentgateway@v1.7.0 schema/config.json .["$defs"].LocalLLMConfig.properties.pathPrefix.type: recorded "string", now "string"
agentgateway always-passthrough for `llm` models
  agentgateway/agentgateway#4185: recorded merged, now merged
  agentgateway/agentgateway@v1.7.0 contains 2a7c2ec473a2: recorded absent, now absent
```

Its `differs` path was tried on a scratch edit of the register, then restored: a recorded state
changed, a text field's value flipped, and a path that doesn't exist each printed `differs` (the
missing file as `unreadable`), and the check exited 1. That test went through no helper, so its
commands are not recorded.

The standards review then changed the first entry's `json` line. Its expression ended in `| any`,
so a schema with no `ai` variant left would also read `false`, as recorded, and the variant's
removal would never show as a difference. The line now records the array, `[false]`: `[true]` is a
deprecation, and `[]` a removal. The check also counts an empty reading as a difference even if
the recorded value is empty.

### For an upstream feature request

The trial passed, but every gap it found against route `ai` was closed by a workaround, not by
`llm` reaching parity. Before the architect files anything, the session searched every
agentgateway issue and pull request, open and closed (1,247 issues and 3,108 pull requests,
2026-11-16), so an issue repeats nothing already raised.

| Gap on `llm` at v1.7.0 | Upstream | What to do |
|---|---|---|
| One path prefix for the whole section, so the aliases can't share one port as `/<alias>/v1` | Kubernetes has the feature: agentgateway#2973 (merged 2026-08-11) lets an HTTPRoute with a path-prefix rule and a backendRef of kind `AgentgatewayModel`, name `*`, instantiate a further model router on the same listener. Nothing asks for it in standalone `llm` | **File one issue** (below) |
| A distinct rate limit per model | agentgateway#4307 (open, Kubernetes). A maintainer's reply (2026-11-16) points standalone users to `localRateLimit` with `key: llm.requestModel` (example `llm-keyed-rate-limit` at v1.7.0), which gives each model its own bucket at one rule's limits | Comment on #4307 if `priority` needs different limits per model; `priority` weighs the keyed limit against the probe's internal `internal/llm:request` target |
| Chat, Messages, Responses, and embeddings parsed as typed requests whatever `passthrough` says | agentgateway#4185, merged 2026-10-27, unreleased, breaking | Watched ([`docs/watch.md`](../watch.md)) |
| `/v1/models` scoped to the caller | agentgateway#2719 closed once per-key `allowedModels` covered it; #2966 (hide virtual models) closed | Nothing: model `authorization` on the listener does it |
| Off-list paths refused with 403, not 404 | none | Too minor to file |
| Standalone `gateways` entries are listeners of one gateway, `default`, so `proxy.gateway.name` can't tell them apart | none | A documentation gap at most |
| No transcription route type | agentgateway#3799 (open, a question) | Nothing here: no row serves transcription |

The one issue worth filing, for the architect to write in their own words (agentgateway's code
of conduct requires a human-written description):

- **Ask:** standalone `llm` parity with #2973: several model routers on one listener, each with
  its own path prefix and its own set of models, its `/v1/models` listing only those.
- **Use case:** per-purpose base URLs (`/agent/v1`, `/vision/v1`, ...) over self-hosted vLLM rows,
  for OpenAI-compatible clients that take the single model a base URL lists (go-ai's integration
  tier, the `infer` CLI), so no client names a model.
- **Today's workaround, with its cost:** one gateway entry and published port per alias, each
  model's `authorization` requiring `proxy.listener.name == "<alias>"` ("The trial"); four ports
  to publish and four base URLs to hand out, and the rule leans on standalone naming every gateway
  entry a listener of `default`.
- **Evidence:** v1.7.0's `LocalLLMConfig.pathPrefix` is one string (`schema/config.json`;
  `crates/agentgateway/src/types/local.rs`); route `ai` gave the same per-alias URLs on one port
  in the agentgateway task, and its UI label is "legacy"; #4307 calls the model form the
  recommended one since 1.7.

### The smoke test

The deploy at 09:37:15 validated the config, recreated the container for the removed port (label
`spike.spec=f7f7f658b092`), and published 3010–3013 on the tailnet address and 3001 on loopback.
Through the helpers, with the architect's key:

| Request | Result |
| --- | --- |
| `/v1/models` on 3010, 3011, 3012, 3013 | `["agent"]`, `["vision"]`, `["audio"]`, `["embedding"]` |
| agent chat on 3010 | "Greetings and welcome, dear friend!", 73 in, 126 out |
| vision chat on 3011 | "Red", 21 in, 2 out |
| embedding on 3013 | one vector of 768, 5 tokens |
| `/agent/v1/models` on 3000 | `000`, "Failed to connect to gb10-2:3000 ... Could not connect to server": nothing listens |

A second deploy at 09:40:56 changed nothing ("image and flags unchanged; config.yaml reloads in
place"), and a keyless `/v1/models` on 3010 got 401 (09:41:01).

## Walkthrough

Slice 4, run by the architect from the repository root on the laptop. Every command goes through
the helpers, so each lands in `.state/routing/commands-<date>.log`. Each step's expected result
comes from slices 1–3.

```sh
source scripts/clients-lib.sh
```

1. **A deploy that changes nothing.**

   ```sh
   logged "mise run agentgateway-deploy"
   ```

   Expected: `Configuration is valid!`, then "agentgateway: image and flags unchanged;
   config.yaml reloads in place", and the container up.

2. **Each base URL's `/models`.**

   ```sh
   for a in agent vision audio embedding; do gw_curl architect -sS "$(gw_base $a)/models" | jq -c '[.data[].id]'; done
   ```

   Expected: `["agent"]`, `["vision"]`, `["audio"]`, `["embedding"]`.

3. **A chat, a stream, an embedding, and a transcription.**

   ```sh
   gw_curl architect -sS -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256}' "$(gw_base agent)/chat/completions" | jq -c '{model, content: .choices[0].message.content, usage}'
   gw_curl architect -sS -N -H 'Content-Type: application/json' -d '{"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200}' "$(gw_base agent)/chat/completions" | grep -c '"usage":{'
   gw_curl architect -sS -H 'Content-Type: application/json' -d '{"model":"embedding","input":["gateway","routing"]}' "$(gw_base embedding)/embeddings" | jq -c '[.data[].embedding | length]'
   gw_curl architect -sS -w '\n%{http_code}\n' -F model=audio -F file=@.state/routing/assets/clip-6s.wav "$(gw_base audio)/audio/transcriptions"
   ```

   Expected: the agent's greeting with its usage; `1`, the one usage chunk `llm` adds to every
   stream, though the request didn't ask for it; `[768,768]`; and `{"detail":"Not Found"}` with
   `404`, the audio row's own answer: no row serves transcription at vLLM v0.33.0
   ("Transcription, verified").

4. **A model at the wrong alias, and a path that isn't served.**

   ```sh
   gw_curl architect -sS -w '\n%{http_code}\n' -H 'Content-Type: application/json' -d '{"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":16}' "$(gw_base agent)/chat/completions"
   gw_curl architect -sS -o /dev/null -w '%{http_code}\n' http://gb10-2:3010/metrics
   ```

   Expected: `403`, "Model authorization denied"; then `403`, from the serving-path allow-list.

5. **A request without a key.**

   ```sh
   logged "curl -sS -o /dev/null -w '%{http_code}\n' http://gb10-2:3010/v1/models"
   ```

   Expected: `401`.

6. **One tier role.**

   ```sh
   goai_tier walk agent
   ```

   Expected: the agent role's scenarios pass, as in behavior 3, and the helper reports that the key
   is in none of the log's lines.

7. **The watch register.**

   ```sh
   logged "mise run watch"
   ```

   Expected: every line `recorded ..., now ...` with the same value, and exit 0. Any `differs` is
   read into [`docs/watch.md`](../watch.md) by hand.

### Walkthrough results

Run by the architect, 2026-11-16, 10:46–10:50, on the laptop over the DERP relay. Every step gave
its expected result:

| Step | Result |
|---|---|
| 1. A deploy that changes nothing | `Configuration is valid!`; "agentgateway: image and flags unchanged; config.yaml reloads in place"; the container up about an hour |
| 2. Each base URL's `/models` | `["agent"]`, `["vision"]`, `["audio"]`, `["embedding"]` |
| 3. Chat, stream, embedding, transcription | `{"model":"agent","content":"Hello, dear friend, welcome back!","usage":{"prompt_tokens":73,"completion_tokens":125,"total_tokens":198,"completion_tokens_details":{"reasoning_tokens":107}}}`; `1` usage chunk in the stream, unrequested; `[768,768]`; `{"detail":"Not Found"}` `404`, the audio row's own answer |
| 4. Wrong alias, unserved path | `{"error":{"message":"Model authorization denied","type":"invalid_request_error","code":"model_authorization_denied"}}` `403`; `/metrics` on 3010 `403` |
| 5. No key | `401` |
| 6. One tier role | `goai_tier walk agent`: 17 passed, 0 failed, 4 skipped (top-level), exit 0; the skips are the roles left unset (embedding, audio, transcription); `TestModels` reads "AI_AGENT_BASE_URL serves agent"; the key is not in the log |
| 7. The watch register | `checked 2026-11-16T15:50Z`, every line `recorded X, now X`, exit 0 |

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

### 2026-11-16 · transcription, verified

The row's route list, model, and version, its log of slice 1's transcriptions and of its start, then
the four transcriptions with the row's counter read before and after each, and the gateway's and the
row's logs of them. One read of the row's `/metrics` between 09:06:49 and 09:08:07, to find the
counter, is not in the log. The vLLM sources were read with `gh api`, on the laptop, and are cited
where they are used:

```text
+ 2026-11-16T09:06:48-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:06:48-05:00 laptop: curl -sS http://framework:8001/openapi.json > .state/routing/transcription/openapi.json && jq -r '.paths | keys[]' .state/routing/transcription/openapi.json
+ 2026-11-16T09:06:49-05:00 laptop: curl -sS http://framework:8001/v1/models | jq -c '[.data[] | {id, root, max_model_len}]'
+ 2026-11-16T09:06:49-05:00 laptop: curl -sS http://framework:8001/version
+ 2026-11-16T09:08:07-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:08:07-05:00 framework: docker logs --since 2026-11-16T12:55:00Z --until 2026-11-16T12:57:00Z vllm-audio 2>&1 | grep -F /v1/audio/transcriptions | sed -E 's/[0-9]+(\.[0-9]+){3}:[0-9]+/<client>/'
+ 2026-11-16T09:08:08-05:00 framework: docker logs vllm-audio 2>&1 | grep -E 'Resolved architecture|Supported tasks|supported_tasks' | head -5
+ 2026-11-16T09:08:18-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:08:18-05:00 laptop: curl -sS http://framework:8001/metrics | grep -E '^http_request(s_total|_size_bytes_(count|sum))\{handler="none"'
+ 2026-11-16T09:08:18-05:00 laptop: curl -sS -w '\n%{http_code} %{size_upload}\n' -F model=audio -F file=@.state/routing/assets/clip-6s.wav http://framework:8001/v1/audio/transcriptions
+ 2026-11-16T09:08:18-05:00 laptop: curl -sS http://framework:8001/metrics | grep -E '^http_request(s_total|_size_bytes_(count|sum))\{handler="none"'
+ 2026-11-16T09:08:18-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code} %{size_upload}\n -F model=audio -F file=@.state/routing/assets/clip-6s.wav http://gb10-2:3000/audio/v1/audio/transcriptions
+ 2026-11-16T09:08:19-05:00 laptop: curl -sS http://framework:8001/metrics | grep -E '^http_request(s_total|_size_bytes_(count|sum))\{handler="none"'
+ 2026-11-16T09:08:19-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code} %{size_upload}\n -F model=audio -F file=@.state/routing/assets/clip-6s.wav http://gb10-2:3012/v1/audio/transcriptions
+ 2026-11-16T09:08:20-05:00 laptop: curl -sS http://framework:8001/metrics | grep -E '^http_request(s_total|_size_bytes_(count|sum))\{handler="none"'
+ 2026-11-16T09:08:20-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code} %{size_upload}\n -F model=vision -F file=@.state/routing/assets/clip-6s.wav http://gb10-2:3012/v1/audio/transcriptions
+ 2026-11-16T09:08:20-05:00 laptop: curl -sS http://framework:8001/metrics | grep -E '^http_request(s_total|_size_bytes_(count|sum))\{handler="none"'
+ 2026-11-16T09:08:29-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:08:29-05:00 gb10-2: docker logs --since 2026-11-16T14:08:15Z --until 2026-11-16T14:08:25Z agentgateway 2>&1 | grep -F /v1/audio/transcriptions | sed -E 's/src\.addr=[^ ]+/src.addr=<laptop>/'
+ 2026-11-16T09:08:29-05:00 framework: docker logs --since 2026-11-16T14:08:15Z --until 2026-11-16T14:08:25Z vllm-audio 2>&1 | grep -F /v1/audio/transcriptions | sed -E 's/[0-9]+(\.[0-9]+){3}:[0-9]+/<client>/'
```

### 2026-11-16 · the tiers and the infer CLI

The go-ai worktree at `tools/infer/v0.1.0` and the released infer, go-ai's and infer's tiers on the
`llm` form's base URLs, then infer with no `--model` on each port. Each tier helper logs the
command it runs on the line after its own:

```text
+ 2026-11-16T09:13:42-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:13:42-05:00 laptop: git -C ~/architecture/go-ai worktree add --detach .state/routing/go-ai tools/infer/v0.1.0
+ 2026-11-16T09:13:42-05:00 laptop: GOBIN=.state/routing/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.1.0 && .state/routing/bin/infer version
+ 2026-11-16T09:13:51-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:13:51-05:00 laptop: goai_tier goai-llm agent vision audio embedding
+ 2026-11-16T09:13:51-05:00 laptop: cd .state/routing/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3010/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3011/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3012/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3013/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/routing/clients/goai-llm.log
+ 2026-11-16T09:14:56-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:14:56-05:00 laptop: infer_tier infer-llm agent vision audio embedding
+ 2026-11-16T09:14:56-05:00 laptop: cd .state/routing/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3010/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_BASE_URL=http://gb10-2:3011/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3012/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3013/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/routing/clients/infer-llm.log
+ 2026-11-16T09:15:31-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:15:35-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:15:35-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3010/v1 .state/routing/bin/infer models
+ 2026-11-16T09:15:35-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3011/v1 .state/routing/bin/infer models
+ 2026-11-16T09:15:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3012/v1 .state/routing/bin/infer models
+ 2026-11-16T09:15:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3013/v1 .state/routing/bin/infer models
+ 2026-11-16T09:15:36-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3010/v1 .state/routing/bin/infer chat Answer with one word: the capital of France?
+ 2026-11-16T09:15:37-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3011/v1 .state/routing/bin/infer chat Answer with one word: the color of the sky on a clear day?
+ 2026-11-16T09:15:37-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3012/v1 .state/routing/bin/infer chat Answer with one word: the opposite of up?
+ 2026-11-16T09:15:37-05:00 laptop: INFER_TOKEN=$(<.state/agentgateway/keys/go-ai) INFER_BASE_URL=http://gb10-2:3013/v1 .state/routing/bin/infer embed gateway routing
```

### 2026-11-16 · the stack and the path

The host stack record, then ten pings to each host and the netcheck, with every address replaced
with `<addr>`:

```text
+ 2026-11-16T09:15:51-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:15:51-05:00 laptop: { date -Is; for h in gb10-2 framework; do echo "== $h"; timeout 60 ssh -o BatchMode=yes $h 'uptime -p; uname -r; docker ps --format "{{.Names}} {{.Image}} {{.Status}}"'; done; for hp in gb10-2:8000 framework:8002; do printf "%s version " $hp; curl -s --max-time 5 http://$hp/version; echo; done; for h in gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done; } 2>&1 | tee .state/routing/stack-$(date +%F).txt
+ 2026-11-16T09:16:03-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:16:03-05:00 laptop: for h in gb10-2 framework; do tailscale ping -c 10 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g" | tail -3; done; tailscale netcheck 2>&1 | grep -E "UDP|IPv4|Nearest|MappingVariesByDestIP|PortMapping" | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"
```

### 2026-11-16 · the overhead cells

O-embed's four runs, O-vision's four, and the four `compare`s. `cell` logs the GuideLLM command it
runs, and for a gateway run the sampler beside it, on the lines after its own:

```text
+ 2026-11-16T09:17:30-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:17:30-05:00 laptop: cell r-embed-direct-1 overhead-embed direct embedding
+ 2026-11-16T09:17:30-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=618426062 --output kind=json,path=.state/routing/cells/r-embed-direct-1/result.json --disable-console-interactive > .state/routing/cells/r-embed-direct-1/guidellm.log 2>&1
+ 2026-11-16T09:18:50-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:18:50-05:00 laptop: cell r-embed-route overhead-embed gateway embedding
+ 2026-11-16T09:18:50-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/embedding/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=2762826689 --output kind=json,path=.state/routing/cells/r-embed-route/result.json --disable-console-interactive > .state/routing/cells/r-embed-route/guidellm.log 2>&1
+ 2026-11-16T09:18:50-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/routing/cells/r-embed-route/gateway-stats.tsv
+ 2026-11-16T09:20:13-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:20:13-05:00 laptop: cell r-embed-llm overhead-embed gateway embedding
+ 2026-11-16T09:20:13-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3013/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=2813028374 --output kind=json,path=.state/routing/cells/r-embed-llm/result.json --disable-console-interactive > .state/routing/cells/r-embed-llm/guidellm.log 2>&1
+ 2026-11-16T09:20:13-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/routing/cells/r-embed-llm/gateway-stats.tsv
+ 2026-11-16T09:21:35-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:21:35-05:00 laptop: cell r-embed-direct-2 overhead-embed direct embedding
+ 2026-11-16T09:21:35-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://framework:8002/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-embed.yaml --backend kind=openai_http,model=embedding --tokenizer kind=huggingface_auto,model=ibm-granite/granite-embedding-english-r2 --seed kind=static,value=1446457629 --output kind=json,path=.state/routing/cells/r-embed-direct-2/result.json --disable-console-interactive > .state/routing/cells/r-embed-direct-2/guidellm.log 2>&1
+ 2026-11-16T09:22:56-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:22:56-05:00 laptop: cell r-vision-direct-1 overhead-vision direct vision
+ 2026-11-16T09:22:56-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8000/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=4267744146 --output kind=json,path=.state/routing/cells/r-vision-direct-1/result.json --disable-console-interactive > .state/routing/cells/r-vision-direct-1/guidellm.log 2>&1
+ 2026-11-16T09:24:39-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:24:39-05:00 laptop: cell r-vision-route overhead-vision gateway vision
+ 2026-11-16T09:24:39-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3000/vision/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=1434110204 --output kind=json,path=.state/routing/cells/r-vision-route/result.json --disable-console-interactive > .state/routing/cells/r-vision-route/guidellm.log 2>&1
+ 2026-11-16T09:24:39-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/routing/cells/r-vision-route/gateway-stats.tsv
+ 2026-11-16T09:26:25-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:26:25-05:00 laptop: cell r-vision-llm overhead-vision gateway vision
+ 2026-11-16T09:26:25-05:00 laptop: GUIDELLM__SPEC__BACKEND__API_KEY=$(<.state/agentgateway/keys/bench) GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:3011/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=2786512739 --output kind=json,path=.state/routing/cells/r-vision-llm/result.json --disable-console-interactive > .state/routing/cells/r-vision-llm/guidellm.log 2>&1
+ 2026-11-16T09:26:25-05:00 laptop: every 5 s while it runs: ssh -n gb10-2 "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' agentgateway" >> .state/routing/cells/r-vision-llm/gateway-stats.tsv
+ 2026-11-16T09:28:12-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:28:12-05:00 laptop: cell r-vision-direct-2 overhead-vision direct vision
+ 2026-11-16T09:28:12-05:00 laptop: GUIDELLM__SPEC__BACKEND__TARGET=http://gb10-2:8000/v1 MISE_ENV=bench timeout 10m mise exec -- guidellm run -c bench/overhead-vision.yaml --backend kind=openai_http,model=vision --tokenizer kind=huggingface_auto,model=google/gemma-4-26B-A4B-it --seed kind=static,value=2357969985 --output kind=json,path=.state/routing/cells/r-vision-direct-2/result.json --disable-console-interactive > .state/routing/cells/r-vision-direct-2/guidellm.log 2>&1
+ 2026-11-16T09:30:00-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:30:00-05:00 laptop: compare r-embed-direct-1 r-embed-route r-embed-direct-2
+ 2026-11-16T09:30:00-05:00 laptop: compare r-embed-direct-1 r-embed-llm r-embed-direct-2
+ 2026-11-16T09:30:01-05:00 laptop: compare r-vision-direct-1 r-vision-route r-vision-direct-2
+ 2026-11-16T09:30:01-05:00 laptop: compare r-vision-direct-1 r-vision-llm r-vision-direct-2
```

### 2026-11-16 · slice 3: the settled form

The deploy that removed 3000 (the container recreated), the smoke test, the cap-cell reader over
the smoke test's window, the watch check's first run, and a deploy that changed nothing with a
keyless request, through `logged`:

```text
+ 2026-11-16T09:37:15-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:37:15-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T09:37:15-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T09:37:16-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.TPmRnz.yaml
+ 2026-11-16T09:37:16-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T09:37:17-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T09:37:18-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T09:37:19-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T09:37:19-05:00 gb10-2: docker rm --force agentgateway
+ 2026-11-16T09:37:20-05:00 gb10-2: docker run --detach --name agentgateway --restart unless-stopped --user "$(id -u):$(id -g)" --publish "$(tailscale ip -4):3010:3010" --publish "$(tailscale ip -4):3011:3011" --publish "$(tailscale ip -4):3012:3012" --publish "$(tailscale ip -4):3013:3013" --publish 127.0.0.1:3001:3001 --volume "$HOME/agentgateway:/config:ro" --add-host "gb10-1:$(tailscale ip -4 gb10-1)" --add-host "gb10-2:$(tailscale ip -4 gb10-2)" --add-host "framework:$(tailscale ip -4 framework)" --label spike.spec=f7f7f658b092 cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml
+ 2026-11-16T09:37:21-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T09:37:27-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:37:27-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3010/v1/models
+ 2026-11-16T09:37:28-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3011/v1/models
+ 2026-11-16T09:37:28-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3012/v1/models
+ 2026-11-16T09:37:28-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3013/v1/models
+ 2026-11-16T09:37:28-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T09:37:32-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Name one primary color, one word."}],"max_tokens":64} http://gb10-2:3011/v1/chat/completions
+ 2026-11-16T09:37:32-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"embedding","input":"gateway routing"} http://gb10-2:3013/v1/embeddings
+ 2026-11-16T09:37:33-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w 3000: %{http_code} %{errormsg}\n http://gb10-2:3000/agent/v1/models
+ 2026-11-16T09:37:41-05:00 laptop: source scripts/measure-lib.sh
+ 2026-11-16T09:37:41-05:00 laptop: ssh -n gb10-2 'docker logs --timestamps --since 2026-11-16T14:37:25Z --until 2026-11-16T14:37:40Z agentgateway 2>&1' | the lines of listener=agent route=internal/llm:request as time, status, path, retry_after > .state/routing/cells/s3-log-check/gateway-requests.tsv
+ 2026-11-16T09:40:04-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:40:04-05:00 laptop: mise run watch
+ 2026-11-16T09:40:56-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:40:56-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T09:40:57-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T09:40:57-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.dTnaLU.yaml
+ 2026-11-16T09:40:58-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T09:40:59-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T09:40:59-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T09:41:00-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T09:41:01-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T09:41:01-05:00 laptop: curl -sS -o /dev/null -w '3010 no key: %{http_code}\n' http://gb10-2:3010/v1/models
```

### 2026-11-16 · after the standards review

The comment-only config change the standards review made was deployed, so the walkthrough's first
deploy changes nothing, and the watch check was rerun after its `json` line changed; the
register's "Last checked" lines cite this run (14:48Z).

```
+ 2026-11-16T09:48:14-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T09:48:14-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T09:48:14-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T09:48:15-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.urVTez.yaml
+ 2026-11-16T09:48:16-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T09:48:16-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T09:48:17-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T09:48:18-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T09:48:18-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T09:48:19-05:00 laptop: mise run watch
```

### 2026-11-16 · the upstream survey

Run by the session on the laptop, outside the helpers, so the times were not recorded; the
commands are as run. The two lists were read once and searched locally with `jq`.

```
gh search issues --repo agentgateway/agentgateway "legacy" --limit 30 --json number,title,state,isPullRequest,createdAt
gh search issues --repo agentgateway/agentgateway "deprecate" --limit 30 --json number,title,state,isPullRequest,createdAt
gh issue view 3655 -R agentgateway/agentgateway --json title,state,body,comments
gh issue view 2767 -R agentgateway/agentgateway --json title,state,body,comments
gh issue view 3204 -R agentgateway/agentgateway --json title,state,body,comments
gh pr view 2473 -R agentgateway/agentgateway --json body
gh pr view 1091 -R agentgateway/website --json title,body,files
gh issue list -R agentgateway/agentgateway --state all --limit 6000 --json number,title,state,body,createdAt > agw-issues.json
gh pr list -R agentgateway/agentgateway --state all --limit 6000 --json number,title,state,body,createdAt > agw-prs.json
jq length agw-issues.json agw-prs.json
gh issue view 2719 -R agentgateway/agentgateway --json comments,stateReason
gh issue view 4307 -R agentgateway/agentgateway --json comments
gh api "repos/agentgateway/agentgateway/contents/examples/llm-keyed-rate-limit/config.yaml?ref=v1.7.0" --jq .content
gh api "repos/agentgateway/agentgateway/contents/examples/llm-keyed-rate-limit/README.md?ref=v1.7.0" --jq .content
```

`jq length` printed 1247 and 3108. Not quoted: fourteen two-word `gh search issues` queries that returned
nothing (GitHub's search matched them too narrowly, which is why the full lists were read), and the
local `jq` greps over the two lists, by gap.

### 2026-11-16 · the walkthrough, run by the architect

```
+ 2026-11-16T10:46:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-16T10:46:29-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-16T10:46:29-05:00 gb10-2: mkdir -p ~/agentgateway
+ 2026-11-16T10:46:30-05:00 laptop: ssh gb10-2 'cat > ~/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.o3oMWH.yaml
+ 2026-11-16T10:46:31-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-16T10:46:31-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-16T10:46:32-05:00 gb10-2: mv ~/agentgateway/config.yaml.next ~/agentgateway/config.yaml
+ 2026-11-16T10:46:33-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "spike.spec"}} {{.State.Running}}' 2>/dev/null || true
+ 2026-11-16T10:46:34-05:00 gb10-2: docker ps --filter name=agentgateway --format '{{.Names}} {{.Image}} {{.Status}}'
+ 2026-11-16T10:47:13-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3010/v1/models
+ 2026-11-16T10:47:13-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3011/v1/models
+ 2026-11-16T10:47:14-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3012/v1/models
+ 2026-11-16T10:47:14-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS http://gb10-2:3013/v1/models
+ 2026-11-16T10:47:40-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say hello in five words."}],"max_tokens":256} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T10:47:55-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -N -H Content-Type: application/json -d {"model":"agent","stream":true,"messages":[{"role":"user","content":"Count from 1 to 5."}],"max_tokens":200} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T10:48:12-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -H Content-Type: application/json -d {"model":"embedding","input":["gateway","routing"]} http://gb10-2:3013/v1/embeddings
+ 2026-11-16T10:48:30-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -F model=audio -F file=@.state/routing/assets/clip-6s.wav http://gb10-2:3012/v1/audio/transcriptions
+ 2026-11-16T10:48:45-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":16} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T10:49:02-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -w \n%{http_code}\n -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":16} http://gb10-2:3010/v1/chat/completions
+ 2026-11-16T10:49:05-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -o /dev/null -w %{http_code}\n http://gb10-2:3010/metrics
+ 2026-11-16T10:49:18-05:00 laptop: curl -sS -o /dev/null -w '%{http_code}\n' http://gb10-2:3010/v1/models
+ 2026-11-16T10:49:25-05:00 laptop: goai_tier walk agent
+ 2026-11-16T10:49:25-05:00 laptop: cd .state/routing/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3010/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/routing/clients/walk.log
+ 2026-11-16T10:50:40-05:00 laptop: mise run watch
```
