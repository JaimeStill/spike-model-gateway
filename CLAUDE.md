# spike-model-gateway

A spike for the Standards Lab reference architecture. It settles which gateway fronts the
workstations' vLLM rows (gb10-1 the agent, gb10-2 vision, the Framework audio and embedding), and
how access to the model APIs is restricted without the tailnet. The repository is managed with the
marathon workflow, so start from `context/README.md`.

- **Rules:** sessions are guided where the architect is learning. Read `context/README.md`,
  "Rules", and the experiment's rules in `standards-lab/context/ai-hosting.md`, "Experiment:
  experiment.hosting", before any host step.
- **Standards:** `STANDARDS.md`, with pointers into the architecture repository.
- **Check:** `mise run check`, which shellchecks every tracked shell script and resolves every
  relative Markdown link.
- **Currency:** `mise run currency`, which reports every pin behind its latest.
- **Goals:** this spike's tasks live in the coordinator's roadmap,
  `standards-lab/context/roadmap.toml`, under `experiment.hosting.spike-model-gateway`. Its goal
  record is `context/goals/experiment.hosting.spike-model-gateway.md`.
- **References:** the repositories this spike reads are keys in the coordinator's
  `references.toml` and `references.local.toml`. The spike reads them and never writes to them,
  except spike-model-engines' `host/`, which experiment.hosting owns: this spike lists
  spike-model-engines in its repos and changes `host/` through pull requests, each citing the
  finding behind it.
