# LAB-STDLIB-COLLECTION-ZIP-PROOF-P2 - prove + lock the existing `zip` collection op

Status: CLOSED (2026-06-24) — zip proven end-to-end + Pair field-access typing fixed; 6 e2e tests green, compiler suite green.
Lane: stdlib science / collections
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

`LAB-STDLIB-COLLECTION-ZIP-READINESS-P1` found that `zip` is already wired (VM eval_ast + bytecode,
parity-identical; declared `stdlib/collections.ig`) but **had no tests** and its synthetic `Pair[A,B]`
field access was **unverified**. This card proves the runtime semantics, locks them with tests, fixes the
one real gap (Pair field-access typing), and documents the unequal-length contract. No new primitive.

## Verify First (done)

Read `lang/igniter-vm/src/vm.rs` zip arms (`:1817` eval_ast, `:4920` bytecode — both `min`-truncate →
`Record{first,second}`), typecheck arm `typechecker/stdlib_calls.rs:789` (builds `Collection[Pair[A,B]]`),
`stdlib/collections.ig:13`, and the field-access resolver `typechecker.rs:3953`. Empirically probed the
real toolchain: `zip` runs; **`map(zip(a,b), p -> p.first + p.second)` FAILED typecheck** with
`OOF-P1 "Unresolved field: Pair.first"` — `Pair` has no `type_shapes` entry, so field access fell to
Unknown → error.

## What changed

- **Typechecker fix** (`lang/igniter-compiler/src/typechecker.rs`, `Expr::FieldAccess`): a whitelist for
  the synthetic `Pair[A,B]` (mirrors the existing `Collection.tail/rest` whitelist) — `.first` resolves to
  type param 0, `.second` to param 1; an Unknown param resolves to Unknown (never a false `OOF-P1`). This
  makes paired iteration `map(zip(a,b), p -> f(p.first, p.second))` typecheck. No grammar/VM change.
- **Tests** (`lang/igniter-vm/tests/stdlib_collection_zip_tests.rs`, 6 e2e via real compiler+VM):
  Pair `{first,second}` shape; truncate-to-min (left-longer + right-longer); typed field access
  (Integer + Float); empty → empty.
- **Docs**: `stdlib/collections.ig` `zip` now documents truncate-to-min + typed Pair field access +
  the consumer-guards-equal-length note.

## Semantics locked

`zip(Collection[A], Collection[B]) -> Collection[Pair[A,B]]`; positional; **unequal lengths truncate to
`min` (silent, deterministic, total — never errors on mismatch)**; element = `Record{first, second}`;
`Pair.first : A`, `Pair.second : B` typed. Deterministic by construction (integer indexing + clone, fixed
source order; no float math). A paired statistic that must not drop observations guards equal length
itself before zipping (the consumer policy from P1).

## Acceptance

- [x] `zip` runtime semantics proven through real compiler + VM (6 tests).
- [x] Truncate-to-min locked (both sides longer).
- [x] `Pair.first`/`.second` typecheck (Integer + Float), fixing `OOF-P1`.
- [x] Unequal-length + Pair-typing contract documented in `collections.ig`.
- [x] No new primitive; no grammar/VM behavior change (typecheck-only fix is additive).
- [x] Compiler suite green (27 test-binaries ok); VM HOF/record suites green; `git diff --check` clean.

## Closing Report (2026-06-24)

**Root cause + fix:** synthetic `Pair` had no field schema → `Pair.first/.second` errored `OOF-P1`. Added a
`Pair` field-access whitelist in `typechecker.rs` resolving `.first→param0`, `.second→param1`. `zip` is now
usable in typed code.

**Evidence (all green):**
- `cargo test --test stdlib_collection_zip_tests` → 6/6 (shape, truncate L/R, Integer/Float field access, empty).
- `cd lang/igniter-compiler && cargo test` → 27 test-binaries ok (no regression from the typechecker change).
- VM `record_construction_in_lambda_tests` (2) + `nested_hof_eval_execution_tests` (5) green.
- `git diff --check` clean. STDLIB_VERSION unchanged (no surface/wiring change — typecheck-only).

**Files:** `lang/igniter-compiler/src/typechecker.rs` (Pair whitelist),
`lang/igniter-vm/tests/stdlib_collection_zip_tests.rs` (new), `lang/igniter-stdlib/stdlib/collections.ig` (doc).

## Suggested Next

`LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P3` — pure `.ig` `covariance`/`correlation :
(Collection[Float], Collection[Float]) -> Option[Float]` with an explicit equal-length guard (→ `none()`),
built on `map`∘`zip` + P2 stats. Optional ergonomic follow-on: `zip_with` fusion (avoids Pair allocation).
