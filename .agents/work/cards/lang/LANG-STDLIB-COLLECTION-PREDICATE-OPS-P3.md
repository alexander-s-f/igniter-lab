# LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3

Status: CLOSED (2026-06-29) — Rust parity normalized; predicate ops proof green; next = P4 inventory + digest
Lane: lang / stdlib / collection / predicate-ops / rust-parity
Mode: bounded implementation
Skill: idd-agent-protocol

## Goal

Bring lab Rust `igniter-compiler` parity in line with canon Ruby P2 for collection predicate ops:

```text
find(Collection[T], T -> Bool) -> Option[T]
any(Collection[T], T -> Bool)  -> Bool
all(Collection[T], T -> Bool)  -> Bool
```

This is **normalization**, not greenfield. Lab Rust already has rough `find`/`any`/`all` arms and VM
handlers, but live verification shows gaps:

- diagnostics are currently coarse (`OOF-TM1` for arity);
- first-arg Collection and predicate Bool checks are incomplete;
- emitter qualification does not list `find`/`any`/`all` in the collection HOF gates.

## Context

Upstream chain:

1. `LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1` chose predicate ops first.
2. `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2` implemented canon Ruby:
   - registry entries for `find`, `any`, `all`;
   - qualified SIR names `stdlib.collection.find/any/all`;
   - `OOF-COL1`, `OOF-COL2`, `OOF-COL3`;
   - proof runner `33/33`.

This card mirrors P2 in lab Rust.

## Authority

Work in:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab
```

Read first:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lang-stdlib-collection-algebra-parity-prop-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/emitter.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-vm/src/vm.rs`
- nearby tests:
  - `collection_flat_map_tests.rs`
  - `collection_comprehension_tests.rs`
  - `collection_nested_ops_diagnostic_tests.rs`

Also inspect canon Ruby P2 in:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb
```

## Verify-First

Before editing, confirm live gaps:

- `stdlib_calls.rs` has `find` and `any|all` arms, but uses `OOF-TM1` for arity and does not fully
  mirror filter-style COL diagnostics.
- `emitter.rs` `COLLECTION_HOF_OPS` does **not** include `find`/`any`/`all`.
- `semantic_expr_for_compute` collection delegation `matches!` does **not** include `find`/`any`/`all`.
- VM already maps qualified `stdlib.collection.find/any/all` to bare handlers; do not change VM unless
  live verification proves a regression.

## Scope

Allowed:

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-compiler/src/emitter.rs`
- new focused tests under `lang/igniter-compiler/tests/`
- this card closing report

Closed:

- no Ruby/canon changes (P2 already did that);
- no VM/runtime changes unless the existing qualified mapping is broken;
- no `stdlib-inventory.json` changes (P4);
- no `take/drop`;
- no `zip`/`Pair`;
- no parser/syntax changes;
- no DB/query authority.

## Implementation Notes

### Typechecker

Implement or refactor the Rust arms to match canon Ruby P2 behavior:

```text
find(Collection[T], T -> Bool) -> Option[T]
any(Collection[T], T -> Bool)  -> Bool
all(Collection[T], T -> Bool)  -> Bool
```

Diagnostics:

- `OOF-COL1`: wrong arity or non-lambda second arg;
- `OOF-COL2`: first arg concrete non-Collection;
- `OOF-COL3`: lambda body concrete non-Bool.

Unknown policy:

- `Collection[Unknown]` and first-arg `Unknown` are permissive;
- lambda body `Unknown` is permissive;
- `find` recovers to `Option[Unknown]` if element type unknown;
- `any`/`all` recover to `Bool`.

Use the existing filter lambda-inference pattern where possible. Do not introduce a new HOF subsystem.

### Emitter

Add all three to both collection HOF gates:

```text
("find", "stdlib.collection.find")
("any",  "stdlib.collection.any")
("all",  "stdlib.collection.all")
```

and the compute-level `matches!(fn_val, ...)` delegation list. P4 proved the second list is
load-bearing: if a bare call stays in `semantic_expr_for_compute`, it may never reach the qualification
block.

## Test Requirements

Add a focused test target, likely:

```text
lang/igniter-compiler/tests/collection_predicate_ops_tests.rs
```

Minimum tests:

1. happy path:
   - `find(xs, x -> x > 0)` compiles clean, emits `stdlib.collection.find`, output `Option[Integer]`;
   - `any(xs, x -> x > 0)` compiles clean, emits `stdlib.collection.any`, output `Bool`;
   - `all(xs, x -> x > 0)` compiles clean, emits `stdlib.collection.all`, output `Bool`;
   - no bare names in SIR.
