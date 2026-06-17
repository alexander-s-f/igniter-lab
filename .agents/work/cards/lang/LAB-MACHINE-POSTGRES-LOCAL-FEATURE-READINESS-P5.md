# Card: LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5 — real local Postgres feature gate

**Lane:** formal / readiness gate · **Skill:** idd-agent-protocol  
**Status: READY.** Follow-on to the fake-adapter Postgres wave P1→P4.

This card prepares the decision packet for a **real local Postgres adapter**. It must not add a
driver, start Docker, connect to a DB, create credentials, or run live/staging traffic.

## Front door

Read first:

- `LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1.md`
- `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2.md`
- `LAB-MACHINE-POSTGRES-WRITE-GATE-P3.md`
- `LAB-MACHINE-POSTGRES-RECONCILE-P4.md`
- `lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`
- `lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md`
- `lab-docs/lang/lab-machine-postgres-write-gate-p3-v0.md`
- `lab-docs/lang/lab-machine-postgres-reconcile-p4-v0.md`
- `LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1.md`
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Verify live code before writing:

- `postgres_read::{PostgresReadExecutor, PostgresReadAdapter, QueryPlan}`
- `postgres_write::{PostgresWriteExecutor, PostgresWriteAdapter, PostgresWriteReceiptResolver}`
- `secrets::{EnvSecretProvider, FileSecretProvider, LayeredSecretProvider}`
- `single_flight::run_write_effect_atomic`
- `serving_loop::{ServingLoop, ConcurrentServingPolicy}` and the P13 wire-path caveat
- `Cargo.toml` feature/dependency layout

## Goal

Produce a readiness packet answering whether/how to open a real local Postgres implementation behind
an opt-in feature:

```text
fake Postgres adapters (P2/P3/P4)
  -> real local adapter gate packet
       dependency choice
       feature flag shape
       local test topology
       DSN/secret source
       schema/migration ownership
       reconcile/read/write mapping
       wire-path atomicity precondition
  -> human decision before implementation
```

This is **not** the implementation card. It is the safety packet that prevents a background agent
from casually adding `tokio-postgres`/Docker/DSN handling without an explicit decision.

## Required questions

1. **Dependency choice.** `tokio-postgres` + pool wrapper? `deadpool-postgres`? why not `sqlx` or
   `diesel` for v0? What exact crates/features would be added?
2. **Feature shape.** What Cargo feature gates the real adapter (`postgres`?), and does default build
   stay dependency-free / fake-only?
3. **Local server source.** How will tests obtain Postgres: existing local service, Docker, embedded,
   or human-provided DSN? Which are allowed in CI vs developer machine?
4. **Secret/DSN handling.** Which `SecretProvider` name(s) resolve DSN/credentials? How are secrets
   kept out of contracts, receipts, and docs?
5. **Schema ownership.** Who creates the `effect_receipts` table and any test business tables?
   Are migrations in scope, fixture SQL, or explicitly out of scope?
6. **Read adapter mapping.** How does `QueryPlan` lower to parameterized SQL without raw SQL from
   contracts? How are source/field/op allowlists enforced before query building?
7. **Write adapter mapping.** How does one effect map to one transaction: business mutation +
   `effect_receipts(idempotency_key)` in the same transaction?
8. **Reconcile mapping.** Exact SQL/read-back for found/not-found/unavailable. How does it preserve
   P4 semantics and avoid re-execution?
9. **Atomicity precondition.** Does the serving wire path need `run_write_effect_atomic` threaded
   into `handle_effect` before any yielding receipt/backend path is used?
10. **Test matrix.** Minimal local tests for read/write/reconcile and failure taxonomy. Which tests
    are durable unit/fake, which are integration and opt-in?
11. **Closed surfaces.** What is explicitly not authorized: production DB, staging DB, public
    ingress, ORM in `.ig`, Postgres-as-`TBackend`, live vendor traffic.

## Acceptance

- [ ] Verify-first cites the current fake surfaces P2/P3/P4 and confirms no real Postgres adapter exists.
- [ ] Packet answers all 11 required questions.
- [ ] Recommends an implementation sequence with the smallest first real-local slice.
- [ ] States exact dependency/feature proposal and what remains default-build clean.
- [ ] States DSN/secret names without values.
- [ ] States schema/migration boundary.
- [ ] Names the wire-path atomicity decision before any yielding backend.
- [ ] Separates fake/unit tests from opt-in integration tests.
- [ ] No code, no dependency edits, no DB connection, no Docker/server start, no credentials.
- [ ] Card is closed with a decision-ready summary.

## Deliverables

- `lab-docs/lang/lab-machine-postgres-local-feature-readiness-p5-v0.md`
- Closing report in this card.
- Optional thin pointer in `IMPLEMENTED_SURFACE.md` readiness/design block only if useful.

## Closed surfaces

- Do not edit `Cargo.toml`.
- Do not add `tokio-postgres`, `sqlx`, `diesel`, pools, Docker, or migrations.
- Do not connect to a database.
- Do not create or read real credentials.
- Do not implement ORM or Postgres-as-`TBackend`.
- Do not change serving loop / ingress / wire-path behavior.

## Possible next routes after this gate

- `LAB-MACHINE-POSTGRES-LOCAL-READ-P6` — real local read adapter behind opt-in feature.
- `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P?` — thread P18 atomic gate into the wire path before yielding
  receipt/backend use.
- `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P?` — real local write transaction + effect_receipts table.
