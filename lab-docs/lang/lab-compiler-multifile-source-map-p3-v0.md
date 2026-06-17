# lab-compiler-multifile-source-map-p3-v0

Proof doc for card `LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3` — add a compiler-side
per-file source map for multifile / project-mode builds, so diagnostics on the
merged `Lab.Multifile.Universe` program can be traced back to the original source
unit + line.

**Status:** CLOSED. **Skill:** idd-agent-protocol (verify-first; the live compiler
is authority). **Lane:** standard / compiler DX foundation. **Builds on:** P1
(project mode) + P2 (overlay). **Motivated by:** P7 / P8 (the editor diagnostics
gap).

> Compiler only. No language/parser/typechecker semantics change; no diagnostic
> suppression; no JetBrains changes; no overlay source-path aliasing (kept honest:
> the map carries whatever path was handed to `compile_units`).

## Verify-first findings (live surfaces)

- `multifile::merged_source` builds the merged program: a `module
  Lab.Multifile.Universe` header, then per unit a `-- source_module: <mod>` marker,
  the unit's lines with `module`/`import` lines stripped, and a trailing blank.
- `multifile::compile_units` returns `MergedProgram { source_path, source_hash,
  source, source_units }`; `source_hash` is `composite_source_hash` over the unit
  contents (independent of the merged text).
- `main::run_compiler_source` is shared by single-file and multifile; it lexes +
  parses the merged `source`. `attach_source_units` writes `source_units` into the
  semantic IR + compilation report (only on the non-parse-error path).
- Diagnostic shape: typecheck `OOF-P1` on a merged program carries **`line: null,
  col: null`**; parser errors carry a numeric **merged** `line`.

## Exact mapping shape

```json
{ "merged_line": 11, "source_path": ".../b.ig", "module_path": "Map.B", "original_line": 5 }
```

`SourceLineMapEntry { merged_line, source_path, module_path, original_line }`
(all 1-based). One entry per *emitted* source line; synthetic lines (the universe
header, `-- source_module:` markers, trailing blanks) are not mapped. Built in a
single pass in `merged_source_with_map`, which produces byte-identical merged text
to the previous `merged_source` (header, markers, stripping, trailing blank all
unchanged), so `source` / `source_hash` and all downstream behavior are unaffected.

Stripped `module`/`import` lines still advance the original-line counter, so the
first emitted line of an importing file keeps its true file line number (e.g. b.ig's
first emitted line is `original_line: 3`, not compacted to 1) — acceptance 5.

## Where it is emitted

- `semantic_ir_program.json` → `source_line_map` (array)
- `compilation_report.json` → `source_line_map` (array)
- On the **parse-error** path as well (its report is built separately) so import-file
  parse errors are traceable.

Threaded as `MergedProgram.source_line_map` → `run_compiler_source(..,
source_line_map)` → `attach_source_line_map` (success/OOF paths) and the parse-error
branch. Single-file builds pass `None` → no `source_line_map` key (acceptance 8).

## Diagnostics enrichment — what can and cannot be enriched today

`enrich_diagnostics_with_origin` adds `source_path` / `module_path` /
`original_line` to any diagnostic whose `line` matches a `merged_line` in the map.
The existing `line` / `col` fields are left untouched (still merged coordinates) —
consumers opt in via the new fields.

| Diagnostic class | merged `line`? | enriched? |
|------------------|----------------|-----------|
| Parser errors (e.g. malformed contract in an imported file) | numeric (merged) | ✅ yes — e.g. merged `line: 11` → `source_path: b.ig`, `module_path: Map.B`, `original_line: 5` |
| Typecheck `OOF-P1` (unresolved field across units) | **`null`** | ❌ no — there is no merged line to map from |

**Why typecheck OOF cannot be enriched yet:** the merged-program typechecker emits
`OOF-P1` with `line: null` / `col: null` (verified live). Enrichment keys on the
merged line, so a null-line diagnostic has nothing to map. Giving typecheck
diagnostics real merged spans is a parser/typechecker change explicitly out of scope
here (hard boundary). The `source_line_map` is still emitted as evidence in that
case, so a future consumer (or a follow-up card that adds typecheck spans) can map
them. Parser errors already enrich today, proving the mechanism is live.

## Overlay honesty (acceptance 6)

In project mode + overlay, the overlaid unit's map entries carry the **overlay
buffer path** (the path handed to `compile_units`), matching P2 `source_units`
behavior. No aliasing was added. Verified by `overlay_line_map_uses_buffer_path`.

## Acceptance matrix — all met

| # | Requirement | Result |
|---|-------------|--------|
| 1 | Existing multifile compile unchanged | ✅ merged text byte-identical; `source_hash` unaffected; P1/P2 suites green |
| 2 | Project-mode P1 tests pass | ✅ `project_mode_tests` 9/9 |
| 3 | Overlay P2 tests pass | ✅ `project_overlay_tests` 10/10 |
| 4 | Two-file map back to source_path/module/original_line | ✅ `valid_multifile_maps_lines_back_to_units` |
| 5 | Skipped header lines keep original line numbers | ✅ same test (b.ig min original_line = 3) |
| 6 | Overlay evidence honest (buffer path) | ✅ `overlay_line_map_uses_buffer_path` |
| 7 | Diagnostics enrichment (or documented limitation) | ✅ parse errors enriched (`parse_error_diagnostic_is_enriched_with_origin`); typecheck OOF `line:null` documented + tested (`typecheck_oof_has_null_line_and_is_not_enriched`) |
| 8 | No regression to single-file reports | ✅ `single_file_has_no_source_line_map` |
| 9 | Focused tests + rerun P1/P2 + honest loop report | ✅ below |

## Exact test counts

```
cd igniter-compiler
cargo test --test multifile_source_map_tests --quiet   # 6 passed; 0 failed
cargo test --test project_mode_tests        --quiet   # 9 passed; 0 failed
cargo test --test project_overlay_tests     --quiet   # 10 passed; 0 failed
cargo test --no-fail-fast --quiet
#   effect_name_parity_tests:  4 passed
#   loop_conformance_tests:   10 passed / 4 failed   (PRE-EXISTING; SemanticIR loop_node
#                                                     assertions, unrelated — see P1 proof)
#   multifile_source_map_tests: 6 passed
#   project_mode_tests:         9 passed
#   project_overlay_tests:     10 passed
```

Fixtures: `igniter-compiler/tests/fixtures/source_map/` — `a.ig` (`module Map.A`,
type), `b.ig` (`module Map.B` importing `Map.A`, valid contract), `b_parse_error.ig`
(bad token on original line 5), `b_typecheck_oof.ig` (unresolved field → `OOF-P1`).

## Authority boundary

igniter-lab only. No canon/production impact. Parser/typechecker semantics, `line`/
`col` meaning, and the merged-source bytes are all unchanged. The live compiler is
authority; this doc is evidence.

## Next JetBrains route

`LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9`: the plugin reads
`source_line_map` from the project-mode report and maps each diagnostic back to its
originating file + line for precise cross-file editor annotations — instead of the
P7 merged-coordinate behavior. Note for P9: enrichment is currently populated for
parse diagnostics; typecheck `OOF-P1` still arrives with `line:null`, so P9 either
consumes the enriched fields where present or waits on a typecheck-span card.

## Intentionally deferred

- Real merged spans for typecheck/classify diagnostics (parser/typechecker change).
- Expression-level / column precision (`original_col`) — line granularity only here.
- Attaching the map on the hard parse-failure path *and* `source_units` parity there
  (kept consistent with existing behavior; map IS attached on parse-error, matching
  where parse diagnostics live).
