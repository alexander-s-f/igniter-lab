# LAB-MACHINE-POSTGRES-PREDICATES-P11 — typed read predicates + order_by

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation
Skill: idd-agent-protocol
Delegation: OPUS-POSTGRES-PREDICATES-P11

## Intent

Extend the Postgres read capability from **`eq`-only** to a small, typed,
host-gated predicate set over the P10 field-kind policy:

```text
QueryPlan JSON (no SQL)
  -> raw-SQL refusal
  -> source/op/field allowlists
  -> typed predicate validation
  -> row-limit clamp
  -> fake/real adapter
  -> typed JSON rows + receipt
```

This is the implementation slice recommended after
`LAB-MACHINE-POSTGRES-TYPED-READ-P10`: richer predicates only after typed reads.
It must remain boring infrastructure: no ORM, no joins, no aggregations, no
raw SQL, no schema introspection as authority.

## Authority

Lab implementation. The machine adapter is host-authoritative: allowed sources,
fields, field value kinds, and predicate shapes come from host policy and the
closed `QueryPlan` grammar, not from DB metadata and not from contracts naming
SQL.

This card may change:

- `runtime/igniter-machine/src/postgres_read.rs`;
- `runtime/igniter-machine/src/postgres_real.rs`;
- `runtime/igniter-machine/tests/postgres_read_tests.rs`;
- `runtime/igniter-machine/tests/postgres_real_read_tests.rs`;
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs` only if
  needed for backwards-compatible shape assertions;
- `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig`
  only if adding an optional query-plan example is useful and compiler-safe;
- one proof doc under `lab-docs/lang/`;
- this card's closing report.

This card must **not** change:

- write/reconcile semantics;
- `run_effect`, receipts machinery, SingleFlight, or coordination;
- `lang/igniter-compiler`, VM, IgWeb, server, or runner semantics;
- Cargo dependencies;
- default feature behavior (`default = []` stays Postgres-free);
- schema migrations or live DB setup outside gated tests;
- canon docs.

No production/staging/SparkCRM writes. No public network. No pool. No TLS.

## Verify First

Read before editing:

- `lab-docs/lang/lab-machine-postgres-schema-query-readiness-p9-v0.md`
- `lab-docs/lang/lab-machine-postgres-typed-read-p10-v0.md`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/tests/postgres_read_tests.rs`
- `runtime/igniter-machine/tests/postgres_real_read_tests.rs`
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs`
- `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig`

Then confirm live facts:

- `QueryFilter` is currently `{ field, op, value }` and defaults op to `"eq"`;
- the fake adapter currently does **not** evaluate filters;
- the real adapter renders only `eq` filters with bound values;
- P10 `PostgresReadValueKind` exists and is host policy, not DB introspection;
- raw-SQL keys `sql`/`raw_sql`/`query` are refused before plan parse;
- default/no-postgres build does not include `tokio-postgres`;
- current env-gated real tests return early when `IGNITER_PG_DSN` is unset.

Live code wins over this card.

## QueryPlan Shape To Support

Keep the existing `eq` shape backwards-compatible:

```json
{ "field": "status", "op": "eq", "value": "active" }
```

Add:

```json
{ "field": "status", "op": "in", "values": ["new", "active"] }
{ "field": "id", "op": "gt", "value": 10 }
{ "field": "id", "op": "gte", "value": 10 }
{ "field": "id", "op": "lt", "value": 20 }
{ "field": "id", "op": "lte", "value": 20 }
```

Add `order_by` at the plan level:

```json
{
  "source": "todos",
  "op": "select",
  "projection": ["id", "title"],
  "filters": [{"field": "account_id", "op": "eq", "value": "a-7"}],
  "order_by": [{"field": "id", "dir": "asc"}],
  "limit": 50
}
```

Recommended Rust shape:

```rust
pub struct QueryFilter {
    pub field: String,
    pub op: String,
    pub value: serde_json::Value,
    pub values: Vec<serde_json::Value>,
}

pub struct QueryOrder {
    pub field: String,
    pub dir: String, // asc | desc
}

