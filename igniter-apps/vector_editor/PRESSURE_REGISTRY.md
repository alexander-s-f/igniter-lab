# Vector Editor Pressure Registry

Updated: 2026-06-14 — APP-RECHECK-WAVE-P11

This registry tracks app pressure from `igniter-apps/vector_editor`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| VE-P01 | RESOLVED | `stdlib.collection` import surface | Wave recheck: Ruby reports 0 OOF-IMP2 (7 call_contract diags instead); Rust reports 1 diag (call_contract callee); `stdlib.collection` recognized via inventory (append/map/filter/is_empty entries present) | `LANG-STDLIB-COLLECTION-APPEND-PROP-P3` inventory entry |
| VE-P02 | RESOLVED | `append` via call_contract (Rust) | Rust wave recheck: 1 diag `call_contract: unknown callee 'append' — not found in this module`. P2 migration: VE-S01 `call_contract("append", layer.objects, obj)` → `append(layer.objects, obj)` in document.ig; `layer.objects : Collection[GraphicObject]` typed from input; Rust ok/0 | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |
| VE-P03 | RESOLVED | Stringly stdlib append invocation | P2 migration resolved the stdlib-form append site in document.ig (VE-S01). Remaining Ruby diag (`Unresolved symbol: new_objects` cascade) also cleared when append resolved. User PascalCase `call_contract("AppendObjectToLayer", ...)` preserved | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |
| VE-P04 | RESOLVED | Text equality | Wave recheck: no `Unsupported operator: ==` in Ruby or Rust output; `==` now in `operator_type` via LANG-STDLIB-TEXT-EQUALITY-P3 | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| VE-P05 | ACTIVE | Variant/ADT surface | `GraphicObject` uses `kind : String` plus optional payload records | variant/ADT surface follow-up |
| VE-P06 | WATCH | App-state / command reducer shape | `HandleCanvasClick(Document, ToolState, Point) -> Document` exposes pure UI command transition shape | app-state / app-assembly track |
| VE-P07 | WATCH | Numeric geometry | Integer coordinate workaround avoids Float/Decimal gaps | numeric/fixed-point stdlib track |
| VE-P08 | RESOLVED | Typed compute binding gap (split) | Wave P3: 3 cascade `Unresolved symbol` diags — `new_objects`, `default_style`, `new_pos`. Root cause split: `new_objects` → stringly migration (VE-S01 resolved in P2); `default_style` + `new_pos` → LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 (Wave P6). All three cascade symbols now resolved. VE-P09 (`new_obj`) newly exposed after cascade cleared | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` + `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` CLOSED |

## Live Commands Used

Rust real compile:

```bash
cargo run -- compile ../igniter-apps/vector_editor/types.ig ../igniter-apps/vector_editor/transform.ig ../igniter-apps/vector_editor/document.ig ../igniter-apps/vector_editor/tools.ig --out /tmp/vector-editor-rust.igapp
```

Ruby real compile:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig transform.ig document.ig tools.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/vector_editor/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/vector-editor-ruby.igapp"); puts JSON.pretty_generate(result)'
```

Probe: temporary copy in `/tmp/vector_editor_probe` with only `import stdlib.collection.{ append, map }` removed from `document.ig`.

## Wave P2 Recheck Summary (2026-06-12)

Rust: oof (1 diagnostic — `call_contract: unknown callee 'append'`). Ruby: oof (7 diagnostics — 4× `Unknown function: call_contract`, 3× `Unresolved symbol` cascade). No new resolutions in Wave P2 for this app; all prerequisite cards (append/equality/encoding) were already captured in P1. Dominant blocker is call_contract parity (VE-P02/P03) on both toolchains.

## LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 Recheck (2026-06-13)

Ruby: oof/1 — `OOF-P1 Unresolved symbol: new_obj` (VE-P09, pre-existing, unrelated to stringly migration). VE-P02, VE-P03, VE-P08 (`new_objects` sub-pressure) all RESOLVED.  
Rust: **ok/0** — stringly append site resolved; no other Rust diags.  
vector_editor is **Rust CLEAN**. Ruby residual is VE-P09 only.

## Wave P6 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic — unchanged (`call_contract: unknown callee 'append'`). Ruby: oof / 3 diagnostics (was 4, −1). LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved the 2 ACTIVE_TRUE_INTERMEDIATE symbols from VE-P08: `default_style` (tools.ig) and `new_pos` (transform.ig) now infer their record types. VE-P08 partially resolved. Remaining Ruby diags: 1× `call_contract: unknown callee 'append'` (VE-P02/P03 stringly append — unchanged), `Unresolved symbol: new_objects` (cascade from append — unchanged), `Unresolved symbol: new_obj` (new cascade, see VE-P09). VE-P09 NEW: `compute new_obj = { ... }` in tools.ig (tools.ig:21) is an unannotated record literal that was previously hidden behind `default_style` being Unknown; now that `default_style` resolves, the P3 structural fallback for `new_obj` should fire — but `new_obj` is a `GraphicObject`-shaped literal; `new_obj`'s fields include `style: default_style` where `default_style` is now typed, plus other fields. Likely matches `GraphicObject` or a sub-type. Needs investigation; classified ACTIVE_TRUE_INTERMEDIATE pending next wave. No regressions.

