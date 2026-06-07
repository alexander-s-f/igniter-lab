# Lab: Igniter View — Slot-Contract Type Linkage Proof (v0)

> **Status:** experimental · lab-only · no-canon · no-public-api · no-stable-schema
> **Track:** LAB-IGNITER-VIEW-FRAMEWORK-P6
> **Date:** 2026-06-06
> **Proof:** 55/55 PASS — `run_ivf_proof_p6.rb`

---

## Overview

This document describes the design and proof of a **static analysis layer** that validates
`.igv` slot `from:` references against external contract output schemas, and validates
array item field compatibility against `node_params_schema` in element definitions.

The layer is **purely additive**: it introduces no changes to ViewArtifact digest,
SSR rendering, or JS runtime behavior. It is an optional post-compilation step that
a build tool or IDE integration could invoke to surface mismatches before deployment.

---

## Problem Statement

A `slot` in a `.igv` view declares a `from:` reference pointing to a contract output:

```ruby
slot :results, type: "array", from: "search.results"
```

A `collection` then wires that slot to an element that declares `node_params_schema`
from its `param` declarations:

```ruby
collection :results_list, slot: :results, item_element: :result_item, item_key: :id
element :result_item do
  param :id,     type: "string"
  param :title,  type: "string"
  param :status, type: "string"
  param :score,  type: "integer"
end
```

Without static analysis, mismatches (wrong type, missing required field, unknown contract)
are only discovered at runtime — or worse, silently produce nil display-rule values.

The `SlotTypeLinker` solves this by:

1. Resolving `from: "contract_id.output_name"` against registered `ContractSchema` objects
2. Checking slot declared type vs contract output type
3. For array slots used by collections: checking element `node_params_schema` against
   contract `item_fields` (required field presence + type compatibility)

---

## New Files (P6, purely additive)

| File | Role |
|------|------|
| `lib/contract_schema.rb` | Structural description of a contract's output types |
| `lib/slot_type_linker.rb` | Static analysis: slots × schemas → diagnostics |
| `fixtures/contract_schemas/search_contract.json` | Matches `results_panel.igv` exactly |
| `fixtures/contract_schemas/diagnostics_contract.json` | For future tabs_panel linkage tests |
| `fixtures/contract_schemas/enriched_search_contract.json` | Extra optional fields (silently allowed policy) |
| `run_ivf_proof_p6.rb` | 55-check proof runner |
| `out/ivf_p6_proof_summary.json` | Machine-readable proof result |

**No existing files were modified.**

---

## ContractSchema

```ruby
# Programmatic construction
schema = ContractSchema.build("search", {
  "results" => {
    "type" => "array",
    "item_fields" => {
      "id"    => { "type" => "string",  "required" => true },
      "title" => { "type" => "string",  "required" => true },
      "score" => { "type" => "integer", "required" => false }
    }
  },
  "query" => { "type" => "string" }
})

# Load from fixture directory
schemas = ContractSchema.load_dir("fixtures/contract_schemas/")
# → { "search" => ContractSchema, "diagnostics" => ContractSchema, ... }
```

### JSON Format

```json
{
  "contract_id": "search",
  "outputs": {
    "results": {
      "type": "array",
      "item_fields": {
        "id":    { "type": "string",  "required": true },
        "score": { "type": "integer", "required": false }
      }
    },
    "query": { "type": "string" }
  }
}
```

---

## SlotTypeLinker

### Usage

```ruby
schemas = ContractSchema.load_dir("fixtures/contract_schemas/")
result  = SlotTypeLinker.link(artifact, schemas)

result.valid?       # → true/false (false if any :error diagnostic)
result.errors       # → [LinkageDiagnostic, ...]
result.warnings     # → [LinkageDiagnostic, ...]
result.diagnostics  # → all (errors + warnings)
```

### Resolution Protocol

`from: "search.results"` → split on first `.` →
- `contract_id = "search"`
- `output_name = "results"`

Everything before the first dot is the contract identifier.
Multi-segment output names are not supported (by design — P6 scope).

---

## Diagnostic Severity Policy

### ERROR (fails closed — `valid? → false`)

| Type | Trigger |
|------|---------|
| `:unresolved_contract_ref` | `from:` has no `.` separator, or no schema registered for contract_id |
| `:missing_output_ref` | Schema exists but has no matching output name |
| `:slot_type_mismatch` | Slot declares `type: "string"` but contract output is `type: "array"` (etc.) |
| `:missing_required_item_field` | Contract item field has `required: true` but element `node_params_schema` omits it |
| `:non_array_collection_slot` | A `collection` references a slot whose contract output is not `type: "array"` |

### WARNING (allowed — `valid? → true`)

| Type | Trigger |
|------|---------|
| `:item_field_type_mismatch` | Field in `node_params_schema` has a different type than contract item_fields |
| `:extra_item_field` | Element declares a param not present in contract item_fields |
| `:missing_item_fields_schema` | Contract declares array output but no `item_fields` — item validation skipped |

### Policy Rationale

**`extra_item_field` is a warning, not an error.** An element may declare params that
are provided by the host independently (e.g., UI-computed state), not from the contract.
Display rules referencing them will evaluate `nil` if the contract doesn't supply that
field — visible in display rule output, not a silent failure.

**`item_field_type_mismatch` is a warning.** Display rules are duck-typed. Integer/float
coercion is common. Only developers need awareness; the runtime still evaluates.

**Optional contract fields not declared in element schema are silently allowed.**
An element only declares what it uses. `enriched_search_contract` may supply `created_at`
and `author` that `result_item` never references — zero warnings, by design.
(This is the reverse of `extra_item_field`.)

---

## Design Decisions

