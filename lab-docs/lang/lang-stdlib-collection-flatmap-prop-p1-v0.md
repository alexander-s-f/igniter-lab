# LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1 — readiness / PROP admission packet

Lane: lang / stdlib / collection / flat_map / canon-admission
Status: DONE (readiness/PROP) — **ADMIT `flat_map`**; Ruby P3 + Rust P4 named
Date: 2026-06-28
Card: `igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1.md`
Predecessor decision: `lab-stdlib-collection-flatmap-or-concat-p1-v0.md` (flat_map chosen as the
smallest primitive for the P7 descriptor pressure)

## Authority boundary (read first)

This is an admission/decision packet. **Canon authority lives in `igniter-lang` only.** The lab VM
runtime proof and the lab Rust compiler placeholder are **evidence, not authority** — neither admits
`flat_map` to the canon surface. Admission happens by the canon `COLLECTION_HOF_FNS` gate
(`igniter-lang/lib/igniter_lang/typechecker.rb`) whose own rule reads *"Adding entries requires PROP
amendment + P4+ authorization."* This packet is that PROP amendment; the Ruby (P3) and Rust (P4)
cards it names do the implementation.

## Live state — four surfaces, verified separately (2026-06-28)

| Surface | State | Evidence |
| --- | --- | --- |
| **Canon Ruby** (authority) | `flat_map` **NOT admitted**. `COLLECTION_HOF_FNS` = `map`/`filter`/`count` only (`typechecker.rb:91`). `and_then` exists but is **Result-monadic only** (`:1277`, `and_then(Result[T,E], (T->Result[U,E]))`), unrelated to collections. | `rg COLLECTION_HOF_FNS\|and_then typechecker.rb` |
| **Canon inventory** (authority) | No `stdlib.collection.flat_map` entry. `map`/`filter` added at P5; `count`, `first`, `last` present. | `docs/spec/stdlib-inventory.json` |
| **Lab Rust compiler** (evidence) | **Placeholder only.** `stdlib_calls.rs:1519` handles `"flat_map" \| "and_then"` together on the **Result** `and_then` path; the comment states *"flat_map keeps its prior Integer placeholder"* — i.e. it does NOT implement the collection one-level-unwrap typing. This is the stale placeholder the card warned about; P4 must REPLACE it, not rely on it. | `stdlib_calls.rs:1519-1646` |
| **Lab VM** (evidence) | **Runtime works.** `vm.rs:1020-1023` aliases `stdlib.collection.flat_map` → the existing array `flat_map` handler (per-element lambda, results flattened one level); commit `d2ed524` wired it. `map(xs, x->[x,x])` nests; the same SIR with `stdlib.collection.flat_map` flattens. | `vm.rs:1020`, lab packet |

Net: the **runtime** half is proven; the **canon compiler surface** is the gap. The lab Rust
placeholder is incidental, wrong for the collection contract, and out of scope until P4.

## Decision — ADMIT `flat_map` as a canon collection HOF now

The prior OR-CONCAT decision, the clear cross-domain pressure (below), and a proven VM runtime make
this the smallest correct primitive. It is admitted with the contract below; nothing is held.

### Canonical contract

| Field | Value |
| --- | --- |
| Source alias | `flat_map(collection, item -> collection)` |
| SemanticIR name | `stdlib.collection.flat_map` (the **only** name emitted) |
| Signature | `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]` |
| Arity | 2, `has_lambda: true` (mirrors `map`/`filter` in `COLLECTION_HOF_FNS`) |
| Purity / authority | `pure`, core stdlib, `authority_surface: none`, deterministic, total |
| **Result-type rule** | **one-level unwrap**: the result element type is the lambda body's collection element type. `A -> Collection[B]` ⇒ result `Collection[B]`, **never** `Collection[Collection[B]]`. |
| Unknown policy | **permissive**, matching `map`/`filter`/`concat`: `Collection[Unknown]` first arg or `Collection[Unknown]` lambda body ⇒ result `Collection[Unknown]`, no error. |

### Diagnostics

| Code | When | Status |
| --- | --- | --- |
| `OOF-COL1` | wrong arity / second arg not a lambda | reuse (same as `map`/`filter`) |
| `OOF-COL2` | first arg not `Collection` (and not `Unknown`) | reuse |
| `OOF-COL9` | **lambda body type is not a `Collection`** (and not `Unknown`) | **NEW** (COL1–COL8 already taken; COL9 is the next free code) |

A NEW code (`OOF-COL9`) is chosen over an `OOF-COL2` variant because the failure is semantically
distinct (body-not-collection ≠ first-arg-not-collection) and `flat_map` is the first HOF whose
lambda body must itself be a collection — a dedicated code keeps the operator's message precise.

## Answers to the card's questions

1. **Admit now or hold?** Admit now. Smallest primitive; VM proven; clear pressure. Not held for a
   broader comprehension decision.
