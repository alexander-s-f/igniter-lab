# Igniter View — Collection Rendering Schema Extension

Status: `experimental · lab-only · no-canon · no-public-api · no-stable-schema · no-stable-syntax`
Track: `lab-igniter-view-collection-rendering-schema-extension-v0`
Card: `LAB-IGNITER-VIEW-FRAMEWORK-P5`
Date: 2026-06-06
Proof: 57/57 (Ruby) + 19/19 (Node.js DOM) = **76/76 PASS**

Depends on:
- LAB-IGNITER-VIEW-FRAMEWORK-P4 (EBNF grammar sketch, portability analysis)
- LAB-IGNITER-VIEW-FRAMEWORK-P3 (`.igv` DSL compiler, 42/42 PASS)
- LAB-IGNITER-VIEW-FRAMEWORK-P2 (slot injection API, 18+15 PASS)
- LAB-IGNITER-VIEW-FRAMEWORK-P1 (ViewArtifact, SSR, runtime baseline, 37/37 PASS)

---

## 1. Motivation

P1–P4 proved a view system for single elements — tabs, panels, static sections.
The P4 grammar sketch flagged collection rendering as the natural next step:
lists, grids, and tables require a *repeated* element with per-instance params.

P5 answers the question: **can the isomorphic ViewArtifact model extend to
collections without violating its own safety contracts?**

**Result: yes.** The extension fits cleanly into every layer:

| Layer | Change | Safety preserved |
|---|---|---|
| ViewArtifact JSON schema | `collections` key added | Banned opcode + slot mutation guards still run on all elements |
| `SSRRenderer` | `render_collection` method | No innerHTML — builds HTML server-side via Ruby string composition |
| `IgvCompiler` | `collection` DSL keyword | Two-fence opcode guard unchanged; slot ref validated at build |
| JS micro-runtime | `_renderCollection`, `cloneNode` path | No innerHTML — cloneNode only; removeChild loop; no eval |
| Digest algorithm | Collections excluded when empty | P1/P2/P3 artifact digests unchanged (backward compat) |

---

## 2. Schema Design

### 2.1 `collections` key in ViewArtifact JSON

```json
{
  "view_id": "igniter.lab.results_panel",
  "artifact_digest": "sha256:...",
  "ui_states": { "sort_by": { "type": "string", "default": "score" } },
  "slots": {
    "results": { "type": "array",  "contract_ref": "search.results", "mode": "read_only" },
    "query":   { "type": "string", "contract_ref": "search.query",   "mode": "read_only" }
  },
  "collections": {
    "results_list": {
      "slot":              "results",
      "item_element":      "result_item",
      "item_key":          "id",
      "container_classes": "results-list flex flex-col gap-2 mt-4",
      "container_tag":     "ul",
      "item_tag":          "li"
    }
  },
  "elements": [
    {
      "element_id":         "result_item",
      "static_classes":     "result-item p-3 rounded-lg border transition-colors list-none",
      "node_params_schema": { "id": "string", "title": "string", "status": "string", "score": "integer" },
      "display_rules": [
        ["match", ["param", "status"],
          { "ok":      { "c": "border-ok bg-ok-5 text-ink-1" },
            "warning": { "c": "border-warn bg-warn-5 text-ink-1" },
            "error":   { "c": "border-oof bg-oof-5 text-ink-1" } },
          { "c": "border-line bg-ink-2 text-grey" }]
      ],
      "interaction_rules": []
    }
  ],
  "safety_policy": { ... },
  "non_claims": ["lab-only", "experimental", "no-canon", "no-stable-schema"]
}
```

### 2.2 Collection definition fields

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `slot` | string | ✓ | — | Slot name providing the items array |
| `item_element` | string | ✓ | — | Element def name used as repeated template |
| `item_key` | string | ✓ | `"id"` | Field in each item used as stable unique key |
| `container_classes` | string | — | `""` | Static CSS for the container element |
| `container_tag` | string | — | `"ul"` | HTML tag for the outer container |
| `item_tag` | string | — | `"li"` | HTML tag for each repeated item |

