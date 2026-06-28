# LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / machine / durability
Implements: audit-control-board row A21 — first machine slice (multi-process exactly-once)
Depends-On: `LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-OWNER-SPLIT-P1`,
`LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8`

Lab evidence only. Machine-crate scope. No TBackend / home-lab / SparkCRM edits, no schema
migration runner, no server/web changes, no live DB mutation outside the dedicated
`igniter_pg_test` database. No filesystem WAL fsync claim (that is the parallel P2-WAL card).

## Headline (verify-first)

The card was framed as "close the multi-process exactly-once gap using DB-native durable
CAS". Verify-first showed the **mechanism already existed**: `TokioPostgresWriteAdapter::transact`
(P8) is already a single atomic writable-CTE statement —

```sql
WITH ins AS (
  INSERT INTO effect_receipts (idempotency_key, correlation_id, target, business_key)
  VALUES ($1,$2,$3,$4) ON CONFLICT (idempotency_key) DO NOTHING RETURNING 1
), biz AS (
  INSERT INTO <target> (...) SELECT ... WHERE EXISTS (SELECT 1 FROM ins)
  ON CONFLICT (<key>) DO UPDATE ... RETURNING 1
) SELECT count(*)::int AS fresh FROM ins
```

`fresh == 1` → `Committed`; `fresh == 0` → `DuplicateKey` (no second business mutation).

What was **missing** was not the CAS but its *proof and hardening*:

1. **No concurrency proof.** Every P8 test was sequential (write A completes, then write B).
   The multi-process race — two writers committing the same idempotency key *at the same
   time* — was never exercised. The P1 packet explicitly listed this: "Concurrent duplicate
   (multi-process) — **GAP — double effect possible**".
2. **DDL not code-anchored.** The load-bearing `effect_receipts(idempotency_key)`
   UNIQUE/PK lived only as a string literal inside the test file. Nothing in `src/` stated
   that the unique key is what makes the CAS work.
3. **DDL/config drift was mislabeled.** A missing unique key (`ON CONFLICT` → SQLSTATE
   42P10), an undefined table (42P01) or column (42703) all fell through to
   `ConstraintViolation` → "constraint violation: …" — telling an operator their *data*
   conflicted when their *schema* is wrong.

This card closes (1)–(3). The in-process `single_flight` lock (P18) is preserved as a fast
path but is explicitly **not** relied on for the cross-process guarantee.

## Before-state and exact live weakness

| Concern | Before P2 | File |
| --- | --- | --- |
| Cross-process exactly-once | Mechanism present, **unproven under real concurrency** | `postgres_real.rs::transact` |
| Canonical receipt DDL | test-only string literal | `tests/postgres_real_write_tests.rs` |
| Missing UNIQUE key (42P10) | mislabeled `ConstraintViolation` | `postgres_real.rs::classify_write_error` |
| Undefined table/column (42P01/42703) | mislabeled `ConstraintViolation` | same |
| In-process lock | only multi-process defence named, but `single_flight` is in-process | `single_flight.rs:11-15` |

## Uniqueness key (Q1)

A machine write effect is uniquely identified by its **`idempotency_key`** — the same key
the machine receipt is keyed by (`run_write_effect` sets it; the executor forwards
`req.idempotency_key` to `transact`). The PG-side durable CAS is therefore
`effect_receipts(idempotency_key)` with a UNIQUE/PRIMARY KEY. This is a deliberate single
axis, not a tuple: target+key would dedup *business identity* (wrong — two legitimately
distinct effects can target the same row), correlation id threads the reconcile trail but is
nullable. The idempotency key is the caller's "exactly this attempt" token, so it is the
correct CAS axis and makes the P7 same-value false-positive impossible.

## DDL / unique-key policy (Q2, Q3)

Canonical DDL is now code-anchored as `postgres_real::EFFECT_RECEIPTS_DDL`:

