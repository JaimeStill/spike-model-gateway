# Standards

The judgement calls the check can't enforce, one line each, for the standards-reviewer. What
`mise run check` enforces is never restated here.

The architecture pages that apply, in the architecture repository:

- `principles/minimal-footprint.md`
- `principles/rolling-currency.md`
- `principles/validation-first.md`

## Tools

- A gateway's native feature comes first; no admin backend or plugin is authored for it.
- No Python is authored, and a mise task runs one script or one command.

## Scripts

- Only a step that must be idempotent is scripted; a helper never runs a benchmark on its own.
- A host's engine or preset changes only through spike-model-engines' `host/`, by pull request.

## Docs

- A finding, `docs/findings/<task>.md`, says what was measured, when, on which gateway and engine
  versions, host stack, and network path (`tailscale ping`), and stays dated.
- Raw run output stays untracked under `.state/`.
- Every command a session or the architect runs appears in its finding exactly as run.
- No tailnet or LAN identifier, and no key, is committed: hosts go by short name, such as `gb10-2`.