### 2.3 Validation at build time (ViewArtifact)

1. `slot` must be declared in `slots` → ArgumentError with clear message if missing
2. `item_element` must reference a declared element in `elements` → ArgumentError
3. `item_key` must be non-empty → ArgumentError
4. All existing slot-mutation, banned-opcode, and UIState/slot-overlap guards run unchanged on every element in the artifact (including `item_element`)

### 2.4 Digest backward compatibility

The `collections` field is included in the SHA-256 digest input **only when non-empty**:

```ruby
canonical_data = { "view_id" => ..., "ui_states" => ..., "slots" => ..., "elements" => ... }
canonical_data["collections"] = @collections.sort.to_h unless @collections.empty?
```

This ensures all P1/P2/P3 artifacts retain their original digests. A view that gains a
collection always gets a different digest from the same view without one.

**Verified:** `tabs_view_artifact.json` digest remains
`sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404`
after the ViewArtifact schema extension (IVC-P5-1b, IVC-P5-5k4).

---

## 3. SSR Rendering Protocol

`SSRRenderer#render_collection(collection_name, items:, ...)` renders:

```html
<ul data-ig-collection="results_list"
    data-ig-collection-slot="results"
    data-ig-collection-element="result_item"
    data-ig-collection-key="id"
    class="results-list flex flex-col gap-2 mt-4">

  <!-- Template: bare item shell for JS runtime to clone. No params, no classes. -->
  <template data-ig-collection-template="results_list">
    <li data-ig-element="result_item"></li>
  </template>

  <!-- SSR-rendered items (one per entry in slot_values["results"]) -->
  <li data-ig-element="result_item"
      data-ig-param='{"id":"r1","title":"Database indexing","status":"ok","score":95}'
      data-ig-item-key="r1"
      class="result-item p-3 rounded-lg border transition-colors list-none border-ok bg-ok-5 text-ink-1">
  </li>

  <li data-ig-element="result_item"
      data-ig-param='{"id":"r2","title":"Memory leak detected","status":"error","score":12}'
      data-ig-item-key="r2"
      class="result-item p-3 rounded-lg border transition-colors list-none border-oof bg-oof-5 text-ink-1">
  </li>
  <!-- ... -->
</ul>
```

Key properties:
- No innerHTML — SSR builds HTML via Ruby string composition with `CGI.escapeHTML`
- Display rules evaluated server-side per item (same expression evaluator as P1)
- Template element carries no params and no classes — it is the clone source
- `data-ig-item-key` enables stable keying for the JS runtime

---

## 4. JS Runtime Protocol

### 4.1 Initial hydration

On page load, existing SSR-rendered items (`data-ig-element` inside the collection container)
are processed by the existing `_render()` call — no new code path required. They already
have the correct classes and params from SSR.

`_bindEvents()` binds interaction rules to all `data-ig-element` items including collection items.

### 4.2 `updateSlots` with a collection slot

When the host calls `component.updateSlots({ results: [...newArray...] })`:

1. Slot values filtered by `filterSlotValues` (P2 guard unchanged)
2. Changed slot keys collected: `changedKeys = Object.keys(result.filtered)`
3. Runtime finds all `[data-ig-collection]` elements inside the root
4. For each collection where `data-ig-collection-slot ∈ changedKeys`: `_renderCollection(collEl)`
5. `_render()` called to apply display rules on all elements (including newly created items)

### 4.3 `_renderCollection(collEl)` algorithm

