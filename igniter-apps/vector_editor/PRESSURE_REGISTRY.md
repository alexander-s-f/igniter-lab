# Vector Editor Pressure Registry

Updated: 2026-06-13 (APP-RECHECK-WAVE-P3)

This registry tracks app pressure from `igniter-apps/vector_editor`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| VE-P01 | RESOLVED | `stdlib.collection` import surface | Wave recheck: Ruby reports 0 OOF-IMP2 (7 call_contract diags instead); Rust reports 1 diag (call_contract callee); `stdlib.collection` recognized via inventory (append/map/filter/is_empty entries present) | `LANG-STDLIB-COLLECTION-APPEND-PROP-P3` inventory entry |
| VE-P02 | ACTIVE | `append` via call_contract (Rust) | Rust wave recheck: 1 diag `call_contract: unknown callee 'append' — not found in this module`; document.ig uses `call_contract("append", layer.objects, obj)` not bare `append(...)`; Rust TC stdlib dispatch doesn't cover stringly-typed call_contract form | call_contract parity follow-up |
| VE-P03 | ACTIVE | Stringly contract invocation | Wave P2: 7 diags (4× `Unknown function: call_contract` + 3× `Unresolved symbol`). Wave P3: 4 diags remain — 1× `call_contract: unknown callee 'append'` (stdlib form) + 3× `Unresolved symbol: new_objects/default_style/new_pos` (cascade). P3 resolved 4 Tier 1 same-module call_contract calls; stdlib-form 'append' callee still blocked in both Rust and Ruby | stringly stdlib migration + call_contract parity |
| VE-P04 | RESOLVED | Text equality | Wave recheck: no `Unsupported operator: ==` in Ruby or Rust output; `==` now in `operator_type` via LANG-STDLIB-TEXT-EQUALITY-P3 | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| VE-P05 | ACTIVE | Variant/ADT surface | `GraphicObject` uses `kind : String` plus optional payload records | variant/ADT surface follow-up |
| VE-P06 | WATCH | App-state / command reducer shape | `HandleCanvasClick(Document, ToolState, Point) -> Document` exposes pure UI command transition shape | app-state / app-assembly track |
| VE-P07 | WATCH | Numeric geometry | Integer coordinate workaround avoids Float/Decimal gaps | numeric/fixed-point stdlib track |
| VE-P08 | ACTIVE | Typed compute binding gap (split) | Wave P3: 3 cascade `Unresolved symbol` diags — `new_objects`, `default_style`, `new_pos`. Wave P4: unchanged — LANG-TYPED-COMPUTE-BINDING-P2 had no effect. Root cause split: `new_objects` = stringly `call_contract("append", ...)` return (route: stringly stdlib migration); `default_style` and `new_pos` = unannotated record literals (route: `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1`) | stringly stdlib migration + `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |

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

## Wave P4 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic — unchanged from Wave P3. Ruby: oof / 4 diagnostics — unchanged from Wave P3. LANG-TYPED-COMPUTE-BINDING-P2 had zero effect. Root cause split confirmed: `new_objects` is a stringly `call_contract("append", ...)` return; `default_style` and `new_pos` are unannotated record literals. VE-P08 route split accordingly. No new pressures.

## Wave P3 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic — `call_contract: unknown callee 'append' — not found in this module`. Ruby: oof / 4 diagnostics — `call_contract: unknown callee 'append'`, `Unresolved symbol: new_objects`, `Unresolved symbol: default_style`, `Unresolved symbol: new_pos`. Resolutions since Wave P2: 4 Tier 1 same-module call_contract calls resolved by LAB-RUBY-CALL-CONTRACT-PARITY-P3 (Ruby was 7 diags, now 4). Remaining blockers: 1 stdlib-form 'append' callee unresolved in both toolchains (VE-P02/VE-P03); 3 cascade unresolved symbols — typed compute binding gap (VE-P08).

## Notes

- Import surface (VE-P01) and equality (VE-P04) are resolved.
- The dominant remaining blocker is call_contract parity (VE-P02/P03): both Rust and Ruby TC don't dispatch stdlib functions via `call_contract("name", ...)` form.
- `call_contract` evidence here should feed typed refs/forms work, not a runtime-dispatch expansion.
- The `GraphicObject` encoding is useful as pressure evidence precisely because it is awkward.
