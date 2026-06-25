# lab-igniter-data-projection-materialization-readiness-p2-v0

Card: `LAB-IGNITER-DATA-PROJECTION-MATERIALIZATION-READINESS-P2`
Route: standard / deep readiness · Skill: idd-agent-protocol
Status: research-only feasibility packet (no code changed; no canon claim; crossing NOT implemented)
Date: 2026-06-25
Builds on: `lab-docs/lang/lab-igniter-data-projection-boundary-readiness-p1-v0.md`

> **Authority boundary.** Research only. This packet *decides nothing about canon*, *implements nothing*,
> and makes no claim that typed-row crossing is implemented. It answers one technical question from live
> VM/compiler/host source, with `file:line` citations, and proposes the smallest implementation card.

---

## The question

> Can host-held typed row values cross into a `.ig` continuation as `Collection[AppRow]`, so `r.title`,
> `r.done`, `filter`, `map`, and `call_contract` work as typed record operations?

**Feasibility verdict: `small-gap`.** The VM value substrate is *already* capable — `from_json` turns a JSON
array-of-objects into `Collection[Record]`, dispatch materializes inputs through exactly that path, and
record field access + HOFs over records already run green in the fleet. The gaps are **all host-side and
small**: the host still stringifies the rows, no materializer aligns rows to a projection spec, and
Decimal/Timestamp cross as strings. **No language / VM / compiler change is required** for the common
String/Integer/Bool/Json/Array case.

---

## 1. Exact live value-materialization path

### 1.1 The value representation (`lang/igniter-vm/src/value.rs`)

```rust
pub enum Value { Nil, Bool(bool), Integer(i64), Float(f64), String(Arc<str>),
                 Decimal { value: i64, scale: u32 }, Array(Arc<Vec<Value>>),
                 Record(Arc<BTreeMap<String, Value>>) }            // value.rs:7-16
```

**There is no separate `Value::Map` variant.** A `Map[String, Unknown]` and a record are *the same runtime
value* — `Value::Record`. The type distinction is a compile-time annotation only. (This is why `req.body_json
: Map[String, Unknown]` and an app record both materialize identically — see §1.3.)

### 1.2 JSON → VM value (`value.rs:51-99`, the literal answer)

`Value::from_json(&serde_json::Value)`:

| serde_json input | becomes | line |
| --- | --- | --- |
| `Null` | `Value::Nil` | `value.rs:53` |
| `Bool` | `Value::Bool` | `value.rs:54` |
| `Number` integral | `Value::Integer(i64)` (else `as_f64` → `Value::Float`, else `Nil`) | `value.rs:55-62` |
| `String` | `Value::String` | `value.rs:64` |
| **`Array`** | **`Value::Array(from_json each)`** | `value.rs:65-68` |
| **`Object`** | **`Value::Record(BTreeMap)`** — *unless* it has both `value`+`scale` keys → special-cased to `Value::Decimal` | `value.rs:69-97` |

So **`serde_json Array-of-Objects` → `Value::Array(Value::Record …)` = `Collection[Record]`** with no extra
machinery. The inverse `to_json` (`value.rs:101-132`) is symmetric (records → objects, decimals →
`{value,scale}`).

### 1.3 Where inputs are materialized at dispatch — and the key fact: **type-erased**

`IgniterMachine::dispatch(name, inputs: serde_json::Value)`:

```rust
let mut vm_inputs = HashMap::new();                         // machine.rs:327
if let Some(obj) = inputs.as_object() {
    for (k, v) in obj { vm_inputs.insert(k.clone(), VMValue::from_json(v)); }   // machine.rs:328-330
}
… execute(&compiled_contract, &vm_inputs, &temporal_context) …                  // machine.rs:346
Ok(output_val.to_json())                                                        // machine.rs:350
```

Each **top-level** input key is materialized via `from_json`. The machine **does not consult the contract's
declared input type** — materialization is fully driven by the JSON shape (Q2 answer: **input materialization
is type-erased**). The VM then looks references up by name (`vm.rs:309-317`,
`"Reference symbol '{}' not found in inputs or temporal context"`). The declared type
`Collection[TodoRow]` is enforced only at **compile time** by the typechecker.

This is the cleanest possible answer: there is **no type-directed materializer to build**, and none is
needed. The host emits the right JSON shape; `from_json` produces `Array(Record …)`; the typechecker has
already compiled `r.title`/`filter`/`map` against the declared row type.

### 1.4 The igniter-web continuation seam (where it stringifies today)

The read host runs the effect, then **flattens** the already-typed rows:

```rust
OutcomeKind::Succeeded => {
    let rows_json = serde_json::to_string(&outcome.result["rows"]) …            // read_dispatch.rs:111-116
    StagedReadResult::Rows(rows_json)                                          // read_dispatch.rs:117
}
```