| VE-P09 | ACTIVE | Newly exposed unannotated record literal compute (`new_obj` in tools.ig) | Wave P6: `Unresolved symbol: new_obj` — exposed after VE-P08 partial resolution; `compute new_obj = { pos: ..., layer_id: ..., style: default_style, ... }` (tools.ig:21) was previously hidden behind `default_style` Unknown cascade; P3 resolved `default_style` first, then `new_obj` must be re-evaluated; appears to be another ACTIVE_TRUE_INTERMEDIATE | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` or re-run P3 candidate matching |

## Wave P5 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic — unchanged from Wave P4. Ruby: oof / 4 diagnostics — unchanged from Wave P4. LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had zero effect: VE-P08 root causes are stringly `call_contract("append", ...)` return (NOT_RECORD_LITERAL: `new_objects`) and unannotated record literals (ACTIVE_TRUE_INTERMEDIATE: `default_style`, `new_pos`) — none are annotated `compute name : Type = { ... }` forms. No new pressures.

## Wave P4 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic — unchanged from Wave P3. Ruby: oof / 4 diagnostics — unchanged from Wave P3. LANG-TYPED-COMPUTE-BINDING-P2 had zero effect. Root cause split confirmed: `new_objects` is a stringly `call_contract("append", ...)` return; `default_style` and `new_pos` are unannotated record literals. VE-P08 route split accordingly. No new pressures.

## Wave P3 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic — `call_contract: unknown callee 'append' — not found in this module`. Ruby: oof / 4 diagnostics — `call_contract: unknown callee 'append'`, `Unresolved symbol: new_objects`, `Unresolved symbol: default_style`, `Unresolved symbol: new_pos`. Resolutions since Wave P2: 4 Tier 1 same-module call_contract calls resolved by LAB-RUBY-CALL-CONTRACT-PARITY-P3 (Ruby was 7 diags, now 4). Remaining blockers: 1 stdlib-form 'append' callee unresolved in both toolchains (VE-P02/VE-P03); 3 cascade unresolved symbols — typed compute binding gap (VE-P08).

## Notes

- Import surface (VE-P01) and equality (VE-P04) are resolved.
- The dominant remaining blocker is call_contract parity (VE-P02/P03): both Rust and Ruby TC don't dispatch stdlib functions via `call_contract("name", ...)` form.
- `call_contract` evidence here should feed typed refs/forms work, not a runtime-dispatch expansion.
- The `GraphicObject` encoding is useful as pressure evidence precisely because it is awkward.

## Wave P7 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: oof / 1 diagnostic (`Unresolved symbol: new_obj` — OOF-P1) — unchanged. VE-P09 ACTIVE. Route: `LAB-VE-NEW-OBJ-INFERENCE-P1` or app-level refactor of `new_obj` call sites. No new pressures. No regressions.

## Wave P8 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: oof / 1 diagnostic (`Unresolved symbol: new_obj` — OOF-P1) — unchanged. VE-P09 ACTIVE. LANG-STRING-TEXT-ALIAS-P2, LANG-RUBY-RECORD-LITERAL-INFERENCE-P5, LANG-STDLIB-STRING-SUBSTRING-P2 all had no effect on vector_editor. No new pressures. No regressions.

## LAB-VE-NEW-OBJ-INFERENCE-P1 Resolution (2026-06-13)

VE-P09 RESOLVED. Root cause: Classification 1 (app-source shape issue). `GraphicObject` has 7 fields in `@type_shapes` — the parser strips `?` from optional annotations, making all fields appear required. The original `new_obj` provided only 5 fields; P3 structural matching requires exact field set equality, so no candidates → Unknown → OOF-P1.

Fix (tools.ig only):
- Added `compute default_text = { content: "", font_size: 0 }` (provides TextData-shaped literal)
- Annotated `compute new_obj : GraphicObject = { ... }` (activates hint path)
- Extended fields: added `path_pts: []` and `text_data: default_text`

Post-fix: Ruby ok / 0, Rust ok / 0. **vector_editor DUAL-CLEAN.**

| VE-P09 | RESOLVED | Unannotated record literal `new_obj` (5/7 fields) → Unknown → OOF-P1 | Root cause: `?` suffix stripped by parser; P3 structural match requires exact field set. Fix: annotation + `default_text` compute + `path_pts: []` + `text_data: default_text` | `LAB-VE-NEW-OBJ-INFERENCE-P1` CLOSED |

## Wave P9 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics (was oof/1 in Wave P8 — VE-P09 RESOLVED by LAB-VE-NEW-OBJ-INFERENCE-P1). DUAL-CLEAN. No new pressures. No regressions.

## Wave P10 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. VE-P09 remains resolved. No new pressures. No regressions.

## Wave P11 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN.

Companion baseline integration (`air_combat`, `lead_router`, `call_router`) and Fold P3/P4 landing had no diagnostic impact on this app. No pressure ID changes this wave. No new pressures. No regressions.

## Wave P12 Recheck Summary (2026-06-15)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

The 20-app fleet expansion and new companion intake (`audit_ledger`, `batch_importer`, `job_runner`, `web_router`) had no diagnostic impact on this app. VE-P09 remains resolved. No pressure ID changes. No new pressures. No regressions.

## Wave P13 Recheck Summary (2026-06-15)

Ruby: ok/0. Rust: ok/0. DUAL-CLEAN. Source files: 4. Source hash: `sha256:cafd7085a537f8efb8751ebe48148fbc9931ebb10041babb6f4b33f1b20fb2fc`. Entrypoint: `none`. unchanged clean app.
No source changes in this wave. No new pressures. No regressions.
