# LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1: Postgres connector + ORM boundary map

**Track:** `lab-machine-postgres-capability-readiness-p1-v0`
**Status:** CLOSED — readiness/design packet. **No code. No dependency. No live DB. No SQL executed.**
**Route:** LAB READINESS / boundary map + bounded next slice.
**Authority:** No canon claim. No language authority. Lab evidence only. Does not promote any
`.ig`/VM surface. Old Ruby framework surfaces are NOT authority here.

---

## 0. Verify-first (current truth, with citations)

Read first: `igniter-machine/IMPLEMENTED_SURFACE.md`, capstone `…-HARDENING-CAPSTONE-P25`,
`…-DEPLOYMENT-TOPOLOGY-P1`, `…-SERVICE-WIRE-EFFECT-MILESTONE`.

**Confirmed by reading the live code (`igniter-machine/src`, `tests`, `Cargo.toml`):**

- **There is NO Postgres connector and NO ORM layer today.** A whole-crate search for
  `postgres` / `Postgres` / `tokio-postgres` / `sqlx` / `diesel` / `orm` / `ORM` returns **zero**
  hits in `src/`, `tests/`, and `Cargo.toml`. The only `repository`-shaped strings are in prose,
  not types. `Cargo.toml` deps: `igniter_compiler`, `igniter_vm`, `igniter_tbackend_playground`
  (default-features off), `serde`/`serde_json`/`rmp-serde`, `futures`, `parking_lot`,
  `async-trait`, `tokio` (full), `chrono`, `uuid`, `blake3`, `crc32fast`; opt-in `magnus` (ffi),
  `ratatui`/`crossterm` (repl), `rustls`/`tokio-rustls`/`rustls-pemfile` (`tls`). **No database
  driver of any kind.**
- **The effect boundary is a trait, not a primitive.** `capability::CapabilityExecutor`
  (`src/capability.rs:98`) = `{ capability_id(&self) -> &str; async fn execute(&self, &EffectRequest) -> EffectOutcome }`.
  Outcomes are `OutcomeKind::{Succeeded, Denied, Retryable, PermanentFailure, UnknownExternalState}`
  (`src/capability.rs:30`). Effects route through `run_effect_core` → `run_effect_with_passport`
  → `run_effect` (`src/capability.rs:322–444`); a **receipt is written as a bitemporal fact** in
  the machine's own `TBackend` store `__receipts__`.
- **Receipt-gated write lifecycle exists and is real.** `write::run_write_effect`
  (`src/write.rs:213`) is two-phase: `prepared` gate (before executor) → `committed` / `denied`
  / `unknown_external_state` / `permanent_failure` / `retryable` / `aborted`
  (`WriteState`, `src/write.rs:35`). Idempotency binds capability + operation + authority +
  `payload_digest` (blake3, `src/write.rs:113`), where `FactWrite::to_payload` forces target
  identity (store+key+value+valid_time) into the digest. `single_flight::run_write_effect_atomic`
  (`src/single_flight.rs:47`) serialises same-key concurrency → exactly-one effect.
- **Unknown-write resolution exists.** `reconcile::reconcile_unknown_write`
  (`src/reconcile.rs:71`) reads the target back (`ReconcileResult::{ResolvedCommitted,
  ResolvedPermanentFailure, StillUnknown, NotApplicable}`); `correlation::CorrelationResolver`
  (`src/correlation.rs:42`) resolves by `correlation_id` (`Landed/NotFound/Unavailable`);
  `recovery::recover_dangling_*` (`src/recovery.rs:65,87`) sweeps dangling `prepared` after
  restart; `retry`/`retry_queue`/`orchestrator` provide bounded, host-driven retry over time.
  **None re-issue the effect.**
- **Real substrate executors already wrap a backend, read-only and write.**
  `executors::TBackendReadExecutor` (`src/executors.rs:27`) and `TBackendWriteExecutor`
  (`src/executors.rs:81`) implement `CapabilityExecutor` over a real `Arc<dyn TBackend>` — the
  proof that "a real external store behind the effect boundary" needs **no new primitive**.
