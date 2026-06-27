# LAB-VM-MAP-LAMBDA-CALLCONTRACT-PARITY-P1

Status: DONE
Route: standard / igniter-lab / lang / igniter-vm / parity / frame-view-pressure
Skill: idd-agent-protocol

## Goal

Close the VM parity gap exposed by the frame-view runtime extraction proof:

```ig
map(lead_labels, label -> call_contract("Leaf", a_row, label))
```

`list_view_dynamic.ig` compiles successfully, but runtime extraction currently fails with:

```json
{"error":"VM evaluation failed: map expects exactly 2 arguments, got 1","status":"error"}
```

This card is a VM/compiler-runtime parity proof, not a view-language syntax card.

## Why This Matters

P3 removed the frame-ui mirror using the static sibling fixture, but the realistic dynamic view remains
blocked. The blocked shape is important beyond frame-ui:

```text
Collection data -> map(lambda) -> call_contract(...) -> typed record tree
```

That is the natural Igniter authoring pattern for data-bound views, report rows, and small projections.
The compiler accepting it while the VM rejects it is exactly the kind of "is it supported or not?"
ambiguity we want to eliminate.

## Current Authority

Live source wins over this card if it has moved.

Primary inputs:

- `lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig`
- `lab-docs/lang/lab-frame-view-igc-run-element-extraction-p3-v0.md`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/src/compiler.rs`
- `lang/igniter-vm/tests/nested_hof_eval_execution_tests.rs`
- `lang/igniter-vm/tests/record_construction_in_lambda_tests.rs`
- `lang/igniter-vm/tests/variant_construct_in_lambda_tests.rs`
- `frame-ui/igniter-frame/tests/ig_runtime_bridge_tests.rs`

Known live facts at card creation:

- `list_view_dynamic.ig` compiles.
- `list_view_inline.ig` runs and feeds frame-ui through real `igniter-vm run` output.
- The dynamic specimen fails at VM runtime with `map expects exactly 2 arguments, got 1`.
- `lang/igniter-vm/src/vm.rs` already has `map` handling in eval surfaces, so do not assume the fix is
  simply "add a missing map arm".
- Nested HOF and record-construction tests exist; this card must identify the remaining shape delta:
  `map` lambda body calling a local contract and returning a record.

## Questions To Answer

1. What exact SIR / runtime JSON shape does the compiler emit for:
   `map(lead_labels, label -> call_contract("Leaf", a_row, label))`?
2. Is the arity failure caused by compiler lowering, VM HOF argument evaluation, lambda encoding, qualified
   stdlib call routing, or `call_contract` inside the lambda body?
3. Does a minimal isolated fixture reproduce the failure without frame-ui-specific records?
4. After the fix, does `list_view_dynamic.ig` run through `igniter-vm run` and produce an `Element` tree?
5. Can the runtime-produced dynamic `Element` tree render through `frame-ui/igniter-frame::ig_bridge`?
6. Are existing nested HOF / record-in-lambda / variant-in-lambda tests still green?

## Implementation Guidance

Start with reproduction and inspection. Do not patch by guess.

1. Compile the dynamic specimen:

   ```bash
   cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
   rm -rf /tmp/frame-list-dynamic.igapp
   ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
     /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
     lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig \
     --out /tmp/frame-list-dynamic.igapp
   ```

2. Create input:

   ```bash
   cat > /tmp/frame-list-dynamic-input.json <<'JSON'
   {
     "lead_labels": ["Review Ada's lead", "Call Grace back", "Send Linus the quote"],
     "sel_title": "Review Ada's lead"
   }
   JSON
   ```

3. Reproduce the runtime failure:

   ```bash
   cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
   cargo run -p igniter-vm -- run \
     --contract /tmp/frame-list-dynamic.igapp \
     --entry ListView \
     --inputs /tmp/frame-list-dynamic-input.json \
     --json
   ```

   If the package name or CLI flags have drifted, use live `lang/igniter-vm/src/main.rs` and document the
   corrected command.

4. Inspect the compiled artifact before editing:

   ```bash
   find /tmp/frame-list-dynamic.igapp -maxdepth 3 -type f | sort
   rg -n "map|call_contract|Leaf|lead_labels|lambda|stdlib.collection" /tmp/frame-list-dynamic.igapp
   ```

5. Add a focused VM test for the minimal blocked shape. Prefer a small `.ig` source compiled through the
   real VM compiler path. The test should include:

   ```ig
   contract Leaf {
     input prefix : String
     input label : String
     compute out = { text: prefix + label }
     output out : Row
   }

   contract Main {
     input labels : Collection[String]
     compute rows = map(labels, label -> call_contract("Leaf", "row:", label))
     output rows : Collection[Row]
   }
   ```

   Adjust syntax to live language constraints. The important shape is:

   ```text
   map(Collection[T], lambda -> call_contract(local_static_contract, captured_value, lambda_param))
   ```

6. Fix the smallest owner surface:
   - If compiler output is wrong, fix/compiler-test that lowering.
   - If compiler output is sound, fix VM evaluation so the shape executes.
   - Keep the change narrow. Do not broaden HOF semantics unless the local implementation naturally shares
     one dispatch path.

7. Re-run the dynamic frame-view specimen and capture the successful runtime envelope.
   - It is acceptable to add a generated runtime fixture only if it is produced by the fixed runtime and the
     proof packet gives the exact command.
   - If added to frame-ui tests, keep it separate from P3's static fixture so the proof remains auditable.

## Acceptance

- [x] The old `map expects exactly 2 arguments, got 1` failure is reproduced and quoted in the proof packet.
- [x] The compiled artifact/SIR shape is inspected and the root cause is assigned to compiler lowering or VM
      evaluation with evidence.
- [x] A focused regression test covers `map(..., lambda -> call_contract(...))`.
- [x] The focused test fails before the fix and passes after the fix, or the packet explains why pre-fail
      capture was not practical.
- [x] `list_view_dynamic.ig` executes successfully via `igniter-vm run --entry ListView`.
- [x] Runtime output includes the authored labels:
      `Review Ada's lead`, `Call Grace back`, `Send Linus the quote`, `+ add item`, `mark done`.
