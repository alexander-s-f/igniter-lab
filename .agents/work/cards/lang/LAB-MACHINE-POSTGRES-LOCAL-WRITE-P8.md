# Card: LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8 — real local Postgres write transaction (opt-in feature)

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol
**Status: CLOSED 2026-06-17 — implementation proof complete (5/5 against real dedicated DB).**
Unblocked by `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7`. Real local Postgres WRITE against a **dedicated
test DB** (`igniter_pg_test`) — never SparkCRM business tables.

## Closing report (2026-06-17)

Doc: [`lab-docs/lang/lab-machine-postgres-local-write-p8-v0.md`](../../../../lab-docs/lang/lab-machine-postgres-local-write-p8-v0.md).

**First REAL database WRITE.** Added `TokioPostgresWriteAdapter` to `src/postgres_real.rs` (impl
`PostgresWriteAdapter` + `PostgresWriteReceiptResolver`) + `tests/postgres_real_write_tests.rs`. No
`Cargo.toml`/`lib.rs` change (the `postgres` feature/module existed from P6). Driven by the UNCHANGED
`run_write_effect`; only the adapter is real, a drop-in behind the P3/P4 traits.

**One effect = one atomic statement** via a writable CTE: `effect_receipts` `ON CONFLICT
(idempotency_key) DO NOTHING` + a business upsert gated `WHERE EXISTS (SELECT 1 FROM ins)` →
`fresh=1`→Committed / `fresh=0`→DuplicateKey. Atomic without a transaction object (`Client::query`
takes `&self` → `Arc<Client>` suffices). Taxonomy: 23xxx→permanent, 40001/40P01→retryable,
42501→denied, connection→unknown. Reconcile resolver = read-only `SELECT … WHERE idempotency_key=$1`.

**Safety:** dedicated `igniter_pg_test` reached by a SEPARATE env `IGNITER_PG_WRITE_DSN` (never the
read DSN → can't hit SparkCRM); host-configured target/key/columns (no contract-supplied
identifiers); fixture DDL once-per-process (OnceCell guards the concurrent CREATE race); targeted
per-test cleanup (parallel-safe, re-runnable).

**Verify:** `IGNITER_PG_WRITE_DSN=… cargo test --no-default-features --features postgres --test
postgres_real_write_tests` → **5/5** (rerun → 5/5; no DSN → 5 skip). Default
`cargo test --no-default-features` → **52 suites green, no regression**. Read-only on SparkCRM
preserved (writes only to `igniter_pg_test`).

## Front door

Read first:

- `LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5.md` (§Q7 write mapping) + its doc
- `LAB-MACHINE-POSTGRES-WRITE-GATE-P3.md` + `lab-docs/lang/lab-machine-postgres-write-gate-p3-v0.md`
- `LAB-MACHINE-POSTGRES-RECONCILE-P4.md` + its doc
- `LAB-MACHINE-POSTGRES-LOCAL-READ-P6.md` + its doc (the `postgres` feature + `TokioPostgresReadAdapter` pattern)
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Verify live code before writing:

- `postgres_write::{PostgresWriteAdapter, PostgresWriteResult, PostgresWriteIntent, PostgresWriteExecutor, PostgresWriteReceiptResolver, PostgresReceiptLookup, reconcile_postgres_unknown_write}`
- `postgres_real::TokioPostgresReadAdapter` (connect pattern)
- `write::{run_write_effect, run_write_effect_atomic, WriteState}`

## Goal

Implement the first real `PostgresWriteAdapter` (over `tokio-postgres`) behind the opt-in `postgres`
feature, proving the P3 write boundary + P4 reconcile against a real local Postgres — **one effect =
one transaction**, with the PG-side `effect_receipts(idempotency_key)` second idempotency layer.

```text
WriteRequest payload = typed PostgresWriteIntent
  → run_write_effect[_atomic] (machine receipt: prepared → terminal)   [UNCHANGED]
  → TokioPostgresWriteAdapter.transact()        [#[cfg(feature = "postgres")]]
       ONE atomic statement: effect_receipts ON CONFLICT(idempotency_key) DO NOTHING
                             + business upsert WHERE the receipt was fresh
  → PostgresWriteResult → WriteState
reconcile (P4): TokioPostgresWriteAdapter.lookup_effect_receipt() = SELECT (read-only)
```

## Required design

1. **Opt-in feature.** Reuse `postgres = ["dep:tokio-postgres"]`; default build unchanged. Real
   adapter `#[cfg(feature = "postgres")]`.
2. **Dedicated test DB.** `igniter_pg_test` (NOT SparkCRM). Schema = fixture DDL in TEST setup
   (`effect_receipts` + a business table), never created by the executor or a contract.
3. **No raw SQL from contracts.** The intent is typed; the adapter is host-configured with the
   target/key-column/value-columns it may write — contract input never supplies identifiers.
4. **One effect = one transaction.** Business mutation + `effect_receipts(idempotency_key)` upsert
   in ONE atomic statement; the receipt insert gates the business mutation (fresh → write;
   conflict → DuplicateKey, no second mutation).
5. **Taxonomy parity (P3).** commit → Committed; PG-side duplicate → DuplicateKey; constraint/type →
   ConstraintViolation(permanent); serialization/deadlock → SerializationFailure(retryable);
   insufficient_privilege → Denied; connection lost → Unknown.
6. **Reconcile parity (P4).** `lookup_effect_receipt` = read-only `SELECT … WHERE idempotency_key=$1`;
   found → committed, not-found → permanent_failure, connection error → still-unknown. No re-exec.
7. **Tests split.** Default fake/unit green; integration `#![cfg(feature = "postgres")]`, **skips
   when no DSN**. Use a dedicated `IGNITER_PG_WRITE_DSN` so write tests can NEVER target SparkCRM.

## Acceptance

- [x] Verify-first confirms no real Postgres write adapter exists before this card.
- [x] `TokioPostgresWriteAdapter` implements `PostgresWriteAdapter`, driven by `run_write_effect`.
- [x] One effect = one atomic statement (business row + effect receipt).
- [x] Successful write: machine receipt committed + business row present + PG effect receipt present.
- [x] Replay (same key+payload) bypasses the adapter via the machine receipt.
- [x] PG-side duplicate key blocks a second business mutation even with a fresh machine receipt store.
- [x] Constraint error → permanent; (taxonomy parity with the fake).
- [x] Reconcile: unknown + PG effect receipt found → committed; not found → permanent_failure;
      read-only (no re-exec, no new mutation).
- [x] Integration test uses the dedicated DB, skips cleanly without DSN; default suite unaffected.
- [x] Docs/card updated; `IMPLEMENTED_SURFACE.md` updated.

## Closed surfaces

- No production / staging / SparkCRM business tables (dedicated test DB only).
- No connection pool / TLS / migrations runner (single connection; fixture DDL in test setup).
- No ORM in `.ig`/VM/capsule; no Postgres-as-`TBackend`.
- No DSN/credentials in code/receipts/docs.
- No change to serving loop / ingress / wire-path or to `run_write_effect` semantics.

## Deliverables

- Real adapter + integration test.
- `lab-docs/lang/lab-machine-postgres-local-write-p8-v0.md`
- Closing report in this card.

## Next routes

- `LAB-MACHINE-POSTGRES-POOL-READINESS-*` — connection pool shape (concurrency), later.
- `postgres-tls`, rich type mapping, fuller filter predicates — named follow-ons.