2. **`and_then` for collections?** No. `and_then` is canon **Result**-monadic (`typechecker.rb:1277`)
   and stays Result-only. Collections expose **`flat_map` only**; overloading `and_then` for
   collections would collide with the Result op and there is no canon monadic-naming policy to lean
   on.
3. **Lambda-body-not-collection diagnostic?** New `OOF-COL9` (see above).
4. **Unknown element types?** Permissive, exactly as `map`/`filter`/`concat` (no fail-closed).
5. **Sufficient for P7?** Yes — `flat_map(Collection[A], A -> Collection[B])` directly assembles
   triangle/mesh and list descriptors. `flatten(Collection[Collection[T]])` is **out of v0** (named
   as a possible future alias; the CONCAT proposal's D12 already parks flatten/flat_map/join/group_by).
6. **Inventory fields + proof lineage?** A new entry mirroring the `map`/`filter` shape:
   `canonical_name`/`semantic_ir_name` = `stdlib.collection.flat_map`; `aliases` =
   `[{kind: source_alias, name: flat_map}]`; `category: "collection"`; `purity: pure`;
   `deterministic: true`; `totality: total`; `type_params: ["A","B"]`;
   `input_signature: ["Collection[A]", "(A -> Collection[B])"]`; `output_signature: "Collection[B]"`;
   `diagnostics: ["OOF-COL1","OOF-COL2","OOF-COL9"]`; `failure_behavior: "none; empty/Unknown permissive"`;
   `authority_surface: "none"`; `proof_lineage`: this PROP packet + `LAB-STDLIB-COLLECTION-FLATMAP-OR-CONCAT-P1`
   + `Rust VM stdlib.collection.flat_map (d2ed524)` + the P3/P4 proofs once they land. (Per the
   `map`/`filter` lineage the inventory entry is added with the implementation slices, not in this
   PROP card.)
7. **Ruby P3 boundary?** ONE file — `igniter-lang/lib/igniter_lang/typechecker.rb`. Add `flat_map` to
   `COLLECTION_HOF_FNS` (`arity: 2, has_lambda: true`) and extend `infer_collection_hof_call` with the
   one-level-unwrap result rule + `OOF-COL9`. No parser/classifier/SemanticIR-emitter/assembler/VM
   change; no `stdlib-inventory.json` edit in P3 (mirrors MAP-FILTER P3 scope).
8. **Rust P4 boundary?** Parity with Ruby in `igniter-lab/lang/igniter-compiler`. **Replace** the
   placeholder at `stdlib_calls.rs:1519` (which mis-types collection `flat_map` as an Integer
   placeholder on the Result `and_then` path) with the real one-level-unwrap typing, and ensure the
   emitter emits `stdlib.collection.flat_map`. The VM runtime is already correct — do not change it
   unless a live check shows the alias proof regressed.

## P7 descriptor pressure → decision mapping

P7 (3D mesh / ViewArtifact) must turn one domain row into *several* descriptor elements
(`body -> [tri, tri, …]`). With only `map`, that yields `Collection[Collection[Tri]]` (nested) and
needs a separate flatten the language doesn't have. `flat_map`'s one-level unwrap is exactly the
"row → many elements, assembled flat" operation — the same shape recurs in report/table section
assembly and science list transforms. Admitting `flat_map` unblocks all of these with one primitive.

## Named next cards

- **`LANG-STDLIB-COLLECTION-FLATMAP-P3`** — canon Ruby `igc`: add to `COLLECTION_HOF_FNS` +
  one-level-unwrap typing + `OOF-COL9` in `typechecker.rb` (one file). Proof: nested-vs-flat fixtures
  + Unknown-permissive + `OOF-COL9` negative.
- **`LANG-STDLIB-COLLECTION-FLATMAP-P4`** — lab Rust parity: replace the `stdlib_calls.rs` placeholder
  with the collection contract, emitter emits `stdlib.collection.flat_map`, byte-parity with Ruby;
  VM runtime unchanged. Then the inventory entry + digest recompute (P5-style, with the lineage above).

## Non-goals (unchanged)

No `flatten`, no comprehensions, no generalized monad / Result `and_then` policy, no host/frame-ui
workaround, **no VM change** (the alias proof is green), and **no silent compiler implementation
across the `COLLECTION_HOF_FNS` gate** — this packet only proposes; P3/P4 implement under their own
authorization.

## Verification (live checks, no code changed)

```text
rg COLLECTION_HOF_FNS|flat_map|stdlib.collection.flat_map  → canon Ruby map/filter/count only;
  and_then Result-only; lab Rust flat_map placeholder on the Result path; VM alias live (vm.rs:1020).
cargo test --manifest-path igniter-lab/lang/igniter-vm/Cargo.toml --test nested_hof_eval_execution_tests  → green (VM half)
git diff --check  → PASS (doc/proposal only; no compiler change)
```
