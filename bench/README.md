# Benchmark scenarios

GuideLLM 0.8.1 scenarios, one file a cell, run from the repository root by the step helpers'
`cell` ([`scripts/measure-lib.sh`](../scripts/measure-lib.sh)) from the bench environment
([`mise.bench.toml`](../mise.bench.toml)), one run at a time in the architect's view. Each file's
header gives its load and the scenario it is copied from: an overhead cell's, spike-model-layout's,
its load the layout's target, unchanged; a cap cell's, the overhead cell's, its requests unchanged
at two levels past the target.

The scenarios name no model, target, or key. `cell <name> <scenario> <direct|gateway> <alias>`
gives the alias as the model and its tokenizer on the command line, the base URL in
`GUIDELLM__SPEC__BACKEND__TARGET` (the row's `http://<host>:<port>/v1`, or the gateway's
`http://gb10-2:3000/<alias>/v1`), and, for a gateway run only, the bench key in
`GUIDELLM__SPEC__BACKEND__API_KEY`, read from `.state/agentgateway/keys/bench` into GuideLLM's
environment. Each file points GuideLLM's backend check at `/v1/models`, since its default,
`/health` at the target's root, is a path the gateway doesn't route.

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

The overhead cells (O-) run direct and through the gateway; the cap cells (C-) run through the
gateway only, with `cell <name> <scenario> cap <alias>`, two levels in one run, past each row's
target. The plans, the step commands, and how the runs are read are in the finding's slice 2 and
slice 3 sections,
[`docs/findings/agentgateway.md`](../docs/findings/agentgateway.md#slice-2--overhead) and
[its cap cells](../docs/findings/agentgateway.md#the-cap-cells).
