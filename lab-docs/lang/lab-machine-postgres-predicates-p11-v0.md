# lab-machine-postgres-predicates-p11-v0 — typed read predicates + order_by

**Card:** `LAB-MACHINE-POSTGRES-PREDICATES-P11` · **Delegation:** `OPUS-POSTGRES-PREDICATES-P11`
**Status:** CLOSED (lab implementation) — the Postgres read capability grows from **`eq`-only** to a small,
typed, host-gated predicate set (`eq` / `in` / `gt` / `gte` / `lt` / `lte`) plus plan-level `order_by`,
validated against the P10 field-kind policy before any adapter work. The fake adapter now **evaluates**
predicates + order deterministically; the real adapter renders **parameterized, allowlisted** SQL
(`= ANY($n)`, `<cast> <op> $n`, `ORDER BY <cast> DIR`). **No joins/aggregations/raw SQL/ORM, no
Cargo-dep change, no write/reconcile/`run_effect` change, default build stays Postgres-free.**
**Authority:** Lab. Allowed sources, fields, kinds, and predicate shapes are host policy + the closed
`QueryPlan` grammar — never DB metadata, never contract-supplied SQL.

## 1. Executive summary

`QueryFilter` gains `values` (for `in`); a `QueryOrder { field, dir }` + `QueryPlan.order_by` are added; the
executor runs a **typed predicate validation gate (G3.5)** after the field allowlist and before the adapter
(malformed/over-broad → `PermanentFailure`; non-allowlisted order/filter field → `Denied` by the existing
allowlist). The fake adapter filters → sorts → projects → limits over stored JSON values, types preserved.
The real adapter binds typed parameters per field kind (`i64`/`bool`/text+cast) and renders only
allowlisted, quoted identifiers. `eq` with a scalar string `value` stays backward-compatible.

## 2. Verify-first facts (live code)

- `QueryFilter` was `{ field, op, value }` defaulting `op` to `"eq"`; the fake did **not** evaluate
  filters; the real adapter rendered only `eq` (`::text = $n`) (`postgres_read.rs`/`postgres_real.rs`
  pre-P11).
- P10 `PostgresReadValueKind` is host policy (`allow_source_typed` / `field_kind`), not DB introspection.
- raw-SQL keys (`sql`/`raw_sql`/`query`) refused before plan parse; default build has no `tokio-postgres`;
  real tests early-return when `IGNITER_PG_DSN` is unset.
