# Card: LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3

**Title:** Per-file source mapping for multifile/project-mode diagnostics
**Skill:** idd-agent-protocol
**Lane:** standard / compiler DX foundation
**Status:** ✅ CLOSED — 2026-06-17
**Authority:** igniter-lab only; no canon impact; no production impact
**Builds on:** LAB-COMPILER-PROJECT-MODE-COMPILE-P1, LAB-COMPILER-PROJECT-OVERLAY-P2
**Motivated by:** LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7, LAB-JETBRAINS-PROJECT-MODE-RUNIDE-SMOKE-P8
**Proof:** `lab-docs/lang/lab-compiler-multifile-source-map-p3-v0.md`

---

## Card Statement

Add a compiler-side source map for multifile / project-mode builds: record, per
emitted merged line, the originating `{ source_path, module_path, original_line }`,
emit it as evidence, and enrich diagnostics that carry a merged line.

## Authority boundary (named before coding)

- **Decides behavior:** the live `igniter_compiler` (`multifile` merge + `main` report).
- **Evidence only:** this card, the proof doc, test output.
- **Authorized to change:** `igniter-compiler` (`multifile.rs`, `main.rs`) + tests.
- **Closed surfaces:** parser/typechecker semantics, `line`/`col` meaning, the merged
  source bytes, the JetBrains plugin, package/module namespaces.

## What landed

- `multifile.rs`: `SourceLineMapEntry { merged_line, source_path, module_path,
  original_line }`; `merged_source_with_map` (single pass, byte-identical merged text);
  `MergedProgram.source_line_map: Vec<Value>`; `compile_units` populates it.
- `main.rs`: `run_compiler_source` takes `source_line_map`; `attach_source_line_map`
  writes it to semantic IR + compilation report and calls `enrich_diagnostics_with_origin`
  (adds origin fields to diagnostics whose `line` matches a merged line; leaves
  `line`/`col` untouched). Parse-error branch also attaches + enriches. Single-file
  passes `None`.

## Mapping shape + emission

`{ "merged_line":11, "source_path":".../b.ig", "module_path":"Map.B", "original_line":5 }`
emitted to `semantic_ir_program.json.source_line_map`, `compilation_report.json.source_line_map`
(and the parse-error report).

## Enrichment status (honest)

- **Parser errors** carry a numeric merged line → enriched with origin (proven:
  merged `line:11` → `b.ig` / `Map.B` / `original_line:5`).
- **Typecheck `OOF-P1`** carries `line:null` (verified live) → cannot be enriched yet;
  the `source_line_map` is still emitted as evidence. Adding typecheck spans is a
  parser/typechecker change, out of scope (hard boundary).

## Acceptance — all met

1. Existing multifile unchanged (byte-identical merged text; P1/P2 green) ✅
2. P1 `project_mode_tests` 9/9 ✅
3. P2 `project_overlay_tests` 10/10 ✅
4. Two-file map back to source_path/module/original_line ✅
5. Skipped header lines keep original line numbers (b.ig min original_line=3) ✅
6. Overlay map source_path = overlay buffer path (P2-honest) ✅
7. Enrichment: parse diags enriched; typecheck `OOF-P1` null-line documented + tested ✅
8. No regression to single-file (no `source_line_map` key) ✅
9. Focused tests + reruns + honest loop report ✅

## Verification

```
cd igniter-compiler
cargo test --test multifile_source_map_tests --quiet   # 6 passed
cargo test --test project_mode_tests        --quiet   # 9 passed
cargo test --test project_overlay_tests     --quiet   # 10 passed
cargo test --no-fail-fast --quiet
#   effect_name_parity:        4 passed
#   loop_conformance:         10 passed / 4 failed  (PRE-EXISTING; unrelated — see P1 proof)
#   multifile_source_map:      6 passed
#   project_mode:              9 passed
#   project_overlay:          10 passed
```

## Next / deferred

- **Next JetBrains route:** `LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9` —
  plugin consumes `source_line_map` to annotate each diagnostic in its originating file
  instead of merged coordinates.
- Deferred: real merged spans for typecheck/classify diagnostics; `original_col`;
  `source_units` parity on the hard parse-failure path.
