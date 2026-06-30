# TBackend — team quickstart (no Rust needed)

**TBackend is a bitemporal, append-only ledger** — a small daemon where every change is an immutable
*fact*, so you can ask "what did we know at time T?" and "why?" and replay it. You talk to it over a
loopback TCP wire (framed JSON). It's pure Rust, loopback-only, no auth by default.

**Why it matters / how to think about it:** it is a **side-ledger / shadow** for audit, replay,
point-in-time, and explanation — **not** a source-of-truth switch. Your existing system (Postgres, etc.)
stays authoritative; TBackend records the lineage next to it. Don't swap a database for it.

## Pick your path

| You are… | Path | Rust? |
|----------|------|-------|
| **macOS dev** (want to try it) | prebuilt **bundle** tarball | no |
| **devops / AWS** | **Docker** image (build locally for now) | no (Rust runs inside the container) |
| **Linux host ops** | **`.deb`** package (arm64 today; amd64 soon) | no |
| **contributor** | source build (`cargo build --release --bin tbackend`) | yes |

Artifacts live in `igniter-home-lab/artifacts/tbackend/releases/<version>/` (current: `v0.1.0-lab.1`).

## 10-minute demo

### macOS (prebuilt bundle — no build)

```bash
tar -xzf tbackend-0.1.0-lab.1-darwin-arm64.tar.gz
cd tbackend-0.1.0-lab.1-darwin-arm64
./scripts/tbackend-dev start          # loopback 127.0.0.1:7401, data -> ./var/data
./scripts/tbackend-dev ping           # -> {"ok":true,"pong":true}
python3 examples/availability_ledger.py
./scripts/tbackend-dev stop           # nothing keeps running
```

### Docker (host needs only Docker)

```bash
# from the source repo — Rust compiles INSIDE the container, not on your host
docker compose -f docker-compose.quickstart.yml up --build -d   # 127.0.0.1:7401 only
# ping + run the example: see docs/docker.md
docker compose -f docker-compose.quickstart.yml down -v
```

(amd64 via `docker buildx --platform linux/amd64`; no registry image is published yet.)

## What the demo proves

The example (`examples/availability_ledger.py`) walks an availability ledger and shows the four things a
plain UPDATE-in-place table can't give you cheaply:

- **idempotent durable write** — a retry of the same logical write replays, never duplicates;
- **point-in-time** — `as_of` returns *different* state at two coordinates ("what did we know then?");
- **seq-ordered audit** — replay order is a server `seq_id`, immune to clock skew;
- **lineage / why** — every fact carries who/when/why, so a decision is explainable a month later.

## What it is NOT ready for (yet)

- **Public internet** — loopback / private only; no TLS/mTLS, auth off by default.
- **Production source-of-truth** — it's a shadow side-ledger; promotion needs explicit gates.
- **Multi-node mesh under clock skew** — gossip replication is readiness-stage; can drop writes under
  skew. Single-node only for now.
- **Live auth-storage upgrade** of a running service — documented but gated (operator approval).
- **Cross-arch coverage** — `v0.1.0-lab.1` ships arm64 (deb + macOS bundle + docker) and arm64-local
  docker; amd64 / Intel-mac / a pushed registry image are pending.

## Artifacts & versioning

- **Immutable version tags**, never `latest`. Channels: `lab` (proof) → `preview` (team eval) → `stable`.
- Every release has a `manifest.json` (provenance + per-artifact `sha256`) and `SHA256SUMS`. **Verify before
  you run:** `sha256sum -c SHA256SUMS` (or `shasum -a 256 -c`).
- Rules: `igniter-home-lab/artifacts/tbackend/releases/README.md`.

## Go deeper

- `example-usecase.md` — the worked example, explained.
- `deployment.md` — the two install tracks (local-dev / devops) + full recipes.
- `docker.md` — container image + AWS/ECS notes.
- `technical_architecture.md` · `user_guide.md` — the engine and the wire API.
