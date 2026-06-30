# LAB-STDLIB-COLLECTION-FLATMAP-OR-CONCAT-P1

Status: CLOSED (2026-06-28) — readiness stop, VM half wired + proven
Lane: igniter-lab / stdlib / collection / app-pressure / descriptor assembly

## Closing Report

- **Live surface (verified):** `map/filter/count/fold/concat/append/filter_map/first/last/sum/range/zip`
  all work end-to-end (Ruby `igc` + VM). `concat(Coll,Coll)` → `[1,2]++[3,4]=[1,2,3,4]`; text concat still
  routes (`"foo"++"bar"`). **`flat_map` is VM-implemented** (`vm.rs:2660`, Array→lambda→flatten) but
  compiler-UNregistered; **`flatten` absent everywhere.**
- **Two precise blockers to nest→flat:** (1) `flat_map` not in the compiler; (2) `fold` with empty seed
  `[]` erases element type (result = seed type = `Collection[Unknown]`) → `fold+concat` won't typecheck.
- **Recommendation:** `flat_map` — smallest primitive that directly models `map`-then-flatten; **VM half
  already done.** `concat`/`append` already unblock multi-list (header+body) assembly TODAY.
- **In-bounds work done:** wired `"stdlib.collection.flat_map" => "flat_map"` alias in the lab VM and
  PROVED it flattens (same SIR, `map`→`flat_map` rename, `[1,2,3]`: `[[1,1],[2,2],[3,3]]` → `[1,1,2,2,3,3]`).
  VM suite 174/0; primitive_eq 6/6; ig_vm_game 9/9; `git diff --check` clean.
- **Why readiness stop:** `COLLECTION_HOF_FNS` (`typechecker.rb:91`) is gated — "Adding entries requires
  PROP amendment + P4+ authorization" — and needs both compilers (canon Ruby + lab Rust), like the concat
  series. Not a lab-card patch.
- **P7 answer:** multi-list assembly UNBLOCKED (concat); full vertex/triangle soup STILL BLOCKED pending
  the compiler registration (VM ready). `BoxInstance` descriptor remains correct meanwhile.
