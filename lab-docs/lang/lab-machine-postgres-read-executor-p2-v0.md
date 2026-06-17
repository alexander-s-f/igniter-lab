# LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2: fake-adapter Postgres read executor

**Track:** `lab-machine-postgres-read-executor-p2-v0`
**Status:** CLOSED — implementation proof. **Fake adapter only. No DB, no SQL, no network, no new dependency.**
**Route:** LAB implementation slice from `LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1`.
**Authority:** No canon claim. No language authority. Lab evidence only. Old Ruby framework
surfaces are not authority.

---

## What was proved

The **first Postgres-shaped read capability** exists in `igniter-machine`, implemented as a host
`CapabilityExecutor`, with all safety gates enforced **before** the adapter is touched — and it
rides the existing capability machinery (authority, idempotency, receipt-as-fact, replay) with
**no new primitive**. There is still **no real database**: the adapter is an in-memory fake.

```text
EffectRequest.args = typed QueryPlan (NO SQL string, NO DB handle)
  → PostgresReadExecutor : CapabilityExecutor
       gates (all BEFORE the adapter):
         raw-SQL refusal · source allowlist · read-only(mutation refusal)
         · op allowlist · field allowlist · row-limit clamp
  → PostgresReadAdapter  (fake: in-memory table map; NO SQL executed)
  → EffectOutcome + receipt via run_effect  (replay bypasses the adapter)
```

This is the live promotion of the *shape* proven (mocked) by `LAB-EXECUTE-QUERY-P1`
(`ExecuteQuery` + `IO.StorageCapability`): a contract emits a typed plan; the host owns the gates
and (eventually) the SQL template. The contract never sees SQL, a connection, a pool, or a cursor.

---

## Verify-first

Before this card there was **no Postgres connector** in the crate (whole-crate search for
`postgres`/`sql`/`sqlx`/`tokio-postgres`/`diesel` = zero hits, recorded in the P1 readiness
packet). The capability boundary read for this slice:

- `capability::CapabilityExecutor` = `{ capability_id(&self) -> &str; async fn execute(&self, &EffectRequest) -> EffectOutcome }` (`src/capability.rs:98`).
- `EffectOutcome` constructors `succeeded/denied/unknown/permanent/retryable`; `OutcomeKind`
  taxonomy (`src/capability.rs:30,66`).
- `run_effect` / `run_effect_core` give idempotency (receipt lookup) + replay (executor bypass)
  for free (`src/capability.rs:322,436`); receipt is a bitemporal fact in `__receipts__`.
- `executors::TBackendReadExecutor` (`src/executors.rs:27`) = the structural template (wrap a
  real port as a `CapabilityExecutor`, count calls for the idempotency proof).
- `sparkcrm::SparkCrmExecutor` (`src/sparkcrm.rs:22`) = the domain-executor composition pattern.

---

## Files

| File | Purpose |
|------|---------|
| `igniter-machine/src/postgres_read.rs` | `QueryPlan`/`QueryFilter`, `PostgresReadPolicy`, `PostgresReadAdapter` trait, `PostgresReadResult`, `PostgresReadExecutor<A>` (impl `CapabilityExecutor`), `FakePostgresAdapter` |
| `igniter-machine/tests/postgres_read_tests.rs` | 9 tests — all acceptance bullets |
| `igniter-machine/src/lib.rs` | `pub mod postgres_read;` |
| `lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md` | this doc |
| `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2.md` | card + closing report |

---

## Public API (added)

```rust
pub struct QueryFilter { pub field: String, pub op: String, pub value: Value }
pub struct QueryPlan   { pub source: String, pub op: String, pub projection: Vec<String>,
                         pub filters: Vec<QueryFilter>, pub limit: Option<i64> }
impl QueryPlan { pub fn from_args(args: &Value) -> Result<QueryPlan, String> }

pub struct PostgresReadPolicy { /* allowed_sources, allowed_ops, allowed_fields, row_limit */ }
impl PostgresReadPolicy {
    pub fn new(row_limit: i64) -> Self;
    pub fn allow_source(self, source: &str, fields: &[&str]) -> Self;
    pub fn allow_ops(self, ops: &[&str]) -> Self;
}

pub enum PostgresReadResult { Rows(Vec<Value>), Unavailable(String), Transient(String), QueryError(String) }

#[async_trait]
pub trait PostgresReadAdapter: Send + Sync {
    async fn query(&self, plan: &QueryPlan, effective_limit: i64) -> PostgresReadResult;
}

pub struct PostgresReadExecutor<A: PostgresReadAdapter> { /* capability_id, adapter, policy */ }
impl<A: PostgresReadAdapter + 'static> CapabilityExecutor for PostgresReadExecutor<A> { … }

pub struct FakePostgresAdapter { /* in-memory; query_count() */ }
```

---

## Gate sequence (all BEFORE the adapter)

