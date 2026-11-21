# spike-model-gateway

A spike for the Standards Lab reference architecture. It settles which gateway fronts the
workstations' vLLM rows (gb10-1 the agent, gb10-2 vision, the Framework audio and embedding), and
how access to the model APIs is restricted without the tailnet. The repository is managed with the
marathon workflow, so start from `context/README.md`.

- **Rules:** sessions are guided where the architect is learning. Read the experiment's rules,
  `standards-lab/docs/ai-hosting.md#experiment-rules`, before any host step.
- **Standards:** `STANDARDS.md`, with pointers into the architecture repository.
- **Check:** `mise run check`, which shellchecks every tracked shell script, resolves every
  relative Markdown link, vets and tests the retry module, and runs lint-context and
  lint-references.
- **Currency:** `mise run currency`, which reports every pin behind its latest.
- **Goals:** the spike answered for experiment.hosting, which has synced; v1.ai.hosting
  (`standards-lab/roadmap/v1.ai.hosting.toml`) builds from its answer.
- **References:** [`docs/capabilities.md`](docs/capabilities.md#references).
