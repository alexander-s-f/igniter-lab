# lab-machine-postgres-typed-read-p10-v0 — typed JSON values for Postgres reads

**Card:** `LAB-MACHINE-POSTGRES-TYPED-READ-P10` · **Delegation:** `OPUS-POSTGRES-TYPED-READ-P10`
**Status:** CLOSED (lab implementation) — the real local Postgres read adapter now decodes projected
columns into **typed `serde_json::Value`** (integer / boolean / json / array / lossless timestamp+decimal
strings / null) per a **host-declared field-kind policy**, instead of mapping everything to `::text`. The
contract still emits only a typed `QueryPlan`; all safety gates, idempotency, and the receipt path are
unchanged.
**No predicate evaluation, no write/reconcile change, no `run_effect` change, no pool/TLS, no schema
introspection-as-authority, no compiler/VM/IgWeb/server change, default build stays Postgres-free.**
**Authority:** Lab. The machine adapter is host-authoritative: field types come from host policy, not from
`.ig` contracts and not from DB metadata.

## 1. Executive summary

The host read policy gains a per-field **decode kind**; the executor passes the projected fields' kinds to
the adapter; the real `tokio_postgres` adapter renders each column per its kind (`::bigint`, `::bool`,
`::jsonb`, `::text`) and decodes it into a typed JSON value (`numeric`/timestamp stay **String**, never
`f64`); the fake adapter already carried typed `serde_json::Value` rows and now has an explicit
type-preservation test. Untyped `allow_source` is unchanged (every field decodes as `Text`). Gates, clamp,
replay, and raw-SQL refusal are untouched. Default/no-`postgres` build pulls no DB driver.

## 2. Verify-first facts / deltas

- **Reorg path:** machine lives under `runtime/igniter-machine/` (card paths confirmed).
- Real adapter (P6) rendered every projection as `"<col>"::text` → `Value::String`/`Value::Null`
  (`postgres_real.rs` pre-P10). **Delta:** now per-kind rendering + decode.
- Fake adapter stores arbitrary typed `serde_json::Value` rows and projection-shapes them by cloning the
  value (`postgres_read.rs` `FakePostgresAdapter::query`) — types already survive; P10 adds the proof.
- `tokio-postgres` is opt-in (`postgres` feature; `default = []`); `serde_json::Value` decoding needs the
  crate's `with-serde_json-1` feature, enabled **only** under `postgres`.
- Real tests skip cleanly when `IGNITER_PG_DSN` is unset (`connect_or_skip`).

## 3. API / policy changes

`runtime/igniter-machine/src/postgres_read.rs`:

```rust
pub enum PostgresReadValueKind { Text, Integer, Boolean, Json, Timestamp, DecimalString, Array }
//  ^ Text is Default → untyped fields keep old all-text behaviour.

// PostgresReadPolicy gains:
pub field_kinds: HashMap<String, HashMap<String, PostgresReadValueKind>>,
pub fn allow_source_typed(self, source, &[(&str, PostgresReadValueKind)]) -> Self  // gate + kinds in one decl
pub fn field_kind(&self, source, field) -> PostgresReadValueKind                   // defaults to Text
```

`PostgresReadAdapter::query` gains a `kinds: &[PostgresReadValueKind]` argument (aligned to
`plan.projection`); the executor computes it from `policy.field_kind(source, field)`. The fake ignores it
(already typed); the real adapter uses it. `allow_source(...)` is unchanged — its fields decode as `Text`.

## 4. SQL rendering + decode strategy (real adapter)

`postgres_real.rs`: `projection_expr(col, kind)` and `decode_value(row, i, kind)`:

| Policy kind | Projection SQL | Decode | Output JSON |
|---|---|---|---|
| `Text` | `"col"::text` | `Option<String>` | `Value::String` / `Null` |
| `Integer` | `"col"::bigint` | `Option<i64>` | `Value::Number` (i64) / `Null` |
| `Boolean` | `"col"::bool` | `Option<bool>` | `Value::Bool` / `Null` |
| `Json` | `"col"::jsonb` | `Option<serde_json::Value>` | decoded value / `Null` |
| `Array` | `"col"::jsonb` | `Option<serde_json::Value>` | `Value::Array` (json array) / `Null` |
| `Timestamp` | `"col"::text` | `Option<String>` | lossless string / `Null` |
| `DecimalString` | `"col"::text` | `Option<String>` | **String** (never `f64`) / `Null` |

