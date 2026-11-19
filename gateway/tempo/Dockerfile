# The gateway's Tempo, the trace store, a single binary on local storage, as go-web-service's
# observability profile builds it (~/architecture's go-web-service/compose/tempo/). This FROM line
# is Tempo's one pin, which `mise run currency` reads.
FROM grafana/tempo:3.1.1

COPY tempo.yaml /etc/tempo/tempo.yaml

# No HEALTHCHECK: since 2.10 the image is only /tempo, with no shell or wget to probe /ready with.

CMD ["-config.file=/etc/tempo/tempo.yaml"]