2. output mismatch:
   - `find` output as `Collection[Integer]` fails;
   - `find` output as bare `Integer` fails.
3. record predicate:
   - `find(Collection[Todo], t -> t.done)` compiles clean; proves param element type.
4. diagnostics:
   - wrong arity -> `OOF-COL1`;
   - non-lambda second arg -> `OOF-COL1`;
   - non-Collection first arg -> `OOF-COL2`;
   - predicate returns non-Bool -> `OOF-COL3`.
5. Unknown permissive:
   - unknown predicate body does not emit `OOF-COL3`;
   - `find` over unknown-ish element recovers without false rejection where possible.
6. regressions:
   - `filter` still emits `OOF-COL3`;
   - `flat_map` still requires Collection body (`OOF-COL9`);
   - `map` remains qualified;
   - no `zip`/Pair changes.

## Acceptance

- [x] Rust typechecker returns `Option[T]` for `find`.
- [x] Rust typechecker returns `Bool` for `any` and `all`.
- [x] Bare calls emit qualified `stdlib.collection.find/any/all`.
- [x] `OOF-COL1`, `OOF-COL2`, `OOF-COL3` covered.
- [x] Unknown predicate policy matches canon P2.
- [x] Record predicate proves lambda param = element type.
- [x] Existing `filter`, `flat_map`, `map` behavior is not regressed.
- [x] No VM/Ruby/inventory/parser changes.
- [x] New focused test target green.
- [x] Relevant regressions green:
  - `collection_flat_map_tests`
  - `collection_comprehension_tests`
  - `collection_nested_ops_diagnostic_tests`
  - VM nested HOF tests if touched or if qualifying paths could affect runtime
- [x] `git diff --check` clean.
- [x] Closing report names next card: expected `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4`
      (inventory + digest), unless live evidence changes the route.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_predicate_ops_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_flat_map_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_comprehension_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_nested_ops_diagnostic_tests
git diff --check
```

If VM is not changed, do not overclaim VM proof beyond existing mapped qualified handler. If you run it:

```bash
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test nested_hof_eval_execution_tests
```

## Non-goals

- No `take/drop`.
- No `zip`/Pair.
- No inventory digest.
- No new syntax.
- No runtime optimization.

## Closing Report Requirements

Report:

- exact files changed;
- test counts;
- whether VM was touched;
- whether existing coarse `OOF-TM1` paths were replaced for these ops;
- next card.

## Closing Report

Closed on 2026-06-29.

Changed files:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/emitter.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/tests/collection_predicate_ops_tests.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3.md`

Implemented lab Rust parity normalization for:

- `find(Collection[T], T -> Bool) -> Option[T]`
- `any(Collection[T], T -> Bool) -> Bool`
- `all(Collection[T], T -> Bool) -> Bool`

Typechecker changes:

- Replaced the old coarse `OOF-TM1` arity path for `find`/`any`/`all` with `OOF-COL1`.
- Added `OOF-COL2` for concrete non-Collection first args.
- Added `OOF-COL3` for concrete non-Bool predicate bodies.
- Preserved Unknown permissiveness for `Collection[Unknown]`, first-arg `Unknown`, and predicate-body `Unknown`.
- Added `find`/`any`/`all` to the HOF lambda nested-op scan gate.

Emitter changes:

- Added bare-name qualification for:
  - `find` -> `stdlib.collection.find`
  - `any` -> `stdlib.collection.any`
  - `all` -> `stdlib.collection.all`
- Added all three to the compute-level collection delegation list.

Verification:

- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_predicate_ops_tests`
  - `6 passed; 0 failed`
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_flat_map_tests`
  - `7 passed; 0 failed`
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_comprehension_tests`
  - `10 passed; 0 failed`
- `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_nested_ops_diagnostic_tests`
  - `8 passed; 0 failed`
- `cargo test --manifest-path lang/igniter-vm/Cargo.toml --test nested_hof_eval_execution_tests`
  - `5 passed; 0 failed`
- `git diff --check`
  - clean

Boundary:

- VM was not edited; only the existing qualified mapping was verified.
- No Ruby/canon edits.
- No parser/syntax edits.
- No inventory/digest edits.
- No `take/drop`, `zip`/`Pair`, query, or database authority changes.

Next card:

- `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4` (inventory + digest).