- **A domain executor composes the substrate without new primitives.**
  `sparkcrm::SparkCrmExecutor` (`src/sparkcrm.rs:22`) is ONE struct implementing
  `CapabilityExecutor` (forward), `CompensatableExecutor` (cancel), and `CorrelationResolver`
  (status lookup) over `HttpCapabilityExecutor` (`src/http.rs:173`). **This is the exact shape a
  Postgres executor will take.**
- **A typed read vocabulary already exists and is proven (mocked).** The `ExecuteQuery` effect
  contract + `IO.StorageCapability` 6-gate (`igniter-view-engine/fixtures/.../*.ig`;
  `lab-execute-query-effect-contract-and-storage-capability-injection-v0.md`, CLOSED 57/57)
  proves: a contract emits a typed `QueryPlan` + an `IO.StorageCapability` authority object,
  the host applies a 6-gate sequence, returns typed `QueryResult` + `QueryExecutionReceipt`
  — **with no SQL, no DB, no ORM, no `TBackend`.** That doc explicitly states the ESCAPE→STORAGE
  promotion is the gated path for live storage execution. **Postgres read is that promotion.**
- **Secret/authority/TLS hardening is already host-side.** `SecretProvider` (`src/http.rs:96`)
  + `secrets::{Env,File,Layered}` (P22), signed `CapabilityPassport` (P21), and the
  `external_profile`/`require_https`/`allowed_hosts` discipline on the HTTP executor (P14) are
  all reusable for a Postgres connector.
- **Deployment constraint to honour:** exactly-one is an **in-process** lock — one effect-process
  per fact store (`…-DEPLOYMENT-TOPOLOGY-P1`). A Postgres write executor inherits this; it does
  not relax it.

**Conclusion of verify-first:** the substrate to host Postgres *already exists and is hardened*.
This packet does **not** propose new effect machinery — it maps Postgres onto the proven boundary
and scopes the smallest honest first slice.

---

## 1. The contour (what we are proposing)

```text
capsule / .ig contract
  emits a TYPED intent  (QueryPlan for read  |  WriteIntent for write)   — NO SQL, NO DB handle
        │
        ▼
service_loop::discover_effect_surface  →  resolve effect → capability → executor   (host)
        │
        ▼
PostgresReadExecutor | PostgresWriteExecutor   (host-side; holds the connection pool & secret)
        │  read: parameterised, allowlisted query template
        │  write: ONE SQL transaction (BEGIN … COMMIT)
        ▼
Postgres
        │
        ▼
receipt (machine __receipts__ spine)  +  idempotency (PG effect-receipt table)
  +  reconcile (correlation / business key)  +  observability (P23, FROM facts)
```

The contract side is unchanged from the proven `ExecuteQuery` shape. Everything new lives
**host-side, behind the `CapabilityExecutor` trait.**

---

## 2. Q1 — Connector boundary: `CapabilityExecutor`, `TBackend`, or both?

The card asks for a clear v0 decision. There are **two distinct readings**, and they have
different answers:

| Reading | What it means | v0 decision |
|---|---|---|
| **(A) Postgres as a domain/application database** reached by contracts that want to read/write business data | Postgres is an *external system of record*, semantically equivalent to SparkCRM (an external service the host talks to) | ✅ **v0 = `CapabilityExecutor` family** (`PostgresReadExecutor` + `PostgresWriteExecutor`). NO new primitive. Receipts stay in the machine's own fact store. |
| **(B) Postgres as the machine's own fact-store / receipt-spine backend** (i.e. an `impl TBackend` that persists bitemporal facts in Postgres instead of `MpkFileBackend`) | Postgres becomes the kernel's durability substrate — the receipt spine, single-flight gate, recovery sweep all run against it | ⛔ **NOT v0.** Explicitly deferred — named future seam (§7). This touches durability/atomicity guarantees (`MpkFileBackend` hardening P2/P3, exactly-one in-process gate) and is a much heavier, higher-risk change. |

**v0 connector boundary (locked):**

```text
Postgres v0 = host CapabilityExecutor + typed repository operations
            = the SparkCrmExecutor pattern, applied to a SQL database
NOT a TBackend implementation (fact-spine on Postgres = separate gated track)
NOT a new language primitive
NOT ActiveRecord inside the capsule
NOT arbitrary SQL from contract inputs
```