| Order | Gate | Refusal | Adapter called? |
|---|---|---|---|
| 0 | raw-SQL refusal (`sql`/`raw_sql`/`query` key present) | `PermanentFailure` | no |
| 0 | plan parse (`source` required) | `PermanentFailure` "malformed query plan" | no |
| G1 | source ∈ `allowed_sources` | `Denied` "source not allowed" | no |
| — | read-only: mutating op (`insert/update/delete/…`) | `Denied` "read-only: mutation refused" | no |
| G2 | op ∈ `allowed_ops` | `Denied` "op not allowed" | no |
| G3 | projection + filter fields ⊆ `allowed_fields[source]` | `Denied` "forbidden field: …" | no |
| G4 | row-limit **clamp** (`effective = min(requested, row_limit)`) | **NOT a denial** | yes |

**Outcome taxonomy at the adapter:** `Rows`→`Succeeded` (`kind:"rows"`/`"empty"`),
`Unavailable`→`UnknownExternalState` (epistemic, no blind retry), `Transient`→`Retryable`
(adapter knows nothing partial happened), `QueryError`→`PermanentFailure`.

Result/receipt payload: `{ kind, source, rows, count, effective_limit, row_limit_clamped }`.

---

## Proof results (9/9, `cargo test --no-default-features --test postgres_read_tests`)

| Test | Proves |
|---|---|
| `allowlisted_source_succeeds_and_returns_rows` | impl `CapabilityExecutor`; allowlisted source → rows; projection-shaped; receipt written; adapter called once |
| `empty_result_is_success_empty` | empty → `Succeeded`/`kind:"empty"`, NOT a failure |
| `raw_sql_input_refused_structurally` | `{sql:…}` → `PermanentFailure`; adapter never called |
| `unknown_source_refused_before_adapter` | unknown source → `Denied`; adapter count 0 |
| `forbidden_field_refused_before_adapter` | forbidden projection AND filter field → `Denied`; adapter count 0 |
| `mutation_attempt_refused_before_adapter` | `op:"update"` → `Denied` read-only; adapter count 0 |
| `row_limit_clamped_and_reflected` | clamp reflected in result AND persisted receipt; only clamped rows returned |
| `adapter_unavailable_maps_to_unknown_and_transient_to_retryable` | `Unavailable`→unknown; `Transient`→retryable |
| `replay_same_key_bypasses_adapter` | replay returns receipt result; adapter count stays 1 |

Full suite green; no regression (postgres_read = +9; rest unchanged). Mod compiled with no new
warnings.

---

## Boundary findings

- **The boundary composes with zero new primitives.** `PostgresReadExecutor` is *only* a
  `CapabilityExecutor`; idempotency, receipts, replay, and authority all come from the existing
  `run_effect` path — exactly the `SparkCrmExecutor`/`TBackendReadExecutor` story.
- **Gates run in the executor body, before the single adapter call.** Because `run_effect_core`
  invokes the executor only on a live first call, replay never re-enters `execute`, so the adapter
  count is the clean idempotency witness.
- **v0 does NOT evaluate filter predicates.** The fake adapter applies projection-shaping
  (pure shaping) and the clamped limit, but treats filter values as bound parameters it does not
  evaluate. Predicate evaluation is a separate named slice (`LAB-FILTER-EVAL-P1`), kept out so this
  card proves only the connector boundary.
- **Schema authority is host config.** `PostgresReadPolicy` (allowed sources/ops/fields/row_limit)
  is hand-written host config — not contract input, not live introspection. Matches the P1 stance.

---

## Closed surfaces

| Surface | Status |
|---|---|
| Real Postgres / connection / pool | Closed — fake adapter only |
| DB driver dependency (`tokio-postgres`/`sqlx`/`diesel`) | Closed — none added |
| SQL execution / raw SQL from contract | Closed — refused structurally |
| Writes / mutations | Closed — refused before adapter (read-only) |
| Filter predicate evaluation | Closed — `LAB-FILTER-EVAL-P1` (separate) |
| Migrations | Closed |
| ORM inside `.ig` / VM / capsule | Closed — capsule gets no DB handle |
| `TBackend` impl for Postgres | Closed — separate deferred track |
| Network / live / public API beyond this module | Closed |

---

## Next routes

- `LAB-MACHINE-POSTGRES-WRITE-GATE-P3` — receipt-gated SQL write design/proof (still fake):
  `run_write_effect`/`run_write_effect_atomic` → one transaction; PG-side `effect_receipts`
  (idempotency_key PK) dedup; full PG-error→`EffectOutcome` taxonomy.
- `LAB-MACHINE-POSTGRES-RECONCILE-P4` — exact reconcile via the in-transaction effect-receipt
  table (correlation-grade), business-key fallback.
- Real local Postgres remains a later **opt-in dependency + human gate** (recommend
  `tokio-postgres` + a pool crate behind a `postgres` feature; `diesel` rejected — it is an
  in-process ORM).

---

*LAB-ONLY. No canon claim. No language authority. Lab evidence does not by itself create canon.*