```
1. Read slotName, elemName, keyField from collEl.dataset
2. Read items = this.slotValues[slotName] — must be Array
3. Find elemDef in this.elementIndex
4. Find <template data-ig-collection-template> inside collEl
5. Extract srcEl = template.content.querySelector("[data-ig-element]")
   (or template itself if .content unavailable — mock DOM fallback)
6. CLEAR: removeChild loop on [data-ig-element][data-ig-item-key] children
   (no innerHTML — iterates parentNode.removeChild(child) per item)
7. FOR EACH item in items array:
   a. Clone srcEl via cloneNode(true) — no HTML string
   b. Set itemEl.dataset.igElement = elemName
   c. Set itemEl.dataset.igParam   = JSON.stringify(itemParams)
   d. Set itemEl.dataset.igItemKey = String(item[keyField])
   e. Apply display rules: applyDisplayRules(elemDef.display_rules, scope)
   f. Patch element: patchElement(itemEl, staticClasses, computed)
   g. appendChild(itemEl) to collEl
   h. _bindElementEvents(itemEl, elemDef) — binds interaction rules
```

### 4.4 `_bindElementEvents` (extracted helper)

Before P5, event binding was inlined in `_bindEvents`. The new `_bindElementEvents(el, elemDef)`
helper binds one element's interaction rules and is called:
- From `_bindEvents` for all initial elements (backward compat)
- From `_renderCollection` for each newly created item

### 4.5 Safety guarantees preserved

| Guarantee | Mechanism |
|---|---|
| No innerHTML | cloneNode + patchElement + removeChild — no HTML strings |
| No eval | cloneNode is a DOM primitive — no code execution |
| Slot read-only | Collection items read slot arrays; `filterSlotValues` guard still runs |
| No slot mutation | Instruction executor's slot-mutation guard runs on all items |
| No contract execution | Runtime never calls any external system |
| P2 `filterSlotValues` guard | Runs at top of `updateSlots` before collection rebuild |

---

## 5. `.igv` DSL Extension

### 5.1 New DSL keyword: `collection`

```ruby
view "igniter.lab.results_panel" do
  slot :results, type: "array", from: "search.results"

  collection :results_list,
             slot:         :results,
             item_element: :result_item,
             item_key:     :id do
    container_classes "results-list flex flex-col gap-2 mt-4"
    container_tag "ul"
    item_tag "li"
  end

  element :result_item do
    classes "result-item p-3 rounded-lg border list-none"
    param :id,     type: "string"
    param :status, type: "string"
    display :match,
            subject: param(:status),
            cases: {
              "ok"    => { c: "border-ok bg-ok-5" },
              "error" => { c: "border-oof bg-oof-5" }
            },
            default: { c: "border-line" }
  end
end
```

### 5.2 `IgvCollectionBuilder` — block DSL context

