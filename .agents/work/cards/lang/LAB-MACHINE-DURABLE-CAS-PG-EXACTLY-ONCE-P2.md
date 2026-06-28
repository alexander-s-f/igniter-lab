# LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2

Status: OPEN
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

- [ ] Live real/fake write paths characterized before editing.
- [ ] Real Postgres receipt table has or requires a UNIQUE durable CAS key.
- [ ] Concurrent same-effect proof shows one durable mutation/receipt, not two.
- [ ] Replay returns deterministic existing receipt/result.
- [ ] Fake/default tests remain green without `postgres` feature or DSN.
- [ ] Real PG tests are feature/env gated and skip cleanly without DSN.
- [ ] Proof packet states DDL, conflict behavior, and remaining gaps.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

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
