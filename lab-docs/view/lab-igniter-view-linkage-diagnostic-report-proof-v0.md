# Lab: Igniter View — Linkage Diagnostic Report Proof (v0)

> **Status:** experimental · lab-only · no-canon · no-public-api · no-stable-schema
> **Track:** LAB-IGNITER-VIEW-FRAMEWORK-P9
> **Date:** 2026-06-06
> **Proof:** 58/58 PASS — `run_ivf_proof_p9.rb`

---

## Overview

P9 builds `LinkageReport` — a unified developer report that combines diagnostics from
all three static-analysis layers introduced in P6–P8:

| Layer | Source | Example diagnostics |
|-------|--------|---------------------|
| `:extractor` | `CompiledContractExtractor` | `:missing_item_fields`, `:opaque_struct_type` |
| `:overlay` | `ContractSchemaSupplement` | `:unknown_output_ref`, `:supplement_to_non_array`, `:contract_id_mismatch` |
| `:linker` | `SlotTypeLinker` | `:missing_item_fields_schema`, `:slot_type_mismatch`, `:missing_required_item_field` |

Each diagnostic is attributed to its source layer. The report produces:
- `to_h` → CI-safe JSON (no absolute paths)
- `to_text` → deterministic terminal output

---

## New Files (P9, purely additive)

| File | Role |
|------|------|
| `lib/linkage_report.rb` | `LinkageReport` model + `ReportEntry` + text/JSON renderers + pipeline builder |
| `run_ivf_proof_p9.rb` | 58-check proof runner |
| `out/ivf_p9_proof_summary.json` | Machine-readable 58/58 PASS |
| `out/ivf_p9_linkage_report_summary.json` | Canonical linkage report (search + supplement) |
| `out/ivf_p9_linkage_report_sample.txt` | Sample text render (happy-path) |

**No existing files were modified.**

---

## LinkageReport API

### Build from result objects

```ruby
report = LinkageReport.build(
  contract_id:       "search",
  view_id:           "igniter.lab.results_panel",
  extraction_result: extracted,    # CompiledContractExtractor::ExtractionResult
  overlay_result:    overlay,      # ContractSchemaSupplement::OverlayResult (or nil)
  linkage_result:    linkage       # SlotTypeLinker::LinkageResult
)
```

### Pipeline convenience

```ruby
report = LinkageReport.build_pipeline(
  igv_path:               "fixtures/results_panel.igv",
  compiled_contract_path: "fixtures/compiled_contracts/search_compiled.json",
  supplement_path:        "fixtures/schema_supplements/search_supplement.json"  # optional
)
```

### Query

```ruby
report.valid?            # → true/false (false if any error entry)
report.error_count       # → Integer
report.warning_count     # → Integer
report.entry_count       # → Integer
report.entries_for(layer: :extractor)  # → [ReportEntry, ...]
report.errors            # → [ReportEntry, ...] (all layers)
report.warnings          # → [ReportEntry, ...]
```

### Render

```ruby
puts report.to_text      # terminal-friendly
json = report.to_h       # CI-safe Hash, no absolute paths
```

---

## ReportEntry Shape

```ruby
ReportEntry = Struct.new(
  :source_layer,   # :extractor | :overlay | :linker
  :severity,       # :error | :warning
  :type,           # original diagnostic type symbol
  :field,          # output/param name (extractor/overlay) or slot name (linker)
  :collection,     # collection name (linker only) or nil
  :detail          # human-readable explanation
)
```

All three underlying diagnostic structs (`ExtractionDiagnostic`, `OverlayDiagnostic`,
`LinkageDiagnostic`) are normalized into `ReportEntry` with `:source_layer` added.
For linker diagnostics: `diagnostic.slot` → `entry.field`, `diagnostic.collection` → `entry.collection`.

---

## JSON Report Format

```json
{
  "_status": "experimental · lab-only · no-canon · no-public-api · no-stable-schema",
  "view_id": "igniter.lab.results_panel",
  "contract_id": "search",
  "valid": true,
  "summary": {
    "errors": 0,
    "warnings": 1,
    "total_entries": 1,
    "by_layer": {
      "extractor": { "errors": 0, "warnings": 1, "total": 1 },
      "overlay":   { "errors": 0, "warnings": 0, "total": 0 },
      "linker":    { "errors": 0, "warnings": 0, "total": 0 }
    }
  },
  "entries": [
    {
      "source_layer": "extractor",
      "severity":     "warning",
      "type":         "missing_item_fields",
      "field":        "results",
      "detail":       "..."
    }
  ]
}
```

No absolute filesystem paths. No `local-file URI` links. The `view_id` and `contract_id`
are semantic identifiers (not file paths). Suitable for CI artifact upload.

---

## Text Render Sample (Happy Path)

```
══════════════════════════════════════════════════════════
LINKAGE REPORT
  view:     igniter.lab.results_panel
  contract: search
  status:   ✅ VALID  (0 errors · 1 warning)
──────────────────────────────────────────────────────────
  [extractor]   [W] :missing_item_fields [results]
                    Output 'results' has type 'Collection[SearchResult]'
                    — mapped to 'array'. Compiled contract format does
                    not carry item_fields. SlotTypeLinker will emit
                    :missing_item_fields_schema for collection slots
                    linked to this output. Add item_fields manually to
                    a supplement if field-level validation is required.
  [overlay]     — no diagnostics
  [linker]      — no diagnostics
──────────────────────────────────────────────────────────
══════════════════════════════════════════════════════════
```