Rationale: `TBackend` is the *kernel's own* bitemporal fact substrate (it backs `__receipts__`,
`__retry_queue__`, coordination stores). An application's Postgres database is *external domain
state*, the same category as an HTTP service. Putting it behind `CapabilityExecutor` reuses the
entire proven receipt / idempotency / reconcile / authority / observability stack with zero new
mechanism, exactly as `SparkCrmExecutor` did.

---

## 3. Q2 — Read path (first safe shape)

**First safe read-only shape = typed repository operations / allowlisted query templates. Arbitrary
SQL from contracts is rejected structurally.**

- The contract emits a **typed `QueryPlan`** (the already-proven `ExecuteQuery` vocabulary:
  `source.table`, `projection`, `filters: Collection[FilterPredicate]`, `order`, `limit`,
  `metadata`) + an `IO.StorageCapability` authority object. It does **not** emit SQL text.
- `PostgresReadExecutor` (impl `CapabilityExecutor`) is the live promotion of the mocked
  `ExecuteQuery` simulator. It:
  1. applies the proven **6-gate sequence** (G1 source allowlist, G2 op allowlist, G3 read_allowed,
     G4 row-limit clamp, G5 include_all restriction, G6 execute) **before touching the DB**;
  2. maps the gated `QueryPlan` to a **host-owned, allowlisted, parameterised SQL template** — the
     table is resolved from `allowed_sources` (never interpolated from a contract string), filters
     bind as parameters (`$1, $2, …`), `limit` is the clamped `effective_limit`;
  3. runs **read-only** (no writes; `forbid_mutations`-style guard);
  4. returns a typed `QueryResult` (`rows` / `empty` / `denied` / `query_error` / `system_error`)
     + `QueryExecutionReceipt`.

**Outcome mapping (mirrors `TBackendReadExecutor`):**

| Postgres result | `OutcomeKind` / `QueryResult.kind` |
|---|---|
| rows returned | `Succeeded` / `rows` |
| zero rows | `Succeeded` / `empty` |
| gate denial (G1–G3) | `Denied` / `denied` (do not retry same plan) |
| malformed plan (G5) | `PermanentFailure` / `query_error` (fix plan, then retry) |
| connection / timeout / DB unavailable | `UnknownExternalState` / `system_error` (retry later) |
| permission denied by DB | `Denied` / `denied` |

**Read slice acceptance (for the next card):**
- [ ] Contract emits `QueryPlan` only; no SQL string crosses the boundary.
- [ ] 6 gates run before any query; denial-as-data preserved (no exceptions).
- [ ] Table/columns come from the capability allowlist; values are bound parameters.
- [ ] `effective_limit = min(plan.limit, cap.row_limit)` enforced server-side too (`LIMIT $n`).
- [ ] Read-only proven (a write op on the read executor is refused before execution).
- [ ] Receipt written; replay returns the receipt without re-querying.

---

## 4. Q3 — Write path (receipt-gated → SQL transaction)

**Receipt-gated write maps to a SQL transaction through the existing `run_write_effect` /
`run_write_effect_atomic` lifecycle. No new write machinery.**

- The contract emits a **typed `WriteIntent`** (named operation + bound params), never SQL.
- `PostgresWriteExecutor::execute` runs **ONE SQL transaction** (`BEGIN … COMMIT`) per effect.
- **Idempotency is enforced in TWO layers** (defence in depth):
  1. **Machine receipt** — the existing `__receipts__` spine + `single_flight` gate (idempotency
     key = capability + operation + authority + `payload_digest`). This is the primary gate; it
     prevents the executor running twice in-process.
  2. **Postgres-side dedup** — the executor's transaction also upserts a row into a dedicated
     **`effect_receipts` table inside Postgres** keyed by the idempotency key
     (`idempotency_key TEXT PRIMARY KEY`). A duplicate hits a **unique-violation**, which the
     executor treats as *already committed* (replay), so even if the machine receipt is lost the
     DB itself refuses the second mutation. This makes "exactly once" survive a torn machine-side
     receipt.

**Failure taxonomy (PG error → `EffectOutcome`):**

