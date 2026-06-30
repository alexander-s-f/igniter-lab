# LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2

Status: CLOSED (2026-06-29) — canon Ruby find/any/all landed; proof 33/33; next = Rust parity P3
Lane: lang / stdlib / collection / predicate-ops / ruby-canon
Mode: bounded implementation
Skill: idd-agent-protocol

## Goal

Implement the first collection-algebra promotion slice in canon Ruby `igc`:

```text
find(Collection[T], T -> Bool) -> Option[T]
any(Collection[T], T -> Bool)  -> Bool
all(Collection[T], T -> Bool)  -> Bool
```

This follows `LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1`, which chose the predicate slice first
because it is pure, deterministic, already lab-proven, and does not require a new type or Pair policy.

## Authority

Work in:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lang
```

Required reading:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lang-stdlib-collection-algebra-parity-prop-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
- existing collection proof runners under:
  - `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/stdlib_collection_proof/`
  - `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/stdlib_collection_flatmap_proof/`
  - sibling `first/last`, `filter_map`, `append`, `range`, `is_empty` proof dirs if useful

Path warning: the live canon typechecker path is `lib/igniter_lang/typechecker.rb`, not
`lib/igniter/typechecker.rb`.

## Verify-First

Before editing:

1. Confirm `find`, `any`, `all` are absent from canon Ruby dispatch/typechecker.
2. Confirm lab Rust + VM already have evidence for these names:
   - `igniter-lab/lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
   - `igniter-lab/lang/igniter-vm/src/vm.rs`
3. Confirm `Option[T]` is already an admitted type shape in canon Ruby (via `first`/`last` or
   `filter_map`/sumtype work).
4. Confirm `OOF-COL3` is the existing predicate-body-not-Bool diagnostic for `filter`.

Live source wins over this card if exact helper names differ.

## Scope

Allowed:

- edit `igniter-lang/lib/igniter_lang/typechecker.rb`;
- add a proof runner under a gitignored proof dir, e.g.
  `experiments/stdlib_collection_predicate_ops_proof/verify_stdlib_collection_predicate_ops_p2.rb`;
- update this card with a closing report.

Closed:

- no Rust `igniter-compiler` changes (P3);
- no VM/runtime changes;
- no `stdlib-inventory.json` changes or digest recompute (P4);
- no `take`/`drop`;
- no `zip`/`Pair`;
- no `group_by`/`sort_by`;
- no new syntax;
- no database/query authority.

## Implementation Notes

Use the existing collection-HOF path instead of inventing a new unrelated call path.

Expected source registration:

```ruby
"find" => { qualified_name: "stdlib.collection.find", arity: 2, has_lambda: true }
"any"  => { qualified_name: "stdlib.collection.any",  arity: 2, has_lambda: true }
"all"  => { qualified_name: "stdlib.collection.all",  arity: 2, has_lambda: true }
```

Expected type rules:

```text
find(Collection[T], T -> Bool) -> Option[T]
any(Collection[T], T -> Bool)  -> Bool
all(Collection[T], T -> Bool)  -> Bool
```

Expected diagnostics:

- `OOF-COL1`: wrong arity or missing/non-lambda callback;
- `OOF-COL2`: first argument is concrete non-Collection;
- `OOF-COL3`: callback/predicate body is concrete non-Bool.

Unknown policy:

- first arg `Unknown` or `Collection[Unknown]` is permissive;
- predicate body `Unknown` is permissive (no false `OOF-COL3`);
- `find` over unknown element returns `Option[Unknown]`;
- `any`/`all` always return `Bool` after structural diagnostics.

SIR/lowering:

- emitted call fn names must be qualified:
  - `stdlib.collection.find`
  - `stdlib.collection.any`
  - `stdlib.collection.all`
- no bare names in SIR for successful compile cases.

## Proof Runner Requirements

Create a proof runner modeled on existing collection proof scripts. Minimum sections:

1. **Registration**
   - all three names are in the canon collection HOF registry;
   - arity 2 / lambda true;
   - qualified names exact.
2. **Happy path / SIR**
   - `find(xs, x -> x > 0)` compiles clean and emits `stdlib.collection.find`;
   - `any(xs, x -> x > 0)` emits `stdlib.collection.any`;
   - `all(xs, x -> x > 0)` emits `stdlib.collection.all`.
3. **Type outputs**
   - `find(Collection[Integer], ...)` output assignable to `Option[Integer]`;
   - `any` and `all` output assignable to `Bool`;
   - `find` output is NOT `Collection[Integer]` and NOT bare `Integer`.