and the dispatcher passes that **string** to the continuation:

```rust
input = json!({ "req": …, "rows_json": rows_json, "carry": carry });           // lib.rs:120-124
… self.machine.dispatch(&entry, input) …                                       // lib.rs:88
```

The rows it stringifies are *already typed serde values* (`postgres_read.rs:517-527`:
`"rows": Value::Array(rows)`, int/bool/json preserved per `postgres_read.rs:602-603`). **The only thing
between here and a `Collection[Record]` is the `to_string` call.** If `lib.rs:120` instead placed the rows
array under a `"rows"` key (structured, not stringified), `dispatch`→`from_json` (§1.3) would materialize
`rows : Value::Array(Value::Record …)`.

---

## 2. Is `Collection[Record]` crossing already possible? — split proof

**At the value substrate: YES (already).** §1.2 + §1.3 structurally guarantee `JSON array-of-objects →
Collection[Record]` through dispatch.

The two halves are each independently proven live; only their *join in one read path* is unexercised (that
is the gap):

- **Consumption of `Collection[Record]` + typed field access + HOFs runs green.**
  `apps/igniter-apps/query_engine` consumes `input rows : Collection[Row]` (`query_engine/execute.ig:21`,
  `eval.ig:74`) and does typed field access inside HOFs and helper contracts:
  `filter(rows, row -> … )` (`eval.ig:76`), `row.age`/`row.id`/`row.active`/`row.city`
  (`eval.ig:38,41,44,47`), `fold(preds, 1, (acc,p) -> acc * call_contract("MatchPredicate", row, p))`
  (`eval.ig:66-67`), and passing a record into `call_contract` (`eval.ig:38`). It is **green in the fleet
  sweep** (`runtime/igniter-machine/IMPLEMENTED_SURFACE.md:147-152`: 11/13, the only two blockers are
  `batch_importer` (`variant_construct` in `eval_ast`) and `web_router` (match-arm record literal) — **not**
  the `Collection[Row]` input). Fleet entry `("query_engine","RunQuery")` at
  `runtime/igniter-machine/tests/machine_tests.rs:215`.
  - *Caveat made explicit:* query_engine builds its rows in-language via `MakeRow` factories
    (`query_engine/example.ig:39-43`), so it proves *consumption*, not *host injection*.

- **Host-injected JSON object → `Value::Record` consumed in `.ig` runs live.**
  `req.body_json` crosses a host JSON object (`server/igniter-web/src/lib.rs:304-307`) and is read in `.ig`
  (`todo_handlers.ig:216` `map_get_string(req.body_json, "title")`). Per §1.1, `body_json`'s runtime value
  *is* a `Value::Record` — the same value an app-record input would receive. So host-JSON → Record → `.ig`
  access is already a live path; it differs from rows only in being one object vs an array of them.

**Conclusion:** every primitive needed (array→`Array`, object→`Record`, type-erased input materialization,
record field access, HOF-over-records, record-as-`call_contract`-arg) is individually proven live. What no
single test does **today** is inject a host JSON **array of objects** into `input rows : Collection[AppRow]`
and field-access it — exactly the smallest implementation card (§6).

---

## 3. Record field access semantics — and why the error surface is unstable

`r.field` has **three different missing-field behaviors depending on the VM path** — the load-bearing finding
for error ownership:

| Path | On present field | On **missing** field | On non-record | Cite |
| --- | --- | --- | --- | --- |
| `field_access`, `ref.field` fast path | returns the field | **returns the whole record** (silent) | falls through | `vm.rs:3881-3902` |
| `field_access`, general expr | returns the field | **errors** `record has no field '{}'` | **errors** | `vm.rs:3908-3916` |
| `OP_GET_FIELD` (bytecode) | returns the field | **errors** `field '{}' not found (available: …)` | **errors** | `vm.rs:2760-2772` |
| HOF-inlined accessors | returns the field | **returns `Value::Nil`** | n/a | `vm.rs:2667, 3080, 3118, 4891, 5117, 5179` (and `1611/1688/1757`) |

So a missing field can **error, return Nil, or return the whole record** depending on how the access is
compiled. A VM error becomes a dispatch `Err` → igniter-web host **500** (`lib.rs:88-94`). **This
inconsistency is the reason the stable error surface must be host-owned** (§5/§6): relying on VM field
errors gives an opaque, path-dependent failure surface unfit for a product taxonomy.

---

## 4. Mismatch / edge behavior (Q4), verified

