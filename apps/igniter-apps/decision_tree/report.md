# Decision Tree Pressure Report

Updated: 2026-06-12

This app models a small decision-tree library using a flat arena representation. It is a useful pressure fixture because tree evaluation stresses collection lookup, element extraction, typed command composition, fixed-depth traversal, and ADT-like data modeling.

## Live Check

Source files checked:

- `types.ig`
- `builder.ig`
- `evaluator.ig`
- `example.ig`

Real multi-file compile currently stops early, but the first blockers differ by toolchain:

| Toolchain | Result | First blocking diagnostic |
| --- | --- | --- |
| Rust lab compiler | `status: oof` | `OOF-IMP2 unknown import path 'stdlib.collection'` in `DecisionTreeBuilder`, `DecisionTreeEvaluator`, and `DecisionTreeExample` |
| Ruby canon compiler | `status: error` | `ParseError: Expected name, got keyword(label)` |

Probe method:

- Rust probe removed only `import stdlib.collection.{ ... }` from the app copy.
- Ruby probe removed those imports and renamed `label` to `class_label` to get past the parser keyword barrier.

| Toolchain | Probe result | Downstream signal |
| --- | --- | --- |
| Rust lab compiler | `status: oof` | `OOF-TY0 call_contract: unknown callee 'append'` at four append sites |
| Ruby canon compiler | `status: oof` | `Unknown function: call_contract`; `Unsupported operator: ==`; cascading unresolved-symbol diagnostics |

## Findings

### DT-P01 - `stdlib.collection` import surface blocks the Rust path

`builder.ig`, `evaluator.ig`, and `example.ig` import `stdlib.collection`. The Rust lab compiler rejects all three imports with `OOF-IMP2` before classification/typechecking. This is the same import-surface pressure observed in the logistics and vector editor apps, but decision tree confirms it across three modules in one app.

Route: `LANG-STDLIB-IMPORT-SURFACE-P2/P3`.

### DT-P02 - `label` is a Ruby parser keyword

`TreeNode` and `Prediction` use a `label` field. The Ruby canon compiler currently fails before import resolution with `ParseError: Expected name, got keyword(label)`. This is a cross-toolchain hygiene issue: ordinary domain words can collide with parser-reserved names.

Route: parser keyword hygiene / reserved-name diagnostic follow-up. At minimum, app reports should call this out explicitly so agents do not misclassify it as a semantic failure.

### DT-P03 - `append` is required for arena construction

Tree building needs to add nodes and feature entries to collections. After removing the stdlib import line in a Rust probe, the next blocker is `call_contract("append", ...)`. This confirms `append` as a separate collection operation, not covered by `map/filter/count/fold/sum`.

Route: `LANG-STDLIB-COLLECTION-APPEND-P1`.

### DT-P04 - `head` / `first` / `find_one` is the critical data-structure gap

`FindNodeById` and `LookupFeature` can use `filter`, but `filter` returns `Collection[T]`. There is no surface operation for extracting exactly one node from a collection. Arena-based structures need a typed, fail-closed way to express “one matching element” or “no unique match”.

Route: `LAB-STDLIB-FIND-ONE-P1` or `LANG-STDLIB-COLLECTION-FIRST-P1`, with careful outcome/error semantics.

### DT-P05 - Text equality is app-visible

The app compares stable IDs and kind tags: `n.id == target_id`, `f.name == name`, and `node.kind == "leaf"`. Ruby currently reports `Unsupported operator: ==` in the probe. A decision-tree evaluator cannot avoid deterministic Text equality.

Route: `LANG-STDLIB-TEXT-EQUALITY-P1`.

### DT-P06 - Tree traversal wants managed recursion or a bounded traversal form

`Evaluate` is forced into fixed-depth unrolling. This keeps the app pure, but it does not scale. The pressure is not arbitrary loops; it is a managed traversal over a finite arena with explicit root and child IDs.

Route: managed recursion / bounded traversal research. This should reuse the SCC recursion work and avoid introducing unbounded runtime loops.

### DT-P07 - Optional fields are not structurally omittable

A fresh mini-probe confirmed that fields typed as `String?` or `Integer?` are still required in record literals. This app therefore uses sentinel values (`""`, `0`) for unused variant fields. The current model is a fat struct with `kind` tags, not a safe ADT.

Route: variant/ADT surface follow-up, plus optional-field semantics clarification.

### DT-P08 - `call_contract` return shape needs documentation

The app report notes an important behavior: single-output contract invocation collapses to the output value, not a wrapper record. This is useful but asymmetric, and it should be made explicit in any future typed invocation/form work.

Route: typed contract refs / invocation forms documentation and proof follow-up.

## Current Pressure Ranking

1. Ruby parser keyword hygiene (`label`) - blocks Ruby before semantic diagnostics.
2. `stdlib.collection` import surface - blocks Rust before typechecking and blocks the intended source style.
3. Collection `append` - required for building arenas and feature collections.
4. `find_one` / `first` / `head` - required for arena lookup after `filter`.
5. Text equality - required for IDs, feature names, and node kind tags.
6. Managed traversal - fixed-depth unroll is not a scalable decision-tree evaluator.
7. Variant/ADT surface - removes fat struct plus sentinel-field encoding.
8. Invocation return-shape documentation - needed for clean composition.

## Non-goals

- Do not add ambient runtime state or external model execution from this app.
- Do not treat fixed-depth unrolling as the final traversal model.
- Do not make `filter` silently return a scalar; element extraction needs explicit semantics.
- Do not solve `append` through stringly `call_contract` dispatch.
- Do not promote `kind` plus sentinel fields as a canonical ADT substitute.

## Recommended Next Cards

- `LAB-DECISION-TREE-PRESSURE-P1` - freeze this app as a pressure fixture with compile probes.
- `LANG-STDLIB-COLLECTION-APPEND-P1` - define and prove `stdlib.collection.append`.
- `LAB-STDLIB-FIND-ONE-P1` - explore typed single-element extraction over collections.
- `LANG-STDLIB-TEXT-EQUALITY-P1` - deterministic equality for Text/String IDs.
- Parser keyword hygiene card for ordinary field names such as `label`.
