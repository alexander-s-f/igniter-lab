# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P8

Card: LAB-IGNITER-VIEW-FRAMEWORK-P8
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-igniter-view-contract-schema-supplement-overlay-proof-v0
Status: done
Date: 2026-06-06
Type: implementation + proof
Ruby proof: 66/66 PASS (first run, zero fixes needed)
Total: **66/66 PASS**
All P1/P2/P3/P5/P6/P7 regression gates: PASS
igniter-lang/** boundary: VERIFIED (no modifications)

---

## [D] Decisions

**D1 — Compiled output is authoritative; supplement is additive-only.**
`ContractSchemaSupplement` can only add `item_fields` to existing array outputs.
It cannot create new output ports, override scalar types, or change `contract_id`.
Any attempt → error (`:supplement_to_non_array`, `:contract_id_mismatch`).

**D2 — contract_id matching is case-sensitive (P7 D2 preserved).**
`"Search"` ≠ `"search"` → `:contract_id_mismatch` error. No silent normalization.
Lab fixtures use lowercase `"search"` to match `.igv` `from:` convention.

**D3 — Unknown output refs are warnings (stale supplement tolerance).**
Supplement for `"deleted_output"` that no longer exists in compiled schema →
`:unknown_output_ref` warning, entry ignored, valid entries still applied.
`valid?=true`. Developer is warned; supplement remains partially functional.

**D4 — Non-destructive merge.**
`apply_to(schema)` never mutates `schema`. Each call returns a new `ContractSchema`.
Proved by IVX-P8-2i: original extracted schema's `results.item_fields` is still `nil`
after overlay.

**D5 — Missing supplement is not an error.**
`apply_matching` with no match → schema unchanged, zero diagnostics. P7 warning
behavior (`:missing_item_fields_schema`) preserved downstream in `SlotTypeLinker`.

**D6 — `load_file` fails closed on malformed input.**
Bad JSON / missing file / array root / blank contract_id → `ArgumentError`.
Consistent with `ContractSchema.load_file` and `CompiledContractExtractor.extract`.

**D7 — Only `item_fields` key is meaningful in supplement entries.**
`type`, `lifecycle`, or other keys → `:unrecognized_supplement_key` warning and ignored.
Prevents supplement from silently overriding compiled output metadata.

---

## [S] Shipped

### New files (all additive):

| File | Purpose |
|------|---------|
| `igniter-view-engine/lib/contract_schema_supplement.rb` | Overlay: supplement JSON → merged ContractSchema |
| `igniter-view-engine/fixtures/schema_supplements/search_supplement.json` | item_fields for search.results (4 fields) |
| `igniter-view-engine/fixtures/schema_supplements/availability_supplement.json` | item_fields for AvailabilityProjection.available_slots (4 fields) |
| `igniter-view-engine/run_ivf_proof_p8.rb` | 66-check proof runner |
| `igniter-view-engine/out/ivf_p8_proof_summary.json` | Machine-readable 66/66 PASS result |
| `lab-docs/lab-igniter-view-contract-schema-supplement-overlay-proof-v0.md` | Design doc |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P8.md` | This handoff card |

### Modified files: NONE

---

## [T] Test Matrix

| ID | Scenario | Result |
|----|----------|--------|
| IVX-P8-1 ×6 | P1/P2/P3/P5/P6/P7 regression gates | ✅ PASS |
| IVX-P8-2a..j | Valid supplement: before (no item_fields) → after (4 fields); scalar unchanged; original not mutated; AvailabilityProjection also works | ✅ PASS |
| IVX-P8-3a..d | Supplemented schema links results_panel — valid?=true, ZERO total diagnostics | ✅ PASS |
| IVX-P8-4a..e | Stale entry (unknown output): `:unknown_output_ref` warning; unknown port NOT added; valid entry applied | ✅ PASS |
| IVX-P8-5a..d | Scalar target: `:supplement_to_non_array` error; type unchanged; error attributed to correct field | ✅ PASS |
| IVX-P8-6a..d | ID mismatch (including casing): `:contract_id_mismatch` error; contract_id unchanged | ✅ PASS |
| IVX-P8-7a..e | Malformed/missing file / array root / no ID / non-schema input → all fail closed | ✅ PASS |
| IVX-P8-8a..d | Multiple stale entries → N warnings; valid entries applied; apply_matching(no match) clean | ✅ PASS |
| IVX-P8-9a..c | Missing supplement: P7 :missing_item_fields_schema preserved; apply_matching(nil) → unchanged | ✅ PASS |
| IVX-P8-10a..c | Drift: scalar mismatch detected; no false drift from supplemented item_fields | ✅ PASS |
| IVX-P8-11 ×9 | Source guards: no innerHTML, eval, fetch, Net::HTTP, contract exec, localStorage, sessionStorage, DOM | ✅ PASS |
| IVX-P8-12a..b | No absolute paths in proof summary JSON | ✅ PASS |
| IVX-P8-13 ×6 | Lab-only markers in all new source files and fixtures | ✅ PASS |
| IVX-P8-14 | igniter-lang/** untouched | ✅ PASS |

**Total: 66/66 PASS**

---

## [R] Risks & Limits

**R1 — Supplement drift risk (same as hand-authored fixture drift).**
A supplement file that becomes stale (compiled contract adds new required fields)
will emit `:unknown_output_ref` warnings for orphaned entries but will NOT
automatically update to add the new fields. A CI step that compares extracted
schema output names against supplement entries would catch this — not implemented.

**R2 — No schema versioning in supplement files.**
Supplement files have no version pin (e.g., `contract_version` or `artifact_hash`).
A supplement written against `search` v1 will silently apply to `search` v2 without
noticing if a field was removed (no `:unknown_item_field` diagnostic).
Future option: add `artifact_hash` to supplement for pin-based freshness checks.

**R3 — `item_fields` type normalization is the caller's responsibility.**
Supplement `item_fields` are stored as-is (no type validation against KNOWN_TYPES).
A supplement with `"type": "UUID"` would produce a ContractSchema with type="UUID",
which `SlotTypeLinker` would then validate against the element's node_params_schema.
The type normalization from P7 applies to extracted types, not supplement types.

---

## Recommended P9 Option

**Option A — Diagnostic Reporter (recommended)**
Build a unified `LinkageReport` that combines:
- `ExtractionResult` diagnostics (from CompiledContractExtractor)
- `OverlayResult` diagnostics (from ContractSchemaSupplement)
- `LinkageResult` diagnostics (from SlotTypeLinker)

Into a single structured report with CLI text output (colored severity), JSON
report for CI, and summary line. Wire as an optional step after `IgvCompiler.compile_file`.

Proof: report includes all diagnostic layers; severity counts correct;
CLI output renderable; JSON has no absolute paths; lab-only markers present.

**Option B — Consolidation & Stability Assessment**
Audit P1–P8 for internal consistency, write a single `docs/lab-igniter-view-layer-design-v0.md`
covering the full pipeline from ViewArtifact → SlotTypeLinker → ContractSchemaSupplement,
and produce a stability assessment for each module (experimental / pre-stable / stable).
Useful as the "v0.1.0-lab" readiness gate before wider sharing.

**Option C — Hold**
P1–P8 form a complete and self-consistent proof of the slot-contract type linkage
pipeline. All P7 structural gaps are now closed. Pause the LAB-IGNITER-VIEW-FRAMEWORK
track and focus on other lab tracks (e.g., LAB-VIEW-DSL, LAB-TAURI-IVF, LAB-FORMS).
