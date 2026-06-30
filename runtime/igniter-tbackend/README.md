# Igniter TBackend

TBackend is the Rust temporal ledger substrate used by Igniter Lab and Home Lab
for append-only fact storage, temporal lookups, audit/replay, and
Spark-shaped shadow systems.

Current status:

```text
implemented lab substrate
  -> shadow-ready candidate for Spark-shaped side-ledger work
  -> preview packaging in progress
  -> production authority only after convergence gates
```

It is **not** an Igniter Lang canonical runtime component, not Reference
Runtime support, and not a public/stable wire API promise. Those are governance
claims. It is legitimate infrastructure for bounded shadow/admission
experiments where the existing application database remains source of truth.

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
| team intro | `docs/tbackend-team-quickstart.md` |
| worked domain example | `docs/example-usecase.md` + `examples/availability_ledger.py` |

## Layout

```text
src/                  Rust daemon, command server, packs, WAL/core logic
docs/                 Operator, architecture, Docker, and team-facing docs
examples/             Small runnable examples
packaging/            Debian/systemd configs and macOS bundle payload files
scripts/build-*.sh    Build/package helpers
scripts/verify/       Focused lab proof harnesses
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

Focused proof scripts:

```bash
ruby scripts/verify/verify_auth.rb
python3 scripts/verify/verify_seqid.py
python3 scripts/verify/verify_idempotent_write.py
python3 scripts/verify/verify_durable_ack.py
python3 scripts/verify/verify_compaction_loss.py
ruby scripts/verify/verify_mcp.rb
```

Most proof scripts start temporary loopback daemons, write ignored `*_data` and
`*_daemon.log` paths, and clean up after themselves. They are lab proofs, not
stable product commands.

## Boundary

Allowed today:

- local lab daemons;
- Home Lab services;
- synthetic Rails mirrors;
- Spark-shaped side ledgers;
- shadow parity checks;
- audit/explainability packets;
- non-authoritative replay evidence.

Not implied:

- public database/service support;
- production source-of-truth authority;
- canonical Igniter Lang runtime authority;
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
