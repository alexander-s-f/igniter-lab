# Lab: Dynamic Data Structures — JSON, Map, Record, Table, Boundary Research (v0)

**Card:** LAB-DYNAMIC-DATA-P1
**Track:** lab-dynamic-data-structures-json-map-table-research-boundary-v0
**Category:** lang / EXPERIMENTAL / LAB-ONLY / RESEARCH
**Status:** CLOSED — research complete
**Date:** 2026-06-09
**Authority:** lab-only — no grammar change, no compiler change, no canon claim, no stable surface

---

## Executive Summary

Igniter has real and growing pressure on dynamic data structures from multiple lab tracks:
Rack headers require `Map[String, String]`; Sidekiq JobReceipt is satisfied by named `Record`;
capability passports, ViewArtifacts, and telemetry receipts are boundary-only JSON artifacts,
not language values. The central finding of this research is a clean **three-tier hierarchy**:

1. **Named Record** (`type Foo { field: T }`) — covers most near-term needs. Known schema,
   static typechecking, compiler-verified at compile time. Proven via LAB-RACK-P12/P13,
   LAB-SIDEKIQ-P4. This is the *preferred path* for any data with a known fixed schema.

2. **Map[K, V]** with homogeneous value type — covers the dynamic-key remainder: HTTP headers,
   query params, cookie state, configuration tables. `Map[String, String]` is the immediate
   concrete need. This is in the ch3 grammar today but is NOT yet in the Stage 1 compiler-proven
   subset and has no stdlib operations proven for it.

3. **JsonValue as tagged sum** (`JsonNull | JsonBool | JsonNumber | JsonString | JsonArray |
   JsonObject`) — covers arbitrary JSON boundary deserialization. Required only at IO boundaries
   (request body parsing, external API responses). Should be a stdlib type, NOT a grammar
   primitive. Currently has zero language-level proof; should remain deferred.

**Table/DataFrame** is explicitly out of scope for Stage 1. It lives under Stage 2 OLAP
(`OLAPPoint[T,Dims]`, PROP-024) and is already reserved.

**The most immediate actionable gap** is `Map[String, String]` — needed for Rack headers
and proven in the schema design but not yet typechecked by the production compiler.

**Unknown must not become a dynamic escape hatch.** Every gap in the type system that
tempts the developer to reach for `Unknown` or `Any` is a design pressure to resolve — not
a design permission.

---

## 1. Current State of Data Types in Igniter

### 1.1 Type Grammar (ch3 §3.1)

The type grammar already names all relevant types. What exists at grammar level vs. what
is in the Stage 1 compiler-proven subset are two different things.

```
Type :=
    Integer | Float | String | Bool | Text | Decimal[N]        -- Stage 1 ✅
  | Record { f₁: T₁, ..., fₙ: Tₙ }                            -- Stage 1 ✅ (anonymous inline)
  | Variant { case₁: T₁ | ... | caseₙ: Tₙ }                    -- Stage 1 grammar, partial
  | Collection[T]                                               -- Stage 1 ✅
  | Option[T]                                                   -- Stage 1 ✅
  | Result[T, E]                                               -- Stage 1 ✅
  | Map[K, V]                -- derived from group_by           -- Stage 1 grammar only, NOT compiler-proven
  | Any                      -- top type, discouraged           -- grammar only, OOF at boundaries
  | ContractRef[In, Out]     -- contract as value               -- lab-proven (call_contract)
  | History[T], BiHistory[T] -- temporal                        -- Stage 2 reserved
  | OLAPPoint[T, Dims]       -- multidimensional               -- Stage 2 reserved (PROP-024)
```

**Named Records via `type` declaration** (distinct from inline `Record { ... }`) are proven
by LAB-RACK-P12/P13/LAB-SIDEKIQ-P4:

```igniter
type RackResponse {
  status: Integer,
  body:   String
}

type JobReceipt {
  job_class:        String,
  job_id:           String,
  attempt:          Integer,
  budget_remaining: Integer,
  status:           String
}
```

The Rust lab typechecker can validate `RecordLiteral` against a declared named type schema
and upgrade `Unknown → RackResponse` at compile time (P13 `check_record_literal_shape`).
This mechanism is lab-proven; it requires production promotion for canon.

### 1.2 Map[K, V] — Grammar vs. Reality

`Map[K, V]` appears in ch3 §3.1 as derived from `group_by`:

```
group_by(xs: Collection[T], fn: T → K) → Map[K, Collection[T]]
```

This means `Map[K, V]` has a legitimate origin as a *computed result type* from
`group_by`. It is NOT currently documented as a general-purpose associative array
that can be constructed via a literal syntax, looked up at runtime with dynamic keys,
or declared as a contract input/output with standalone semantics.

**What Map[K,V] is today (grammar-level only):**
- A result type of `group_by`
- Present in Rack shape docs as `headers: Map[String, String]` — but these are illustrative
  schema descriptions in the lab, not production compiler-verified annotations

