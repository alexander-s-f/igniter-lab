# Lab: Igniter View — ContractSchema Supplement Overlay Proof (v0)

> **Status:** experimental · lab-only · no-canon · no-public-api · no-stable-schema
> **Track:** LAB-IGNITER-VIEW-FRAMEWORK-P8
> **Date:** 2026-06-06
> **Proof:** 66/66 PASS — `run_ivf_proof_p8.rb`

---

## Overview

P8 closes the structural gap left open by P7: compiled contract artifacts carry
`output_ports[].type_tag` but not `item_fields` for Collection types. P7 extracted
accurate type-level schemas and emitted `:missing_item_fields` / `:missing_item_fields_schema`
warnings to signal this gap. P8 provides a bounded supplement overlay mechanism
that allows hand-authored `item_fields` to be merged into extracted schemas without
granting supplement files any compiler authority.

**Invariant:** The compiled contract output remains authoritative. The supplement
can only add `item_fields` to existing array outputs. It cannot create new outputs,
override scalar types, or change `contract_id`.

---

## New Files (P8, purely additive)

| File | Role |
|------|------|
| `lib/contract_schema_supplement.rb` | `ContractSchemaSupplement` overlay: supplement JSON → merged `ContractSchema` |
| `fixtures/schema_supplements/search_supplement.json` | item_fields for `search.results` (matches search_contract.json exactly) |
| `fixtures/schema_supplements/availability_supplement.json` | item_fields for `AvailabilityProjection.available_slots` (TimeSlot struct) |
| `run_ivf_proof_p8.rb` | 66-check proof runner |
| `out/ivf_p8_proof_summary.json` | Machine-readable 66/66 PASS result |

**No existing files were modified.**

---

## Supplement JSON Format

```json
{
  "_comment": "Lab supplement for 'search' contract.",
  "_status": "experimental · lab-only · no-canon · no-public-api · no-stable-schema",
  "contract_id": "search",
  "supplements": {
    "results": {
      "item_fields": {
        "id":    { "type": "string",  "required": true  },
        "score": { "type": "integer", "required": false }
      }
    }
  }
}
```

Only `item_fields` is meaningful in each supplement entry. Any other key
(e.g., `type`) is rejected with `:unrecognized_supplement_key` warning —
supplement cannot silently override compiled output properties.

---

## ContractSchemaSupplement API

```ruby
# Load from file
supplement = ContractSchemaSupplement.load_file("fixtures/schema_supplements/search_supplement.json")

# Apply to an extracted ContractSchema
overlay = supplement.apply_to(extracted_schema)
overlay.valid?        # → true/false
overlay.schema        # → ContractSchema with item_fields merged
overlay.errors        # → [OverlayDiagnostic, ...]
overlay.warnings      # → [OverlayDiagnostic, ...]

# Convenience class methods
overlay = ContractSchemaSupplement.apply(schema, supplement)

# Match by contract_id and apply (nil/missing → schema unchanged)
supplements_map = ContractSchemaSupplement.load_dir("fixtures/schema_supplements/")
overlay = ContractSchemaSupplement.apply_matching(extracted_schema, supplements_map)
```

---

## Merge Protocol

The overlay performs a non-destructive deep merge:

1. Copy extracted schema outputs (does not mutate the original).
2. For each supplement entry `{ output_name => { item_fields: {...} } }`:
   - **contract_id mismatch** → `:contract_id_mismatch` ERROR. Supplement not applied.
   - **unknown output** → `:unknown_output_ref` WARNING. Entry ignored, not added.
   - **non-array output** → `:supplement_to_non_array` ERROR. Item_fields not applicable.
   - **valid array output** → `item_fields` merged into the output definition.
3. A new `ContractSchema` is built from the merged outputs. Original schema is untouched.

---

## Diagnostic Policy

### OverlayResult Diagnostics

**ERROR (valid? → false):**

| Type | Trigger |
|------|---------|
| `:invalid_schema` | `apply_to` received something that is not a `ContractSchema` |
| `:contract_id_mismatch` | Supplement `contract_id` ≠ schema `contract_id` (case-sensitive) |
| `:supplement_to_non_array` | Supplement targets a non-array output (type != "array") |

**WARNING (valid? → true):**

| Type | Trigger |
|------|---------|
| `:unknown_output_ref` | Supplement references output absent from compiled schema (stale supplement) |
| `:unrecognized_supplement_key` | Supplement entry contains keys other than `item_fields` |

---

## Design Decisions

### D1 — Compiled output is always authoritative

The compiled schema is the source of truth for output names and scalar types.
The supplement cannot change them. This prevents the supplement from "fixing"
a type mismatch by overriding the scalar type — such a mismatch should be
resolved at the contract definition level, not the supplement level.

### D2 — contract_id match is case-sensitive (P7 D2 preserved)

`"Search"` ≠ `"search"`. A casing mismatch → `:contract_id_mismatch` error
(IVX-P8-6d). No silent normalization. This keeps the casing convention explicit
and visible.

### D3 — Unknown output refs are warnings, not errors

