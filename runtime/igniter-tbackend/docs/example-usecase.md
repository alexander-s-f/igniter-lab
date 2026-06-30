# Example usecase — a bitemporal availability audit ledger

A small, self-contained example that shows **what TBackend gives you that a
plain UPDATE-in-place table does not**. Runnable end to end against a local
daemon. Code: [`examples/availability_ledger.py`](../examples/availability_ledger.py).

This is lab/example material. The intended authority boundary is a **shadow
side-ledger**: an existing system (Rails/Postgres) stays the source of truth and
mirrors selected lifecycle facts here for audit, replay, and explainability (see
`technical_architecture.md` §2 Promotion Ladder).

## The domain

A contractor's technician (`tech-7`) has schedule slots. Slots get **blocked**
(scheduled / off-schedule) and later **corrected** (rescheduled). Instead of
overwriting a row, every change is an **append-only fact**. The ledger can then
replay the exact state visible at any past coordinate and explain each decision.

## What it demonstrates

| # | Capability | TBackend op | Why a table can't (cheaply) |
|---|------------|-------------|------------------------------|
| 1 | idempotent durable append | `write_fact_once` + `durability:"durable"` | acked write is on disk via group-commit `fdatasync` |
| 2 | retry-safe writes | same **domain-derived `id`** → `idempotent_replay` | a retry/redelivery never creates a duplicate |
| 3 | point-in-time / time-travel | `latest_for` with `as_of` | "what did we know at time T?" — overwrites destroy this |
| 4 | clock-free audit order | `facts_by_seq` | replay order is the server `seq_id`, immune to clock skew |
| 5 | lineage / explainability | the stored fact (`seq_id`, `tt`, `vt`, reason) | "why was this slot blocked, and when did we learn it?" |

## Run it

```bash
# 1. build + start a daemon (durable path)
cargo build --release --bin tbackend
./target/release/tbackend --host 127.0.0.1 --port 7401 --data-dir data

# 2. in another shell
python3 examples/availability_ledger.py
```

Expected shape of the output:

```text
== 1. idempotent durable append ==
  first write : {'ok': True, 'committed': True, 'durability': 'durable', 'idempotent_replay': False, 'seq_id': 1}
== 2. retry the SAME logical write ==
  retry       : {'ok': True, 'committed': True, 'durability': 'durable', 'idempotent_replay': True, 'seq_id': 1}
== 3. point-in-time (time-travel) ==
  as_of early : {'slot': 540, 'state': 'blocked', 'reason': 'scheduled'}
  as_of now   : {'slot': 540, 'state': 'available', 'reason': 'rescheduled'}
== 4. clock-free audit order (facts_by_seq) ==
  seq=1  vt=1782277200  blocked (scheduled)
  seq=2  vt=1782280800  available (rescheduled)
== 5. lineage — why was tech-7 unavailable at the early coordinate? ==
  blocked because fact seq=1 (id=availability_demo:tech-7:slot.blocked:1)
```

The retry returns the **same `seq_id`** and `idempotent_replay: True` — no
duplicate fact. The `as_of` reads return *different* values for the same key at
two coordinates: the heart of bitemporal time-travel.

## How it maps to the primitives

- **`id` is domain-deterministic** (`store:tech:kind:version`). A retry recomputes
  the same id, so `write_fact_once` collapses it to a replay. The `version` is a
  stable domain version (think `updated_at` / `lock_version`) — **never a
  wall-clock**, which would make every retry a new id and silently duplicate.
- **`seq_id` is the ordering authority** (server-assigned, monotonic).
  `transaction_time` is *evidence* and `valid_time` is *domain time*; neither is
  trusted for order. `facts_by_seq` reads in `seq_id` order, correct even when
  facts arrived out of wall-clock order (backfills, corrections, replays).
- **`durability:"durable"`** blocks until a group-commit `fdatasync` covers the
  write. The default `"accepted"` is page-cache (survives a process crash, not
  power loss) and is the right mode for a high-volume shadow path. On an
  ephemeral (no `--data-dir`) daemon, `durable` honestly downgrades to
  `in_memory` — it never claims a durability it didn't achieve.
- **The server stamps a canonical Blake3 `value_hash`** — the client's hash is
  not trusted, so content identity can't be poisoned.

## Anti-patterns the example deliberately avoids

- **Wall-clock in the `id`** → breaks idempotency (every retry is a new fact).
  Use a domain version.
- **Ordering reads by `transaction_time`** → wrong under skew/backfill. Use
  `facts_by_seq` for replay/audit.
- **Treating `accepted` as power-loss-durable** → it isn't. Ask for `durable`
  when you need on-device durability.
- **Multi-node mesh under clock skew** → the gossip replication is readiness-
  stage (still tt-keyed); don't rely on convergence yet (see
  `technical_architecture.md` §D4).

## Where this goes next

This mirrors the real Spark-shaped usecase proven in the home lab
(`igniter-home-lab/apps/spark-availability-ledger-lab`): ActiveRecord/Postgres
stays authoritative; TBackend is the side-ledger that answers point-in-time and
"why" questions. The same shape is the on-ramp for the Hub's audit ledger
(events → decisions → commands → receipts), which is designed to minimize delta
against this backend so it can be swapped in behind a shadow once convergence is
proven.
