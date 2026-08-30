ARG PARADEDB_VERSION=v0.25.6
ARG PG_VERSION=18
FROM paradedb/paradedb:${PARADEDB_VERSION}-pg${PG_VERSION}

ARG PG_VERSION
ARG VCHORD_VERSION=1.1.1
ARG TARGETARCH

RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL -o /tmp/vchord.deb \
      "https://github.com/supervc-stack/VectorChord/releases/download/${VCHORD_VERSION}/postgresql-${PG_VERSION}-vchord_${VCHORD_VERSION}-1_${arch}.deb"; \
    apt-get install -y --no-install-recommends /tmp/vchord.deb; \
    apt-get purge -y --auto-remove curl; \
    rm -rf /var/lib/apt/lists/* /tmp/vchord.deb

RUN set -eux; \
    CONF="/usr/share/postgresql/${PG_VERSION}/postgresql.conf.sample"; \
    if grep -q "^shared_preload_libraries" "$CONF"; then \
      sed -i "s/^shared_preload_libraries = '\(.*\)'/shared_preload_libraries = '\1,vchord'/" "$CONF"; \
    else \
      echo "shared_preload_libraries = 'vchord'" >> "$CONF"; \
    fi; \
    grep shared_preload_libraries "$CONF"
