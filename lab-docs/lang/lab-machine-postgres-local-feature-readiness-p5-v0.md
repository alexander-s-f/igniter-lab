# LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5: real local Postgres feature gate

**Track:** `lab-machine-postgres-local-feature-readiness-p5-v0`
**Status:** CLOSED — formal readiness/decision packet. **No code. No `Cargo.toml` edit. No driver.
No DB connection. No Docker/server start. No credentials.**
**Route:** formal gate before any real local Postgres implementation.
**Authority:** No canon claim. No language authority. Lab evidence only. This packet is a decision
input for a human gate; it grants no implementation by itself.

---

## 0. Purpose

The fake-adapter Postgres wave (P2 read / P3 write gate / P4 reconcile) proved the *boundary and
behaviour* with no database. This packet answers **whether and how** to open a **real local**
Postgres implementation behind an opt-in feature — and exists specifically to stop a background
agent from casually adding `tokio-postgres`/Docker/DSN handling without an explicit decision.

It is **not** an implementation card. It produces: answers to 11 questions, the smallest first
real-local slice, an exact dependency/feature proposal, the DSN/secret names (no values), the
schema/migration boundary, the wire-path atomicity decision, the fake-vs-integration test split,
and a decision-ready summary.

---

## 1. Verify-first (current truth)

The three fake surfaces are live and green (default build, `cargo test --no-default-features`):

- **Read** — `postgres_read::{PostgresReadExecutor<A>, PostgresReadAdapter, PostgresReadResult,
  QueryPlan, QueryFilter, PostgresReadPolicy, FakePostgresAdapter}` (9 tests). Gates (raw-SQL
  refusal · source/op/field allowlist · row-limit clamp) run BEFORE the adapter; outcome taxonomy
  rows/empty→Succeeded, unavailable→Unknown, transient→Retryable, query-error→Permanent.
- **Write** — `postgres_write::{PostgresWriteExecutor<A>, PostgresWriteAdapter, PostgresWriteResult,
  PostgresWriteIntent, PostgresWritePolicy, FakePostgresWriteAdapter}` (10 tests). Driven by the
  EXISTING `write::run_write_effect` two-phase receipt; two idempotency layers (machine `__receipts__`
  + fake PG-side `effect_receipts(idempotency_key)`).
- **Reconcile** — `postgres_write::{reconcile_postgres_unknown_write, PostgresWriteReceiptResolver,
  PostgresReceiptLookup, PostgresReconcileResult}` (7 tests). READ-ONLY lookup by idempotency
  identity; found→committed / not-found→permanent_failure / unavailable→still-unknown; never
  re-runs the executor.

**Confirmed: no real Postgres adapter exists.** No `tokio-postgres`/`sqlx`/`diesel` in `Cargo.toml`
(`[dependencies]` has serde/tokio/blake3/chrono/uuid/…; opt-in `tls` pulls rustls). No DB driver.

Two load-bearing facts read from live code for this packet:

- **Wire path is NOT atomic-gated.** `ingress::handle_effect` (`src/ingress.rs:253`) and
  `serve_once_effect` (`src/ingress.rs:602`) perform the effect via **plain
  `run_write_effect`** (`src/ingress.rs:344`); `EffectBridgeConfig` carries no `single_flight`.
  Only `bridge_effect::ServiceEffectBridge` (`src/bridge_effect.rs:93`) uses
  `run_write_effect_atomic` (P18). → The wire path has the **sequential-idempotency** behaviour;
  exactly-one under concurrent same-key duplicates is NOT guaranteed there yet. (This is the P13
  wire-path caveat — see Q9.)
- **`tls` is the opt-in-feature precedent.** `[features] default = ["ffi"]; tls = ["dep:rustls",
  "dep:tokio-rustls", "dep:rustls-pemfile"]`. A `postgres` feature follows this shape exactly; the
  default build stays DB-dependency-free and fake-only. The `tls` integration tests are also the
  precedent for **offline-precheck / opt-in** integration tests.
