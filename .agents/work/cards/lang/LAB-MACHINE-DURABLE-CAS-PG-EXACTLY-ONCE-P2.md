# LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2

Status: CLOSED (2026-06-28)
Route: standard / main-audit / machine / durability
Skill: idd-agent-protocol
Depends-On: `LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-OWNER-SPLIT-P1`

## Goal

Close the machine-owned multi-process exactly-once gap for Postgres write
effects using database-native durable CAS: `effect_receipts(idempotency_key)`
with a UNIQUE constraint and atomic `INSERT ... ON CONFLICT` / writable CTE
semantics.

This is audit-control-board row A21 first recommended machine slice. TBackend
already owns its daemon fact-log seq/CAS/group-commit story; this card is
machine-only and must not fork TBackend.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-machine-durable-cas-seqid-fsync-owner-split-p1-v0.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/src/write.rs`
- `runtime/igniter-machine/src/single_flight.rs`
- `runtime/igniter-machine/tests/postgres_write_tests.rs`
- `runtime/igniter-machine/tests/postgres_real_write_tests.rs` if present

Known facts to re-verify:

- in-process `single_flight` is a fast path, not a multi-process guarantee;
- existing fake and real write tests already cover receipts/reconcile at some
  level;
- real Postgres tests must remain feature/env gated and must never require a
  live DB by default.

## Scope

Allowed:

- Strengthen real Postgres write executor receipt/CAS logic.
- Add or document required receipt table unique constraint / canonical DDL.
- Preserve `single_flight` as an in-process optimization if still useful.
- Add fake tests only for shape if needed, plus real local Postgres tests gated
  by feature/env.
- Prove concurrent same-idempotency write executes once or returns the stored
  receipt deterministically.

Closed:

- No TBackend/home-lab/SparkCRM edits.
- No schema migration runner.
- No live DB mutation outside gated local-test database.
- No server/web runner changes.
- No claim about filesystem WAL fsync; that is P2-WAL.

## Questions To Answer

1. What exact uniqueness key represents a machine write effect:
   idempotency key, target+key, correlation id, or a tuple?
2. Does real Postgres already use an atomic writable CTE, and is it sufficient
   under concurrent clients?
3. What table/DDL drift should fail loud as permanent config error?
4. How does replay return the original receipt/result without re-executing the
   mutation?
5. What remains only in-process after this slice?

## Acceptance

- [x] Live real/fake write paths characterized before editing.
- [x] Real Postgres receipt table has or requires a UNIQUE durable CAS key.
- [x] Concurrent same-effect proof shows one durable mutation/receipt, not two.
- [x] Replay returns deterministic existing receipt/result.
- [x] Fake/default tests remain green without `postgres` feature or DSN.
- [x] Real PG tests are feature/env gated and skip cleanly without DSN.
- [x] Proof packet states DDL, conflict behavior, and remaining gaps.
- [x] `git diff --check` passes.
- [x] Card is closed with a concise report.

## Report (2026-06-28)

**Verify-first overturned the framing:** the DB-native CAS mechanism already existed (P8's
`TokioPostgresWriteAdapter::transact` is a single writable-CTE with `INSERT … effect_receipts
ON CONFLICT (idempotency_key) DO NOTHING` gating the business mutation on `EXISTS(ins)`).
What was missing was the **proof and hardening**, which this card delivered:

1. **Multi-process concurrency proof** — `real_concurrent_same_key_writes_once_multi_process`:
   two adapters on separate connections + separate receipt stores (= two processes) race the
   same idempotency key via `tokio::join!` on a multi-thread runtime → both `Committed`, dup
   flags exactly `{false,true}`, both reach the DB (`single_flight` can't dedup cross-process),
   exactly ONE business row + ONE `effect_receipts` row. **Ran green against the live local
   `igniter_pg_test`.**
2. **Canonical DDL** — `postgres_real::EFFECT_RECEIPTS_DDL` code-anchored; the PK on
   `idempotency_key` documented as the load-bearing exactly-once anchor; the real-write test
   now sources it instead of a private literal.
3. **DDL/config drift fails loud** — new `PostgresWriteResult::PermanentConfig`;
   `classify_write_error` maps 42P10 (missing `ON CONFLICT` unique key) / 42P01 / 42703 /
   42704 / 42P07 / 42601 → permanent `config/DDL error` (no longer mislabeled "constraint
   violation"). Proven by `real_ddl_drift_undefined_target_is_permanent_config` (real DB) +
   fake `permanent_config_ddl_drift_is_permanent_config_error` (default build).

Answers: Q1 uniqueness key = `idempotency_key` (single axis, == machine receipt key). Q2 the
writable CTE IS sufficient concurrently (DB arbitrates; loser's `EXISTS(ins)` is empty → no
mutation). Q3 DDL drift = 42P10/42P01/42703/42704/42P07/42601 → `PermanentConfig`. Q4 replay
deterministic via machine receipt (executor never reached) + PG dup (no 2nd mutation) +
read-only reconcile. Q5 still in-process / out of scope: filesystem WAL fsync (parallel
P2-WAL), `single_flight` (in-process fast path), `seq_id`/clock-ordered receipts, pool/TLS,
TBackend daemon adoption.

Files: `runtime/igniter-machine/src/postgres_write.rs` (+`PermanentConfig` result + fake
behavior + executor arm), `src/postgres_real.rs` (+`EFFECT_RECEIPTS_DDL` + drift
classification), `tests/postgres_write_tests.rs` (+fake shape test),
`tests/postgres_real_write_tests.rs` (+2 gated real tests, canonical DDL),
`IMPLEMENTED_SURFACE.md`, board A21, packet
`lab-docs/lang/lab-machine-durable-cas-pg-exactly-once-p2-v0.md`.

Verification: real PG (DSN-set) `postgres_real_write_tests` 7 PASS; fake `postgres_write_tests`
12 PASS; `postgres_reconcile_tests` 7 PASS; skip-clean without DSN; default + `postgres`
builds clean; `git diff --check` PASS.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_write_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_reconcile_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --features postgres --test postgres_real_write_tests
git diff --check
```

Adjust exact real-test name after verify-first.

## Required Packet

Create:

```text
lab-docs/lang/lab-machine-durable-cas-pg-exactly-once-p2-v0.md
```

Packet must include:

- before-state and exact live weakness;
- DDL / unique key policy;
- concurrency evidence;
- fake/default and real-gated verification results;
- remaining non-machine or non-PG durability gaps.
