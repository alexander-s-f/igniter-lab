# LAB-MACHINE-POSTGRES-TYPED-READ-P10 — typed JSON values for Postgres reads

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation
Skill: idd-agent-protocol
Delegation: OPUS-POSTGRES-TYPED-READ-P10

## Intent

Promote the real local Postgres read adapter from "all projected columns are
`::text` strings" to **typed `serde_json::Value` rows** while preserving the
existing safety model:

```text
QueryPlan JSON (no SQL)
  -> PostgresReadExecutor gates (raw-SQL refusal / allowlists / clamp)
  -> PostgresReadAdapter
  -> typed JSON rows + receipt
```

This is the next implementation slice chosen by
`LAB-MACHINE-POSTGRES-SCHEMA-QUERY-READINESS-P9`: types before richer
predicates. It should not add ORM behavior, migrations, raw SQL, joins,
aggregations, pooling, or schema inference.

## Authority

Lab implementation. The machine adapter is host-authoritative: schema and field
types come from host policy, not from `.ig` contracts and not from DB
introspection as authority.

This card may change:

- `runtime/igniter-machine/src/postgres_read.rs`;
- `runtime/igniter-machine/src/postgres_real.rs`;
- `runtime/igniter-machine/tests/postgres_read_tests.rs`;
- `runtime/igniter-machine/tests/postgres_real_read_tests.rs`;
- `runtime/igniter-machine/Cargo.toml` **only** if a narrow
  `tokio-postgres` feature is required for JSON decoding, and only under the
  existing opt-in `postgres` feature;
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md` if useful;
- one proof doc under `lab-docs/lang/`;
- this card's closing report.

This card must **not** change:

- `runtime/igniter-machine` write/reconcile semantics;
- `run_effect`, receipts machinery, SingleFlight, or coordination;
- `lang/igniter-compiler`, `.ig`, `.igweb`, `igniter-web`, or server code;
- default feature behavior (`default = []` must stay Postgres-free);
- schema migrations / live DB setup outside gated tests;
- canon docs.

No production/staging/SparkCRM writes. No public network. No pool. No TLS.

## Verify First

Read before editing:

- `lab-docs/lang/lab-machine-postgres-schema-query-readiness-p9-v0.md`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/tests/postgres_read_tests.rs`
- `runtime/igniter-machine/tests/postgres_real_read_tests.rs`
- `runtime/igniter-machine/Cargo.toml`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`

Then verify:

- current real adapter renders projection as `"<col>"::text` and returns
  `Value::String`/`Value::Null`;
- fake adapter already carries arbitrary typed `serde_json::Value` rows and
  should remain compatible;
- `tokio-postgres` feature support for `serde_json::Value` / JSONB, if needed;
- whether scalar decoding can be implemented without new deps;
- current real tests skip cleanly when `IGNITER_PG_DSN` is unset;
- current default build does not include `tokio-postgres`.

Live code wins over this card.

## Design Decision

Use a **host policy type map**, not DB introspection as authority.

Add a small read-type descriptor, for example:

```rust
pub enum PostgresReadValueKind {
    Text,
    Integer,
    Boolean,
    Json,
    Timestamp,
    DecimalString,
    Array,
}
```

Exact names are flexible. The key requirement is that the host policy declares
how an allowlisted field is decoded. The contract still emits only a typed
`QueryPlan`; it never names SQL casts or DB types.

Backwards compatibility:

- existing `allow_source("companies", &["id", "name"])` should keep working;
- default old fields may be treated as `Text` unless a typed variant is used;
- add an ergonomic typed API, e.g.
  `allow_source_typed("typed_todos", &[("id", Integer), ...])`.

Do **not** infer schema from DB metadata in this card. Metadata may be used as
debug evidence if useful, but not as the policy authority.

## Required Type Mapping

Implement these row value outputs:

| Policy kind | Output JSON |
|---|---|
| `Text` / uuid-like text | `Value::String` |
| `Integer` | `Value::Number` integer (`i64` where possible) |
| `Boolean` | `Value::Bool` |
| `Json` / `jsonb` | decoded `serde_json::Value` |
| `Timestamp` / date-like | RFC3339/string representation (lossless string) |
| `DecimalString` / numeric | **String**, never lossy float |
| `Array` | `Value::Array` where feasible; if array decoding is too broad for this slice, implement JSON-array fields first and document the narrow support |
| NULL | `Value::Null` for every kind |

Important: decimal-as-string is intentional. Do not turn arbitrary precision
`numeric` into `f64`.

## SQL Rendering Constraints

Preserve the existing security model:

- projection fields are already allowlisted before the adapter;
- identifiers are still quoted defensively;
- values are still bound parameters;
- raw SQL keys (`sql`/`raw_sql`/`query`) remain structurally refused;
- no `SELECT *`;
- no joins/aggregations/order/range in this card.

The real adapter may use different expressions per field kind (for example
raw column for bool/int/json, `::text` for timestamp/decimal/text), but the
projection shape and field names in returned rows must remain the same.

If `tokio-postgres` decoding requires a feature such as serde-json support,
enable it narrowly under the existing `postgres` feature and prove the default
normal dependency tree remains Postgres-free.

## Fake Adapter Requirements

The fake adapter already returns typed `serde_json::Value` rows. Add/adjust
tests to make that explicit:

- integer stays integer;
- bool stays bool;
- null stays null;
- JSON object/array stays JSON;
- projection shaping preserves typed values;
- replay still bypasses the adapter.

Do not make the fake evaluate predicates in this card; predicate evaluation is
still a separate named slice.

## Real Adapter / Test Strategy

Prefer a dedicated local test fixture under the existing `postgres` feature and
env gate. Acceptable patterns:

1. If `IGNITER_PG_DSN` points to a dedicated test DB, create/drop a tiny
   `igniter_typed_read_*` table in the test setup and read from it.
2. If creating tables is judged too broad, use an already dedicated local
   `igniter_pg_test` DB and document the required setup.
3. Do **not** write to SparkCRM/dev business tables for this typed-read proof.

Tests must skip cleanly when env is unset, following the current
`postgres_real_read_tests.rs` pattern.

The adapter remains read-only in normal operation; test setup DDL, if used, is
local/developer-gated and must be clearly isolated.

## Required Tests

At minimum:

1. **Fake typed pass-through.** A fake table row containing integer, bool, null,
   object/array JSON, timestamp-string, decimal-string survives projection and
   receipt result unchanged.
2. **Default build.** `cargo test --no-default-features --test postgres_read_tests`
   (or the relevant default fake tests) passes without `postgres`.
3. **Real typed read (gated).** Under `--features postgres` and env DSN, a
   dedicated local typed fixture proves:
   - integer comes back as JSON number;
   - boolean as JSON bool;
   - JSON/JSONB as object/array;
   - timestamp/date as string;
   - numeric/decimal as string;
   - NULL as null.
4. **Gate parity.** Forbidden source/field still refuses before the DB adapter.
5. **Filter parity.** Existing `eq` filter still works for text-compatible
   comparison; do not add range/order/in here.
6. **Replay.** Same idempotency key returns receipt result and does not re-query.
7. **Raw SQL refusal.** `sql`/`raw_sql`/`query` still permanent-fail before DB.
8. **Default dependency boundary.** `cargo tree -e normal --no-default-features`
   (or equivalent) shows no `tokio-postgres` in default/no-postgres build.

If a real local Postgres is unavailable in the environment, the gated real test
may skip, but the proof doc must state that exact skip path. Do not fake a live
DB proof.

## Required Verification Commands

Report exact counts/skips:

```text
cd runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests
cd runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests
cd runtime/igniter-machine && cargo test --no-default-features --features postgres --test postgres_real_read_tests
cd runtime/igniter-machine && cargo tree -e normal --no-default-features
```

If cheap, also run the full default machine suite:

```text
cd runtime/igniter-machine && cargo test --no-default-features
```

Do not run real DB tests against production/staging or SparkCRM write DSNs.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-machine-postgres-typed-read-p10-v0.md
```

