# TBackend — Docker image (devops / AWS evaluation)

A container image for ECS / EC2 / Kubernetes-style environments. Build it with **Docker only** (no Rust on
the host) — the `Dockerfile` is a multi-stage build (Rust builder → slim Debian runtime).

This is a **lab** artifact. Loopback/private by default, auth off, no TLS — not a production surface.

## Build + run (quickstart)

```bash
# build (linux of the build host's arch; use buildx for amd64 — see below)
docker build -t tbackend:0.1.0-lab.1-local .

# run, loopback-only on the host, durable volume
docker run --rm -d --name tbackend-smoke \
  -p 127.0.0.1:7401:7401 \
  -v tbackend-data:/var/lib/tbackend \
  tbackend:0.1.0-lab.1-local

# smoke (framed CRC32 ping from the host)
python3 - <<'PY'
import socket,struct,zlib,json
b=json.dumps({"op":"ping"}).encode()
f=struct.pack(">I",len(b))+b+struct.pack(">I",zlib.crc32(b)&0xffffffff)
s=socket.create_connection(("127.0.0.1",7401),3);s.sendall(f)
n=struct.unpack(">I",s.recv(4))[0];print(s.recv(n).decode())   # -> {"ok":true,"pong":true}
PY

docker logs tbackend-smoke
docker stop tbackend-smoke
docker volume rm tbackend-data
```

Or with compose: `docker compose -f docker-compose.quickstart.yml up --build -d` … `… down -v`.

## The binding nuance (read this)

The image config binds **`0.0.0.0:7401` inside the container** — required so a Docker port-mapping can reach
it. **Loopback-only exposure is enforced by the host mapping** `-p 127.0.0.1:7401:7401` (compose does the
same). **Never** publish a bare `-p 7401:7401` / `"7401:7401"` — that exposes the daemon on all host
interfaces. The in-container bind lives in `/etc/tbackend/tbackend.config.json`
(from `packaging/tbackend.docker.json`); override it by mounting your own config or templating it at deploy
time.

## Image contents

- `/usr/bin/tbackend` — the pure-Rust daemon (no FFI/Ruby).
- `/etc/tbackend/tbackend.config.json` — default config (host `0.0.0.0`, port `7401`, `data_dir=/var/lib/tbackend`, auth off, durability `accepted`).
- `VOLUME /var/lib/tbackend` — the ledger; back it with a named volume / EBS / EFS.
- Runs as non-root user `tbackend`. Logs to stdout/stderr (container logs).
- `ENTRYPOINT ["/usr/bin/tbackend"]`, `CMD ["--config","/etc/tbackend/tbackend.config.json"]`.

## Multi-arch (amd64 for AWS)

The plain `docker build` produces an image for the **build host's arch** (arm64 on Apple silicon). For an
x86 AWS host, cross-build with buildx:

```bash
docker buildx build --platform linux/amd64 -t tbackend:0.1.0-lab.1-amd64 --load .
```

(Multi-arch manifest + registry push are out of scope for this card.)

## Healthcheck

No in-image `HEALTHCHECK` yet — the slim runtime has no Python/nc and the wire is a CRC32-framed binary, so
a real client is needed. **Follow-up:** ship a tiny static `tbackend-ping` (or a `--healthcheck` daemon
flag). For now, health-probe externally with the framed ping above, or an ECS/K8s TCP-connect probe to 7401
(connect-only, not protocol-aware).

## AWS / devops notes

- **Where:** an ECS task or an EC2 Docker host on a **private** subnet — not the public internet. No public
  bind by default.
- **Storage:** mount a persistent **EBS/EFS** volume at `/var/lib/tbackend` (the ledger must survive task
  restarts).
- **Logs:** stdout/stderr → CloudWatch Logs (the daemon already logs there).
- **Config/secrets:** supply config via a mounted file or a template rendered from **SSM Parameter Store /
  Secrets Manager** — **never bake secrets into the image**. (Auth is off by default; when enabled, the
  bootstrap token + token store are runtime state under the volume, not image content.)
- **Tags:** use **immutable** version tags (`tbackend:0.1.0-lab.1`, aligned with the release manifest
  convention) — **never `latest`** in task definitions or runbooks.
- **Network:** keep it loopback / private-subnet; TLS/mTLS and auth hardening are separate follow-ups.

## Tag convention (aligned with the release manifest)

```text
tbackend:0.1.0-lab.1            tbackend:0.1.0-preview.1            tbackend:0.1.0
tbackend:0.1.0-lab.1-g<sha>     (immutable, sha-pinned)
```

See `igniter-home-lab/artifacts/tbackend/releases/README.md` for the channel/version rules.
