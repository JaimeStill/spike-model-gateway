# The gateway's OpenTelemetry Collector, contrib distribution.
# See docs/stack.md#the-collector
FROM otel/opentelemetry-collector-contrib:0.165.0

COPY otel-collector.yaml /etc/otelcol-contrib/otel-collector.yaml

CMD ["--config=/etc/otelcol-contrib/otel-collector.yaml"]
