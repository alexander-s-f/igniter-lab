# LAB-MACHINE-POSTGRES-WRITE-GATE-P3: fake-adapter Postgres receipt-gated write

**Track:** `lab-machine-postgres-write-gate-p3-v0`
**Status:** CLOSED — implementation proof. **Fake adapter only. No DB, no SQL, no network, no new dependency.**
**Route:** LAB implementation slice, follow-on to `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2`.
**Authority:** No canon claim. No language authority. Lab evidence only. Old Ruby framework
surfaces are not authority.

---

## What was proved

The **Postgres-shaped write boundary** exists in `igniter-machine`, implemented as a host
`CapabilityExecutor` and driven by the EXISTING `write::run_write_effect` two-phase receipt
protocol — with **two idempotency layers** (machine `__receipts__` + a PG-side
`effect_receipts(idempotency_key)` table) and the full failure taxonomy. Still **no real
database**: the adapter is an in-memory fake.

```text
WriteRequest.payload = typed PostgresWriteIntent (NO SQL string, NO DB handle)
  → run_write_effect / run_write_effect_atomic     (machine receipt: prepared → terminal)
       layer-1 idempotency: machine __receipts__ (replay / different-payload refusal)
  → PostgresWriteExecutor : CapabilityExecutor
       gates BEFORE the adapter: raw-SQL refusal · target allowlist · op allowlist
  → PostgresWriteAdapter.transact(intent, idempotency_key)   (fake: ONE txn)
       layer-2 idempotency: PG-side effect_receipts(idempotency_key) → no 2nd mutation
  → EffectOutcome → WriteState (committed/denied/retryable/permanent/unknown)
```

This realises the P1 readiness §4 design: **one effect = one transaction**; idempotency is defence
in depth; unknown is never blindly retried; no ORM/SQL reaches `.ig`, the VM, or a capsule.

---

## Verify-first

P2 (`postgres_read`) is read-only; before P3 there was **no Postgres write executor**. The live
write protocol read for this slice (`src/write.rs`):

- `run_write_effect` (`src/write.rs:213`) verifies the passport, checks the idempotency key,
  resolves prior receipts (replay / different-payload refusal / dangling-unknown → no blind
  retry), writes the **`prepared`** gate fact, calls `exec.execute(EffectRequest{ args: payload,
  idempotency_key })` exactly once, then finalises the terminal receipt.
- The outcome→state map is FIXED in `run_write_effect` (`src/write.rs:313`): `Succeeded→Committed`,
  `Denied→Denied`, `Retryable→Retryable`, `PermanentFailure→PermanentFailure`,
  `UnknownExternalState→UnknownExternalState`.
- So a write executor is *just* a `CapabilityExecutor` that parses the typed intent, gates it, runs
  the transaction, and returns the right `EffectOutcome` — the `TBackendWriteExecutor`
  (`src/executors.rs:81`) pattern.

---

## Files

| File | Purpose |
|------|---------|
| `igniter-machine/src/postgres_write.rs` | `PostgresWriteIntent`, `PostgresWritePolicy`, `PostgresWriteAdapter` trait, `PostgresWriteResult`, `PostgresWriteExecutor<A>` (impl `CapabilityExecutor`), `FakePostgresWriteAdapter` + `FakeWriteBehavior` |
| `igniter-machine/tests/postgres_write_tests.rs` | 10 tests — all acceptance bullets |
| `igniter-machine/src/lib.rs` | `pub mod postgres_write;` |
| `lab-docs/lang/lab-machine-postgres-write-gate-p3-v0.md` | this doc |
| `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-WRITE-GATE-P3.md` | card + closing report |

---

## Public API (added)

```rust
pub struct PostgresWriteIntent { pub operation: String, pub target: String, pub key: String,
                                 pub values: Value, pub correlation_id: Option<String> }
impl PostgresWriteIntent { pub fn from_args(args: &Value) -> Result<PostgresWriteIntent, String> }

pub struct PostgresWritePolicy { /* allowed_targets, allowed_ops */ }
impl PostgresWritePolicy { pub fn new() -> Self; pub fn allow_target(self, &str) -> Self;
                           pub fn allow_ops(self, &[&str]) -> Self }

pub enum PostgresWriteResult { Committed, DuplicateKey, Denied(String),
                               ConstraintViolation(String), SerializationFailure(String), Unknown(String) }

#[async_trait]
pub trait PostgresWriteAdapter: Send + Sync {
    async fn transact(&self, intent: &PostgresWriteIntent, idempotency_key: &str) -> PostgresWriteResult;
}

pub struct PostgresWriteExecutor<A: PostgresWriteAdapter> { /* capability_id, adapter, policy */ }
impl<A: PostgresWriteAdapter + 'static> CapabilityExecutor for PostgresWriteExecutor<A> { … }

pub enum FakeWriteBehavior { Commit, ConstraintViolation, SerializationFailure, Unknown, Denied }
pub struct FakePostgresWriteAdapter { /* business_rows + effect_receipts; attempts()/…_count() */ }
```

---

## The two idempotency layers