- **Secret source is ready.** `secrets::{EnvSecretProvider (allowlist `allow(name, env_key)`),
  FileSecretProvider (traversal-safe root), LayeredSecretProvider}` all impl `http::SecretProvider`
  (`resolve(&str) -> Option<String>`). A DSN is just another named secret.

---

## 2. The 11 questions

### Q1 — Dependency choice

| Crate | Verdict |
|---|---|
| **`tokio-postgres` (0.7)** | ✅ **v0.** Async, explicit `$1..$n` parameterisation, no build-time DB, matches the hand-rolled-transport style of `http.rs`. |
| `deadpool-postgres` (pool) | 🔶 add **only at the write/concurrency slice**, not the first read slice (a single connection is enough to prove the read boundary). |
| `tokio-postgres-rustls` (TLS) | 🔶 later — reuse the existing rustls stack; local loopback first slice may use `sslmode=disable` (dev-only), TLS is a P14-style follow-on. |
| `sqlx` | ❌ build-time `DATABASE_URL` / offline query cache couples the build to a DB and adds CI friction. |
| `diesel` | ❌ synchronous and it **is** an in-process ORM — contradicts the stance. |

**v0 = `tokio-postgres` only** (single connection) for the first real slice; add `deadpool-postgres`
when serving concurrent writes; TLS later.

### Q2 — Feature shape

Add one opt-in Cargo feature (mirrors `tls`):

```toml
# PROPOSAL (not applied in this card):
postgres = ["dep:tokio-postgres"]                 # first read slice
# later:  postgres-pool = ["postgres", "dep:deadpool-postgres"]
#         postgres-tls  = ["postgres", "dep:tokio-postgres-rustls", "tls"]
```

- **Default build unchanged** (`["ffi"]`) — DB-dependency-free, fake-only.
- The **fake adapters (P2/P3/P4) stay in the default build** (pure Rust, no deps) — they are the
  always-on behavioural contract.
- Real adapter code is `#[cfg(feature = "postgres")]`; integration tests are
  `#![cfg(feature = "postgres")]` and additionally **skip when no DSN is present**.

### Q3 — Local server source

| Environment | Policy |
|---|---|
| Developer machine | A **human-provided local Postgres** (already running) reached by a DSN from a `SecretProvider`. If the DSN secret is absent → integration tests **skip** (no hard failure), exactly the `tls` offline-precheck pattern. |
| CI | **Default CI stays fake-only.** A **separate, opt-in CI job** may run integration tests against a CI **service container** (`services: postgres`), gated on the `postgres` feature. |
| Forbidden | The test process starting Docker, downloading/embedding a server, or connecting to any **non-local** host. No `embedded-postgres`-style vendored-server crate. |

### Q4 — Secret / DSN handling

- DSN/credentials resolved via the existing `SecretProvider` (Env allowlist / File / Layered).
- **Proposed secret name (no value):** a single logical `pg.dsn` (e.g. `EnvSecretProvider::new()
  .allow("pg.dsn", "IGNITER_PG_DSN")`), or a split set `pg.host/pg.port/pg.user/pg.password/pg.db`.
  Recommend the single `pg.dsn`.
- The DSN/password is a **`{{secret:pg.dsn}}` reference** — never in a contract, receipt, audit,
  result, log, or doc. The connection password never enters a fact (existing P22 redaction
  discipline). **This packet states names only — no values.**

### Q5 — Schema ownership

- **`effect_receipts` table and any business test tables are host-owned and created out-of-band**
  (operator / fixture DDL in the **test harness setup**), NOT by the executor at runtime and NOT by
  a contract. For the first integration slice, a tiny `CREATE TABLE IF NOT EXISTS` run by **test
  setup** (not by the executor path) is acceptable and explicitly test-only.
- **Migrations are out of scope** for the first slices — named future seam
  `LAB-MACHINE-POSTGRES-MIGRATIONS-*`. No migration runner in the executor path.