Security model preserved: explicit projection required (no `SELECT *`); identifiers allowlisted +
quoted; filter values bound as `$1..$n`; `eq`-only filters (text compare, unchanged); raw-SQL keys
(`sql`/`raw_sql`/`query`) still structurally refused; no joins/aggregations/order/range. **Honest narrow
scope:** `Array` supports **JSON/JSONB arrays only** — native PG arrays (`int[]`) are deferred. `numeric`
and timestamps are intentionally **strings** (arbitrary precision / lossless), not numbers.

## 5. Fake-adapter proof

`runtime/igniter-machine/tests/postgres_read_tests.rs` ::
`fake_typed_values_survive_projection_and_receipt` — a fake `typed_todos` row with integer / boolean /
json object / json array / timestamp-string / decimal-string / null, read under an `allow_source_typed`
policy, comes back with **types preserved** (`id` i64, `active` bool, `meta` object, `tags` array,
`amount` String, `note` null) in both the `EffectOutcome` result and the persisted **receipt fact**.

## 6. Real-adapter gated proof (env-gated early return here — honest)

`runtime/igniter-machine/tests/postgres_real_read_tests.rs` ::
`real_typed_read_decodes_by_kind` (under `--features postgres`) reads a pre-seeded local
`igniter_typed_read(id bigint, active boolean, meta jsonb, tags jsonb, created_at timestamptz, amount
numeric, note text)` table and **structurally** asserts each field decodes to its declared JSON kind
(`is_i64`, `is_boolean`, `is_object/array`, `is_string` for timestamp/decimal, null tolerated). One-time
setup SQL is in the test header; it never touches SparkCRM/dev business tables.

**In this environment `IGNITER_PG_DSN` is unset, so the env-gated tests return early via
`connect_or_skip`** (Cargo reports them as `passed`, not `ignored`) — the typed-read test **compiles** under
`--features postgres` and returns early. No live DB proof is faked. A developer with a local dedicated
Postgres + the fixture table runs it green.

## 7. Gate / replay / raw-SQL regression proof

The pre-P10 `postgres_read_tests` still pass unchanged: unknown-source / forbidden-field / mutating-op
denials before the adapter, row-limit clamp, replay-bypasses-adapter, raw-SQL structural refusal, and the
P3 `relational_queryplan_bridge_tests`. Untyped policy behaviour is byte-identical (Text default).

## 8. Dependency boundary proof

```text
$ cargo tree -e normal --no-default-features | grep -i tokio-postgres   → (none)
```

The default build pulls no `tokio-postgres` (and thus no `with-serde_json-1`); the driver is reachable
only under `--features postgres`.

## 9. Commands + exact counts

```text
$ cd runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests
  → 10 passed; 0 failed                 (9 prior gates/replay/raw-sql + 1 new fake-typed)
$ cargo test --no-default-features --test relational_queryplan_bridge_tests
  →  6 passed; 0 failed                 (P3 bridge intact)
$ cargo test --no-default-features --features postgres --test postgres_real_read_tests
  →  7 passed; 0 failed                 (IGNITER_PG_DSN unset; env-gated tests returned early)
$ cargo tree -e normal --no-default-features | grep tokio-postgres
  → (none)                              (default build Postgres-free)
$ cargo test --no-default-features        (full default sweep)
  → 227 passed; 1 failed
```

**The 1 default-sweep failure is unrelated to P10 and not caused by these changes:** it is
`test_machine_fleet_sweep`, where `batch_importer` diverges with
`VMExecutionError("Unsupported AST kind in VM evaluator: variant_construct")` — a **VM-evaluator** gap
(batch_importer models `Result` as a user variant; `variant_construct` is unsupported in the VM eval
path). **Zero fleet apps reference `PostgresRead`** (`rg -l PostgresRead apps/igniter-apps` → 0), so the
Postgres read adapter is unreachable from that test. The failure is pre-existing / from concurrent
compiler work in the shared tree, not from P10 (whose changes are confined to the Postgres read adapter +
its tests + the opt-in feature).

## 10. Limits + next card

- **Predicate evaluation still deferred** — filters are carried, `eq`-only, text-compared.
- **`Array` = JSON/JSONB arrays only**; native PG arrays deferred.
- **No pool / TLS / migrations / schema introspection-as-authority**; single connection.
- Decimal/timestamp are strings by design (precision/losslessness).

**Next:** `LAB-MACHINE-POSTGRES-PREDICATES-P11` — `in` / `order_by` / range over the typed field policy
(do not open until typed reads are proven — they now are).

---

*Lab implementation. Compiled 2026-06-19; 10 read + 6 bridge + 7 real-gated early-return tests green;
default build Postgres-free; one unrelated VM `variant_construct` fleet failure documented. No
write/reconcile, run_effect, compiler, VM, or IgWeb change.*
