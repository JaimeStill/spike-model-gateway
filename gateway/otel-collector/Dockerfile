# The gateway's OpenTelemetry Collector, contrib distribution, as go-web-service's observability
# profile builds it (~/architecture's go-web-service/compose/otel-collector/): it receives spans
# from agentgateway and the four vLLM rows and forwards them to Tempo. This FROM line is the
# Collector's one pin, which `mise run currency` reads.
FROM otel/opentelemetry-collector-contrib:0.165.0

COPY otel-collector.yaml /etc/otelcol-contrib/otel-collector.yaml

# No HEALTHCHECK: the contrib image ships no shell, so a probe against the Collector's own
# health_check extension has nothing to run it with. Its exporter retries with backoff, so a Tempo
# that is still starting costs nothing but delay.

CMD ["--config=/etc/otelcol-contrib/otel-collector.yaml"]