**What Map[K,V] is NOT today:**
- A first-class creatable-via-literal type (no `{ "key" => value }` syntax)
- A type with proved lookup semantics and failure handling
- Part of the Stage 1 typechecked subset
- A production compiler feature with SemanticIR shape

### 1.3 Unknown — Compiler Uncertainty Marker

`Unknown` is a compiler-internal uncertainty marker, not a user-facing type:

- Appears when `infer_expr` cannot resolve a type (e.g., `RecordLiteral` before P13)
- Used in `Unknown-compat` rules to avoid cascading false-positive errors
- Propagated conservatively: `Unknown` output from one node does not block downstream nodes
- **Is not** a dynamic type, a type variable, or a dynamic-dispatch marker
- **Must not** be used as an escape hatch for "I don't know the schema"

The `Any` top type is the grammar-level analog. Both are discouraged at contract boundaries
(ch3 §3.9, Covenant Postulate 9). `Map[String, Any]` — which would be the naive mapping
for Rack's env hash — is explicitly identified as wrong in LAB-RACK-P1.

---

## 2. Pressure Source Analysis

### 2.1 Rack (HTTP framework)

| Need | Shape | Status | Gap |
|------|-------|--------|-----|
| HTTP status code | `Integer` | ✅ Stage 1 | None |
| HTTP body (static) | `String` or `Collection[String]` | ✅ Stage 1 | None |
| HTTP headers | `Map[String, String]` | ⚠️ grammar only | No production typechecking for Map[K,V]; no stdlib lookup ops |
| Query parameters | `Map[String, String]` | ⚠️ grammar only | Same as headers |
| Cookie/session state | `Map[String, String]` + `Store[T]` | ❌ blocked | Store[T] is Stage 2+; dynamic cookie parsing is not proven |
| Request body (JSON) | `JsonValue` or named `Record` | ❌ not designed | No JSON parser; named Record requires known schema |
| Named handler result | named `Record` (`RackResponse`) | ✅ P12/P13 | Production promotion needed |
| Route dispatch table | `Collection[RouteEntry]` | ✅ P4 | Proven as data shape |

**Immediate gap:** `Map[String, String]` for HTTP headers. RackResponse was deliberately
simplified to `{ status, body }` in P12 because headers require Map[K,V] support.

### 2.2 Sidekiq (Background jobs)

| Need | Shape | Status | Gap |
|------|-------|--------|-----|
| Job contract | named `Record` (inputs), named `Record` (receipt) | ✅ P4 | Production promotion needed |
| JobReceipt | `type JobReceipt { ... }` | ✅ P4 | Production promotion needed |
| Job descriptor (enqueue) | named `Record` or anonymous | ✅ data shape | No dynamic queue |
| Queue snapshot | `Collection[JobDescriptor]` | ✅ Collection[T] | Dynamic queue needs Store[T] |
| Retry policy budget | `BudgetedLocalLoop` / `max_steps` | ✅ P3 | — |
| Job failure taxonomy | named `Record` (e.g. `DeadJobReceipt`) | ✅ data shape | Not yet proved |
| Arbitrary metadata (annotations) | `Map[String, Any]` would be wrong | ❌ design gap | Needs named subtype per use case |

**Sidekiq pressure:** Named `Record` covers all concrete needs. The only gap is annotations
or tags that vary per job type — these should be typed per job schema, not collapsed into
`Map[String, Any]`.

### 2.3 Capability Passports

| Need | Shape | Status | Gap |
|------|-------|--------|-----|
| Passport JSON artifact | JSON file format | ✅ lab-only | Boundary artifact; not a language value |
| `required_capabilities` section | `Map[String, CapabilitySpec]` conceptually | ❌ lab artifact only | Capability bindings are lab-emitted JSON, not Igniter values |
| Capability binding keys | dynamic strings | lab-only | Named parameters preferred over Map |
| `sandbox_policy_source` | String enum | lab-only | Not a language value |

**Capability passport pressure:** Zero pressure on language data structures. Passports
are boundary artifacts (JSON files) read by the runtime loader, not values that flow
through contracts. The `required_capabilities` dict in the passport has dynamic string
keys (capability names) but this is an artifact schema, not a contract type.

The correct design, if capability authority ever needs to be a language value (e.g., passed
as a contract input), is a named `Record` per capability kind — not a Map.

### 2.4 Telemetry / Proof Receipts / Manifests

| Need | Shape | Status | Gap |
|------|-------|--------|-----|
| SemanticIR | JSON file format | ✅ emitter | Not a language value |
| Compilation report | JSON file format | ✅ emitter | Not a language value |
| Capability passport | JSON file format | ✅ lab-only | Not a language value |
| Proof summary | JSON file format | Lab | Not a language value |
| PROP-038 compiler manifest | JSON file format | partial-impl | Not a language value |

**Telemetry/receipt pressure:** All current telemetry, receipts, and manifests are JSON-encoded
**boundary artifacts** — they're files written by the compiler and read by external tooling.
They are not Igniter values flowing through contracts. There is therefore **zero pressure
from telemetry/receipts on language data structure design** today.

