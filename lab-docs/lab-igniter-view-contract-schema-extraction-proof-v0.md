# Lab: Igniter View — Contract Schema Extraction Proof (v0)

> **Status:** experimental · lab-only · no-canon · no-public-api · no-stable-schema
> **Track:** LAB-IGNITER-VIEW-FRAMEWORK-P7
> **Date:** 2026-06-06
> **Proof:** 57/57 PASS — `run_ivf_proof_p7.rb`

---

## Overview

P7 prototypes a static extraction path that derives `ContractSchema` objects from
compiled contract artifacts (`.igapp/contracts/*.json` format) instead of relying
on hand-authored JSON fixtures.

This closes the drift risk identified in P6 (R2): schemas that are manually
maintained can diverge from what the compiler actually emits. By extracting from
compiled output, the schema description stays in sync with the contract's declared
type signature.

**Key limitation discovered during pre-flight:**
Compiled contract artifacts carry output `type_tag` values (`"String"`, `"Integer"`,
`"Collection[TimeSlot]"`, etc.) but do **not** carry `item_fields` for collection
types. The extractor produces accurate type-level schemas; `item_fields` must still
be supplied via hand-authored supplements. This is consistent with the
`missing_item_fields_schema` warning policy already established in P6.

---

## New Files (P7, purely additive)

| File | Role |
|------|------|
| `lib/compiled_contract_extractor.rb` | Extractor: compiled JSON → `ContractSchema` |
| `fixtures/compiled_contracts/search_compiled.json` | Synthetic lab fixture in compiled format (search contract) |
| `fixtures/compiled_contracts/availability_projection_compiled.json` | Lab copy of real `AvailabilityProjection` compiled output |
| `run_ivf_proof_p7.rb` | 57-check proof runner |
| `out/ivf_p7_proof_summary.json` | Machine-readable 57/57 PASS result |

**No existing files were modified.**

---

## Compiled Contract Format

The Igniter compiler emits contract artifacts under
`<igapp>/contracts/<name>.json`. The fields relevant to schema extraction:

```json
{
  "contract_id": "search",
  "output_ports": [
    { "name": "results", "type_tag": "Collection[SearchResult]", "required": true,  "lifecycle": "session" },
    { "name": "query",   "type_tag": "String",                  "required": true,  "lifecycle": "session" },
    { "name": "total",   "type_tag": "Integer",                 "required": true,  "lifecycle": "session" }
  ],
  "type_signature": {
    "outputs": { "results": "Collection[SearchResult]", "query": "String", "total": "Integer" }
  }
}
```

The extractor uses `output_ports` as the authoritative source (more structured than
`type_signature.outputs`). The `contract_id` field names the schema.

---

## CompiledContractExtractor

### API

```ruby
# From a file path
result = CompiledContractExtractor.extract("path/to/search.json")
result.valid?       # → true/false
result.schema       # → ContractSchema or nil (on error)
result.errors       # → [ExtractionDiagnostic, ...]
result.warnings     # → [ExtractionDiagnostic, ...]

# From an already-parsed Hash
result = CompiledContractExtractor.extract_data(data, source: "label")

# Extract all contracts from a directory
schemas = CompiledContractExtractor.extract_dir("fixtures/compiled_contracts/")
# → Hash { contract_id => ContractSchema }
```

### Type Tag Normalization

The `type_tag` field uses the compiler's type vocabulary. The extractor normalizes
to ContractSchema's `KNOWN_TYPES = %w[string integer float boolean array object any]`:

| Compiled `type_tag` | Normalized type | Notes |
|---------------------|-----------------|-------|
| `"Integer"` | `"integer"` | Direct |
| `"String"` | `"string"` | Direct |
| `"Float"` / `"Double"` | `"float"` | Direct |
| `"Boolean"` / `"Bool"` | `"boolean"` | Direct |
| `"Collection[X]"` | `"array"` | + `:missing_item_fields` warning |
| `"Array[X]"` | `"array"` | + `:missing_item_fields` warning |
| `"List[X]"` | `"array"` | + `:missing_item_fields` warning |
| `"Decimal[N]"` | `"float"` | Fixed-precision → float |
| `"Object"` | `"object"` | Direct |
| `"Any"` | `"any"` | Direct |
| Custom struct (`"AvailabilitySnapshot"`) | `"object"` | + `:opaque_struct_type` warning |

Matching is case-insensitive for scalar types.

---

## Diagnostic Policy

### ExtractionResult Diagnostics

**ERROR (valid? → false):**

| Type | Trigger |
|------|---------|
| `:malformed_artifact` | Not valid JSON, nil, or non-object root |
| `:missing_contract_id` | `"contract_id"` absent or blank |
| `:missing_output_ports` | `"output_ports"` absent or not an Array |
| `:invalid_output_entry` | Output port has no `"name"` field |

**WARNING (valid? → true):**

| Type | Trigger |
|------|---------|
| `:missing_item_fields` | `Collection[X]` / `Array[X]` / `List[X]` — item fields not in compiled format |
| `:opaque_struct_type` | Custom struct name — mapped to `"object"`, verify correct |
| `:empty_output_ports` | Contract has no output ports |

### Downstream LinkageDiagnostics

When an extracted schema (without `item_fields`) is used with `SlotTypeLinker`:
- Array slots: `SlotTypeLinker` emits `:missing_item_fields_schema` warning (P6 policy)
- Scalar slots: full type validation applies, `valid?=true` when types match
- Per IVX-P7-3: `results_panel` links with `valid?=true` using extracted schema

---

## Design Decisions

### D1 — `output_ports` is the authoritative source

Both `output_ports` and `type_signature.outputs` carry the same type information.
`output_ports` is preferred because it has `"required"` and `"lifecycle"` fields
(useful for future extensions) and retains port ordering. `type_signature.outputs`
is a flat map without per-port metadata.

