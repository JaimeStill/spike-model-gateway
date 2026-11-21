# Gateway comparison

The spike's gateway comparison, on paper (evidence 10 of
[`context/README.md`](../context/README.md#the-evidence)). LiteLLM is the feature reference. Beside
it are agentgateway, which the spike runs, and Bifrost, Agent Router, Kong AI Gateway, Portkey,
Helicone, and TensorZero. Six topics follow: vLLM's production-stack router, Kubernetes
portability, JWT and OIDC, production's Azure Container Apps routing, IL6, and a cheaper chat tier.
Each candidate is then scored against the spike's six question bullets
([`context/README.md`](../context/README.md#the-question)).

**How to read it.**

- **Live evidence comes from agentgateway alone.** agentgateway v1.7.0 is the only gateway the
  spike ran. Each of its cells cites the finding that proved it.
- **Every other gateway is described from its own documentation, repository, or advisories.**
  This document never says that another gateway does something live.
- **Sources.** Every source was read on the web on 2026-11-18. Each claim links to its source, and
  the links are listed under "Sources", grouped by candidate.
- **Gaps in the record.** Where a source was unavailable or a claim couldn't be confirmed, the text
  says so. "Unconfirmed" collects those cases.
- **No other gateway was tried live.** LiteLLM was dropped from a live trial (the spike's goal
  record, `context/goals/experiment.hosting.spike-model-gateway.md` at `2f2e8c1^`, Decisions,
  2026-11-13) because of:
  - its 2026 supply-chain compromises (two, under "Candidates") and advisories;
  - a Python runtime whose Rust port isn't production-ready;
  - single-vendor governance.

  It stays here as the feature reference.

## Candidates

**agentgateway**: the gateway the spike runs.

- **What it is.** An Apache-2.0 proxy for AI traffic, written in Rust ([license][agw-lic]).
- **Governance.**
  - It is a Linux Foundation project, "a Series of LF Projects, LLC" ([charter][agw-charter]).
    Solo.io contributed it on 2025-08-25 ([LF][agw-lf]).
  - It joined the Agentic AI Foundation (AAIF) on 2026-06-04 as a hosted project
    ([AAIF][agw-aaif]).
  - Eight of its nine active maintainers list Solo.io ([maintainers][agw-maint]).
- **Releases.** It ships about one minor release a month:
  - v1.4.0, 2026-07-27;
  - v1.5.0, 2026-08-27;
  - v1.6.0, 2026-10-02;
  - v1.7.0, 2026-10-27, which is the latest and the version the spike runs ([releases][agw-rel]).
- **Advisories.** It has published seven GHSAs, all in 2026 ([advisories][agw-adv]).
  - Each concerns MCP or Kubernetes, and none concerns LLM routing.
  - The highest is GHSA-mvgg-jvj2-4frq, rated 8.1: stateful MCP sessions crossing routes.
  - Each is fixed at or before v1.7.0.
- **Enterprise edition.** Solo Enterprise for agentgateway is a separate, licensed distribution
  ([enterprise][agw-ent], [licensing][solo-lic]). Every feature this document credits to
  agentgateway is in the open-source v1.7.0.
- **What the spike proved.** The spike ran it in front of the four rows and proved:
  - pass-through under purpose aliases, gateway-issued keys, and the fence on non-serving paths
    ([`agentgateway.md`](findings/agentgateway.md));
  - the route `ai` form ([`routing.md`](findings/routing.md), "Realignment on route `ai`");
  - overflow, per-key limits, and priority ([`priority.md`](findings/priority.md));
  - retries and traces ([`answer.md`](findings/answer.md)).

**LiteLLM**: the feature reference.

- **What it is.** BerriAI's Python SDK and proxy server ([repository][lt-repo]).
- **License.** MIT, except the `litellm/enterprise/` directory ([license][lt-lic]). That directory
  is under a proprietary license, which allows production use only "if you … have a valid BerriAI
  Enterprise license" ([enterprise license][lt-entlic]).
- **Governance.** One company, with no foundation.
- **Releases.** A stable release ships every week, promoted from the previous week's release
  candidate, alongside nightlies and an LTS pilot ([release cycle][lt-cycle],
  [releases][lt-rel]).
- **Two supply-chain compromises in 2026:**
  - **March.** litellm 1.82.7 and 1.82.8 on PyPI carried a credential stealer, through a
    compromised Trivy step in CI ([March][lt-mar]).
  - **October.** On 2026-10-21, litellm 1.107.0 was published to PyPI, Docker Hub, and GHCR by
    LiteLLM's own pipeline, "validly signed, valid Trusted Publishing provenance", after an
    attacker took an organization owner's token ([incident][lt-oct], [attack chain][lt-chain],
    [after][lt-after], [GHSA-92x9-889m-jgmw][lt-mal]).
- **Three of its 2026 advisories:**
  - **GHSA-7hp6-4w63-5g45** (critical, 2026-09-30): an internal user escalates to proxy admin and
    then to command execution ([advisory][lt-7hp6]).
  - **GHSA-w4c7-34wj-hqm8** (critical, 2026-10-27): an unauthenticated file read leaks the master
    key on Enterprise proxies ([advisory][lt-w4c7]).
  - **GHSA-2rwg-2wh4-7c4f** (high, 2026-11-12): Azure Entra credential parameters in the request
    body let a caller exfiltrate secrets ([advisory][lt-2rwg]). It bears directly on an Azure
    overflow.
- **The Rust work** is a route-by-route migration inside the Python proxy, "not a v2 and not a
  rewrite" ([launch][lt-rust-launch]).
  - All routing has flowed through a Rust core since v1.110.0 ([router][lt-router-rust]).
  - The benchmark post still calls it "an early beta" ([benchmarks][lt-rust-bench]).
  - `/v1/messages` end to end in Rust is planned "by Dec 1" ([rerouted][lt-rerouted]).
  - No statement that a Rust server is production-ready was found.

**Bifrost**: Maxim AI's gateway.

- **What it is.** An Apache-2.0 gateway in Go ([repository][bf-repo], [license][bf-lic]).
- **Governance.** One company, with no foundation.
- **Enterprise edition.** A closed superset, pulled from a private registry
  ([enterprise][bf-ent], [on-premise][bf-onprem]).
- **Releases.** A minor release every three to four weeks, the latest v2.6.0 on 2026-11-19
  ([cadence][bf-cadence], [releases][bf-rel]).
- **Advisories:**
  - **GHSA-86gf-xh3g-rvxq** (critical, 2026-09-23): MCP stdio remote code execution
    ([advisory][bf-86gf]).
  - **GHSA-2qp8-4xgm-fw6g** (high, 2026-09-23): an unauthenticated RCE through the plugin API
    "when management authentication is disabled (the default …)" ([advisory][bf-2qp8]).
  - **GHSA-w98g-5w9p-p3rc** (high, 2026-07-21): the SSRF deny-list is incomplete
    ([advisory][bf-w98g]).

**Agent Router**: Envoy AI Gateway, renamed and moved to the AAIF.

- **What it is.** Envoy AI Gateway, renamed: "Same code, same maintainers, same release cadence
  and Apache 2.0 license", with the CLI still `aigw` ([README][ar-readme]).
- **Governance.** It joined the AAIF on 2026-09-09, with maintainer seats across Bloomberg,
  Nutanix, AMD, Tetrate, and Netflix ([AAIF][ar-aaif], [projects][ar-proj]).
- **Runtime.** Go, with Envoy as the data plane.
- **Kubernetes-first.** `aigw run` is "useful for testing the configuration locally"
  ([aigw run][ar-run]), and v1.2 needs Kubernetes 1.32 or later ([compatibility][ar-compat]).
- **Releases.** About one minor release every six to eight weeks, the latest v1.3.0 on 2026-11-18
  ([releases][ar-rel]).
- **Advisories.** 24 GHSAs in 2026, mostly MCP ([advisories][ar-adv]). Among them:
  - `aigw run` logs literal API keys ([GHSA-qv6v-2357-v3gm][ar-qv6v]);
  - duplicated `stream_options` keys suppress token accounting ([GHSA-w5rr-gc4v-5946][ar-w5rr]).
- **Enterprise edition.** Tetrate sells one ([Tetrate][ar-ent]).

**Kong AI Gateway**: Kong Gateway's AI plugins.

- **What it is.** Kong Gateway with AI plugins, written in Lua on OpenResty
  ([repository][kong-repo]).
- **The open-source edition.** Kong Gateway OSS is Apache-2.0 and carries only the basic AI
  plugins ([plugins][kong-plugins]). Failover (`ai-proxy-advanced`) and token budgets
  (`ai-rate-limiting-advanced`) are "only available as part of our AI Gateway Enterprise offering"
  ([ai-proxy-advanced][kong-apa], [ai-rate-limiting-advanced][kong-arla]).
- **Releases.**
  - OSS releases stop at the 3.9 line: 3.9.4, 2026-10-12 ([releases][kong-rel],
    [Docker Hub][kong-hub]).
  - Enterprise is at 3.16 ([kong-gateway][kong-gw-hub]).
  - No OSS 3.10 has shipped, and a user's question about one went unanswered
    ([discussion][kong-14405]).
  - Enterprise's free mode is deprecated ([breaking changes][kong-breaking]).
- **AI Gateway 2.x.** A separate product, "managed through Konnect", that needs an Enterprise
  license ([AI Gateway][kong-aigw], [Docker install][kong-aigw-docker]).
- **Advisories.**
  - CVE-2026-1907 (high, 2026-10-12) affects OSS before 3.9.4 ([CVE][kong-cve-1907]).
  - CVE-2026-92544 (high, 2026-11-10) is an SQL injection in the LLM usage counters of Enterprise
    and AI Gateway 2.2.0 ([CVE][kong-cve-92544]).

**Portkey**: an open-source gateway owned by Palo Alto Networks.

- **What it is.** An MIT gateway in TypeScript ([repository][pk-repo], [license][pk-lic]). The
  enterprise gateway is a separate closed image ([Helm values][pk-helm-values]).
- **Governance.** Palo Alto Networks completed its acquisition on 2026-05-29, as "the core AI
  Gateway for Prisma AIRS" ([press release][pk-panw]).
- **Releases.** The open-source gateway's last release is v1.15.2, on 2026-01-12
  ([releases][pk-rel]). Its last commit was 2026-05-25.
- **Advisories.** One, GHSA-hhh5-2cvx-vmfp (medium, 2025-12-01, SSRF) ([advisory][pk-adv]).

**Helicone**: unmaintained.

- **What it is.** Helicone's AI Gateway, a Rust router ([README][hc-readme]).
- **Releases and code.** It only ever shipped betas, the last v0.2.0-beta.30 on 2025-07-21
  ([releases][hc-rel]). Its last code commit was 2025-07-30 ([commits][hc-commits]).
- **License.** Changed to GPL-3.0 on 2025-11-21 ([license][hc-lic]).
- **Ownership.**
  - Mintlify acquired Helicone, announced 2026-03-03, and "Helicone will continue operating in
    maintenance mode" ([Mintlify][hc-mintlify]).
  - The site now says Helicone "is now part of Experiential Labs" ([pull request][hc-5871]).
- **Docs.** The self-hosted gateway docs are gone; the current docs describe only the cloud
  gateway ([gateway docs][hc-gwdocs]).
- **CVEs.**
  - CVE-2026-15508 (medium) is an SSRF in the gateway, where "the vendor … did not respond in any
    way" ([NVD][hc-cve-15508]).
  - Two CVEs are against the platform ([CVE-2026-85178][hc-cve-85178],
    [CVE-2026-108602][hc-cve-108602]).

**TensorZero**: archived.

- **Status.** The repository is archived; its last push was 2026-06-11 ([repository][tz-repo]).
  - Its CEO wrote that "we came to the difficult decision to wind down the project" and that the
    repository "won't be actively maintained" ([Hacker News][tz-hn]).
  - The site says it "is no longer maintained" ([site][tz-site]).
  - The archive's exact date is not on a primary source: the GitHub API doesn't expose it.
- **What it is.** An Apache-2.0 gateway in Rust.
- **Releases.** The final release is 2026.6.0, on 2026-06-04 ([releases][tz-rel]).
- **Advisories.** One, GHSA-824w-x939-6cmc (high): file read and SSRF before 2026.6.0
  ([advisory][tz-adv]).

## vLLM's production-stack router

**What it does.**

- **The router.** vLLM's production-stack is "vLLM's reference system for K8S-native
  cluster-wide deployment" ([repository][ps-repo]), an Apache-2.0 Helm stack whose router,
  `vllm-router`, is Python. Its releases are Helm chart tags, the latest vllm-stack-0.1.14 on
  2026-11-07 ([releases][ps-rel]).
- **Routing logics.** Round-robin, session, KV-aware, load-aware, prefix-aware,
  disaggregated-prefill, and priority ([parser][ps-parser]).
- **Reading `/metrics`.** It polls each engine's `/metrics` every `--engine-stats-interval`,
  30 s by default, and reads `vllm:num_requests_running`, `num_requests_waiting`, and KV-cache
  usage ([engine stats][ps-stats]).
- **Routing by model.** It filters endpoints by model name and supports aliases ([request
  service][ps-request], [router README][ps-readme-router]).
- **Cloud models.** An external-providers config routes a model *name* to an OpenAI-compatible
  provider with a static key. That is routing by name, not fallback from a local row
  ([provider][ps-openai-provider]).
- **Not found.** No client keys, rate limits, or budgets turned up in the files read
  (`parser.py`, `app.py`, `request.py`, and the external-providers code; the rest of the tree
  wasn't read).
- **Traces.** It traces over OTLP (`--otel-endpoint`, [parser][ps-parser]).

**Complements, not competes.** It balances replicas of one model, and each purpose here has one
row with no replica, so it has nothing to balance. It has none of the six bullets' access control,
so it can't replace the gateway. If a purpose gains replicas, it fits beneath the gateway as that
purpose's backend, and its load-aware routing reads the signals that admission needs.

**Related projects from vLLM.**

- **vllm-project/router.** A Rust router, "a fork of SGLang Model Gateway", with the same
  replica-balancing role ([repository][vr-repo]).
- **vLLM Semantic Router.** An Apache-2.0 project that "selects or combines models for each call"
  ([repository][sr-repo]). It runs as an Envoy ExtProc service, and agentgateway documents it as
  an integration ([agentgateway][agw-vsr], [guide][sr-agw]). It bears on the cheaper chat tier,
  below.

## Kubernetes portability

**The spike runs agentgateway's standalone form.** One YAML file serves the four aliases on route
`ai`, one route per `/<alias>/v1` ([`routing.md`](findings/routing.md), "Realignment on route
`ai`").

**Kubernetes mode is configured another way.** It is the control plane and custom resources
under the Gateway API, installed from two Helm charts ([introduction][agw-k8s-intro]). Kubernetes
mode is "not a standalone installation method" ([install][agw-k8s-install]).

**The Kubernetes model form is `AgentgatewayModel`.**

- It is `agentgateway.dev/v1alpha1`, "subject to change" ([models][agw-models]).
- Each resource declares one client-facing model, concrete or virtual (weighted, failover,
  conditional, callout).
- The models on one parent are aggregated into a model router that serves `/v1/models` and the
  standard paths.
- The models doc says it replaces the older form of an `ai` backend on an HTTPRoute.
- Since 1.7 it "is the recommended way to expose LLMs" ([#4307][agw-4307]).

**How the spike's needs map onto it:**

- **Per-alias base URLs.** Supported. Since #2973 (merged 2026-08-12), an HTTPRoute with a
  PathPrefix match and a `backendRef` of `kind: AgentgatewayModel, name: "*"` scopes a model
  router to that prefix ([#2973][agw-2973], [models][agw-models]).
- **Per-model rate limits.** "An AgentgatewayPolicy cannot target an AgentgatewayModel"
  ([models][agw-models]).
  - #4307 asks for a rate limit on a single model, and is still open.
  - Its workarounds are conditional gateway-level rate limits, "capped at 16 entries", or one
    HTTPRoute per model ([#4307][agw-4307]).
  - Embedding's 34 a second would take one of those workarounds.
- **Translation.** The standalone file doesn't carry over: no converter from standalone to
  Kubernetes resources was found in the docs or issues.
  - The mapping is an inference, since no doc states it: `AgentgatewayModel` corresponds to the
    standalone `llm` section, and HTTPRoute with `AgentgatewayBackend` to route `ai`
    ([configuration modes][agw-cfgmodes]).
  - The `agentgateway-standalone` Helm chart is the exception. It runs the same file unchanged,
    as one Deployment with no Gateway API ([v1.7.0][agw-v170]).
- **Admission.** The Gateway API Inference Extension is Kubernetes-native.
  - An `InferencePool` with its endpoint picker chooses among a model's replicas on queue and
    KV-cache metrics ([inference routing][agw-inf-k8s]).
  - Standalone, agentgateway runs as the picker's sidecar, and "standalone request scheduler mode
    does not support `InferencePool`" ([standalone inference][agw-inf-std]).
  - The paper inventory weighed it as replica selection, not purpose admission
    ([`agentgateway.md`](findings/agentgateway.md), "The paper inventory").

**The other candidates.**

- **Agent Router** is Kubernetes-first ([aigw run][ar-run]).
- **Helm charts.**
  - LiteLLM ships one, needing Postgres and Redis ([Helm][lt-helm]).
  - Bifrost ships one ([Helm][bf-helm]).
  - Portkey's charts serve its enterprise image ([chart][pk-helm-readme]); the open-source
    gateway has a plain manifest.
  - TensorZero has a reference chart ([deployment][tz-deploy]).
- **Kong** runs under its Ingress Controller or Operator, and AI Gateway 2.x under Docker Compose
  or Kong Operator ([AI Gateway][kong-aigw]).
- **No Gateway API integration found** for LiteLLM, Bifrost, or Portkey.

## JWT and OIDC

**agentgateway** has every piece in the open-source edition. None was tried live.

- **Consumers.** A `jwtAuth` policy checks issuer, audiences, and JWKS, on a listener, a route,
  or `llm.policies` ([JWT][agw-jwt]). Its default mode, `optional`, "allows requests without a
  JWT token!", so a deployment sets `strict`.
- **Browsers.** v1.7.0 adds an OIDC policy, Authorization Code with PKCE, that serves "both
  browsers and API clients" ([OIDC][agw-oidc], [v1.7.0][agw-v170]).
- **The UI.** It can be served on a gateway of its own with an `oidc`, `jwtAuth`, or `extAuthz`
  policy ([secure the UI][agw-ui]). The copy on the admin interface "stays unauthenticated",
  which is safe only because that address is loopback.
- **The spike's UI today** has no authentication of its own. It rests on gb10-2's loopback and
  SSH ([`agentgateway.md`](findings/agentgateway.md), "Gap: the UI has no authentication of its
  own").
- **A private CA.** Open issue #1883 says the gateway's calls to an identity provider ignore a
  custom CA ([#1883][agw-1883]). That matters on a network with a private CA.

**The other candidates.**

| Candidate | Consumers | UI |
| --- | --- | --- |
| LiteLLM | JWT auth is an Enterprise feature ([JWT][lt-jwt]) | SSO "free for up to 5 users", Enterprise beyond ([SSO][lt-sso]) |
| Bifrost | IdP tokens on Enterprise with SSO ([virtual keys][bf-vk], [workload identity][bf-wi]) | OIDC SSO is Enterprise ([OIDC][bf-oidc]); the open-source edition has a password, off by default ([auth][bf-auth]) |
| Agent Router | JWT, OIDC, and API keys through Envoy Gateway's SecurityPolicy ([security][ar-sec]) | No UI |
| Kong | OSS `jwt` plugin; `openid-connect` is Enterprise ([plugins][kong-plugins]) | No SSO in the OSS config ([kong.conf][kong-conf]); Enterprise's admin SSO not read |
| Portkey | JWT is Enterprise ([JWT][pk-jwt]); the open-source gateway has no consumer authentication on its LLM routes ([keys][pk-keys]) | SSO is Enterprise, on the control plane ([SSO][pk-sso]) |
| Helicone | Helicone API keys only; no JWT found ([README][hc-readme]) | Not researched: the platform's |
| TensorZero | API keys; "Authentication for the UI is coming soon" ([auth][tz-auth]) | None |

**On Azure Container Apps,** built-in authentication ("Easy Auth") runs as a sidecar on each
replica, with Microsoft Entra ID or any OpenID Connect provider ([authentication][aca-auth]).
Whether it validates a bearer token from a service-to-service caller directly is unconfirmed: the
page documents a client-directed flow through `/.auth/login/<provider>`.

## Production's Azure Container Apps routing

**The production shape.** Production has no tailnet. A containerized service on Azure Container
Apps will route inference between Azure AI Foundry and the self-hosted stack, by request and
availability (`standards-lab/context/ai-hosting.md`, "Production").

**What Azure Container Apps provides** ([ingress][aca-ingress]):

- **Ingress:** external or internal; HTTP or TCP; IP restrictions; built-in authentication;
  traffic splitting between revisions; and session affinity.
- **Timeout:** "Request time out is 240 seconds". A long non-streaming agent request near that
  bound would be cut. Whether streamed replies behave differently was not checked.
- **mTLS:** client certificates are supported.
- **Network:** an environment can be internal-only, and private endpoints are supported in
  workload-profile environments ([private endpoints][aca-pe]).
- **Traffic splitting** weights revisions of one app, not backends ([traffic
  splitting][aca-split]), so it isn't the routing between Foundry and the stack.
- **Managed identity** gives the app a token for Azure OpenAI with no key ([managed
  identity][aca-mi]). Azure OpenAI then needs the "Cognitive Services OpenAI User" role and a
  custom subdomain ([Azure OpenAI][aoai-mi]).

**agentgateway on Azure Container Apps.** agentgateway documents running on Container Apps or AKS
and reaching Azure OpenAI with the managed identity, through its `azure` provider with
`auth.azure` ([Azure][agw-aca]).

- The spike didn't use that provider. Its `azure` provider builds neither the verified Foundry
  host nor its path, so each Foundry deployment is a `custom` provider with a key
  ([`priority.md`](findings/priority.md), "Answer for this task").
- Keyless Foundry from Container Apps is therefore documented but unproven here.

**The other candidates on Azure Container Apps.**

- **Portkey** documents a hybrid deployment on Container Apps ([ACA][pk-aca]).
- **LiteLLM's** Azure page covers AKS only ([Azure][lt-azure-deploy]).
- **Kong and Bifrost:** no official Container Apps guide was found.

**Azure's own option.** Azure API Management's AI gateway fronts Foundry models and "Self-hosted
models and endpoints" ([AI gateway][apim-ai]).

- `llm-token-limit` sets a TPM limit or a token quota per counter key ([token limit][apim-tl]).
- Its backends balance round-robin, weighted, priority-based, and session-aware, with a circuit
  breaker that applies `Retry-After` ([backends][apim-backends]).
- It is the managed alternative for the routing between Foundry and the stack. None of it reads
  vLLM's `/metrics`, and its docs were read only for these features.

**Placement.** The six bullets hold for whichever service sits in front of the rows. If the
Container Apps service routes between Foundry and the stack, the self-hosted gateway still owns
the aliases, keys, limits, and fence, and its overflow becomes the Container Apps service's to
weigh. That choice is the gateway document's, not this comparison's.

## IL6

**What IL6 is.**

- **Classification.** IL6 holds information "classified up to the SECRET level". It runs in "a
  closed self-contained environment … connected only to SIPRNet", physically separated from other
  tenants ([IL6][il6]). That text is the DoD Cloud Computing SRG as Microsoft quotes it. DISA's own
  document library couldn't be read: its page redirected, and a mirror refused.
- **Clouds.**
  - Azure Government Secret holds the DoD IL6 provisional authorization; Azure Government Top
    Secret holds ICD 503 ([audit scope][gov-scope]).
  - Both are "dedicated US air-gapped regions" ([national security][gov-ns]).
  - Azure Government's own regions "support only unclassified data up to and including IL5"
    ([DoD][gov-dod]).

**What is available there.**

- **Container Apps is not in IL6 scope.** Microsoft's audit-scope table ticks it for FedRAMP High
  and DoD IL2 only ([audit scope][gov-scope]).
- **In IL6 scope:** AKS, API Management, App Service, Container Instances, and Azure OpenAI.
- **Unknown:** whether Container Apps runs in the Secret or Top Secret clouds. Their service lists
  aren't public.
- **Azure OpenAI.** DISA authorized it for IL6 in Azure Government Secret in early 2025
  ([authorization][aoai-il6]), and GPT-5.2 reached the Secret and Top Secret clouds on 2026-01-15
  ([GPT-5.2][gpt52]).
- **The production shape doesn't carry over.** It assumes Container Apps, which is not in IL6
  scope, so an IL6 deployment needs another host for the routing service, such as AKS.

**No cloud overflow under IL6.** The answer task's plan round decided it (the spike's goal
record, `context/goals/experiment.hosting.spike-model-gateway.md` at `2f2e8c1^`, Decisions, R1 Q8).

- **Why.** Cloud models exist in the Secret cloud, but routing to them crosses the self-hosted
  boundary that IL6 workloads stay inside.
- **What changes in agentgateway.** Each alias's `ai` backend keeps only its row's group. A row
  down then answers with its failure and no Azure fallback, which the layout's no-failover rule
  already expects (spike-model-layout `docs/layout.md`, requirement 6).

**What each candidate needs to run disconnected.**

| Candidate | Disconnected | Source |
| --- | --- | --- |
| agentgateway | Apache-2.0 with no license key. No phone-home is stated in its docs, and a code search found no usage-reporting code; that search is not proof of absence. The model cost catalog takes only a file or inline source. Images come from `cr.agentgateway.dev`, and the Helm values take a private registry. Solo's enterprise control plane checks its license at start and every 24 hours | [schema][agw-schema], [enterprise license][solo-lic] |
| LiteLLM | `LITELLM_OFFLINE_MODE=true` stops the cost-map, release-check, and other fetches. Telemetry is "off unless you turn it on". Enterprise metering "needs outbound HTTPS" | [outbound][lt-offline], [telemetry][lt-tel], [billing][lt-billing] |
| Bifrost | Fetches a pricing datasheet at start, and "Bifrost cannot start" without it, unless `pricing_url` names a file. An announcements feed is on by default. Enterprise images come from a private registry with credentials | [air-gapped][bf-airgap], [on-premise][bf-onprem] |
| Agent Router | Apache-2.0, with no license or SaaS control plane. Needs Kubernetes, Envoy Gateway, and its images mirrored. `aigw run` downloads Envoy through func-e, so the binary must be staged. Phone-home unconfirmed | [aigw run][ar-run] |
| Kong | `anonymous_reports` is on by default and must be turned off. Enterprise and AI Gateway 2.x need a license, set locally. Some 2.x features are Konnect-only. Whether Enterprise's license check goes online is unconfirmed | [kong.conf][kong-conf], [AI Gateway][kong-aigw-docker], [changelog][kong-aigw-log] |
| Portkey | The enterprise hybrid keeps its control plane with Portkey, and "Air-gapped deployment is no longer offered" for new customers. The open-source gateway runs alone, with no telemetry found in its code | [hybrid][pk-hybrid], [air-gapped][pk-airgap] |
| Helicone | With authentication off it contacts no control plane. Authentication needs the Helicone platform, cloud or self-hosted, whose gateway docs are gone. Unmaintained | [config][hc-helicone-cfg] |
| TensorZero | Pseudonymous usage analytics are on by default and can be disabled. Archived | [deployment][tz-deploy] |

## A cheaper chat tier

**What it means here.** Chat requests that don't need gpt-oss-120b go to a cheaper model, such as
Gemma 4 26B-A4B, and gpt-oss-120b is kept for the tasks that need it (the spike's roadmap
summary, as first written). In this layout Gemma 4 26B-A4B is the vision row on gb10-2, so a
cheaper chat tier shares vision's row, its cap of 16, and its queue.

**Two ways to reach it.**

1. **A named tier: its own alias.** A `chat` alias on its own `/chat/v1`, routed to the vision
   row, is one more route `ai` entry in agentgateway's form: the same form that serves the four
   aliases. It was not configured or run. A consumer then picks its tier by base URL, and per-key
   priority on the vision row would rank chat against vision's bulk work as it does today
   ([`priority.md`](findings/priority.md), "Benchmark D: priority on vision (evidence 6)").
2. **A routed tier: the gateway picks the model from the request.**
   - agentgateway's conditional virtual models (a CEL `when`, such as on a header) and callout
     routing (a service that scores the prompt) do this ([virtual models][agw-vm]).
   - Both are in the `llm` section only, which takes one path prefix at v1.7.0
     ([`agentgateway.md`](findings/agentgateway.md), "The paper inventory"). They don't combine
     with per-alias base URLs on route `ai`.
   - vLLM Semantic Router is the content classifier, attached as ExtProc ([agentgateway][agw-vsr]).

**The other candidates.**

- **Bifrost's** routers classify each request as simple, medium, or complex and send each tier to
  its own model. They are in the open-source docs ([routers][bf-routers]).
- **LiteLLM's** auto routing is "[Beta]", and custom classifiers are Enterprise ([auto
  routing][lt-auto]).
- **Kong's** semantic routing is in Enterprise `ai-proxy-advanced` ([ai-proxy-advanced][kong-apa]).
- **Agent Router** routes on headers, including the model from the body
  ([fallback][ar-fallback]).
- **Portkey's** conditional routing matches metadata, parameters, and the path, with no content
  classifier ([conditional routing][pk-cond]).
- **Helicone and TensorZero:** nothing found.

## Scoring

Each cell's mark comes first:

- **proven:** shown live by the spike, citing the finding;
- **documented:** in the candidate's open-source docs or code;
- **enterprise:** in a paid edition only;
- **partial:** documented with a stated shortfall;
- **not found:** absent from the docs and code read;
- **gap:** agentgateway's own, shown on paper.

| Want | agentgateway v1.7.0 | LiteLLM | Bifrost | Agent Router | Kong AI Gateway | Portkey | Helicone | TensorZero |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **1. Admission on live `/metrics` per purpose floor, queueing past caps** | **gap.** Nothing reads a row's `/metrics`, and nothing queues at the gateway; vLLM queues behind it ([`agentgateway.md`](findings/agentgateway.md), "The paper inventory"). A full row's 503 at its queue limit evicts it ([`priority.md`](findings/priority.md), "Answer for this task") | **not found** for `/metrics`. `max_parallel_requests` has "no wait queue"; `dynamic_queue` (1.111, rc) queues only on an upstream 429 ([routing][lt-routing], [settings][lt-cfg]) | **partial.** A per-provider worker pool with a blocking queue; no `/metrics` ([performance][bf-perf]) | **partial, Kubernetes.** An InferencePool's endpoint picker reads queue and KV cache; its queueing is behind a feature gate, off by default ([InferencePool][ar-pool], [flow control][ar-flow]) | **not found** ([ai-proxy-advanced][kong-apa]) | **not found** ([circuit breaker][pk-cb]) | **not found.** A provider is marked unhealthy on its 5xx ratio ([balance][hc-balance]) | **not found** |
| **2. Embedding held to 34 req/s** | **proven.** A global 34/1s bucket admitted 34 of 40 and refused the rest with 429 and `Retry-After: 1` ([`priority.md`](findings/priority.md), "Embedding's limit (behavior 17)"); retried by go-ai ([`answer.md`](findings/answer.md), "Step 5 · the retry proof (behaviors 6–8)") | **partial.** A deployment's `rpm` as a hard limit: per minute, so 2,040 a minute, no per-second bound ([load balancing][lt-lb]) | **partial.** A global model limit; documented windows start at 1 minute ([model limits][bf-limits]) | **documented.** Envoy Gateway's global rate limit, with its rate-limit service and Redis ([rate limiting][ar-ratelimit], [Envoy Gateway][eg-ratelimit]) | **documented.** OSS `rate-limiting`, per `second` ([schema][kong-rl]) | **not found** in OSS; Enterprise limits per minute at the finest ([integrations][pk-integrations]) | **not found.** Per-key limits only ([rate limit][hc-rl]) | **documented.** `model_inferences_per_second` ([rate limits][tz-rl]) |
| **3. Per-consumer keys with budgets, rate limits, and priority** | **proven.** Gateway-issued keys, refused when missing or revoked ([`agentgateway.md`](findings/agentgateway.md), "Behavior 4"). Per-key buckets, token budgets per UTC clock hour charging streams, and vLLM priority per key ([`priority.md`](findings/priority.md), "Slice 3 · keys and limits", "Benchmark D: priority on vision (evidence 6)"). Shortfalls: a fixed hour, and priority orders only the waiting queue | **documented** keys with budgets and rate limits ([virtual keys][lt-vk]). Priority is a per-request beta "for testing only" ([scheduler][lt-sched]); priority reservation is **enterprise** ([dynamic limits][lt-dyn]) | **documented** keys with budgets and rate limits ([virtual keys][bf-vk], [budgets][bf-budget]); priority **not found** | **partial.** Keys through Envoy Gateway; token limits per client ([security][ar-sec], [rate limiting][ar-ratelimit]); priority only through the picker's flow control ([flow control][ar-flow]) | **partial.** OSS keys; token budgets **enterprise** ([ai-rate-limiting-advanced][kong-arla]); priority **not found** | **enterprise.** Budgets and limits ([budgets][pk-budget]); OSS has no consumer keys ([keys][pk-keys]) | **partial.** Per-key request rate only, keys from Helicone's control plane ([rate limit][hc-rl]) | **documented.** Keys, token and cost limits by key ([auth][tz-auth], [rate limits][tz-rl]); priority **not found** |
| **4. Purpose aliases on per-alias base URLs whose `/models` lists only that alias** | **proven.** One route per `/<alias>/v1`; each `/models` lists its alias alone ([`agentgateway.md`](findings/agentgateway.md), "Behavior 3"; [`routing.md`](findings/routing.md), "Realignment on route `ai`"), answered by the gateway ([`priority.md`](findings/priority.md), "Answer for this task") | **partial.** One global root path; `/models` scoped per key or team ([settings][lt-cfg], [model access][lt-access]) | **partial.** One base path; `/models` scoped per virtual key ([virtual keys][bf-vk]) | **partial.** `/models` scoped by Host, not path; prefixes set once per install ([endpoints][ar-endpoints], [code][ar-models-code]) | **partial.** A route per path; no client-facing `/models` found ([ai-proxy][kong-ap]) | **not found.** Fixed `/v1`; `/models` per hosted workspace ([models][pk-models]) | **partial.** `/router/<name>` per router, but chat completions only, and no `/models` ([endpoints][hc-endpoints]) | **not found** |
| **5. Overflow to Azure AI Foundry under the same alias** | **proven** with a row down: priority groups and eviction, marked by a header ([`priority.md`](findings/priority.md), "A row down (behaviors 7, 8)"). With a row full, only after its 503s evict it, sending nearly the whole load to Azure ("Benchmark C-agent (behavior 9)") | **documented.** Deployments of one `model_name` by `order`, on connection errors, 429, and the like ([routing][lt-routing]) | **documented.** Fallbacks on any error, to Azure ([retries and fallbacks][bf-retries], [routing][bf-routing]) | **documented.** `backendRefs` priority with retry triggers, to Azure ([provider fallback][ar-fallback], [providers][ar-providers]) | **enterprise.** `ai-proxy-advanced` failover ([ai-proxy-advanced][kong-apa]) | **documented.** Fallback on non-2xx or listed codes ([fallbacks][pk-fallback]) | **not found.** No Azure provider ([providers][hc-providers]) | **documented.** Providers tried in order, Azure among them ([fallbacks][tz-fallback]) |
| **6. Consumer keys reach serving routes only** | **proven.** Unrouted and non-serving paths get 404, a missing key 401, and the admin API stays on the container's loopback ([`agentgateway.md`](findings/agentgateway.md), "Behavior 2", "Behavior 5"; [`routing.md`](findings/routing.md), "Realignment on route `ai`"). Dot segments pass to the row unnormalized, so hardening is required ("Dot segments" there) | **partial.** Per-key `allowed_routes`; management access follows the owner's role; global route controls are **enterprise** ([virtual keys][lt-vk], [public routes][lt-public]) | **partial.** The admin API shares the inference port, its password off by default ([auth][bf-auth], [security][bf-secbp]) | **documented.** Configured by Kubernetes resources, with no admin API on the proxy (an inference from its docs); allow-lists through Envoy Gateway ([security][ar-sec]) | **documented.** Admin API on loopback by default; OSS `acl` ([kong.conf][kong-conf]) | **partial.** OSS has no consumer authentication; Enterprise scopes keys ([keys][pk-keys]) | **partial.** No admin API, but authentication is off by default ([#307][hc-307]) | **not found** |
| **Traces over OTLP** | **proven.** The gateway's span parents the row's through `traceparent`; an overflowed trace has no row span; no content in any span ([`answer.md`](findings/answer.md), "Slice 2 · traces") | **documented**, GenAI conventions ([OpenTelemetry][lt-otel]) | **documented** ([OpenTelemetry][bf-otel]) | **documented** ([tracing][ar-trace]) | **documented**, OTLP/HTTP; GenAI attributes from 3.13, an Enterprise version ([OpenTelemetry][kong-otel]) | **enterprise** ([OpenTelemetry][pk-otel]) | **documented** in code ([telemetry][hc-telemetry]) | **documented**, gRPC ([OpenTelemetry][tz-otel]) |
| **License** | Apache-2.0 ([license][agw-lic]) | MIT, with a proprietary `enterprise/` ([license][lt-lic]) | Apache-2.0; enterprise closed ([license][bf-lic], [enterprise][bf-ent]) | Apache-2.0 ([README][ar-readme]) | Apache-2.0 OSS, frozen at 3.9.x; Enterprise licensed ([releases][kong-rel], [breaking changes][kong-breaking]) | MIT; enterprise closed ([license][pk-lic]) | GPL-3.0 since 2025-11-21 ([license][hc-lic]) | Apache-2.0 ([repository][tz-repo]) |
| **Governance** | LF project, AAIF-hosted since 2026-06-04; maintainers mostly Solo.io ([AAIF][agw-aaif], [maintainers][agw-maint]) | BerriAI alone ([license][lt-lic]) | Maxim AI alone ([repository][bf-repo]) | AAIF since 2026-09-09; no company holds a majority of maintainer seats ([AAIF][ar-aaif]) | Kong Inc. ([repository][kong-repo]) | Palo Alto Networks since 2026-05-29 ([press release][pk-panw]) | Mintlify, in maintenance mode; now "part of Experiential Labs" ([Mintlify][hc-mintlify], [pull request][hc-5871]) | Wound down ([Hacker News][tz-hn]) |
| **Runtime and cadence** | Rust; about monthly; v1.7.0, 2026-10-27 ([releases][agw-rel]) | Python, routing in a Rust core since v1.110.0; weekly ([router][lt-router-rust], [release cycle][lt-cycle]) | Go; minor every 3–4 weeks; v2.6.0, 2026-11-19 ([cadence][bf-cadence]) | Go and Envoy; every 6–8 weeks; v1.3.0, 2026-11-18 ([releases][ar-rel]) | Lua on OpenResty; OSS 3.9.4, 2026-10-12, no 3.10 ([releases][kong-rel]) | TypeScript; last v1.15.2, 2026-01-12 ([releases][pk-rel]) | Rust; betas only, last 2025-07-21 ([releases][hc-rel]) | Rust; final 2026.6.0, 2026-06-04 ([releases][tz-rel]) |
| **Advisories** | 7 GHSAs in 2026, all MCP or Kubernetes, none affecting v1.7.0 ([advisories][agw-adv]) | Two supply-chain compromises in 2026, and critical advisories through 2026-10-27 ([October][lt-oct], [advisories][lt-adv]) | A critical MCP RCE and an unauthenticated RCE on the default-open admin API, 2026-09 ([advisories][bf-adv]) | 24 GHSAs in 2026, mostly MCP; `aigw run` logged keys ([advisories][ar-adv]) | OSS CVE-2026-1907 (high); Enterprise CVE-2026-92544, SQL injection in LLM usage counters ([CVE][kong-cve-1907], [CVE][kong-cve-92544]) | One medium SSRF, 2025 ([advisory][pk-adv]) | A gateway SSRF the vendor didn't answer; authentication off by default ([NVD][hc-cve-15508], [#307][hc-307]) | One high, fixed in the final release ([advisory][tz-adv]) |

## Conclusion

Nothing on paper beats agentgateway for this layout.

- **Bullets.** It is the only candidate to have shown five of the six bullets live. It is the only
  one whose open-source edition serves per-alias base URLs, each with its own `/models`.
- **Foundation.** It sits in a foundation, the AAIF, with no advisory against its LLM path.
- **The sixth bullet** is admission on `/metrics` with queueing at the gateway. No candidate does
  it natively: Agent Router comes closest, through the llm-d endpoint picker on Kubernetes.
- **The nearest rivals:**
  - Agent Router, in the same foundation, is Kubernetes-first and scopes `/models` by host, not
    path.
  - Bifrost leaves its admin API open by default, and has had critical RCEs.
  - LiteLLM's 2026 record stands against it.

**What would change the decision:**

- production moving to Kubernetes with replicas per purpose, where Agent Router's picker or
  agentgateway's Kubernetes form would be weighed;
- agentgateway deprecating route `ai` without parity ([`watch.md`](watch.md));
- admission on `/metrics` becoming a hard requirement;
- an advisory against agentgateway's LLM path.

## Unconfirmed

Each claim here couldn't be confirmed from a primary source on 2026-11-18, and the text above
marks it where it appears.

**Repository and project facts:**

- **TensorZero's archive date.** The GitHub API doesn't expose it. Only secondary sources give
  2026-06-12.
- **Helicone's move to Experiential Labs.** Its terms are unconfirmed: only Helicone's own banner
  states it. Helicone's own acquisition post returns 404, and its self-hosted gateway docs are
  gone, so every Helicone feature above is read from source at its last commit.
- **Bifrost's critical MCP RCE.** CVE-2026-90898 looks like GHSA-86gf-xh3g-rvxq, but OSV lists no
  alias.
- **agentgateway's CVE-2026-29791** is rated 4.9 on its GHSA and 6.5 by third-party databases.
- **LiteLLM's Rust work.** No statement that a standalone Rust server is production-ready was
  found. Its "[Beta] Rust AI Gateway" page returns 404.

**Features:**

- **Priority to vLLM.** Whether LiteLLM forwards a per-key `priority` to vLLM, or Bifrost's
  extra-parameter passthrough does.
- **Rate-limit windows.** Whether Bifrost's model limits take a 1-second window. Whether
  LiteLLM's `LITELLM_RATE_LIMIT_WINDOW_SIZE` applies to a model's `rpm`.
- **Portkey's circuit breaker** without a control plane.
- **Agent Router:**
  - whether the endpoint picker behaves with a one-replica InferencePool;
  - whether fallback from an InferencePool backend works;
  - Envoy Gateway's per-second rate-limit unit, read only through Agent Router's docs.
- **Kong:**
  - Enterprise's admin SSO configuration;
  - whether Kong Enterprise's license check goes online.
- **Phone-home.** Whether Agent Router phones home. agentgateway's docs don't state it either way.
- **Azure Container Apps:**
  - whether Easy Auth validates a service-to-service bearer token directly;
  - whether the 240 s timeout applies to streamed replies;
  - whether Container Apps is GA in Azure Government (its only announcement found is a 2024
    public preview), or present in the Secret and Top Secret clouds.

**Sources that couldn't be read:**

- **The DoD Cloud Computing SRG.** DISA's library redirected and a mirror refused, so IL6's
  definition is Microsoft's quotation of it.
- **Kong's advisories.** No authoritative Kong advisory index was found, so Kong's CVE list may be
  incomplete. Its CVE records were read from MITRE's CVE API, since NVD's pages didn't render.
- **NVD for 2025.** NVD's API mostly failed for LiteLLM's 2025 range, so that range is the GitHub
  Advisory Database's.

**Coverage:**

- **vLLM production-stack's router.** The absence of client keys, rate limits, and budgets rests
  on the files read, not the whole tree.
- **The vLLM project's governance.** Whether production-stack is hosted by the PyTorch
  Foundation, as vLLM is ([PyTorch][pt-vllm]), wasn't found.

## Sources

All read on 2026-11-18.

**agentgateway**

[agw-lic]: https://github.com/agentgateway/agentgateway/blob/main/LICENSE
[agw-charter]: https://github.com/agentgateway/agentgateway/blob/main/CHARTER.md
[agw-lf]: https://www.linuxfoundation.org/press/linux-foundation-welcomes-agentgateway-project-to-accelerate-ai-agent-adoption-while-maintaining-security-observability-and-governance
[agw-aaif]: https://aaif.io/blog/agentgateway-joins-aaif-as-an-open-gateway-for-agentic-ai-infrastructure
[agw-maint]: https://github.com/agentgateway/community/blob/main/MAINTAINERS.md
[agw-rel]: https://github.com/agentgateway/agentgateway/releases
[agw-v170]: https://github.com/agentgateway/agentgateway/releases/tag/v1.7.0
[agw-adv]: https://github.com/agentgateway/agentgateway/security/advisories
[agw-ent]: https://agentgateway.dev/enterprise
[solo-lic]: https://docs.solo.io/agentgateway/kubernetes/latest/documentation/install/licensing/
[agw-jwt]: https://agentgateway.dev/docs/standalone/latest/documentation/configuration/security/jwt-authn/
[agw-oidc]: https://agentgateway.dev/docs/standalone/latest/documentation/configuration/security/oidc/
[agw-ui]: https://agentgateway.dev/docs/standalone/latest/documentation/setup/ui/secure-ui/
[agw-1883]: https://github.com/agentgateway/agentgateway/issues/1883
[agw-k8s-intro]: https://agentgateway.dev/docs/standalone/latest/documentation/about/introduction/
[agw-k8s-install]: https://agentgateway.dev/docs/standalone/latest/documentation/setup/install/kubernetes/
[agw-models]: https://agentgateway.dev/docs/kubernetes/latest/documentation/llm/models/about/
[agw-4307]: https://github.com/agentgateway/agentgateway/issues/4307
[agw-2973]: https://github.com/agentgateway/agentgateway/pull/2973
[agw-cfgmodes]: https://agentgateway.dev/docs/standalone/latest/documentation/llm/configuration-modes/
[agw-inf-k8s]: https://agentgateway.dev/docs/kubernetes/latest/documentation/llm/inference/inference-routing/
[agw-inf-std]: https://agentgateway.dev/docs/standalone/latest/documentation/llm/inference/
[agw-vm]: https://agentgateway.dev/docs/standalone/latest/documentation/llm/virtual-models/
[agw-vsr]: https://agentgateway.dev/docs/standalone/latest/integrations/llm/routing/vllm-semantic-router/
[agw-aca]: https://agentgateway.dev/docs/standalone/latest/integrations/cloud-providers/azure/
[agw-schema]: https://raw.githubusercontent.com/agentgateway/agentgateway/v1.7.0/schema/config.md

- [License][agw-lic], [charter][agw-charter], [Linux Foundation][agw-lf], [AAIF][agw-aaif],
  [maintainers][agw-maint]
- [Releases][agw-rel], [v1.7.0][agw-v170], [advisories][agw-adv], [enterprise][agw-ent],
  [Solo licensing][solo-lic]
- [JWT][agw-jwt], [OIDC][agw-oidc], [securing the UI][agw-ui], [#1883][agw-1883]
- [Introduction][agw-k8s-intro], [Kubernetes install][agw-k8s-install], [models][agw-models],
  [#4307][agw-4307], [#2973][agw-2973], [configuration modes][agw-cfgmodes]
- [Inference routing][agw-inf-k8s], [standalone inference][agw-inf-std], [virtual models][agw-vm],
  [vLLM Semantic Router][agw-vsr], [Azure][agw-aca], [v1.7.0 schema][agw-schema]

**LiteLLM**

[lt-repo]: https://github.com/BerriAI/litellm
[lt-lic]: https://github.com/BerriAI/litellm/blob/main/LICENSE
[lt-entlic]: https://github.com/BerriAI/litellm/blob/main/litellm/enterprise/LICENSE.md
[lt-rel]: https://github.com/BerriAI/litellm/releases
[lt-cycle]: https://docs.litellm.ai/docs/proxy/release_cycle
[lt-adv]: https://github.com/BerriAI/litellm/security/advisories
[lt-7hp6]: https://github.com/BerriAI/litellm/security/advisories/GHSA-7hp6-4w63-5g45
[lt-w4c7]: https://github.com/BerriAI/litellm/security/advisories/GHSA-w4c7-34wj-hqm8
[lt-2rwg]: https://github.com/BerriAI/litellm/security/advisories/GHSA-2rwg-2wh4-7c4f
[lt-mar]: https://docs.litellm.ai/blog/security-update-march-2026
[lt-oct]: https://docs.litellm.ai/blog/security-incident-oct-21-2026
[lt-chain]: https://docs.litellm.ai/blog/security-incident-oct-21-2026-attack-chain
[lt-after]: https://docs.litellm.ai/blog/security-changes-after-oct-21-2026
[lt-mal]: https://github.com/advisories/GHSA-92x9-889m-jgmw
[lt-rust-launch]: https://docs.litellm.ai/blog/litellm-rust-launch
[lt-rust-bench]: https://docs.litellm.ai/blog/rust-ai-gateway-benchmarks
[lt-router-rust]: https://docs.litellm.ai/blog/router-rust
[lt-rerouted]: https://docs.litellm.ai/blog/rust-migration-rerouted
[lt-routing]: https://docs.litellm.ai/docs/routing
[lt-cfg]: https://docs.litellm.ai/docs/proxy/config_settings
[lt-lb]: https://docs.litellm.ai/docs/proxy/load_balancing
[lt-vk]: https://docs.litellm.ai/docs/proxy/virtual_keys
[lt-sched]: https://docs.litellm.ai/docs/scheduler
[lt-dyn]: https://docs.litellm.ai/docs/proxy/dynamic_rate_limit
[lt-access]: https://docs.litellm.ai/docs/proxy/model_access
[lt-public]: https://docs.litellm.ai/docs/proxy/public_routes
[lt-otel]: https://docs.litellm.ai/docs/observability/opentelemetry_v2
[lt-jwt]: https://docs.litellm.ai/docs/proxy/token_auth
[lt-sso]: https://docs.litellm.ai/docs/proxy/admin_ui_sso
[lt-helm]: https://docs.litellm.ai/docs/proxy/deploy/helm
[lt-offline]: https://docs.litellm.ai/docs/proxy/outbound_requests
[lt-tel]: https://docs.litellm.ai/docs/proxy/telemetry
[lt-billing]: https://docs.litellm.ai/docs/proxy/billing_metrics
[lt-auto]: https://docs.litellm.ai/docs/proxy/auto_routing
[lt-azure-deploy]: https://docs.litellm.ai/docs/proxy/deploy/cloud/azure

- [Repository][lt-repo], [license][lt-lic], [enterprise license][lt-entlic], [releases][lt-rel],
  [release cycle][lt-cycle]
- [Advisories][lt-adv], [GHSA-7hp6-4w63-5g45][lt-7hp6], [GHSA-w4c7-34wj-hqm8][lt-w4c7],
  [GHSA-2rwg-2wh4-7c4f][lt-2rwg], [GHSA-92x9-889m-jgmw][lt-mal]
- [March 2026][lt-mar], [October 21][lt-oct], [attack chain][lt-chain], [changes after][lt-after]
- [Rust launch][lt-rust-launch], [Rust benchmarks][lt-rust-bench], [router in Rust][lt-router-rust],
  [migration rerouted][lt-rerouted]
- [Routing][lt-routing], [config settings][lt-cfg], [load balancing][lt-lb],
  [virtual keys][lt-vk], [scheduler][lt-sched], [dynamic rate limits][lt-dyn],
  [model access][lt-access], [public routes][lt-public], [auto routing][lt-auto]
- [OpenTelemetry][lt-otel], [JWT][lt-jwt], [UI SSO][lt-sso], [Helm][lt-helm],
  [outbound requests][lt-offline], [telemetry][lt-tel], [billing metrics][lt-billing],
  [Azure][lt-azure-deploy]

**Bifrost**

[bf-repo]: https://github.com/maximhq/bifrost
[bf-lic]: https://github.com/maximhq/bifrost/blob/dev/LICENSE
[bf-ent]: https://docs.getbifrost.ai/enterprise/overview.md
[bf-onprem]: https://docs.getbifrost.ai/deployment-guides/enterprise/on-premise.md
[bf-rel]: https://github.com/maximhq/bifrost/releases
[bf-cadence]: https://docs.getbifrost.ai/release-cadence.md
[bf-adv]: https://github.com/maximhq/bifrost/security/advisories
[bf-86gf]: https://github.com/maximhq/bifrost/security/advisories/GHSA-86gf-xh3g-rvxq
[bf-2qp8]: https://github.com/maximhq/bifrost/security/advisories/GHSA-2qp8-4xgm-fw6g
[bf-w98g]: https://github.com/maximhq/bifrost/security/advisories/GHSA-w98g-5w9p-p3rc
[bf-perf]: https://docs.getbifrost.ai/providers/performance.md
[bf-limits]: https://docs.getbifrost.ai/features/governance/model-limits.md
[bf-budget]: https://docs.getbifrost.ai/features/governance/budget-and-limits.md
[bf-vk]: https://docs.getbifrost.ai/features/governance/virtual-keys.md
[bf-routing]: https://docs.getbifrost.ai/features/governance/routing.md
[bf-retries]: https://docs.getbifrost.ai/features/retries-and-fallbacks.md
[bf-auth]: https://docs.getbifrost.ai/quickstart/gateway/setting-up-auth.md
[bf-secbp]: https://docs.getbifrost.ai/deployment-guides/how-to/security-best-practices.md
[bf-otel]: https://docs.getbifrost.ai/features/otel.md
[bf-oidc]: https://docs.getbifrost.ai/enterprise/setting-up-generic-oidc/oidc.md
[bf-wi]: https://docs.getbifrost.ai/enterprise/workload-identity/overview.md
[bf-helm]: https://docs.getbifrost.ai/deployment-guides/helm.md
[bf-airgap]: https://docs.getbifrost.ai/deployment-guides/how-to/airgapped.md
[bf-routers]: https://docs.getbifrost.ai/features/routers.md

- [Repository][bf-repo], [license][bf-lic], [enterprise][bf-ent], [on-premise][bf-onprem],
  [releases][bf-rel], [release cadence][bf-cadence]
- [Advisories][bf-adv], [GHSA-86gf-xh3g-rvxq][bf-86gf], [GHSA-2qp8-4xgm-fw6g][bf-2qp8],
  [GHSA-w98g-5w9p-p3rc][bf-w98g]
- [Performance][bf-perf], [model limits][bf-limits], [budgets and limits][bf-budget],
  [virtual keys][bf-vk], [routing][bf-routing], [retries and fallbacks][bf-retries],
  [routers][bf-routers]
- [Setting up auth][bf-auth], [security best practices][bf-secbp], [OpenTelemetry][bf-otel],
  [OIDC][bf-oidc], [workload identity][bf-wi], [Helm][bf-helm], [air-gapped][bf-airgap]

**Agent Router**

[ar-readme]: https://github.com/theagentrouter/agent-router/blob/main/README.md
[ar-aaif]: https://aaif.io/blog/agent-router-joins-aaif
[ar-proj]: https://aaif.io/projects/agent-router
[ar-rel]: https://github.com/theagentrouter/agent-router/releases
[ar-compat]: https://theagentrouter.ai/docs/compatibility
[ar-adv]: https://github.com/theagentrouter/agent-router/security/advisories
[ar-qv6v]: https://github.com/theagentrouter/agent-router/security/advisories/GHSA-qv6v-2357-v3gm
[ar-w5rr]: https://github.com/theagentrouter/agent-router/security/advisories/GHSA-w5rr-gc4v-5946
[ar-ent]: https://tetrate.io/blog/announcing-agent-router-enterprise
[ar-run]: https://theagentrouter.ai/docs/cli/aigwrun
[ar-pool]: https://theagentrouter.ai/docs/capabilities/inference/inferencepool-support
[ar-flow]: https://github.com/llm-d/llm-d-router/blob/main/pkg/epp/flowcontrol/README.md
[ar-ratelimit]: https://theagentrouter.ai/docs/capabilities/traffic/usage-based-ratelimiting
[eg-ratelimit]: https://gateway.envoyproxy.io/docs/tasks/traffic/global-rate-limit/
[ar-sec]: https://theagentrouter.ai/docs/capabilities/security
[ar-endpoints]: https://theagentrouter.ai/docs/capabilities/llm-integrations/supported-endpoints
[ar-models-code]: https://github.com/theagentrouter/agent-router/blob/main/internal/extproc/models_processor.go
[ar-fallback]: https://theagentrouter.ai/docs/capabilities/traffic/provider-fallback
[ar-providers]: https://theagentrouter.ai/docs/getting-started/connect-providers/
[ar-trace]: https://theagentrouter.ai/docs/capabilities/observability/tracing

- [README][ar-readme], [AAIF][ar-aaif], [AAIF project][ar-proj], [releases][ar-rel],
  [compatibility][ar-compat], [Tetrate enterprise][ar-ent]
- [Advisories][ar-adv], [GHSA-qv6v-2357-v3gm][ar-qv6v], [GHSA-w5rr-gc4v-5946][ar-w5rr]
- [`aigw run`][ar-run], [InferencePool][ar-pool], [llm-d flow control][ar-flow],
  [rate limiting][ar-ratelimit], [Envoy Gateway global rate limit][eg-ratelimit],
  [security][ar-sec], [endpoints][ar-endpoints], [models code][ar-models-code],
  [provider fallback][ar-fallback], [providers][ar-providers], [tracing][ar-trace]

**Kong AI Gateway**

[kong-repo]: https://github.com/Kong/kong
[kong-plugins]: https://github.com/Kong/kong/tree/master/kong/plugins
[kong-apa]: https://developer.konghq.com/plugins/ai-proxy-advanced/
[kong-arla]: https://developer.konghq.com/plugins/ai-rate-limiting-advanced/
[kong-ap]: https://developer.konghq.com/plugins/ai-proxy/
[kong-rel]: https://github.com/Kong/kong/releases
[kong-hub]: https://hub.docker.com/_/kong
[kong-gw-hub]: https://hub.docker.com/r/kong/kong-gateway
[kong-14405]: https://github.com/Kong/kong/discussions/14405
[kong-breaking]: https://developer.konghq.com/gateway/breaking-changes/
[kong-aigw]: https://developer.konghq.com/ai-gateway/
[kong-aigw-docker]: https://developer.konghq.com/ai-gateway/install/docker/
[kong-aigw-log]: https://developer.konghq.com/ai-gateway/changelog/
[kong-cve-1907]: https://cveawg.mitre.org/api/cve/CVE-2026-1907
[kong-cve-92544]: https://cveawg.mitre.org/api/cve/CVE-2026-92544
[kong-rl]: https://github.com/Kong/kong/blob/master/kong/plugins/rate-limiting/schema.lua
[kong-conf]: https://github.com/Kong/kong/blob/master/kong.conf.default
[kong-otel]: https://developer.konghq.com/plugins/opentelemetry/

- [Repository][kong-repo], [plugins][kong-plugins], [releases][kong-rel], [Docker Hub][kong-hub],
  [kong-gateway][kong-gw-hub], [discussion #14405][kong-14405], [breaking changes][kong-breaking]
- [ai-proxy][kong-ap], [ai-proxy-advanced][kong-apa], [ai-rate-limiting-advanced][kong-arla],
  [rate-limiting schema][kong-rl], [kong.conf.default][kong-conf], [OpenTelemetry][kong-otel]
- [AI Gateway][kong-aigw], [AI Gateway on Docker][kong-aigw-docker],
  [AI Gateway changelog][kong-aigw-log], [CVE-2026-1907][kong-cve-1907],
  [CVE-2026-92544][kong-cve-92544]

**Portkey**

[pk-repo]: https://github.com/Portkey-AI/gateway
[pk-lic]: https://github.com/Portkey-AI/gateway/blob/main/LICENSE
[pk-helm-values]: https://github.com/Portkey-AI/helm/blob/main/charts/portkey-gateway/values.yaml
[pk-helm-readme]: https://github.com/Portkey-AI/helm/blob/main/charts/portkey-gateway/README.md
[pk-panw]: https://www.paloaltonetworks.com/company/press/2026/palo-alto-networks-completes-acquisition-of-portkey-to-secure-ai-agents
[pk-rel]: https://github.com/Portkey-AI/gateway/releases
[pk-adv]: https://github.com/Portkey-AI/gateway/security/advisories/GHSA-hhh5-2cvx-vmfp
[pk-cb]: https://portkey.ai/docs/product/ai-gateway/circuit-breaker
[pk-integrations]: https://portkey.ai/docs/product/model-catalog/integrations
[pk-budget]: https://portkey.ai/docs/product/administration/enforce-budget-and-rate-limit
[pk-keys]: https://portkey.ai/docs/product/enterprise-offering/org-management/api-keys-authn-and-authz
[pk-models]: https://portkey.ai/docs/api-reference/inference-api/models/models
[pk-fallback]: https://portkey.ai/docs/product/ai-gateway/fallbacks
[pk-cond]: https://portkey.ai/docs/product/ai-gateway/conditional-routing
[pk-otel]: https://portkey.ai/docs/product/enterprise-offering/otel/otel
[pk-jwt]: https://portkey.ai/docs/product/enterprise-offering/org-management/jwt
[pk-sso]: https://portkey.ai/docs/product/enterprise-offering/org-management/sso
[pk-hybrid]: https://portkey.ai/docs/self-hosting/hybrid-deployments/architecture
[pk-airgap]: https://portkey.ai/docs/self-hosting/airgapped/model-pricing
[pk-aca]: https://portkey.ai/docs/self-hosting/hybrid-deployments/azure/aca

- [Repository][pk-repo], [license][pk-lic], [Helm values][pk-helm-values],
  [Helm chart][pk-helm-readme], [Palo Alto Networks][pk-panw], [releases][pk-rel],
  [GHSA-hhh5-2cvx-vmfp][pk-adv]
- [Circuit breaker][pk-cb], [integrations][pk-integrations], [budgets][pk-budget],
  [API keys][pk-keys], [models][pk-models], [fallbacks][pk-fallback],
  [conditional routing][pk-cond]
- [OpenTelemetry][pk-otel], [JWT][pk-jwt], [SSO][pk-sso], [hybrid][pk-hybrid],
  [air-gapped][pk-airgap], [Azure Container Apps][pk-aca]

**Helicone**

[hc-readme]: https://github.com/Helicone/ai-gateway/blob/main/README.md
[hc-commits]: https://github.com/Helicone/ai-gateway/commits/main
[hc-lic]: https://github.com/Helicone/ai-gateway/blob/main/LICENSE
[hc-rel]: https://github.com/Helicone/ai-gateway/releases
[hc-mintlify]: https://www.mintlify.com/blog/mintlify-acquires-helicone
[hc-5871]: https://github.com/Helicone/helicone/pull/5871
[hc-gwdocs]: https://docs.helicone.ai/gateway/overview.md
[hc-cve-15508]: https://nvd.nist.gov/vuln/detail/CVE-2026-15508
[hc-cve-85178]: https://nvd.nist.gov/vuln/detail/CVE-2026-85178
[hc-cve-108602]: https://nvd.nist.gov/vuln/detail/CVE-2026-108602
[hc-307]: https://github.com/Helicone/ai-gateway/issues/307
[hc-endpoints]: https://github.com/Helicone/ai-gateway/blob/main/ai-gateway/src/endpoints/mod.rs
[hc-balance]: https://github.com/Helicone/ai-gateway/blob/main/ai-gateway/src/config/balance.rs
[hc-rl]: https://github.com/Helicone/ai-gateway/blob/main/ai-gateway/src/config/rate_limit.rs
[hc-helicone-cfg]: https://github.com/Helicone/ai-gateway/blob/main/ai-gateway/src/config/helicone.rs
[hc-providers]: https://github.com/Helicone/ai-gateway/blob/main/ai-gateway/config/embedded/providers.yaml
[hc-telemetry]: https://github.com/Helicone/ai-gateway/blob/main/crates/telemetry/src/lib.rs

- [README][hc-readme], [commits][hc-commits], [license][hc-lic], [releases][hc-rel],
  [Mintlify][hc-mintlify], [pull request #5871][hc-5871], [gateway docs][hc-gwdocs]
- [CVE-2026-15508][hc-cve-15508], [CVE-2026-85178][hc-cve-85178],
  [CVE-2026-108602][hc-cve-108602], [#307][hc-307]
- [Endpoints][hc-endpoints], [balance][hc-balance], [rate limit][hc-rl],
  [Helicone config][hc-helicone-cfg], [providers][hc-providers], [telemetry][hc-telemetry]

**TensorZero**

[tz-repo]: https://github.com/tensorzero/tensorzero
[tz-hn]: https://news.ycombinator.com/item?id=48516504
[tz-site]: https://www.tensorzero.com/
[tz-rel]: https://github.com/tensorzero/tensorzero/releases
[tz-adv]: https://github.com/tensorzero/tensorzero/security/advisories/GHSA-824w-x939-6cmc
[tz-rl]: https://www.tensorzero.com/docs/operations/enforce-custom-rate-limits
[tz-auth]: https://www.tensorzero.com/docs/operations/set-up-auth-for-tensorzero
[tz-fallback]: https://www.tensorzero.com/docs/gateway/guides/retries-fallbacks
[tz-otel]: https://www.tensorzero.com/docs/operations/export-opentelemetry-traces
[tz-deploy]: https://www.tensorzero.com/docs/deployment/tensorzero-gateway

- [Repository][tz-repo], [Hacker News][tz-hn], [site][tz-site], [releases][tz-rel],
  [GHSA-824w-x939-6cmc][tz-adv]
- [Rate limits][tz-rl], [auth][tz-auth], [retries and fallbacks][tz-fallback],
  [OpenTelemetry][tz-otel], [deployment][tz-deploy]

**vLLM**

[ps-repo]: https://github.com/vllm-project/production-stack
[ps-rel]: https://github.com/vllm-project/production-stack/releases
[ps-parser]: https://github.com/vllm-project/production-stack/blob/main/src/vllm_router/parsers/parser.py
[ps-stats]: https://github.com/vllm-project/production-stack/blob/main/src/vllm_router/stats/engine_stats.py
[ps-request]: https://github.com/vllm-project/production-stack/blob/main/src/vllm_router/services/request_service/request.py
[ps-readme-router]: https://github.com/vllm-project/production-stack/blob/main/src/vllm_router/README.md
[ps-openai-provider]: https://github.com/vllm-project/production-stack/blob/main/src/vllm_router/external_providers/openai_provider.py
[vr-repo]: https://github.com/vllm-project/router
[sr-repo]: https://github.com/vllm-project/semantic-router
[sr-agw]: https://github.com/vllm-project/semantic-router/blob/main/website/docs/installation/k8s/agentgateway.md
[pt-vllm]: https://pytorch.org/blog/pytorch-foundation-welcomes-vllm/

- [production-stack][ps-repo], [releases][ps-rel], [parser][ps-parser],
  [engine stats][ps-stats], [request service][ps-request], [router README][ps-readme-router],
  [OpenAI provider][ps-openai-provider]
- [vllm-project/router][vr-repo], [Semantic Router][sr-repo],
  [Semantic Router with agentgateway][sr-agw], [PyTorch Foundation][pt-vllm]

**Azure**

[aca-ingress]: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
[aca-split]: https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
[aca-pe]: https://learn.microsoft.com/en-us/azure/container-apps/private-endpoints-with-dns
[aca-auth]: https://learn.microsoft.com/en-us/azure/container-apps/authentication
[aca-mi]: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
[aoai-mi]: https://learn.microsoft.com/en-us/azure/foundry-classic/openai/how-to/managed-identity
[apim-ai]: https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities
[apim-tl]: https://learn.microsoft.com/en-us/azure/api-management/llm-token-limit-policy
[apim-backends]: https://learn.microsoft.com/en-us/azure/api-management/backends
[gov-scope]: https://learn.microsoft.com/en-us/azure/azure-government/compliance/azure-services-in-fedramp-auditscope
[il6]: https://learn.microsoft.com/en-us/azure/compliance/offerings/offering-dod-il6
[gov-dod]: https://learn.microsoft.com/en-us/azure/azure-government/documentation-government-overview-dod
[gov-ns]: https://azure.microsoft.com/en-us/explore/global-infrastructure/government/national-security/
[aoai-il6]: https://devblogs.microsoft.com/azuregov/azure-openai-authorization/
[gpt52]: https://devblogs.microsoft.com/azuregov/advancing-ai-capabilities-in-azure-for-u-s-government-secret-and-top-secret-clouds/

- [Container Apps ingress][aca-ingress], [traffic splitting][aca-split],
  [private endpoints][aca-pe], [authentication][aca-auth], [managed identity][aca-mi],
  [Azure OpenAI managed identity][aoai-mi]
- [API Management AI gateway][apim-ai], [llm-token-limit][apim-tl], [backends][apim-backends]
- [Audit scope][gov-scope], [DoD IL6][il6], [Azure Government for DoD][gov-dod],
  [national security][gov-ns], [Azure OpenAI authorization][aoai-il6], [GPT-5.2][gpt52]
