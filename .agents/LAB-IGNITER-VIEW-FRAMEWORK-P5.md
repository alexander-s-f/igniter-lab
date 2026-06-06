# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P5

Card: LAB-IGNITER-VIEW-FRAMEWORK-P5
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-igniter-view-collection-rendering-schema-extension-v0
Status: done
Date: 2026-06-06
Type: implementation + proof
Ruby proof:   57/57 PASS
Node.js DOM proof: 19/19 PASS
Total: **76/76 PASS**
P1 baseline digest: sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404 (unchanged)
All P1/P2/P3 regression gates: PASS

---

## [D] Decisions

**D1 — Items come from slot array, not inline DSL data.**
`collection :name, slot: :results, ...` — items injected by host via `updateSlots(...)`.
The view runtime never fetches, never executes contracts. Data/view separation preserved.

**D2 — Item fields become node_params directly.**
Each item in the slot array is a flat Hash. Its fields ARE the `node_params` context for
display rule evaluation. `node_params_schema` of `item_element` describes the expected shape.

**D3 — cloneNode over innerHTML for item creation.**
`cloneNode(true)` copies DOM without parsing HTML strings. No HTML injection risk.
`<template>` element hosts the bare clone source. Browser: `template.content.querySelector`.
Mock/fallback: `template.content = { querySelector: ... }` shim for Node.js proof.

**D4 — removeChild loop over innerHTML="" for clearing.**
`container.innerHTML = ""` is banned by safety policy. Iterates `existingItems.forEach(el => container.removeChild(el))`. Proved by IVC-P5-DOM-11 (mock DOM tracks removals).

**D5 — `_bindElementEvents` extracted helper.**
Before P5, event binding was inlined in `_bindEvents`. New helper `_bindElementEvents(el, elemDef)` called by `_bindEvents` (initial elements) AND `_renderCollection` (dynamic items). Backward compat preserved.

**D6 — Collection container is NOT a `data-ig-element`.**
`<ul data-ig-collection="...">` has no `data-ig-element` attr → `_render()` sweep ignores it.
Container classes are static (set at SSR time). Only item children get display rule patches.

**D7 — Empty `collections: {}` always in `to_h`.**
Host can detect collection-capable artifacts: `Object.keys(artifact.collections).length > 0`.
`collections` excluded from digest when empty → P1/P2/P3 digest backward compat maintained.

---

## [S] Shipped

### Modified files

| File | Change |
|---|---|
| `igniter-view-engine/lib/view_artifact.rb` | Added `collections:` param, `attr_reader :collections`, `normalize_collections`, `validate_collections!`, `collection(name)` lookup, digest conditional, `to_h` includes `"collections"` |
| `igniter-view-engine/lib/ssr_renderer.rb` | Added `render_collection(collection_name, ...)` method |
| `igniter-view-engine/lib/igv_compiler.rb` | Added `IgvCollectionBuilder` class; `collection` DSL keyword in `IgvViewBuilder`; `@collection_defs` field; `NON_CLAIMS_DEFAULT` updated with `no-stable-schema` |
| `igniter-view-engine/igniter_view_runtime.js` | Added `_renderCollection(collEl)`, `_bindElementEvents(el, elemDef)`, `updateSlots` collection rebuild trigger; updated header comment |

### New files

