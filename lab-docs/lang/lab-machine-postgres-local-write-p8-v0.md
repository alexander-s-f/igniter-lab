# LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8: real local Postgres write transaction (opt-in feature)

**Track:** `lab-machine-postgres-local-write-p8-v0`
**Status:** CLOSED — implementation proof. **First REAL database WRITE.** Opt-in `postgres` feature;
default build unchanged. One effect = one atomic statement. Proven against a **dedicated** local
Postgres (`igniter_pg_test`) — never SparkCRM business tables.
**Route:** unblocked by `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7` (the wire seam is atomic).
**Authority:** No canon claim. No language authority. Lab evidence only. Dedicated test DB only.

---

## What was proved

The P3 write boundary and P4 reconcile now work against a **real** Postgres.
`TokioPostgresWriteAdapter` (over `tokio-postgres`) implements the unchanged `PostgresWriteAdapter`
and `PostgresWriteReceiptResolver`; the `PostgresWriteExecutor` gates and the
`run_write_effect` two-phase receipt are **identical** to the fake path — only the adapter is real.

```text
WriteRequest payload = typed PostgresWriteIntent
  → run_write_effect (machine receipt: prepared → terminal)          [UNCHANGED]
  → TokioPostgresWriteAdapter.transact()        [#[cfg(feature = "postgres")]]
      ONE atomic statement (writable CTE):
        WITH ins AS (INSERT INTO effect_receipts … ON CONFLICT (idempotency_key) DO NOTHING RETURNING 1),
             biz AS (INSERT INTO <target> … SELECT … WHERE EXISTS (SELECT 1 FROM ins)
                     ON CONFLICT (<key>) DO UPDATE …)
        SELECT count(*) AS fresh FROM ins      -- fresh=1 → Committed, 0 → DuplicateKey
  → PostgresWriteResult → WriteState
reconcile (P4): TokioPostgresWriteAdapter.lookup_effect_receipt() = SELECT (read-only)
```

**One effect = one transaction** without a transaction object: a single writable-CTE statement is
atomic, so the business mutation and the `effect_receipts` upsert commit (or roll back) together —
and `Client::query` takes `&self`, so `Arc<Client>` suffices (no `&mut`). The receipt insert gates
the business upsert (`WHERE EXISTS (SELECT 1 FROM ins)`): a duplicate idempotency key ⇒ `ins` empty
⇒ no business mutation ⇒ `DuplicateKey`.

---

## Verify-first

Before this card: a real read adapter (P6) existed; **no real write adapter**. The boundary read:
`postgres_write::{PostgresWriteAdapter, PostgresWriteResult, PostgresWriteIntent,
PostgresWriteReceiptResolver, PostgresReceiptLookup, reconcile_postgres_unknown_write}` (P3/P4) and
`postgres_real::TokioPostgresReadAdapter` (the `connect` + feature pattern).

---

## Files

| File | Purpose |
|------|---------|
| `igniter-machine/src/postgres_real.rs` | + `TokioPostgresWriteAdapter` (impl `PostgresWriteAdapter` + `PostgresWriteReceiptResolver`), `classify_write_error`, `json_to_opt_text` |
| `igniter-machine/tests/postgres_real_write_tests.rs` | `#![cfg(feature = "postgres")]`, DSN-gated — 5 integration tests |
| `lab-docs/lang/lab-machine-postgres-local-write-p8-v0.md` | this doc |
| `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8.md` | card + closing report |

No `Cargo.toml`/`lib.rs` change (the `postgres` feature + module already existed from P6).

---

## Safety: dedicated DB, host-owned identifiers

- **Dedicated test DB only.** The write tests read a SEPARATE env var `IGNITER_PG_WRITE_DSN` (not
  the read `IGNITER_PG_DSN`), so they can NEVER target the SparkCRM databases. Schema = fixture DDL
  (`effect_receipts` + a `leads` business table) created once per process (a `OnceCell` guards the
  concurrent `CREATE TABLE IF NOT EXISTS` race); each test cleans only its OWN keys/ids
  (parallel-safe, re-runnable).
- **No contract-supplied identifiers.** The adapter is HOST-CONFIGURED with the one `target`, its
  `key_column`, and the `columns` it may write. The intent's `values` are read ONLY for those
  configured columns (missing → NULL); a contract can never inject a table/column name.
