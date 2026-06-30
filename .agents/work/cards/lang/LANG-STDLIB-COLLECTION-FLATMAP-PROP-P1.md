# LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1

Status: CLOSED (2026-06-28) — ADMIT flat_map; Ruby P3 + Rust P4 named
Lane: lang / stdlib / collection / flat_map / canon-admission
Mode: readiness + PROP amendment
Skill: idd-agent-protocol

## Context

`LAB-STDLIB-COLLECTION-FLATMAP-OR-CONCAT-P1` closed with a clear decision:
`flat_map` is the smallest primitive that directly unblocks the P7 descriptor
pressure:

```text
Collection[A] --flat_map(A -> Collection[B])--> Collection[B]
```

This matters beyond 3D:

- full mesh/triangle descriptor emission;
- ViewArtifact list assembly from domain rows;
- report/table section assembly;
- science vector/list transformations.

The VM half is already proven in the lab:

- `lang/igniter-vm/src/vm.rs` has an existing `flat_map` / `and_then` handler;
- commit `d2ed524` wired `stdlib.collection.flat_map` to that handler;
- VM proof showed `map(xs, x -> [x,x])` gives nested arrays while the same SIR
  with `stdlib.collection.flat_map` gives a flattened array.

But the canon compiler surface is intentionally gated. In
`igniter-lang/lib/igniter_lang/typechecker.rb`, `COLLECTION_HOF_FNS` currently
contains only `map`, `filter`, and `count`, with this rule:

```text
Adding entries requires PROP amendment + P4+ authorization.
```

This card is that admission step. Do not treat the lab VM alias or any lab Rust
placeholder as canon authority.

## Goal

Write the canon-facing readiness / PROP packet that admits
`stdlib.collection.flat_map` as a collection HOF surface and defines the exact
implementation contract for the follow-up Ruby and Rust compiler cards.

This card may update proposal/governance text and the card itself. It should not
silently implement compiler behavior unless the local authority documents make
that explicitly allowed. The expected output is a precise, implementation-ready
decision packet plus named next cards.

## Current Authority To Verify

Read live state first. Old proof packets are evidence, not authority.

Canon / Ruby:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`
- any canon proposal files related to collection HOFs / stdlib inventory

Lab / Rust / VM evidence:

- `lab-docs/lang/lab-stdlib-collection-flatmap-or-concat-p1-v0.md`
- `.agents/work/cards/lang/LAB-STDLIB-COLLECTION-FLATMAP-OR-CONCAT-P1.md`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-compiler/src/emitter.rs`
- existing `map/filter/count`, `concat`, nested-HOF, and VM tests

Important stale-risk note:

- `lab-stdlib-collection-flatmap-or-concat-p1` says "`flat_map` is compiler
  unregistered." Re-verify both compilers. The lab Rust compiler may already
  contain old placeholder `flat_map` / `and_then` code. Canon Ruby and the
  stdlib inventory still decide admission.

## Proposed Surface

Source alias:

```text
flat_map(collection, item -> collection)
```

Canonical SemanticIR function name:

```text
stdlib.collection.flat_map
```

Signature:

```text
flat_map(Collection[A], A -> Collection[B]) -> Collection[B]
```

Purity / authority:

```text
pure, core stdlib, authority_surface: none
```

Relationship to `map`:

```text
map(Collection[A], A -> B) -> Collection[B]
flat_map(Collection[A], A -> Collection[B]) -> Collection[B]
```

The crucial type rule is the one-level unwrap: `flat_map` result type is the
lambda body's collection element type. It must not wrap the body type again as
`Collection[Collection[B]]`.

## Questions To Answer

1. Is `flat_map` admitted as a canon collection HOF now, or held for a broader
   collection-comprehension decision?
2. Should `and_then` remain an internal/legacy alias, or is only `flat_map`
   public for collections?
3. What diagnostic should fire when the lambda does not return a collection?
   Reuse OOF-COL2, or introduce a new OOF-COL code?
4. How should `Unknown` element types behave?
   Preserve the permissive pattern used by `map`/`concat`, or fail closed?
5. Is `flat_map(Collection[A], A -> Collection[B])` sufficient for P7, or does
   the proposal also need a future `flatten(Collection[Collection[T]])` alias?
6. What exact inventory fields and proof lineage should be added?
7. What is the Ruby P3 implementation boundary?
8. What is the Rust P4 parity boundary, given the existing lab placeholder?

## Recommended Decision Shape

Unless live evidence contradicts it, recommend:

- admit `flat_map` as a public source alias;
- do not expose `and_then` for collections in source unless canon already has a
  broader monadic naming policy;