| Case | Today's runtime behavior | Owner recommendation |
| --- | --- | --- |
| **Missing field** | path-dependent: error \| Nil \| record-passthrough (§3) | **Host** — materializer guarantees every declared field present (totality) |
| **Extra field** | harmless — structural access ignores unaccessed keys; typechecker only checks accessed fields against the declared type; `from_json` keeps all object keys | **Host** drops extras for cleanliness (cosmetic) |
| **Wrong scalar kind** (Bool expected, string supplied) | no error, **silently wrong**: `Value::String("true") == Value::Bool(false)` is `false` (distinct `Value` variants, derived `PartialEq`, `value.rs:6`) | **Host** — decode kind must equal the declared field type; host is the schema authority |
| **`null` for non-nullable** | `from_json(Null)` → `Value::Nil` (`value.rs:53`); a downstream `as_str`/string op on `Nil` → VM error → host 500 | **Host** — map SQL NULL to a declared default or refuse per projection spec |
| **Integer precision** | integral JSON → `Value::Integer(i64)`; out of `i64` → falls to `Value::Float` (or `Nil`) (`value.rs:55-62`) | **Host** — within `i64` exact; document the `i64` bound |
| **Decimal precision** | `PostgresReadValueKind::DecimalString` decodes to a JSON **string**; `from_json` → `Value::String`, **NOT `Value::Decimal`** (the `{value,scale}` special-case at `value.rs:82-91` needs an *object*, which Postgres does not emit) | **Host** — v0: declare the field `String`/`Text` (lossless on the wire); typed-Decimal via the latent `{value,scale}` bridge is a named follow-on |
| **Timestamp** | decodes to RFC3339 **string** (`postgres_read.rs:307-308`) → `Value::String` | **Host** — declare the field `String`/`Text` in v0 |

**Net:** for `String / Integer (≤ i64) / Bool / Json / Array` columns, host typed rows materialize correctly
with no language change. `Decimal` and `Timestamp` cross as **strings** in v0 (honest — they *are* strings on
the wire); a typed-Decimal projection is a deferred follow-on that already has a runtime landing pad
(`value.rs:82-91`).

---

## 5. The exact gap, and the proposed host materializer

**No VM/compiler gap.** The gap is entirely host-side, in the igniter-web read contour. Three small moves:

1. **Stop stringifying.** Add a structured staged-read result (e.g. `StagedReadResult::TypedRows(Value)`
   carrying the serde array) alongside the existing `Rows(String)`, so `read_dispatch.rs:111` no longer
   collapses the typed rows. The executor already hands them typed (`postgres_read.rs:520`).

2. **Cross rows under a structured input key.** In `dispatch_with_read` (`lib.rs:120-124`), place the rows
   array under `"rows"` (and the provenance sidecar under `"meta"`, per P1 §4) instead of `"rows_json"`.
   `from_json` then materializes `rows : Collection[Record]` (§1.3). The continuation declares
   `input rows : Collection[<AppRow>]`.

3. **A host materializer that aligns rows to a projection spec.** A pure host function:

   ```text
   materialize_rows(typed_rows: &[serde_json::Value], spec: ProjectionSpec) -> Result<Value, ReadError>
     spec = { field -> (declared_kind, nullable, default?) }   // derived from QueryPlan.projection
                                                                //  + PostgresReadPolicy.field_kinds (host already has both)
     for each row:
       - keep only projected fields (drop extras)
       - require every declared field present        → else ReadError::SchemaMismatch (stable)
       - map SQL NULL per nullability                → default | ReadError
       - Decimal/Timestamp → String (v0)             | {value,scale} object (typed-Decimal follow-on)
     → serde_json::Value::Array(objects)             // crossed structurally; from_json does the rest
   ```

   The host **already holds everything this needs**: the typed rows (`postgres_read.rs:520`), the field
   decode kinds (`PostgresReadPolicy.field_kinds`, `postgres_read.rs:328`), and the projected field list
   (`QueryPlan.projection`, `postgres_read.rs:56`). So the materializer is a host-side reshape with a stable
   error taxonomy — **no language, VM, compiler, Postgres, or `.igweb` change.**

This honors the P2 design bias: it proves the existing value substrate carries rows with a *small host
materializer*; it adds no JSON-parser DX to `.ig`, does not force `Map[String, Unknown]` for relational
reads, and invents no language feature.

---

## 6. Mismatch/error behavior recommendation

**Make the failure surface host-owned and stable; keep `.ig` rows total and typed.** Because VM field-access
errors are path-dependent and opaque (§3), the host materializer must validate *before* crossing and surface
a stable taxonomy, mirroring the existing read gates (P1 §6):

