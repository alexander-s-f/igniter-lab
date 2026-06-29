# LANG-STDLIB-COLLECTION-FLATMAP-P4

Status: OPEN
Lane: lang / stdlib / collection / flat_map / rust-parity
Mode: bounded implementation
Skill: idd-agent-protocol

## Context

`LANG-STDLIB-COLLECTION-FLATMAP-P3` landed the canon Ruby `igc` surface:

```text
flat_map(Collection[A], A -> Collection[B]) -> Collection[B]
SIR: stdlib.collection.flat_map
diagnostics: OOF-COL1 / OOF-COL2 / OOF-COL9
```

This card brings the lab Rust compiler (`igniter-compiler`) to parity with the
Ruby implementation. The VM runtime is already ready: commit `d2ed524` wired
`stdlib.collection.flat_map` to the existing `flat_map` handler.

## Current Live Gap

Verify first, but current known shape is:

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` has a `"flat_map" |
  "and_then"` arm around the Result/Option path.
- That arm comments that `flat_map` keeps an **Integer placeholder** for the
  lambda parameter.
- It does not implement the collection contract:

  ```text
  flat_map(Collection[A], A -> Collection[B]) -> Collection[B]
  ```

- `lang/igniter-compiler/src/emitter.rs` currently qualifies collection HOFs
  such as `map/filter/filter_map/count/...`, but not bare `flat_map`.

Do not rely on this placeholder. Replace or split it.

## Goal

Implement Rust `igniter-compiler` parity for collection `flat_map`:

- source alias `flat_map` is accepted;
- SIR emits `stdlib.collection.flat_map`;
- lambda param is bound to the input collection element type `A`;
- lambda body must be `Collection[B]` or `Unknown`;
- result type is `Collection[B]` (one-level unwrap, not double-wrapped);
- scalar/non-collection lambda body emits `OOF-COL9`;
- existing Result/Option `and_then` behavior is unchanged.

## Scope

Allowed:

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-compiler/src/emitter.rs`
- focused tests under `lang/igniter-compiler/tests`
- this card closing report
- optional proof packet if useful

Closed:

- no Ruby `igniter-lang` changes (P3 already landed);
- no VM changes;
- no stdlib inventory digest in this card unless current Rust parity precedent
  requires it (expected: no);
- no `flatten`;
- no collection comprehension syntax;
- no Result `and_then` policy change;
- no unrelated collection algebra promotion.

## Implementation Notes

Expected shape:

1. Split collection `flat_map` from monadic `and_then`.
   - `and_then` stays Option/Result-oriented.
   - `flat_map` is collection-only.

2. First argument:

   ```text
   Collection[A] or Unknown accepted.
   non-Collection concrete -> OOF-COL2
   ```

3. Second argument:

   ```text
   must be lambda -> OOF-COL1 if missing/non-lambda
   lambda param type = A (or Unknown)
   ```

4. Lambda body:

   ```text
   Collection[B] -> output Collection[B]
   Unknown       -> output Collection[Unknown]
   other scalar  -> OOF-COL9 + recover Collection[Unknown]
   ```

5. Emitter:

   Add:

   ```rust
   ("flat_map", "stdlib.collection.flat_map")
   ```

   to the collection HOF qualification table so bare source `flat_map` never
   appears in SIR.

## Tests / Proof Matrix

Add focused Rust compiler tests covering:

1. **happy path**
   - `flat_map(xs, x -> [x, x])` compiles clean;
   - SIR fn is `stdlib.collection.flat_map`;
   - resolved output is `Collection[Integer]`, not nested.

2. **record/descriptor pressure**
   - `flat_map(bodies, b -> [b.a, b.b])` compiles clean;
   - proves lambda param is the record element type, not the old Integer
     placeholder.

3. **OOF-COL9**
   - `flat_map(xs, x -> x)` emits `OOF-COL9`;
   - message names `stdlib.collection.flat_map`.

4. **OOF-COL1 / OOF-COL2**
   - wrong arity;
   - second arg non-lambda;
   - first arg non-collection.

5. **Unknown permissive**
   - empty list or Unknown-bearing body does not falsely emit `OOF-COL9`.

6. **regression**
   - `map/filter/count` still qualify and typecheck;
   - `filter_map` still qualifies;
   - Result/Option `and_then` remains unchanged.

If practical, compare key snippets with the Ruby P3 proof output or source
expectations. Exact byte parity is ideal, but do not over-build a large runner if
small Rust tests make the contract unambiguous.

## Acceptance

- [ ] `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]` works in
      Rust `igniter-compiler`.
- [ ] Bare `flat_map` emits `stdlib.collection.flat_map`.
- [ ] Lambda param uses collection element type, not Integer placeholder.
- [ ] One-level unwrap result proven; no double-wrap.
- [ ] `OOF-COL9` emitted for scalar/non-collection lambda body.
- [ ] `OOF-COL1` and `OOF-COL2` covered.
- [ ] Unknown policy matches Ruby P3.
- [ ] `and_then` Result/Option behavior unchanged.
- [ ] No VM/Ruby/inventory/comprehension changes.
- [ ] `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test <new_test_target>` green.
- [ ] Relevant regression tests green.
- [ ] `git diff --check` clean.
- [ ] Closing report names the next route: inventory entry/digest recompute or
      broader algebra parity, depending on what live evidence shows.

## Suggested Verification

Run from `/Users/alex/dev/projects/igniter-workspace/igniter-lab`:

```sh
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test <new_flat_map_test_target>
cargo test --manifest-path lang/igniter-compiler/Cargo.toml collection_comprehension_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml collection_nested_ops_diagnostic_tests
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test nested_hof_eval_execution_tests
git diff --check
```

Use `--test <target>` for integration targets. Avoid trailing filters that run
zero tests.

## Non-goals

- No `flatten`.
- No `zip/take/find/any/all` promotion.
- No collection-flow syntax.
- No performance optimization.
- No inventory digest unless explicitly required by the local parity precedent.