| Postgres condition | `WriteState` / `OutcomeKind` |
|---|---|
| transaction commits | `Committed` |
| unique-violation on the idempotency key | `Committed` (replay — effect already landed) |
| `serialization_failure` / `deadlock_detected` (40001/40P01) | `Retryable` (executor asserts no mutation persisted — txn rolled back) |
| check/constraint/foreign-key violation, type error, bad statement | `PermanentFailure` (do not retry) |
| `insufficient_privilege` | `Denied` |
| connection drop / statement timeout / lost-after-send | `UnknownExternalState` (NO blind retry → reconcile) |

The `Retryable`-with-no-mutation contract matches `EffectOutcome::retryable`'s existing invariant
(the executor must guarantee the txn rolled back before reporting `Retryable`).

**Write slice acceptance (for a later card):**
- [ ] One effect = one `BEGIN…COMMIT`.
- [ ] `prepared` receipt written before the executor runs.
- [ ] Same idempotency key + same payload → executor runs once; duplicate replays the receipt.
- [ ] Same key + different payload → refused before execution (digest mismatch).
- [ ] Connection-loss-after-send → `unknown` + NO blind retry (hands off to reconcile).
- [ ] PG-side `effect_receipts` unique constraint proven to block a second mutation.

---

## 5. Q4 — Reconcile: did an unknown SQL write land?

When a write returns `unknown_external_state` (connection lost after sending), we must determine
whether it landed **without re-issuing it**. Two mechanisms, in priority order:

