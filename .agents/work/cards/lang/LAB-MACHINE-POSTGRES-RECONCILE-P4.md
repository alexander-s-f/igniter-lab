# Card: LAB-MACHINE-POSTGRES-RECONCILE-P4 — fake Postgres write reconcile

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol  
**Status: READY.** Follow-on to `LAB-MACHINE-POSTGRES-WRITE-GATE-P3`.

## Front door

Read first:

- `LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1.md`
- `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2.md`
- `LAB-MACHINE-POSTGRES-WRITE-GATE-P3.md`
- `lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`
- `lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md`
- `lab-docs/lang/lab-machine-postgres-write-gate-p3-v0.md`
- `LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13.md`
- `LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19.md`
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Verify live code before writing:

- `postgres_write::{PostgresWriteIntent, FakePostgresWriteAdapter, PostgresWriteResult}`
- `correlation::{CorrelationResolver, CorrelationLookup, reconcile_unknown_by_correlation}`
- `recovery::{recover_dangling_by_correlation, RecoveryReport}`
- `write::{run_write_effect, WriteState}`
- `tests/postgres_write_tests.rs`

## Goal

Close the P3 `unknown_external_state` hole for fake Postgres writes by proving exact read-back
reconciliation against the fake PG-side `effect_receipts(idempotency_key)` table:

```text
unknown write receipt
  carries idempotency/correlation trail
  -> PostgresWriteReconciler / resolver lookup (READ ONLY)
       found PG effect_receipt     -> machine receipt becomes committed
       not found                   -> machine receipt becomes permanent_failure
       adapter unavailable/unclear  -> remains unknown
```

This is the Postgres-shaped version of P13 correlation reconcile, using the in-transaction
`effect_receipts` table modelled in P3. It must **never** re-run the write executor.

## Required decisions

1. **Resolver/read-back only.** Reconcile code must not accept a `CapabilityExecutor` and must not
   call `PostgresWriteAdapter::transact`.
2. **Primary lookup key.** Use the PG-side idempotency key / effect receipt identity as the exact
   lookup. If a correlation id is present, record/return it; do not rely on same-value matching.
3. **Terminal mapping.**
   - found effect receipt → `committed`
   - not found → `permanent_failure`
   - unavailable/ambiguous → still `unknown_external_state`
4. **Dangling prepared support.** Reuse the P19/P13 model: a dangling `prepared` receipt after
   crash is eligible for reconcile, not blind retry.
5. **No business mutation.** Tests must prove adapter mutation count does not increase during
   reconcile.
6. **No real DB.** Fake adapter/resolver only; no SQL, driver, network, Docker, migration, or ORM.

## Suggested shape

Agent may choose exact API after verify-first, but keep it narrow and compositional:

```rust
pub trait PostgresWriteReceiptResolver: Send + Sync {
    async fn lookup_effect_receipt(&self, idempotency_key: &str) -> PostgresReceiptLookup;
}

pub enum PostgresReceiptLookup {
    Found { correlation_id: Option<String>, target: String, key: String },
    NotFound,
    Unavailable(String),
}

pub async fn reconcile_postgres_unknown_write(...)
```

Acceptable alternative: implement `correlation::CorrelationResolver` for a fake PG resolver if that
keeps the diff smaller. The important part is the semantics: read-only lookup of the fake PG-side
effect receipt table.

## Acceptance

- [ ] Verify-first confirms P3 write has PG-side fake `effect_receipts` but no reconcile helper yet.
- [ ] Reconcile is read-only: no executor/transact call, no new business mutation.
- [ ] Unknown write with PG effect receipt found resolves to `committed`.
- [ ] Unknown write with no PG effect receipt resolves to `permanent_failure`.
- [ ] Resolver unavailable keeps the receipt `unknown_external_state`.
- [ ] Dangling `prepared` receipt can be reconciled through the same path.
- [ ] Recovered committed receipt replays without re-executing.
- [ ] Correlation/idempotency/target/key evidence is preserved in the terminal receipt.
- [ ] Same-value false positive is impossible: lookup is by idempotency/effect receipt identity, not values.
- [ ] Fake only; no DB dependency, SQL execution, network, migrations, or ORM.
- [ ] Docs/card updated; `IMPLEMENTED_SURFACE.md` updated if public API is added.

## Closed surfaces

- Do not add real Postgres.
- Do not add `tokio-postgres`, `sqlx`, `diesel`, Docker, migrations, or SQL execution.
- Do not change `run_write_effect` semantics.
- Do not change retry/orchestrator behavior here.
- Do not implement a Postgres `TBackend`.
- Do not open public/network/live work.

## Deliverables

- Minimal implementation + tests.
- `lab-docs/lang/lab-machine-postgres-reconcile-p4-v0.md`
- Closing report in this card.
- `IMPLEMENTED_SURFACE.md` update only if public API is added.

## Next routes

- Real local Postgres remains a later opt-in `postgres` feature + human gate.
- `wire-path atomic gate` remains a separate serving-loop follow-up before any yielding receipt backend.