```sql
CREATE TABLE IF NOT EXISTS effect_receipts (
  idempotency_key TEXT PRIMARY KEY,
  correlation_id  TEXT,
  target          TEXT NOT NULL,
  business_key    TEXT NOT NULL,
  committed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

The `PRIMARY KEY` on `idempotency_key` is the load-bearing exactly-once anchor — `ON
CONFLICT (idempotency_key)` requires it. The machine **never** creates or migrates this
table (operator-owned, no migration runner); the constant exists so tests and operator
runbooks share one source of truth.

**Q2 — is the writable CTE sufficient under concurrent clients?** Yes, proven. Two
concurrent `INSERT … ON CONFLICT DO NOTHING` on the same key: the loser blocks on the
winner's uncommitted row, then sees the conflict and inserts nothing; its `biz` CTE's `WHERE
EXISTS (SELECT 1 FROM ins)` is empty, so the business mutation is skipped. Exactly one
business mutation, deterministically, with no application lock. `single_flight` cannot help
here (separate processes share no lock map) — the **database** is the arbiter.

**Q3 — DDL drift that must fail loud as a permanent config error.** `classify_write_error`
now maps the schema/config SQLSTATEs to a new `PostgresWriteResult::PermanentConfig`
(→ `EffectOutcome::permanent("permanent config/DDL error: …")`):

| SQLSTATE | Meaning |
| --- | --- |
| `42P10` | no unique/exclusion constraint matching `ON CONFLICT` (the durable-CAS key is missing) |
| `42P01` | undefined table (e.g. `effect_receipts` or the target absent) |
| `42703` | undefined column |
| `42704` | undefined object |
| `42P07` | duplicate table |
| `42601` | syntax error |

All remain **permanent** (no blind retry), but the message points at the schema. `40001`/
`40P01`→retryable, `42501`→denied, `23xxx`→constraint violation, other DB errors→permanent
fallback are unchanged.

## Replay without re-execution (Q4)

Two layers, unchanged by this card:

1. **Machine receipt** (`run_write_effect`): a prior terminal receipt for `capability:key`
   short-circuits — the executor (and the DB) is never reached. Proven by
   `real_replay_bypasses_adapter` (adapter `attempts() == 1` across two identical calls).
2. **PG-side `effect_receipts`**: if the machine receipt is lost (e.g. a different process),
   the DB CAS returns `DuplicateKey` → `duplicate: true`, still `Committed`, no second
   mutation. The original outcome is reconstructed from the stored receipt, not re-run.
   `unknown` receipts reconcile by a **read-only** `SELECT … WHERE idempotency_key=$1`
   (`reconcile_postgres_unknown_write`) — never `transact`.

## Concurrency evidence

`real_concurrent_same_key_writes_once_multi_process` (multi-thread runtime, real local
Postgres): two adapters on **separate connections** + **separate receipt stores** (= two
processes) fire `run_write_effect` on the same idempotency key via `tokio::join!`. Asserted:

- both outcomes `Committed`; the `duplicate` flags are exactly `{false, true}` (one fresh,
  one DB-deduped) — in either order;
- both adapters reached the DB (`attempts() == 1` each) — `single_flight` did not and could
  not dedup across processes;
- exactly **one** durable business row survives (`name == "Ada"`);
- exactly **one** `effect_receipts` row for the shared key (`count == 1`).

`real_ddl_drift_undefined_target_is_permanent_config`: an adapter bound to a non-existent
target table → the CTE references an undefined relation (42P01) → `PermanentFailure` with a
`config/DDL` detail, and (atomic plan-time failure) **zero** effect-receipt rows for the
key.

## Verification results

Real, against the dedicated local DB (`IGNITER_PG_WRITE_DSN="host=localhost user=alex
dbname=igniter_pg_test"`):

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml \
  --no-default-features --features postgres --test postgres_real_write_tests -- --test-threads=1
```
Result: PASS, 7 tests (incl. `real_concurrent_same_key_writes_once_multi_process`,
`real_ddl_drift_undefined_target_is_permanent_config`).

Fake / default (no `postgres` feature, no DSN):

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_write_tests
```
Result: PASS, 12 tests (incl. `permanent_config_ddl_drift_is_permanent_config_error`).

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_reconcile_tests
```
Result: PASS, 7 tests.

Skip-clean check (feature on, DSN unset): `postgres_real_write_tests` → all tests return
early (eprintln `SKIP`), 0 failures. `git diff --check`: PASS.

## What remains only in-process / out of scope (Q5)

- **Filesystem WAL fsync / power-loss durability** of the machine's own receipt/fact store
  (`wal.rs` `flush()`-only, `MpkFileBackend`): the parallel `LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2`
  card. This card's durability is Postgres-native only.
- **`single_flight`** stays an in-process optimization (collapses same-key storms within one
  process before they hit the DB); it is explicitly not the cross-process guarantee.
- **`seq_id` / clock-ordered receipts** in the machine remain absent (P1 owner matrix; the
  machine receipt store still orders by `transaction_time`).
- **Connection pool / TLS** for the real adapter (single NoTls connection today) — named P8
  follow-ons, unchanged.
- **TBackend daemon adoption** (whether machine eventually consumes `pure_core` seq/CAS
  instead of a parallel mechanism) — deferred cross-project
  `LAB-MACHINE-TBACKEND-RECEIPT-ADOPTION-READINESS-P2`.
