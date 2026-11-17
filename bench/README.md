# Benchmark scenarios

GuideLLM 0.8.1 scenarios, one file a cell, run from the repository root by the step helpers'
`cell` ([`scripts/measure-lib.sh`](../scripts/measure-lib.sh)) from the bench environment
([`mise.bench.toml`](../mise.bench.toml)), one run at a time in the architect's view. Each file's
header gives its load and the scenario it is copied from: an overhead cell's, spike-model-layout's,
its load the layout's target, unchanged; a cap cell's, the overhead cell's, its requests unchanged
at two levels past the target.

The scenarios name no model, target, or key. `cell <name> <scenario> <direct|gateway|cap> <alias>
[<key>]` gives the alias as the model and its tokenizer on the command line, the base URL in
`GUIDELLM__SPEC__BACKEND__TARGET` (the row's `http://<host>:<port>/v1`, or the gateway's
`http://gb10-2:3000/<alias>/v1`), and, for a gateway or cap run only, the named key, bench unless
another is given, in `GUIDELLM__SPEC__BACKEND__API_KEY`, read from
`.state/agentgateway/keys/<key>` into GuideLLM's environment. Each file points GuideLLM's
backend check at `/v1/models`, since its default, `/health` at the target's root, is a path the
gateway doesn't route: it serves the serving endpoints alone.

| Cell | Scenario | Alias, row | Tokenizer | Load |
| --- | --- | --- | --- | --- |
| O-agent | `overhead-agent.yaml` | agent, gb10-1:8000 | `openai/gpt-oss-120b` | 4-turn synthetic sessions, 8,192 tokens then 512 a turn, 512 out a turn; 4 concurrent; 110 s |
| O-vision | `overhead-vision.yaml` | vision, gb10-2:8000 | `google/gemma-4-26B-A4B-it` | a synthetic 1440p JPEG and 200 text tokens, 100 out; 4 concurrent; 90 s |
| O-audio | `overhead-audio.yaml` | audio, framework:8001 | `google/gemma-4-E4B-it` | a LibriSpeech dummy clip as 16 kHz WAV in chat with the card's prompt, at most 256 out; 4 concurrent; 30 s or 64 requests |
| O-embed | `overhead-embed.yaml` | embedding, framework:8002 | `ibm-granite/granite-embedding-english-r2` | 512 synthetic tokens; a constant 34 requests a second; 60 s |
| C-agent | `cap-agent.yaml` | agent, through the gateway | `openai/gpt-oss-120b` | O-agent's sessions at 12, then 16; 110 s a level |
| C-vision | `cap-vision.yaml` | vision, through the gateway | `google/gemma-4-26B-A4B-it` | O-vision's requests at 16, then 20 concurrent; 60 s a level |
| C-audio | `cap-audio.yaml` | audio, through the gateway | `google/gemma-4-E4B-it` | O-audio's requests at 4, then 8 concurrent; 30 s or 64 requests a level |
| C-embed | `cap-embed.yaml` | embedding, through the gateway | `ibm-granite/granite-embedding-english-r2` | O-embed's requests at 128, then 160 in flight; 60 s a level |
| C-agent, benchmark C | `overflow-agent.yaml` | agent, through the gateway | `openai/gpt-oss-120b` | single-turn synthetic prompts, 512 tokens, 128 out; 28 concurrent; 60 s |
| C-vision, benchmark C (dropped, never run) | `overflow-vision.yaml` | vision, through the gateway | `google/gemma-4-26B-A4B-it` | a synthetic 720p JPEG and 200 text tokens, 100 out; 36 concurrent; 60 s |
| C-embed, benchmark A | `limited-embed.yaml` | embedding, through the gateway, bench key | `ibm-granite/granite-embedding-english-r2` | O-embed's requests at 160 in flight, held to 34 a second by the route's limit; 90 s |
| C-vision, benchmark B | `bulk-vision-150.yaml` | vision, through the gateway, bulk key | `google/gemma-4-26B-A4B-it` | O-vision's requests at 20 concurrent; 150 s |
| C-vision, benchmark D | `bulk-vision-120.yaml` | vision, through the gateway, bulk key | `google/gemma-4-26B-A4B-it` | O-vision's requests at 20 concurrent; 120 s |
| O-vision at 1, benchmark D | `interactive-vision.yaml` | vision, through the gateway, go-ai key | `google/gemma-4-26B-A4B-it` | O-vision's requests at 1 concurrent; 90 s |

The overhead cells (O-) run direct and through the gateway; the cap cells (C-) run through the
gateway only, with `cell <name> <scenario> cap <alias>`, two levels in one run, past each row's
target. The plans, the step commands, and how the runs are read are in the agentgateway task's
finding, its slice 2 and slice 3 sections,
[`docs/findings/agentgateway.md`](../docs/findings/agentgateway.md#slice-2--overhead) and
[its cap cells](../docs/findings/agentgateway.md#the-cap-cells).

Benchmark C, the priority task's overflow benchmark, runs each `overflow-` cell through the
gateway with `cap`, one level past the row's queue limit (agent 24, vision 32). There the row
answers 503, and the gateway sends the alias to its Azure AI Foundry deployment while the row is
evicted. The requests are sized to Azure's capacity, so the row fills on concurrency, not tokens.
A cell stops early if Azure answers 429: no GuideLLM constraint tells a 429 from the row's 503s,
so the session watches `azure_count` and interrupts the run by hand. `overflow_read <name>` reads
the run. Only C-agent has run; C-vision was dropped after C-agent breached the task's Azure stop
rule. The runs and their reading are in the priority task's finding,
[`docs/findings/priority.md`](../docs/findings/priority.md).

Benchmarks A, B, and D (the priority task's slice 3) each run two cells at once, in two terminals,
the outer cell first and the inner one started inside it: A, `limited-embed` with O-audio
(`overhead-audio`, go-ai key) about 20 s in; B, `bulk-vision-150` with O-agent (`overhead-agent`,
go-ai key) about 20 s in; D, `bulk-vision-120` with `interactive-vision` about 15 s in, then the
same pair under the `priority-flat` probe overlay. A's anchors are O-audio alone, direct and
through the gateway, and B's O-agent alone, both read the same way; `rtfx <name>...` reads audio's
real-time factor. No cell pushes a row past its queue limit (vision 32, agent 24, audio 8), so
none sends anything to Azure while the rows are up; each file's header gives its count.
