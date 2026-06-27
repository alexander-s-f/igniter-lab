# LAB-VM-MAP-LAMBDA-CALLCONTRACT-PARITY-P1 v0

Date: 2026-06-27
Scope: lab runtime/compiler parity proof. Lab evidence, not canon authority by itself.

## Summary

The dynamic frame-view specimen now compiles and executes through `igniter-vm run`.

Blocked shape:

```ig
map(lead_labels, label -> call_contract("Leaf", a_row, label))
```

Old runtime failure reproduced before the fix:

```json
{"error":"VM evaluation failed: map expects exactly 2 arguments, got 1","status":"error"}
```

Root cause was compiler lowering in the canonical Ruby `igniter-lang` compiler path, not a missing VM
`map` arm. The Ruby typechecker inferred the lambda body and used it for the output type/deps, but emitted
the typed call as `args: [collection_arg]`, dropping the lambda argument before SemanticIR assembly. The VM
then correctly received a one-argument `stdlib.collection.map` call and rejected it.

## Fix

Changed:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
  - `infer_collection_hof_call` now preserves a typed lambda in `map`/`filter` call args.
  - `infer_filter_map_call` now preserves a typed lambda in `filter_map` call args.
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/typechecker.rs`
  - Rust mirror `rewrite_concat_calls` now recurses through lambda bodies instead of treating lambdas as
    leaves.
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-vm/tests/map_lambda_callcontract_parity_tests.rs`
  - Added focused VM regression for `map(..., item -> call_contract(..., captured_value, item))`.

No parser, `.igv`, `.ig.html`, invocation-form syntax, cross-module refs, or frame-ui bridge files were
changed.

## Artifact Shape

Compile command:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rm -rf /tmp/frame-list-dynamic.igapp
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig \
  --out /tmp/frame-list-dynamic.igapp
```

Result: `status: ok`, source hash
`sha256:9d1698af8e911d651642b0e54ef10ec8795307a46d71e5107538a80a74e2e160`.

SIR inspection:

```bash
jq '.contracts[] | select(.contract_name=="ListView") | .nodes[] |
    select(.name=="item_rows") | {deps, expr}' \
  /tmp/frame-list-dynamic.igapp/semantic_ir_program.json
```

Key fixed shape:

```json
{
  "fn": "stdlib.collection.map",
  "kind": "call",
  "args": [
    { "kind": "ref", "name": "lead_labels" },
    {
      "kind": "lambda",
      "params": ["label"],
      "body": {
        "kind": "call",
        "fn": "call_contract",
        "args": [
          { "kind": "literal", "value": "Leaf" },
          { "kind": "ref", "name": "a_row" },
          { "kind": "ref", "name": "label" }
        ]
      }
    }
  ]
}
```

## Runtime Proof

Input:

```json
{
  "lead_labels": ["Review Ada's lead", "Call Grace back", "Send Linus the quote"],
  "sel_title": "Review Ada's lead"
}
```

Command:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo run --manifest-path lang/igniter-vm/Cargo.toml -- run \
  --contract /tmp/frame-list-dynamic.igapp \
  --entry ListView \
  --inputs /tmp/frame-list-dynamic-input.json \
  --json
```

Result: `status: success`.

Runtime output includes the expected authored labels and actions:

- `Review Ada's lead`
- `Call Grace back`
- `Send Linus the quote`
- `+ add item`
- `mark done`

The returned root is an `Element` record with `tag: "row"`, two child columns, dynamic sidebar rows from
the `map`, and the detail column.

## Focused Regression

Added tracked VM test:

```bash
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test map_lambda_callcontract_parity_tests
```

Result:

```text
test map_lambda_can_call_local_contract_with_capture_and_item ... ok
```

Pre-fail coverage: the old failure was captured with the card specimen before the fix. The tracked
regression was added after root-cause isolation, so its exact before-fix failure was not kept as a separate
test transcript; the pre-fix specimen failure is the preserved negative evidence for this card.

Note: the test uses lambda param `item` because the lab Rust compiler path treats `label` as a reserved-ish
surface token in this context and reports `Unexpected token in expression: Arrow`. The card's canonical Ruby
`igc` specimen still uses `label` and now compiles/runs successfully. That parser difference is out of scope
for this parity card.

## Other Verification

```bash
ruby -c /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb
```

Result: `Syntax OK`.

```bash
cargo test --manifest-path lang/igniter-vm/Cargo.toml \
  --test nested_hof_eval_execution_tests \
  --test record_construction_in_lambda_tests \
  --test variant_construct_in_lambda_tests
```

Result: all listed tests passed.

```bash
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
```

Result: full lab Rust compiler suite passed.

```bash
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_comprehension_tests
```

Result: `10 passed`.

```bash
git -C /Users/alex/dev/projects/igniter-workspace/igniter-lab diff --check
git -C /Users/alex/dev/projects/igniter-workspace/igniter-lang diff --check
```

Result: clean.

`cargo fmt --manifest-path lang/igniter-compiler/Cargo.toml --check` remains non-clean because of existing
format drift outside this card's patch area, including `linalg_mat3_tests.rs`, `package_lockfile_cli_tests.rs`,
`stdlib_float_to_text_tests.rs`, and one pre-existing `Pair.first/second` line in
`lang/igniter-compiler/src/typechecker.rs`. Those unrelated lines were not reformatted in this pass.

`cargo fmt --manifest-path lang/igniter-vm/Cargo.toml --check` also reports existing unrelated format drift
in `src/vm.rs` and several older VM tests. The new `map_lambda_callcontract_parity_tests.rs` was adjusted to
the formatter's suggested shape and its focused test passes.

## Frame-UI

Frame-ui was not touched. P3's static bridge proof remains separate. This card closes the dynamic runtime
specimen; a future bridge card can choose whether to add a generated dynamic fixture to
`frame-ui/igniter-frame`.

## Remaining HOF Gaps

No remaining gap was found for this shape after the fix:

```text
Collection data -> map(lambda) -> call_contract(...) -> typed record tree
```

The unrelated Rust-lab parser observation around the parameter name `label` is explicitly not closed here.