pub struct QueryPlan {
    ...
    pub order_by: Vec<QueryOrder>,
}
```

Exact names are flexible. Keep old callers working: a scalar string `value`
must still parse for `eq`.

## Predicate Semantics

Supported v0 ops:

| op | Meaning | Notes |
|---|---|---|
| `eq` | equality | existing behavior, still default |
| `in` | field is one of values | `values` must be a non-empty array; max length bounded |
| `gt` | greater than | typed scalar only |
| `gte` | greater than or equal | typed scalar only |
| `lt` | less than | typed scalar only |
| `lte` | less than or equal | typed scalar only |

Type policy:

- `Text`: allow `eq`, `in`; optionally `order_by`; reject range ops unless the
  implementation explicitly justifies lexicographic compare.
- `Integer`: allow all supported ops and `order_by`.
- `Boolean`: allow `eq`, `in`; reject range/order unless justified.
- `Timestamp`: allow range and `order_by`, but values remain strings and are
  bound/cast by the real adapter; do not parse wall-clock time in contracts.
- `DecimalString`: allow range only if real adapter casts/binds safely without
  float; otherwise defer range for decimal and document it.
- `Json` / `Array`: no ordering or range; `eq` only if implemented safely,
  otherwise reject non-Text/Integer/Boolean/Timestamp predicates for v0.

If this matrix is too broad for one clean implementation, prefer:

1. `in` for `Text`/`Integer`/`Boolean`;
2. range + `order_by` for `Integer` and `Timestamp`;
3. document deferred kinds explicitly.

Do **not** silently coerce invalid values. Invalid predicate shape is a
`PermanentFailure` before adapter mutation/IO, with adapter query count 0 in
fake tests where possible.

## Host Policy / Limits

Add bounded limits if needed:

- max `in` list length, e.g. `max_in_values = 100`;
- max `order_by` clauses, e.g. 2 or 3;
- direction must be exactly `asc` or `desc` (case-insensitive if normalized).

Field allowlist remains the gate for projection + filters + order fields.
Adding `order_by` must update "all touched fields" validation or equivalent.

## Real Adapter Requirements

Render parameterized SQL only:

- identifiers from allowlisted fields, quoted defensively;
- values bound as `$1..$n`;
- no raw SQL fragments from the request;
- no `SELECT *`;
- limit remains clamped;
- `ORDER BY` uses quoted allowlisted fields and normalized direction only.

Suggested rendering:

- `eq`: `"field" <typed-cast> = $n` or existing safe equivalent;
- `in`: `"field" <typed-cast> = ANY($n)` where `$n` is a typed Vec parameter,
  or a bounded `IN ($n, $n+1, ...)` expansion if simpler and safer;
- range: `"field" <typed-cast> > $n`, etc.

Prefer a small helper that maps `(field kind, op, json value)` to a bound
parameter type. Do not use string interpolation for values.

## Fake Adapter Requirements

P11 should make the fake adapter useful for predicate tests without becoming a
full SQL engine:

- evaluate supported predicates against stored `serde_json::Value` rows;
- apply `order_by`;
- then apply projection shaping and limit;
- preserve typed values unchanged;
- unsupported/invalid ops should be refused before `query` where practical.

Keep fake semantics intentionally small and deterministic. No joins, no
aggregations, no expression language.

## Required Tests

At minimum in `postgres_read_tests`:

1. `eq` still works and is backward-compatible with old string `value`.
2. `in` filters fake rows by text and/or integer.
3. range filters fake rows by integer.
4. `order_by` sorts deterministically before limit.
5. `order_by` on a non-allowlisted field is denied before adapter.
6. invalid `in` (`values` missing/empty/too long) is permanent failure or
   denial before adapter; document chosen taxonomy.
7. invalid range kind/value is refused before adapter.
8. replay bypasses adapter with predicates/order unchanged.
9. raw SQL refusal still wins before plan parsing/adapters.
10. typed values survive projection + receipt after predicate/order evaluation.

At minimum under `--features postgres` in `postgres_real_read_tests`:

11. The real adapter compiles with `in`, range, and `order_by` rendering.
12. If `IGNITER_PG_DSN` and fixture tables exist, a local-only test proves
    typed `in`/range/order behavior. If env is unset, return early honestly.

Regression:

13. `relational_queryplan_bridge_tests` still pass; if adding example
    relational plans, keep them no-DB and no-raw-SQL.

## Required Verification Commands

Run and record exact counts:

```text
cd runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests
cd runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests
cd runtime/igniter-machine && cargo test --no-default-features --features postgres --test postgres_real_read_tests
cd runtime/igniter-machine && cargo tree -e normal --no-default-features
git diff --check
```

If cheap, also run:

```text
cd runtime/igniter-machine && cargo test --no-default-features
```

If the known `test_machine_fleet_sweep` / `batch_importer` VM
`variant_construct` failure remains, report it separately and confirm it is not
reachable from the Postgres read adapter.

Do not require a real Postgres DSN. Do not fake a live DB proof.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-machine-postgres-predicates-p11-v0.md
```

