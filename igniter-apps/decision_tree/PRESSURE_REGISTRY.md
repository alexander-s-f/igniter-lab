# Decision Tree Pressure Registry

Updated: 2026-06-12 (APP-RECHECK-WAVE-P1)

This registry tracks app pressure from `igniter-apps/decision_tree`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| DT-P01 | RESOLVED | `stdlib.collection` import surface | Wave recheck: Rust shows 4 diags (all `call_contract: unknown callee 'append'`), no OOF-IMP2; `stdlib.collection` recognized in inventory | `LANG-STDLIB-COLLECTION-APPEND-PROP-P3` inventory |
| DT-P02 | ACTIVE | Ruby parser keyword hygiene | Wave recheck: Ruby still stops at `ParseError: Expected name, got keyword(label)`; blocks all Ruby TC output | parser keyword / reserved-name diagnostic card |
| DT-P03 | ACTIVE | `append` via call_contract (Rust) | Wave recheck: Rust shows 4 `call_contract: unknown callee 'append'` diags; builder.ig + example.ig use `call_contract("append", tree.nodes, node)`; stdlib dispatch doesn't cover stringly form | call_contract parity follow-up |
| DT-P04 | ACTIVE | Single-element collection extraction | `FindNodeById` and `LookupFeature` can only return `Collection[T]`; no `head`/`first`/`find_one` | `LAB-STDLIB-FIND-ONE-P1` |
| DT-P05 | RESOLVED | Text equality | Wave recheck (Rust): 0 equality errors; `==` works via Rust TC; Ruby blocked by DT-P02 but LANG-STDLIB-TEXT-EQUALITY-P3 implements `==` in Ruby `operator_type` | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| DT-P06 | WATCH | Managed traversal | `Evaluate` is fixed-depth unrolled because tree traversal cannot recurse/loop safely | managed recursion / bounded traversal follow-up |
| DT-P07 | ACTIVE | Variant/ADT surface | `TreeNode` uses `kind` plus sentinel fields for leaf vs decision nodes | variant/ADT surface follow-up |
| DT-P08 | WATCH | Contract invocation return shape | Single-output `call_contract` collapses to scalar, not wrapper record | typed refs / invocation forms docs |

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

## Notes

- Import surface (DT-P01) and equality (DT-P05) are resolved.
- DT-P02 (`label` keyword) blocks all Ruby TC output for this app — must be fixed before Ruby recheck is meaningful.
- `call_contract("append", ...)` still fails in Rust (DT-P03) — 4 sites across builder.ig + example.ig.
- `find_one` should not be smuggled in as scalar `filter`; it needs explicit fail-closed semantics.
- The app is a strong fixture for finite graph/arena traversal, but not evidence for unbounded loops.
