# answer

The spike's last task: the clients at go-ai v0.2.0 through the gateway, go-ai's live retry proof
against the gateway's own refusals, traces from the gateway down to each row, and the paper and the
answer (evidence 8–11 of [`context/README.md`](../../context/README.md#the-evidence)). This finding
holds slice 1, "Clients": behaviors 1–8, and slice 2, "Traces": behaviors 9–12, with 17 and 18
throughout, then slice 4, the walkthrough.

In short, after slices 1 and 2:

- **Rows up (behavior 3):** go-ai's and infer's whole tiers at `tools/infer/v0.2.0` passed through
  the gateway on all four aliases: go-ai 26 passed, 0 failed, 1 skipped; infer 19 passed, 0 failed,
  1 skipped. Each skip is transcription's own route, which no row serves. No request reached Azure.
- **Rows down (behaviors 4, 5):** every fix go-ai claims for priority's discrepancies passed on
  Azure: the empty-id first chat chunk, the Responses reasoning item added with content, top-level
  `reasoning_tokens`, and a translated Messages stream's input tokens. Each declared gap skipped
  before sending, and each provider's or gateway's error came through as recorded, but two:
  - the 16-token Messages stall didn't recur: that stream ended within its limit;
  - the allowed_tools-required test now runs on Messages alone, so it has no completions case to
    skip.
  TestTranscribeChat passed after the audio rerun's warm-up. No claimed fix still fails.
- **Retry proof (behaviors 6–8):** all four cases passed with the rows up and nothing sent to
  Azure, each cross-checked against the access log or `requests_shed`. rate-limit-agent passed only
  after its overlay was fixed: since priority, the agent route's own `localRateLimit` takes the
  place of the overlay's attached policy, so the overlay's bucket never applied ("Case a").
- **Traces (behaviors 9–12):** every request through a row is one trace of 3 spans, the row's
  `llm_request` the child of the gateway's client span; an overflowed request's trace has no row
  span, its retried attempts and Azure's each a client span. No span holds prompt or completion
  content. Each row's startup trace gives its cold start by phase: 13.0–50.0 s. The trace services
  came back from a restart, and every gateway container restarts unless stopped.
- **Azure:** 50 of the task's 80 requests: 48 in slice 1's step 3 (2xx ×34, 400 ×14) and 2 for the
  overflow trace (2xx ×2), no 429.

- **Measured:** from the laptop, 2026-11-18, local time. The architect's host updates ran
  18:11–18:35, and the session's smoke check at 18:36. Step 1, the stack's deploy, ran
  18:37:58–18:38:16; step 2, the rows-up tiers, 18:38:21–18:39:49; step 3, rows down,
  18:40:15–18:41:39; step 5, the retry cases, 18:42:37–18:45:06; and the firmware history and the
  path were read 18:45:32–18:45:43. Slice 2, traces, ran 19:10:59–19:18:12. Every command the
  helpers logged is under "Commands as run".
- **Path:** direct to every host over Tailscale, 1 ms, at 18:11:00 and 18:45:43.
- **Gateway:** agentgateway v1.7.0, `cr.agentgateway.dev/agentgateway:v1.7.0`, on gb10-2, with its
  Postgres (`postgres:18.7-alpine`) in one compose project
  ([`gateway/compose.yml`](../../gateway/compose.yml)), configured from
  [`gateway/agentgateway/config.yaml`](../../gateway/agentgateway/config.yaml), with the stats port,
  15020, on gb10-2's loopback ([`gateway/agentgateway.yml`](../../gateway/agentgateway.yml)).
- **Rows:** vLLM v0.34.0, each row serving its alias as its only model name, bound to its host's
  tailnet address: agent on gb10-1, vision on gb10-2, audio and embedding on the Framework.
- **Clients:** go-ai's integration tier and infer's from a worktree at `tools/infer/v0.2.0`
  (`228ed02`), whose base module is go-ai v0.2.0; the released infer v0.2.0; and the spike's retry
  test, [`retry/`](../../retry/retry_test.go), at go-ai v0.2.0 from the module proxy.
- **Cloud:** the spike's Azure AI Foundry account, one deployment per alias, as priority set it up
  ([`priority.md`](priority.md), "Azure AI Foundry").
- **Kept out:** no address, key, Azure account or resource group name, or other secret. A
  `tailscale ping` line is quoted with each address as `<addr>`, and the deploy's temporary files
  as `<tmp>`, as the helpers log them. Raw output stays untracked under `.state/answer/`.

## Method

**Steps.** The session runs every host step over Tailscale SSH with no root, each through the step
helpers, [`scripts/clients-lib.sh`](../../scripts/clients-lib.sh), or the deploy,
[`scripts/agentgateway-deploy.sh`](../../scripts/agentgateway-deploy.sh), which log each command to
`.state/answer/commands-2026-11-18.log` before it runs. The architect ran the host updates (root).

**Targets and profiles.** Each tier run names what answers the aliases, `CLIENTS_TARGET=rows-up` or
`rows-down`, and the helper sets each alias's profile for it (behavior 1): rows up, the agent row's
vLLM 0.34.0 profile from go-ai's `integration/doc.go`; rows down, agent's
`{"completions":{"no_tool_choice_required":true}}` and vision's refused efforts. A profile's
declared gap is refused before sending, so the test skips naming it.

**The priority rerun.** `priority_rerun` reruns, as one `go test -run` selection per tier, the
top-level tests priority's finding lists as failing on Azure, on all four aliases; a selected test's
passing subtests run too. `audio_rerun` then warms the audio row's eviction with two text-only chats
before each of go-ai's two audio tests, and runs the test alone.

**The retry test.** [`retry/`](../../retry/retry_test.go) builds go-ai's client with `ai.New` over an
`*http.Client` whose transport records every attempt: its start, its reply's time, status,
`Retry-After`, `x-ratelimit-*`, and whether a refused body holds `request limit exceeded`. The policy
is infer's default: 3 attempts, 500 ms base, 30 s most; in-flight-1's second call alone allows 5
attempts, since full jitter can make a retry beat the held stream's release (the test's comment),
and it used 2. A case passes only if every refused attempt carries a marker only the gateway gives
(`x-ratelimit-*` on a 429, the body marker on a 503), the call's last attempt is 200 (but
bulk-rate-low's refused call), and each retry starts no sooner than the refused attempt's
Retry-After after its reply. `retry_case <case>` runs one case, after checking that the deployed
copy's first line names its overlay, and writes its per-attempt table beside its log under
`.state/answer/retry/`. The key is read by the test from its file.

**The cross-checks.** A 429 is the gateway's own: it leaves an access log line with
`http.status=429`, `retry_after`, and no `endpoint`. The in-flight limit's 503 leaves no line at all,
only `agentgateway_requests_shed_total`, read before and after each case with `requests_shed`.

**The Azure cap.** Azure answers at most 80 requests in the task, counting its 2xx and its 4xx other
than 429, with 429s reported apart. Before each step that can overflow, the session estimates its
cost; after it, `azure_count <since>` counts the access log's lines marked `overflow="azure"` per
alias and status. Only synthetic and test-fixture content is sent.

## Slice 1 · clients

### The hosts

The architect ran `apt` on both GB10s and Dell's firmware updates on both (BIOS, embedded
controller, and USB-C PD controller), each with a reboot: gb10-1's firmware at 18:13 and gb10-2's at
18:26, fwupd's history reads, each update's state "success". The Framework wasn't updated. Read
before (18:11:00) and after (gb10-1 18:23:34, the Framework 18:27:10, gb10-2 18:34:28), untracked
under `.state/answer/`; the firmware's earlier versions from fwupd's history (18:45:39):

| Host | Rows | Firmware before → after (BIOS; EC; PD) | Kernel | NVIDIA driver | Docker | Updates pending, before → after |
| --- | --- | --- | --- | --- | --- | --- |
| gb10-1 | agent, 8000 | 4.1.0; 0x02000c00; 0x00000516 → 5.0.0; 0x02000d00; 0x00000519 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 36 → 13 |
| gb10-2 | vision, 8000; the gateway, 3000 | 4.1.0; 0x02000c00; 0x00000516 → 5.0.0; 0x02000d00; 0x00000519 | 7.0.0-1025-nvidia | 580.178.04 | 29.6.2 | 33 → 18 |
| framework | audio, 8001; embedding, 8002 | not updated | 7.2.15-1-omarchy | — | 29.9.2 | 0 → 0, not rebooted (up since 2026-11-17 05:49:56) |

Neither GB10 left `/var/run/reboot-required`. Kernel, driver, and Docker were the same before and
after. The four host reads and the firmware's update ran outside the helpers, so they aren't in the
command log; the reads are in `.state/answer/*-2026-11-18.txt`. Each after read's `/health` line
reads 000, the Framework's too, whose rows had run 36 hours: the rows bind to their hosts' tailnet
addresses, so those lines don't show a row's state. Every alias answered the keyed smoke check
through the gateway at 18:36:06, and every request in steps 1 and 2.