- **DSN never in code/receipts.** `{{secret}}`/env source; NoTls loopback (TLS = later slice).

## Outcome taxonomy (real PG → `PostgresWriteResult` → `WriteState`)

| Condition | Result | WriteState |
|---|---|---|
| `fresh=1` | `Committed` | `Committed` |
| `fresh=0` (PG idempotency key already present) | `DuplicateKey` | `Committed` (no 2nd mutation) |
| SQLSTATE `23xxx` (constraint/not-null/type) | `ConstraintViolation` | `PermanentFailure` |
| SQLSTATE `40001`/`40P01` (serialization/deadlock) | `SerializationFailure` | `Retryable` |
| SQLSTATE `42501` | `Denied` | `Denied` |
| connection/IO error | `Unknown` | `UnknownExternalState` |

---

## Proof results (5/5, dedicated DB; repeatable)

`IGNITER_PG_WRITE_DSN="host=localhost user=alex dbname=igniter_pg_test" cargo test
--no-default-features --features postgres --test postgres_real_write_tests` → **5/5**. Re-run → 5/5
(targeted cleanup makes it idempotent). Without the DSN → **5 skip cleanly**.

| Test | Proves (against the real DB) |
|---|---|
| `real_commit_lifecycle` | machine `committed` + real business row written + real PG effect receipt present; adapter ran once |
| `real_pg_side_dedup_blocks_second_mutation` | machine receipt LOST + different values on the same key → `DuplicateKey`, business row UNCHANGED (one mutation despite 2 attempts) |
| `real_replay_bypasses_adapter` | replay same key+payload → machine receipt replays, adapter never touched |
| `real_constraint_violation_is_permanent` | NOT-NULL violation (23502) → `PermanentFailure`; **atomic rollback** (neither business row nor effect receipt landed) |
| `real_reconcile_found_commits_not_found_permanent` | unknown + real PG effect receipt found → `committed`; absent → `permanent_failure`; READ-ONLY (no new transaction) |

**Default build** (`cargo test --no-default-features`): **52 suites green, no regression**;
`postgres_real`/the write tests excluded, no driver compiled.

---

## Boundary findings

- **The fake (P3/P4) was a faithful contract.** The real adapter dropped in behind the unchanged
  traits and matched the observable behaviour (commit/duplicate/constraint taxonomy, two-layer
  idempotency, read-only reconcile) — the boundary held end-to-end against real Postgres.
- **Atomicity is structural.** The constraint test proves all-or-nothing: a failed business insert
  rolls back the `effect_receipts` row too (single writable-CTE statement), so a permanent failure
  leaves NO dangling receipt.
- **PG-side dedup is the real second layer.** With the machine receipt lost, the executor re-runs,
  but Postgres's `effect_receipts` primary key blocks the second business mutation — exactly the
  defence-in-depth the readiness packet specified, now on real infrastructure.
- **Honest v0 bounds.** Single connection (no pool); `::text`/text-column values; one host-configured
  target — all named follow-ons, not silent gaps.

---

## Closed surfaces

| Surface | Status |
|---|---|
| Production / staging / SparkCRM business tables | Closed — dedicated `igniter_pg_test` only |
| Connection pool | Closed — single connection (`postgres-pool` later) |
| TLS to Postgres | Closed — NoTls loopback (later) |
| Migrations runner | Closed — fixture DDL in test setup |
| Rich PG-type mapping / non-text columns | Closed — text v0 (named follow-on) |
| ORM in `.ig`/VM/capsule · Postgres-as-`TBackend` | Closed |
| Serving loop / ingress / wire-path / `run_write_effect` semantics | Unchanged |
| DSN/credentials in code/receipts/docs | Closed — env/SecretProvider reference only |

---

## Next routes

- `LAB-MACHINE-POSTGRES-POOL-READINESS-*` — connection pool shape for concurrent serving (the wire
  path is already atomic per P7).
- `postgres-tls`, rich type mapping, fuller filter predicates — named follow-ons.

---

*LAB-ONLY. No canon claim. No language authority. Dedicated local dev DB only. Lab evidence does not
by itself create canon.*
