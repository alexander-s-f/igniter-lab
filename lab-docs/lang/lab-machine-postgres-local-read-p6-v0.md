# LAB-MACHINE-POSTGRES-LOCAL-READ-P6: real local Postgres read adapter (opt-in feature)

**Track:** `lab-machine-postgres-local-read-p6-v0`
**Status:** CLOSED — implementation proof. **First REAL database adapter.** Opt-in `postgres`
feature; default build unchanged (fake-only, no driver). Read-only. Proven against a real local
Postgres (dev SparkCRM).
**Route:** first real-local slice authorized by `LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5`
(human gate opened — developer provided a local Postgres + dev SparkCRM databases for pressure).
**Authority:** No canon claim. No language authority. Lab evidence only. Local dev DB only — no
production/staging, no live vendor traffic.

---

## What was proved

The P2 read boundary now works against a **real** Postgres. `TokioPostgresReadAdapter` (over
`tokio-postgres`) implements the unchanged `PostgresReadAdapter` trait; the `PostgresReadExecutor`
gates and the `run_effect` receipt/idempotency/replay machinery are **identical** to the fake path —
only the adapter is real. Proven against the dev SparkCRM `companies` table (id/name/status), with
the **same observable contract** as the fake.

```text
QueryPlan (gated: source/op/field allowlist + row-limit clamp, BEFORE the adapter)
  → TokioPostgresReadAdapter.query()        [#[cfg(feature = "postgres")]]
      parameterized SQL: SELECT "<allowlisted cols>"::text FROM "<source>"
                         [WHERE "<col>"::text = $1 …] LIMIT <effective_limit>
      → tokio_postgres SELECT (read-only)
  → PostgresReadResult → EffectOutcome + receipt   (unchanged P2 path)
```

The fake adapter (P2) stays the always-on default-build contract; the real adapter is a drop-in
behind the feature, asserted to match.

---

## Verify-first

Before this card: no real Postgres adapter, no DB driver (P5 packet). The boundary read:

- `postgres_read::{PostgresReadAdapter (async query(plan, effective_limit) -> PostgresReadResult),
  PostgresReadExecutor<A>, QueryPlan, QueryFilter, PostgresReadResult, PostgresReadPolicy}` — the
  trait the real adapter implements; the executor's gates run before it.
- `Cargo.toml` `tls` opt-in feature — the precedent for the new `postgres` feature.

---

## Files

| File | Purpose |
|------|---------|
| `igniter-machine/Cargo.toml` | `tokio-postgres = { version = "0.7", optional = true }`; `postgres = ["dep:tokio-postgres"]` |
| `igniter-machine/src/postgres_real.rs` | `#[cfg(feature = "postgres")]` `TokioPostgresReadAdapter` (impl `PostgresReadAdapter`) + `connect(dsn)` + `query_count()` |
| `igniter-machine/src/lib.rs` | `#[cfg(feature = "postgres")] pub mod postgres_real;` |
| `igniter-machine/tests/postgres_real_read_tests.rs` | `#![cfg(feature = "postgres")]`, DSN-gated skip — 6 integration tests |
| `lab-docs/lang/lab-machine-postgres-local-read-p6-v0.md` | this doc |
| `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-LOCAL-READ-P6.md` | card + closing report |

---

## v0 SQL mapping (deliberately bounded)

The point of P6 is the **connector boundary**, not rich type mapping, so v0 is tight:

- **Explicit projection required** (no `SELECT *`).
- **Every projected column rendered `"<col>"::text`** → each value returns as TEXT → JSON string
  (or null). This sidesteps the full PG-type→JSON matrix; rich typing is a later slice.
- **Filters: `eq`-only**, value bound as `$1..$n`, the column cast `::text` for a uniform text
  compare. Any other operator → `query_error` (permanent) — never a silently-wrong query.
- **Identifiers come ONLY from the already-allowlisted plan** and are quoted (defence in depth).
  Values are NEVER interpolated — always bound parameters. Raw SQL from a contract is impossible
  (refused in `QueryPlan::from_args`).
- **`LIMIT` = the clamped `effective_limit`.**