4. **Record predicate pressure**
   - `find(Collection[Todo], t -> t.done)` or equivalent record-field predicate works;
   - proves lambda param is bound to element type.
5. **Diagnostics**
   - wrong arity / non-lambda second arg → `OOF-COL1`;
   - non-collection first arg → `OOF-COL2`;
   - predicate returns scalar non-Bool → `OOF-COL3`.
6. **Unknown permissive**
   - body `Unknown` or a fixture that makes predicate type unknown does not falsely raise `OOF-COL3`;
   - if a live Unknown fixture is too expensive, source-check the branch and state the limitation.
7. **Regression**
   - `filter` still uses `OOF-COL3`;
   - `flat_map` remains collection-returning and does not accept scalar predicate bodies;
   - `first`/`last` Option behavior unchanged;
   - no `zip`/`Pair` behavior introduced.

Use exact assertions. Do not count “compiler exits” as proof by itself.

## Acceptance

- [x] `find`, `any`, and `all` are added to canon Ruby collection-HOF dispatch.
- [x] SIR emits qualified `stdlib.collection.find/any/all`.
- [x] `find(Collection[T], T -> Bool) -> Option[T]`.
- [x] `any/all(Collection[T], T -> Bool) -> Bool`.
- [x] Lambda param binds to collection element type (record-field predicate proof).
- [x] `OOF-COL1`, `OOF-COL2`, `OOF-COL3` covered.
- [x] Unknown predicate policy is permissive where existing filter policy is permissive.
- [x] `filter`, `flat_map`, `first`, `last` regressions covered.
- [x] Proof runner added and green.
- [x] No Rust/VM/parser/inventory/syntax changes.
- [x] `git diff --check` clean in `igniter-lang`.
- [x] Closing report names next card: expected `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3` (lab Rust parity)
      unless live evidence forces a different route.

## Suggested Verification

From `/Users/alex/dev/projects/igniter-workspace/igniter-lang`:

```bash
ruby experiments/stdlib_collection_predicate_ops_proof/verify_stdlib_collection_predicate_ops_p2.rb
git diff --check
```

Optionally rerun the nearest existing regressions:

```bash
ruby experiments/stdlib_collection_flatmap_proof/verify_stdlib_collection_flatmap_p3.rb
ruby experiments/stdlib_collection_proof/verify_stdlib_collection_map_filter_p3.rb
```

If a legacy proof has stale inventory expectations, isolate and report it rather than treating it as a
predicate-regression.

## Non-goals

- No lab Rust parity.
- No VM changes.
- No inventory digest.
- No `take/drop`.
- No `zip` / `Pair`.
- No `join` / query DSL.
- No lazy stream/transducer work.

## Closing Report Requirements

Report:

- exact files changed;
- proof runner result count;
- whether existing map/filter/flat_map proof runners still pass or any stale failures are isolated;
- `git diff --check` result;
- next card name.

## Closing Report

Closed on 2026-06-29.

Changed files:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/stdlib_collection_predicate_ops_proof/verify_stdlib_collection_predicate_ops_p2.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2.md`

Implemented canon Ruby collection predicate ops in the existing collection-HOF path:

- `find(Collection[T], T -> Bool) -> Option[T]`
- `any(Collection[T], T -> Bool) -> Bool`
- `all(Collection[T], T -> Bool) -> Bool`

Verification:

- `ruby experiments/stdlib_collection_predicate_ops_proof/verify_stdlib_collection_predicate_ops_p2.rb`
  - `predicate ops P2: 33 passed, 0 failed`
- `ruby experiments/stdlib_collection_flatmap_proof/verify_stdlib_collection_flatmap_p3.rb`
  - `flat_map P3: 18 passed, 0 failed`
- `ruby experiments/stdlib_collection_proof/verify_stdlib_collection_map_filter_p3.rb`
  - `59 PASS / 2 FAIL / 61 total`
  - isolated stale inventory checks: `H-05` and `H-06` expect `stdlib.collection.map/filter` not to be in
    `stdlib-inventory.json`; dispatch/typechecker checks passed.
- `ruby -c experiments/stdlib_collection_predicate_ops_proof/verify_stdlib_collection_predicate_ops_p2.rb`
  - `Syntax OK`
- `git diff --check`
  - clean

Boundary:

- No Rust `igniter-compiler` edits.
- No VM/runtime edits.
- No parser/syntax edits.
- No inventory/digest edits.
- No `take/drop`, `zip`/`Pair`, query, or database authority changes.

Next card:

- `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P3` (lab Rust parity / already-present evidence normalization).