| Condition | Surfaced as | Consistent with |
| --- | --- | --- |
| Declared field missing from a row; kind undecodable | host **read error** (`SchemaMismatch`) → 503/permanent | `read_dispatch.rs` `HostError`, `lib.rs:133-136` |
| NULL for a non-nullable field with no default | host **read error** (or applied default) | same |
| Source/field/op not allowed; raw-SQL; bad predicate | already host `Denied`/`Permanent` (unchanged) | `postgres_read.rs:463-508` |
| Empty result set | **not an error** — app product decision (`200 []` vs `404`) | `todo_handlers.ig:344-357` |

Result: `.ig` only ever receives **total, well-typed `Collection[<AppRow>]`** — it never reaches the
inconsistent VM missing-field paths in normal operation. The VM's structural errors remain a safety net, not
the product error channel. That is "stable enough for P3."

---

## 7. Smallest implementation card

### `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6`

**Goal.** Cross a fake-Postgres read's typed rows into a continuation as `Collection[TodoRow]` (not a JSON
string) and prove `r.title` / `r.done` / `filter` / `map` / `call_contract` work as typed record operations.
DB-free, harness-only.

**Shape.**
- Host: `StagedReadResult::TypedRows(Value)` + a `materialize_rows(rows, spec)` reshape (§5); thread the
  result into the continuation input as `rows` (structured), not `rows_json`.
- App fixture: `type TodoRow { id: String, account_id: String, title: String, done: Bool }`; continuation
  `input rows : Collection[TodoRow]`.

**Acceptance tests** (sibling of `server/igniter-web/tests/todo_postgres_read_host_tests.rs`, fake adapter,
`--features machine`, no DB):
- [ ] `ListTodosByAccount → QueryPlan → fake PostgresReadExecutor → materialize_rows → continuation`, where
      the continuation declares `input rows : Collection[TodoRow]` and the body runs:
      `compute pending = filter(rows, r -> r.done == false)`,
      `compute titles = map(rows, r -> r.title)`,
      `compute n = count(pending)` — compiles and returns the expected typed results.
- [ ] A row with `done` as a **real Bool** and `id` as **String** survives: `r.done == false` selects
      correctly (not silently false), proving scalar kinds materialized (not all-string).
- [ ] `map(rows, r -> call_contract("TodoLabel", r))` runs (record passed to a contract) — the join to the
      proven `Collection[HtmlNode]` view path (P1 §7).
- [ ] **Mismatch is host-owned:** a fixture row missing a declared field → a **stable host read error**
      (not an opaque VM 500); a NULL field → declared default or stable error. Encodes §6.
- [ ] DB-free; no `.igweb`/compiler/VM/Postgres change; no canon claim; `git diff --check` clean.

**Out of scope (named follow-ons):** typed `Decimal`/`Timestamp` via the `{value,scale}` `from_json` bridge
(`value.rs:82-91`); the `DatasetMeta` provenance sidecar + read→HTML join (P1 card P3); nullability policy
config surface.

---

## Verification

```bash
rg -n "from_json|to_json|serde_json|Value::Record|Value::Map|Collection|dispatch\(" \
  lang/igniter-vm lang/igniter-compiler server/igniter-web runtime/igniter-machine \
  > /tmp/igniter-materialization-grep.txt      # 2230 hits

git diff --check                                # clean
```

No scratch experiment was run: each half of the crossing is proven live (§2) and the value substrate
structurally guarantees the join (§1), so a standalone harness would only duplicate the §7 acceptance test —
which the implementation card owns. No fixture or scratch file committed.

---

## Reporting

- **Feasibility verdict:** `small-gap`. The VM value substrate is already capable — `from_json` yields
  `Collection[Record]` (`value.rs:65-97`), dispatch materializes inputs through it type-erased
  (`machine.rs:327-330`), and record field access + HOFs over records run green (`query_engine`,
  `IMPLEMENTED_SURFACE.md:147-152`). No language/VM/compiler change needed for String/Integer/Bool/Json/Array.
- **Exact implementation gap:** host-side only — (1) stop stringifying at `read_dispatch.rs:111`; (2) cross
  rows under a structured `rows` input at `lib.rs:120`; (3) a host `materialize_rows(rows, spec)` reshape
  (the host already holds the typed rows + field kinds + projection). Decimal/Timestamp cross as `String`
  in v0 (typed-Decimal is a follow-on with a runtime landing pad at `value.rs:82-91`).
- **Why this avoids JSON-string / decoder DX:** the rows arrive as native `Value::Record`s the VM accesses
  with `r.field`/`map`/`filter` directly — no in-language JSON parser, no per-field `map_get_string`, no
  app-side decoder for host-owned relational reads. Decoders stay the lower-level fallback for untrusted
  input (P1 §5).
- **Next implementation card:** `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` (§7) — host materializer
  + typed continuation, DB-free, with host-owned mismatch taxonomy.