If future contracts are designed to PRODUCE receipts as typed contract outputs (which Covenant
Postulate 8 suggests is the correct long-term shape), named Records are the right answer — not
JSON maps.

### 2.5 ViewArtifact / SiteArtifact / GUI Artifacts

| Need | Shape | Status | Gap |
|------|-------|--------|-----|
| View artifact JSON | JSON file format | ✅ lab IDE | Boundary artifact; not a language value |
| Slot schema in artifact | `{ slot_name: { contract_ref, ... } }` | lab-only | Map-like in JSON, but lab artifact |
| `slot_values` in trace | Dynamic string keys → values | lab-only | Map[String, T] conceptually |
| ViewArtifact digest/id | String fields | lab-only | Strings only |

**View artifact pressure:** The slot-binding model (`slot_values: Map[String, T]`) creates
latent pressure on `Map[String, T]` but these are currently bridge/adapter patterns in the
IDE lab code — they are Ruby/Rust structures, not Igniter language values. If slot binding
ever moves into the language layer (a view contract that declares `slot_values: Map[String,
Text]`), this becomes concrete. Not today.

### 2.6 Future Web Framework

| Need | Shape | Gap |
|------|-------|-----|
| Route parameters (`:id`) | `Map[String, String]` or named Record | Proven as static in P4; dynamic params → Map gap |
| JSON API request body | `JsonValue` → named Record via boundary decoder | No decoder; no JsonValue stdlib |
| JSON API response body | named Record serialized to JSON | No serializer |
| Form data | `Map[String, String]` (flat) or `Map[String, Collection[String]]` (multi) | No stdlib form parser |
| GraphQL / JSON:API schemas | Variant{} + named Record | Grammar present; no proven stdlib |

---

## 3. Taxonomy Matrix

### 3.1 Record (Named, Fixed-Schema)

| Dimension | Detail |
|-----------|--------|
| **Grammar** | `type Name { field: T, ... }` (named); `Record { field: T }` (anonymous inline) |
| **Semantics** | Fixed field set, known at compile time. Width and depth subtyping. |
| **Stage 1 proven** | Named Record via LAB-RACK-P12/P13, LAB-SIDEKIQ-P4 (lab). Production promotion pending. |
| **Typechecking** | Nominal (P13): `check_record_literal_shape` validates presence, absence, and type of fields. RecordLiteral upgrades from Unknown → named type. |
| **Failure mode** | Missing/extra fields → OOF-TY0 at compile time. Wrong field type → OOF-TY0. Field expressions → Unknown-compat if complex. |
| **Lookup** | Static field access `record.field_name` (Rule 3, ch3 §3.3). Dynamic key lookup not supported. |
| **Authority** | Lab-proven; production promotion is the next route. |
| **Use for** | JobReceipt, RackResponse, HttpRequest, capability specs, any known-schema data |
| **Closed surfaces** | Open-ended anonymous field sets; dynamic key-based field access; schema inference |

### 3.2 Map[K, V] (Dynamic-Key, Homogeneous-Value)

| Dimension | Detail |
|-----------|--------|
| **Grammar** | `Map[K, V]` — ch3 §3.1 |
| **Origin** | Currently: result of `group_by`. Latent: general associative array. |
| **Stage 1 proven** | ❌ NOT in Stage 1 typechecked subset. In grammar but not compiler-proven. |
| **Semantics** | Dynamic key set at runtime; all values homogeneous type V. Keys type K. |
| **Lookup failure semantics** | Correct answer: `Option[V]`. NOT `Unknown`. NOT runtime error. NOT `Any`. |
| **Literal syntax** | Not designed. No `{ "key" => value }` or `map { k: v }` form exists today. |
| **Construction** | Currently: only via `group_by(collection, key_fn)`. No direct literal. |
| **SemanticIR** | No `map_literal_node` or `map_lookup_node` kind exists today. |
| **Stdlib ops** | No `stdlib.map.*` exists. `get(m, k) → Option[V]` not implemented. |
| **Use for** | HTTP headers, query params, environment variables, configuration tables |
| **Closed surfaces** | `Map[String, Any]` (heterogeneous values); map mutation (Ref[T]); Map as dynamic Record substitute |
| **Design locks needed** | Literal syntax; lookup → Option[V] semantics; stdlib ops; SemanticIR node kind |

### 3.3 JsonValue (Boundary Tagged Sum)

