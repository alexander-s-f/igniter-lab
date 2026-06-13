# Vector Math Pressure Registry

Updated: 2026-06-13 (APP-RECHECK-WAVE-P3)

This registry tracks app pressure from `igniter-apps/vector_math`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| VM-P01 | BASELINE | Full Rust multi-file compilation | Rust lab compiler emits complete `igapp`: 6 source units, 37 contracts, artifact hash `sha256:289a586aeb172ccc35a55e23f5f400194d14cf8cbb246120881c205bb3ea3d9a` — still CLEAN in Wave P3 recheck (0 diagnostics) | `LAB-VECTOR-MATH-BASELINE-P1` |
| VM-P02 | POSITIVE | Pure contract math architecture | Vec2/Vec3/Mat3/AABB operations compile without IO/state/capability surface | preserve as positive app evidence |
| VM-P03 | WATCH | Integer milli-unit numeric model | `1000 = 1.0`; avoids Float/Decimal operator gaps | fixed-point / scale-aware numeric research |
| VM-P04 | RESOLVED | Unary negative literal workaround | Source uses `0 - N` forms instead of `-N`. LANG-UNARY-OPERATORS-P3/P4 CLOSED — unary `-` now dual-toolchain; `0 - N` workarounds in source are stale but no app edits in this wave | `LANG-UNARY-OPERATORS-P3/P4` CLOSED |
| VM-P05 | RESOLVED | Comparison operator ergonomics | App rewrites `>=`/`<=` using nested `<`/`>` checks. LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED — `<`, `<=`, `>=` added to Ruby TC; Wave P3 recheck: 0 comparison operator errors in Rust; Ruby now also clean on comparison ops | `LANG-STDLIB-NUMERIC-COMPARISON-P3` CLOSED |
| VM-P06 | RESOLVED | Ruby contract invocation parity | Wave P2: 26 `Unknown function: call_contract` diagnostics. Wave P3: LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED; all 26 call_contract errors gone; Ruby TC `when "call_contract"` arm dispatches Tier 1 same-module callee lookup | `LAB-RUBY-CALL-CONTRACT-PARITY-P3` CLOSED |
| VM-P07 | RESOLVED | Ruby numeric comparison parity | Wave P2: 8 `Unsupported operator: <` diagnostics. Wave P3: 0 comparison errors — LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED; `<`, `<=`, `>=` all handled in Ruby TC | `LANG-STDLIB-NUMERIC-COMPARISON-P3` CLOSED |
| VM-P08 | WATCH | Ruby record-shape cascades | Wave P2: predicted as cascade after upstream Unknown propagation. Wave P3: record-shape cascades still present; 36 "missing required field: r0/r1/r2" + "unexpected field: x/y/z" diagnostics — new VM-P10 opened | re-check after VM-P10 resolution |
| VM-P09 | ACTIVE | Typed compute binding gap (record literal) | Wave P3: Ruby shows 5 `Unresolved symbol` diags — `gravity`, `point`, `b`, `a_min`, `min_pt`. Wave P4: unchanged — LANG-TYPED-COMPUTE-BINDING-P2 had no effect. Root cause re-classified: unannotated record literal computes; Ruby TC `infer_record_literal` returns Unknown when no output_type_hint is set | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |
| VM-P10 | ACTIVE | Record literal field name mismatch | Wave P3: Ruby emits 36 `missing required field: r0`/`r1`/`r2` + `unexpected field: x`/`y`/`z` diagnostics; record literal shapes in vec2.ig/vec3.ig use field names `x/y/z` but type declaration uses `r0/r1/r2` (or vice versa); newly surfaced once call_contract P3 resolves and propagates proper types downstream | field name alignment in type declarations vs record literal call sites |

## Live Commands Used

Rust real compile:

```bash
cargo run -- compile ../igniter-apps/vector_math/types.ig ../igniter-apps/vector_math/vec2.ig ../igniter-apps/vector_math/vec3.ig ../igniter-apps/vector_math/mat3.ig ../igniter-apps/vector_math/geometry.ig ../igniter-apps/vector_math/example.ig --out /tmp/vector-math-rust.igapp
```

Ruby real compile:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig vec2.ig vec3.ig mat3.ig geometry.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/vector_math/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/vector-math-ruby.igapp"); puts JSON.pretty_generate(result)'
```

## Wave P2 Recheck Summary (2026-06-12)

Rust: CLEAN (0 diagnostics). Ruby: oof (34 diagnostics — 26× `Unknown function: call_contract`, 8× `Unsupported operator: <`). No resolutions in Wave P2 for this app.

## Wave P4 Recheck Summary (2026-06-13)

Rust: CLEAN (ok / 0 diagnostics). Ruby: oof / 41 diagnostics — unchanged from Wave P3. LANG-TYPED-COMPUTE-BINDING-P2 had zero effect: `gravity`, `point`, `b`, `a_min`, `min_pt` are unannotated record literal computes. VM-P09 route updated to `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1`. VM-P10 (36× field name mismatch) unchanged. No new pressures.

## Wave P3 Recheck Summary (2026-06-13)

Rust: CLEAN (ok / 0 diagnostics). Ruby: oof / 41 diagnostics — 5× `Unresolved symbol` (gravity/point/b/a_min/min_pt) + 36× record literal mismatch (`missing required field: r0/r1/r2` + `unexpected field: x/y/z`). Resolutions since Wave P2: VM-P06 RESOLVED — LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED; 26 call_contract errors eliminated. VM-P07 RESOLVED — LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED; 8 `<` operator errors eliminated. Remaining blockers: typed compute binding gap — 5 unresolved symbols (VM-P09); record literal field name mismatch — 36 diagnostics newly surfaced after upstream resolution (VM-P10).

## Notes

- Treat this app as a positive Rust baseline; VM-P01 still CLEAN in Wave P3.
- VM-P04 (unary minus) and VM-P05 (comparison ops) are RESOLVED — unary minus and `<`/`<=`/`>=` are dual-toolchain.
- VM-P06 (call_contract Ruby parity) RESOLVED — LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED.
- VM-P07 (Ruby `<` operator) RESOLVED.
- Remaining Ruby blockers: VM-P09 (typed compute binding; 5 unresolved symbols) + VM-P10 (record literal field name mismatch; 36 diags newly visible).
- VM-P10 is a new diagnostic surface — field names in record literals do not match field names in type declarations; may require app-level hygiene fix (not a compiler feature gap) or investigation into type declaration field name conventions.
- VM-P08 reclassified from WATCH to active monitoring: prior prediction (cascades after upstream Unknown) is partially borne out by VM-P10 being downstream visibility, but VM-P10 is a distinct shape issue.
