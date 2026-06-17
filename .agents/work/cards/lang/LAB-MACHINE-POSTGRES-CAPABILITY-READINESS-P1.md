# Card: LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1 — Postgres connector + ORM boundary map

**Lane:** standard / readiness-design · **Skill:** idd-agent-protocol  
**Status: CLOSED 2026-06-17 — readiness/design packet produced.** Design/readiness only. No
dependency, no running Postgres, no SQL execution, no ORM implementation, no `src/` change.

## Closing report (2026-06-17)

Doc: [`lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`](../../../../lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md).

Verify-first confirmed against live code: **no Postgres connector, no ORM, no SQL/sqlx/tokio-postgres/
diesel anywhere** (zero hits in `src/`, `tests/`, `Cargo.toml`); storage is the abstract
`TBackend` only. The capability-IO substrate (`CapabilityExecutor` trait, `run_write_effect` +
`single_flight`, `reconcile`/`correlation`/`recovery`/`orchestrator`, `TBackendRead/WriteExecutor`,
`SparkCrmExecutor` domain pattern, `ExecuteQuery`+`IO.StorageCapability` 6-gate read vocabulary) is
already present and hardened — Postgres needs **no new primitive**.

Load-bearing conclusions:
- **v0 connector boundary = host `CapabilityExecutor` family** (`PostgresRead/WriteExecutor`), the
  `SparkCrmExecutor` pattern applied to SQL. **Postgres-as-`TBackend`** (fact-spine on Postgres) is a
  separate, heavier, **deferred** track — decided explicitly, not both.
- **Read** = typed `QueryPlan` + 6-gate + allowlisted parameterised templates (promotion of the
  proven mocked `ExecuteQuery`); arbitrary SQL from contracts rejected structurally.
- **Write** = `run_write_effect`/`run_write_effect_atomic` → one `BEGIN…COMMIT`; idempotency in two
  layers (machine `__receipts__` + a PG-side `effect_receipts(idempotency_key PK)` upsert in-txn);
  full PG-error→`EffectOutcome` taxonomy.
- **Reconcile** = read-back the in-txn effect-receipt table (correlation-grade, exact), business-key
  fallback; never re-issue.
- **ORM** = host-side typed repository structs; capsules never get a DB handle.
- **Schema** = hand-written repo config + boot-time introspection *validation* (refuse on drift).
- **Migrations** out of v0 (named seam). **Transactions** = one effect ↔ one txn; cross-effect via
  compensation (P12), not 2PC.
- **Security** reuses `SecretProvider`/passport/TLS-allowlist; mandatory parameterisation; no raw SQL
  in receipts; redaction.
- **Next slice (bounded):** `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2` — **fake-adapter** read executor,
  no DB, no dependency. Then write-gate P3, reconcile P4, then human-gated real local Postgres behind
  an opt-in `postgres` feature (recommend `tokio-postgres` + pool; reject `diesel`).

## Front door

Read first:

- `igniter-machine/IMPLEMENTED_SURFACE.md`
- `LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25.md`
- `LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1.md`
- `LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE.md`

Verify live code before writing:

- `capability::{CapabilityExecutor, EffectOutcome}`
- `write::{run_write_effect, WriteState, payload_digest}`
- `single_flight::run_write_effect_atomic`
- `reconcile` / `correlation` / `recovery` / `orchestrator`
- `http::HttpCapabilityExecutor` and `sparkcrm::SparkCrmExecutor` as examples of domain
  executors that compose without new primitives.
- Search for `postgres`, `sql`, `orm` and state the current truth. Expected at card start:
  **no Postgres connector and no ORM layer exist today**.

## Goal

Answer how Postgres and "ORM" should enter `igniter-machine` without contaminating the language or
capsule purity:

```text
capsule/contract emits typed intent
  → host capability executor / repository adapter
  → Postgres query/transaction
  → receipt/idempotency/reconcile/observability
```

The output should be a concrete readiness packet and a proposed next implementation slice, not a
general essay about databases.

## Questions to answer

1. **What is the connector boundary?** Is Postgres a `CapabilityExecutor`, a `TBackend`, or both?
   Decide v0 clearly.
2. **Read path:** what is the first safe read-only shape? Prefer allowlisted query templates or
   typed repository operations; reject arbitrary SQL from contracts.
3. **Write path:** how does receipt-gated write map to SQL transactions? Where is the idempotency
   key stored or enforced? What is the failure taxonomy?
4. **Reconcile:** how do we determine whether an unknown SQL write landed? Primary key? business
   key? correlation table? receipt table?
5. **ORM meaning:** define ORM as a host-side typed repository/adapter, not language authority.
   State explicitly that contracts/capsules do not receive a DB handle.
6. **Schema authority:** where do table schemas live? Postgres introspection, typed adapter config,
   generated bindings, or hand-written repository?
7. **Migrations:** out of scope or integrated? If out of scope, name the future seam.
8. **Transactions:** what is v0 transaction boundary? One operation per effect? Multi-step unit?
9. **Security:** secret source, allowlist, query parameterization, no raw SQL in receipt, redaction.
10. **Test strategy:** fake transport first, local Postgres later, or direct local Postgres with
    opt-in dependency? Recommend the next slice.

## Required stance

The language/VM must stay pure. A `.ig` contract may declare an intent or use a typed data source;
it must not hold a Postgres connection, run arbitrary SQL, or become an ORM runtime.

Recommended default unless live code proves otherwise:

```text
Postgres v0 = host CapabilityExecutor + typed repository operations
NOT a new language primitive
NOT ActiveRecord inside the capsule
NOT arbitrary SQL from contract inputs
```

## Acceptance

- [x] Verify-first section cites current files and confirms no existing Postgres/ORM surface.
- [x] Produces `lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`.
- [x] Defines v0 connector boundary: `CapabilityExecutor`, `TBackend`, or explicit split.
- [x] Provides a read-only first slice and a write slice, with acceptance for each.
- [x] Defines unknown/reconcile strategy for SQL writes.
- [x] Defines ORM/repository semantics and keeps ORM out of contracts/VM.
- [x] Lists dependency choices and tradeoffs (`tokio-postgres`, `sqlx`, fake adapter first, etc.)
      without adding them.
- [x] States security and redaction rules.
- [x] Names the next implementation card with a bounded scope.
- [x] No code changes unless only updating this card with closing report.

## Closed surfaces

- No new dependencies.
- No live database, no Docker/Postgres process, no network.
- No SQL execution.
- No migration runner.
- No ORM inside `.ig`, VM, or capsule activation.
- No changes to capability-IO semantics.

## Suggested next cards

- `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2` — fake/local read-only typed query executor.
- `LAB-MACHINE-POSTGRES-WRITE-GATE-P3` — receipt-gated SQL write design/proof.
- `LAB-MACHINE-POSTGRES-RECONCILE-P4` — correlation/business-key reconciliation.
