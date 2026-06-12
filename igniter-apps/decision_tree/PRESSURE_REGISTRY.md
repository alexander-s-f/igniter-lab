# Decision Tree Pressure Registry

Updated: 2026-06-12

This registry tracks app pressure from `igniter-apps/decision_tree`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| DT-P01 | ACTIVE | `stdlib.collection` import surface | Rust stops at `OOF-IMP2 unknown import path 'stdlib.collection'` in three modules | `LANG-STDLIB-IMPORT-SURFACE-P2/P3` |
| DT-P02 | ACTIVE | Ruby parser keyword hygiene | Ruby stops at `ParseError: Expected name, got keyword(label)` | parser keyword / reserved-name diagnostic card |
| DT-P03 | ACTIVE | `append` collection helper | Rust probe without stdlib imports reaches four `call_contract: unknown callee 'append'` diagnostics | `LANG-STDLIB-COLLECTION-APPEND-P1` |
| DT-P04 | ACTIVE | Single-element collection extraction | `FindNodeById` and `LookupFeature` can only return `Collection[T]`; no `head`/`first`/`find_one` | `LAB-STDLIB-FIND-ONE-P1` |
| DT-P05 | ACTIVE | Text equality | Ruby probe reaches `Unsupported operator: ==` for IDs, feature names, and node kind tags | `LANG-STDLIB-TEXT-EQUALITY-P1` |
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

- This app should stay pressure-only until import surface, append, and single-element extraction are clearer.
- `find_one` should not be smuggled in as scalar `filter`; it needs explicit fail-closed semantics.
- The app is a strong fixture for finite graph/arena traversal, but not evidence for unbounded loops.