- **Schema authority = hand-written host config** (`PostgresReadPolicy`/`PostgresWritePolicy`), not
  live introspection-as-truth. Boot-time introspection **validation** (assert declared columns/types
  match; refuse on drift) is a deferred guardrail.

### Q6 — Read adapter mapping (`QueryPlan` → parameterised SQL)

- The 6 gates already run in `PostgresReadExecutor::execute` BEFORE the adapter, so the real
  `query()` receives an **already-gated** plan. It builds
  `SELECT <allowlisted projected cols> FROM <allowlisted source> WHERE <col> = $1 … LIMIT
  <effective_limit>`.
- **Identifiers come ONLY from the allowlist** (`PostgresReadPolicy.allowed_sources / allowed_fields`),
  never interpolated from contract strings; **all values bind as `$1..$n`**. Raw SQL from contracts
  is already structurally impossible (`QueryPlan::from_args` refuses `sql`/`raw_sql`/`query`).
- **New work vs the fake:** the fake did NOT evaluate filter predicates; the real adapter must turn
  `QueryFilter{field,op,value}` into a real parameterised `WHERE`. The set of supported operators is
  a bounded allowlist (`eq`/`lt`/`gt`/`in`/…), named as `LAB-MACHINE-POSTGRES-FILTER-PREDICATES-*`
  (overlaps the previously-named `LAB-FILTER-EVAL-P1`); the first read slice may support only `eq`.

### Q7 — Write adapter mapping (one effect = one transaction)

One effect = one transaction:

```sql
BEGIN;
  <business upsert on the allowlisted target, values bound $1..$n>;
  INSERT INTO effect_receipts (idempotency_key, correlation_id, target, key, committed_at)
    VALUES ($1, $2, $3, $4, now())
    ON CONFLICT (idempotency_key) DO NOTHING;   -- PG-side second idempotency layer
COMMIT;
```

- `ON CONFLICT (idempotency_key) DO NOTHING` + rows-affected gives the P3 **`DuplicateKey`** result
  (no second business mutation). PG error → `PostgresWriteResult` mapping is exactly the P3 taxonomy:
  unique_violation on the idempotency PK → `DuplicateKey`; `serialization_failure`/`deadlock_detected`
  → `SerializationFailure` (retryable, txn rolled back); check/fk/type → `ConstraintViolation`
  (permanent); `insufficient_privilege` → `Denied`; connection lost after send → `Unknown`.
- The executor runs UNDER the unchanged `run_write_effect` (machine receipt gate); the real adapter
  only replaces `transact`.

### Q8 — Reconcile mapping

- `reconcile_postgres_unknown_write` and its `PostgresWriteReceiptResolver` trait are unchanged. The
  real resolver's `lookup_effect_receipt(idempotency_key)` =
  `SELECT correlation_id, target, key FROM effect_receipts WHERE idempotency_key = $1` → row →
  `Found` / no row → `NotFound` / connection error → `Unavailable`.
- **Read-only (SELECT only); never re-runs the write.** Preserves P4 semantics exactly (same trait,
  same result enum). Keyed by the idempotency PK → same-value false positive impossible.

### Q9 — Atomicity precondition (load-bearing)

**Finding (verified):** the wire path (`ingress::handle_effect` / `serve_once_effect`) uses plain
`run_write_effect`; only `bridge_effect::ServiceEffectBridge` uses `run_write_effect_atomic` (P18).

- For **fake** executors, a double-execution under concurrent same-key wire requests is harmless
  (no real external mutation).
- For a **real Postgres WRITE served over the concurrent wire path**, plain `run_write_effect`
  reintroduces the P18 gap: two concurrent same-key requests can both read no-receipt → both prepare
  → both execute. The PG-side `ON CONFLICT` mitigates the *business row*, but the machine still does
  two prepares and the executor runs twice (any non-idempotent work beyond the unique key could
  double).

**DECISION (gate):** thread `run_write_effect_atomic` (the P18 single-flight) into the wire
`handle_effect`/`serve_once_effect` path **before** serving a real Postgres write over the concurrent
wire — a dedicated card `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P?` (pure in-process, fake-executor proof,
no DB). The real **read** slice does NOT need this (reads are idempotent). So: **real read → wire-atomic
gate → real write.**

