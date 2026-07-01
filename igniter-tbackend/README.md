# Igniter TBackend

TBackend is a small Rust temporal-ledger daemon for append-only fact storage,
point-in-time lookups, audit/replay, and Spark-shaped shadow systems.

Current status:

```text
implemented core
  -> ready for local/team preview
  -> intended first use: Spark-shaped shadow side ledger
  -> source-of-truth promotion only after convergence evidence
```

In plain terms: it is ready to try as a bounded side ledger next to an existing
application database. It is not asking to replace that database on day one. For
now the existing app stays authoritative; TBackend records history, lineage, and
point-in-time evidence beside it.

> **On the team? Start with [`docs/tbackend-onboarding.md`](docs/tbackend-onboarding.md)** — how to read
> TBackend as a *reference fact-contract* and design our ledgers toward it (minimize the delta), not just
> how to run it.

## Start Here

```bash
make build          # build ./target/release/tbackend
make test           # Rust unit tests
make verify-auth    # auth/storage/bootstrap proof
make docker-up      # local Docker quickstart on 127.0.0.1:7401
make docker-down    # stop and remove quickstart volume
```

Manual run:

```bash
cargo build --release --bin tbackend
./target/release/tbackend --config tbackend.config.json
```

Framed ping:

```bash
python3 - <<'PY'
import json, socket, struct, zlib
b = json.dumps({"op": "ping"}).encode()
s = socket.create_connection(("127.0.0.1", 7401), 3)
s.sendall(struct.pack(">I", len(b)) + b + struct.pack(">I", zlib.crc32(b) & 0xffffffff))
n = struct.unpack(">I", s.recv(4))[0]
print(s.recv(n).decode())
PY
```

## Preview Paths

| Audience | Entry point |
| --- | --- |
| macOS developer | `packaging/README-quickstart.md` |
| devops / AWS evaluation | `docs/docker.md` |
| Linux host ops | `docs/deployment.md` |
| team — start here | `docs/tbackend-onboarding.md` (reference framing + reading path) |
| team — 10-min hands-on | `docs/tbackend-team-quickstart.md` |
| worked domain example | `docs/example-usecase.md` + `examples/availability_ledger.py` |

## Layout

```text
src/                  Rust daemon, command server, packs, WAL/core logic
docs/                 Operator, architecture, Docker, and team-facing docs
examples/             Small runnable examples
packaging/            Debian/systemd configs and macOS bundle payload files
scripts/build-*.sh    Build/package helpers
scripts/verify/       Focused verification scripts
scripts/dev/          Legacy/local Ruby dev utilities
docs/assets/          Images and diagrams
```

The package root intentionally keeps only the preview-facing entrypoints:
`Cargo.toml`, `Dockerfile`, `docker-compose.quickstart.yml`, `Makefile`,
`README.md`, and local sample config.

Ignored runtime/build output includes `target/`, `data/`, `out/`, `*.log`, and
`*.wal`.

## Verification

Fast path:

```bash
make test
make verify-auth
```

Focused verification scripts:

```bash
ruby scripts/verify/verify_auth.rb
python3 scripts/verify/verify_seqid.py
python3 scripts/verify/verify_idempotent_write.py
python3 scripts/verify/verify_durable_ack.py
python3 scripts/verify/verify_compaction_loss.py
ruby scripts/verify/verify_mcp.rb
```

Most verification scripts start temporary loopback daemons, write ignored
`*_data` and `*_daemon.log` paths, and clean up after themselves. They are for
maintainers and CI-style checks; the human quickstart paths are listed above.

## Current fit

Good fits today:

- local development daemons;
- Home Lab services;
- synthetic Rails mirrors;
- Spark-shaped side ledgers;
- shadow parity checks;
- audit/explainability packets;
- non-authoritative replay evidence.

Not the right first use:

- public database/service support;
- immediate production source-of-truth role;
- stable wire/API/layout guarantees;
- public MCP/auth/mesh/pipeline service guarantees.

Promotion path:

```text
shadow mirror -> parity evidence -> failure-mode evidence -> restore/reconcile runbook
  -> explicit operator gate -> preview/stable promotion
```

For SparkCRM-style usage, the intended first role is a **side ledger**:

```text
Rails/Postgres write succeeds
  -> TBackend mirror/write is best-effort or queued
  -> shadow projection/audit compares against ActiveRecord truth
  -> convergence evidence decides promotion
```