### D1 — Standalone module, no ViewArtifact mutation

The linker takes `(artifact, schemas)` and returns a new `LinkageResult`. It does not
mutate the artifact, recompute its digest, or change any compiled output. The result is
ephemeral and only meaningful at the moment of invocation.

### D2 — ContractSchema is NOT Igniter::Contract

`ContractSchema` is a plain structural description loaded from JSON fixtures. It contains
no contract execution logic, no dependency graph, no Executor references. It is
intentionally decoupled from the runtime — a build-time type envelope only.

### D3 — `from:` format: `contract_id.output_name` (single-dot split)

Split on the **first** dot only. This allows output names with dots in future if needed
(unlikely, but safe). Contract IDs are simple identifiers (no dots).

### D4 — Schemas passed as Hash, not auto-discovered

The linker accepts `Hash { contract_id => ContractSchema }`. Discovery strategy
(directory loading, registry lookup, build tool integration) is the caller's
responsibility. This keeps the linker pure and testable.

### D5 — `types_compatible?` uses equality + "any" escape hatch

Type system is deliberately minimal: `any == any` matches everything.
`string == string`, `integer == integer`, etc. No coercion rules.
Future extension could add coercion rules without changing the diagnostic protocol.

### D6 — Slot without `from:` is silently skipped

Slots that declare no `from:` reference produce zero diagnostics. A slot may be
satisfied by host-injected data rather than a contract. The linker only validates
the subset of slots that declare a contract reference.

---

## Proof Matrix: IVT-P6-1 through IVT-P6-13

All 55 checks PASS as of 2026-06-06.

| ID | Description | Result |
|----|-------------|--------|
| IVT-P6-1a..d | P1/P2/P3/P5 proof runners all still pass (no regression) | ✅ |
| IVT-P6-2a..d | Valid linkage (`results_panel` + `search_contract`): zero errors, zero warnings | ✅ |
| IVT-P6-3a..d | Missing contract schema → `:unresolved_contract_ref` error, fails closed | ✅ |
| IVT-P6-4a..c | Contract exists but output missing → `:missing_output_ref` error | ✅ |
| IVT-P6-5a..c | Enriched contract with optional extra fields → silently allowed (0 warnings) | ✅ |
| IVT-P6-6a..d | Required field absent from element → `:missing_required_item_field` error | ✅ |
| IVT-P6-7a..d | Field type mismatch → `:item_field_type_mismatch` warning, `valid?=true` | ✅ |
| IVT-P6-8a..d | Element declares extra params → `:extra_item_field` warning × N, `valid?=true` | ✅ |
| IVT-P6-8e1..2 | Slot type mismatch (string slot, array contract) → `:slot_type_mismatch` error | ✅ |
| IVT-P6-8f1..2 | Collection uses non-array slot → `:non_array_collection_slot` error | ✅ |
| IVT-P6-8g1..2 | Array output with no `item_fields` → `:missing_item_fields_schema` warning | ✅ |
| IVT-P6-9a..c | SSR collection rendering unchanged by linkage layer | ✅ |
| IVT-P6-10 | P5 Node.js DOM proof (19 checks) still passes after P6 additions | ✅ |
| IVT-P6-11 (×8) | No innerHTML, eval, fetch, Net::HTTP, contract execution, localStorage, sessionStorage | ✅ |
| IVT-P6-12 (×6) | Lab-only markers present in all new source files | ✅ |
| IVT-P6-13 | `igniter-lang/**` untouched (canon boundary) | ✅ |

---

## SSR / JS Runtime Non-Impact

The `SlotTypeLinker` is invoked **after** ViewArtifact compilation, not during it.
IVT-P6-9 proves that after running `SlotTypeLinker.link(artifact, schemas)`:

- SSR collection rendering produces identical output
- Per-item display rules evaluate with unchanged logic
- The artifact's digest is unchanged (linker never touches the artifact)

The JS runtime (`igniter_view_runtime.js`) is **not modified** in P6.
Slot values flow into the runtime identically. The linker's diagnostic output
is purely build-time information.

---

## Integration Path (Future, Out of Scope)

The `SlotTypeLinker` is designed to be composed into a hypothetical build/lint step:

```ruby
# Hypothetical build-tool integration (not implemented in P6):
artifact = IgvCompiler.compile_file("views/results_panel.igv")
schemas  = ContractSchema.load_dir("contract_schemas/")
result   = SlotTypeLinker.link(artifact, schemas)
unless result.valid?
  result.errors.each { |d| puts "[ERROR] #{d.slot}: #{d.detail}" }
  exit 1
end
result.warnings.each { |d| puts "[WARN]  #{d.slot}: #{d.detail}" }
```

This is intentionally not a CLI tool in P6 — the proof runner demonstrates the interface,
not a production entry point.

---

## Constraints Observed

- Zero modifications to `igniter-lang/**` (IVT-P6-13 verified)
- No changes to ViewArtifact, SsrRenderer, IgvCompiler, or the JS runtime
- No contract execution, no network access, no browser APIs, no localStorage
- No Igniter::Contract dependency at load time
- All new files carry `lab-only · no-canon · no-stable-schema` markers

---

## Relationship to Prior Work

| Phase | Contribution to P6 |
|-------|-------------------|
| P1 (ViewArtifact + SSR) | `artifact.slots` and `artifact.elements` — both used by SlotTypeLinker |
| P3 (IgvCompiler) | `.igv` DSL emits `contract_ref` in slot definitions from `from:` parameter |
| P5 (Collections) | `artifact.collections` and `element.node_params_schema` — both used for item field validation |
| P6 (this) | SlotTypeLinker + ContractSchema: static analysis layer on top of P1–P5 |
