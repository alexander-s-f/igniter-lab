# LAB-RECORD-MAP-P1: Record / Map[String,V] Bridge Proof — v0

**Track:** `lab-record-map-bridge-field-and-map-lookup-proof-v0`
**Status:** CLOSED / PROVED — 51/51 PASS
**Date:** 2026-06-09
**Depends on:** LAB-RECORD-VM-P1, LAB-RECORD-VM-P2, LAB-RECORD-VM-P3, PROP-043-P3, PROP-043-P4

---

## 1. Goal

Prove the lab-only bridge between typed Records and the proof-local `Map[String,V]` model:
records with map-typed fields, map lookup through record fields, and fail-closed behavior for
unresolved or ill-typed map access — without creating canon, runtime-stable, public API, JSON,
or mutable map authority.

---

## 2. Finding: Two-Layer Gap

**The bridge is proved in two layers with a clear gap at map lookup.**

### Layer A — Production Rust Compiler

The production Rust compiler (`igniter-lab/igniter-compiler`) handles the record side cleanly:

| What | Finding |
|---|---|
| `Map[String,String]` field in named record | ✅ Compiles — `FullRackResponse`, `JobEnvelope` |
| SIR: Map params preserved in record field declarations | ✅ `type_ref: {name: Map, params: [String, String]}` |
| SIR: Field access on Map-typed field preserves params | ✅ `response.headers → Map[String,String]` (params intact!) |
| Tier 1 callee resolution through Map-typed record | ✅ `envelope: FullRackResponse`; `hdrs: Map[String,String]` |
| Tier 2 + map field access | ✅ FAIL-CLOSED — OOF-P1 `Unknown.headers` |
| `map_get(response.headers, key)` | ❌ BLOCKED — `Unknown function: map_get` |
| C1 (wrong map params in record field) | ❌ NOT CAUGHT — `Map[String,Integer]` as `Map[String,String]` field |
| OOF-MAP1 (non-String key) | ❌ NOT ENFORCED — Rust compiler accepts `Map[Integer,String]` |
| OOF-MAP2 (`Map[String,Any]`) | ❌ NOT ENFORCED — Rust compiler accepts it |

**Surprising finding**: The Rust compiler correctly preserves `Map[String,String]` params through
field access in the SIR. This is better than the Ruby MapPipeline (C1), and means the type
metadata bridge is structurally sound at the SIR level.

### Layer B — Ruby MapPipeline (PROP-043 proof-local extension)

The Ruby MapPipeline (`igniter-lang/experiments/prop043_map_kv_proof/`) handles map_get cleanly
for direct Map inputs:

| What | Finding |
|---|---|
| `map_get(headers_input, key)` where `headers : Map[String,String]` | ✅ `Option[String]` |
| `or_else(Option[String], default)` | ✅ `String` |
| `map_get(response.headers, key)` via record field | ❌ C1 — `Option[Unknown]` |
| OOF-MAP1 (Integer key) | ✅ Fires in MapPipeline |
| OOF-MAP2 (`Map[String,Any]`) | ✅ Fires in MapPipeline |
| OOF-MAP3 (`Map[String,Unknown]` in output) | ✅ Fires in MapPipeline |

### Layer C — VM Runtime

| What | Finding |
|---|---|
| `Map[String,String]` as contract input (JSON object) | ✅ Accepted and stored |
| `record.map_field` field access returns map value | ✅ VM-01 through VM-08 all pass |
| `map_get` bytecode opcode | ❌ NOT IMPLEMENTED — deferred to P5+ |

---

## 3. Explicit Answers to Card Questions