The `:missing_item_fields` warning from the extractor correctly signals that the
supplement's `item_fields` were applied (suppressing the downstream `:missing_item_fields_schema`
at the linker layer), while the extractor still notes that the compiled format itself
doesn't carry item_fields.

---

## Design Decisions

### D1 — Source layer attribution is the primary organizing principle

All entries carry `:source_layer` (`:extractor`, `:overlay`, `:linker`). This tells
the developer *where* the issue originates — a compilation decision, a supplement
inconsistency, or a view-to-contract mismatch — which determines where to fix it.

### D2 — ReportEntry normalizes all diagnostic types

The three underlying structs (`ExtractionDiagnostic`, `OverlayDiagnostic`,
`LinkageDiagnostic`) have slightly different field names (`field` vs `slot`/`collection`).
`ReportEntry` normalizes to `field` + optional `collection`, consistent with a
"named output or slot" convention.

### D3 — `valid?` aggregates across all layers

`report.valid?` is `false` if any entry from any layer is `:error` severity.
A single `:supplement_to_non_array` error at the overlay layer or a
`:slot_type_mismatch` at the linker layer both make the report invalid.

### D4 — Missing layers are silently absent (nil-safe)

`LinkageReport.build` accepts `nil` for any result object. A report built with only
a `linkage_result` and no `extraction_result` or `overlay_result` is valid — it
just shows zero extractor/overlay entries. This enables progressive adoption:
start with just the linker layer, add extraction and overlay over time.

### D5 — Pipeline builder is a convenience, not the only path

`build_pipeline` runs the full extraction → supplement → link chain from file paths.
It is thin orchestration — no new logic, just calls the existing P6–P8 classes in
the canonical order. Advanced callers can build result objects themselves and
call `build` directly.

### D6 — JSON report excludes absolute paths (CI portability)

`to_h` uses semantic identifiers (`view_id`, `contract_id`) not file paths.
Diagnostic `detail` strings may mention output names or field names but not
filesystem paths. Proved by IVX-P9-10a: no `absolute-home-path/`, `/home/`, or `local-file URI`
in the report JSON.

### D7 — Text renderer is deterministic (extractor → overlay → linker order)

`to_text` always iterates layers in fixed order: `:extractor`, `:overlay`, `:linker`.
Within each layer, entries appear in insertion order (match input diagnostic order).
Two calls on the same report produce identical output (IVX-P9-9a).

---

## Full P1–P9 Pipeline

```
.igv file
  → IgvCompiler.compile_file(...)         → ViewArtifact (view_id, slots, elements, collections)

compiled contract (.igapp/contracts/*.json)
  → CompiledContractExtractor.extract(...)  → ExtractionResult { schema, diagnostics[:extractor] }

supplement JSON (fixtures/schema_supplements/*.json)
  → ContractSchemaSupplement.load_file(...) → ContractSchemaSupplement
  → supplement.apply_to(extracted_schema)   → OverlayResult { schema, diagnostics[:overlay] }

ViewArtifact + { contract_id => final_schema }
  → SlotTypeLinker.link(...)                → LinkageResult { valid?, diagnostics[:linker] }

ExtractionResult + OverlayResult + LinkageResult
  → LinkageReport.build(...)                → LinkageReport
     → report.to_h    (CI JSON)
     → report.to_text (terminal)
```

---

## Proof Matrix: IVX-P9-1 through IVX-P9-12

All 58 checks PASS as of 2026-06-06.

| ID | Description | Result |
|----|-------------|--------|
| IVX-P9-1 (×7) | P1/P2/P3/P5/P6/P7/P8 regression gates | ✅ |
| IVX-P9-2a..d | Extraction diagnostics: present, `source_layer=:extractor`, `:missing_item_fields`, attributed to `results` | ✅ |
| IVX-P9-3a..d | Overlay diagnostics: present, `source_layer=:overlay`, `:unknown_output_ref`, `valid?=true` | ✅ |
| IVX-P9-4a..d | Linker diagnostics: present, `source_layer=:linker`, `:slot_type_mismatch`, `valid?=false` | ✅ |
| IVX-P9-5a..d | Severity counts: total=sum by layer; entry_count=errors+warnings | ✅ |
| IVX-P9-6a..c | Stale supplement: `:unknown_output_ref` at overlay; valid entry applied; `:missing_item_fields_schema` absent | ✅ |
| IVX-P9-7a..c | Scalar override: `:supplement_to_non_array` at overlay; `valid?=false`; field=`query` | ✅ |
| IVX-P9-8a..c | Missing supplement: `:missing_item_fields_schema` at linker; `valid?=true`; zero overlay entries | ✅ |
| IVX-P9-9a..f | Text renderer: deterministic; header; layer markers; status line; VALID on happy path; file written | ✅ |
| IVX-P9-10a..e | JSON: no absolute paths; valid JSON; by_layer breakdown; `_status` marker; file written | ✅ |
| IVX-P9-10 (×10) | Source guards: no innerHTML/eval/fetch/Net::HTTP/contract exec/localStorage/sessionStorage/DOM/system | ✅ |
| IVX-P9-12 (×5) | Lab-only markers + `NON_CLAIMS` constant present | ✅ |

---

## Constraints Observed

- Zero modifications to `igniter-lang/**`
- No changes to any existing `lib/*.rb` file
- No absolute paths in `to_h` JSON output
- No contract execution, network, DOM, or storage access
- All new files carry `lab-only · no-canon · no-stable-schema` markers