1. **Primary — idempotency-keyed effect-receipt table (exact, P13/correlation-style).** Because
   the write transaction upserts into Postgres's own `effect_receipts(idempotency_key PRIMARY KEY,
   correlation_id, committed_at, …)` *inside the same transaction* as the business mutation, a
   read-back is an **exact lookup**: `SELECT 1 FROM effect_receipts WHERE idempotency_key = $1`.
   Present → `ResolvedCommitted`; absent → `ResolvedPermanentFailure`; DB unavailable →
   `StillUnknown`. Implement as a `CorrelationResolver` over Postgres → reuse
   `correlation::reconcile_unknown_by_correlation` unchanged.
2. **Fallback — business-key read-back (P7-style).** If a particular operation cannot carry the
   effect-receipt row, reconcile by the row's **business/primary key** via the read executor
   (`SELECT … WHERE <business_key> = $1`). Weaker (the same-value caveat that P13 closed for HTTP
   reapplies), so it is the fallback, not the default.

**Decision: prefer the in-transaction effect-receipt table (a "receipt table" in Postgres) over a
fuzzy business-key scan.** It gives exact, correlation-grade resolution and survives the machine
losing its own receipt. Never re-run the write to find out — read-back only.

---

## 6. Q5 — ORM meaning (and Q6 schema authority)

**"ORM" here = a host-side typed repository/adapter. It is NOT language authority and NOT a
runtime inside the capsule.**

- A `.ig` contract / capsule **never receives a DB handle, connection, pool, session, or cursor.**
  It declares a typed intent (a `QueryPlan` or `WriteIntent`) or uses a typed data-source *shape*.
  The capability passport gap (ESCAPE class) already enforces this: a contract that declares a
  storage effect cannot execute without host-side capability injection.
- The **repository/adapter is a set of Rust structs** (the `Postgres*Executor` family) that hold
  the `tokio-postgres`/`sqlx` pool and map typed Igniter values (`QueryResult` rows, records)
  ↔ SQL rows. Each named repository operation = **one allowlisted parameterised statement**. There
  is no generic "any object → any table" mapper, no lazy loading, no identity map, no
  ActiveRecord-style live object graph. "ORM" = the bounded value↔row mapping at the host edge.
- This is the same composition as `SparkCrmExecutor` (a typed adapter over a transport), just with
  SQL as the transport.

**Q6 — Schema authority.** Where table schemas live, ranked:

| Option | Verdict |
|---|---|
| Postgres introspection as *source of truth* (read `information_schema` at runtime) | ❌ not authority — drift-prone, makes the schema implicit |
| **Hand-written typed repository operations (Rust)** | ✅ **v0 authority** — explicit, reviewable, allowlisted |
| Boot-time introspection as **validation only** | ✅ recommended guardrail — assert declared columns/types match the live DB; **refuse to serve on drift** |
| Generated bindings (sqlx compile-time macros / build-time codegen) | 🔶 later option (needs a DB or offline cache at build) |

**Decision: v0 schema authority = hand-written typed repository config, with optional boot-time
introspection *validation* that refuses on mismatch.** The language does not learn the schema; the
host owns it.

---

## 7. Q7 — Migrations

**Out of scope for v0.** The machine assumes the schema already exists; the boot-time introspection
check (§6) is the guardrail against drift.

**Future seam (named, not built):** `LAB-MACHINE-POSTGRES-MIGRATIONS-*` — a host-side / operational
migration runner (e.g. `sqlx migrate`, `refinery`, or an external tool), applied **outside** the
capability path, **never** from a contract or capsule. Migrations are an operator action, like the
deployment-topology backup/restore commands; they are not effects and write no receipts.

---

## 8. Q8 — Transactions (v0 boundary)

**v0 transaction boundary = ONE effect ↔ ONE SQL transaction.**

- A single `PostgresWriteExecutor::execute` opens `BEGIN`, runs the operation's statements
  (which **may be multiple** — a real unit of work), and `COMMIT`s atomically. The whole thing is
  governed by **one** idempotency key and **one** machine receipt.
- **Multi-statement-within-one-effect: allowed** (that is the normal unit of work).
- **Multi-effect distributed transaction / saga across effects: NOT v0.** Cross-effect atomicity is
  already the domain of compensation (`compensation::run_compensation`, P12) — a committed effect is
  reversed by a compensating effect, not by a 2-phase-commit across the DB and other systems. v0
  does not introduce XA/2PC.

So: one receipt-gated effect = one atomic DB transaction (possibly multi-statement); anything
larger is composed at the orchestration layer via compensation, not a database-level distributed
transaction.

---

## 9. Q9 — Security & redaction

All reusable from existing hardening:

- **Secret source** = the existing `SecretProvider` (`Env`/`File`/`Layered`, P22). The Postgres
  connection string / password is a **`{{secret:NAME}}` reference**, resolved host-side at connect
  time, and **never** enters a fact, receipt, audit event, or result.
- **Connection allowlist** = host/port allowlist for the DB endpoint (mirrors HTTP
  `allowed_hosts`); **TLS to Postgres** (`sslmode=verify-full`) under the same external-profile
  discipline as P14 (cert-invalid = permanent/security failure, transient TLS = retryable).
- **Operation allowlist** = only declared, named repository operations are callable; there is no
  generic "run this SQL" entry point.
- **Parameterisation MANDATORY** = every value binds as a parameter (`$1, $2, …`). No string
  interpolation of contract-supplied values into SQL, ever. Table/column identifiers come from the
  capability allowlist, not from contract input. **Arbitrary SQL from contracts is structurally
  impossible** (contracts emit typed plans/intents, not text).
- **No raw SQL in the receipt.** The receipt records the **operation name + parameter digest +
  correlation id**, never the rendered SQL with literal values. Secret-bearing params and PII are
  redacted exactly as HTTP headers/bodies are today.

---

## 10. Q10 — Test strategy & recommended next slice

**Recommended order: fake adapter first → local Postgres behind an opt-in feature later. No live
DB in the next card.**

1. **Fake adapter (no DB, no dependency).** A `FakePostgresRepository` implementing
   `CapabilityExecutor`, scripted to return rows / empty / unique-violation / serialization-failure
   / connection-loss — exactly like `FakeWriteExecutor` (`src/write.rs:361`) and the fake HTTP
   transport. This proves the **gate sequence, outcome taxonomy, receipt, idempotency, and
   reconcile wiring** with **zero new dependencies**.
2. **Local Postgres behind an opt-in feature** (mirrors the `tls` feature gating real rustls).
   A `postgres` feature flag pulls the driver; a loopback-only, local-only slice proves a real
   connection — *separately authorized*, like the P11/P14 real-transport slices. **Not this card.**
3. **Live / production DB: human-gated**, same posture as the SparkCRM live gate (P25). Not an
   engineering continuation.

### Dependency choices & tradeoffs (listed, NOT added)

| Crate | Pros | Cons | Verdict for v0 |
|---|---|---|---|
| **none (fake adapter)** | zero risk, proves the whole boundary | not a real connection | ✅ **next slice** |
| `tokio-postgres` (+ `deadpool-postgres` / `bb8` pool) | async, minimal, explicit parameterisation, matches the hand-rolled-transport style of `http.rs`; no build-time DB | manual row mapping; pooling is a second crate | ✅ **recommended** when the real slice is authorized |
| `sqlx` | compile-time-checked queries, built-in pool, built-in migrations | needs `DATABASE_URL` at build or an offline query cache; heavier | 🔶 alternative if compile-time query checking is wanted |
| `diesel` | mature, full query DSL | **synchronous by default; it IS an in-process ORM** — contradicts the stance (no ORM-in-runtime) | ❌ rejected |

**Recommendation:** keep the next card dependency-free (fake adapter). When a real connection is
authorized, prefer `tokio-postgres` + a pool crate behind an opt-in `postgres` feature.

---

## 11. Required stance (restated)

The language / VM stays pure. A `.ig` contract may declare a storage intent or use a typed data
source; it must **not** hold a Postgres connection, run arbitrary SQL, or become an ORM runtime.
The connection, pool, secret, SQL templates, and value↔row mapping all live **host-side behind the
`CapabilityExecutor` trait** — the proven boundary, no new primitive.

---

## 12. Next implementation card (bounded)

**`LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2` — fake-adapter read executor.**

Scope (tight):
- Implement `PostgresReadExecutor : CapabilityExecutor` over a **fake** scripted repository
  (no `tokio-postgres`, no DB, no new dependency).
- Drive it with the **existing** `QueryPlan` / `IO.StorageCapability` / 6-gate vocabulary
  (promote the mocked `ExecuteQuery` simulator to run through `run_service` / the capability
  boundary instead of a Ruby sim).
- Prove: gate sequence before query, outcome taxonomy (rows/empty/denied/query_error/system_error),
  receipt-as-fact, replay bypasses the executor, read-only refuses a write op.
- Closed: no real DB, no write path, no SQL string from a contract, no migration, no new dep.

Then, in order: `LAB-MACHINE-POSTGRES-WRITE-GATE-P3` (receipt-gated write + PG-side `effect_receipts`
dedup, still fake) → `LAB-MACHINE-POSTGRES-RECONCILE-P4` (correlation/business-key reconcile, fake)
→ (human-gated) real local Postgres behind a `postgres` feature.

Deferred seams (named, not v0): `LAB-MACHINE-POSTGRES-MIGRATIONS-*` (operational migration runner);
**Postgres-as-`TBackend`** (fact-spine persistence on Postgres) — a separate, heavier track that
touches durability/atomicity guarantees and is **not** the connector this packet scopes.

---

## 13. Acceptance map (this card)

- [x] Verify-first cites current files and confirms **no existing Postgres/ORM surface** (§0).
- [x] v0 connector boundary defined: **`CapabilityExecutor`**, with the `TBackend` reading
      explicitly split out and deferred (§2).
- [x] Read-only first slice **and** write slice, each with acceptance (§3, §4).
- [x] Unknown/reconcile strategy for SQL writes defined (in-transaction effect-receipt table,
      correlation-grade; business-key fallback) (§5).
- [x] ORM/repository semantics defined; ORM kept out of contracts/VM (§6).
- [x] Dependency choices + tradeoffs listed without adding any (§10).
- [x] Security & redaction rules stated (§9).
- [x] Next implementation card named with bounded scope (§12).
- [x] No code changes (this doc + card closing report only).

---

## Closed surfaces (this card)

- No new dependencies (none added to `Cargo.toml`).
- No live database, no Docker/Postgres process, no network, no SQL executed.
- No migration runner.
- No ORM inside `.ig`, the VM, or capsule activation.
- No changes to capability-IO semantics or any `src/` file.
- No Postgres-as-`TBackend` (fact-spine) work — deferred, named seam only.

---

*LAB-ONLY. No canon claim. No language authority. Old Ruby framework surfaces are not authority.
Lab evidence does not by itself create canon.*