### Q10 — Test matrix (fake/unit vs opt-in integration)

| Tier | Build | Runs when | Contents |
|---|---|---|---|
| **Durable fake/unit** | default (`--no-default-features`) | always | the existing P2/P3/P4 fake tests — the behavioural contract (read taxonomy, write two-layer idempotency, reconcile identity/no-re-exec). |
| **Opt-in integration** | `--features postgres` | DSN secret present (else **skip**) | real read (rows/empty/denied-gate/limit-clamp); real write (commit/ON-CONFLICT-duplicate/constraint/serialization/denied); real reconcile (found/not-found/unavailable); failure taxonomy (connection drop → unknown). |

The integration tests assert the **same observable contract** as the fakes (parity) → the real
adapter is a drop-in behind the existing traits.

### Q11 — Closed surfaces (explicitly NOT authorised)

Production DB · staging DB · public ingress · ORM in `.ig`/VM/capsule · Postgres-as-`TBackend`
(fact-spine) · live vendor traffic · migration runner in the executor path · Docker auto-start by
tests · embedded/vendored server crate · secrets in docs/receipts/logs.

---

## 3. Recommended implementation sequence (smallest first)

1. **`LAB-MACHINE-POSTGRES-LOCAL-READ-P6`** — real read adapter (`tokio-postgres`, single
   connection) behind the `postgres` feature; opt-in integration test gated on `pg.dsn`; `eq`-only
   filters to start. **No atomicity needed** (reads idempotent). *Smallest first real-local slice.*
2. **`LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P?`** — thread `run_write_effect_atomic` into
   `ingress::handle_effect`/`serve_once_effect`. Pure in-process, fake-executor proof, no DB.
   **Precondition for any real write over the concurrent wire.**
3. **`LAB-MACHINE-POSTGRES-LOCAL-WRITE-P?`** — real write transaction (`BEGIN … ON CONFLICT …
   COMMIT`) + `effect_receipts` table + real reconcile resolver, behind the feature (and
   `postgres-pool` if concurrent).
4. Deferred seams: `…-POSTGRES-FILTER-PREDICATES-*`, `…-POSTGRES-MIGRATIONS-*`, `postgres-tls`,
   boot-time introspection validation. Real production/staging stays a separate human gate.

---

## 4. Decision-ready summary

| Decision | Recommendation |
|---|---|
| Open a real local adapter? | **Yes, gated** — behind an opt-in `postgres` feature; default build stays fake-only and DB-dependency-free. |
| Dependency | `tokio-postgres` only for the first read slice; `deadpool-postgres` at the write/concurrency slice; TLS later. **Not** `sqlx`/`diesel`. |
| First slice | **Real local READ** (`LAB-MACHINE-POSTGRES-LOCAL-READ-P6`), `eq`-only, DSN-gated opt-in test. |
| Hard precondition before any real WRITE over the wire | **Wire-path atomic gate** (`run_write_effect_atomic` in `handle_effect`) — a dedicated card, no DB. |
| DSN/secret | A single named secret `pg.dsn` via `SecretProvider`; value never in contract/receipt/doc. |
| Schema/migrations | Host-owned, fixture-DDL in test setup; migrations out of scope (named seam); schema authority = host policy config. |
| What this card authorises | **Nothing to implement.** It is the human-gate input. Each next slice needs its own card. |

---

## Closed surfaces (this card)

- No `Cargo.toml` edit; no `tokio-postgres`/`sqlx`/`diesel`/pool/Docker/migration added.
- No database connection, no credentials created or read.
- No ORM, no Postgres-as-`TBackend`.
- No change to serving loop / ingress / wire-path behaviour (the atomicity item is a *named next
  card*, not done here).
- No code at all — design/decision packet only.

---

*LAB-ONLY. No canon claim. No language authority. Decision input for a human gate; grants no
implementation by itself.*