Include:

1. executive summary;
2. verify-first facts and deltas from P9;
3. API/policy changes (`PostgresReadValueKind` or equivalent);
4. SQL rendering and decode strategy;
5. type mapping table with examples;
6. fake-adapter proof;
7. real-adapter gated proof or honest skip;
8. gate/replay/raw-SQL regression proof;
9. dependency boundary proof;
10. limits and next card.

## Acceptance

- [x] Real adapter no longer maps every projection to text by default when typed policy is used.
- [x] Host policy can declare field value kinds.
- [x] Existing untyped `allow_source` behavior remains compatible.
- [x] Integer, bool, JSON, timestamp-string, decimal-string, array/narrow-array, and null semantics are tested or explicitly scoped.
- [x] Raw SQL refusal, allowlist gates, limit clamp, and replay behavior remain unchanged.
- [x] Default/no-postgres build remains Postgres-free.
- [x] No ORM, migration runner, joins, aggregations, pooling, TLS, or schema inference added.
- [x] Real Postgres proof is env-gated and local-only, or explicitly skipped with evidence.
- [x] Proof doc written.
- [x] Card closed with compact report and exact command counts.

---

## Closing Report (2026-06-19)

**Implemented:** typed Postgres reads driven by a host-declared field-kind policy.
- `postgres_read.rs`: `PostgresReadValueKind` enum (`Text` default), `PostgresReadPolicy.field_kinds` +
  `allow_source_typed()` + `field_kind()`; `PostgresReadAdapter::query` gains a `kinds` arg; the executor
  computes per-projection kinds from policy; fake adapter ignores them (already typed).