- [x] If frame-ui is touched, dynamic runtime output renders through `render_ig_view` without reintroducing a
      hand-written mirror.
- [x] Existing nested HOF / record-in-lambda / variant-in-lambda tests remain green.
- [x] No parser, `.igv`, `.ig.html`, invocation-form syntax, cross-module refs, or canon surface changes.
- [x] `git diff --check` is clean.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test -p igniter-vm nested_hof_eval_execution_tests
cargo test -p igniter-vm record_construction_in_lambda_tests
cargo test -p igniter-vm variant_construct_in_lambda_tests
cargo test -p igniter-vm <new_focused_test_name>

rm -rf /tmp/frame-list-dynamic.igapp
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig \
  --out /tmp/frame-list-dynamic.igapp

cargo run -p igniter-vm -- run \
  --contract /tmp/frame-list-dynamic.igapp \
  --entry ListView \
  --inputs /tmp/frame-list-dynamic-input.json \
  --json

# Only if a frame-ui bridge fixture/test is added:
cargo test -p igniter_frame --test ig_runtime_bridge_tests

git diff --check
```

## Boundary

Allowed:

- Narrow VM/compiler-runtime parity fix.
- Focused VM test(s).
- Optional generated dynamic runtime fixture, if command-produced and documented.
- Optional frame-ui bridge test using runtime-produced dynamic output.
- Proof packet and closing report.

Closed:

- Do not implement `igc run` passport flow.
- Do not change view authoring syntax.
- Do not add `.igv` / `.ig.html`.
- Do not implement invocation-form sugar or cross-module contract refs.
- Do not replace the dynamic specimen with a static hand-unrolled workaround.
- Do not edit unrelated dirty files.
- Do not stage `frame-ui/igniter-frame/Cargo.lock` unless live investigation proves it belongs to this
  card and the proof packet says why.

## Required Packet

Create:

`lab-docs/lang/lab-vm-map-lambda-callcontract-parity-p1-v0.md`

Include:

- reproduction command + exact failure;
- compiled artifact/SIR inspection summary;
- root cause;
- fix summary;
- focused test name(s);
- dynamic specimen runtime command + result;
- output shape and label evidence;
- whether frame-ui bridge was updated;
- remaining HOF gaps, if any;
- commands run and skipped commands with reasons.

## Closing Report

Closed in `lab-docs/lang/lab-vm-map-lambda-callcontract-parity-p1-v0.md`.

Root cause: canonical Ruby `igniter-lang` typechecker dropped the lambda argument from typed
`map`/`filter`/`filter_map` calls after using it for type inference. The VM correctly rejected the resulting
one-arg `stdlib.collection.map`.

Changes:

- `igniter-lang/lib/igniter_lang/typechecker.rb`: preserve typed lambda args for `map`/`filter` and
  `filter_map`.
- `lang/igniter-compiler/src/typechecker.rs`: Rust mirror concat rewrite now recurses through lambda bodies.
- `lang/igniter-vm/tests/map_lambda_callcontract_parity_tests.rs`: focused runtime regression for
  `map(..., item -> call_contract(...))`.

Verified:

- Ruby `igc` compile of `list_view_dynamic.ig`: `status: ok`, source hash
  `sha256:9d1698af8e911d651642b0e54ef10ec8795307a46d71e5107538a80a74e2e160`.
- SIR `item_rows` now has `stdlib.collection.map` with two args: collection ref + `lambda` whose body is
  `call_contract("Leaf", a_row, label)`.
- `cargo run --manifest-path lang/igniter-vm/Cargo.toml -- run --contract /tmp/frame-list-dynamic.igapp
  --entry ListView --inputs /tmp/frame-list-dynamic-input.json --json`: `status: success`; output contains
  all expected labels/actions.
- `cargo test --manifest-path lang/igniter-vm/Cargo.toml --test map_lambda_callcontract_parity_tests`: pass.
- `cargo test --manifest-path lang/igniter-vm/Cargo.toml --test nested_hof_eval_execution_tests --test
  record_construction_in_lambda_tests --test variant_construct_in_lambda_tests`: pass.
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml`: pass.
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_comprehension_tests`: pass.
- `ruby -c /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`:
  `Syntax OK`.
- `git diff --check` in `igniter-lab` and `igniter-lang`: clean.

Notes:

- Frame-ui was not touched; P3 static bridge proof remains separate.
- `cargo fmt --manifest-path lang/igniter-compiler/Cargo.toml --check` still reports unrelated existing
  formatting drift outside this patch area, documented in the proof packet.

To be filled by the implementing agent.
