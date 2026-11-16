# Watch register

What this project watches upstream: any dependency's anticipated capability, deprecation, or other
change that would affect the infrastructure it maintains, one entry each. Version gaps are
`mise run currency`'s; this register holds what a version bump alone doesn't show, such as a form
the project relies on heading for removal, or a capability it is waiting for. It is written so that
other repositories can keep one the same way, a shared feature the architect wants for the
infrastructure we maintain.

**The check.** `mise run watch` ([`scripts/watch.sh`](../scripts/watch.sh)) reads every entry's
upstream and watched lines, below, and prints each beside its recorded value, with `differs` where
the two part, exiting nonzero if any do. It reads the network through `gh` and writes nothing. It
runs at every task's PLAN, as its own block, separate from `mise run currency`. Its output is read
by hand: each entry whose line differs is updated in place, its recorded value, its state, and its
other fields as the change warrants, and every entry checked gets its last-checked line from the
run. Git keeps the old text.

**An entry's fields:**

- **Kind:** deprecation, capability, or other.
- **Dependency:** the project, its repository, and where this project pins it.
- **Relies on** (a deprecation) or **wants** (a capability or other): the behavior at stake.
- **Evidence:** what shows the change is coming, or what the want is measured against, with its
  sources.
- **Upstream:** the issues and pull requests, one line each, `upstream <owner/repo>#<n> =
  <state>`, the state open, closed, or merged.
- **Watched:** the release fields that would show the change, read at the dependency's latest
  release tag, one line each in one of the forms below.
- **Trigger** (a deprecation) or **parity** (a capability): what, seen upstream, moves the entry
  on.
- **Fallback** (a deprecation) or **action** (a capability or other): what the project does then.
- **State**, by kind, in order:
  - Deprecation: **watching** → **deprecated in a release** → **removed**, or **withdrawn** if
    upstream backs out.
  - Capability: **watching** → **available in a release** → **adopted**, or **declined** if the
    project weighs it and stays.
  - Other: **watching** → **resolved**.
- **Last checked:** the check's `checked` time, and what it read.

**The machine-readable lines.** Each is a list item whose text starts with one backticked span,
which the check parses; prose may follow the span. A recorded value is what the line read when the
entry was last updated.

```text
upstream <owner/repo>#<n> = open|closed|merged
json <owner/repo> <path> <jq expression> = <value, as jq -c prints it>
text <owner/repo> <path> <fixed string> = present|absent
release-contains <owner/repo> <commit> = present|absent
```

`json` runs the jq expression on the file at the latest release tag; `text` looks for the string
in it; `release-contains` asks whether the tag's history holds the commit (`gh api
repos/<owner/repo>/compare/<commit>...<tag>`: ahead or identical is present). The latest release
is `gh release view`'s. A line that can't be read, a file moved or a path gone, prints as
`unreadable` and differs.

An entry is deleted once its state is final (removed, withdrawn, adopted, declined, or resolved)
and the project has acted on it; the finding or decision that acted keeps the record.

## agentgateway route `ai` backends deprecated

- **Kind:** deprecation.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, the image pinned in
  [`gateway/agentgateway/deploy.env`](../gateway/agentgateway/deploy.env) (v1.7.0).
- **Relies on:** the gateway's four routes, `/<alias>/v1` on the `consumer` port, each with an
  inline `ai` backend ([`gateway/agentgateway/config.yaml`](../gateway/agentgateway/config.yaml)).
  Task `routing` trialled the `llm` section and shipped it, then realigned on route `ai`, the form
  agentgateway's docs recommend for path-based routing ([`docs/findings/routing.md`](findings/routing.md),
  "Realignment on route `ai`"). The entry watches whether route `ai` is deprecated after all, and
  whether it goes the way `binds` went: deprecated before the replacement could express everything
  it did.
- **Evidence**, at v1.7.0. For route `ai` staying a supported form:
  - The current docs recommend routing-based configuration for path-based LLM routing. The
    decision table in `content/docs/standalone/latest/documentation/llm/configuration-modes.md`
    (agentgateway/website, last edited 2026-11-10, `d35d036`) has the row "Do you need custom,
    path-based routing (e.g., `/openai`, `/anthropic`)? | Yes | Routing-based configuration", and
    the page's title is "Routing-based configuration for LLMs".
  - The UI's "legacy" label may mean "inline backend on a route", not deprecation. The MCP docs
    (`mcp/configuration-modes.md`, same edit) state that the top-level `mcp` section "is a
    simplified form of the same MCP backend that `routes[].backends[].mcp` configures. It is not a
    different feature", while the UI labels an inline route `mcp` backend "legacy MCP backend" as
    well as an inline `ai` one "legacy LLM backend" (`ui/src/traffic.ts`).
  - The schema doesn't mark route `ai`: the route backend's `ai` variant carries no description
    (`schema/config.json`, `$defs.LocalRouteBackend`), where `binds`' says "Deprecated".

  On the other side:
  - agentgateway's UI labels an inline `ai` backend "legacy LLM backend" (`ui/src/traffic.ts`).
  - The client docs moved from route `ai` to the `llm` section: website#1091 rewrote the Claude
    Code and Claude Desktop client pages from `routes[].backends[].ai` to `llm:`, closing
    agentgateway#3655, "Docs result in legacy backend configuration".
  - `binds` was deprecated in favour of `gateways` and `routes` before `gateways` could express
    `tunnelProtocol: connect` or `mode: internal` (#3204, open), so upstream has deprecated a form
    without parity before.
  - agentgateway has no deprecation policy: #2767, "Define a project deprecation policy", was
    closed as premature.
  - On Kubernetes the model form is already the recommended one: agentgateway#4307 opens "Since
    1.7, `AgentgatewayModel` is the recommended way to expose LLMs", `AgentgatewayModel` being the
    Kubernetes counterpart of the `llm` section's models.
- **Upstream:**
  - `upstream agentgateway/agentgateway#4307 = open` per-model rate limits on `AgentgatewayModel`,
    whose opening names it the recommended form since 1.7.
  - `upstream agentgateway/agentgateway#3204 = open` `binds` deprecated without parity.
  - `upstream agentgateway/agentgateway#2767 = closed` the deprecation policy, closed as premature.
  - `upstream agentgateway/agentgateway#3655 = closed` the docs' legacy backend configuration.
  - `upstream agentgateway/website#1091 = merged` the client docs moved to `llm`.