- `postgres_real.rs`: `projection_expr` (`::bigint`/`::bool`/`::jsonb`/`::text`) + `decode_value`
  (i64/bool/`serde_json::Value`/String) — `numeric`+timestamp stay **String** (never `f64`); NULL→null.
- `Cargo.toml`: `tokio-postgres` gains `with-serde_json-1` (only under the opt-in `postgres` feature).
- Untyped `allow_source` unchanged (all `Text`); gates/clamp/replay/raw-SQL refusal untouched.

**Blocker handled:** at start, `igniter_compiler` (a path-dep of `igniter-machine`) didn't compile due to
concurrent in-flight igweb "P26" work in the shared tree; surfaced it; once the neighbor fixed it
("compiles cleanly"), P10 built and tested. No compiler files were changed by P10.

**Proof — exact counts:**
- `cargo test --no-default-features --test postgres_read_tests` → **10 passed** (+1 new `fake_typed_*`).
- `--test relational_queryplan_bridge_tests` → **6 passed** (P3 intact).
- `--features postgres --test postgres_real_read_tests` → **7 passed** (`IGNITER_PG_DSN` unset; env-gated
  tests return early via `connect_or_skip`; the new `real_typed_read_decodes_by_kind` compiles under
  `postgres` and returns early — no faked DB).
- `cargo tree -e normal --no-default-features | grep tokio-postgres` → **none** (default Postgres-free).
- Full default sweep: **227 passed, 1 failed** — the 1 failure is `test_machine_fleet_sweep`
  (`batch_importer` → VM `variant_construct` gap), **unrelated to P10**: zero fleet apps use
  `PostgresRead` (`rg -l PostgresRead apps/igniter-apps` → 0), so the read adapter is unreachable from that
  test; pre-existing / from concurrent compiler work.

**Honest bounds:** predicate eval still deferred (`eq`-only); `Array` = JSON/JSONB arrays only (native PG
arrays deferred); decimal/timestamp as strings by design; single connection, no pool/TLS. Proof doc:
`lab-docs/lang/lab-machine-postgres-typed-read-p10-v0.md`. **Next:**
`LAB-MACHINE-POSTGRES-PREDICATES-P11`.

## Closed Surfaces

No predicates beyond existing `eq`. No `in`/range/order/keyset. No write path.
No `effect_receipts` DDL changes. No pool. No TLS. No schema introspection as
authority. No contract-owned SQL. No compiler/VM/IgWeb/server changes. No
production/staging DB.

## Suggested Next

After P10, the likely next machine DB slice is:

```text
LAB-MACHINE-POSTGRES-PREDICATES-P11
```

Scope: `in`, `order_by`, and maybe range predicates over the typed field policy.
Do not open P11 until typed reads are proven.