| Dimension | Detail |
|-----------|--------|
| **Grammar** | NOT in grammar. Not a language primitive. |
| **Correct shape** | Tagged sum type: `JsonNull \| JsonBool \| JsonNumber \| JsonString \| JsonArray[JsonValue] \| JsonObject[String, JsonValue]` |
| **Use case** | Boundary deserialization: raw HTTP/JSON body → JsonValue → typed Record via decoder contract |
| **Stdlib placement** | Should be a stdlib type if needed, NOT a grammar primitive. `stdlib.json.*` module. |
| **Overlap with Map[K,V]** | `JsonObject` is `Map[String, JsonValue]` — but only at JSON boundaries. Do NOT conflate `Map[String, String]` with `JsonObject` inside contracts. |
| **Pressure level** | Real but not immediate. No JSON parser exists in the lang or lab stdlib today. |
| **Prerequisite** | `Map[K, V]` must be designed first. `Collection[T]` already exists (used as `JsonArray` base). |
| **Risk** | If introduced prematurely, becomes a "JSON escape hatch" that lets every untyped value flow through the language as `JsonValue`. |
| **Authority** | ❌ Deferred. No PROP, no grammar, no stdlib. |
| **Closed surfaces** | Using `JsonValue` as a contract-internal value type; `Map[String, JsonValue]` as an internal record substitute |

### 3.4 Collection[T] (Ordered, Finite, Bounded, Homogeneous)

| Dimension | Detail |
|-----------|--------|
| **Grammar** | `Collection[T]` — Stage 1 ✅ |
| **Semantics** | Finite, bounded at classification time. Homogeneous element type. No index access (only fold/map/filter/first/last). |
| **Use for** | HTTP response body chunks, ordered sequences, job queues (data-plane snapshot), list of route entries |
| **NOT for** | Key-value pairs (use Map[K,V] or Collection[Record{key, value}]); tables (use OLAPPoint); unbounded streams (Stage 2) |
| **vs. List[T]** | No distinct `List[T]` type exists or is needed. Collection[T] IS the list/array type. |
| **vs. Vector[T]** | No `Vector[T]` type. Not needed — Collection[T] is index-free and that's by design (prevents unbounded random access). |
| **Open question** | Should Collection[T] support index access `xs[n] → Option[T]`? Currently: no. Deliberate: bounds checking at the type level would require refinement types (Stage 2). |

### 3.5 Table / DataFrame

| Dimension | Detail |
|-----------|--------|
| **Grammar** | NOT a language type. OLAPPoint[T,Dims] is Stage 2 reserved (PROP-024, ch9). |
| **Correct analogy** | `OLAPPoint[T, { dim₁: D₁, ..., dimₙ: Dₙ }]` is the column-oriented, schema-bearing table. |
| **Row-oriented** | A row is a named Record. A row-oriented table is `Collection[RowRecord]` — expressible today! |
| **Column-oriented** | Requires `OLAPPoint[T, Dims]` — Stage 2. |
| **DataFrame** | A DataFrame is conceptually a column-oriented table with named typed columns — maps to `OLAPPoint`. |
| **Schema validation vs. typechecking** | Typechecking of table schemas requires Stage 2 (`OLAPPoint` dimensions as type-level params). Runtime-only schema validation would be a design violation (Covenant Postulate 1). |
| **Lab-only OLAP layer** | OLAP is NOT lab-only — it is formally specified (PROP-024) and Stage 2. Do NOT design a competing lab-only table/DataFrame mechanism. |
| **Authority** | ❌ Stage 2 reserved. Close for Stage 1. |

### 3.6 Unknown (Compiler Uncertainty Marker — NOT a Data Type)

| Dimension | Detail |
|-----------|--------|
| **Nature** | Internal compiler state. Not a language value. Not a runtime type. |
| **Correct use** | When the TypeChecker cannot resolve a type (unresolved RecordLiteral, complex expression). |
| **Unknown-compat rule** | Downstream checks accept Unknown on either side to avoid false positives (OOF cascade prevention). |
| **What it must NOT become** | A user-facing dynamic type (`output x: Unknown`). A substitute for `Option[T]`. A Map lookup result. A workaround for missing Map[K,V]. |
| **Design pressure** | Every `Unknown` in production IR is either (a) a resolved type that the compiler just doesn't know yet → fix the typechecking, OR (b) a genuine schema-unknown that requires an explicit `Option[T]`, `Result[T,E]`, or `Any` boundary declaration. |

---

## 4. Key Questions — Answers

### Q1: Should JSON be a first-class Igniter value, or only a boundary artifact format?

**Answer: Only a boundary format, until a concrete need for `JsonValue` as a language value
is proven.**

All current JSON in the Igniter ecosystem is either:
- A compiler-emitted artifact (SemanticIR, compilation report, capability passport, manifests)
- A lab tool format (proof summaries, trace receipts)
- A proposed boundary encoding (HTTP request body — not yet implemented)

None of these require JSON to be a language value that flows through contracts. The correct
design is: typed Records for known schemas; `JsonValue` tagged sum (stdlib) only at
deserialization boundaries where the schema is genuinely unknown until runtime.

Using JSON as an escape hatch inside contracts — passing `{ "status" => 200, "body" => "ok" }`
as an untyped map — violates Axiom 1 (Honesty) and Postulate 9 (Authority Is Explicit).

### Q2: Should `JsonValue` be a tagged sum type, a stdlib type, or deferred?

**Answer: A stdlib type when needed, deferred until then.**

