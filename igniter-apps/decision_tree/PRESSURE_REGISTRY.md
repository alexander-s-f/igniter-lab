# Decision Tree Pressure Registry

Updated: 2026-06-14 (APP-RECHECK-WAVE-P10 — DUAL-CLEAN)

This registry tracks app pressure from `igniter-apps/decision_tree`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| DT-P01 | RESOLVED | `stdlib.collection` import surface | Wave recheck: Rust shows 4 diags (all `call_contract: unknown callee 'append'`), no OOF-IMP2; `stdlib.collection` recognized in inventory | `LANG-STDLIB-COLLECTION-APPEND-PROP-P3` inventory |
| DT-P02 | RESOLVED | Ruby parser keyword hygiene | Wave P2: Ruby stopped at `ParseError: Expected name, got keyword(label)`. Wave P3: LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 CLOSED — `name_token!` now accepts `%i[ident keyword]` in all binding positions; `label` is valid as a binding name; Ruby progresses to TC | `LANG-PARSER-CONTEXTUAL-KEYWORDS-P2` CLOSED |
| DT-P03 | RESOLVED | `append` via call_contract | Wave P3: Rust 4 diags (4× `call_contract: unknown callee 'append'`); Ruby 7 diags (4× `call_contract: unknown callee 'append'` + 3× `Unresolved symbol` cascade). P2 migration: all 4 sites migrated — DT-S01 (`nodes_0` BOOTSTRAP), DT-S02 (`features_good` BOOTSTRAP), DT-S03 (`features_bad` BOOTSTRAP), DT-S04 (`new_nodes` ACCUMULATING in builder.ig); both TCs now ok/0 | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |
| DT-P04 | ACTIVE | Single-element collection extraction | `FindNodeById` and `LookupFeature` can only return `Collection[T]`; no `head`/`first`/`find_one` | `LAB-STDLIB-FIND-ONE-P1` |
| DT-P05 | RESOLVED | Text equality | Wave recheck (Rust): 0 equality errors; `==` works via Rust TC; Ruby blocked by DT-P02 but LANG-STDLIB-TEXT-EQUALITY-P3 implements `==` in Ruby `operator_type` | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| DT-P06 | WATCH | Managed traversal | `Evaluate` is fixed-depth unrolled because tree traversal cannot recurse/loop safely | managed recursion / bounded traversal follow-up |
| DT-P07 | ACTIVE | Variant/ADT surface | `TreeNode` uses `kind` plus sentinel fields for leaf vs decision nodes | variant/ADT surface follow-up |
| DT-P08 | WATCH | Contract invocation return shape | Single-output `call_contract` collapses to scalar, not wrapper record | typed refs / invocation forms docs |
| DT-P09 | RESOLVED | Typed compute binding gap (stringly call_contract) | Wave P3: 3 cascade `Unresolved symbol` diags — `new_nodes`, `nodes_0`, `features_good`. Root cause: cascade from stringly `call_contract("append", ...)` failures. P2 migration resolved all 4 append sites; all cascade symbols now resolved. Both TCs ok/0 | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED |

## Live Commands Used

Rust real compile:

```bash
cargo run -- compile ../igniter-apps/decision_tree/types.ig ../igniter-apps/decision_tree/builder.ig ../igniter-apps/decision_tree/evaluator.ig ../igniter-apps/decision_tree/example.ig --out /tmp/decision-tree-rust.igapp
```