| Question | Answer |
|---|---|
| Record field can carry `Map[String,String]` metadata | **YES** — Rust SIR: params preserved |
| `map_get(record.map_field, key)` resolves to `Option[String]` | **PARTIAL** — Rust: correct field type, no `map_get`; Ruby: C1 strips params → `Option[Unknown]` |
| `or_else` unwraps lookup result to `String` | **YES** (direct Map input); blocked by C1 when through record field |
| Record field param unification catches wrong map value types | **NO — C1 CONFIRMED ACTIVE** in both compilers |
| This closes or confirms PROP-043 C1 | **CONFIRMS** — C1 is active; P4 planning specifies the fix (classifier.rb 1-line) |
| `map_empty()` needed for this bridge | **NO** — not needed for record/map field access |
| VM Map runtime behavior | **PARTIAL** — field store/retrieve works; `map_get` bytecode deferred |
| Bridge creates JSON/JsonValue authority | **NO** — CLOSED |
| Bridge creates mutable map authority | **NO** — CLOSED |
| Bridge creates canon/stable API authority | **NO** — lab-only |
| Exact next route | **PROP-043-P5** (production implementation) |

---

## 4. PROP-043 Caveat C1 — Confirmed Active

C1 from PROP-043-P3 is confirmed active in both compilers.

### Ruby MapPipeline (C1 root cause)

The production Ruby TypeChecker's `type_shapes` method uses `normalize_type` which returns only
the type name string, stripping generic params:

```ruby
# production lib/igniter_lang/typechecker.rb (BEFORE P5 fix)
def type_shapes(classified_program)
  classified_program.fetch("type_declarations").each_with_object({}) do |type, shapes|
    shapes[type.fetch("name")] = type.fetch("fields", []).each_with_object({}) do |field, fields|
      fields[field.fetch("name")] = type_ir(normalize_type(field.fetch("type_annotation")))
      #                                         ^^^^^^^^^^^ strips Map[String,String] → "Map"
    end
  end
end
```

Result: `@type_shapes["FullRackResponse"]["headers"] = {"name"=>"Map","params"=>[]}` (no params).

When field access resolves `response.headers`, it returns `Map` (no params). Then
`map_get(Map_no_params, key)` infers `Option[Unknown]`, not `Option[String]`.

**P4 fix** (planned): `classifier.rb:52` — change `normalize_type` call to
`normalized_type_annotation` which preserves generic params.

### Rust Compiler (C1 surface)

The Rust compiler does NOT catch wrong Map params in record field assignment. `Map[String,Integer]`
assigned to a `Map[String,String]` field compiles without error. The C1 fix (planned in P4) also
covers this case through the classifier change.

**IMPORTANT ASYMMETRY**: The Rust compiler correctly preserves `Map[String,String]` params
through field ACCESS in the SIR (output `hdrs: Map[String,String]` correctly typed). The gap
is only at field ASSIGNMENT (C1 — wrong params not checked).

---

## 5. Mechanism: Record/Map Bridge in the SIR

### Why field access preserves params in the Rust compiler

The Rust compiler's typechecker tracks Map params through the type system. When it resolves
`response.headers` (where `response: FullRackResponse`), it looks up the field type in the
type registry and returns the full `Map[String,String]` type with params. This appears in the
SIR as:

```json
{
  "name": "hdrs",
  "type": { "kind": "type_ref", "name": "Map", "params": ["String", "String"] },
  "expr": { "kind": "field_access", "field": "headers",
             "object": { "kind": "ref", "name": "response" } }
}
```

The params `["String", "String"]` are preserved end-to-end from the record type declaration
through field access in the SIR.

### Why map_get cannot currently use these params

`map_get` is not implemented in the Rust compiler or Rust VM. This is the P5 scope. When P5
lands, the Rust compiler will add a `map_get` stdlib function that:
1. Reads the Map type params from the argument's SIR type
2. Extracts V from `Map[String,V]`
3. Returns `Option[V]` in the SIR

At that point, the full chain `response.headers → Map[String,String]` → `map_get → Option[String]`
→ `or_else → String` will work correctly in the Rust compiler.

---

## 6. Observed VM Outputs

### WithHeaders (Map stored in record field)

Input: `{ "req_status": 200, "req_body": "OK", "resp_headers": {"content-type": "text/plain", "x-frame-options": "deny"} }`

```json
{
  "body": "OK",
  "headers": { "content-type": "text/plain", "x-frame-options": "deny" },
  "status": 200
}
```

