# syntax=docker/dockerfile:1
# Multi-stage: build the pure-Rust daemon, ship it on a slim Debian runtime.
# No Rust on the operator host — only Docker. The daemon is FFI/Ruby-free by default.

FROM rust:1-bookworm AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
# pure-Rust daemon — no --features ffi (that would pull in magnus/Ruby + a cdylib)
RUN cargo build --release --bin tbackend

FROM debian:bookworm-slim AS runtime
RUN groupadd --system tbackend \
 && useradd --system --no-create-home --gid tbackend tbackend \
 && mkdir -p /var/lib/tbackend \
 && chown -R tbackend:tbackend /var/lib/tbackend
COPY --from=build /src/target/release/tbackend /usr/bin/tbackend
COPY packaging/tbackend.docker.json /etc/tbackend/tbackend.config.json
USER tbackend
# The container binds 0.0.0.0:7401 INTERNALLY (so a host port-mapping can reach it).
# Keep it loopback-only on the HOST via the mapping, e.g. -p 127.0.0.1:7401:7401.
# See docs/docker.md — never publish a bare "7401:7401".
EXPOSE 7401
VOLUME ["/var/lib/tbackend"]
ENTRYPOINT ["/usr/bin/tbackend"]
CMD ["--config", "/etc/tbackend/tbackend.config.json"]
