# DSA Pressure Report

Updated: 2026-06-12

This app implements small data-structure and algorithm patterns in Igniter: indexed arrays, sets, graphs, and string-like character lookup. It is a positive Rust baseline and a useful pressure map for collection primitives, equality, single-element extraction, and Ruby parity.

## Live Check

Source files checked:

- `types.ig`
- `arrays.ig`
- `sets.ig`
- `graphs.ig`
- `strings.ig`
- `example.ig`

Rust lab compiler result:

| Field | Value |
| --- | --- |
| status | `ok` |
| stages | `parse -> classify -> typecheck -> emit -> assemble` |
| source units | 6 |
| contracts | 12 |
| diagnostics | 0 |
| `semantic_ir_program.json` | 49,749 bytes |
| `sourcemap.json` | 37,073 bytes |
| `manifest.json` | 6,517 bytes |
| artifact hash | `sha256:29ec2742e597236c797b1eca2a27cced4e300bcfddadc7f0fe059807e57fd8f6` |

Ruby canon compiler result:

| Field | Value |
| --- | --- |
| status | `oof` |
| diagnostics | 25 |
| dominant blockers | `Unknown function: call_contract` (9), `Unsupported operator: ==` (6) |
| notable parity gap | Ruby resolves `concat` as `stdlib.text.concat`, not collection concat |

## Findings

### DSA-P01 - Full Rust multi-file compilation is proven

The Rust lab compiler successfully compiles all six files and produces a complete `igapp` artifact. This is a second positive app baseline after `vector_math`, but with a collection/algorithmic workload instead of numeric geometry.

Route: preserve as a regression fixture for collection, import, typechecker, emitter, and assembler changes.

### DSA-P02 - Array literals are real collection constructors

The source uses `[e0, e1, e2]`, `[100, 200]`, and `[edge1, edge2, edge3]`. Rust parses and typechecks these as `Collection[T]`. This removes the need for mock `empty`/`append` bootstrapping for many simple fixtures.

Route: document array literal semantics and include them in collection baseline tests.

### DSA-P03 - Collection concat exists in Rust but not Ruby parity

`SetInsert` uses `concat(s.elements, [new_elem])`. Rust accepts this as collection concat. Ruby currently resolves bare `concat` as `stdlib.text.concat` and reports `expected Text, got Collection`.

Route: `LANG-STDLIB-COLLECTION-CONCAT-P1`.

### DSA-P04 - Text/equality work is also integer equality work

DSA uses `==` over integers for indexed lookup, set contains, graph edge matching, and string-character lookup. Ruby reports `Unsupported operator: ==`. Equality work should cover deterministic Integer/Bool/Text equality as planned, not only Text.

Route: `LANG-STDLIB-TEXT-EQUALITY-P3`, with the P2 plan's Integer/Bool support preserved.

### DSA-P05 - `is_empty` / `non_empty` is required for true Set semantics

`SetContains` can filter matching values, but `SetInsert` cannot branch on whether the match collection is empty. The current implementation appends blindly, so it is semantically a multiset insert.

Route: `LANG-STDLIB-IS-EMPTY-PROP-P2/P3`.

### DSA-P06 - `find_one` / `head` remains a separate algorithmic gap

`ArrayGet`, `CharAt`, `GetAdjacent`, and `HasEdge` all return matching collections because the language cannot extract a single value. `is_empty` is the first guard primitive, but scalar extraction needs separate fail-closed semantics.

Route: `LAB-STDLIB-FIND-ONE-P1` after `is_empty` is implemented.

### DSA-P07 - Indexed access has an algorithmic cost

Without `col[i]`, DSA models arrays and strings using `IndexedElement { index, value }` and scans with `filter`/`map`. This turns ordinary indexed operations into O(n) transforms. This is acceptable as pressure evidence, not as a final data-structure story.

Route: keep in backlog until collection safety primitives settle.

### DSA-P08 - Ruby `call_contract` parity still dominates examples

Example contracts call `ArrayGet`, `ArraySet`, `SetContains`, `SetInsert`, `GetAdjacent`, `HasEdge`, and `CharAt` through `call_contract`. Ruby reports `Unknown function: call_contract`, creating downstream Unknown and unresolved-symbol diagnostics.

Route: typed contract refs / invocation forms / Ruby invocation parity follow-up.

## Current Pressure Ranking

1. Preserve Rust DSA full-compile baseline.
2. Equality implementation (`==`) for Integer/Bool/Text as planned.
3. Collection concat parity in Ruby.
4. `is_empty` / `non_empty` for true set semantics.
5. `find_one` / `head` for scalar extraction from filtered collections.
6. Ruby contract invocation parity.
7. Indexed access / algorithmic complexity backlog.

## Non-goals

- Do not promote DSA app-local helpers into stdlib wholesale.
- Do not treat blind `SetInsert` as true Set semantics.
- Do not solve scalar extraction by making `filter` return a scalar.
- Do not open mutable arrays or in-place updates from this app.
- Do not treat string-as-collection encoding as a final text model.

## Recommended Next Cards

- `LAB-DSA-BASELINE-P1` - freeze this app as a Rust full-pipeline regression fixture.
- `LANG-STDLIB-COLLECTION-CONCAT-P1` - define collection concat parity distinct from text concat.
- `LANG-STDLIB-IS-EMPTY-PROP-P2/P3` - implement emptiness guards.
- `LAB-STDLIB-FIND-ONE-P1` - explore single-element extraction semantics.
- `LANG-STDLIB-TEXT-EQUALITY-P3` - unlock deterministic equality across DSA filters.
