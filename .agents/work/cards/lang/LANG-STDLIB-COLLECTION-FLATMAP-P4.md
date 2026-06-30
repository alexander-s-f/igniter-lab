# LANG-STDLIB-COLLECTION-FLATMAP-P4

Status: CLOSED (2026-06-29) — lab Rust parity landed; tests 7/7; next = inventory entry/digest
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

- [x] `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]` works in Rust (identity-flatten
      `Collection[Collection[Integer]] -> Collection[Integer]` compiles clean).
- [x] Bare `flat_map` emits `stdlib.collection.flat_map` (SIR; never bare).
- [x] Lambda param = collection element type, not Integer placeholder (`bd -> bd.items` on `Body`).
- [x] One-level unwrap proven; no double-wrap (`Collection[Collection[Integer]]` output mismatches).
- [x] `OOF-COL9` for scalar/non-collection body.
- [x] `OOF-COL1` (arity/non-lambda) + `OOF-COL2` (non-collection first arg) covered.
- [x] Unknown policy matches Ruby P3 (array-literal/empty-list body → no false OOF-COL9).
- [x] `and_then` Result/Option unchanged (split into its own arm; no COL diagnostics on Result).
- [x] No VM/Ruby/inventory/comprehension changes (only `stdlib_calls.rs` + `emitter.rs` + new test).
- [x] `cargo test --test collection_flat_map_tests` green (7/7).
- [x] Regressions green: comprehension 10/10, nested-ops 8/8, VM nested_hof 5/5, full compiler suite
      0 failures, machine fleet sweep 13/13.
- [x] `git diff --check` clean.
- [x] Closing report + next route below.

## Report (2026-06-29)

Lab Rust parity for collection `flat_map`. Three edits:

1. `typechecker/stdlib_calls.rs` — **split** the shared `"flat_map" | "and_then"` arm: `and_then`
   keeps its Option/Result-monadic behavior (unchanged); a NEW dedicated `"flat_map"` arm (modeled on
   the `map` arm) binds the lambda param to the input element type A (no Integer placeholder),
   infers the body, and does the **one-level unwrap** — body `Collection[B]` ⇒ result `Collection[B]`
   (as-is, not re-wrapped); body `Unknown` ⇒ `Collection[Unknown]`; else `OOF-COL9` + recover
   `Collection[Unknown]`. OOF-COL1 (arity/non-lambda) + OOF-COL2 (non-collection first arg) mirror map.
2. `emitter.rs` — added `("flat_map", "stdlib.collection.flat_map")` to `COLLECTION_HOF_OPS`, **and**
   added `flat_map` to the compute-level delegation `matches!` in `semantic_expr_for_compute` (line
   ~1490). The second edit was the load-bearing one: without it a compute-level `flat_map(...)` never
   reached the qualification block (it fell through field-recursion and stayed bare) — that is exactly
   why `map` qualified but `flat_map` did not until both gates listed it.

**Parity caveat (documented, pre-existing — NOT a flat_map bug):** an array-literal lambda body
`x -> [x, x]` infers `Collection[Unknown]` in the lab Rust TC, because Rust array-literal element
inference is context-driven and a lambda body has no expected-type hint (the horizon-research §4 gap;
Ruby infers it from contents). So the one-level-unwrap proofs use collection-VALUED bodies (a Ref
`inner -> inner`, a record field `bd -> bd.items`) that carry a concrete element type; the
array-literal body is still covered as an Unknown-permissive case (no false OOF-COL9). The flat_map
contract itself is at full parity with Ruby P3.

Tests `lang/igniter-compiler/tests/collection_flat_map_tests.rs` (7): one-level-unwrap clean+qualified,
not-double-wrapped, record-pressure param-is-record-type, OOF-COL9, OOF-COL1/COL2, Unknown-permissive,
map-qualifies + and_then-Result-only. All green; regressions green; `git diff --check` PASS.

Next route: **inventory entry + digest recompute** for `stdlib.collection.flat_map`
(`docs/spec/stdlib-inventory.json`, P5-style, with proof lineage P1→P3→P4) — deferred to its own card
per the map/filter precedent (inventory lands separately). Then the broader
`LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1` (promote zip/take/find/any/all) from the horizon roadmap.

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
