# Vector Editor Pressure Registry

Updated: 2026-06-12

This registry tracks app pressure from `igniter-apps/vector_editor`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| VE-P01 | ACTIVE | `stdlib.collection` import surface | Both Rust and Ruby stop at `OOF-IMP2 unknown import path 'stdlib.collection'` in `VectorDocument` | `LANG-STDLIB-IMPORT-SURFACE-P1` |
| VE-P02 | ACTIVE | `append` collection helper | Probe without stdlib import reaches Rust `OOF-TY0 call_contract: unknown callee 'append'` | `LANG-STDLIB-COLLECTION-APPEND-P1` |
| VE-P03 | ACTIVE | Stringly contract invocation | `call_contract("AddObjectToDoc", ...)`, `call_contract("CreateAndAppendRect", ...)`, `call_contract("AppendObjectToLayer", ...)` | typed contract refs / invocation forms follow-up |
| VE-P04 | ACTIVE | Text equality | Probe reaches Ruby `Unsupported operator: ==` for layer IDs and active tool dispatch | `LANG-STDLIB-TEXT-EQUALITY-P1` |
| VE-P05 | ACTIVE | Variant/ADT surface | `GraphicObject` uses `kind : String` plus optional payload records | variant/ADT surface follow-up |
| VE-P06 | WATCH | App-state / command reducer shape | `HandleCanvasClick(Document, ToolState, Point) -> Document` exposes pure UI command transition shape | app-state / app-assembly track |
| VE-P07 | WATCH | Numeric geometry | Integer coordinate workaround avoids Float/Decimal gaps | numeric/fixed-point stdlib track |

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

## Notes

- The app should remain pressure-only until stdlib import surface and append semantics are clearer.
- `call_contract` evidence here should feed typed refs/forms work, not a runtime-dispatch expansion.
- The `GraphicObject` encoding is useful as pressure evidence precisely because it is awkward.