- emit only `stdlib.collection.flat_map` in SIR;
- require lambda return type `Collection[B]`;
- result type is `Collection[B]`;
- arity error: OOF-COL1;
- first arg non-collection: OOF-COL2;
- lambda body non-collection: either a new explicit OOF-COL code or an OOF-COL2
  variant, but choose one and document it;
- `Unknown` remains permissive where current collection HOFs are permissive;
- `flatten` stays out of v0.

## Deliverables

1. A readiness / PROP packet, suggested path:

   ```text
   lab-docs/lang/lang-stdlib-collection-flatmap-prop-p1-v0.md
   ```

2. If this repo has a proposal directory for this lane, add or update a proposal
   draft that future implementation cards can cite. Prefer the existing
   collection-HOF proposal style over inventing a new template.

3. Update this card with a closing report and named next cards.

## Acceptance

- [x] Canon Ruby / lab Rust / VM / inventory characterized separately (packet §"Live state").
- [x] Canon authority vs lab evidence explicitly distinguished (packet §"Authority boundary").
- [x] Decision made: **ADMIT `flat_map` now**.
- [x] Exact signature, source alias, SemanticIR name, one-level-unwrap result rule, Unknown
      policy, and diagnostics (`OOF-COL1`/`OOF-COL2`/new `OOF-COL9`) specified.
- [x] Implementation cards named: `LANG-STDLIB-COLLECTION-FLATMAP-P3` (Ruby) +
      `LANG-STDLIB-COLLECTION-FLATMAP-P4` (Rust parity).
- [x] P7 descriptor pressure mapped directly to the decision.
- [x] No silent compiler implementation crosses the `COLLECTION_HOF_FNS` gate (proposal + readiness
      packet only; `typechecker.rb`/inventory untouched).
- [x] `git diff --check` clean (both repos).

## Report (2026-06-28)

**Decision: ADMIT `flat_map`.** Verify-first separated the four surfaces: canon Ruby
(`COLLECTION_HOF_FNS` = map/filter/count; `and_then` is Result-only) and the canon inventory both
LACK flat_map (the real gate); the lab Rust compiler has a **placeholder** (`stdlib_calls.rs:1519`
rides the Result `and_then` path with an "Integer placeholder" — wrong for collections, must be
replaced in P4); the lab VM runtime is real and proven (`vm.rs:1020`, `d2ed524`). So the runtime half
is done and only the canon compiler surface needs admission.

Contract: `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]`, SIR
`stdlib.collection.flat_map`, arity 2 + lambda, pure/total, **one-level unwrap** (result element =
lambda body's collection element type, never double-wrapped), Unknown permissive (as map/filter/
concat). Diagnostics: reuse `OOF-COL1`/`OOF-COL2`, NEW `OOF-COL9` for lambda-body-not-collection
(COL1–COL8 taken). `and_then` stays Result-only; `flatten` out of v0.

Deliverables: readiness/PROP packet
`igniter-lab/lab-docs/lang/lang-stdlib-collection-flatmap-prop-p1-v0.md`; canon proposal draft
`igniter-lang/.agents/work/proposals/LANG-STDLIB-COLLECTION-FLATMAP-collection-flat_map-v0.md`
(authored-pending-review — proposal text only, no `typechecker.rb`/inventory edit).

Next cards: `LANG-STDLIB-COLLECTION-FLATMAP-P3` (Ruby `igc`, one file: add to `COLLECTION_HOF_FNS` +
one-level-unwrap + `OOF-COL9`) → `LANG-STDLIB-COLLECTION-FLATMAP-P4` (Rust parity: replace the
placeholder, emit `stdlib.collection.flat_map`, byte-parity; VM unchanged; inventory entry + digest
follow).

Verification: VM `nested_hof_eval_execution_tests` 5/5, `primitive_eq_parity_tests` 6/6; `git diff
--check` PASS (igniter-lab + igniter-lang). No compiler/inventory behavior changed.

## Suggested Verification

This card is mostly doc/proposal, but the agent should use live checks to avoid
stale claims:

```sh
rg -n "COLLECTION_HOF_FNS|flat_map|stdlib.collection.flat_map" \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec \
  lang/igniter-compiler/src \
  lang/igniter-vm/src

cargo test --manifest-path lang/igniter-vm/Cargo.toml --test nested_hof_eval_execution_tests
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test primitive_eq_parity_tests
git diff --check
```

Do not use a trailing filter where `--test <target>` is required.

## Non-goals

- No `flatten` implementation.
- No collection comprehensions.
- No generalized monad / Result `and_then` policy.
- No host/frame-ui-specific workaround.
- No VM changes unless a live check shows the VM alias proof regressed.