`JsonValue` SHOULD be a tagged sum if it ever becomes a language type:
```
JsonValue :=
    JsonNull
  | JsonBool(Bool)
  | JsonNumber(Decimal[9])         -- arbitrary precision; JSON number range
  | JsonString(Text)
  | JsonArray(Collection[JsonValue])
  | JsonObject(Collection[JsonField])   -- where JsonField = { key: Text, value: JsonValue }
```

Note: `JsonObject` is NOT `Map[String, JsonValue]` — JSON objects may have duplicate keys
(spec-technically), and key order is meaningful in some parsers. Using
`Collection[JsonField]` preserves these semantics without requiring Map[K,V] first.

But this should only be introduced when a concrete `stdlib.json.parse(text: Text) → Result[JsonValue, Text]`
use case is ready. Today, no such use case is proven.

### Q3: Do we need `Map[String, T]` before `JsonObject`?

**Answer: Yes — `Map[String, String]` for headers is more urgent than JsonValue.**

`Map[String, String]` is needed for HTTP headers, query parameters, cookie keys, and environment
variables. These are homogeneous-value string maps — a much simpler type than `JsonObject`.
`JsonObject` can wait for the `JsonValue` stdlib. `Map[String, String]` cannot.

### Q4: Can named `Record` cover most near-term needs better than JSON?

**Answer: Yes, for all cases where the schema is known.**

Named `Record` covers:
- HTTP responses (RackResponse — proven)
- Job receipts (JobReceipt — proven)
- HTTP requests (HttpRequest — shape-proven in lab)
- Capability specs (CapabilitySpec — lab artifacts only)
- Route entries, middleware descriptors, any domain model

Named `Record` does NOT cover:
- Dynamic-key data like HTTP headers → needs `Map[String, String]`
- Unknown-schema external data → needs `JsonValue` at boundary

### Q5: What is the minimum data structure needed for Rack headers?

**Answer: `Map[String, String]`.**

Headers have dynamic keys (determined by the HTTP client), homogeneous string values, and
case-insensitive key lookup semantics. The minimum required shape is `Map[String, String]`
with a `get(m: Map[String, String], k: String) → Option[String]` stdlib operation.
Case normalization is a stdlib concern, not a type system concern.

### Q6: What is the minimum data structure needed for Sidekiq JobReceipt?

**Answer: Named `Record` — already proven.**

`type JobReceipt { job_class: String, job_id: String, attempt: Integer, budget_remaining: Integer, status: String }`
is fully proven by LAB-SIDEKIQ-P4. No dynamic data structures needed.

### Q7: What is the minimum data structure needed for capability passports?

**Answer: None — passports are boundary artifacts, not language values.**

The passport JSON schema (`required_capabilities`, `capability_bindings`, etc.) is a file
format read by the VM loader. It does not need to be a language value. If capability authority
ever needs to flow through contracts as a value, it should be modelled as named Records
(e.g., `type NetworkCapabilitySpec { ...fields... }`) — NOT as a `Map[String, JsonValue]`.

### Q8: Should tables/data frames be part of core language, stdlib, or lab-only OLAP layer?

**Answer: Stage 2 (OLAPPoint). Not core language, not stdlib, not lab-only.**

PROP-024 (`OLAPPoint[T, Dims]`) is the fully specified design for multidimensional data.
Tables and DataFrames are special cases of OLAPPoint. Row-oriented "tables" (`Collection[RowRecord]`)
are expressible today and should be used where needed. Column-oriented / schema-indexed
DataFrames require Stage 2 and should not be designed around prematurely.

Introducing a competing "lab-only DataFrame" concept would create a design fork that
complicates Stage 2 OLAPPoint adoption. Hold.

### Q9: What failure semantics should lookup use?

**Answer: `Option[T]` for Map[K,V] runtime lookup; OOF at compile time for Record.**

| Lookup type | Failure semantic | Why |
|-------------|-----------------|-----|
| `record.field` (known field) | No failure — static check; OOF-TC2 if field missing | Field set is fixed at type-definition time |
| `record.field` (unknown field) | OOF-P1 (TypeChecker) | Compile-time rejection; not a runtime question |
| `map.get(key) → Option[V]` | `None` on missing key | Key set is dynamic; caller must handle absence |
| `map.get(key) → Unknown` | **WRONG** — Unknown is compiler state, not domain state | Would conflate compiler uncertainty with runtime absence |
| `map.get(key) → runtime error` | **WRONG** | Violates Postulate 1 (declared dependencies); caller has no static signal |
| `map.get(key) → default_value` | **WRONG as a primary path** | Hides missing-key case; use `or_else(map.get(k), default)` |

The correct pattern in Igniter:
```igniter
compute content_type = or_else(get(headers, "content-type"), "application/octet-stream")
```

Where `get(headers, "content-type") → Option[String]` is explicit about the absent case.

### Q10: What should stay explicitly closed before v1?

