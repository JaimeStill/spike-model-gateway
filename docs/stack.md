# The gateway's stack

The reasoning behind the gateway's compose project, [`gateway/`](../gateway/), and the mise tasks
that operate it, one section per service; each compose file, Dockerfile, and service configuration
points at its section with a `See` line. agentgateway's own configuration is in
[`agentgateway-config.md`](agentgateway-config.md).

## The compose project

The gateway's stack on gb10-2: agentgateway in front of the four rows, the Postgres it keeps its
state in, and its traces: the OpenTelemetry Collector that agentgateway and the rows send spans to,
Tempo, which stores them, and Grafana, which searches them. It follows go-web-service's compose
convention
([go-web-service's `compose/README.md`](https://github.com/standards-lab/go-web-service/blob/main/compose/README.md)):
[`gateway/compose.yml`](../gateway/compose.yml) names the project and includes one file per
service group, and each service but agentgateway builds from its own Dockerfile, whose FROM line is
its one pin, which `mise run currency` reads; the three trace services are go-web-service's
observability profile's, at its pins, though here they always run.

It runs from ~/gateway on gb10-2, where
[`scripts/agentgateway-deploy.sh`](../scripts/agentgateway-deploy.sh) copies the gateway
directory's compose files and build contexts, [`gateway/compose.sh`](../gateway/compose.sh),
deploy.env as the project's .env, the rendered config, and Postgres's env file, then runs
`gateway/compose.sh up --detach --wait --build`. compose.sh sets the values read at run time on
gb10-2 (the tailnet addresses, the user, the config section's hash), so none is written down. Every
service restarts with the host unless it was stopped (`restart: unless-stopped`).

## deploy.env

[`gateway/agentgateway/deploy.env`](../gateway/agentgateway/deploy.env) holds the gateway's image
and the stack's ports. scripts/agentgateway-deploy.sh sources it and copies it to gb10-2 as the
compose project's .env, which the compose files read; scripts/currency.sh and the step helpers
([`scripts/clients-lib.sh`](../scripts/clients-lib.sh),
[`scripts/measure-lib.sh`](../scripts/measure-lib.sh)) source it too. So it holds plain assignments
only. The image is pinned here once; `mise run currency` compares its tag with agentgateway's
latest GitHub release.

- `AGW_PORT` and `AGW_UI_PORT`: the ports of config.yaml's gateways: the consumer port, published
  on gb10-2's tailnet address, where each alias's base URL is http://gb10-2:3000/<alias>/v1; and
  the UI's, published on its loopback.
- `OTEL_GRPC_PORT`: the Collector's OTLP gRPC port, published on gb10-2's tailnet address, where
  agentgateway and the rows send their spans ([The Collector](#the-collector); spike-model-engines'
  host/vllm.env, `VLLM_TRACE_COLLECTOR`).
- `GRAFANA_PORT`: Grafana's, published on its loopback.

## agentgateway

[`gateway/agentgateway.yml`](../gateway/agentgateway.yml) runs agentgateway from the image
deploy.env pins (`AGW_IMAGE`, read from the project's .env, which the deploy copies from
deploy.env), as the deploy ran it before the compose project. Two exceptions to the compose
convention, both recorded in [`findings/priority.md`](findings/priority.md):

- The image is pulled, not built: agentgateway's image pin stays in deploy.env, where the deploy
  validates a config copy with it and `mise run currency` compares it with agentgateway's latest
  release.
- The config is bind-mounted, read-only, not baked into an image. The deploy renders it on the
  laptop with each key's hash and each secret substituted, so it can't be committed into a build
  context, and agentgateway reloads it in place when a new copy is moved in, so a config-only deploy
  needs no restart. The directory is mounted, not the file, so the rename that moves a copy into
  place reaches the container.

Fields under the config's top-level `config` are read once, at start, so a change there needs a
restart: compose.sh hashes that section into the `spike.config-section` label, and a changed label
makes `up` create the container again.

The service's settings:

- **A fixed container name**, as the deploy gave it before: the step helpers read
  `docker stats agentgateway` and `docker logs agentgateway` on gb10-2.
- **The deploying user**, so the container reads the config it owns and writes nothing as root.
- **Ports.** The consumer port on gb10-2's tailnet address, and the UI's on its loopback, reached
  through an SSH tunnel. The stats port, 15020, agentgateway's Prometheus metrics, on the loopback
  too, read over SSH: `requests_shed` counts the in-flight limit's refusals, which leave no access
  log line ([`scripts/clients-lib.sh`](../scripts/clients-lib.sh), `requests_shed`).
- **Extra hosts.** gb10-2 resolves names through systemd-resolved's stub (127.0.0.53), which a
  container can't reach, so docker gives it an outside resolver that doesn't know the tailnet's
  short names. Each row's host is added by its tailnet address, looked up on gb10-2 by compose.sh.
- **Start order.** It starts once Postgres is healthy. The Collector it exports its spans to
  (`config.tracing`) has no health check ([The Collector](#the-collector)), so agentgateway waits
  on its start only.

## Unattested builds

Each built service sets `provenance: false` and `sbom: false`, so an unchanged Dockerfile keeps its
image id and `up` leaves the container alone. The deploy runs `up --build`, and compose creates the
container again whenever the built image's id changes. BuildKit attaches a provenance attestation by
default, which records the build's own times, and with gb10-2's containerd image store the image id
is the digest of the index that lists the attestation, so every build made a new id from an
unchanged Dockerfile, and every deploy recreated Postgres. Compose v5.2.0 drops `provenance: false`
and `sbom: false` from the bake definition it writes (`compose.sh build --print postgres` shows no
`attest`), so compose.sh also sets `BUILDX_NO_DEFAULT_ATTESTATIONS`; a later Compose honours the
two settings. With no attestation, a cached build of an unchanged Dockerfile is the same image, and
`up` leaves the container alone; a changed Dockerfile still rebuilds it.

## Postgres

Postgres, agentgateway's database (`config.database`,
[`agentgateway-config.md`](agentgateway-config.md#database)): its request log and token budgets
live here. [`gateway/postgres.yml`](../gateway/postgres.yml) publishes no port: only agentgateway
reaches it, as `postgres` on the project's network. Its password is generated by the deploy on the
laptop, kept untracked under .state/agentgateway/, and reaches gb10-2 only in postgres.env, beside
the deployed compose files, 0600; the image reads it on the first start, when it initializes the
volume.

[`gateway/postgres/Dockerfile`](../gateway/postgres/Dockerfile) sets the user and database
agentgateway's `config.database` URL names. The password isn't there: it is a secret, so it comes
from postgres.env at run time. The image is healthy once the server accepts TCP connections to the
agentgateway database; agentgateway starts only then, since it connects to its database once, at
start. The probe goes over TCP, not the socket, because the first start's initialization runs a
temporary server on the socket alone, which would report ready before the real server starts.

## The Collector

The OpenTelemetry Collector, contrib distribution, as go-web-service's observability profile builds
it, is the stack's one OTLP ingress ([`gateway/otel-collector.yml`](../gateway/otel-collector.yml)):
agentgateway sends it spans over the project's network, as `otel-collector`, and the four vLLM rows,
three of them on other hosts, through its OTLP gRPC port, published on gb10-2's tailnet address as
agentgateway's consumer port is (`AGW_ADDR`, which compose.sh looks up there). It forwards every
span to Tempo, and starts once Tempo has started, since Tempo has no health check.

The port takes spans from any tailnet peer, unauthenticated: the spike's trust is the tailnet's, and
authenticated OTLP ingress is a requirement for production, not built here.

Its Dockerfile, [`gateway/otel-collector/Dockerfile`](../gateway/otel-collector/Dockerfile), has no
HEALTHCHECK: the contrib image ships no shell, so a probe against the Collector's own
`health_check` extension has nothing to run it with. Its exporter retries with backoff, so a Tempo
that is still starting costs nothing but delay.

Its configuration,
[`gateway/otel-collector/otel-collector.yaml`](../gateway/otel-collector/otel-collector.yaml), has
one pipeline, traces: it receives OTLP over gRPC, batches the spans, and exports them to Tempo by
its service name. No metrics or logs pipeline: the answer task traces only.

- **Liveness** on 13133, published nowhere; a request from another container on the compose network
  reads it when needed.
- **The receiver**, OTLP over gRPC only, which agentgateway's `config.tracing` and vLLM's
  `--otlp-traces-endpoint` both send. It binds every interface, since the default, localhost, is
  unreachable through the published port and from the compose network.
- **The exporter**, Tempo's OTLP gRPC receiver, plaintext inside the compose network.

## Tempo

Tempo, the trace store, a single binary on local storage, as go-web-service's observability profile
builds it, is fed by the Collector and read by Grafana, both as `tempo` on the project's network
([`gateway/tempo.yml`](../gateway/tempo.yml)). It publishes no port. Its traces live in a named
volume, mounted at /var/tempo, and its blocks are kept 24 h.

Its Dockerfile, [`gateway/tempo/Dockerfile`](../gateway/tempo/Dockerfile), has no HEALTHCHECK:
since 2.10 the image is only /tempo, with no shell or wget to probe /ready with.

Its configuration, [`gateway/tempo/tempo.yaml`](../gateway/tempo/tempo.yaml), is go-web-service's
with only the receiver the Collector sends to. Its HTTP API, on 3200, serves Grafana and the
session's trace reads ([`scripts/clients-lib.sh`](../scripts/clients-lib.sh), `traces`), both from
inside the compose network.

- **The receiver.** Tempo 3 binds receivers to localhost by default; the Collector reaches this one
  over the compose network, so it binds every interface.
- **The live-store.** Tempo 3 replaced the ingester with the live-store, which the single-binary
  target feeds directly (no Kafka). Its defaults cut blocks every 30s and hold them for 20m, so
  nothing in the configuration overrides them.
- **Retention.** Block retention is a compaction setting; the single-binary target runs both the
  scheduler that plans compaction jobs and the worker that runs them, and each reads its own copy.

## Grafana

Grafana, with Tempo as its datasource, for searching the stack's traces
([`gateway/grafana.yml`](../gateway/grafana.yml)), reached as
[Operating the stack](#operating-the-stack) gives it. Anonymous access is its admin, as
go-web-service's observability profile gives it
([`gateway/grafana/Dockerfile`](../gateway/grafana/Dockerfile)), so it needs no login and holds no
secret. Its state, the SQLite database, lives in a named volume. It starts once Tempo has started,
since Tempo has no health check.

The image sets `GF_PATHS_PROVISIONING=/etc/grafana/provisioning`; Grafana reads datasources/ beneath
it at startup. It is healthy once Grafana's health endpoint answers, which it does only when its
database is reachable.

Its one datasource,
[`datasources.yaml`](../gateway/grafana/provisioning/datasources/datasources.yaml), is the
gateway's Tempo, reached by its compose service name. Its uid is explicit, as go-web-service's are,
so a link to it doesn't name a generated one.

## Operating the stack

The mise tasks act on the gateway's compose project on gb10-2 as the deploy left it in ~/gateway:
each `gateway:` task runs gateway/compose.sh there over Tailscale SSH. Postgres's data, Tempo's
traces, and Grafana's state live in named volumes, which `gateway:down` keeps and `gateway:reset`
drops. A config or project change goes out with `mise run agentgateway-deploy`, which brings the
stack up itself.

- **The UI**, published on gb10-2's loopback only, is reached from the laptop through an SSH tunnel,
  `mise run gateway:ui`: http://localhost:3001/ui while it runs, its Logs and Analytics pages
  reading the request log in Postgres. The tunnel holds the terminal until Ctrl-C.
- **Grafana**, published on gb10-2's loopback only, is reached the same way, `mise run
  gateway:grafana`: http://localhost:3002 while it runs, its Explore page searching the stack's
  traces in Tempo. The tunnel holds the terminal until Ctrl-C.

## The tools

[`mise.toml`](../mise.toml) pins the tools the check, currency, and the deploy use. marathon's
release, `github:standards-lab/claude-plugins` at its `marathon/v` tag, provides lint-context and
lint-references, which `mise run check` runs. Tasks never
install a missing tool (`task.run_auto_install = false`); `mise install` is the one step that reads
the network. crane lists an image's tags for `mise run currency`, which compares each compose
Dockerfile's FROM pin; go builds the retry test's module ([`retry/`](../retry/)), which
`mise run check` vets and tests. `mise run currency` reports every pin behind its latest: the mise
tools of mise.toml and of the bench environment, agentgateway's image in deploy.env, and each
compose Dockerfile's FROM line, the client helpers' go-ai tag, and the retry test's go-ai
requirement. The engine pins stay with spike-model-engines, whose host/ this
spike changes only through pull requests.

[`mise.bench.toml`](../mise.bench.toml) holds the tool the spike measures with from the laptop,
GuideLLM, and the runtimes it needs. It lives in its own environment, not mise.toml, so `mise run
check` never installs it. Activate it with `MISE_ENV=bench`: `MISE_ENV=bench mise install`, then
`MISE_ENV=bench mise exec -- guidellm`. mise's pipx backend installs GuideLLM through uv, with its
vision and audio extras, which the vision and audio cells need.
