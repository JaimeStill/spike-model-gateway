# The gateway's Tempo, a single binary on local storage.
# See docs/stack.md#tempo
FROM grafana/tempo:3.1.1

COPY tempo.yaml /etc/tempo/tempo.yaml

CMD ["-config.file=/etc/tempo/tempo.yaml"]