| Surface | Status | Reason |
|---------|--------|--------|
| `Any` as user-visible type | **CLOSED** | Violates Axiom 1; undermines all typechecking |
| `Map[String, Any]` | **CLOSED** | Heterogeneous values; bypasses accountability |
| `JsonValue` as grammar primitive | **CLOSED** | Should be stdlib type when needed; not core grammar |
| Dynamic field access on Record | **CLOSED** | Records have static field sets; dynamic access → Map |
| `Table`/`DataFrame` as Stage 1 type | **CLOSED** | Stage 2 (OLAPPoint) |
| `Ref[T]` outside ESCAPE | **CLOSED** | Mutable references break Postulate 5 |
| Runtime-only schema validation | **CLOSED** | Schemas that can't be checked at compile time are drift risks |
| `Unknown` as user-declared output type | **CLOSED** | Compiler state only |
| `Collection[T]` with index access `xs[n]` | **CLOSED** | Bounds checking requires refinement types; Stage 2 |
| `Map[String, Any]` as passport/receipt value | **CLOSED** | Lab artifacts stay as boundary JSON files |

---

## 5. Risk Matrix

### R1: Dynamic Escape Hatch (Critical)

**Trigger:** Any of these patterns appear in a contract:
- `output x: Map[String, Any]`
- `output x: Unknown`  
- `compute x = json_parse(raw_body)` where result is untyped

**Risk:** Once `Any` or an untyped Map appears in a contract output, the accountability chain
breaks. Downstream contracts cannot verify what they receive. Receipts become unauditable.

**Mitigation:** The type system must reject `Any` at contract boundaries (ch3 §3.9 already
states this). `JsonValue` as a stdlib type is acceptable ONLY at the outermost boundary — the
parsing contract `parse_json(text: Text) → Result[JsonValue, Text]` — not as a pass-through
type inside domain contracts.

### R2: Schema Drift (High)

**Trigger:** Runtime-only schema validation: a contract accepts `Map[String, String]` where
a named Record is correct, and the key set varies over time.

**Risk:** If the schema is not fixed at compile time, field additions/removals are invisible
to the compiler. The contract accepts any string-keyed map, which means refactoring field
names produces no compile errors.

**Mitigation:** Prefer named Records for any schema that is known at design time. Use Map[K,V]
ONLY when the key set is genuinely dynamic at runtime (HTTP headers, query params). Never use
Map[K,V] to avoid the work of defining a named Record schema.

### R3: Runtime-Only Validation (Medium)

**Trigger:** Designing a `validate_json(value: JsonValue, schema: Map[String, String]) → Result[T, Text]`
where `T` is only known at runtime.

**Risk:** This is a runtime schema registry — the compile-time typechecker has no information
about the schema. It violates Postulate 1 (declared dependencies) and makes contracts
non-auditable at compile time.

**Mitigation:** If JSON boundary decoding is needed, the decoding contract must have a
statically-known output type: `parse_http_request(raw: Text) → Result[HttpRequest, Text]`.
Generic JSON validators with runtime schemas are ESCAPE-tier and must be explicitly labelled.

### R4: Overfitting to JSON (Medium)

**Trigger:** Designing the language data model to mirror JSON semantics:
- No distinction between `null` and `None`
- Numbers are `Decimal[arbitrary]` not `Integer | Float | Decimal[N]`
- All objects are `Map[String, Any]`

**Risk:** JSON semantics are deliberately underspecified (duplicate keys, number precision,
null ambiguity). Fitting Igniter types to JSON semantics would inherit those ambiguities.

**Mitigation:** `JsonValue` as a boundary type is correct. `JsonValue` as a domain type is
wrong. The mapping JSON → Igniter typed values must be explicit and lossy where needed (e.g.,
`JsonNumber → Integer` may fail; that failure is a `Result[Integer, Text]`).

### R5: Premature Table/DataFrame Scope (Low)

**Trigger:** Creating a lab-only `Table` or `DataFrame` mechanism that pre-empts Stage 2
OLAPPoint design.

**Risk:** Two competing column-oriented data models. The lab DataFrame accumulates usage
and becomes a de facto standard that conflicts with the formally specified OLAPPoint.

**Mitigation:** Row-oriented `Collection[RowRecord]` is available today and covers most
tabular data needs in Stage 1. Explicitly defer all column-oriented/schema-indexed table
work to Stage 2. Do not design a lab DataFrame.

### R6: Map as Record Substitute (Medium)

**Trigger:** Using `Map[String, T]` where a named Record would be correct because naming
the fields seems like "too much ceremony."

**Risk:** Map[String, T] has no field documentation, no compile-time field-name checking,
no type differentiation between fields. A `Map[String, String]` containing `{ job_id, job_class,
status }` is structurally identical to a map containing `{ foo, bar, baz }`.

**Mitigation:** Any map where the keys are known at design time should be a named Record.
The only legitimate Map[String, T] is one where the keys are NOT known at design time (HTTP
headers, query params, environment variables, user-defined configuration tables).

---