Provides three setters: `container_classes(str)`, `container_tag(tag)`, `item_tag(tag)`.
No expression or instruction helpers (collections don't have their own display/interaction
rules — those belong to the `item_element`'s element def).

### 5.3 Compiler validation

- `slot:` must be non-empty → `IgvCompileError` at DSL level
- `item_element:` must be non-empty → `IgvCompileError` at DSL level
- `slot` declared in view's `slots` → `ArgumentError` at ViewArtifact level (hard error)
- `item_element` declared in view's `elements` → `ArgumentError` at ViewArtifact level
- If item_element's interaction rules contain a banned opcode → caught by existing two-fence guard

### 5.4 Grammar sketch update (P4 candidate, now validated)

The P4 grammar's candidate productions for collections are confirmed:

```ebnf
(* Candidate additions from P4, validated by P5 implementation *)
view_stmt    += collection_def ;

collection_def    = 'collection' , symbol , ','
                  , 'slot:'         , symbol , ','
                  , 'item_element:' , symbol , ','
                  , [ 'item_key:'   , symbol , ',' ]
                  , [ 'do' , collection_body , 'end' ] ;

collection_body   = { container_classes_stmt
                    | container_tag_stmt
                    | item_tag_stmt } ;

container_classes_stmt = 'container_classes' , quoted_string ;
container_tag_stmt     = 'container_tag' , quoted_string ;
item_tag_stmt          = 'item_tag' , quoted_string ;
```

These match the `IgvCollectionBuilder` implementation exactly.

---

## 6. Design Decisions

### D1 — Items come from a slot, not inline DSL data

The collection's items are injected by the host via `updateSlots(...)` — not declared
in the `.igv` file. This preserves the fundamental contract:
- `.igv` = structure and behavior declaration
- Slot = runtime data from contract execution
- The view runtime never fetches, never executes contracts

An alternative (`items: [...]` hardcoded in `.igv`) would violate the data/view separation.

### D2 — Item params derive from slot array items (flat field map)

Each item in the slot array is expected to be a Hash/object. The item's fields become
the `node_params` context for display rule evaluation. No transformation layer between
slot item and params — the fields ARE the params.

This means `node_params_schema` of `item_element` effectively declares the expected
item object shape. Type mismatch is currently warning-only (P2 param validation stance).

### D3 — cloneNode over innerHTML for item creation

JavaScript `cloneNode(true)` creates a DOM copy without parsing HTML strings.
It is:
- Safe: no HTML injection risk
- Fast: in-memory deep copy with no parser overhead
- Consistent: same DOM object as the SSR-rendered template shell

The `<template>` element is used as the clone source. In browsers, `template.content`
is an inert `DocumentFragment` — its children are never rendered or executed.
In the lab's Node.js mock, a `content` shim with `querySelector` is provided.

### D4 — removeChild loop over `container.innerHTML = ""`

The `innerHTML = ""` shortcut clears a container's children but is banned by the
P1 safety policy (`dom_patch_scope: "class|aria|data only"` and innerHTML guard).

The alternative: iterate existing item children and call `parentNode.removeChild(child)`.
This is pure DOM manipulation, not HTML string injection. Proved by IVC-P5-DOM-11
(removeChild call verified in mock DOM).

### D5 — Event binding extracted to `_bindElementEvents`

Before P5, event binding iterated all `[data-ig-element]` roots once at construction.
Collection items created dynamically after construction would have no event handlers.

`_bindElementEvents(el, elemDef)` is the extracted single-element helper.
`_bindEvents` still works for initial elements (backward compat unchanged).
`_renderCollection` calls `_bindElementEvents` per new item.

### D6 — Collection container is NOT a `data-ig-element` itself

The `<ul data-ig-collection="...">` container has collection hydration attrs but NOT
`data-ig-element`. This means `_render()`'s `querySelectorAll("[data-ig-element]")` sweep
does not process the container — only its item children. The container's `class` is
static (set at SSR time from `container_classes`); the runtime does not patch it.

### D7 — Empty `collections: {}` in `to_h` is always present

Even for views without collections, `to_h` returns `"collections": {}`. This lets host
code detect whether a given artifact schema version supports collections without
checking for key existence. Detection: `Object.keys(artifact.collections).length > 0`.

---

## 7. Proof Summary

### IVC-P5-1: P1 baseline

✅ P1 proof runner exits cleanly
✅ Tabs artifact digest `sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404` unchanged

### IVC-P5-2/3: Regression

✅ P2 structural proof (18 checks) exits cleanly
✅ P3 `.igv` compiler proof (42 checks) exits cleanly

### IVC-P5-4: Grammar doc

✅ P4 EBNF grammar present; design doc references P5 collection extension

### IVC-P5-5: Compilation

✅ 5a: `results_panel.igv` compiles successfully
✅ 5b–j: Artifact structure, collection def, digest, non_claims verified
✅ 5k1–k4: ViewArtifact validation guards for undeclared slot, undeclared element, backward compat

### IVC-P5-6: SSR rendering (11 checks)

✅ Container attrs, template element, item count (4/4), per-item display rules, item keys,
sort btn active class, results_header visibility, determinism, no innerHTML in output

### IVC-P5-7: JS runtime (19 Node.js DOM checks)

✅ Runtime loads; `_renderCollection`/`_bindElementEvents` exist; querySelectorAll works;
cloneNode independence; 3 items created; display rules per item (ok/error/warning classes);
updateSlots rebuilds; non-collection update doesn't rebuild; empty items clears; removeChild
called; undeclared slot rejected; no innerHTML in source; no spurious diagnostics; P2 backward compat

### IVC-P5-8: Opcode gate

✅ Collection with banned opcode in item → compile_error + no artifact
✅ Collection with undeclared slot → validation_error

### IVC-P5-9: No banned constructs

✅ No innerHTML, eval, new Function, fetch, localStorage, sessionStorage, dispatchEvent,
CustomEvent, contract execution; cloneNode/appendChild/removeChild confirmed present

### IVC-P5-10: Lab-only markers

✅ All five layer files carry lab-only/no-stable-schema markers

### IVC-P5-11: Canon boundary

✅ igniter-lang/** unchanged

**Total: 76/76 PASS**

---

## 8. Generated Artifacts

| File | Description |
|---|---|
| `out/results_panel_artifact.json` | ViewArtifact compiled from `fixtures/results_panel.igv` |
| `out/results_panel_ssr.html` | SSR output with 4 items (ok/error/warning/ok) |
| `out/ivf_p5_proof_summary.json` | Ruby proof: 57/57 PASS |
| `out/ivf_p5_dom_proof.json` | Node.js DOM proof: 19/19 PASS |

---

## 9. Open Questions / Future Work

### Q1 — Slot-contract type linkage (inherited from P4 Finding 4)

The `slot: :results` declaration requires `type: "array"` but the schema does not validate
the *shape* of each array item against the element's `node_params_schema`. A runtime
with valid slot data but wrong item field names will produce silent display rule failures
(null → falsy branch). No error, no diagnostic.

Resolution path: contract schema introspection at compile time (slot type linkage, P6+).

### Q2 — Collection ordering / sorting

The current collection renders items in the order provided by the slot array. Sorting is
the host's responsibility — the host passes a sorted array. If sorting were a view concern
(triggered by UIState), the runtime would need to re-sort in memory and call `_renderCollection`.
This is possible without new artifact fields but would require a `sort_by` expression
on the collection def. Not prototyped in P5.

### Q3 — Collection with UIState-driven visibility (empty state)

The `empty_notice` element in `results_panel.igv` is static — it has no reference to the
results slot. The host must control its visibility by some other means (separate element with
a slot ref, or an element inside the collection container that SSR renders only when empty).
A future `display_when_empty:` option on the collection def would clean this up.

### Q4 — Nested collections

A collection item element cannot itself reference another collection. The artifact model
supports only one level of collection nesting. Multi-level would require recursive
`_renderCollection` calls and deeper artifact schema changes.

### Q5 — P5 grammar productions verified

P4's candidate grammar for `collection_def` (now confirmed):
```ebnf
view_stmt    += collection_def ;
collection_def    = 'collection' , symbol , ',' , 'slot:' , symbol , ','
                  , 'item_element:' , symbol
                  , [ ',' , 'item_key:' , symbol ]
                  , [ 'do' , collection_body , 'end' ] ;
```

This should be added to `igv-grammar-sketch-v0.ebnf` as a P5-validated extension.

---

## 10. Recommendation for P6

Options:
1. **Slot-contract type linkage** — validate slot `from:` paths against contract output types (closes P4 Q4 / P5 Q1)
2. **Grammar-based parser** — Tier 1 Ruby PEG parser for the now-stable DSL subset (view, state, slot, element, collection)
3. **Collection ordering** — `order_by:` expression on collection def for UIState-driven sorting
4. **Hold** — consolidate P1–P5 findings into a formal lab report

**Recommended: Option 1 — Slot-contract type linkage** if the Igniter contract type
system has an introspection API available. Option 2 otherwise — the grammar subset is
now stable enough to warrant a real parser.

---

## 11. What This Is Not (Non-Claims)

| Claim | Status |
|---|---|
| Stable schema for `collections` | **No** — lab-only, subject to change |
| Canonical collection syntax | **No** — `.igv` remains no-canon |
| Production framework | **No** |
| Certified by Igniter-Lang governance | **No** — lab track only |
| Complete collection feature set | **No** — Q1–Q5 above are open |