**Outcome taxonomy:** rows/empty → Succeeded; DB error (SQLSTATE, `as_db_error().is_some()`) →
`QueryError` → PermanentFailure; connection/IO error → `Unavailable` → UnknownExternalState
(epistemic, never a false "not found").

---

## Feature & build discipline

- `postgres = ["dep:tokio-postgres"]`; **default build (`["ffi"]`) unchanged** — fake-only, no DB
  driver. The real module is `#[cfg(feature = "postgres")]`; the integration test is
  `#![cfg(feature = "postgres")]`.
- The fake P2/P3/P4 adapters stay in the default build (pure Rust) — the always-on behavioural
  contract.
- DSN comes from `IGNITER_PG_DSN` (a `SecretProvider`/env source); **never in code, receipts, or
  docs.** NoTls (local loopback); TLS is a later slice.

---

## Proof results

**Default build** (`cargo test --no-default-features`): **50 suites green, no regression**;
`postgres_real` excluded, no driver compiled.

**Integration** (`IGNITER_PG_DSN=… cargo test --no-default-features --features postgres --test
postgres_real_read_tests`) against dev SparkCRM `companies`: **6/6**. Without a DSN: **6 skip
cleanly** (no hard failure).

| Test | Proves (against the real DB) |
|---|---|
| `real_companies_select_returns_rows` | allowlisted SELECT → rows (id/name/status shape) + receipt; adapter queried once |
| `real_limit_clamp` | row_limit 2 + plan limit 100 → `effective_limit:2`, `row_limit_clamped:true`, ≤2 real rows |
| `real_eq_filter_subset` | `status = $1` ("active") → every returned row has `status:"active"` (parameter-bound, correct WHERE) |
| `real_gate_parity_refuses_before_adapter` | forbidden field (`balance`) + unknown source → `Denied`; real DB never queried (count 0) |
| `real_replay_bypasses_adapter` | replay same idempotency key → real DB queried exactly once |
| `real_db_error_is_permanent` | a non-existent allowlisted column → SQLSTATE 42703 → `PermanentFailure` (taxonomy parity) |

---

## Boundary findings

- **The fake was a faithful contract.** The real adapter dropped in behind the unchanged trait and
  matched the P2 observable behaviour (taxonomy, gates, clamp, replay) without touching the
  executor or `run_effect` — the boundary held.
- **Gates are real-DB-protective.** Forbidden field / unknown source are refused *before* any SQL
  is built, so an unapproved column or table never reaches the connection (proven: query count 0).
- **Parameterisation is enforced structurally.** Filter values are always bound (`$1`), identifiers
  always from the allowlist; the `eq`-subset test confirms the WHERE is correct and injection-free.
- **Honest v0 limits, named.** `::text` projection + `eq`-only filters are explicit v0 bounds; rich
  type mapping and a fuller predicate set are named follow-ons, not silent gaps.

---

## Closed surfaces

| Surface | Status |
|---|---|
| Writes / DDL / migrations | Closed — read-only SELECT |
| Production / staging DB | Closed — local dev only |
| Connection pool | Closed — single connection (pool = a later slice) |
| TLS to Postgres | Closed — NoTls loopback (TLS = later slice) |
| Rich PG-type → JSON mapping | Closed — `::text` v0 (named follow-on) |
| Non-`eq` filter predicates | Closed — `eq` v0 (named follow-on) |
| ORM in `.ig`/VM/capsule · Postgres-as-`TBackend` | Closed |
| Serving loop / ingress / wire-path | Unchanged |
| DSN/credentials in code/receipts/docs | Closed — env/SecretProvider reference only |

---

## Next routes

- `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P?` — thread `run_write_effect_atomic` into
  `ingress::handle_effect`/`serve_once_effect` (the P5 precondition before any real write over the
  concurrent wire). Pure in-process, no DB.
- `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P?` — real write transaction (`BEGIN … ON CONFLICT
  (idempotency_key) … COMMIT`) + `effect_receipts` table + real reconcile resolver, behind the
  feature, against a **dedicated test DB** (never the SparkCRM business tables).
- Follow-ons: `postgres-pool`, `postgres-tls`, rich type mapping, fuller filter predicates.

---

*LAB-ONLY. No canon claim. No language authority. Local dev DB only. Lab evidence does not by itself
create canon.*
