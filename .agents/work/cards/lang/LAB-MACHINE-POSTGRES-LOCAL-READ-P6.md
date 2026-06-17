# Card: LAB-MACHINE-POSTGRES-LOCAL-READ-P6 — real local Postgres read adapter (opt-in feature)

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol  
**Status: CLOSED 2026-06-17 — implementation proof complete (6/6 against real DB).** First
real-local slice authorized by `LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5` (human gate opened:
developer provided a local Postgres + dev SparkCRM databases for pressure).

## Closing report (2026-06-17)

Doc: [`lab-docs/lang/lab-machine-postgres-local-read-p6-v0.md`](../../../../lab-docs/lang/lab-machine-postgres-local-read-p6-v0.md).

**First REAL database adapter.** Added `tokio-postgres` as an **optional** dep behind a new opt-in
`postgres` feature (default build unchanged — fake-only, no driver), `src/postgres_real.rs`
(`#[cfg(feature="postgres")]` `TokioPostgresReadAdapter` impl `PostgresReadAdapter`), and
`tests/postgres_real_read_tests.rs` (`#![cfg(feature="postgres")]`, DSN-gated skip). The
`PostgresReadExecutor` gates and the `run_effect` machinery are UNCHANGED — only the adapter is
real, a drop-in behind the trait.

v0 SQL mapping (bounded, named): explicit projection required; columns rendered `"<col>"::text`;
`eq`-only filters bound as `$1..$n` with `::text` compare; identifiers from the allowlist only
(quoted), values never interpolated; `LIMIT` = clamped `effective_limit`. Taxonomy: rows/empty→
Succeeded, SQLSTATE error→PermanentFailure, connection/IO→UnknownExternalState.

**Verify:** default `cargo test --no-default-features` → 50 suites green, no regression,
`postgres_real` excluded. `IGNITER_PG_DSN=… cargo test --no-default-features --features postgres
--test postgres_real_read_tests` → **6/6 against the dev SparkCRM `companies` table** (read-only);
without DSN → 6 skip cleanly. `IMPLEMENTED_SURFACE.md` updated (public API + feature added).
Read-only — no SparkCRM business tables written.

## Front door

Read first:

- `LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5.md` + `lab-docs/lang/lab-machine-postgres-local-feature-readiness-p5-v0.md`
- `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2.md` + `lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md`
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Verify live code before writing:

- `postgres_read::{PostgresReadExecutor, PostgresReadAdapter, PostgresReadResult, QueryPlan, QueryFilter, PostgresReadPolicy}`
- `capability::{CapabilityExecutor, run_effect}` (the boundary the executor rides)
- `Cargo.toml` feature layout (the `tls` opt-in precedent)

## Goal

Implement the **first real** `PostgresReadAdapter` (over `tokio-postgres`) behind an opt-in
`postgres` feature, proving the P2 read boundary against a real local Postgres — read-only.

```text
QueryPlan (gated by PostgresReadExecutor: source/op/field allowlist + limit clamp)
  → TokioPostgresReadAdapter.query()         [#[cfg(feature = "postgres")]]
      build parameterized SQL (allowlisted identifiers, $1..$n values, LIMIT clamp)
      → tokio_postgres SELECT (read-only)
  → PostgresReadResult → EffectOutcome + receipt (unchanged P2 path)
```

## Required design

1. **Opt-in feature.** `postgres = ["dep:tokio-postgres"]`; **default build unchanged** (fake-only,
   no DB driver). Real adapter is `#[cfg(feature = "postgres")]`.
2. **No raw SQL from contracts.** Identifiers come ONLY from the gated plan/allowlist; values bind
   as `$1..$n`. The executor's gates run before the adapter (unchanged).
3. **Read-only.** SELECT only; no writes/DDL.
4. **Outcome taxonomy.** rows/empty → Succeeded; DB error (SQLSTATE) → QueryError(permanent);
   connection/IO error → Unavailable(unknown).
5. **DSN via SecretProvider/env.** No DSN/credentials in code, receipts, or docs.
6. **Tests split.** Default fake/unit tests stay green; a new integration test is
   `#![cfg(feature = "postgres")]` and **skips when no DSN** is present.

## Acceptance

- [x] Verify-first confirms no real Postgres adapter exists before this card.
- [x] `postgres` Cargo feature added; default build stays fake-only / DB-dependency-free.
- [x] `TokioPostgresReadAdapter` implements `PostgresReadAdapter` behind the feature.
- [x] `QueryPlan` lowers to parameterized SQL; identifiers from allowlist, values bound.
- [x] Real local SELECT returns rows through `PostgresReadExecutor` + receipt.
- [x] Limit clamp reflected against the real query.
- [x] eq filter returns a correct subset (parameter-bound).
- [x] Forbidden field / unknown source still refused before the adapter (gate parity).
- [x] Replay same idempotency key bypasses the adapter (query count stays 1).
- [x] DB error → permanent; connection failure → unknown (taxonomy parity).
- [x] Integration test skips cleanly when no DSN; default suite unaffected.
- [x] Docs/card updated; `IMPLEMENTED_SURFACE.md` updated (public API + feature added).

## Closed surfaces

- No writes / DDL / migrations (read-only).
- No production/staging DB; local dev only.
- No ORM in `.ig`/VM/capsule; no Postgres-as-`TBackend`.
- No DSN/credentials in code/receipts/docs.
- No change to serving loop / ingress / wire-path.

## Deliverables

- Minimal implementation + integration test.
- `lab-docs/lang/lab-machine-postgres-local-read-p6-v0.md`
- Closing report in this card.

## Next routes

- `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P?` — thread `run_write_effect_atomic` into the wire path
  (precondition before any real write).
- `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P?` — real write transaction + `effect_receipts` table.
