# The gateway's Postgres: agentgateway's database. This FROM line is Postgres's one pin, which
# `mise run currency` reads.
FROM postgres:19.0-alpine

# The user and database agentgateway's config.database URL names. The password isn't here: it is
# a secret, so it comes from postgres.env at run time (postgres.yml).
ENV POSTGRES_USER=agentgateway \
    POSTGRES_DB=agentgateway

# Healthy once the server accepts TCP connections to the agentgateway database; agentgateway
# starts only then (agentgateway.yml), since it connects to its database once, at start. The probe
# goes over TCP, not the socket, because the first start's initialization runs a temporary server
# on the socket alone, which would report ready before the real server starts.
HEALTHCHECK --start-period=30s --start-interval=1s --interval=5s --timeout=3s --retries=5 \
    CMD ["pg_isready", "-h", "127.0.0.1", "-U", "agentgateway", "-d", "agentgateway"]