### HeadersAccessor (field access returns map value)

Input: same → `{ "content-type": "text/plain", "x-frame-options": "deny" }`

### JobEnvelopeBuilder (Sidekiq — Map stored in record field)

Input: `{ "job_id": "j-001", "job_meta": {"queue": "default", "priority": "high", "retry": "true"} }`

```json
{
  "job_id": "j-001",
  "meta": { "priority": "high", "queue": "default", "retry": "true" }
}
```

Map keys sorted alphabetically (BTreeMap guarantee).

---

## 7. Check Inventory

| Section | Count | Description |
|---|---|---|
| RECORD-MAP-COMPILE | 6 | Rust compiler; Map[String,String] record fields; SIR output types |
| RECORD-MAP-SIR | 5 | Rust compiler; Map params preserved through field access |
| RECORD-MAP-VM | 8 | VM execution; Map inputs stored/retrieved; field access returns map |
| RECORD-MAP-PIPELINE | 9 | MapPipeline; direct map_get → Option[String]; C1 confirmed; OOF-MAP1/2/3 |
| RECORD-MAP-FAIL-CLOSED | 7 | C1 gap; Tier 2 fail-closed; map_get gap; OOF-MAP1/2 not in Rust |
| RECORD-MAP-REG | 4 | P2/P3/P13/P4 regression baselines |
| RECORD-MAP-CLOSED | 5 | Closed surface scan |
| RECORD-MAP-GAP | 7 | Explicit answers; gap packet |
| **Total** | **51** | |

---

## 8. Gap Packet

```
proof:        lab-record-map-p1-record-map-bridge / v0
status:       CLOSED / PROVED — 51/51 PASS

layer_a_rust_compiler:
  record_with_map_field: PROVED (FullRackResponse, JobEnvelope)
  sir_map_params_preserved: PROVED (Map[String,String] through field access)
  vm_map_store_retrieve: PROVED (field access returns map value)
  map_get_in_rust: BLOCKED (Unknown function; P5 scope)
  c1_gap_rust: CONFIRMED (wrong params not caught at assignment)
  oof_map1_map2_rust: NOT ENFORCED (P5 scope)

layer_b_map_pipeline:
  direct_map_get: PROVED (Option[String])
  or_else_unwrap: PROVED (String)
  field_access_map_get: DEGRADED (C1: Option[Unknown])
  oof_map1: PROVED (experiment-pass candidate)
  oof_map2: PROVED (experiment-pass candidate)
  oof_map3: PROVED (experiment-pass candidate)

c1_status: CONFIRMED ACTIVE (both compilers)
c1_fix: classifier.rb:52 normalize_type → normalized_type_annotation (1-line, P4 planned)
c2_status: UNCHANGED (map_empty deferred v1)
prop043_c1_closes: IN P5

closed_by_p1:
  - rack_record_map_field_compile
  - sidekiq_record_map_field_compile
  - map_field_sir_params_preserved
  - vm_map_field_store_retrieve
  - tier2_map_field_fail_closed
  - map_get_gap_documented
  - c1_caveat_confirmed_active
  - oof_map1_map2_not_in_rust_compiler

still_open:
  - map_get_production_implementation (P5)
  - or_else_through_record_field_params_restored (P5 after C1 fix)
  - c1_fix_production_deployment (P5)
  - oof_map1_in_production_rust_compiler (P5)
  - oof_map2_in_production_rust_compiler (P5)
  - vm_map_get_bytecode_opcode (P5+)

next_route: PROP-043-P5 (production implementation)
```

---

## 9. Boundary

Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim. No canon grammar change.
No production runtime authority. No public API stability.

`call_contract` is lab-only. `map_get` and `or_else` are proof-local MapPipeline only — not in the
production Rust compiler or VM. `Map[String,V]` type annotations are compiler-parsed but not
fully typechecked (C1 gap) in production until P5.

No JSON/JsonValue authority. No mutable map. No non-String keys (v1). No map literal syntax (v1).