The laptop's path to each host was direct, 1 ms, at 18:11:00 and again at 18:45:43 (`tailscale
ping`, each address replaced).

### Step 1 · the stack's deploy (behavior 8)

`mise run agentgateway-deploy` at 18:37:58 deployed the compose project with the stats port,
`127.0.0.1:15020`. It recreated the agentgateway container, since its ports changed, and Postgres
too: the build pulled `postgres:18.7-alpine`'s layers again, so gb10-2 no longer held the image
after its update (why wasn't read), and the rebuilt image's id moved. Both came up healthy. Every later deploy in the task left Postgres
`Running`, as priority's attestation fix has it. The access log starts with that container, so the
task's Azure count is read from 18:38:00; before it, the only gateway traffic in the task was the
18:36 smoke check, with the rows up and no overlay.

| Check (18:38:16) | Result |
| --- | --- |
| each alias's `/v1/models` | `["agent"]`, `["vision"]`, `["audio"]`, `["embedding"]`: each lists itself alone |
| `requests_shed` | `agentgateway_requests_shed_total{bind="bind/3000"} 0`: the metric, `agentgateway_requests_shed_total`, exists under the name the helper reads, so the helper is unchanged |

Before the tiers, `goai_checkout` made the worktree at `tools/infer/v0.2.0`, and `infer_install`
installed infer v0.2.0. The install's first try, at 18:37:17, failed: `go` found go-ai v0.2.0 but
not the `tools/infer` module beside it. The same command from the scratch directory downloaded
`tools/infer` v0.2.0 at once, and the helper's second try, at 18:37:52, printed `v0.2.0`: a cold
module proxy lookup, not a change to make.

### Step 2 · rows up (behavior 3)

With the base config and every row up (18:38:21–18:39:49):

| Tier | Result | Skipped |
| --- | --- | --- |
| go-ai, `a1-up-goai`, all four aliases | 26 passed, 0 failed, 1 skipped (78 subtests passed) | `TestTranscribeRoute`: no transcription role |
| infer, `a1-up-infer`, all four aliases | 19 passed, 0 failed, 1 skipped | `TestTranscribeRoute`: no transcription role |

Every other skip is a subtest: `TestModels/AI_TRANSCRIPTION_BASE_URL` in both tiers, and the tiers'
own checks of the declared-skip path (`TestSkipDeclared_ThroughClient/*`,
`TestSkipDeclared/declared*`, `TestDeclaredSkip/chat`). The agent row's profile declared no gap
that any test reached: nothing skipped as declared. `azure_count` from 18:38:21: 0. Each run's
helper found no key in its log.

### Step 3 · rows down (behavior 4)

**The cost, before.** Priority's whole tiers on Azure cost 42 (go-ai) and about 28 (infer), and its
audio rerun 6. The rerun selects a subset of those tiers, so the bound was about 76 and the
estimate about 50, under the cap: the step went ahead. At 18:40:15, `azure_count` from 18:38:00
read 0, the baseline.

`mise run agentgateway-deploy rows-down` at 18:40:15 put every row's provider at its host's closed
port 8009; the copy's first line read `# overlays: rows-down`. Then:

| Run | Result | Azure-answered |
| --- | --- | --- |
| `CLIENTS_TARGET=rows-down priority_rerun a2-down`: go-ai's selection, `a2-down-goai` | 1 passed, 9 failed, 0 skipped (top-level) | 42, both runs (agent 30: 200 ×21, 400 ×9; vision 11: 200 ×11; audio 1: 200 ×1) |
| infer's selection, `a2-down-infer` | 2 passed, 2 failed, 0 skipped (top-level) | (above) |
| `audio_rerun a3-audio`: `TestAudioInResponsesRefused` | 0 passed, 1 failed | 6 in all (audio: 400 ×5, 200 ×1) |
| `audio_rerun a3-audio`: `TestTranscribeChat` | 1 passed | (above) |

The 9 agent 400s are Azure's refusal of `tool_choice: required` on the Messages and Responses
cases (below). In the selection, go-ai's two audio tests sent their large bodies while the audio
row wasn't yet evicted, so each got the row's 503 ("connection refused"), as in priority; infer's
`TestTranscribeChat`, which ran after them, found the row evicted and passed on Azure. Each
warm-up of `audio_rerun` was answered 400 by Azure, marked `x-gateway-overflow: azure`.

**Back to the rows.** A plain deploy at 18:41:25 removed the overlay (`# overlays: none`). At
18:41:33 each alias answered one request 200 with no `x-gateway-overflow` header, and the access log
named each row as the endpoint, with the provider `custom`, not `azure`:

| Route | Endpoint | Status |
| --- | --- | --- |
| `default/agent` | `gb10-1:8000` | 200 |
| `default/vision` | `gb10-2:8000` | 200 |
| `default/audio` | `framework:8001` | 200 |
| `default/embedding` | `framework:8002` | 200 |

No row stayed evicted: the reload builds the backends again.

### The revalidation (behaviors 4, 5)

Each priority discrepancy, the change that claims it, the result expected, and the result, from
`a2-down-goai`, `a2-down-infer`, and `a3-audio-*`:

| Discrepancy (priority) | Claimed by | Expected | Result |
| --- | --- | --- | --- |
| Azure's chat stream opens with a chunk of empty id | go-ai v0.1.1, `format/completions` | pass | **pass**: infer's `TestChatImage` (all three formats) and `TestChatReasoningEffort/completions/stream=true` on vision; go-ai's `TestStreamText/completions` |
| a Responses reasoning item added with content | go-ai v0.1.1, `format/responses` | pass | **pass**: infer's `TestChatReasoningEffort/responses/stream=true/low` on vision |
| `reasoning_tokens` at the usage's top level | go-ai v0.1.1, `format/completions` | pass | **pass**: agent's Chat Completions replies print `(17 reasoning)` and `(19 reasoning)` (infer's `TestChatIncompleteAtMaxTokens/completions`), where they had decoded as 0 |
| `TestStreamText/messages`, a translated Messages stream's input tokens | go-ai v0.2.0, `format/messages` (several `message_delta` events) | pass | **pass** |
| `tool_choice: required` on agent Chat Completions: the function-call, reasoning round-trip, and allowed_tools-required tests | go-ai v0.2.0, `completions.Options.NoToolChoiceRequired`; the helper's rows-down agent profile | declared skip | **declared skip** for `TestFunctionCallRoundTrip`, `TestStreamFunctionCall`, `TestReasoningRoundTrip`, `TestStreamReasoningRoundTrip`, each `/completions`: "refused before sending". `TestToolChoice/allowed_tools_required` runs on Messages alone at v0.2.0 (its doc comment), so it has no completions case |
| effort `none` on vision | go-ai v0.2.0, `RefusedEfforts`; the rows-down vision profile | declared skip | **declared skip** on Chat Completions and Responses, both stream modes. Through Messages, which the profile doesn't cover, `none` passed (below) |
| `tool_choice: required` on agent Messages and Responses | — | the provider's error | **as expected**: 400 "Request included unsupported tool use. tool_choice 'required' is not supported for the model." (`UnsupportedToolUse`), 9 times, `TestToolChoice/allowed_tools_required/messages` among them |
| a named function ignored | — | the provider's behavior | **as expected**: `TestToolChoice/named_function`, all three formats, "Output has 0 function calls, want 1" |
| an unknown model accepted | — | the gateway's behavior | **as expected**: `TestChatUnknownModelIsAPIError`, all three formats, "Generate error = <nil>" |
| Responses' incomplete reason `max_tokens` | — | the gateway's translation | **as expected**: go-ai's `TestChatIncompleteAtMaxOutputTokens/responses` and infer's `TestChatIncompleteAtMaxTokens/responses` (both stream modes), `incomplete: max_tokens` |
| audio in a Responses request refused by the gateway | — | the gateway's error | **as expected** after the warm-up: 400 "failed to process LLM request: failed to parse Responses request: data did not match any variant of untagged enum InputParam" |
| the 16-token Messages stall on agent | — | the provider's or the gateway's behavior | **not seen**: infer's `TestChatIncompleteAtMaxTokens/messages` passed, both stream modes, in 0.26 s and 0.24 s |
| gpt-audio-mini refuses a text-only chat | — | the provider's error | **as expected**: each of the audio rerun's 4 warm-ups, 400 from Azure |
| `TestTranscribeChat` | — | pass after the warm-up | **pass** in go-ai's tier after the warm-up, and in infer's selection once the row was evicted |

One failure has moved, not changed. infer's `TestChatReasoningEffort` runs on vision at v0.2.0,
where priority's ran on agent. On vision through Messages, effort `low` gave 0 reasoning items
(both stream modes), where priority's agent gave the same through Messages: the gateway translates
a Messages request into Chat Completions for both deployments. The rows-down vision profile
declares no Messages efforts, so `none` ran there and passed; a `messages` member declaring the gap
would be the helper's, not go-ai's, and is left for the session.

No claimed fix still fails, so no pending edit for v1.ai.client comes of the revalidation (below).

### Step 5 · the retry proof (behaviors 6–8)

Each case ran with the rows up, through `retry_case`, with its overlay deployed through the deploy's
overlay mechanism and the base config deployed after it. No request went to Azure (the task's count
was unchanged at 18:45:06). Times below are local.

**Case a: rate-limit-agent.** Its first run, at 18:42:40, failed: 4 chats, each 200, each carrying
the go-ai key's own bucket (`x-ratelimit-limit: 1200`), and none refused. The overlay was the
probe's own bug, not go-ai's: it attached a top-level policy to route `default/agent`, and since
priority the route has its own `localRateLimit` (&key-rates, the per-key buckets), which takes its
place. The fix, in
[`probes/rate-limit-agent.yaml`](../../gateway/agentgateway/probes/rate-limit-agent.yaml): the
probe's bucket, 2 requests refilled every 10 s with no key, is the first entry of the route's own
`conditional` list, with the condition `'true'`, so every request draws on it. Its first form, with
no condition, failed the deploy's validation at 18:43:43 ("conditional policy entries without
condition must be last"), so nothing was moved into place and the second run, at 18:43:43, ran
against the earlier copy and failed the same way. The vision and audio routes alias &key-rates, so
the probe limits them too, each route with its own bucket; the case sends to agent alone. Deployed
and validated at 18:43:57, the case passed at 18:44:03:

| Call | Attempt | Start | Reply | Gap after the last reply | Status | Retry-After | x-ratelimit-limit / remaining / reset |
| --- | --- | --- | --- | --- | --- | --- | --- |
| chat-1 | 1 | 18:44:03.854 | 824 ms | | 200 | | 2 / 1 / 4 |
| chat-2 | 1 | 18:44:04.679 | 805 ms | | 200 | | 2 / 0 / 3 |
| chat-3 | 1 | 18:44:05.484 | 2 ms | | 429 | 2 | 2 / 0 / 2 |
| chat-3 | 2 | 18:44:07.488 | 2 ms | 2,001 ms | 429 | 1 | 2 / 0 / 0 |
| chat-3 | 3 | 18:44:08.490 | 823 ms | 1,000 ms | 200 | | 2 / 1 / 9 |

The access log (from 18:44:03) holds the same five lines: `route=default/agent
endpoint=gb10-1:8000 http.status=200` twice, `http.status=429 retry_after="2"` and
`http.status=429 retry_after="1"`, each with no endpoint, and a last 200 from `gb10-1:8000`.
`requests_shed` read 0 before and after.

The wait of exactly the Retry-After, 2 s, came back to a bucket not yet refilled, and a second
429 said 1 s more. The bucket's Retry-After reads as the whole seconds to the refill, rounded down,
so a client that waits exactly that long can be refused once more; the times above bear this out,
and the source wasn't read. infer's 3 attempts absorbed it here, with none to spare.

**Case b: embedding-burst** (the base config, `# overlays: none`), at 18:44:24. Of 40 embeddings
sent at once, 34 were admitted and 6 refused 429 with `Retry-After: 1` and `x-ratelimit-limit: 34`
(`embed-15`, `-20`, `-23`, `-32`, `-34`, `-36`). Each was retried 1,000 ms after its reply and
answered 200. Every call ended 200; the test passed. The access log from 18:44:24: 40 lines
`route=default/embedding endpoint=framework:8002 http.status=200` and 6 lines `http.status=429
retry_after="1"`. `requests_shed` read 0 before and after.

**Case c: in-flight-1**, at 18:44:38:

| Call | Attempt | Start | Reply | Gap after the last reply | Status | Retry-After | Body marker |
| --- | --- | --- | --- | --- | --- | --- | --- |
| held | 1 | 18:44:38.272 | 11 ms | | 200 | | |
| second | 1 | 18:44:38.418 | 2 ms | | 503 | none | `request limit exceeded` |
| second | 2 | 18:44:38.567 | 851 ms | 146 ms | 200 | | |

The held stream was released on the second's 503, and the retry, after go-ai's backoff of 146 ms,
was admitted. The access log from 18:44:38 holds two lines, both 200 from `gb10-1:8000`, the held
stream's (`duration=197ms`) and the retry's, and none for the 503. `requests_shed` read 0 before and
1 after: the one refusal.

**Case d: bulk-rate-low**, with the bulk key, at 18:44:52:

| Call | Attempt | Start | Reply | Status | Retry-After | x-ratelimit-limit / remaining / reset |
| --- | --- | --- | --- | --- | --- | --- |
| chat-1 | 1 | 18:44:52.880 | 852 ms | 200 | | 2 / 1 / 59 |
| chat-2 | 1 | 18:44:53.733 | 885 ms | 200 | | 2 / 0 / 59 |
| chat-3 | 1 | 18:44:54.618 | 1 ms | 429 | 58 | 2 / 0 / 58 |

chat-3's Retry-After, 58 s, is past infer's 30 s most, so go-ai returned the 429 at once, after one
attempt, its `APIError` holding the wait; the test passed. The access log from 18:44:52: two 200s
from `gb10-1:8000` and `http.status=429 retry_after="58"`. `requests_shed` read 1 before and after.

| Case | Overlay | Result | Gateway's refusals | Cross-check |
| --- | --- | --- | --- | --- |
| a. rate-limit-agent | rate-limit-agent (fixed) | pass | 429 ×2, Retry-After 2 then 1, `x-ratelimit-*`; the call's third attempt 200 | access log: `retry_after="2"`, `retry_after="1"`; `requests_shed` 0 → 0 |
| b. embedding-burst | none | pass | 429 ×6, Retry-After 1, `x-ratelimit-*`; each retry 200 | access log: 6 × `retry_after="1"`, 40 × 200; `requests_shed` 0 → 0 |
| c. in-flight-1 | in-flight-1 | pass | 503 ×1, `request limit exceeded`, no Retry-After; the retry 200 | access log: no line for the 503; `requests_shed` 0 → 1 |
| d. bulk-rate-low | bulk-rate-low | pass | 429 ×1, Retry-After 58, returned at once after 1 attempt | access log: `retry_after="58"`; `requests_shed` 1 → 1 |

No run's log shows a header timeout or an idle close. Each run's helper found no key in its log or
its table. A plain deploy at 18:45:00 left the base config live (`# overlays: none`).

### The Azure count (behavior 17)

Counted from the access log after each step that can overflow:

| Step | Azure-answered | Toward the cap |
| --- | --- | --- |
| step 2, rows up, 18:38:21–18:39:49 | 0 | 0 |
| step 3, the priority rerun, from 18:40:15 | 42 (agent 30: 200 ×21, 400 ×9; vision 11: 200 ×11; audio 1: 200 ×1) | 42 |
| step 3, the audio rerun, from 18:41:14 | 6 (audio: 400 ×5, 200 ×1) | 6 |
| step 5, the retry cases | 0 | 0 |
| total, from 18:38:00 to 18:45:06 | 48 (2xx ×34, 400 ×14) | 48 of 80 |

Azure answered no 429. As in priority, one of the audio rerun's 400s is the gateway's own refusal
of `TestAudioInResponsesRefused`'s request, logged against the Azure provider and marked as
overflow though it never reached Azure, so the total overstates Azure's by one, on the cap's safe
side. Only synthetic and test-fixture content was sent: the tiers' prompts and fixtures
(`shapes.png`, `phrase.wav`) and the helpers' prompts. The helper's printed cap read 300,
priority's, until this slice set it to 80; each step's count is the same either way.

## Slice 2 · traces

Behaviors 9–12, with 17 and 18: the Collector, Tempo, and Grafana beside the gateway, agentgateway's
spans, the rows' spans through spike-model-engines' `host/`, and the overflow's trace. Measured
19:10:59–19:18:12, every command under "Commands as run". The `traces` helper prints each span's
service, name, kind, ids, parent, and duration, and its attribute keys, never their values; a span
named for a host under `azure.com` shows it as `<azure host>`.

### The deploy (behaviors 9, 10)

`mise run agentgateway-deploy` at 19:10:59 copied the three new service groups and the config with
`config.tracing`, and brought the stack up by 19:11:30: `gateway-otel-collector-1`,
`gateway-tempo-1`, and `gateway-grafana-1` (healthy) added, agentgateway recreated with tracing,
Postgres left running. The Collector and Tempo have no health check (their images have no shell),
so their state is `running`. Grafana is reached through `mise run gateway:grafana`, which tunnels
localhost:3002 ([`mise.toml`](../../mise.toml)); the architect has used it.

### The gateway's spans (behavior 10)

One keyed request per alias at 19:11:35–19:11:36, each 200. Each alias's trace had 2 spans, both
agentgateway's: its server span `POST /<alias>/v1/*`, and beneath it its client span
`POST <row host>:<port>` to the row. The agent's was `5a45e7cc054294179cc163ff451ab24d`.

### The rows' spans (behavior 11)

spike-model-engines' pull request #20, merged as `6ce3210`, adds the rows' optional tracing:
`VLLM_TRACE=on` points the row at the Collector on gb10-2, resolved at run time, with service name
`vllm-<alias>`, detailed traces off. At 19:13:08 the session pulled `6ce3210` on each host and ran
`host/engines vllm update` with `VLLM_TRACE=on` for each of the four rows, the Framework's two in
turn; no host was rebooted. Each update returned in under 3 s, and all four rows answered `/health`
200 by 19:14:32 (`gb10-1:8000`, `gb10-2:8000`, `framework:8001`, `framework:8002`). Each
update's output is in `.state/answer/restart-<host>.log`, untracked.

### Traces through each row (behavior 12)

One keyed request per alias at 19:14:38–19:14:41, each 200. Each trace had 3 spans, the row's span
the child of the gateway's client span, carried by traceparent:

```text
agentgateway "POST /<alias>/v1/*"          server, root
  agentgateway "POST <row host>:<port>"    client
    vllm-<alias> "llm_request"             server, parent the gateway's client span
```

| Alias | Trace | Gateway server span | Row's `llm_request` |
| --- | --- | --- | --- |
| agent | `926cce9c743b3282b84dd00843be70b0` | 1251.6 ms | 1022.7 ms |
| vision | `debc01ce0bf1314b751d2c83b03c54ba` | 120.9 ms | 116.0 ms |
| audio | `34e23b7c861e7d4ede07d7acb9844be8` | 2264.2 ms | 2257.0 ms |
| embedding | `266b7f194bec460e8f26e6c1ae390bf1` | 34.2 ms | 26.6 ms |

The Framework's two row spans start a few ms before their parent client span by the hosts' clocks,
so the helper, which orders by start time, prints them first; their parent is still the gateway's
client span. The skew is between the Framework's clock and gb10-2's, not in the link.

**The attribute keys.** Read from the four traces, keys only:

- **The row's `llm_request`:** `gen_ai.latency.time_to_first_token`, `gen_ai.latency.e2e`,
  `gen_ai.latency.time_in_queue`, `gen_ai.latency.time_in_model_prefill`,
  `gen_ai.latency.time_in_model_decode`, `gen_ai.latency.time_in_model_inference`,
  `gen_ai.usage.prompt_tokens`, `gen_ai.usage.completion_tokens`, `gen_ai.request.id`, and on a chat
  `gen_ai.request.top_p`, `gen_ai.request.max_tokens`, `gen_ai.request.temperature`,
  `gen_ai.request.n` (the embedding's has none of the four).
- **The gateway's server span:** `gateway`, `listener`, `route`, `endpoint`, `client.address`,
  `network.protocol.version`, `trace.id`, `span.id`, `protocol`, `gen_ai.operation.name`,
  `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.response.model`,
  `gen_ai.usage.input_tokens`, on a chat `gen_ai.usage.output_tokens`,
  `gen_ai.usage.reasoning_tokens`, `gen_ai.request.max_tokens`, then `duration`, `url.scheme`,
  `http.request.method`, `http.response.status_code`, `url.path`, `server.address`, `server.port`.
- **The gateway's client span:** `agentgateway.outbound.kind`, `agentgateway.outbound.subtype`,
  `http.host`, `http.path`, `http.status`, `http.method`.

No span holds a prompt or completion key: no `gen_ai.prompt`, `gen_ai.completion`,
`gen_ai.input.messages`, `gen_ai.output.messages`, or any other content key, on the gateway's spans
or the rows'. The values aren't printed: `client.address` holds the caller's address, and on an
overflow `endpoint` and `http.host` name the Azure account's host.

### The rows' startup traces and cold start

Each row's restart also sent a startup trace, rooted at `Overall Loading`, with its engine's init
beneath it: `AsyncMPClient init`, `EngineCoreProc init`, `Executor init` (`Worker init`,
`Init device`, `Load model` with `Initialize model` and `Load weights`), and `Prepare model`
(`Allocate KV cache`, `Warmup (GPU)`). Read at 19:16:19–19:16:20 with
`traces -q '{ resource.service.name = "vllm-<alias>" && name = "Overall Loading" }'`, each span's
duration its end less its start:

| Row | Trace | Overall Loading | Load model | Load weights | Prepare model | Allocate KV cache | Warmup (GPU) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| agent, gb10-1 | `6ae3ac2b23a72439228f84730f0670c8` | 46.2 s | 27.5 s | 17.8 s | 11.9 s | 1.4 s | 8.7 s |
| vision, gb10-2 | `ff0f8fd83322cd4c40df6d45da3e1ae3` | 31.3 s | 4.9 s | 2.8 s | 19.6 s | 0.0 s | 4.1 s |
| audio, Framework | `2f83559cd51522a751d109859480ca18` | 50.0 s | 2.7 s | 1.3 s | 37.4 s | 0.0 s | 20.5 s |
| embedding, Framework | `886b292c21953dc3860e0fd8bf45db64` | 13.0 s | 1.2 s | 0.3 s | 3.1 s | 0.0 s | 3.1 s |

Every row's weights were cached: `Download weights - HF` took 0.1–0.2 s. The agent's cold start is led by
its weights' load; vision's and audio's are mostly `Prepare model` outside the spans beneath it
(15.6 s and 16.9 s that neither KV cache allocation nor warmup accounts for). `Overall Loading`
covers the engine's startup from its client's init, not the container's start before it. One
restart each, so one sample per row.

### The overflow trace (behaviors 12, 17)

With the base config's baseline read (Azure: 0 since 19:00), `mise run agentgateway-deploy rows-down`
at 19:16:47, then exactly one keyed agent chat ("Say OK.", `max_tokens` 32) at 19:16:49 and one
embedding ("hello") at 19:16:50, then `mise run agentgateway-deploy` at 19:16:51 removed the
overlay. Both answered 200 with `x-gateway-overflow: azure`. At 19:17:10–19:17:12 one request per
alias answered 200 with no overflow header, and the access log named each row as its endpoint (the
first read's pattern, at 19:17:12, matched no line; the second, at 19:17:30, is the one quoted):
`gb10-1:8000`, `gb10-2:8000`, `framework:8001`, `framework:8002`. No row stayed evicted.

Each overflow trace had 4 spans, all agentgateway's, and no `vllm-*` span:

```text
trace 2a8fd3f06a9ab9e3e1f8d32c877edf19 (agent)
  agentgateway "POST /agent/v1/*"         server, root      753.2 ms
    agentgateway "POST gb10-1:8009"       client, error.type  1.7 ms
    agentgateway "POST gb10-1:8009"       client, error.type  2.0 ms
    agentgateway "POST <azure host>:443"  client, http.status 706.0 ms
trace 5b24fe0838f97333fc467f8189785d40 (embedding)
  agentgateway "POST /embedding/v1/*"     server, root      278.1 ms
    agentgateway "POST framework:8009"    client, error.type  1.2 ms
    agentgateway "POST framework:8009"    client, error.type  1.9 ms
    agentgateway "POST <azure host>:443"  client, http.status 232.4 ms
```

Each retried attempt is its own client span under the one server span: two refused connections to
the overlay's closed port, 8009, carrying `error.type` in place of `http.status`, then Azure's. The
server span adds `retry.attempt` to the keys above; the embedding's also carries
`gen_ai.embeddings.dimension.count` and agentgateway's cost keys, `agw.ai.usage.cost.*` (`total`,
`input`, `output`, `cache_read`, `cache_write`, `reasoning`, `input_audio`, `output_audio`, `pages`,
`audio_duration`). No content key, here either.

### The unattended restart (behavior 9)

At 19:17:44, `docker restart gateway-otel-collector-1 gateway-tempo-1 gateway-grafana-1` on gb10-2,
no root. By 19:17:59 the Collector and Tempo were `running` and Grafana `running healthy`. At
19:18:07–19:18:08 one request per alias answered 200 from its row, and each trace was whole, 3 spans
with the row's `llm_request` under the gateway's client span: agent
`cea3f3ad7550397f1ae06d12f6b8cbd4`, vision `ac004c2048f1f264e928ba6ea1cd8efe`, audio
`ad3599374da129f37ffebaf7533626dc`, embedding `bdfa6219b5a739635ab55dbd0c9a6dbd`.

Every container of the gateway's compose project restarts unless stopped (`docker inspect`,
19:18:12): `agentgateway`, `gateway-postgres-1`, `gateway-otel-collector-1`, `gateway-tempo-1`, and
`gateway-grafana-1`, each `unless-stopped`. gb10-2 wasn't rebooted after these three services were
added: the evidence that the stack comes back with the host unattended is their restart policy,
the same as agentgateway's and Postgres's; agentgateway came back by itself after gb10-2's firmware
reboot, answering the 18:36 smoke check before any deploy ("The hosts").

### The Azure count, slice 2

| Step | Azure-answered | Toward the cap |
| --- | --- | --- |
| before the overflow, 19:00:00–19:16:37 | 0 | 0 |
| the overflow trace, from 19:16:47 (read 19:17:00 and again at 19:17:40) | 2 (agent: 200 ×1; embedding: 200 ×1) | 2 |
| the task's total, slices 1 and 2 | 50 (2xx ×36, 400 ×14) | 50 of 80 |

Azure answered no 429. The second read, after the rows' check, still counted 2: no check request
overflowed.

### For production

- **The OTLP port takes unauthenticated spans from the tailnet.** The Collector's 4317 is published
  on gb10-2's tailnet address with no authentication, so any tailnet host can send it spans. A
  production deployment needs the receiver authenticated (mTLS or a bearer token), or bound where
  only the gateway and the rows reach it.
- **Sampling is at 100%.** agentgateway's `randomSampling` is `"true"`, every request, and every
  row traces every request. Right for a spike's few requests; production lowers it to a ratio, or
  samples at the Collector by tail.

## Slice 4 · walkthrough

The architect runs the walkthrough from the repository root on the laptop, one step at a time, in
the base config (`# overlays: none`) with every row up and traced. Every command goes through the
helpers, so each lands in `.state/answer/commands-<date>.log`. Each step's expected result comes
from slices 1–3. No step sends a request to Azure: nothing deploys an overlay, every row answers
its own alias, and steps 2 and 4 read `azure_count` to show it. The task's Azure count stays at 50
of 80. A reply carrying `x-gateway-overflow: azure`, or an `azure_count` above 0, stops the walk for
the session to escalate.

1. **Source the helpers.** This starts the day's command log and marks the walk's start, for
   `azure_count`.

   ```sh
   source scripts/clients-lib.sh
   W0=$(date -Iseconds)
   ```

   Expected: one line, `+ <time> laptop: source scripts/clients-lib.sh`.

2. **The rows-up tier at v0.2.0.** infer's integration tier, the shorter of the two (about 25 s,
   against go-ai's minute), from the worktree at `tools/infer/v0.2.0`, through the gateway on all
   four aliases, with each alias's rows-up profile. A tier names each run once, so a second try
   takes a new name. If `.state/answer/go-ai` is gone, `goai_checkout` makes it first.

   ```sh
   CLIENTS_TARGET=rows-up infer_tier walk-up-infer agent vision audio embedding
   azure_count "$W0"
   ```

   Expected:
   - the tier's `go test -v` output, then its three summary lines: `walk-up-infer: exit 0`,
     `walk-up-infer: the key is not in .state/answer/clients/walk-up-infer.log`, and
     `walk-up-infer: 19 passed, 0 failed, 1 skipped (top-level tests)`, as in slice 1's step 2;
   - the one skip is `TestTranscribeRoute`: transcription's own route, which no row serves
     (`grep -- '--- SKIP' .state/answer/clients/walk-up-infer.log` shows it, with the subtests'
     skips);
   - `azure_count`: `Azure answered 0 requests`, each alias 0, and `toward the cap of 80: 0`, 429
     0.

3. **One retry case: embedding-burst.** go-ai v0.2.0, at infer's default policy, sends 40
   embeddings at once against the embedding route's own bucket, 34 a second. The case needs no
   overlay: the bucket is the base config's, and the helper refuses to run unless the deployed
   copy's first line reads `# overlays: none`. Every request goes to the embedding row.

   ```sh
   W3=$(date -Iseconds)
   requests_shed
   retry_case embedding-burst
   logged "cut -f2,5,6,7 $(ls -t .state/answer/retry/embedding-burst-*.tsv | head -1) | sort | uniq -c"
   logged "ssh -n gb10-2 'docker logs --since $W3 agentgateway 2>&1' | grep -E '[[:space:]]request ' | grep -oE '(route=[^ ]+|endpoint=[^ ]+|http.status=[0-9]+|retry_after=[^ ]+)' | paste -sd' ' | sed -E 's/ (route=)/\n\1/g' | sort | uniq -c"
   requests_shed
   ```

   Expected:
   - `requests_shed`: `agentgateway_requests_shed_total{bind="bind/3000"} <n>` (0 when this was
     written);
   - `retry_case`: `# overlays: none`, the test's per-attempt table, `--- PASS:
     TestEmbeddingBurst`, then `embedding-burst: exit 0` and the key found in neither the log nor
     the table;
   - the table's count, its columns attempt, gap in ms, status, and Retry-After: `34 1 200`, the
     burst's first attempts admitted; `6 1 429 1`, the rest refused with `Retry-After: 1`; and
     `6 2 1000 200`, each refused call retried 1,000 ms after its 429 and answered 200 (a gap a ms
     or two longer splits that line; the test fails any retry sooner than its Retry-After); plus
     the header's own line. Which 6 calls are refused varies;
   - the access log: `40 route=default/embedding endpoint=framework:8002 http.status=200`, the 34
     and the 6 retries, and `6 route=default/embedding http.status=429 retry_after="1"`, the
     gateway's own refusals, with no endpoint;
   - `requests_shed`: the same `<n>` as before. A bucket's 429 isn't a shed request.

4. **A trace in Grafana.** Grafana is published on gb10-2's loopback only and reached through an
   SSH tunnel. In a second terminal, from the repository root:

   ```sh
   source scripts/clients-lib.sh
   logged "mise run gateway:grafana"
   ```

   The tunnel holds its terminal and prints nothing. Open http://localhost:3002 (no login), then
   Explore, with the Tempo datasource. In the first terminal, one agent request:

   ```sh
   gw_curl architect -sS -m 120 -o /dev/null -w 'agent %{http_code}\n' -H 'Content-Type: application/json' -d '{"model":"agent","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}' "$(gw_base agent)/chat/completions"
   ```

   Expected: `agent 200`.

   In Explore, the TraceQL query, over the last 15 minutes:

   ```text
   { resource.service.name = "vllm-agent" && name = "llm_request" }
   ```

   Open the newest trace. Expected:
   - three nested spans: agentgateway `POST /agent/v1/*`, the server span and root; beneath it
     agentgateway `POST gb10-1:8000`, the client span to the row; and beneath that vllm-agent
     `llm_request`, the row's span;
   - the `llm_request` span's attributes include `gen_ai.latency.time_to_first_token`,
     `gen_ai.latency.e2e`, `gen_ai.latency.time_in_queue`, and the other `gen_ai.latency.*`, with
     `gen_ai.usage.*` and `gen_ai.request.*`, and no prompt or completion attribute
     (`gen_ai.prompt`, `gen_ai.completion`, or a message key), as in slice 2.

   Grafana shows attribute values, which the helper doesn't: record no address it shows, such as
   the gateway span's `client.address`. The same trace from the first terminal, keys only:

   ```sh
   traces -q '{ resource.service.name = "vllm-agent" && name = "llm_request" }' -n 1
   azure_count "$W0"
   ```

   Expected:
   - `trace <id>: 3 spans, services agentgateway, vllm-agent`, the same id as Grafana's, then the
     three spans indented by parent: `agentgateway "POST /agent/v1/*" server ... parent none
     (root)`, `agentgateway "POST gb10-1:8000" client`, and `vllm-agent "llm_request" server ...
     parent <the client span's id> (agentgateway)`, each with its duration;
   - the `llm_request` line's keys: `gen_ai.latency.*`, `gen_ai.usage.prompt_tokens`,
     `gen_ai.usage.completion_tokens`, `gen_ai.request.*`, and no content key;
   - `azure_count`: 0 for the whole walk.

   Then Ctrl-C in the second terminal to close the tunnel.

5. **The answer, on paper.** Read [`docs/gateway.md`](../gateway.md), "Requirements for
   v1.ai.hosting" and "Priority's gaps", and the README's "The answer"
   ([`README.md`](../../README.md#the-answer)). Nothing runs.

   Expected: the reader can name, from the documents alone:
   - **the overflow rule:** agent and vision only, each to its own Foundry deployment while its row
     is evicted; never audio, never embedding, and never under IL6 (requirement 8);
   - **the embedding 429 rule:** past 34 requests a second, embedding answers 429 with
     `Retry-After: 1` and the client waits; nothing queues or overflows (requirement 6), as step 3
     showed;
   - **the gaps:** admission on `/metrics`, on paper (requirement 14), and priority's gaps: the
     fixed-hour budget window, priority ordering only the waiting queue, the queue limit counting
     every key alike, eviction's uncapped growth, the 64 KiB retry buffer, the UI's links, and the
     route `ai` deprecation risk.

### Results

Not run. The architect waived the walkthrough on 2026-11-18, having followed each slice live: the
post-update smoke check, the Collector's walk with the gateway-only and three-span traces read in
Grafana, and each slice's results as they landed. The steps above stay as the way to repeat it.
Each one's Expected line comes from a run already recorded in this finding: step 2 from slice 1's
rows-up tiers, step 3 from the embedding-burst retry case, and step 4 from slice 2's traces. No
request went to Azure for the walk, and the task's count stays at 50 of 80.

## Commands as run

Every command the log holds, as logged, with its time, from `.state/answer/commands-2026-11-18.log`.
The output stays there, untracked. The architect's host updates and the session's four host reads
(18:11–18:34) ran outside the helpers, so they aren't here. Each `mise run agentgateway-deploy` line
is followed by the deploy's own `+` lines, appended to the log by `logged`. The helpers log curl's
arguments joined by spaces, so a JSON body shows without its shell quotes.

### 2026-11-18 · the post-update smoke check

```text
+ 2026-11-18T18:35:59-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:36:06-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:36:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 20 http://gb10-2:3000/agent/v1/models
+ 2026-11-18T18:36:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 20 http://gb10-2:3000/vision/v1/models
+ 2026-11-18T18:36:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 20 http://gb10-2:3000/audio/v1/models
+ 2026-11-18T18:36:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 20 http://gb10-2:3000/embedding/v1/models
+ 2026-11-18T18:36:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D .state/answer/smoke-vision.hdr -o .state/answer/smoke-vision.json http://gb10-2:3000/vision/v1/chat/completions -H content-type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}
+ 2026-11-18T18:36:06-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 30 http://gb10-2:3000/embedding/v1/embeddings -H content-type: application/json -d {"model":"embedding","input":"hello"}
```

### 2026-11-18 · step 1: the helpers' clients, the stack's deploy, and its checks

```text
+ 2026-11-18T18:37:16-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:37:16-05:00 laptop: git -C ~/architecture/go-ai worktree add --detach .state/answer/go-ai tools/infer/v0.2.0
+ 2026-11-18T18:37:17-05:00 laptop: GOBIN=.state/answer/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.2.0 && .state/answer/bin/infer version
+ 2026-11-18T18:37:52-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:37:52-05:00 laptop: GOBIN=.state/answer/bin go install github.com/standards-lab/go-ai/tools/infer/cmd/infer@v0.2.0 && .state/answer/bin/infer version
+ 2026-11-18T18:37:58-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:37:58-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-18T18:37:58-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:37:58-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:37:58-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:37:58-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:37:58-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:37:58-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:37:58-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:37:58-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:37:58-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:38:12-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:38:16-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:38:16-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 20 http://gb10-2:3000/agent/v1/models
+ 2026-11-18T18:38:16-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 20 http://gb10-2:3000/vision/v1/models
+ 2026-11-18T18:38:16-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 20 http://gb10-2:3000/audio/v1/models
+ 2026-11-18T18:38:16-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 20 http://gb10-2:3000/embedding/v1/models
+ 2026-11-18T18:38:16-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
```

### 2026-11-18 · step 2: the rows-up tiers

```text
+ 2026-11-18T18:38:21-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:38:21-05:00 laptop: CLIENTS_TARGET=rows-up goai_tier a1-up-goai agent vision audio embedding
+ 2026-11-18T18:38:21-05:00 laptop: cd .state/answer/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AGENT_PROFILE='{"completions":{"refused_efforts":["none","minimal","xhigh","max"],"no_allowed_tools":true},"responses":{"refused_efforts":["none","xhigh"],"no_allowed_tools":true,"resend_reasoning_text":true},"messages":{"refused_efforts":["none","xhigh","max"]}}' AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/answer/clients/a1-up-goai.log
+ 2026-11-18T18:39:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:39:22-05:00 laptop: CLIENTS_TARGET=rows-up infer_tier a1-up-infer agent vision audio embedding
+ 2026-11-18T18:39:22-05:00 laptop: cd .state/answer/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AGENT_PROFILE='{"completions":{"refused_efforts":["none","minimal","xhigh","max"],"no_allowed_tools":true},"responses":{"refused_efforts":["none","xhigh"],"no_allowed_tools":true,"resend_reasoning_text":true},"messages":{"refused_efforts":["none","xhigh","max"]}}' AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v ./integration/... 2>&1 | tee .state/answer/clients/a1-up-infer.log
+ 2026-11-18T18:39:49-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:39:49-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:38:21-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-18 · step 3: the rows-down overlay, the priority rerun, the audio rerun, and back to the rows

```text
+ 2026-11-18T18:40:15-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:40:15-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:38:00-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-18T18:40:15-05:00 laptop: mise run agentgateway-deploy rows-down
+ 2026-11-18T18:40:15-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:40:15-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:40:15-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:40:15-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:40:15-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:40:15-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:40:15-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:40:15-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:40:15-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:40:17-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:40:24-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:40:24-05:00 laptop: CLIENTS_TARGET=rows-down goai_tier -run '^(TestFunctionCallRoundTrip|TestStreamFunctionCall|TestReasoningRoundTrip|TestStreamReasoningRoundTrip|TestToolChoice|TestChatUnknownModelIsAPIError|TestStreamText|TestChatIncompleteAtMaxOutputTokens|TestAudioInResponsesRefused|TestTranscribeChat)$' a2-down-goai agent vision audio embedding
+ 2026-11-18T18:40:24-05:00 laptop: cd .state/answer/go-ai/. && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AGENT_PROFILE='{"completions":{"no_tool_choice_required":true}}' AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_PROFILE='{"completions":{"refused_efforts":["none","xhigh","max"]},"responses":{"refused_efforts":["none","xhigh"]}}' AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v -run '^(TestFunctionCallRoundTrip|TestStreamFunctionCall|TestReasoningRoundTrip|TestStreamReasoningRoundTrip|TestToolChoice|TestChatUnknownModelIsAPIError|TestStreamText|TestChatIncompleteAtMaxOutputTokens|TestAudioInResponsesRefused|TestTranscribeChat)$' ./integration/... 2>&1 | tee .state/answer/clients/a2-down-goai.log
+ 2026-11-18T18:40:35-05:00 laptop: CLIENTS_TARGET=rows-down infer_tier -run '^(TestChatReasoningEffort|TestChatImage|TestChatIncompleteAtMaxTokens|TestTranscribeChat)$' a2-down-infer agent vision audio embedding
+ 2026-11-18T18:40:35-05:00 laptop: cd .state/answer/go-ai/tools/infer && AI_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 AI_AGENT_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_AGENT_PROFILE='{"completions":{"no_tool_choice_required":true}}' AI_VISION_BASE_URL=http://gb10-2:3000/vision/v1 AI_VISION_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_VISION_PROFILE='{"completions":{"refused_efforts":["none","xhigh","max"]},"responses":{"refused_efforts":["none","xhigh"]}}' AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) AI_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 AI_EMBEDDING_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v -run '^(TestChatReasoningEffort|TestChatImage|TestChatIncompleteAtMaxTokens|TestTranscribeChat)$' ./integration/... 2>&1 | tee .state/answer/clients/a2-down-infer.log
+ 2026-11-18T18:41:07-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:41:07-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:40:15-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-18T18:41:14-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:41:14-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:41:14-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-18T18:41:14-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-18T18:41:14-05:00 laptop: CLIENTS_TARGET=rows-down goai_tier -run '^TestAudioInResponsesRefused$' a3-audio-TestAudioInResponsesRefused audio
+ 2026-11-18T18:41:14-05:00 laptop: cd .state/answer/go-ai/. && AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v -run '^TestAudioInResponsesRefused$' ./integration/... 2>&1 | tee .state/answer/clients/a3-audio-TestAudioInResponsesRefused.log
+ 2026-11-18T18:41:14-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-18T18:41:14-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Reply with the word ready."}],"max_completion_tokens":16} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-18T18:41:15-05:00 laptop: CLIENTS_TARGET=rows-down goai_tier -run '^TestTranscribeChat$' a3-audio-TestTranscribeChat audio
+ 2026-11-18T18:41:15-05:00 laptop: cd .state/answer/go-ai/. && AI_AUDIO_BASE_URL=http://gb10-2:3000/audio/v1 AI_AUDIO_TOKEN=$(<.state/agentgateway/keys/go-ai) GOWORK=off go test -race -tags integration -count=1 -v -run '^TestTranscribeChat$' ./integration/... 2>&1 | tee .state/answer/clients/a3-audio-TestTranscribeChat.log
+ 2026-11-18T18:41:17-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:41:14-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-18T18:41:24-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:41:24-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:40:15-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-18T18:41:25-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-18T18:41:25-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:41:25-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:41:25-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:41:25-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:41:25-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:41:25-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:41:25-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:41:25-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:41:25-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:41:27-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:41:27-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:41:33-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:41:33-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 60 -D - -o /dev/null -H Content-Type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Hi"}],"max_completion_tokens":8} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-18T18:41:33-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 60 -D - -o /dev/null -H Content-Type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Hi"}],"max_completion_tokens":8} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-18T18:41:33-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 60 -D - -o /dev/null -H Content-Type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Hi"}],"max_completion_tokens":8} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-18T18:41:34-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -sS -m 60 -D - -o /dev/null -H Content-Type: application/json -d {"model":"embedding","input":"ready"} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-18T18:41:39-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:41:39-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:41:25-05:00 agentgateway 2>&1' | grep -E '[[:space:]]request ' | grep -oE '(route=[^ ]+|gen_ai.provider.name=[^ ]+|endpoint=[^ ]+|http.status=[0-9]+|overflow=[^ ]+)' | paste -sd' ' | sed -E 's/ (route=)/\n\1/g'
```

### 2026-11-18 · step 5a: rate-limit-agent, with the overlay's fix

```text
+ 2026-11-18T18:42:37-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:42:37-05:00 laptop: mise run agentgateway-deploy rate-limit-agent
+ 2026-11-18T18:42:37-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:42:37-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:42:37-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:42:37-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:42:37-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:42:38-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:42:38-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:42:38-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:42:38-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:42:40-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:42:40-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:42:40-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:42:40-05:00 laptop: retry_case rate-limit-agent
+ 2026-11-18T18:42:40-05:00 laptop: cd retry && RETRY_CASE=rate-limit-agent RETRY_KEY_FILE=../.state/agentgateway/keys/go-ai RETRY_KEY_IN=bearer RETRY_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 RETRY_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 RETRY_TABLE=../.state/answer/retry/rate-limit-agent-20261118T184240.tsv go test -count=1 -timeout 5m -v -run '^TestRateLimitAgent$' . 2>&1 | tee .state/answer/retry/rate-limit-agent-20261118T184240.log
+ 2026-11-18T18:42:44-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:43:42-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:43:42-05:00 laptop: mise run agentgateway-deploy rate-limit-agent
+ 2026-11-18T18:43:42-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:43:42-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:43:43-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:43:43-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:43:43-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:43:43-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:43:43-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:43:43-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:43:43-05:00 laptop: retry_case rate-limit-agent
+ 2026-11-18T18:43:43-05:00 laptop: cd retry && RETRY_CASE=rate-limit-agent RETRY_KEY_FILE=../.state/agentgateway/keys/go-ai RETRY_KEY_IN=bearer RETRY_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 RETRY_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 RETRY_TABLE=../.state/answer/retry/rate-limit-agent-20261118T184343.tsv go test -count=1 -timeout 5m -v -run '^TestRateLimitAgent$' . 2>&1 | tee .state/answer/retry/rate-limit-agent-20261118T184343.log
+ 2026-11-18T18:43:47-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:43:57-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:43:57-05:00 laptop: mise run agentgateway-deploy rate-limit-agent
+ 2026-11-18T18:43:57-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:43:57-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:43:57-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:43:57-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:43:57-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:43:57-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:43:57-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:43:57-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:43:57-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:43:59-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:43:59-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:44:03-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:44:03-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:44:03-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:44:03-05:00 laptop: retry_case rate-limit-agent
+ 2026-11-18T18:44:03-05:00 laptop: cd retry && RETRY_CASE=rate-limit-agent RETRY_KEY_FILE=../.state/agentgateway/keys/go-ai RETRY_KEY_IN=bearer RETRY_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 RETRY_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 RETRY_TABLE=../.state/answer/retry/rate-limit-agent-20261118T184403.tsv go test -count=1 -timeout 5m -v -run '^TestRateLimitAgent$' . 2>&1 | tee .state/answer/retry/rate-limit-agent-20261118T184403.log
+ 2026-11-18T18:44:09-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:44:16-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:44:16-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:44:03-05:00 agentgateway 2>&1' | grep -E '[[:space:]]request ' | grep -oE '^[^ ]+|(route=[^ ]+|endpoint=[^ ]+|http.status=[0-9]+|retry_after=[^ ]+|overflow=[^ ]+)' | paste -sd' ' | sed -E 's/ ([0-9]{4}-[0-9]{2}-[0-9]{2}T)/\n\1/g'
```

### 2026-11-18 · step 5b: embedding-burst

```text
+ 2026-11-18T18:44:22-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:44:22-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-18T18:44:22-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:44:22-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:44:22-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:44:22-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:44:22-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:44:22-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:44:23-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:44:23-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:44:23-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:44:24-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:44:24-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:44:24-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:44:24-05:00 laptop: retry_case embedding-burst
+ 2026-11-18T18:44:24-05:00 laptop: cd retry && RETRY_CASE=embedding-burst RETRY_KEY_FILE=../.state/agentgateway/keys/go-ai RETRY_KEY_IN=bearer RETRY_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 RETRY_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 RETRY_TABLE=../.state/answer/retry/embedding-burst-20261118T184424.tsv go test -count=1 -timeout 5m -v -run '^TestEmbeddingBurst$' . 2>&1 | tee .state/answer/retry/embedding-burst-20261118T184424.log
+ 2026-11-18T18:44:26-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:44:31-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:44:31-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:44:24-05:00 agentgateway 2>&1' | grep -E '[[:space:]]request ' | grep -oE '(route=[^ ]+|endpoint=[^ ]+|http.status=[0-9]+|retry_after=[^ ]+)' | paste -sd' ' | sed -E 's/ (route=)/\n\1/g' | sort | uniq -c
```

### 2026-11-18 · step 5c: in-flight-1

```text
+ 2026-11-18T18:44:35-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:44:35-05:00 laptop: mise run agentgateway-deploy in-flight-1
+ 2026-11-18T18:44:35-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:44:35-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:44:35-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:44:35-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:44:35-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:44:35-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:44:36-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:44:36-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:44:36-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:44:37-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:44:37-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:44:38-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:44:38-05:00 laptop: retry_case in-flight-1
+ 2026-11-18T18:44:38-05:00 laptop: cd retry && RETRY_CASE=in-flight-1 RETRY_KEY_FILE=../.state/agentgateway/keys/go-ai RETRY_KEY_IN=bearer RETRY_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 RETRY_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 RETRY_TABLE=../.state/answer/retry/in-flight-1-20261118T184438.tsv go test -count=1 -timeout 5m -v -run '^TestInFlight1$' . 2>&1 | tee .state/answer/retry/in-flight-1-20261118T184438.log
+ 2026-11-18T18:44:39-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:44:44-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:44:44-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:44:38-05:00 agentgateway 2>&1' | grep -E '[[:space:]]request ' | grep -oE '(route=[^ ]+|endpoint=[^ ]+|http.status=[0-9]+|retry_after=[^ ]+|duration=[^ ]+)' | paste -sd' ' | sed -E 's/ (route=)/\n\1/g'
```

### 2026-11-18 · step 5d: bulk-rate-low, back to base, and the task's Azure count

```text
+ 2026-11-18T18:44:50-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:44:50-05:00 laptop: mise run agentgateway-deploy bulk-rate-low
+ 2026-11-18T18:44:50-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:44:50-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:44:50-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:44:50-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:44:50-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:44:50-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:44:50-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:44:50-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:44:50-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:44:52-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:44:52-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:44:52-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:44:52-05:00 laptop: retry_case bulk-rate-low
+ 2026-11-18T18:44:52-05:00 laptop: cd retry && RETRY_CASE=bulk-rate-low RETRY_KEY_FILE=../.state/agentgateway/keys/bulk RETRY_KEY_IN=bearer RETRY_AGENT_BASE_URL=http://gb10-2:3000/agent/v1 RETRY_EMBEDDING_BASE_URL=http://gb10-2:3000/embedding/v1 RETRY_TABLE=../.state/answer/retry/bulk-rate-low-20261118T184452.tsv go test -count=1 -timeout 5m -v -run '^TestBulkRateLow$' . 2>&1 | tee .state/answer/retry/bulk-rate-low-20261118T184452.log
+ 2026-11-18T18:44:54-05:00 laptop: ssh -n gb10-2 'curl -fsS --max-time 5 http://127.0.0.1:15020/metrics' | grep requests_shed
+ 2026-11-18T18:45:00-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:45:00-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:44:52-05:00 agentgateway 2>&1' | grep -E '[[:space:]]request ' | grep -oE '(route=[^ ]+|endpoint=[^ ]+|http.status=[0-9]+|retry_after=[^ ]+)' | paste -sd' ' | sed -E 's/ (route=)/\n\1/g'
+ 2026-11-18T18:45:00-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-18T18:45:00-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T18:45:00-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T18:45:00-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T18:45:00-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T18:45:00-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T18:45:00-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T18:45:00-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T18:45:00-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T18:45:00-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T18:45:02-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T18:45:02-05:00 laptop: ssh -n gb10-2 head -1 '~/gateway/agentgateway/config.yaml'
+ 2026-11-18T18:45:06-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:45:06-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T18:38:00-05:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-18 · the firmware history and the laptop's path

```text
+ 2026-11-18T18:45:32-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:45:32-05:00 laptop: for h in gb10-1 gb10-2; do echo "== $h"; ssh -n -o BatchMode=yes $h 'fwupdmgr get-history --json 2>/dev/null' | jq -r '.Devices[]? | [.Name, (.Releases[0].Version // "?"), .Version, (.Created // 0 | tostring)] | @tsv'; done
+ 2026-11-18T18:45:39-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:45:39-05:00 laptop: for h in gb10-1 gb10-2; do echo "== $h"; ssh -n -o BatchMode=yes $h 'fwupdmgr get-history --json 2>/dev/null' | jq -r '.Devices[]? | [.Name, .Version, (.Releases[0].Version // "?"), (.UpdateState // "?" | tostring), (.Modified // 0 | todate)] | @tsv'; done
+ 2026-11-18T18:45:43-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T18:45:43-05:00 laptop: for h in gb10-1 gb10-2 framework; do tailscale ping -c 1 $h | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?/<addr>/g"; done
```

### 2026-11-18 · slice 2: the deploy, the gateway's traces, the rows' restart with tracing, and their traces

```text
+ 2026-11-18T19:10:59-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:10:59-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-18T19:10:59-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T19:11:00-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env otel-collector.yml otel-collector tempo.yml tempo grafana.yml grafana | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T19:11:00-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T19:11:00-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T19:11:00-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T19:11:00-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T19:11:00-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T19:11:00-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T19:11:00-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T19:11:30-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T19:11:35-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:11:35-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -o /dev/null -w agent %{http_code}\n http://gb10-2:3000/agent/v1/chat/completions -H content-type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}
+ 2026-11-18T19:11:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -o /dev/null -w vision %{http_code}\n http://gb10-2:3000/vision/v1/chat/completions -H content-type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}
+ 2026-11-18T19:11:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -o /dev/null -w audio %{http_code}\n http://gb10-2:3000/audio/v1/chat/completions -H content-type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}
+ 2026-11-18T19:11:36-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 30 -o /dev/null -w embedding %{http_code}\n http://gb10-2:3000/embedding/v1/embeddings -H content-type: application/json -d {"model":"embedding","input":"hello"}
+ 2026-11-18T19:12:16-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\} --data-urlencode limit=6 --data-urlencode start=1795046236 --data-urlencode end=1795047136" | jq -r '.traces[].traceID'
+ 2026-11-18T19:12:17-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 3b48450499728072612a820326e18f1f a024b16c41f96a51b8ea9df635c85733 32ebe0f9e2529540b033c4eda491ea59 5a45e7cc054294179cc163ff451ab24d" | spans, parents, and attribute keys
+ 2026-11-18T19:12:57-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:13:08-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:13:08-05:00 laptop: ssh -n gb10-1 "cd ~/repos/spike-model-engines && git pull -q --ff-only && git log --oneline -1 && time VLLM_TRACE=on VLLM_MODEL=gpt-oss-120b-agent-fp8 host/engines vllm update" > .state/answer/restart-gb10-1.log 2>&1 & ssh -n gb10-2 "cd ~/repos/spike-model-engines && git pull -q --ff-only && git log --oneline -1 && time VLLM_TRACE=on VLLM_MODEL=gemma-4-26B-A4B-NVFP4-vision-gb10 host/engines vllm update" > .state/answer/restart-gb10-2.log 2>&1 & ssh -n framework "cd ~/repos/spike-model-engines && git pull -q --ff-only && git log --oneline -1 && time VLLM_TRACE=on VLLM_MODEL=gemma-4-E4B-it-audio-framework host/engines vllm update && time VLLM_TRACE=on VLLM_MODEL=granite-embedding-english-r2-framework host/engines vllm update" > .state/answer/restart-framework.log 2>&1 & wait; for h in gb10-1 gb10-2 framework; do echo "== $h"; tail -6 .state/answer/restart-$h.log; done
+ 2026-11-18T19:14:38-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:14:38-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -o /dev/null -w agent %{http_code}\n http://gb10-2:3000/agent/v1/chat/completions -H content-type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}
+ 2026-11-18T19:14:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -o /dev/null -w vision %{http_code}\n http://gb10-2:3000/vision/v1/chat/completions -H content-type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}
+ 2026-11-18T19:14:39-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -o /dev/null -w audio %{http_code}\n http://gb10-2:3000/audio/v1/chat/completions -H content-type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32}
+ 2026-11-18T19:14:41-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 30 -o /dev/null -w embedding %{http_code}\n http://gb10-2:3000/embedding/v1/embeddings -H content-type: application/json -d {"model":"embedding","input":"hello"}
+ 2026-11-18T19:15:26-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\} --data-urlencode limit=4 --data-urlencode start=1795046426 --data-urlencode end=1795047326" | jq -r '.traces[].traceID'
+ 2026-11-18T19:15:27-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 266b7f194bec460e8f26e6c1ae390bf1 926cce9c743b3282b84dd00843be70b0 2f83559cd51522a751d109859480ca18 6ae3ac2b23a72439228f84730f0670c8" | spans, parents, and attribute keys
+ 2026-11-18T19:15:33-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:15:33-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ resource.service.name\ =\ \"vllm-vision\"\ \&\&\ name\ =\ \"llm_request\"\ \} --data-urlencode limit=1 --data-urlencode start=1795046433 --data-urlencode end=1795047333" | jq -r '.traces[].traceID'
+ 2026-11-18T19:15:33-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh debc01ce0bf1314b751d2c83b03c54ba" | spans, parents, and attribute keys
+ 2026-11-18T19:15:33-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ resource.service.name\ =\ \"vllm-audio\"\ \&\&\ name\ =\ \"llm_request\"\ \} --data-urlencode limit=1 --data-urlencode start=1795046433 --data-urlencode end=1795047333" | jq -r '.traces[].traceID'
+ 2026-11-18T19:15:34-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 34e23b7c861e7d4ede07d7acb9844be8" | spans, parents, and attribute keys
```

### 2026-11-18 · slice 2: the startup traces

```text
+ 2026-11-18T19:16:19-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:16:19-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ resource.service.name\ =\ \"vllm-agent\"\ \&\&\ name\ =\ \"Overall\ Loading\"\ \} --data-urlencode limit=2 --data-urlencode start=1795036579 --data-urlencode end=1795047379" | jq -r '.traces[].traceID'
+ 2026-11-18T19:16:19-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 6ae3ac2b23a72439228f84730f0670c8" | spans, parents, and attribute keys
+ 2026-11-18T19:16:19-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ resource.service.name\ =\ \"vllm-vision\"\ \&\&\ name\ =\ \"Overall\ Loading\"\ \} --data-urlencode limit=2 --data-urlencode start=1795036579 --data-urlencode end=1795047379" | jq -r '.traces[].traceID'
+ 2026-11-18T19:16:19-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh ff0f8fd83322cd4c40df6d45da3e1ae3" | spans, parents, and attribute keys
+ 2026-11-18T19:16:19-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ resource.service.name\ =\ \"vllm-audio\"\ \&\&\ name\ =\ \"Overall\ Loading\"\ \} --data-urlencode limit=2 --data-urlencode start=1795036579 --data-urlencode end=1795047379" | jq -r '.traces[].traceID'
+ 2026-11-18T19:16:19-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 2f83559cd51522a751d109859480ca18" | spans, parents, and attribute keys
+ 2026-11-18T19:16:20-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ resource.service.name\ =\ \"vllm-embedding\"\ \&\&\ name\ =\ \"Overall\ Loading\"\ \} --data-urlencode limit=2 --data-urlencode start=1795036580 --data-urlencode end=1795047380" | jq -r '.traces[].traceID'
+ 2026-11-18T19:16:20-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 886b292c21953dc3860e0fd8bf45db64" | spans, parents, and attribute keys
```

### 2026-11-18 · slice 2: the overflow trace, back to the rows, and the Azure count

```text
+ 2026-11-18T19:16:37-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:16:37-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T19:00:00 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-18T19:16:47-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:16:47-05:00 laptop: mise run agentgateway-deploy rows-down
+ 2026-11-18T19:16:47-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T19:16:47-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env otel-collector.yml otel-collector tempo.yml tempo grafana.yml grafana | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T19:16:47-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T19:16:47-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T19:16:47-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T19:16:47-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T19:16:47-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T19:16:47-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T19:16:47-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T19:16:49-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T19:16:49-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o .state/answer/overflow-agent.json -H content-type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-18T19:16:50-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o .state/answer/overflow-embedding.json -H content-type: application/json -d {"model":"embedding","input":"hello"} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-18T19:16:51-05:00 laptop: mise run agentgateway-deploy
+ 2026-11-18T19:16:51-05:00 gb10-2: mkdir -p ~/gateway/agentgateway
+ 2026-11-18T19:16:51-05:00 laptop: tar -C gateway --transform 's,^agentgateway/deploy.env$,.env,' -cf - compose.yml agentgateway.yml postgres.yml postgres/Dockerfile compose.sh agentgateway/deploy.env otel-collector.yml otel-collector tempo.yml tempo grafana.yml grafana | ssh gb10-2 'tar -C ~/gateway -xf -'
+ 2026-11-18T19:16:51-05:00 laptop: ssh gb10-2 'umask 077 && cat > ~/gateway/postgres.env' < .state/agentgateway/postgres.<tmp>.env
+ 2026-11-18T19:16:51-05:00 laptop: ssh gb10-2 'cat > ~/gateway/agentgateway/config.yaml.next' < .state/agentgateway/config.rendered.<tmp>.yaml
+ 2026-11-18T19:16:51-05:00 gb10-2: docker image inspect cr.agentgateway.dev/agentgateway:v1.7.0 >/dev/null 2>&1 || docker pull cr.agentgateway.dev/agentgateway:v1.7.0
+ 2026-11-18T19:16:51-05:00 gb10-2: docker run --rm --user "$(id -u):$(id -g)" --volume "$HOME/gateway/agentgateway:/config:ro" cr.agentgateway.dev/agentgateway:v1.7.0 -f /config/config.yaml.next --validate-only
+ 2026-11-18T19:16:51-05:00 gb10-2: mv ~/gateway/agentgateway/config.yaml.next ~/gateway/agentgateway/config.yaml
+ 2026-11-18T19:16:51-05:00 gb10-2: docker container inspect agentgateway --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo absent
+ 2026-11-18T19:16:51-05:00 gb10-2: gateway/compose.sh up --detach --wait --build
+ 2026-11-18T19:16:53-05:00 gb10-2: gateway/compose.sh ps --format "{{.Name}} {{.Image}} {{.Status}}"
+ 2026-11-18T19:17:00-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:17:00-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T19:16:47 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
+ 2026-11-18T19:17:00-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ resource.service.name\ =\ \"agentgateway\"\ \} --data-urlencode limit=10 --data-urlencode start=1795047240 --data-urlencode end=1795047420" | jq -r '.traces[].traceID'
+ 2026-11-18T19:17:00-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 266b7f194bec460e8f26e6c1ae390bf1 34e23b7c861e7d4ede07d7acb9844be8 debc01ce0bf1314b751d2c83b03c54ba 926cce9c743b3282b84dd00843be70b0" | spans, parents, and attribute keys
+ 2026-11-18T19:17:10-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:17:10-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-18T19:17:11-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-18T19:17:11-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-18T19:17:12-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"embedding","input":"hello"} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-18T19:17:12-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T19:17:10 agentgateway 2>&1' | grep -o ' route=default/[a-z]* .* endpoint=[^ ]*' | grep -o 'route=[^ ]*\|endpoint=[^ ]*' | grep -v azure.com | paste - -
+ 2026-11-18T19:17:30-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:17:30-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T19:17:10 agentgateway 2>&1' | grep -oE ' route=default/[a-z]+ endpoint=[^ ]+' | grep -v azure.com
+ 2026-11-18T19:17:35-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:17:35-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 curl -fsS --max-time 10 -G http://tempo:3200/api/search --data-urlencode q=\{\ span.gen_ai.provider.name\ =\ \"azure\"\ \} --data-urlencode limit=10 --data-urlencode start=1795047155 --data-urlencode end=1795047455" | jq -r '.traces[].traceID'
+ 2026-11-18T19:17:35-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh 5b24fe0838f97333fc467f8189785d40 2a8fd3f06a9ab9e3e1f8d32c877edf19" | spans, parents, and attribute keys
+ 2026-11-18T19:17:40-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:17:40-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T19:16:47 agentgateway 2>&1' | the request lines with overflow="azure" or gen_ai.provider.name=azure, counted per route and status
```

### 2026-11-18 · slice 2: the unattended restart and the restart policies

```text
+ 2026-11-18T19:17:44-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:17:44-05:00 laptop: ssh -n gb10-2 'docker restart gateway-otel-collector-1 gateway-tempo-1 gateway-grafana-1'
+ 2026-11-18T19:17:59-05:00 laptop: ssh -n gb10-2 'for i in $(seq 30); do s=$(docker inspect -f "{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" gateway-otel-collector-1 gateway-tempo-1 gateway-grafana-1); echo "$s" | grep -q starting || break; sleep 2; done; echo "$s"'
+ 2026-11-18T19:18:07-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:18:07-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"agent","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32} http://gb10-2:3000/agent/v1/chat/completions
+ 2026-11-18T19:18:08-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"vision","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32} http://gb10-2:3000/vision/v1/chat/completions
+ 2026-11-18T19:18:08-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"audio","messages":[{"role":"user","content":"Say OK."}],"max_tokens":32} http://gb10-2:3000/audio/v1/chat/completions
+ 2026-11-18T19:18:08-05:00 laptop: printf 'header = "Authorization: Bearer %s"\n' "$(<.state/agentgateway/keys/architect)" | curl -K - -s -m 120 -D - -o /dev/null -H content-type: application/json -d {"model":"embedding","input":"hello"} http://gb10-2:3000/embedding/v1/embeddings
+ 2026-11-18T19:18:08-05:00 laptop: ssh -n gb10-2 'docker logs --since 2026-11-18T19:18:07 agentgateway 2>&1' | grep -oE ' route=default/[a-z]+ endpoint=[^ ]+ .* trace\.id=[0-9a-f]+' | grep -v azure.com | sed -E 's/ src.addr=.* (trace.id=)/ \1/'
+ 2026-11-18T19:18:12-05:00 laptop: source scripts/clients-lib.sh
+ 2026-11-18T19:18:12-05:00 laptop: ssh -n gb10-2 'docker inspect -f "{{.Name}} {{.HostConfig.RestartPolicy.Name}}" $(docker ps -aq --filter label=com.docker.compose.project=gateway)'
+ 2026-11-18T19:18:12-05:00 laptop: ssh -n gb10-2 "docker exec gateway-grafana-1 sh -c 'for id; do curl -fsS --max-time 10 http://tempo:3200/api/v2/traces/$id && echo || exit; done' sh cea3f3ad7550397f1ae06d12f6b8cbd4 ac004c2048f1f264e928ba6ea1cd8efe ad3599374da129f37ffebaf7533626dc bdfa6219b5a739635ab55dbd0c9a6dbd" | spans, parents, and attribute keys
```

## For the goal record

Pending edits from these slices, for the session to move into the goal record:

- **v1.ai.client, claimed fixes still failing:** none. Each of go-ai's four claimed fixes passed on
  Azure through the gateway ("The revalidation").
- **v1.ai.hosting, a measured cold start:** vLLM's startup traces give each row's cold start
  broken down by phase, read from its `Overall Loading` trace: weights' load, model preparation,
  KV cache allocation, and warmup, per row ("The rows' startup traces and cold start"). The agent's
  46.2 s is led by its 17.8 s weights' load; audio's 50.0 s by its 20.5 s warmup. A candidate for
  v1.ai.hosting's restart and capacity notes, in place of an estimate.
