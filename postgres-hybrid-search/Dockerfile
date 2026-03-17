FROM pgvector/pgvector:pg17 AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        postgresql-server-dev-17 \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN cd /tmp && \
    git clone --branch v0.6.1 --depth 1 https://github.com/timescale/pg_textsearch.git && \
    cd pg_textsearch && \
    make && \
    make install

FROM pgvector/pgvector:pg17

COPY --from=builder /usr/lib/postgresql/17/lib/pg_textsearch.so /usr/lib/postgresql/17/lib/
COPY --from=builder /usr/share/postgresql/17/extension/pg_textsearch* /usr/share/postgresql/17/extension/

COPY init-extensions.sql /docker-entrypoint-initdb.d/