- **Refinement of the P10 adapter signature:** P10 passed `kinds: &[PostgresReadValueKind]` aligned to the
  projection. P11 needs kinds for **filter and order** fields too, so the trait now passes
  `kinds: &HashMap<String, PostgresReadValueKind>` (the source's full field→kind map; `Text` default).
  Internal-only; no behavior change for untyped sources.

## 3. QueryPlan shape additions

```json
{ "field": "status", "op": "eq",  "value": "active" }           // unchanged (scalar value)
{ "field": "status", "op": "in",  "values": ["new","active"] }  // NEW: non-empty list
{ "field": "id",     "op": "gt",  "value": 10 }                 // NEW: range (gt/gte/lt/lte)
"order_by": [{ "field": "id", "dir": "asc" }]                    // NEW: plan-level, dir asc|desc
```

Rust: `QueryFilter { field, op, value, values }`, `QueryOrder { field, dir }`,
`QueryPlan { …, order_by: Vec<QueryOrder> }`. Old callers keep working: a scalar string `value` still
parses for `eq`; `values`/`order_by` default empty.

## 4. Predicate / type support matrix (v0)

| kind | `eq` | `in` | range (`gt`/`gte`/`lt`/`lte`) | `order_by` |
|---|---|---|---|---|
| `Integer` | ✓ | ✓ | ✓ | ✓ |
| `Text` | ✓ | ✓ | ✗ | ✓ (lexicographic) |
| `Boolean` | ✓ | ✓ | ✗ | ✗ |
| `Timestamp` | ✓ | ✗ | ✓ (string bound + `::timestamptz` cast) | ✓ |
| `DecimalString` | ✓ | ✗ | ✗ (deferred — no float) | ✗ |
| `Json` / `Array` | ✗ | ✗ | ✗ | ✗ |

Bounds: `max_in_values` (default 100), `max_order_by` (default 3), `dir ∈ {asc, desc}`. Violations and
type/shape errors are `PermanentFailure` **before** the adapter (`validate_predicates`); a non-allowlisted
filter/order field is `Denied` by the field allowlist (it joins `referenced_fields`). **No silent
coercion** — an out-of-matrix op or empty/oversized `in` fails closed.

## 5. Real adapter rendering strategy

`postgres_real.rs` (parameterized only, no interpolated values):
- per-field cast `compare_cast`: `Integer→::bigint`, `Boolean→::bool`, `Timestamp→::timestamptz`,
  else `::text`.
- `eq`/range → `<cast> <op> $n` (Timestamp also casts the param: `$n::timestamptz`).
- `in` → `<cast> = ANY($n)` over a **typed array** param (`Vec<i64>`/`Vec<bool>`/`Vec<String>`).
- `order_by` → `ORDER BY <cast> ASC|DESC, …` (allowlisted, quoted, normalized dir).
- typed scalar binding (`bind_scalar`/`bind_array`): `Integer→i64`, `Boolean→bool`, else text; a value that
  can't bind to its kind → `QueryError` (permanent), never coerced. Params boxed as
  `Box<dyn ToSql + Sync + Send>` (Send so the query future stays `Send`). Projection decode is unchanged
  (P10) but now resolves each field's kind via the map.

## 6. Fake adapter evaluation strategy

Deterministic, no SQL/expression engine: **filter** (AND-composed; `row_matches_filter` via `cmp_values`
— numbers numerically, bools as bools, else string fallback) → **order_by** (stable sort, last clause first
so earlier clauses dominate; `desc` reverses) → **project** (clone preserves types) → **limit**. A row
missing a filtered field never matches.

## 7. Gate / replay / raw-SQL regression proof

The pre-P11 `postgres_read_tests` still pass (allowlist denials, mutation refusal, clamp, replay, raw-SQL
refusal) and the P3 `relational_queryplan_bridge_tests` (6) still pass — the fake now filters, but the
bridge's `account_id eq acct-7` plan still returns both matching rows. Untyped `allow_source` behaviour is
unchanged (`eq` on `Text` allowed; no order/range).

## 8. Real-adapter env-gated proof

`postgres_real_read_tests.rs :: real_typed_predicates_and_order` (under `--features postgres`) runs
`in(id) + gte(id) + order_by(id desc)` against the P10 `igniter_typed_read` fixture and asserts integers
stay numbers + descending order. **`IGNITER_PG_DSN` is unset here, so it (and the other real tests) return
early via `connect_or_skip`** (Cargo reports `passed`, not `ignored`); the predicate/`in`/`order_by`
rendering **compiles** under `--features postgres`. No live DB proof is faked.

## 9. Dependency boundary proof

```text
$ cargo tree -e normal --no-default-features | grep -i tokio-postgres   → (none)
```

No Cargo dependency was added (P11 forbids it); the driver stays behind `--features postgres`.

## 10. Commands + exact counts

```text
$ cd runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests
  → 18 passed; 0 failed                 (10 prior + 8 new: eq-backcompat, in×2, range, order, order-denied,
                                          invalid-in, invalid-range-kind, typed-survive)
$ cargo test --no-default-features --test relational_queryplan_bridge_tests
  →  6 passed; 0 failed                 (P3 bridge intact; fake-filter compatible)
$ cargo test --no-default-features --features postgres --test postgres_real_read_tests
  →  8 passed; 0 failed                 (7 prior + 1 new; ALL skip — IGNITER_PG_DSN unset; compiles)
$ cargo tree -e normal --no-default-features | grep tokio-postgres   → (none)
$ git diff --check                                                   → clean
$ cargo test --no-default-features        (full default sweep)       → 1 failure
```

**The 1 default-sweep failure is the known, unrelated `test_machine_fleet_sweep`** — `batch_importer`
diverges with `VMExecutionError("Unsupported AST kind in VM evaluator: variant_construct")` (a VM-evaluator
gap, not Postgres). **Zero fleet apps use `PostgresRead`** (`rg -l PostgresRead apps/igniter-apps` → 0), so
the read adapter is unreachable from that test; pre-existing / concurrent compiler work, not P11.

## 11. Limits + next card

- `Timestamp` range binds strings + `::timestamptz`; **decimal range deferred** (no float).
- `in` only for Text/Integer/Boolean; range only for Integer/Timestamp; no order on Boolean/Json/Array/
  DecimalString.
- No keyset cursor, no offset pagination, no joins/aggregations/`SELECT *`, no pool/TLS.

**Next:** `LAB-MACHINE-POSTGRES-KEYSET-P12` (stable cursors for API pagination) **or**
`LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` (live DB reads in the IgWeb path) — choose by pressure.

---

*Lab implementation. Compiled 2026-06-19; 18 read + 6 bridge + 8 real-gated(skip) tests green; default
build Postgres-free; one unrelated VM `variant_construct` fleet failure documented. No Cargo dep, write/
reconcile, run_effect, compiler, VM, or IgWeb change.*
