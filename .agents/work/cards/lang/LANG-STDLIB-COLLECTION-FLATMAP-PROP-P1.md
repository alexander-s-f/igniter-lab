# LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1

Status: OPEN
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

- [ ] Live canon Ruby, lab Rust compiler, VM, and inventory state are
      characterized separately.
- [ ] The card explicitly distinguishes canon authority from lab evidence.
- [ ] A decision is made: admit `flat_map` now, or hold with a named blocker.
- [ ] If admitted, the exact signature, source alias, SemanticIR name, result
      type rule, Unknown policy, and diagnostics are specified.
- [ ] If admitted, the packet names implementation cards:
      `LANG-STDLIB-COLLECTION-FLATMAP-P3` (Ruby `igc`) and
      `LANG-STDLIB-COLLECTION-FLATMAP-P4` (Rust parity).
- [ ] If not admitted, the packet names the precise gate that blocks it.
- [ ] The P7 descriptor pressure is mapped directly to the decision.
- [ ] No silent compiler implementation crosses the `COLLECTION_HOF_FNS` gate.
- [ ] `git diff --check` clean.

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