A stale supplement (referencing an output that no longer exists in the compiled
schema) produces a `:unknown_output_ref` warning and skips that entry.
`valid?=true`. This allows old supplements to remain functional for their valid
entries even if some entries have rotted. The warning surfaces staleness to the
developer.

### D4 — Supplement cannot add new output ports

If a supplement entry references `"new_output"` that doesn't exist in the compiled
schema, it is ignored with a `:unknown_output_ref` warning. The extractor's schema
is the authoritative port list.

### D5 — Non-destructive merge

`apply_to(schema)` never mutates `schema`. The original extracted schema is
preserved unchanged (IVX-P8-2i). Each overlay call produces a new `ContractSchema`.

### D6 — Missing supplement is not an error

`apply_matching` with no matching supplement returns the original schema unchanged
with zero diagnostics. P7 warning behavior (`:missing_item_fields_schema`) is
preserved downstream in `SlotTypeLinker`. The developer can choose whether to
add a supplement or accept the warning.

### D7 — load_file fails closed on malformed input

Bad JSON, missing file, array root, missing `contract_id` → raises `ArgumentError`.
This is consistent with `ContractSchema.load_file` and `CompiledContractExtractor.extract`
behavior.

---

## Full Pipeline

P1–P8 form a complete static analysis pipeline for slot-contract type validation:

```
.igv file                     → IgvCompiler.compile_file(...)          → ViewArtifact
compiled contract (.igapp)     → CompiledContractExtractor.extract(...)  → ContractSchema (no item_fields)
supplement JSON               → ContractSchemaSupplement.load_file(...) → ContractSchemaSupplement
                                 supplement.apply_to(extracted_schema)   → ContractSchema (with item_fields)

ViewArtifact + {ContractSchema} → SlotTypeLinker.link(artifact, schemas) → LinkageResult
```

**Endpoint:** `LinkageResult.valid?` — zero diagnostics when all types match and
all required item fields are present.

---

## Proof Matrix: IVX-P8-1 through IVX-P8-14

All 66 checks PASS as of 2026-06-06.

| ID | Description | Result |
|----|-------------|--------|
| IVX-P8-1 (×6) | P1/P2/P3/P5/P6/P7 regression gates | ✅ |
| IVX-P8-2a..j | Valid supplement: item_fields added; scalar unchanged; original not mutated; AvailabilityProjection also works | ✅ |
| IVX-P8-3a..d | Supplemented schema links `results_panel` — zero total diagnostics | ✅ |
| IVX-P8-4a..e | Unknown output ref → `:unknown_output_ref` warning; unknown port NOT added; valid entry still applied | ✅ |
| IVX-P8-5a..d | Non-array output → `:supplement_to_non_array` error; scalar type unchanged | ✅ |
| IVX-P8-6a..d | Contract ID mismatch (including case) → `:contract_id_mismatch` error; no silent normalization | ✅ |
| IVX-P8-7a..e | Malformed JSON / missing file / array root / no contract_id / non-schema input → all fail closed | ✅ |
| IVX-P8-8a..d | Multiple stale entries → N warnings; valid entries still applied; `apply_matching` no-match is clean | ✅ |
| IVX-P8-9a..c | No supplement → P7 `:missing_item_fields_schema` warning preserved; `apply_matching(nil)` returns unchanged | ✅ |
| IVX-P8-10a..c | Drift detection active: scalar mismatch detected even with supplement applied; no false drift from supplement | ✅ |
| IVX-P8-11 (×9) | Source guards: no innerHTML, eval, fetch, Net::HTTP, contract execution, localStorage, sessionStorage, DOM | ✅ |
| IVX-P8-12a..b | Proof summary JSON: no absolute paths, no local-file URI | ✅ |
| IVX-P8-13 (×6) | Lab-only markers in all new source files and fixture JSONs | ✅ |
| IVX-P8-14 | `igniter-lang/**` untouched | ✅ |

---

## Before / After Comparison

### Without supplement (P7 behavior)

```
Extract search_compiled.json → ContractSchema {
  results: { type: "array" }         ← NO item_fields
  query:   { type: "string" }
  total:   { type: "integer" }
}

SlotTypeLinker.link(results_panel, {"search" => extracted})
→ valid?=true
→ warnings: [:missing_item_fields_schema on slot "results"]
```

### With supplement (P8 behavior)

```
Extract search_compiled.json → ContractSchema { results: { type: "array" }, ... }
Apply search_supplement.json → ContractSchema {
  results: { type: "array", item_fields: {id, title, status, score} }  ← ADDED
  query:   { type: "string" }                                           ← UNCHANGED
  total:   { type: "integer" }                                          ← UNCHANGED
}

SlotTypeLinker.link(results_panel, {"search" => overlaid})
→ valid?=true
→ diagnostics: []                                                       ← ZERO WARNINGS
```

---

## Constraints Observed

- Zero modifications to `igniter-lang/**`
- No changes to ViewArtifact, SsrRenderer, IgvCompiler, SlotTypeLinker,
  ContractSchema, CompiledContractExtractor, or JS runtime
- No contract execution, no network access, no Igniter::Contract dependency
- No absolute filesystem paths in proof summary JSON
- All new files carry `lab-only · no-canon · no-stable-schema` markers
