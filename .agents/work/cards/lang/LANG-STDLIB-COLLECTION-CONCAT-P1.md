# Agent Card: LANG-STDLIB-COLLECTION-CONCAT-P1

**Lane:** lang / stdlib / collection / concat  
**Mode:** READINESS / PROPOSAL BOUNDARY  
**Status:** CLOSED — AUTHORED / READINESS PROVED  
**Date closed:** 2026-06-12  
**Proposal doc:** `igniter-lang/.agents/work/proposals/LANG-STDLIB-COLLECTION-CONCAT-collection-concat-v0.md`  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_concat_p1.rb`

---

## Goal

Establish the readiness/proposal boundary for `stdlib.collection.concat`:
define the canonical contract, OOF namespace, disambiguation policy, current toolchain
state, and the triage route from orphaned inventory entry to `lab-implemented`.

---

## Key Decisions Made

### Contract
`concat(Collection[T], Collection[T]) → Collection[T]`  
Source alias `concat` shared with `stdlib.text.concat`; disambiguated by first arg type.

### Disambiguation Rule
| First arg type | Route |
|----------------|-------|
| `Collection` | → `stdlib.collection.concat` |
| `Unknown` | → `stdlib.collection.concat` (permissive — fixes DSA-P03) |
| `Text`, `String`, other concrete | → `stdlib.text.concat` (existing path) |

### OOF Namespace
| Code | Description | New/Reuse |
|------|-------------|-----------|
| OOF-COL1 | Arity ≠ 2 | Reuse |
| OOF-COL2 | First arg not Collection/Unknown | Reuse; extended to second arg ("second argument must be Collection[T]") |
| **OOF-COL7** | Element type mismatch: `Collection[T]` ++ `Collection[U]` where T ≠ U concrete | **NEW — first activation at P3** |

### DSA-P03 Root Cause
`rewrite_concat_calls` in Rust TC uses `quick_arg_type` which returns "Unknown" for
field access expressions. Unknown → text.concat rewrite → SIR fn = `"stdlib.text.concat"`,
resolved_type = Text. No diagnostic emitted. P4 must fix this disambiguation path.

### Rust Element Type Erasure Bug
Even when correctly routed to `stdlib.collection.concat`, the emitter produces
`resolved_type: {name: "Collection", params: []}` — element type parameter erased.
P4 must propagate `params[0]` from the first arg's type.

---

## Current State (Baseline)

| Toolchain | concat(Collection, Collection) behavior |
|-----------|----------------------------------------|
| Ruby TC | OOF-TY0: "stdlib.text.concat arg 1: expected Text, got Collection" |
| Rust TC (bare ref first arg) | ok, SIR fn = `stdlib.collection.concat`, resolved_type = Collection[] (params erased) |
| Rust TC (field access first arg) | ok (no diagnostic), SIR fn = `stdlib.text.concat`, resolved_type = Text (DSA-P03 mislabeling) |

### Inventory Entry (current)
- lifecycle_status: `orphaned`
- lowering_status: `single-toolchain`  
- aliases: `[]` (no source_alias — import would OOF-IMP3)
- diagnostics: `[]`

---

## Proof Coverage (45/45 PASS)

| Section | Content | Checks |
|---------|---------|--------|
| A (source structure) | inventory entry exists; lifecycle/lowering fields; Rust rewrite fn present; Ruby text-only dispatch | 7 |
| B (Ruby gap) | Collection concat → OOF-TY0; message references stdlib.text.concat; no collection path | 6 |
| C (Rust partial — bare ref) | `concat(a, b)` bare refs → `stdlib.collection.concat` in SIR; ok; no diagnostics | 5 |
| D (DSA-P03 mislabeling) | `concat(s.elements, [item])` → stdlib.text.concat in SIR; resolved_type=Text; no diagnostic | 4 |
| E (element type erasure) | `stdlib.collection.concat` resolved_type params=[] (inner type erased) | 3 |
| F (text.concat regression) | `concat(Text, Text)` still ok in both toolchains; SIR fn = stdlib.text.concat | 6 |
| G (app fixtures) | DSA SetInsert: Rust DSA-P03 confirmed; conformance collection_extension: Rust ok, Ruby oof | 6 |
| H (inventory fields) | no source_alias; no diagnostics; type_params=[T]; input/output signatures | 5 |
| I (authority / scope) | no VM dispatch; purity=pure; no flatten/flat_map/join/group_by | 3 |

---

## Closed Surfaces

- No parser changes
- No typechecker.rb / typechecker.rs implementation
- No VM / runtime / capability authority
- No flatten / flat_map / join / group_by
- No new import surface authority

---

## Previous / Related

- **DSA-P03**: `verify_lab_dsa_baseline_p1.rb` K-04 confirms mislabeling; routes to this card
- **stdlib.collection.concat inventory**: orphaned entry established in LANG-STDLIB-ENTRY-CONTRACT-P3

## Next Route

**LANG-STDLIB-COLLECTION-CONCAT-PROP-P2** — implementation planning (Ruby TC dispatch shape +
Rust TC fix approach + proof matrix)
