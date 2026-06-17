# Card: LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2 — fake-adapter Postgres read executor

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol  
**Status: READY.** This is the bounded next slice from
`LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1`.

## Front door

Read first:

- `LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1.md`
- `lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Verify live code before writing:

- `capability::{CapabilityExecutor, EffectRequest, EffectOutcome, OutcomeKind}`
- `CapabilityExecutorRegistry`
- existing read executors in `executors.rs`
- `http::HttpCapabilityExecutor` and `sparkcrm::SparkCrmExecutor` as domain-executor patterns
- existing `ExecuteQuery` / `IO.StorageCapability` docs and fixtures, if available

## Goal

Implement the **first Postgres-shaped read capability** without adding a real database dependency.

This is a fake-adapter proof:

```text
EffectRequest args = typed QueryPlan + StorageCapability-like policy
  → PostgresReadExecutor (host CapabilityExecutor)
  → FakePostgresAdapter (allowlisted parameterized query model, no SQL execution)
  → EffectOutcome + receipt through existing capability machinery
```

The point is to prove the connector boundary and safety gates, not to talk to Postgres yet.

## Required design

1. **No dependencies.** Do not add `tokio-postgres`, `sqlx`, `diesel`, Docker, or a real DB.
2. **No arbitrary SQL.** The contract/request provides a typed plan or named query; the executor
   chooses the host-owned template.
3. **Host-side only.** Capsules/contracts do not receive a DB handle, SQL string, pool, cursor, or
   ORM object.
4. **Read-only.** Mutating operations are refused before adapter execution.
5. **Allowlist gates.** Source/table, operation, projected fields, filters, and limit are checked
   before adapter execution.
6. **Outcome taxonomy.** Rows/empty are success; gate denial is denied/permanent as appropriate;
   adapter unavailable is unknown/retryable according to the readiness packet.
7. **Receipts.** Use the existing capability execution path so replay bypasses the adapter.

## Suggested minimal API

Agent may adjust names after verify-first, but keep the shape narrow:

```rust
pub trait PostgresReadAdapter: Send + Sync {
    async fn query(&self, plan: &QueryPlan) -> PostgresReadResult;
}

pub struct PostgresReadExecutor<A> {
    capability_id: String,
    adapter: Arc<A>,
    policy: PostgresReadPolicy,
}
```

`FakePostgresAdapter` can be an in-memory table map keyed by allowlisted source/query name.

## Acceptance

- [ ] Verify-first note confirms no real Postgres connector exists before this card.
- [ ] `PostgresReadExecutor` implements `CapabilityExecutor`.
- [ ] Fake adapter only; no new dependency and no real SQL/network.
- [ ] Typed query/plan input accepted; raw SQL input refused structurally.
- [ ] Allowlisted source/query succeeds and returns rows.
- [ ] Empty result maps to success/empty, not failure.
- [ ] Unknown source / forbidden field / mutation attempt refused before adapter call.
- [ ] Row limit is clamped by policy and reflected in result/receipt details.
- [ ] Adapter unavailable maps to `UnknownExternalState` or `Retryable` per documented taxonomy.
- [ ] Replay with same idempotency key bypasses the adapter (adapter call count remains 1).
- [ ] Docs/card updated; `IMPLEMENTED_SURFACE.md` updated only if public API is added.

## Closed surfaces

- No real Postgres.
- No DB driver dependencies.
- No migrations.
- No writes.
- No ORM in `.ig`, VM, or capsule activation.
- No `TBackend` implementation for Postgres.
- No public/network/live work.

## Deliverables

- Minimal implementation + tests.
- `lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md`
- Closing report in this card.

## Next routes

- `LAB-MACHINE-POSTGRES-WRITE-GATE-P3` — receipt-gated SQL write design/proof.
- `LAB-MACHINE-POSTGRES-RECONCILE-P4` — exact reconcile via PG-side effect receipt table.
- Real local Postgres remains a later opt-in dependency/gate.