Ruby real compile:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig builder.ig evaluator.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/decision_tree/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/decision-tree-ruby.igapp"); puts JSON.pretty_generate(result)'
```

Probes:

- Rust probe: temporary copy in `/tmp/decision_tree_probe` with `stdlib.collection` imports removed.
- Ruby probe: temporary copy in `/tmp/decision_tree_ruby_probe` with `stdlib.collection` imports removed and `label` renamed to `class_label`.

## Wave P2 Recheck Summary (2026-06-12)

Rust: oof (4 diagnostics — all `call_contract: unknown callee 'append'`). Ruby: error (1 diagnostic — `ParseError: Expected name, got keyword(label)`). No new resolutions in Wave P2; DT-P02 (`label` keyword) still blocks all Ruby TC output. Rust remains blocked on call_contract("append",...) form. Parser keyword fix (LANG-PARSER-LABEL-IDENTIFIER-P1 CLOSED readiness proof) is the prerequisite before Ruby recheck is meaningful.

## LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 Recheck (2026-06-13)

Ruby: **ok/0** — all 4 stringly append sites migrated (3 BOOTSTRAP in example.ig, 1 ACCUMULATING in builder.ig); DT-P03 and DT-P09 both RESOLVED.  
Rust: **ok/0** — same.  
**decision_tree is DUAL-TOOLCHAIN CLEAN.**  
Remaining active pressures: DT-P04 (find-one), DT-P06 (managed traversal), DT-P07 (variant/ADT).

## Wave P6 Recheck Summary (2026-06-13)

Rust: oof / 4 diagnostics — unchanged (4× `call_contract: unknown callee 'append'`). Ruby: oof / 7 diagnostics — unchanged (4× `call_contract: unknown callee 'append'`, 3× `Unresolved symbol` cascade from DT-P09). LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 had zero effect: all remaining pressures are stringly call_contract("append",...) failures — NOT_RECORD_LITERAL classification confirmed. No new pressures. No regressions. Dominant route unchanged: `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`.

## Wave P5 Recheck Summary (2026-06-13)

Rust: oof / 4 diagnostics — unchanged from Wave P4. Ruby: oof / 7 diagnostics — unchanged from Wave P4. LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had zero effect: DT-P09 computes (`new_nodes`, `nodes_0`, `features_good`) are cascade from stringly `call_contract("append", ...)` failures (NOT_RECORD_LITERAL) — not annotated compute bindings. No new pressures.

## Wave P4 Recheck Summary (2026-06-13)

Rust: oof / 4 diagnostics — unchanged from Wave P3. Ruby: oof / 7 diagnostics — unchanged from Wave P3. LANG-TYPED-COMPUTE-BINDING-P2 had zero effect: `new_nodes`, `nodes_0`, `features_good` are cascade from stringly `call_contract("append", ...)` failures, not annotated compute bindings. DT-P09 route confirmed: stringly stdlib migration is the prerequisite. No new pressures.

## Wave P3 Recheck Summary (2026-06-13)

Rust: oof / 4 diagnostics — all `call_contract: unknown callee 'append' — not found in this module`. Ruby: oof / 7 diagnostics — 4× `call_contract: unknown callee 'append'`, `Unresolved symbol: new_nodes`, `Unresolved symbol: nodes_0`, `Unresolved symbol: features_good`. Resolutions since Wave P2: DT-P02 RESOLVED — LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 CLOSED; `label` now valid in binding positions; Ruby no longer crashes with ParseError; Ruby progresses to TC and surfaces 7 diags. Rust unchanged (4 diags, same as P2). Remaining blockers: stdlib-form append callee unresolved in both toolchains (DT-P03); 3 cascade unresolved symbols — typed compute binding gap (DT-P09).

## Notes

- Import surface (DT-P01) and equality (DT-P05) are resolved.
- DT-P02 (`label` keyword) is RESOLVED — LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 CLOSED; Ruby now reaches TC.
- `call_contract("append", ...)` still fails in both Rust and Ruby (DT-P03) — 4 sites across builder.ig + example.ig.
- `find_one` should not be smuggled in as scalar `filter`; it needs explicit fail-closed semantics.
- The app is a strong fixture for finite graph/arena traversal, but not evidence for unbounded loops.

## Wave P7 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. DT-P03 and DT-P09 remain RESOLVED. No pressure ID changes this wave. No new pressures. (Waves P3–P7 all no-change since LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 CLOSED.)

## Wave P8 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LANG-STRING-TEXT-ALIAS-P2, LANG-RUBY-RECORD-LITERAL-INFERENCE-P5, LANG-STDLIB-STRING-SUBSTRING-P2, and LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 had no effect on this app. No new pressures. No regressions.

## Wave P9 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4, LAB-VE-NEW-OBJ-INFERENCE-P1, LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1, LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2, and LAB-PARSER-RECORD-IN-HOF-P1 had no effect on this app. No new pressures. No regressions.

## Wave P10 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. No pressure ID changes this wave. No new pressures. No regressions.
