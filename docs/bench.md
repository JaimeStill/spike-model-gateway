# The benchmark cells

The load, sizing, and derivation of each GuideLLM scenario in [`bench/`](../bench/), one section
per file; each file's header points at its section with a `See` line. How the cells are run and
read is in [`bench/README.md`](../bench/README.md).

## The backend check

GuideLLM checks the backend before a run with GET <target>/health, the target's /v1 cut off.
Through the gateway that is /<alias>/health, which no route serves (404), so each file's
`api_routes` points the check at /v1/models instead, direct and through the gateway alike; through
the gateway the gateway answers it itself, and it also proves the key before any load is sent.

## Audio requests

The audio cells' requests, shared by [overhead-audio](#overhead-audio) and
[cap-audio](#cap-audio):

- **The reply cap.** A transcript is as long as its clip, so no request sets output tokens or
  ignore_eos; `max_tokens` caps each reply, sent as max_completion_tokens, should the model not
  stop.
- **The sources.** The two sources are read side by side, one row of each a request, and a level
  stops when either runs out. Source 0 is the prompt, from Gemma 4's card ("Transcribe the
  following speech segment in {LANGUAGE} into {LANGUAGE} text. ... Only output the transcription,
  with no newlines."), once a request: 73 of it, one a clip, where layout's footprint-l3.yaml's 32
  stopped the zip at its 32nd clip. Source 1 is hf-internal-testing/librispeech_asr_dummy, 73
  clips from LibriSpeech's clean validation split, about 9 MB fetched once from Hugging Face (the
  laptop's cache already holds it). Each level reads both sources from their start.
- **The columns.** Only the prompt and the clip: LibriSpeech's own text column is the reference
  transcript, which the mapper's defaults would otherwise send as the prompt.
- **The encoding.** Every clip is re-encoded as 16 kHz mono WAV, as layout's cells sent it; the
  source is FLAC.

## Levels

A level stops at its `max_duration`, or at its `max_requests` where a cell sets one, whichever comes
first; the requests or sessions in flight then are counted incomplete.

## overhead-agent

O-agent, the agentgateway task's agent overhead cell (behavior 7): the agent row, gpt-oss-120b with
FP8 KV (gpt-oss-120b-agent-fp8 on gb10-1's 8000), at the agent's target of 4 sessions for 110 s, run
three times, direct, then through the gateway, then direct. Copied from spike-model-layout's
bench/vllm-layout-agent.yaml, its sessions and level length unchanged: GuideLLM's multi-turn
synthetic conversation, 4 turns, the first 8,192 prompt tokens and the next three 512 each, every
turn exactly 512 output tokens, each turn sent when the last one's reply ends. Adapted: one level,
4, where layout swept 4 and 12; the model is the alias, agent, with its tokenizer
(openai/gpt-oss-120b); and the backend check reads /v1/models.

The priority task's benchmark B runs it with the go-ai key inside
[bulk-vision-150](#bulk-vision-150), and alone, direct and through the gateway, as B's anchors.
Azure: none. Its 4 sessions stay under the agent row's queue limit of 24 (twice its cap of 12,
--max-num-queued-reqs), so the row never refuses with 503 and nothing overflows to gpt-oss-120b
while the rows are up.

## overhead-vision

O-vision, the agentgateway task's vision overhead cell (behavior 7): the vision row, NVFP4 26B-A4B
(gemma-4-26B-A4B-NVFP4-vision-gb10 on gb10-2's 8000), at the vision target of 4 concurrent streams
for 90 s, run three times, direct, then through the gateway, then direct. Copied from
spike-model-layout's bench/vllm-layout-vision-alone.yaml (V-alone), its requests and level
unchanged: one synthetic 1440p JPEG beside 200 synthetic text tokens, exactly 100 output tokens.
Adapted: the model is the alias, vision, with its tokenizer (google/gemma-4-26B-A4B-it); and the
backend check reads /v1/models.

## overhead-audio

O-audio, the agentgateway task's audio overhead cell (behavior 7): the audio row, E4B BF16
(gemma-4-E4B-it-audio-framework on the Framework's 8001), at 4 concurrent streams for 30 s or 64
requests, run three times, direct, then through the gateway, then direct. Copied from
spike-model-layout's bench/vllm-layout-audio-alone.yaml (A-alone), its requests and level
unchanged: one LibriSpeech clip as 16 kHz WAV in chat with the model card's transcription prompt,
the reply at most 256 tokens ([Audio requests](#audio-requests)). Adapted: the model is the alias,
audio, with its tokenizer (google/gemma-4-E4B-it); and the backend check reads /v1/models.

The priority task's benchmark A runs it with the go-ai key inside [limited-embed](#limited-embed),
and alone, direct and through the gateway, as A's anchors; `rtfx` reads each. Azure: none. Its 4
streams stay under the audio row's queue limit of 8 (twice its cap of 4, --max-num-queued-reqs), so
the row never refuses with 503 and nothing overflows to gpt-audio-mini while the rows are up.

## overhead-embed

O-embed, the agentgateway task's embedding overhead cell (behavior 7): the embedding row, granite
(granite-embedding-english-r2-framework on the Framework's 8002), at a constant 34 requests a second
for 60 s, run three times, direct, then through the gateway, then direct. Copied from
spike-model-layout's bench/vllm-layout-embed-rate-4x.yaml, its requests and rate unchanged: 512
synthetic tokens to /v1/embeddings, 34 a second whatever the replies' latency (17,408 prompt tok/s,
four times layout's floor and the rate the layout admits at the gateway), so the requests in flight
follow the server. Adapted: 60 s, where layout ran 240 s beside audio; the model is the alias,
embedding, with its tokenizer (ibm-granite/granite-embedding-english-r2); and the backend check
reads /v1/models.

## cap-agent

C-agent, the agentgateway task's agent cap cell (behavior 8): the agent row, gpt-oss-120b with FP8
KV (agent on gb10-1's 8000), through the gateway only, at two levels past the agent's target of 4
sessions: 12, then 16, each for 110 s. Observational: nothing stands at the cap on the gateway, so
the cell shows what a client sees there, every reply's status, the row's running and waiting
counts, and how latency grows from one level to the next. Derived from
[overhead-agent](#overhead-agent), its requests unchanged. Adapted: the two levels, where the
overhead cell ran one, 4. Run with the bench key.

## cap-vision

C-vision, the agentgateway task's vision cap cell (behavior 8): the vision row, NVFP4 26B-A4B
(vision on gb10-2's 8000), through the gateway only, at two levels past the vision target of 4
concurrent streams: 16, then 20, each for 60 s. Observational, as [cap-agent](#cap-agent) is.
Derived from [overhead-vision](#overhead-vision), its requests unchanged. Adapted: the two levels
and 60 s a level, where the overhead cell ran one level, 4, for 90 s. Run with the bench key.

## cap-audio

C-audio, the agentgateway task's audio cap cell (behavior 8): the audio row, E4B BF16 (audio on the
Framework's 8001), through the gateway only, at two levels, 4 and then 8 concurrent streams, each
for 30 s or 64 requests. Observational, as [cap-agent](#cap-agent) is. Derived from
[overhead-audio](#overhead-audio), its requests unchanged. Adapted: the two levels, where the
overhead cell ran one, 4. Run with the bench key.

## cap-embed

C-embed, the agentgateway task's embedding cap cell (behavior 8): the embedding row, granite
(embedding on the Framework's 8002), through the gateway only, at two levels of 128 and then 160
requests in flight, each for 60 s. Observational, as [cap-agent](#cap-agent) is. Derived from
[overhead-embed](#overhead-embed), its requests unchanged: 512 synthetic tokens to /v1/embeddings.
Adapted: a fixed number of requests in flight, 128 and then 160, each sent as the last one's reply
arrives, where the overhead cell sent a constant 34 a second whatever the replies' latency; the cap
is a count in flight, so the load is too. Run with the bench key.

## overflow-agent

C-agent, benchmark C's agent cell (the priority task's behavior 9; evidence 7): the agent row,
gpt-oss-120b with FP8 KV (agent on gb10-1's 8000), through the gateway only, at 28 concurrent for
60 s: past the 24 the row holds before it refuses (twice its cap of 12 in flight,
--max-num-queued-reqs), so the row answers 503, two in a row evict it for 5 s, then 5 s times the
evictions so far, with no cap ([`agentgateway-config.md`](agentgateway-config.md#row-provider)),
and the gateway sends the agent alias to its Azure AI Foundry deployment, gpt-oss-120b, while it is
out. The cell reads 503s from the row, the requests Azure answered, whether a refused request
reached Azure, and the eviction windows a minute (`overflow_read`,
[`scripts/measure-lib.sh`](../scripts/measure-lib.sh)). Every request Azure answers counts against
the task's cap of 300 (`azure_count`, [`scripts/clients-lib.sh`](../scripts/clients-lib.sh)).

Sized to Azure's capacity (the slice 2 escalation, [`findings/priority.md`](findings/priority.md)):
the deployment has 50 units, about 50,000 tokens a minute, which O-agent's sessions (8,192 prompt
tokens to start) would pass within seconds of an overflow. So each request is short, and the row
fills on concurrency, not tokens: one turn, 512 synthetic prompt tokens and 128 output tokens, the
next request sent when a reply ends.

The cell stops early if Azure answers 429. No GuideLLM 0.8.1 constraint can: max_errors and the
error-rate constraints count every errored request, and the row's 503s are errors too, with no
status code to tell them apart. So the session watches `azure_count`, which flags any 429 from
Azure, or the access log, and interrupts the run by hand. Run with the bench key.

## overflow-vision

Dropped, never run. The architect dropped C-vision on 2026-11-16, after C-agent breached the task's
Azure stop rule: under saturation a row's 503 with eviction sends nearly the whole load to Azure,
and C-vision would show the same at gpt-5-mini's 10 units
([`findings/priority.md`](findings/priority.md), "Escalation 2"). The file is kept as the sizing it
would have run with; nothing runs it.

C-vision, benchmark C's vision cell (the priority task's behavior 9; evidence 7): the vision row,
NVFP4 26B-A4B (vision on gb10-2's 8000), through the gateway only, at 36 concurrent for 60 s: past
the 32 the row holds before it refuses (twice its cap of 16 in flight, --max-num-queued-reqs), so
the row answers 503, two in a row evict it for 5 s, then 5 s times the evictions so far, with no
cap, and the gateway sends the vision alias to its Azure AI Foundry deployment, gpt-5-mini, while it
is out. The cell reads what [overflow-agent](#overflow-agent) reads, and the time to the row's first
refusal, which vLLM #58192 delays on vision. Every request Azure answers counts against the task's
cap of 300.

Sized to Azure's capacity (the slice 2 escalation): the deployment has 10 units, about 10,000
tokens a minute, so each request is small and the row fills on concurrency, not tokens: one
synthetic 720p JPEG (GuideLLM's gradient, quality 85) beside 200 synthetic text tokens, exactly 100
output tokens. The image's base64 is 21 to 46 KB (1,000 GuideLLM 0.8.1 rows, measured on the
laptop), so each body stays under the 64 KiB the gateway buffers for a retry, and a refused request
is retried, to Azure once the row is evicted
([`agentgateway-config.md`](agentgateway-config.md#retry)). 1080p reaches 82 KB, past it. The cell
stops early if Azure answers 429, as overflow-agent does. Run with the bench key.

## limited-embed

C-embed, benchmark A's embedding run (the priority task's behavior 17; evidence 5): the embedding
row, granite (embedding on the Framework's 8002), through the gateway only, with the bench key, 160
requests in flight for 90 s, held by the embedding route's global limit of 34 requests a second
([`agentgateway-config.md`](agentgateway-config.md#embedding-limits)): the gateway admits a burst of
34 and then 34 a second, and answers the rest 429 with Retry-After itself. The go-ai key's O-audio
([overhead-audio](#overhead-audio), 4 streams, 30 s or 64 requests) starts inside it, in a second
terminal, about 20 s in, once the load has settled, and is read with `rtfx` beside its anchors,
O-audio alone direct and through the gateway. A reads whether the bucket's burst of 34 lets audio
hold its RTFx median at 5 or more; a miss escalates to a paced bucket. Derived from
[cap-embed](#cap-embed), its requests unchanged: 512 synthetic tokens to /v1/embeddings, each sent
as the last one's reply arrives. Adapted: one level, 160, for 90 s, where the cap cell ran 128 and
then 160 for 60 s each.

Azure: none. The 429 is the gateway's own, answered before any backend, so it never reaches the row
or evicts it; the embedding row has no queue limit, so it never answers 503, and nothing fails over
to text-embedding-3-small unless the row's connection fails twice in a row. Audio's 4 streams stay
under its queue limit of 8. So the run sends nothing to Azure while the rows are up; `azure_count`
after the pair shows none.

Load: a refused request returns at once, and each of the 160 is sent again as its 429 arrives, so
the gateway answers far more 429s than 34 a second, about 160 a round trip, each an access log line
and a request log row in Postgres. The gateway's CPU in this run is its 429s' as much as its
forwarding's. Run with `cap`, the cell also reads the row's running and waiting counts and every
reply's status and Retry-After from the access log. The bench key's budget only audits, so the run's
1,570,000 or so tokens refuse nothing.

## bulk-vision-150

C-vision, benchmark B's bulk run (the priority task's behaviors 13 and 14; evidence 6): the vision
row, NVFP4 26B-A4B (vision on gb10-2's 8000), through the gateway with the bulk key, at 20
concurrent for 150 s. The gateway gives each bulk request vLLM's priority 10 on the vision row
([`agentgateway-config.md`](agentgateway-config.md#priority-by-key)). The go-ai key's O-agent
([overhead-agent](#overhead-agent), 4 sessions for 110 s) runs inside it on the agent row, in a
second terminal, started about 20 s in, and is read against its anchors, O-agent alone direct and
through the gateway: B reads whether chat holds its floor, an agent ITL median of 100 ms or less,
and how TTFT, ITL, and the gateway's CPU move against the direct spread, with bulk vision's load on
the same gateway.

Azure: none. The vision row refuses with 503 only past 32 in flight (twice its cap of 16,
--max-num-queued-reqs), and this run holds 20; the agent row refuses only past 24, and O-agent holds
4. So neither row refuses, neither is evicted, and nothing overflows while the rows are up. A row
that fails twice in a row for another reason, a lost connection, would be evicted for 5 s, then 5 s
times the evictions so far, with no cap
([`agentgateway-config.md`](agentgateway-config.md#row-provider)), and send its alias's requests to
Azure meanwhile, so `azure_count` is read after the pair, and any overflow stops the session.
bulk's request-rate bucket, 600 a minute, and its budget, 1,000,000 tokens an hour, are above the
run's load: about 1.9 requests a second of about 580 tokens each (the agentgateway task's c-vision
at 20).

Derived from [cap-vision](#cap-vision), its requests unchanged: one synthetic 1440p JPEG beside 200
synthetic text tokens, exactly 100 output tokens. Adapted: one level, 20, for 150 s, where the cap
cell ran 16 and then 20 for 60 s each. Run with the bulk key.

## bulk-vision-120

C-vision, benchmark D's bulk run (the priority task's behaviors 13 and 14; evidence 6): the vision
row, NVFP4 26B-A4B (vision on gb10-2's 8000), through the gateway with the bulk key, at 20
concurrent for 120 s. The gateway gives each bulk request vLLM's priority 10 on the vision row, and
each interactive key's 0, and the row serves the lower value first
([`agentgateway-config.md`](agentgateway-config.md#priority-by-key)). The go-ai key's O-vision at
1 concurrent ([interactive-vision](#interactive-vision), 90 s) runs inside it on the same row, in a
second terminal, started about 15 s in, once the bulk load has filled the row. D reads whether the
interactive run's median request latency stays at 10 s or less with priority, and, against the same
pair run under the priority-flat probe overlay, every key at bulk's 10, how far it moves without.

Azure: none. The vision row refuses with 503 only past 32 in flight (twice its cap of 16,
--max-num-queued-reqs); this run's 20 and the interactive run's 1 are 21, so the row never refuses,
is never evicted, and nothing overflows to gpt-5-mini while the rows are up. A row that fails twice
in a row for another reason, a lost connection, would be evicted for 5 s, then 5 s times the
evictions so far, with no cap, and send the run's requests to gpt-5-mini meanwhile, so
`azure_count` is read after the pair, and any overflow stops the session. bulk's request-rate
bucket, 600 a minute, and its budget, 1,000,000 tokens an hour, are above the run's load: about 1.9
requests a second of about 580 tokens each (the agentgateway task's c-vision at 20).

Derived from [cap-vision](#cap-vision), its requests unchanged. Adapted: one level, 20, for 120 s,
where the cap cell ran 16 and then 20 for 60 s each. Run with the bulk key.

## interactive-vision

O-vision at 1, benchmark D's interactive run (the priority task's behavior 13; evidence 6): the
vision row, NVFP4 26B-A4B (vision on gb10-2's 8000), through the gateway with the go-ai key, at 1
concurrent stream for 90 s. It runs inside [bulk-vision-120](#bulk-vision-120), the bulk key's 20
concurrent on the same row, in a second terminal, started about 15 s into the bulk run, so it ends
inside it. Each go-ai request reaches the row with vLLM's priority 0, ahead of bulk's 10
([`agentgateway-config.md`](agentgateway-config.md#priority-by-key)); under the priority-flat probe
overlay, the control, it carries bulk's 10. D reads its median request latency against vision's
floor of 10 s, with priority and without.

Azure: none. Its 1 in flight beside the bulk run's 20 is 21, under the vision row's queue limit of
32 (twice its cap of 16, --max-num-queued-reqs), so the row never refuses it with 503 and nothing
overflows to gpt-5-mini while the rows are up; `azure_count` after the pair shows none. go-ai's
request-rate bucket, 1,200 a minute, is far above the run's one request every few seconds, and its
budget only audits.

Copied from [overhead-vision](#overhead-vision) (O-vision), its requests unchanged. Adapted: 1
concurrent stream, where O-vision ran vision's target of 4, so it is one interactive caller. Run
with the go-ai key.
