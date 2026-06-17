# Card: LAB-MACHINE-POSTGRES-WRITE-GATE-P3 — fake Postgres receipt-gated write

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol  
**Status: READY.** Follow-on to `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2`.

## Front door

Read first:

- `LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1.md`
- `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2.md`
- `lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`
- `lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md`
- `LAB-MACHINE-CAPABILITY-IO-WRITE-P6.md`
- `LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18.md`
- `LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19.md`
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Verify live code before writing:

- `write::{run_write_effect, run_write_effect_with_passport, WriteState, payload_digest}`
- `single_flight::run_write_effect_atomic`
- `postgres_read::{QueryPlan, PostgresReadPolicy}` for naming/style only
- `executors::TBackendWriteExecutor` as existing write-executor pattern
- `sparkcrm::SparkCrmExecutor` as domain executor pattern

## Goal

Prove the **Postgres-shaped write boundary** without a real database:

```text
WriteRequest payload = typed WriteIntent (NO SQL string, NO DB handle)
  → run_write_effect / run_write_effect_atomic
  → PostgresWriteExecutor (host CapabilityExecutor)
  → FakePostgresWriteAdapter.transaction(...)
      business mutation + pg_effect_receipts(idempotency_key PK) in one fake txn
  → WriteState + machine receipt
```

This card proves the design from P1:

- one effect = one transaction;
- idempotency has two layers: machine `__receipts__` + fake PG-side `effect_receipts` table;
- no blind retry on unknown;
- no ORM/SQL inside `.ig` or capsule.

## Required design

1. **No dependencies.** Do not add `tokio-postgres`, `sqlx`, `diesel`, Docker, or a real DB.
2. **No arbitrary SQL.** Payload is a typed operation/intent. Raw SQL keys are structurally refused.
3. **Host-side only.** Capsules/contracts do not receive DB handles, SQL strings, pools, cursors, or
   ORM objects.
4. **Transaction model.** Fake adapter must model one transaction containing:
   - a business mutation, and
   - insertion/upsert of a PG-side effect receipt keyed by idempotency key.
5. **Outcome taxonomy.**
   - committed transaction → `committed`;
   - duplicate PG-side idempotency key → committed/replay-like result, not second mutation;
   - constraint/type error → permanent failure;
   - insufficient privilege / policy denial → denied;
   - serialization/deadlock-style transient that rolled back → retryable;
   - lost-after-send / unknown commit state → unknown_external_state.
6. **Identity digest.** Payload digest must include target identity and values, not only operation
   name, so same key + different payload is refused before adapter execution.

## Suggested minimal API

Agent may choose exact names after verify-first, but keep the shape narrow:

```rust
pub struct PostgresWriteIntent {
    pub operation: String,
    pub target: String,
    pub key: String,
    pub values: Value,
    pub correlation_id: Option<String>,
}

pub trait PostgresWriteAdapter: Send + Sync {
    async fn transact(&self, intent: &PostgresWriteIntent, idempotency_key: &str)
      -> PostgresWriteResult;
}

pub struct PostgresWriteExecutor<A> { ... }
```

`FakePostgresWriteAdapter` can keep two in-memory maps:

- `business_rows[target/key] = values`
- `effect_receipts[idempotency_key] = { correlation_id, target, key }`

## Acceptance

- [ ] Verify-first confirms P2 is read-only and no Postgres write executor exists.
- [ ] `PostgresWriteExecutor` implements `CapabilityExecutor` and is exercised through
      `run_write_effect` or `run_write_effect_atomic`, not a bespoke runner.
- [ ] Fake adapter only; no new dependency, no real SQL/network.
- [ ] Typed write intent accepted; raw SQL payload refused structurally before adapter call.
- [ ] Successful write lifecycle: machine receipt `prepared → committed`, fake business row written,
      fake PG-side effect receipt inserted.
- [ ] Replay same idempotency key + same payload bypasses adapter through machine receipt.
- [ ] Same idempotency key + different payload refused before adapter execution.
- [ ] PG-side duplicate idempotency key prevents a second business mutation if machine receipt is
      absent or simulated-lost.
- [ ] Transient rolled-back condition maps to `retryable`; unknown/lost-after-send maps to
      `unknown_external_state` with no blind retry.
- [ ] Constraint/type error maps to permanent failure; authorization/policy denial maps to denied.
- [ ] Correlation/idempotency key is recorded in result/receipt details without leaking raw SQL or
      secrets.
- [ ] Docs/card updated; `IMPLEMENTED_SURFACE.md` updated if public API is added.

## Closed surfaces

- No real Postgres.
- No DB driver dependencies.
- No migrations.
- No actual SQL execution.
- No ORM in `.ig`, VM, or capsule activation.
- No `TBackend` implementation for Postgres.
- No public/network/live work.
- No automatic reconcile loop here; reconcile is P4.

## Deliverables

- Minimal implementation + tests.
- `lab-docs/lang/lab-machine-postgres-write-gate-p3-v0.md`
- Closing report in this card.

## Next routes

- `LAB-MACHINE-POSTGRES-RECONCILE-P4` — exact reconcile via fake PG-side effect receipt table.
- Real local Postgres remains a later opt-in dependency/gate.
