# The gateway's Postgres: agentgateway's database.
# See docs/stack.md#postgres
FROM postgres:19.0-alpine

ENV POSTGRES_USER=agentgateway \
    POSTGRES_DB=agentgateway

HEALTHCHECK --start-period=30s --start-interval=1s --interval=5s --timeout=3s --retries=5 \
    CMD ["pg_isready", "-h", "127.0.0.1", "-U", "agentgateway", "-d", "agentgateway"]
