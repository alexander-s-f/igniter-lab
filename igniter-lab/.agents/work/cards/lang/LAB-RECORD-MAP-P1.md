# LAB-RECORD-MAP-P1: Record / Map[String,V] Bridge

**Category:** lang
**Track:** `lab-record-map-bridge-field-and-map-lookup-proof-v0`
**Status:** CLOSED / PROVED — 51/51 PASS
**Date closed:** 2026-06-09
**Agent:** Igniter-Lang Implementation Agent
**Role:** implementation-agent
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Depends on

- LAB-RECORD-VM-P1 (VM record construction — 43/43)
- LAB-RECORD-VM-P2 (dispatched record field access — 42/42)
- LAB-RECORD-VM-P3 (nested record field values — 49/49)
- PROP-043-P3 (Map[K,V] proof-local acceptance decision)
- PROP-043-P4 (Map[K,V] production-edit planning)

---

## Goal

Prove the lab-only bridge between typed Records and the proof-local `Map[String,V]` model:
records with map-typed fields, map lookup through record fields, and fail-closed behavior
for unresolved or ill-typed map access.

---

## Key Finding: Two-Layer Gap

The bridge is proven in two layers with a clear gap at map lookup.

### Layer A — Rust Compiler (what works today)

| Component | Status |
|---|---|
| `Map[String,String]` field in named Record | ✅ PROVED |
| SIR: Map params preserved through field access | ✅ PROVED (unexpected bonus!) |
| VM: Map inputs stored/retrieved through records | ✅ PROVED |
| Tier 2 + map field access fail-closed | ✅ PROVED (OOF-P1 `Unknown.headers`) |
| `map_get(record.map_field, key)` | ❌ BLOCKED (`Unknown function`) |
| C1: wrong map params in record field caught | ❌ NOT CAUGHT (P5 fix) |
| OOF-MAP1/2 in Rust compiler | ❌ NOT ENFORCED (P5 scope) |

**Surprising finding**: The Rust compiler preserves `Map[String,String]` params through field
access in the SIR. This is better than the Ruby MapPipeline (which has C1). The structural
bridge is sound at the SIR level.

### Layer B — Ruby MapPipeline (proof-local)

| Component | Status |
|---|---|
| `map_get(headers_direct, key)` → `Option[String]` | ✅ PROVED |
| `or_else(Option[String], default)` → `String` | ✅ PROVED |
| `map_get(response.headers, key)` via record field | ❌ C1: `Option[Unknown]` |
| OOF-MAP1/2/3 firing | ✅ PROVED (experiment-pass candidates) |

---

## Explicit Answers

| Question | Answer |
|---|---|
| Record field can carry `Map[String,String]` metadata | ✅ YES — Rust SIR confirms params preserved |
| `map_get(record.map_field, key)` resolves to `Option[String]` | ⚠️ PARTIAL — C1 blocks; `map_get` not in Rust |
| `or_else` unwraps to `String` | ✅ YES (direct map input) |
| Record field param unification catches wrong map value types | ❌ NO — C1 CONFIRMED in both compilers |
| Closes or confirms PROP-043 C1 | ✅ CONFIRMS — C1 active; P4 specifies fix |
| `map_empty()` needed | ❌ NO — not needed for this bridge |
| VM Map runtime behavior | ⚠️ PARTIAL — field store/retrieve works; `map_get` bytecode deferred |
| JSON/JsonValue authority created | ❌ NO — CLOSED |
| Mutable map authority created | ❌ NO — CLOSED |
| Canon/stable API authority created | ❌ NO — lab-only |
| Next route | **PROP-043-P5** (production implementation) |

---

## C1 Confirmed Active

Both compilers confirmed to have C1:

- **Ruby MapPipeline**: `@type_shapes` strips Map params → `response.headers → Map (no params)` → `map_get → Option[Unknown]`
- **Rust compiler**: `Map[String,Integer]` assigned to `Map[String,String]` field → no error

The asymmetry: the Rust compiler correctly preserves params in SIR output (field ACCESS works),
but doesn't validate params at field ASSIGNMENT (C1 gap).

**P4 fix planned**: `classifier.rb:52` — `normalize_type` → `normalized_type_annotation` (1-line)

---

## Deliverables

| File | Status |
|---|---|
| `igniter-view-engine/fixtures/rack_core/record_map_bridge.ig` | ✅ Written |
| `igniter-view-engine/proofs/verify_record_map_bridge.rb` | ✅ 51/51 PASS |
| `lab-docs/lang/lab-record-map-bridge-field-and-map-lookup-proof-v0.md` | ✅ Written |
| `.agents/work/cards/lang/LAB-RECORD-MAP-P1.md` (this file) | ✅ Authoritative |
| `.agents/portfolio-index.md` updated | ✅ P1 row added |

---

## Gap Packet Summary

```
layer_a_rust_compiler:
  record_with_map_field: PROVED
  sir_map_params_preserved: PROVED (bonus finding)
  vm_map_store_retrieve: PROVED
  map_get_in_rust: BLOCKED (P5 scope)
  c1_gap_rust: CONFIRMED

layer_b_map_pipeline:
  direct_map_get: PROVED → Option[String]
  or_else_unwrap: PROVED → String
  field_access_map_get: DEGRADED → Option[Unknown] (C1)
  oof_map1_map2_map3: PROVED (experiment-pass)

c1_status: CONFIRMED ACTIVE (both compilers; P5 fix planned)
still_open: map_get production; or_else via record field; C1 fix deployment; VM map_get opcode
next_route: PROP-043-P5
```

---

## Boundary

Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim. No canon grammar change.
No production runtime authority. No public API stability. `call_contract` is lab-only.
`map_get`/`or_else` are proof-local MapPipeline only (P5 scope for production).
No JSON authority. No mutable map. No non-String keys (v1). No map literal (v1).