- **Named next cards:** `LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1` (PROP amendment; result type = lambda
  body's collection DIRECTLY, the one-level unwrap vs `map`) → `-P3` (Ruby igc) → `-P4` (Rust parity) ▶
  secondary `LANG-STDLIB-COLLECTION-FOLD-EMPTY-SEED-INFERENCE-P1`.
- **Packet:** `lab-docs/lang/lab-stdlib-collection-flatmap-or-concat-p1-v0.md`.
Mode: focus card
Skill: idd-agent-protocol

## Context

`LAB-FRAME-3D-GAME-IG-MESH-DESCRIPTOR-P7` proved the useful pattern:

```text
domain state -> .ig descriptor -> host renderer
```

But it also found the top language/stdlib blocker: Igniter can `map` bodies into
`Collection[BoxInstance]`, but it cannot currently flatten or concatenate nested
collections in a way that would let `.ig` author full triangle/vertex soup:

```text
Collection[Body]
  -> map(body -> Collection[Vertex])
  -> Collection[Collection[Vertex]]
  -> ??? no flat_map / flatten / usable concat chain
```

P7 therefore chose a staged `BoxInstance` descriptor and let the host expand cube
topology. That was the right proof boundary, but the missing collection assembly
primitive is now real app/game/science pressure, not theoretical stdlib polish.

There is prior collection-concat work. Read it, but trust live code:

- `.agents/work/cards/lang/LANG-STDLIB-COLLECTION-CONCAT-P1.md`
- `.agents/work/cards/lang/LANG-STDLIB-COLLECTION-CONCAT-PROP-P3.md`
- any later `LANG-STDLIB-COLLECTION-CONCAT-*` / append / map-filter cards
- `lab-docs/lang/lab-frame-3d-game-ig-mesh-descriptor-p7-v0.md`
- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig`
- `frame-ui/igniter-frame/src/game_loop.rs`
- `frame-ui/igniter-frame/tests/ig_vm_game_tests.rs`

Known old facts to re-verify:

- `concat(Collection[T], Collection[T]) -> Collection[T]` was proved in a Ruby
  TC lane, with text-vs-collection disambiguation.
- Older cards mention Rust parity gaps, field-access routing, and element-type
  erasure. These facts may be stale.
- P7's actual pressure is broader than pairwise concat: full descriptor emission
  wants flattening, `flat_map`, or a small composable equivalent.

## Goal

Choose and prove the smallest collection assembly primitive that unblocks the
P7 descriptor pressure while remaining broadly useful for UI lists, reports,
science vectors, and future mesh descriptors.

Do not implement a whole sequence library. This card is about the next one
or two primitives, with live proof.

## Phase 0 — Verify Live Surface

Characterize the current state in live source/tests:

- Which collection primitives are available in parser/typechecker/SIR/VM?
- Does `concat(Collection[T], Collection[T])` work today through the real
  compiler and VM, for both bare refs and field accesses?
- Does text `concat(String, String)` still route correctly?
- Is there any existing `append`, `flatten`, `flat_map`, `fold`, or nested-HOF
  behavior that changes the choice?
- Is nested `map` inside lambda still a known limitation, or already fixed?

Write exact findings. If old card claims disagree with live code, live code wins.

## Phase 1 — Compare Alternatives

Compare at least these options against the P7 pressure:

1. `concat(Collection[T], Collection[T]) -> Collection[T]`
2. `append(Collection[T], T) -> Collection[T]` plus repeated construction
3. `flatten(Collection[Collection[T]]) -> Collection[T]`
4. `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]`
5. comprehension / builder syntax as future sugar over one of the above

Use concrete examples:

- full triangle-soup emission for a few boxes;
- `body = concat(header_nodes, rows)` style view assembly;
- report/table rows;
- scientific vector/list transformations.

Decision rule:

- Prefer the smallest primitive that can be implemented and tested now.
- If `concat` is already near-ready, it may be the first implementation slice.
- If P7 cannot be solved ergonomically without `flatten`/`flat_map`, name that
  honestly instead of pretending pairwise concat is enough.

## Phase 2 — Implementation Or Readiness Stop

If one primitive is clearly implementable in this card, implement it narrowly.
Expected proof surface:

- real compiler accepts typed collection use;
- VM executes it, including HOF/eval_ast path if relevant;
- element type is preserved where the current type system can express it;
- mismatched concrete element types fail with a useful diagnostic or are
  explicitly documented as not yet enforceable;
- text concat behavior does not regress.

If implementation would require a larger language decision, stop at a readiness
packet and name the exact implementation card(s). Do not hack a frame-ui-only
special case.

## Phase 3 — Pressure Proof

Add a small, durable proof that ties the primitive back to real pressure.
Pick the smallest feasible option:

- a `.ig` mesh/descriptor fixture that assembles more than one list;
- a ViewArtifact/list fixture that combines header/body/footer nodes;
- or a focused collection fixture that shows nested-to-flat assembly.

If the primitive is `flat_map`/`flatten`, include a nested-collection proof. If
the primitive is only `concat`, show at least multi-list assembly and state what
remains blocked for full triangle-soup.

## Acceptance

- [ ] Live collection surface characterized; old concat cards reconciled with
      current code.
- [ ] At least 5 alternatives compared with a concrete recommendation.
- [ ] Either a minimal primitive is implemented and tested, or a readiness packet
      names the exact next implementation card.
- [ ] If implemented: real compiler + VM proof exists, not only source-text checks.
- [ ] Text concat remains green / explicitly regression-tested.
- [ ] P7 pressure is answered honestly: unblocked, partially unblocked, or still
      blocked with a named next primitive.
- [ ] Proof/readiness packet written:
      `lab-docs/lang/lab-stdlib-collection-flatmap-or-concat-p1-v0.md`.
- [ ] `git diff --check` clean.

## Suggested Verification

Adapt exact test names after discovery; avoid filter-only commands that run
zero tests.

```sh
cargo test --manifest-path lang/igniter-compiler/Cargo.toml collection
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test primitive_eq_parity_tests
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_vm_game_tests
git diff --check
```

If you add a new VM test target, run it with `--test <target>`, not as a trailing
filter.

## Non-goals

- No general list-comprehension syntax.
- No `group_by`, lazy streams, iterator protocols, or query language.
- No host-renderer special cases.
- No broad parser redesign.
