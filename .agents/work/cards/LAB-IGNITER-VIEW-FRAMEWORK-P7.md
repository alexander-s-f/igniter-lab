# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P7

Card: LAB-IGNITER-VIEW-FRAMEWORK-P7
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-igniter-view-contract-schema-extraction-proof-v0
Status: done
Date: 2026-06-06
Type: implementation + proof
Ruby proof: 57/57 PASS
Total: **57/57 PASS**
All P1/P2/P3/P5/P6 regression gates: PASS
igniter-lang/** boundary: VERIFIED (no modifications)

---

## Pre-flight Finding (card accuracy note)

The compiled contract format (`output_ports[].type_tag`) carries output type names
but does **not** carry `item_fields` for Collection types. `Collection[SearchResult]`
identifies item type by name only; struct fields are not emitted.

Consequence: IVX-P7-4 was scoped to "scalar outputs equal; array type=array without
item_fields (expected structural gap)" — not full equality including item_fields.
This is consistent with P6's `:missing_item_fields_schema` warning policy and the
card's IVX-P7-7 intent.

---

## [D] Decisions

**D1 — `output_ports` is the authoritative extraction source.**
Preferred over `type_signature.outputs` because `output_ports` retains per-port
metadata (`required`, `lifecycle`) useful for future extensions. Both carry the
same type information.

**D2 — `contract_id` preserved as-is (no case normalization).**
Compiler emits PascalCase. Lab fixtures use lowercase to match `.igv` `from:`
convention. Mismatches → `:unresolved_contract_ref` in SlotTypeLinker (visible, not silent).
Not auto-downcased in P7 to avoid surprises.

**D3 — item_fields not in compiled output — structural limit, not a bug.**
`Collection[SearchResult]` names the type but doesn't expand its fields.
`:missing_item_fields` extraction warning + downstream `:missing_item_fields_schema`
linkage warning together surface this gap. Hand-authored supplement (or `.igv` `param`
declarations in `node_params_schema`) is still needed for field-level validation.

**D4 — `extract_dir` silently skips failed files (stderr warning).**
Mirrors `ContractSchema.load_dir` behavior. Single malformed file doesn't abort
bulk schema load.

**D5 — ExtractionDiagnostic separate from LinkageDiagnostic.**
Different concerns — decoupled by design. Each layer testable standalone.

**D6 — Synthetic compiled fixtures are lab artifacts, not compiler output.**
`fixtures/compiled_contracts/*.json` are hand-crafted to match the compiled format
for proof purposes. `_comment` + `_status` fields document this.

---

## [S] Shipped

### New files (all additive):

| File | Purpose |
|------|---------|
| `igniter-view-engine/lib/compiled_contract_extractor.rb` | Extractor: compiled JSON → ContractSchema + ExtractionDiagnostic |
| `igniter-view-engine/fixtures/compiled_contracts/search_compiled.json` | Synthetic lab fixture matching compiled format |
| `igniter-view-engine/fixtures/compiled_contracts/availability_projection_compiled.json` | Lab copy of real AvailabilityProjection compiled output |
| `igniter-view-engine/run_ivf_proof_p7.rb` | 57-check proof runner |
| `igniter-view-engine/out/ivf_p7_proof_summary.json` | Machine-readable 57/57 PASS result |
| `lab-docs/lab-igniter-view-contract-schema-extraction-proof-v0.md` | Design doc |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P7.md` | This handoff card |

### Modified files: NONE

---

## [T] Test Matrix

| ID | Scenario | Result |
|----|----------|--------|
| IVX-P7-1 ×5 | P1/P2/P3/P5/P6 regression gates | ✅ PASS |
| IVX-P7-2a..j | Valid extraction: search (3 outputs) + availability (2 outputs), all types correct | ✅ PASS |
| IVX-P7-3a..d | Extracted schema links results_panel — valid?=true, :missing_item_fields_schema expected | ✅ PASS |
| IVX-P7-4 ×5 | Scalar equivalence with fixture; array type matches; item_fields absent (expected) | ✅ PASS |
| IVX-P7-5a..e | Nil / array root / malformed JSON / bad file / missing file → all fail closed | ✅ PASS |
| IVX-P7-6a..c | Missing/blank contract_id → :missing_contract_id error | ✅ PASS |
| IVX-P7-7a..e | Collection[X] / Array[X] → valid?=true + :missing_item_fields warning; scalar clean | ✅ PASS |
| IVX-P7-8a..c | Drift detected for type mismatch; no drift when types agree | ✅ PASS |
| IVX-P7-9 ×8 | Source guards: no innerHTML, eval, fetch, Net::HTTP, contract exec, localStorage, sessionStorage | ✅ PASS |
| IVX-P7-10a..c | P1 digest unchanged; results_panel digest valid sha256; extractor doesn't touch ViewArtifact | ✅ PASS |
| IVX-P7-11 ×5 | Lab-only markers in all new source files | ✅ PASS |
| IVX-P7-12 | igniter-lang/** untouched | ✅ PASS |

**Total: 57/57 PASS**

---

## [R] Risks & Limits

**R1 — item_fields derivation requires a type registry (not in P7 scope).**
`Collection[SearchResult]` → `"array"` but no `SearchResult` field expansion.
Closing this gap requires: (a) compiler emitting a type registry per igapp, OR
(b) a separate `item_fields_supplement.json` convention, OR (c) deriving from
`.igv` element `param` declarations (already available via `node_params_schema`).

**R2 — contract_id casing convention mismatch.**
Compiler emits PascalCase; `.igv` convention is lowercase. Either a normalization
option in the extractor (e.g., `normalize_id: :downcase`) or a naming convention
alignment between compiler and view layer would remove this friction.

**R3 — No real compiler pipeline integration.**
The extractor reads static JSON files. It does not hook into a build step that
regenerates schemas when contracts change. Drift is detectable (IVX-P7-8) but
not automatically triggered.

---

## Recommended P8 Options

**Option A — Diagnostic Reporter (recommended)**
Render `ExtractionResult` + `LinkageResult` as a unified structured report:
- CLI output with colored severity markers
- JSON report suitable for CI artifact upload
- Optional IDE annotation format (JSON with file+line references)
Wire into the `IgvCompiler` pipeline as optional post-compilation step.
Proof: report includes all diagnostics, severity counts, summary line.

**Option B — Grammar Parser (lab toy)**
Extend the `parser_builder.rb` sketch to handle a meaningful subset of `.igv` grammar.
Would allow parsing existing `.igv` files without the Ruby DSL.
Proof: parse `results_panel.igv` and produce equivalent artifact to `IgvCompiler`.
Risk: large scope, likely needs multiple cards.

**Option C — Collection Ordering**
Prove that collection rendering order is deterministic across SSR and JS runtime
when `item_key` values collide or items are reordered. Extend `_renderCollection`
to support stable key-based diffing.
Proof: same slot values always produce same DOM order.

**Option D — Hold / Consolidation**
Consolidate P1–P7 into a single design document and produce a stability assessment
for each subsystem (ViewArtifact, SSRRenderer, IgvCompiler, SlotTypeLinker,
CompiledContractExtractor). Evaluate what's stable enough for a `v0.1.0-lab` tag.