### D2 — contract_id is preserved as-is (no case normalization)

The compiler emits PascalCase contract IDs (`"Search"`, `"AvailabilityProjection"`).
The extractor preserves this exactly. If `.igv` slot `from:` references use a different
casing, the lookup will fail — this is visible as `:unresolved_contract_ref` in
`SlotTypeLinker`. The synthetic lab fixtures use lowercase `"search"` to match
the `.igv` slot reference convention.

Future option: normalize to lowercase on extraction — not done in P7 to avoid
silent surprises when the naming convention differs.

### D3 — item_fields are not in compiled output (known structural limit)

The compiler's `output_ports` does not include `item_fields` for Collection types.
`Collection[SearchResult]` identifies the item type by name but does not expand
its fields. This is a structural property of the compiled format, not a bug.

Consequence: extracted schemas always need a hand-authored supplement for
field-level collection validation. The `:missing_item_fields` extraction warning
and the downstream `:missing_item_fields_schema` linkage warning both surface this.

A path to full item_fields derivation would require:
1. Type registry access (to expand `SearchResult` struct fields), OR
2. A separate `item_fields.json` supplement alongside the compiled contract, OR
3. Direct annotation in the `.igv` view via explicit `param` declarations
   (which `node_params_schema` already captures — P6 already has this)

### D4 — `extract_dir` silently skips failed files (with stderr warning)

`extract_dir` is designed for bulk loading. A single malformed file should not
abort the entire schema load. Errors are logged to stderr, and only valid schemas
are returned. This mirrors `ContractSchema.load_dir` behavior from P6.

### D5 — ExtractionDiagnostic is separate from LinkageDiagnostic

These are different concerns: extraction (reading compiled artifacts) vs linkage
(connecting ViewArtifact slots to ContractSchemas). Keeping them separate avoids
coupling two independent analysis layers and allows each to be used standalone.

### D6 — Synthetic lab fixtures use the compiled format structure

`fixtures/compiled_contracts/search_compiled.json` is hand-crafted to match the
compiled contract format — it was NOT produced by running the compiler. This is
a lab proof technique: we prove the extractor handles the format correctly without
needing to run a full compilation pipeline. The `_comment` and `_status` fields
document this.

---

## Proof Matrix: IVX-P7-1 through IVX-P7-12

All 57 checks PASS as of 2026-06-06.

| ID | Description | Result |
|----|-------------|--------|
| IVX-P7-1 (×5) | P1/P2/P3/P5/P6 regression gates all pass | ✅ |
| IVX-P7-2a..j | Valid extraction: search + availability_projection, all types normalized correctly | ✅ |
| IVX-P7-3a..d | Extracted schema links `results_panel` — `valid?=true`, expected `:missing_item_fields_schema` warning present | ✅ |
| IVX-P7-4 (×5) | Scalar outputs equal hand-authored fixture; array type=array; no item_fields in extracted (expected) | ✅ |
| IVX-P7-5a..e | Malformed JSON / nil / array root / bad file / missing file → all fail closed | ✅ |
| IVX-P7-6a..c | Missing/blank `contract_id` → `:missing_contract_id` error, fails closed | ✅ |
| IVX-P7-7a..e | `Collection[X]` → `valid?=true` + `:missing_item_fields` warning; `Array[X]` same; scalars unaffected | ✅ |
| IVX-P7-8a..c | Drift detected when compiled type differs from fixture; no drift when they match | ✅ |
| IVX-P7-9 (×8) | No innerHTML, eval, fetch, Net::HTTP, contract execution, localStorage, sessionStorage | ✅ |
| IVX-P7-10a..c | P1 tabs digest unchanged; results_panel digest valid sha256; extractor doesn't touch ViewArtifact | ✅ |
| IVX-P7-11 (×5) | Lab-only markers present in all new source files | ✅ |
| IVX-P7-12 | `igniter-lang/**` untouched | ✅ |

---

## Drift Detection Pattern

IVX-P7-8 proves a drift detection pattern — comparing extracted schema against a
hand-authored fixture for the same contract:

```ruby
# Hypothetical CI integration (not implemented in P7):
extracted = CompiledContractExtractor.extract("build/out/search.igapp/contracts/search.json").schema
fixture   = ContractSchema.load_file("fixtures/contract_schemas/search_contract.json")

drift = {}
(extracted.outputs.keys & fixture.outputs.keys).each do |name|
  et = extracted.output(name)["type"]
  ft = fixture.output(name)["type"]
  next if et == "array" && ft == "array"  # array item_fields gap is expected
  drift[name] = { extracted: et, fixture: ft } if et != ft
end

if drift.any?
  warn "[DRIFT] ContractSchema fixture mismatch for 'search': #{drift}"
end
```

This pattern is ready for use in a build lint step — out of scope for P7.

---

## Relationship to Prior Work

| Phase | Contribution to P7 |
|-------|-------------------|
| P6 ContractSchema | `ContractSchema.build(contract_id, outputs)` — target format for extractor output |
| P6 SlotTypeLinker | Consumer of extracted schemas; `:missing_item_fields_schema` warning is the downstream signal |
| P6 `:missing_item_fields_schema` warning | Design intent confirmed: this warning covers the structural gap in compiled format |
| P7 (this) | `CompiledContractExtractor` — derived schema from compiled artifacts; closes drift risk R2 |

---

## Constraints Observed

- Zero modifications to `igniter-lang/**`
- No changes to ViewArtifact, SsrRenderer, IgvCompiler, SlotTypeLinker, ContractSchema, or JS runtime
- No contract execution, no network access, no Igniter::Contract dependency
- All new files carry `lab-only · no-canon · no-stable-schema` markers