Include:

1. executive summary;
2. verify-first facts from P9/P10/live code;
3. exact QueryPlan shape additions;
4. predicate/type support matrix;
5. real adapter rendering strategy;
6. fake adapter evaluation strategy;
7. gate/replay/raw-SQL regression proof;
8. real-adapter env-gated proof or honest early-return;
9. dependency boundary proof;
10. limits and next card.

## Acceptance

- [x] `eq` remains backward-compatible.
- [x] `in` works for at least Text/Integer/Boolean typed fields.
- [x] range comparisons work for at least Integer (and Timestamp if feasible).
- [x] `order_by` works on allowlisted fields and is deterministic.
- [x] order/filter fields are allowlist-gated.
- [x] invalid predicate shapes fail closed before unsafe adapter work.
- [x] fake adapter evaluates supported predicates/order deterministically.
- [x] real adapter compiles under `--features postgres` and renders only
      parameterized, allowlisted SQL.
- [x] replay/raw-SQL/limit-clamp behavior remains unchanged.
- [x] default/no-postgres build remains DB-driver-free.
- [x] No joins, aggregations, raw SQL, ORM, pool, TLS, migration runner, or
      schema introspection authority.
- [x] Proof doc + closing report written.

---

## Closing Report (2026-06-19)

**Implemented** the typed predicate set + `order_by` over the P10 field-kind policy.
- `postgres_read.rs`: `QueryFilter.values`, `QueryOrder`, `QueryPlan.order_by`; `from_args` parses both;
  `referenced_fields` now covers order fields (allowlist-gated); policy `max_in_values`/`max_order_by` +
  `with_predicate_limits`; a `validate_predicates` gate (G3.5) refusing out-of-matrix/empty/oversized/bad-
  dir before the adapter; fake adapter now **filters → orders → projects → limits** deterministically.
- `postgres_real.rs`: typed param binding (`bind_scalar`/`bind_array`, `Box<dyn ToSql+Sync+Send>`),
  `compare_cast`, `= ANY($n)` for `in`, `<cast> <op> $n` for eq/range (`$n::timestamptz` for Timestamp),
  `ORDER BY <cast> DIR`. Adapter trait `kinds` refined from projection-vec to a source field→kind **map**
  (filter/order fields need kinds too) — internal-only, untyped sources unchanged.
- **No Cargo dependency added** (P11 constraint).

**Proof — exact counts:**
- `--test postgres_read_tests` → **18 passed** (10 prior + 8 new: eq-backcompat, in×2, range, order,
  order-denied, invalid-in, invalid-range-kind, typed-survive).
- `--test relational_queryplan_bridge_tests` → **6 passed** (P3 intact; fake-filter compatible).
- `--features postgres --test postgres_real_read_tests` → **8 passed, ALL skip** (`IGNITER_PG_DSN` unset;
  the new `real_typed_predicates_and_order` compiles under `postgres`, early-returns — no faked DB).
- `cargo tree -e normal --no-default-features | grep tokio-postgres` → **none**.
- `git diff --check` clean. Full default sweep: **1 failure**, the known unrelated
  `test_machine_fleet_sweep` (`batch_importer` VM `variant_construct`) — zero fleet apps use `PostgresRead`,
  so unreachable from P11.

**Honest bounds:** decimal range deferred (no float); `in` = Text/Integer/Boolean, range = Integer/
Timestamp, no order on Boolean/Json/Array/Decimal; no keyset/offset/joins/aggregations/pool/TLS. Proof doc:
`lab-docs/lang/lab-machine-postgres-predicates-p11-v0.md`. **Next:** `LAB-MACHINE-POSTGRES-KEYSET-P12` or
`LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3`.

## Closed Surfaces

No joins. No aggregations. No `SELECT *`. No raw SQL from contracts. No
cross-table relation planner. No keyset cursor yet. No offset pagination. No
write path. No receipt/reconcile changes. No pool/TLS. No migrations. No schema
introspection as authority. No compiler/VM/IgWeb/server changes. No production
or SparkCRM DB.

## Suggested Next

After P11, choose based on pressure:

- `LAB-MACHINE-POSTGRES-KEYSET-P12` if API pagination needs stable cursors; or
- `LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` if TodoApp needs live DB reads in
  the web path before more DB operators.

