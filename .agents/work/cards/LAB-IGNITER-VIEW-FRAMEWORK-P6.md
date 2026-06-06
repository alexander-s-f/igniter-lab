# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P6

Card: LAB-IGNITER-VIEW-FRAMEWORK-P6
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-igniter-view-slot-contract-type-linkage-proof-v0
Status: done
Date: 2026-06-06
Type: implementation + proof
Ruby proof: 55/55 PASS
Total: **55/55 PASS**
All P1/P2/P3/P5 regression gates: PASS
igniter-lang/** boundary: VERIFIED (no modifications)

---

## [D] Decisions

**D1 — Purely additive: no existing files modified.**
`SlotTypeLinker` and `ContractSchema` are new standalone modules. Zero changes to
`view_artifact.rb`, `ssr_renderer.rb`, `igv_compiler.rb`, or `igniter_view_runtime.js`.
The ViewArtifact digest is unchanged. SSR and JS runtime behavior are unchanged.

**D2 — ContractSchema is NOT Igniter::Contract.**
`ContractSchema` is a plain structural JSON envelope loaded from fixture files.
It has no dependency on `Igniter::Contract`, `Executor`, or the runtime graph.
It exists purely as a build-time type description.

**D3 — `from:` resolution: split on first dot.**
`"search.results"` → `contract_id="search"`, `output_name="results"`.
Split on **first** dot only — safe for future output names that might contain dots.
Slots without `from:` are silently skipped (no diagnostic).

**D4 — Schemas injected by caller, not auto-discovered.**
`SlotTypeLinker.link(artifact, schemas)` accepts a `Hash { contract_id => ContractSchema }`.
How schemas are loaded (directory scan, registry, build-tool config) is the caller's
responsibility. Keeps the linker pure and easily unit-tested.

**D5 — Severity split: ERROR vs WARNING.**
ERROR types: `unresolved_contract_ref`, `missing_output_ref`, `slot_type_mismatch`,
`missing_required_item_field`, `non_array_collection_slot` — all fail closed.
WARNING types: `item_field_type_mismatch`, `extra_item_field`, `missing_item_fields_schema`
— do not make `valid?` false.

**D6 — Optional contract fields not in element schema: silently allowed.**
The element only declares the params it uses. `enriched_search_contract` supplies
`created_at` and `author`; `result_item` doesn't declare them → zero warnings.
This is the reverse of `extra_item_field` (element declares param not in contract).

**D7 — `types_compatible?` uses equality + "any" wildcard, no coercion.**
Minimal type matching: `string == string`, `any` matches anything. No integer↔float
coercion rules in P6. Future extension can add coercion without changing the protocol.

**D8 — LinkageResult is immutable; diagnostics are frozen on construction.**
`@diagnostics.freeze` on construction. `to_h` serializes cleanly to JSON.
The result is ephemeral — not stored in the artifact.

---

## [S] Shipped

### New files (all additive):

| File | Purpose |
|------|---------|
| `igniter-view-engine/lib/contract_schema.rb` | ContractSchema: load JSON, normalize outputs/item_fields, programmatic build |
| `igniter-view-engine/lib/slot_type_linker.rb` | SlotTypeLinker + LinkageResult + LinkageDiagnostic |
| `igniter-view-engine/fixtures/contract_schemas/search_contract.json` | Matches `results_panel.igv` exactly (id/title/status/score) |
| `igniter-view-engine/fixtures/contract_schemas/diagnostics_contract.json` | has_warnings/error_count/warning_list |
| `igniter-view-engine/fixtures/contract_schemas/enriched_search_contract.json` | Extra optional fields (created_at/author) for silently-allowed policy proof |
| `igniter-view-engine/run_ivf_proof_p6.rb` | 55-check proof runner |
| `igniter-view-engine/out/ivf_p6_proof_summary.json` | Machine-readable 55/55 PASS result |
| `lab-docs/lab-igniter-view-slot-contract-type-linkage-proof-v0.md` | Design doc |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P6.md` | This handoff card |

### Modified files: NONE

---

## [T] Test Matrix

| ID | Scenario | Result |
|----|----------|--------|
| IVT-P6-1a..d | P1/P2/P3/P5 regression gates all pass | ✅ PASS |
| IVT-P6-2a..d | Valid linkage (results_panel + search_contract): 0 errors, 0 warnings | ✅ PASS |
| IVT-P6-3a..d | No schema for contract → `:unresolved_contract_ref`, `valid?=false` | ✅ PASS |
| IVT-P6-4a..c | Schema exists, output missing → `:missing_output_ref`, `valid?=false` | ✅ PASS |
| IVT-P6-5a..c | Enriched contract optional fields not in element → 0 warnings (silently allowed) | ✅ PASS |
| IVT-P6-6a..d | Required field absent from element schema → `:missing_required_item_field`, `valid?=false` | ✅ PASS |
| IVT-P6-7a..d | Field type mismatch → `:item_field_type_mismatch` warning, `valid?=true` | ✅ PASS |
| IVT-P6-8a..d | Element declares extra params → `:extra_item_field` warning ×N, `valid?=true` | ✅ PASS |
| IVT-P6-8e1..2 | Slot type mismatch (string vs array) → `:slot_type_mismatch`, `valid?=false` | ✅ PASS |
| IVT-P6-8f1..2 | Collection on non-array slot → `:non_array_collection_slot`, `valid?=false` | ✅ PASS |
| IVT-P6-8g1..2 | Array output, no item_fields → `:missing_item_fields_schema` warning, `valid?=true` | ✅ PASS |
| IVT-P6-9a..c | SSR rendering deterministic, unchanged by linkage layer | ✅ PASS |
| IVT-P6-10 | P5 Node.js DOM proof still passes (19/19) | ✅ PASS |
| IVT-P6-11 ×8 | No innerHTML, eval, fetch, Net::HTTP, contract exec, localStorage, sessionStorage | ✅ PASS |
| IVT-P6-12 ×6 | Lab-only markers present in all new source files | ✅ PASS |
| IVT-P6-13 | `igniter-lang/**` untouched | ✅ PASS |

**Total: 55/55 PASS**

---

## [R] Risks & Limits

**R1 — No multi-dot output name support.**
`from: "analytics.pipeline.results"` would set `contract_id="analytics"`,
`output_name="pipeline.results"` — which would then fail `:missing_output_ref` unless
the schema explicitly has a key named `"pipeline.results"`. Document in P6 design doc.

**R2 — ContractSchema JSON is manually authored, not derived from actual contracts.**
Until a code-gen step writes `contract_schemas/*.json` from real `Igniter::Contract`
class definitions, the fixtures are authoritative only by convention — drift is possible.
An IDD card for contract-schema extraction is a natural P7 candidate.

**R3 — `extra_item_field` warning is noisy for wide-schema contracts.**
A contract with 20 item fields and an element that uses 4 will generate 16 warnings.
A `suppress_extra_item_field_warnings: true` option on the linker call could mitigate.
Out of scope for P6.

**R4 — Only one-level `from:` resolution.**
Nested contracts, aliased slots, and composed views with slot remapping are not analyzed.
Each slot is resolved independently from its `contract_ref`.

---

## Recommended Next Card

**LAB-IGNITER-VIEW-FRAMEWORK-P7 — Contract Schema Extraction**

Generate `fixtures/contract_schemas/*.json` from real `Igniter::Contract` class
definitions (or from compiled graphs), replacing hand-authored JSON fixtures.
This closes the drift risk identified in R2.

Alternative next track:
- **LAB-IGNITER-VIEW-FRAMEWORK-P7 — Diagnostic Reporter** — render `LinkageResult`
  as structured CLI output, IDE annotation markers, or HTML report; wire into
  the IgvCompiler pipeline as optional post-compilation step.
