# Decision Tree Pressure Registry

Updated: 2026-06-13 (APP-RECHECK-WAVE-P3)

This registry tracks app pressure from `igniter-apps/decision_tree`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| DT-P01 | RESOLVED | `stdlib.collection` import surface | Wave recheck: Rust shows 4 diags (all `call_contract: unknown callee 'append'`), no OOF-IMP2; `stdlib.collection` recognized in inventory | `LANG-STDLIB-COLLECTION-APPEND-PROP-P3` inventory |
| DT-P02 | RESOLVED | Ruby parser keyword hygiene | Wave P2: Ruby stopped at `ParseError: Expected name, got keyword(label)`. Wave P3: LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 CLOSED — `name_token!` now accepts `%i[ident keyword]` in all binding positions; `label` is valid as a binding name; Ruby progresses to TC | `LANG-PARSER-CONTEXTUAL-KEYWORDS-P2` CLOSED |
| DT-P03 | ACTIVE | `append` via call_contract | Wave P3: Rust 4 diags (4× `call_contract: unknown callee 'append'`); Ruby 7 diags (4× `call_contract: unknown callee 'append'` + 3× `Unresolved symbol` cascade); stdlib-form call_contract('append',...) still not dispatched in either toolchain | stringly stdlib migration + call_contract parity |
| DT-P04 | ACTIVE | Single-element collection extraction | `FindNodeById` and `LookupFeature` can only return `Collection[T]`; no `head`/`first`/`find_one` | `LAB-STDLIB-FIND-ONE-P1` |
| DT-P05 | RESOLVED | Text equality | Wave recheck (Rust): 0 equality errors; `==` works via Rust TC; Ruby blocked by DT-P02 but LANG-STDLIB-TEXT-EQUALITY-P3 implements `==` in Ruby `operator_type` | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| DT-P06 | WATCH | Managed traversal | `Evaluate` is fixed-depth unrolled because tree traversal cannot recurse/loop safely | managed recursion / bounded traversal follow-up |
| DT-P07 | ACTIVE | Variant/ADT surface | `TreeNode` uses `kind` plus sentinel fields for leaf vs decision nodes | variant/ADT surface follow-up |
| DT-P08 | WATCH | Contract invocation return shape | Single-output `call_contract` collapses to scalar, not wrapper record | typed refs / invocation forms docs |
| DT-P09 | ACTIVE | Typed compute binding gap (stringly call_contract) | Wave P3: 3 cascade `Unresolved symbol` diags from Ruby TC — `new_nodes`, `nodes_0`, `features_good`. Wave P4: unchanged — LANG-TYPED-COMPUTE-BINDING-P2 had no effect. Root cause confirmed: cascade from stringly `call_contract("append", ...)` failures; output variables not bound into symbol_types when callee is unresolved; clears when stringly stdlib migration resolves append | stringly stdlib migration (`LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`) |

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
