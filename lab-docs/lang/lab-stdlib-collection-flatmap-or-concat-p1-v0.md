# LAB-STDLIB-COLLECTION-FLATMAP-OR-CONCAT-P1 — readiness + VM-half wired

Status: READINESS STOP (Phase 2). The smallest primitive that unblocks the P7 descriptor pressure is
**`flat_map`** — and its VM half is ALREADY implemented; this card WIRES the qualified name to it and
PROVES it flattens. The remaining work is the compiler-side registration, which is PROP-gated in canon,
so it is named as a follow-up card rather than patched from a lab card.
Lane: igniter-lab / stdlib / collection / app-pressure
Date: 2026-06-28
Builds on: `LAB-FRAME-3D-GAME-IG-MESH-DESCRIPTOR-P7`, the concat series (`LANG-STDLIB-COLLECTION-CONCAT-P1/P3/P4`).

## Phase 0 — live collection surface (verified, not from old cards)

End-to-end (Ruby `igc` compile + `igniter-vm` run), all confirmed THIS card:

| primitive | compiler-known | VM | end-to-end today | note |
|---|---|---|---|---|
| `map` / `filter` / `count` | ✓ (`COLLECTION_HOF_FNS`) | ✓ | ✓ | PROP-registered HOFs |
| `fold` (3-arg, `(acc,x) ->`) | ✓ | ✓ | ✓ | result type = SEED type (see gap) |
| `concat(Coll[T],Coll[T])` | ✓ (P3/P4) | ✓ (`vm.rs:1571`) | ✓ `[1,2]++[3,4]=[1,2,3,4]` | text `concat` still routes (`"foo"++"bar"="foobar"`) |
| `append(Coll[T],T)` | ✓ | ✓ | ✓ | |
| `filter_map` / `first` / `last` / `sum` / `range` / `zip` | ✓ | ✓ | ✓ | |
| **`flat_map`** | ✗ (compiler) | **✓** (`vm.rs:2660`, Array→lambda→flatten) | ✗ (compiler `Unknown function: flat_map`) | **VM half done** |
| **`flatten`** | ✗ | ✗ | ✗ | absent everywhere |

Two precise blockers to `.ig`-authored full vertex/triangle soup (`Coll[Body] → Coll[Coll[Vertex]] → flat`):

1. **`flat_map` is not registered in the compiler.** The Rust VM implements it (`"flat_map" | "and_then"`,
   `vm.rs:2660`: for an Array, eval the lambda per element and `extend` when the result is an Array —
   exactly map-then-flatten), but the typechecker has no entry, so `.ig` won't compile a `flat_map` call.
2. **`fold` with an empty seed erases the element type.** `fold(xss, [], (acc,xs) -> concat(acc,xs))`
   fails to typecheck: `[]` is `Collection[Unknown]`, and `fold`'s result type is the SEED type
   (`acc_type`, `typechecker.rb:3091+`), so it stays `Collection[Unknown]` even though the lambda returns
   `Collection[Integer]` → `Output type mismatch: expected Collection[Integer], got Collection[Unknown]`.
   So the obvious `fold+concat` flatten is also blocked today.

## Phase 1 — alternatives compared (against the P7 pressure)

| option | unblocks nest→flat | cost now | breadth |
|---|---|---|---|
| 1. `concat(Coll,Coll)` | only pairwise / known-arity | **0 (works)** | lists, header+body assembly |
| 2. `append`+repeat | manual, O(n) verbose | 0 (works) | small builds |
| 3. `flatten(Coll[Coll[T]])` | yes | VM + compiler (both new) | general |
| 4. **`flat_map(Coll[A], A->Coll[B])`** | **yes, directly** | **VM done; compiler reg (PROP)** | lists/reports/mesh/science |
| 5. fold empty-seed inference fix | yes (`fold+concat`) | compiler (infer acc elem from body) | general, no new fn |

**Recommendation: `flat_map`.** It is the smallest primitive that DIRECTLY models the P7 pressure
(`map` then flatten), the VM half already exists, and it generalises to UI lists, report sections, science
vectors, and future mesh descriptors. `concat`/`append` already cover multi-list assembly (header+body+
footer) TODAY — that part of the pressure is already unblocked.

## What this card did (in-bounds): wire + prove the VM half

- `lang/igniter-vm/src/vm.rs`: added the alias `"stdlib.collection.flat_map" => "flat_map"` next to the
  other `stdlib.collection.*` aliases, routing the qualified name the compiler WOULD emit to the existing
  handler. (Lab VM; additive; mirrors the `filter_map`/`concat` aliases.)
- **Proof the VM flattens via the qualified name** — same SIR, only the builtin name swapped, same input:

  ```text
  map(xs, x -> concat([x],[x]))  on [1,2,3]  → [[1,1],[2,2],[3,3]]   (nested)
  …rename stdlib.collection.map → stdlib.collection.flat_map in the SIR…
  flat_map equivalent            on [1,2,3]  → [1,1,2,2,3,3]         (FLATTENED) ✓
  ```

  So the VM executes `flat_map` end-to-end through the dispatch path; only the compiler registration is
  missing. VM suite **174 passed / 0**; `primitive_eq_parity_tests` 6/6; frame-ui `ig_vm_game_tests` 9/9;
  `git diff --check` clean. (No durable `.ig`-level test is committed for `flat_map` — it cannot compile
  until the registration lands; the reproducible VM proof above stands in until then. No misleading green.)

## Why not register the HOF here

`COLLECTION_HOF_FNS` (`igniter-lang/lib/igniter_lang/typechecker.rb:91`) carries an explicit governance
gate: **"Adding entries requires PROP amendment + P4+ authorization."** Registering `flat_map` changes the
canon language surface, and (like the `concat` series) needs BOTH compilers — the Ruby `igc` (canon) and
the Rust `igniter-compiler` (lab parity). That is a canon-governed, multi-surface effort, not a lab-card
patch. So this card stops at readiness with the VM half proven, and names the implementation cards.

## P7 pressure — honest answer

- **Multi-list assembly (header+body+footer, concat of known lists): UNBLOCKED today** (`concat`/`append`).
- **Full vertex/triangle soup (`map`→nested→flat): STILL BLOCKED** pending `flat_map` compiler
  registration (VM ready) OR the `fold` empty-seed inference fix. P7's `BoxInstance` descriptor remains the
  correct, working choice in the meantime; `flat_map` is what lifts it to per-vertex authorship.

## Next cards (named, ranked)

1. **`LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1`** (canon readiness + PROP amendment) — admit `flat_map` to
   `COLLECTION_HOF_FNS`; spec: `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]`; result type
   = the lambda body's collection type DIRECTLY (NOT `collection_type_ir_from(body_type)` as `map` does —
   that is the one-level-unwrap distinction); OOF-COL1/COL2 + a new "lambda must return Collection" check.
2. **`LANG-STDLIB-COLLECTION-FLATMAP-P3`** (Ruby `igc` typechecker + SIR) — mirror `map` registration with
   the unwrap; emit `stdlib.collection.flat_map` (the VM alias is already wired here).
3. **`LANG-STDLIB-COLLECTION-FLATMAP-P4`** (Rust `igniter-compiler` parity) — same as concat P4.
4. **`LANG-STDLIB-COLLECTION-FOLD-EMPTY-SEED-INFERENCE-P1`** (secondary) — when a `fold` seed is an empty
   collection literal, infer the accumulator element type from the lambda body (so `fold+concat` flattens
   without a new primitive). Smaller blast radius than a new HOF; useful on its own.

## Files

- `lang/igniter-vm/src/vm.rs` (+1 alias line, documented)
- this packet
