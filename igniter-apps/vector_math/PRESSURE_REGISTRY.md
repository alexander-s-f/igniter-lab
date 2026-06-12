# Vector Math Pressure Registry

Updated: 2026-06-12

This registry tracks app pressure from `igniter-apps/vector_math`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| VM-P01 | BASELINE | Full Rust multi-file compilation | Rust lab compiler emits complete `igapp`: 6 source units, 37 contracts, artifact hash `sha256:289a586aeb172ccc35a55e23f5f400194d14cf8cbb246120881c205bb3ea3d9a` | `LAB-VECTOR-MATH-BASELINE-P1` |
| VM-P02 | POSITIVE | Pure contract math architecture | Vec2/Vec3/Mat3/AABB operations compile without IO/state/capability surface | preserve as positive app evidence |
| VM-P03 | WATCH | Integer milli-unit numeric model | `1000 = 1.0`; avoids Float/Decimal operator gaps | fixed-point / scale-aware numeric research |
| VM-P04 | ACTIVE | Unary negative literal workaround | Source uses `0 - N` forms instead of `-N` | `LANG-PARSER-UNARY-MINUS-P1` |
| VM-P05 | ACTIVE | Comparison operator ergonomics | App rewrites `>=`/`<=` using nested `<`/`>` checks | numeric comparison parity slice |
| VM-P06 | ACTIVE | Ruby contract invocation parity | Ruby emits 26 `Unknown function: call_contract` diagnostics | typed refs / invocation forms / Ruby parity follow-up |
| VM-P07 | ACTIVE | Ruby numeric comparison parity | Ruby emits 8 `Unsupported operator: <` diagnostics | `LANG-NUMERIC-COMPARISON-PARITY-P1` |
| VM-P08 | WATCH | Ruby record-shape cascades | Record-shape diagnostics appear after upstream Unknown propagation | re-check after invocation parity |

## Live Commands Used

Rust real compile:

```bash
cargo run -- compile ../igniter-apps/vector_math/types.ig ../igniter-apps/vector_math/vec2.ig ../igniter-apps/vector_math/vec3.ig ../igniter-apps/vector_math/mat3.ig ../igniter-apps/vector_math/geometry.ig ../igniter-apps/vector_math/example.ig --out /tmp/vector-math-rust.igapp
```

Ruby real compile:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig vec2.ig vec3.ig mat3.ig geometry.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/vector_math/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/vector-math-ruby.igapp"); puts JSON.pretty_generate(result)'
```

## Notes

- Treat this app as a positive baseline, not just a pressure map.
- Preserve the Rust full-compile property when touching multi-file, typechecker, emitter, or assembler code.
- Ruby diagnostics should be re-read after invocation parity before opening record-shape-specific work.