| File | Description |
|---|---|
| `igniter-view-engine/fixtures/results_panel.igv` | P5 collection fixture: search results panel (state, 3 slots, 1 collection, 5 elements) |
| `igniter-view-engine/run_ivf_proof_p5.rb` | Ruby proof runner: 57 checks |
| `igniter-view-engine/run_ivf_dom_proof_p5.js` | Node.js DOM proof: 19 checks with extended mock DOM (cloneNode, appendChild, removeChild, multi-attr querySelectorAll, template.content shim) |
| `lab-docs/lab-igniter-view-collection-rendering-schema-extension-v0.md` | Design doc |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P5.md` | This handoff |

### Generated outputs (`igniter-view-engine/out/`)

| File | Description |
|---|---|
| `results_panel_artifact.json` | Compiled ViewArtifact with collections schema extension |
| `results_panel_ssr.html` | SSR output: 4 items (ok/error/warning/ok status classes) |
| `ivf_p5_proof_summary.json` | Ruby proof results: 57/57 PASS |
| `ivf_p5_dom_proof.json` | Node.js DOM proof results: 19/19 PASS |

### Existing files untouched

- `igniter-lang/**` — not edited
- `tailmix/**` — not edited
- `igniter-view-engine/fixtures/tabs_artifact.rb` — not edited (P1 digest verified unchanged)
- `igniter-view-engine/run_ivf_proof.rb` — not edited
- `igniter-view-engine/run_ivf_proof_p2.rb` — not edited
- `igniter-view-engine/run_ivf_proof_p3.rb` — not edited
- `igniter-view-engine/run_ivf_dom_proof.js` — not edited

---

## [T] Proof Matrix

### P1/P2/P3 regression gates

| Gate | Status |
|---|---|
| P1 proof runner exits cleanly | ✅ |
| P1 tabs digest unchanged | ✅ `sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404` |
| P2 structural (18 checks) exits cleanly | ✅ |
| P3 .igv compiler (42 checks) exits cleanly | ✅ |

### IVC-P5 checks (57/57 Ruby)

| Check | Result | What it verifies |
|---|---|---|
| IVC-P5-1a | ✅ | P1 baseline exits cleanly |
| IVC-P5-1b | ✅ | P1 tabs digest unchanged (backward compat) |
| IVC-P5-2 | ✅ | P2 structural regression |
| IVC-P5-3 | ✅ | P3 compiler regression |
| IVC-P5-4a | ✅ | P4 EBNF grammar file present |
| IVC-P5-4b | ✅ | Grammar design doc has P5 collection recommendation |
| IVC-P5-5a | ✅ | `results_panel.igv` compiles without error |
| IVC-P5-5b | ✅ | Compiled artifact written to out/ |
| IVC-P5-5c | ✅ | Artifact has `results_list` collection |
| IVC-P5-5d (×5) | ✅ | Collection def: slot, item_element, item_key, container_tag, item_tag |
| IVC-P5-5e | ✅ | `result_item` element defined in artifact |
| IVC-P5-5f | ✅ | `result_item` has `:match` display rule |
| IVC-P5-5g | ✅ | `results` slot declared |
| IVC-P5-5h | ✅ | Artifact digest has `sha256:` prefix |
| IVC-P5-5i | ✅ | Collection artifact digest differs from P1 tabs |
| IVC-P5-5j | ✅ | `non_claims` includes `no-stable-schema` |
| IVC-P5-5k1 | ✅ | Undeclared slot → ArgumentError with clear message |
| IVC-P5-5k2 | ✅ | Undeclared item_element → ArgumentError with clear message |
| IVC-P5-5k3 | ✅ | Plain ViewArtifact: `collections: {}` in `to_h` |
| IVC-P5-5k4 | ✅ | Empty collections excluded from digest (backward compat) |
| IVC-P5-6a..k (×11) | ✅ | SSR: container attrs, template, 4 items, display rules, keys, sort btn, header, determinism, no innerHTML |
| IVC-P5-8a..d (×4) | ✅ | Opcode gate: banned opcode in item → compile_error; undeclared slot → validation_error |
| IVC-P5-9 (×12) | ✅ | Source guards: no innerHTML/eval/new Function/fetch/storage/dispatch/CustomEvent/contract |
| IVC-P5-10 (×5) | ✅ | Lab-only markers in all 5 modified files |
| IVC-P5-11 | ✅ | igniter-lang/** unchanged |

### P5-DOM checks (19/19 Node.js)

| Check | Result | What it verifies |
|---|---|---|
| P5-DOM-1 | ✅ | Runtime loads in collection-capable context |
| P5-DOM-2 | ✅ | `_renderCollection` on prototype |
| P5-DOM-3 | ✅ | `_bindElementEvents` on prototype |
| P5-DOM-4 | ✅ | `querySelectorAll("[data-ig-collection]")` works |
| P5-DOM-5 | ✅ | `cloneNode` creates independent element |
| P5-DOM-6a | ✅ | Initially 0 items (empty slot) |
| P5-DOM-6b | ✅ | 3 items created after slot update |
| P5-DOM-6c | ✅ | Items have correct `data-ig-item-key` values |
| P5-DOM-7a..c | ✅ | Display rules applied per item: ok/error/warning classes |
| P5-DOM-8 | ✅ | `updateSlots` replaces items on second call |
| P5-DOM-9 | ✅ | Non-collection slot update does not clear collection |
| P5-DOM-10 | ✅ | Empty array → 0 items |
| P5-DOM-11 | ✅ | `removeChild` called on old items before rebuild |
| P5-DOM-12 | ✅ | Undeclared slot key rejected by `filterSlotValues` |
| P5-DOM-13 | ✅ | No `innerHTML` assignment in runtime source |
| P5-DOM-14 | ✅ | No unexpected diagnostics from valid collection update |
| P5-DOM-15 | ✅ | P2 `updateSlots` API backward compat (string slot) |

---

## [R] Risks and Open Questions

**Risk 1 — No item shape validation (Q1 — inherited).**
`node_params_schema` declares expected item field types but the runtime does not validate
item objects against the schema. Wrong field names → silent null → falsy display rule branch.
Closing this requires contract schema introspection (P6+).

**Risk 2 — Single-level collections only.**
`item_element` cannot itself reference another collection. Multi-level nested lists are
not supported in this schema version.

**Risk 3 — Collection ordering is host-side.**
Items render in slot array order. UIState-driven sorting requires the host to pass a
pre-sorted array. A future `order_by:` expression on the collection def would enable
client-side sorting without roundtrip.

**Risk 4 — `<template>` polyfill needed for very old browsers.**
The `<template>` element is supported in all modern browsers (IE 11 excluded). The runtime
has a fallback that treats the template element directly (no `.content` indirection), but
IE 11 would render the template's inner HTML visibly. Lab scope: not a concern.

---

## P6 Recommendation

**Recommended: Slot-contract type linkage** — validate slot `from:` reference paths against
the Igniter contract's declared output types, and verify that `item_element.node_params_schema`
is compatible with the slot array item shape. Closes the most significant static type gap
(P4 Finding 4, P5 Q1).

**Alternative:** Grammar-based parser (Tier 1, Ruby PEG) for the now-stable DSL subset
(`view`, `state`, `slot`, `element`, `collection`). The grammar productions for all P1–P5
constructs are now confirmed by working implementation.

---

## Baseline Carried Forward

P1: 37/37 PASS
P2 structural: 18/18 PASS · P2 dynamic: 15/15 PASS
P3: 42/42 PASS
P4: IGV-G1..G9 all VERIFIED
P5: 57/57 Ruby · 19/19 Node.js DOM · 76/76 total
tabs.igv digest: sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404 (unchanged through P5)
igniter-lang/**: untouched throughout P1–P5
