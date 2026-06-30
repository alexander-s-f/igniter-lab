# LANG-STDLIB-COLLECTION-FLATMAP-P3

Status: CLOSED (2026-06-28) — canon Ruby flat_map landed; proof 18/18; next = P4 Rust parity
Lane: lang / stdlib / collection / flat_map / ruby-igc
Mode: bounded implementation
Skill: idd-agent-protocol

## Context

`LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1` admitted `flat_map` as a canon
collection HOF surface:

```text
flat_map(Collection[A], A -> Collection[B]) -> Collection[B]
SIR: stdlib.collection.flat_map
```

This card is the Ruby `igc` implementation slice. It crosses the
`COLLECTION_HOF_FNS` gate under the P1 admission decision, but only for this one
function.

## Authority

Work in:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lang
```

Required reading:

- `igniter-lab/lab-docs/lang/lang-stdlib-collection-flatmap-prop-p1-v0.md`
- `igniter-lang/.agents/work/proposals/LANG-STDLIB-COLLECTION-FLATMAP-collection-flat_map-v0.md`
- `igniter-lang/lib/igniter_lang/typechecker.rb`
- existing proof runners:
  - `experiments/stdlib_collection_proof/verify_stdlib_collection_map_filter_p3.rb`
  - `experiments/stdlib_collection_concat_proof/verify_stdlib_collection_concat_p3.rb`

Live code wins if wording differs, but do not widen this card beyond the P1
admission contract.

## Goal

Implement Ruby `igc` typechecking/lowering for `flat_map`:

```text
flat_map(Collection[A], A -> Collection[B]) -> Collection[B]
```

and prove:

- source alias `flat_map` is accepted;
- SIR emits `stdlib.collection.flat_map`;
- result type is one-level unwrapped;
- lambda-body-not-collection fails with `OOF-COL9`;
- `map`/`filter`/`count` behavior is unchanged.

## Scope

Allowed:

- `igniter-lang/lib/igniter_lang/typechecker.rb`
- a new proof runner under `igniter-lang/experiments/stdlib_collection_flatmap_proof/`
- this card closing report
- optional proposal status note if the local style requires it

Closed:

- no Rust `igniter-compiler` parity work (that is P4);
- no VM changes (already green in lab);
- no `stdlib-inventory.json` edit/digest recompute in this card unless the local
  map/filter P3 precedent proves inventory changed there (expected: no);
- no `flatten`;
- no collection comprehensions;
- no Result `and_then` policy changes;
- no parser/classifier/assembler changes unless live code proves unavoidable.

## Implementation Notes

Current Ruby shape (verify live line numbers):

```ruby
COLLECTION_HOF_FNS = {
  "map"    => { qualified_name: "stdlib.collection.map",    arity: 2, has_lambda: true  },
  "filter" => { qualified_name: "stdlib.collection.filter", arity: 2, has_lambda: true  },
  "count"  => { qualified_name: "stdlib.collection.count",  arity: 1, has_lambda: false },
}.freeze
```

Add:

```ruby
"flat_map" => { qualified_name: "stdlib.collection.flat_map", arity: 2, has_lambda: true }
```

`infer_collection_hof_call` already handles arity, first-arg collection check,
lambda validation, element binding, and body inference for `map`/`filter`.
Extend it with:

```text
map      -> Collection[body_type]
filter   -> Collection[input_element_type]
flat_map -> if body_type is Collection[B] then Collection[B]
```

The crucial rule is **one-level unwrap**: do not use
`collection_type_ir_from(body_type)` for `flat_map`, because that would produce
`Collection[Collection[B]]`.

Diagnostic:

```text
OOF-COL9: lambda body must return Collection[B], got <Type>
```

Unknown policy:

- if body type is `Unknown`, result `Collection[Unknown]`, no `OOF-COL9`;
- if body type is `Collection[Unknown]`, result `Collection[Unknown]`;
- if first arg is `Collection[Unknown]`, lambda param is `Unknown` as today.

`and_then` remains Result-only. Do not expose it for collections.

## Proof Runner Requirements

Create a proof runner roughly like the existing collection proof scripts.

Minimum sections:

1. **Source registration**
   - `COLLECTION_HOF_FNS` includes `flat_map`;
   - qualified name is `stdlib.collection.flat_map`;
   - arity 2 and `has_lambda: true`.
2. **Happy path**
   - `flat_map(xs, x -> [x, x])` compiles clean;
   - SIR call fn is `stdlib.collection.flat_map`;
   - result type is `Collection[Integer]`, not nested.
3. **Record/descriptor pressure**
   - `flat_map(bodies, b -> BodyTriangles(b))` or a small equivalent returns
     a flat `Collection[Record]`/`Collection[Integer]`;
   - this should mirror the P7 row-to-many shape, not only scalar doubling.
4. **Unknown permissive**
   - if live fixtures can produce `Unknown`, prove no false `OOF-COL9`;
   - otherwise source-check the intended branch and document why a live Unknown
     fixture is deferred.
5. **OOF-COL9**
   - lambda returns non-collection scalar -> `OOF-COL9`;
   - message names `stdlib.collection.flat_map`.
6. **OOF-COL1 / OOF-COL2**
   - wrong arity / non-lambda second arg;
   - non-collection first arg.
7. **Regression**
   - `map`, `filter`, `count` proof snippets remain clean;
   - Result `and_then` remains Result-only.

Use exact assertions, not just “compiler exits”.

## Acceptance

- [x] `flat_map` added to Ruby `COLLECTION_HOF_FNS` (`{ qualified_name: "stdlib.collection.flat_map", arity: 2, has_lambda: true }`).
- [x] Ruby `igc` emits `stdlib.collection.flat_map` (proof 2.2/2.3; never bare).
- [x] One-level unwrap: `A -> Collection[B]` → `Collection[B]` (proof 2.1 clean + 2.4 nested-output MISMATCHES).
- [x] Scalar/non-collection lambda body → `OOF-COL9` naming `stdlib.collection.flat_map` (proof 5.1/5.2).
- [x] Unknown policy matches P1 (empty-list body → no false `OOF-COL9`, 4.1; body-fully-Unknown branch source-verified, 4.2).
- [x] `map`/`filter`/`count` regressions covered (7.1–7.3 clean + qualified + registered).
- [x] `and_then` remains Result-only (7.4: absent from `COLLECTION_HOF_FNS`).
- [x] Proof runner added + green (18/18).
- [x] No Rust/VM/parser/inventory/comprehension changes (only `typechecker.rb`).
- [x] `git diff --check` clean in `igniter-lang`.
- [x] Closing report below; next route `LANG-STDLIB-COLLECTION-FLATMAP-P4`.

## Report (2026-06-28)

Canon Ruby implementation under the P1 admission. Two edits in
`igniter-lang/lib/igniter_lang/typechecker.rb`: (1) added `flat_map` to `COLLECTION_HOF_FNS`
(arity 2, has_lambda); (2) a `when "flat_map"` branch in `infer_collection_hof_call`'s output-type
case doing the **one-level unwrap** — `type_name(body_type) == "Collection"` ⇒ return `body_type`
as-is (NOT `collection_type_ir_from`, which would double-wrap); `"Unknown"` ⇒ `Collection[Unknown]`
(permissive); else `OOF-COL9` + recover as `Collection[Unknown]`. `infer_collection_hof_call`
already owned OOF-COL1/COL2/lambda-binding, so those are inherited unchanged; OOF-COL3 stays
filter-only.

Proof runner `experiments/stdlib_collection_flatmap_proof/verify_stdlib_collection_flatmap_p3.rb`
(in the gitignored `experiments/` dir, the established convention for all sibling collection proof
runners): **18/18 PASS** — registration, happy path + qualified SIR + non-nested, record/descriptor
pressure (row→many flat), Unknown-permissive, OOF-COL9, OOF-COL1/COL2, and map/filter/count +
`and_then`-Result-only regressions.

Note on the map/filter P3 runner: it reports 2 failures (`H-05`/`H-06`, "map/filter not in
stdlib-inventory.json") — these are **pre-existing stale assertions** (P5 added those inventory
entries after the P3 runner was written). Proven independent of this card: with the `typechecker.rb`
change stashed, the same 2 failures persist. No flat_map effect; the inventory was not touched.

Verification: flat_map runner 18/18; `git diff --check` PASS (`igniter-lang`); only tracked change is
`typechecker.rb`. Next: **`LANG-STDLIB-COLLECTION-FLATMAP-P4`** — lab Rust parity (replace the
`stdlib_calls.rs` placeholder with the one-level-unwrap contract, emit `stdlib.collection.flat_map`,
byte-parity with Ruby; VM unchanged), then the inventory entry + digest recompute.

## Suggested Verification

Run from `/Users/alex/dev/projects/igniter-workspace/igniter-lang`:

```sh
ruby experiments/stdlib_collection_flatmap_proof/verify_stdlib_collection_flatmap_p3.rb
ruby experiments/stdlib_collection_proof/verify_stdlib_collection_map_filter_p3.rb
git diff --check
```

If the repo has a standard full Ruby/compiler suite, run the narrow relevant
subset and report exact command/results.

## Non-goals

- No Rust parity.
- No inventory digest.
- No `flatten`.
- No collection comprehension syntax.
- No performance optimization.