| Layer | Where | What it stops |
|---|---|---|
| **1 — machine receipt** | `run_write_effect` over `__receipts__` | same key + same payload → replay (executor not reached); same key + **different** payload → refuse before executor; dangling `prepared`/`unknown` → no blind retry |
| **2 — PG-side effect receipt** | `effect_receipts(idempotency_key)` inside the fake transaction | a second business mutation **even if the machine receipt is lost/absent** → `DuplicateKey`, no 2nd row |

The transaction is modelled atomically: the business row AND the `effect_receipts` upsert happen
together or not at all. Layer 2 is what makes "exactly once" survive a torn machine-side receipt.

## Outcome taxonomy (adapter → `EffectOutcome` → `WriteState`)

| Adapter result | EffectOutcome | WriteState | Mutation |
|---|---|---|---|
| `Committed` | succeeded | `Committed` | one business row + effect receipt |
| `DuplicateKey` | succeeded (`duplicate:true`) | `Committed` | none (replay of a prior landed effect) |
| `Denied(m)` | denied | `Denied` | none |
| `ConstraintViolation(m)` | permanent | `PermanentFailure` | none (rolled back) |
| `SerializationFailure(m)` | retryable | `Retryable` | none (rolled back, KNOWN no mutation) |
| `Unknown(m)` | unknown | `UnknownExternalState` | unknown — **P4 reconciles**, no blind retry |

Plus host-side **policy gates** before the adapter: disallowed `target` or `operation` → `Denied`
(adapter untouched). Raw SQL payload (`sql`/`raw_sql`/`query`) → `PermanentFailure`, structurally.

---

## Proof results (10/10, `cargo test --no-default-features --test postgres_write_tests`)

| Test | Proves |
|---|---|
| `commit_lifecycle_business_row_and_pg_receipt` | machine receipt `prepared`→`committed` (both facts present); business row + PG effect receipt written; receipt records correlation + idempotency key, no raw SQL |
| `raw_sql_payload_refused_structurally` | `{sql:…}` → `PermanentFailure`; adapter never called |
| `replay_same_key_same_payload_bypasses_adapter` | machine-receipt replay; adapter attempts stays 1 |
| `same_key_different_payload_refused_before_adapter` | different-payload refusal (machine layer); adapter not reached |
| `pg_side_dedup_blocks_second_mutation_when_machine_receipt_lost` | machine receipt LOST (fresh store) → executor reached twice (attempts 2) but PG-side dedup → **one** business row |
| `serialization_failure_is_retryable` | transient rolled-back → `Retryable`; no mutation |
| `unknown_is_unknown_with_no_blind_retry` | lost-after-send → `UnknownExternalState`; re-run sees the unknown receipt → no blind retry (attempts stays 1) |
| `constraint_violation_is_permanent` | constraint/type → `PermanentFailure`; no mutation |
| `adapter_denied_maps_to_denied` | DB-level privilege denial → `Denied` |
| `policy_gates_refuse_before_adapter` | disallowed target / op → `Denied`; adapter untouched |

Full suite green; no regression (postgres_write = +10). Module compiled with no new warnings.

---

## Boundary findings

- **No new write machinery.** `PostgresWriteExecutor` is *only* a `CapabilityExecutor`; the
  two-phase receipt, payload-digest idempotency, replay, different-payload refusal, and
  no-blind-retry all come from the existing `run_write_effect` — exactly the
  `TBackendWriteExecutor` story.
- **The two layers are genuinely independent.** The "machine receipt lost" test runs the SAME
  adapter against a FRESH receipts store; the machine layer no longer dedups, the executor IS
  reached again, yet the PG-side `effect_receipts` key still blocks the second mutation. That is
  the defence-in-depth the readiness packet specified.
- **`unknown` is left for reconcile.** v0 models lost-after-send as "recorded nothing, returns
  unknown, no blind retry"; the landed-but-unknown read-back is `LAB-MACHINE-POSTGRES-RECONCILE-P4`,
  not this card.
- **Receipt carries correlation + idempotency key, not raw SQL or values.** The executor result
  echoes `correlation_id`/`target`/`key` (no business `values`, no SQL); the machine receipt adds
  `payload_digest` (a digest, not the raw payload).

---

## Closed surfaces

| Surface | Status |
|---|---|
| Real Postgres / connection / pool | Closed — fake adapter only |
| DB driver dependency (`tokio-postgres`/`sqlx`/`diesel`) | Closed — none added |
| SQL execution / raw SQL from contract | Closed — refused structurally |
| Migrations | Closed |
| ORM inside `.ig` / VM / capsule | Closed — capsule gets no DB handle |
| `TBackend` impl for Postgres | Closed — separate deferred track |
| Reconcile loop for `unknown` | Closed — `LAB-MACHINE-POSTGRES-RECONCILE-P4` |
| Network / live / public API beyond this module | Closed |

---

## Next routes

- `LAB-MACHINE-POSTGRES-RECONCILE-P4` — exact reconcile of an `unknown` write via the in-transaction
  `effect_receipts(idempotency_key)` table (correlation-grade, read-back only), business-key
  fallback. Composes the existing `reconcile`/`correlation` modules with a fake PG resolver.
- Real local Postgres remains a later **opt-in dependency + human gate** (`tokio-postgres` + pool
  behind a `postgres` feature; `diesel` rejected — in-process ORM).

---

*LAB-ONLY. No canon claim. No language authority. Lab evidence does not by itself create canon.*