## 6. Compact Taxonomy Matrix

| Type | Grammar | Stage 1 | Proven | Near-term | Lookup failure | Closed surfaces |
|------|---------|---------|--------|-----------|----------------|-----------------|
| `Record { f: T }` (anonymous inline) | ✅ | ✅ | ✅ partial | Yes — known schemas | OOF-TC2 at compile time | Dynamic key access |
| `type Name { f: T }` (named) | ✅ | ✅ lab | ✅ P12/P13 | Yes — receipts, responses | OOF-TY0 at compile time | Same |
| `Map[K, V]` | ✅ grammar | ❌ not proven | ❌ | Yes — headers, params | `Option[V]` (design intent) | `Map[String, Any]`; Map as Record |
| `Collection[T]` | ✅ | ✅ | ✅ | Yes — lists, sequences | `Option[T]` via first/last | Index access; unbounded streams |
| `Option[T]` | ✅ | ✅ | ✅ | Yes — nullable fields, lookup | `None` | Discarding `None` silently |
| `Result[T, E]` | ✅ | ✅ | ✅ | Yes — parse results, IO | `Err(E)` | Unwrapping without match |
| `JsonValue` (tagged sum) | ❌ | ❌ | ❌ | Latent | `Result[T,E]` via decode | Use inside domain contracts |
| `Table` / `DataFrame` | ❌ | ❌ Stage 2 | ❌ | No (Stage 2+) | OLAPPoint design | Any Stage 1 impl |
| `Unknown` | ❌ (internal) | compiler only | — | No — internal only | N/A | User-declared type |
| `Any` | ✅ grammar | ❌ discouraged | — | No — OOF at boundaries | N/A | Contract I/O |

---

## 7. Compact Pressure-Source Matrix

| Source | Named Record | Map[K,V] | JsonValue | Collection | Option/Result | Closed |
|--------|-------------|----------|-----------|------------|---------------|--------|
| **Rack / HTTP** | ✅ RackResponse, HttpRequest | 🔴 headers, query_params | 🟡 body JSON parsing | ✅ body chunks | ✅ Option[String] fields | dynamic env hash |
| **Sidekiq** | ✅ JobReceipt, job descriptor | none today | none today | ✅ job queue | ✅ Option fields | dynamic metadata map |
| **Capability passports** | 🟡 CapabilitySpec (future lang value) | none (boundary JSON) | none (boundary JSON) | none | none | All passport data stays boundary-only |
| **Telemetry / receipts** | 🟡 future: typed contract receipts | none today | none today | none today | none | All current receipts are boundary JSON files |
| **ViewArtifact / IDE** | 🟡 slot schema | 🟡 slot_values (latent) | none today | none today | none | Language-level view types deferred |
| **Future web framework** | ✅ route entries, domain models | 🔴 route params, form data | 🔴 JSON API | ✅ collections | ✅ Results | runtime-only validation |

Legend: ✅ satisfied today | 🔴 real gap | 🟡 latent / future pressure | none = no current pressure

---

## 8. Next Route Recommendation

### Priority 1 (Immediate): Map[K, V] Design Lock

**What:** Nail down the semantics of `Map[K, V]` as a first-class Stage 1 type.
Specific decisions needed:
1. Literal syntax: `{ "key" => value, ... }` or `map { k: v, ... }` or `from_pairs(...)` ?
2. Lookup: `get(m: Map[K, V], k: K) → Option[V]`
3. Construction: `from_pairs(Collection[{ key: K, value: V }]) → Map[K, V]` or direct literal
4. Mutation: **CLOSED** — Map[K,V] is immutable. `with_entry` returns a new Map.
5. SemanticIR node kind: `map_literal_node`, `map_lookup_node`
6. Stdlib module: `stdlib.map.*`

**Concrete driver:** `headers: Map[String, String]` for RackResponse — remove the P12 deferral.

**Proposal route:** PROP-043 or folded into PROP-041 errata? Given that Map[K,V] is in ch3
grammar already and its semantics interact with the typechecker and SemanticIR, a new PROP
(PROP-043) is cleaner.

### Priority 2 (Near-term): Named Record Production Promotion

**What:** Promote LAB-RACK-P12/P13 nominal record typechecking from lab Rust to production
lang compiler. This closes the gap between `type RackResponse { ... }` being lab-proven
and being a first-class production feature.

**Requires:** PROP (amendment to PROP-004 ch3 type grammar, or new PROP for named type
declarations), then production compiler edits (requires P4/P5 authorization).

**Note:** Named `type` declaration is already in the Igniter grammar (experiments
typechecker_proof uses it). The lab has proven the typechecking mechanism. The promotion
is mostly about documenting the canon surface and protecting it against drift.

### Priority 3 (Deferred): JSON Boundary Design

**What:** Design `stdlib.json.*` with:
- `JsonValue` tagged sum type (grammar or stdlib)
- `parse(text: Text) → Result[JsonValue, Text]`
- `decode_as(value: JsonValue, decoder: T) → Result[T, Text]` (boundary-only)

