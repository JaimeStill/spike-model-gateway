# The gateway's Grafana, over Tempo, with anonymous admin access as go-web-service's observability
# profile gives it (~/architecture's go-web-service/compose/grafana/), so it needs no login and
# holds no secret: its port is published on gb10-2's loopback only (gateway/grafana.yml), reached
# from the laptop through an SSH tunnel, `mise run gateway:grafana`. This FROM line is Grafana's
# one pin, which `mise run currency` reads.
FROM grafana/grafana:13.3.1

ENV GF_AUTH_ANONYMOUS_ENABLED=true \
    GF_AUTH_ANONYMOUS_ORG_ROLE=Admin

# The image sets GF_PATHS_PROVISIONING=/etc/grafana/provisioning; Grafana reads datasources/
# beneath it at startup.
COPY provisioning /etc/grafana/provisioning

# Healthy once Grafana's health endpoint answers, which it does only when its database is
# reachable.
HEALTHCHECK --start-period=30s --start-interval=1s --interval=5s --timeout=3s --retries=5 \
    CMD ["wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