- **Watched:**
  - `json agentgateway/agentgateway schema/config.json [.["$defs"].LocalRouteBackend.oneOf[] | select(.properties.ai) | .description // "" | test("deprecated"; "i")] = [false]`
    whether the route backend's `ai` variant's description says "Deprecated", as `binds`' does:
    `[true]` is its deprecation, and `[]` its removal from the schema.
  - `text agentgateway/agentgateway ui/src/traffic.ts legacy LLM backend = present` the UI's
    label.
- **Trigger:** the `ai` variant's description says deprecated, or the UI's label changes, or a
  release note deprecates route `ai`: the state moves to deprecated in a release. Its removal from
  the schema moves it to removed.
- **Fallback:** the `llm` form trialled in task `routing`
  ([`docs/findings/routing.md`](findings/routing.md), "The trial"): one alias per port, each model
  authorized on its own port by `proxy.listener.name`. On a trigger, check what this project, and
  what `priority` plans, still needs from route `ai`, such as route retries or `ai.groups`
  ([`docs/findings/agentgateway.md`](findings/agentgateway.md), "The paper inventory"), and record
  what `llm` must gain for parity.
- **State:** watching.
- **Last checked:** 2026-11-16T16:34Z, `mise run watch`: every line as recorded, at v1.7.0, the
  latest release.

## agentgateway `llm` serving several base URLs on one port

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** the `llm` section serving each alias at its own base URL on one port, through several
  path prefixes or a model list per prefix, so that the gateway could serve today's
  `http://gb10-2:3000/<alias>/v1` base URLs from `llm` rather than from route `ai`. This is the
  migration trigger: the gateway stays on route `ai`, the documented form for path-based routing,
  until `llm` can express the same base URLs.
- **Evidence:** task `routing`'s trial ([`docs/findings/routing.md`](findings/routing.md), "The
  trial"): at v1.7.0, `llm.pathPrefix` is one string, the one prefix for every gateway the section
  is attached to, so the trial told the four aliases apart by port, each model authorized on its
  own listener.
- **Upstream:** Kubernetes has it: agentgateway#2973 lets an HTTPRoute with a path-prefix rule
  instantiate a further model router on the same listener, which `AgentgatewayModel`s bind to. No
  issue asks for it in the standalone `llm` section (survey of every issue and pull request,
  2026-11-16); the facts for one are in [`docs/findings/routing.md`](findings/routing.md), "For an
  upstream feature request", for the architect to file.
  - `upstream agentgateway/agentgateway#2973 = merged` model routers scoped to an HTTPRoute,
    Kubernetes only.
- **Watched:**
  - `json agentgateway/agentgateway schema/config.json .["$defs"].LocalLLMConfig.properties.pathPrefix.type = "string"`
    one prefix; an array, or an object, would be the change.
- **Parity:** a release whose `llm` section lists only a prefix's own models on that prefix's
  `/models`, and refuses another prefix's, as each port does today.
- **Action:** when standalone `llm` serves several prefixes (Kubernetes has it, #2973), weigh
  moving the gateway to it: the same `/<alias>/v1` base URLs, served by the `llm` section, against
  re-checking its body handling (the always-passthrough entry below).
- **State:** watching.
- **Last checked:** 2026-11-16T16:34Z, `mise run watch`: as recorded, at v1.7.0.

## agentgateway always-passthrough for `llm` models

- **Kind:** capability.
- **Dependency:** agentgateway, `agentgateway/agentgateway`, as above.
- **Wants:** a release with #4185, "(breaking) llm: fix passthrough to proper override known
  types", merged 2026-10-27 at `2a7c2ec`, after v1.7.0's tag. At v1.7.0 a model's `passthrough`
  decides only how unknown paths are handled: the `llm` section parses chat completions, messages,
  responses, and embeddings as typed requests, refuses a format its provider doesn't list with 400,
  and adds `stream_options.include_usage` to streams
  ([`docs/findings/routing.md`](findings/routing.md), "Behavior 2"). #4185 restores `passthrough`
  to its documented meaning, always pass through, and is marked breaking.
- **Evidence:** the pull request's description; v1.7.0's tag is behind its merge commit.
- **Upstream:**
  - `upstream agentgateway/agentgateway#4185 = merged` always-passthrough restored.
- **Watched:**
  - `release-contains agentgateway/agentgateway 2a7c2ec473a221c643ff5c3adab77351bac65e71 = absent`
    the latest release carries the merge.
- **Parity:** the release carrying it, read in its notes for what `passthrough: detect` now does.
- **Action:** relevant if and when the gateway moves to `llm`, and to route `ai`'s typed route
  types, should the gateway's `ai.routes` ever name one in place of `detect`. Before either, on the
  release carrying it, re-check the gateway's body handling on every alias: the formats each model
  lists, whether streams still gain `include_usage`, and whether usage is still read for the access
  log and for `priority`'s budgets; then decide `passthrough` per model.
- **State:** watching.
- **Last checked:** 2026-11-16T16:34Z, `mise run watch`: as recorded; v1.7.0, the latest
  release, doesn't carry the merge.