**Gate:** Requires concrete use case: an Igniter contract that receives an HTTP request body
as `Text` and must decode it to a named Record. This does not exist yet even in the lab.

**Risk to manage:** Once JsonValue exists, it will be tempting to use it inside domain
contracts. The stdlib module must explicitly document the "boundary-only" design intent.

### Priority 4 (Hold): Table / DataFrame

**What:** Row-oriented tables (`Collection[RowRecord]`) are available today and sufficient
for Stage 1. Column-oriented / schema-indexed tables are Stage 2 OLAPPoint (PROP-024).

**Action:** No new design work needed. Use `Collection[RowRecord]` for tabular data in Stage 1.
Do NOT create a lab-only DataFrame mechanism.

### Decision Matrix Summary

| Route | Priority | Trigger | Risk if delayed |
|-------|----------|---------|-----------------|
| Map[K,V] design lock (PROP-043) | 🔴 Immediate | Rack headers deferred in P12 | Headers stay `Unknown` in RackResponse; incomplete Rack type model |
| Named Record production promotion | 🟡 Near-term | P12/P13 lab-proven, not production | Two codebases diverge on record typechecking; lab evidence doesn't transfer |
| JSON boundary stdlib (PROP-044?) | 🟢 Deferred | No concrete need yet | Low risk; no HTTP body parsing use case proven |
| Table/DataFrame | ⚪ Hold | Stage 2 gate | None — OLAPPoint is the right vehicle |

---

## 9. Explicitly Closed Surfaces

These surfaces are named here to prevent them from being opened by accident in future lab
work. Each is closed for a specific design reason, not arbitrary restriction.

| Surface | Closed because |
|---------|---------------|
| `output x: Any` | Violates Axiom 1 — breaks accountability chain |
| `Map[String, Any]` | Heterogeneous values defeat typechecking |
| `Map` with mutable update semantics | Violates Postulate 5 — outputs are immutable values |
| Dynamic key access on Record (`record[dynamic_key]`) | Records have static field sets — use Map for dynamic keys |
| `JsonValue` as contract-internal domain type | JSON semantics are underspecified; use named Records for domain values |
| Runtime-only schema validation | Violates Postulate 1 — schema must be declared, not discovered |
| `Table` / `DataFrame` as Stage 1 type | Stage 2 (OLAPPoint); premature introduction creates design fork |
| `Unknown` as user-declared type annotation | Internal compiler state |
| `Collection[T]` with integer index access | Requires refinement types; Stage 2 |
| `null` as a language value (distinct from `None`) | `Option[T]` is the correct nullable representation; `null` is not an Igniter value |
| `Map[String, Any]` as receipt/passport schema value | Boundary artifacts stay as JSON files; not language values |

---

## References

| Document | Location | Relevance |
|----------|----------|-----------|
| Ch3 Type System (PROP-004, PROP-021) | `igniter-lang/docs/spec/ch3-type-system.md` | Type grammar, Map[K,V] grammar position, Any discouraged |
| Ch8 Stdlib (PROP-013) | `igniter-lang/docs/spec/ch8-stdlib.md` | Collection[T] ops, group_by → Map origin, stage 2 deferred |
| Ch9 Stage 2 Reserved (PROP-022–025) | `igniter-lang/docs/spec/ch9-stage2-reserved.md` | OLAPPoint[T,Dims], History[T], fold_stream — deferred |
| Language Covenant | `igniter-lang/docs/language-covenant.md` | Postulates 1, 5, 8, 9 — relevant to data structure design |
| LAB-RACK-P2: Core shapes | `igniter-lab/lab-docs/lang/lab-rack-core-contract-shape-and-pipeline-proof-v0.md` | Map[String,String] headers gap identified |
| LAB-RACK-P12: Typed response | `igniter-lab/lab-docs/lang/lab-rack-typed-response-dispatch-v0.md` | RackResponse without headers (Map deferred) |
| LAB-RACK-P13: Nominal record TC | `igniter-lab/lab-docs/lang/lab-rack-nominal-record-typechecking-v0.md` | Named Record typechecking proven |
| LAB-RACK-P1: Feasibility | `igniter-lab/lab-docs/lang/lab-igniter-rack-reimplementation-feasibility-v0.md` | Map[String,Any] rejected; Map[String,String] identified |
| LAB-SIDEKIQ-P1: Feasibility | `igniter-lab/lab-docs/lang/lab-sidekiq-reimplementation-feasibility-and-language-pressure-map-v0.md` | Named Record for JobReceipt identified |
| LAB-SIDEKIQ-P4: JobReceipt | `igniter-lab/lab-docs/lang/lab-sidekiq-jobreceipt-schema-proof-v0.md` | Named Record proven for receipts |
| LAB-STDLIB-IO-P7: Passport schema | `igniter-lab/lab-docs/stdlib/lab-experimental-io-capability-passport-schema-generalization-v0.md` | Passports as boundary JSON artifacts, not language values |
