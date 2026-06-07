# Igniter Isomorphic View Artifact — MVP Boundary

Status: `experimental · lab-only · no-canon · no-public-api · no-stable-syntax`
Track: `lab-igniter-isomorphic-view-artifact-mvp-boundary-v0`
Card: LAB-IGNITER-VIEW-FRAMEWORK-P1
Date: 2026-06-06
Proof: 37/37 IVF-P1 checks — ALL PASS
Artifact digest: `sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404`

Based on:
- `lab-tailmix-concept-applicability-to-igniter-gui-v0-A.md` (LAB-TAILMIX-P1-A)
- `lab-tailmix-inspired-gui-interaction-ir-schema-v0.md` (LAB-TAILMIX-P2)
- `lab-igniter-lang-to-gui-research-boundary-v0.md`
- `lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0.md`
- Agent-A concept packet (Igniter isomorphic view framework design)

---

## 1. What Was Built

A minimal, self-contained isomorphic view layer for Igniter Lab consisting of:

| Artifact | Path | Role |
|---|---|---|
| `ViewArtifact` Ruby class | `igniter-view-engine/lib/view_artifact.rb` | Content-addressed component definition |
| `SSRRenderer` Ruby class | `igniter-view-engine/lib/ssr_renderer.rb` | Server-side HTML emission with hydration attrs |
| `igniter_view_runtime.js` | `igniter-view-engine/igniter_view_runtime.js` | Vanilla JS micro-runtime for client hydration |
| `tabs_artifact.rb` fixture | `igniter-view-engine/fixtures/tabs_artifact.rb` | Minimal proof specimen (tabs + slot + param) |
| `run_ivf_proof.rb` | `igniter-view-engine/run_ivf_proof.rb` | 37-check proof runner |
| `out/tabs_view_artifact.json` | generated | Machine-readable ViewArtifact export |
| `out/tabs_ssr_output.html` | generated | Full SSR specimen with inlined artifact |

No React, Svelte, Vue, HTMX, Tailmix, or Alpine dependency anywhere in the chain.

---

## 2. The Isomorphism Model

```
ViewArtifact JSON
      │
      ├─── Ruby SSRRenderer ──→ static HTML  (initial render, correct classes without JS)
      │         └── embeds data-ig-* attrs   (UIState seed, slot values, element markers)
      │         └── inlines artifact JSON    (<script type="application/json">)
      │
      └─── JS IgniterComponent ──→ hydration (reads same artifact from script tag)
                └── bindEvents()            (attaches click/input listeners)
                └── _render()               (evaluates display_rules → patches class/aria)
                └── _update(patch)          (UIState mutation → re-render)
```

The `ViewArtifact` is the only source of truth. Both consumers read it verbatim.
No rendering logic is duplicated between Ruby and JS — both implement the same
expression evaluator over the same rule array format.

---

## 3. ViewArtifact Schema (IVF-P1-1)

```json
{
  "view_id":         "igniter.lab.tabs_panel",
  "artifact_digest": "sha256:ed8ab03d...",

  "ui_states": {
    "active_tab": { "type": "string", "default": "overview" }
  },

  "slots": {
    "has_warnings": {
      "type": "boolean",
      "contract_ref": "diagnostics.has_warnings",
      "mode": "read_only"
    }
  },

  "elements": [
    {
      "element_id":         "tab_btn",
      "static_classes":     "tab-btn px-4 py-2 text-xs font-mono rounded-t transition-colors",
      "node_params_schema": { "id": "string" },
      "display_rules": [
        ["style",
          ["eq", ["ui_state", "active_tab"], ["param", "id"]],
          { "c": "bg-ignite text-ink-1 font-bold", "a": { "selected": "true" } },
          { "c": "text-grey hover:text-grey-2",    "a": { "selected": "false" } }]
      ],
      "interaction_rules": [
        ["on", "click", [["set_ui_state", "active_tab", ["param", "id"]]]]
      ]
    }
  ],

  "safety_policy": {
    "banned_opcodes":            ["fetch", "dispatch", "boot", "watch", "persistence", "eval", "innerHTML"],
    "allowed_opcodes":           ["set_ui_state", "toggle_ui_state", "clear_ui_state"],
    "slot_mode":                 "read_only",
    "interaction_target_domain": "ui_state_only",
    "dom_patch_scope":           "class|aria|data only"
  },

  "non_claims": ["lab-only", "experimental", "no-canon", "no-public-api", ...]
}
```

### Schema invariants enforced at `ViewArtifact.new` (build time):

| Invariant | Error raised |
|---|---|
| UIState and slot keys overlap | `ArgumentError: share keys` |
| Interaction rule targets a slot key | `ArgumentError: read-only slot` |
| Interaction rule uses banned opcode | `ArgumentError: banned opcode` |
| Interaction rule uses unknown opcode | `ArgumentError: unknown opcode` |

All enforcement happens at definition time — not at render time, not at runtime.

---

## 4. UIState vs SlotValue Separation (IVF-P1-2)

The foundational decision from LAB-TAILMIX-P1-A (Decision D1) is enforced
structurally in the schema and at three levels:

| Level | Mechanism |
|---|---|
| Schema | Separate `ui_states` and `slots` keys with no overlap |
| Build time | `ViewArtifact` raises `ArgumentError` on overlap or slot mutation |
| JS runtime | `executeInstructions` checks `hasOwnProperty.call(scope.uiState, target)` — slots are not in `uiState`, so any attempt to set them fails closed |
| SSR renderer | Slot values are passed as a separate read-only parameter; renderer does not merge them into UIState |

---

## 5. SSR Renderer — What It Does (IVF-P1-3)

`SSRRenderer` consumes a `ViewArtifact` and produces static HTML that is:

1. **Correct without JavaScript** — `display_rules` are evaluated Ruby-side with the
   initial UIState + injected SlotValues. The active tab gets its highlight classes;
   the warning banner shows/hides; all in the first HTTP response.

2. **Hydration-ready** — every element carries the attributes the JS runtime needs:
   - `data-ig-component` — component root marker + view_id
   - `data-ig-state` — JSON-encoded initial UIState (seed for JS component)
   - `data-ig-slots` — JSON-encoded slot values (read-only in JS)
   - `data-ig-artifact-digest` — artifact version for integrity check
   - `data-ig-element` — element name, matches artifact element index
   - `data-ig-param` — per-instance node params (e.g. `{"id":"overview"}`)

3. **Inlines the artifact** — `artifact_script_tag` emits:
   ```html
   <script type="application/json" id="ig-artifact-igniter-lab-tabs_panel">
     { ... full artifact JSON ... }
   </script>
   ```
   The JS runtime reads this from the DOM. No network fetch needed.

4. **No framework, no IO, no contract execution** — pure Ruby, stdlib only.

---

## 6. JS Micro-Runtime — What It Does (IVF-P1-4, IVF-P1-5)

`igniter_view_runtime.js` — pure IIFE, no module system, no dependencies.

### Lifecycle

```
DOMContentLoaded
  → hydrate()
      → querySelectorAll("[data-ig-component]")
      → for each root:
          → read artifact from <script type="application/json" id="ig-artifact-*">
          → new IgniterComponent(root, artifact)
              → uiState  ← JSON.parse(root.dataset.igState)
              → slotValues ← JSON.parse(root.dataset.igSlots)
              → _bindEvents() — attach listeners per interaction_rules
              → _render()    — evaluate display_rules → patchElement()
```

### On user event (e.g. tab click)

```
click → executeInstructions(instructions, scope, onUpdate)
  → whitelist check (set_ui_state only)
  → UIState domain check (target must be in uiState)
  → evaluate(valueExpr, scope) — pure, no side effects
  → onUpdate(patch)
      → Object.assign(this.uiState, patch)
      → _render() — re-evaluate display_rules for all elements
```

### DOM patching scope (IVF-P1-5)

```javascript
el.className = "...";              // class rebuild from static + computed
el.setAttribute("aria-selected", "true");   // aria attributes
el.setAttribute("data-custom", "val");      // data attributes
// Nothing else. No innerHTML. No textContent. No style.cssText.
```

### Forbidden APIs — absent from runtime (IVF-P1-7)

| API | Status | Reason |
|---|---|---|
| `innerHTML =` | **absent** | DOM write; XSS vector |
| `eval()` | **absent** | Arbitrary code execution |
| `fetch()` | **absent** | Unmediated I/O; violates Postulate 4 |
| `localStorage.*` | **absent** | Client persistence out of scope |
| `new CustomEvent()` | **absent** | Cross-component coupling; unauditable |
| `.dispatchEvent()` | **absent** | Same |
| `import` / `require` | **absent** | Pure IIFE; no module system |

---

## 7. Fixture Proof Specimen (IVF-P1-11)

The `tabs_artifact` fixture demonstrates the full pipeline with minimal surface:

| Requirement | Present |
|---|---|
| One UIState (`active_tab: string`) | ✓ |
| One SlotValue (`has_warnings: boolean` from `diagnostics.has_warnings`) | ✓ |
| One node param (`id: string` on tab_btn element) | ✓ |
| One display rule (`style` with `eq` condition) | ✓ per element |
| One interaction rule (`on click → set_ui_state`) | ✓ on tab_btn |
| SSR applies display rule server-side | ✓ active tab gets ignite classes |
| JS runtime would find all `[data-ig-element]` hooks | ✓ |
| Artifact inlined as `<script type="application/json">` | ✓ |

---

## 8. Security Boundary Proof (IVF-P1-6, IVF-P1-7)

Three layers of security:

**Layer 1 — Build time (Ruby `ViewArtifact.new`):**
- Slot mutation in interaction_rules → `ArgumentError` (test: IVF-P1-6a)
- Banned opcode → `ArgumentError` (test: IVF-P1-7f source check)

**Layer 2 — SSR (Ruby `SSRRenderer`):**
- No dynamic code evaluation
- Slot values are separate from UIState; SSR renderer cannot confuse them
- No network IO; no contract execution

**Layer 3 — JS runtime (`IgniterComponent`):**
- `executeInstructions`: banned opcode → `console.error` + `return` (fail closed)
- `executeInstructions`: target not in `uiState` → `console.error` + `return` (fail closed)
- `evaluate()`: unknown op → `console.warn` + return `null`
- `applyDisplayRules()`: unknown rule kind → `console.warn` + skip

---

## 9. Digest / Versioning (IVF-P1-10)

The artifact digest is a SHA-256 of the canonical serialization:

```
sha256(JSON.generate({
  view_id:   "igniter.lab.tabs_panel",
  ui_states: sorted_hash,
  slots:     sorted_hash,
  elements:  [element.to_h.sort.to_h, ...]
}))
```

Properties:
- Same definition → same digest (deterministic: verified by IVF-P1-3i)
- Any change to ui_states, slots, or elements → different digest (verified by IVF-P1-10b)
- Digest embedded in SSR HTML as `data-ig-artifact-digest` → JS runtime can warn on mismatch
- Artifact inlined as `<script>` with matching content

---

## 10. What This Is Not (Non-Claims)

| Claim | Status |
|---|---|
| Canonical Igniter language feature | **No** — lab prototype only |
| Stable public API | **No** — everything may change |
| Production-ready frontend framework | **No** |
| Reference runtime implementation | **No** |
| Portable to other runtimes | **No guarantee** |
| Igniter Ruby framework integration | **No** — Igniter-Lang track only |
| React / Svelte replacement | **No** — IDE developer tooling scope |

---

## 11. Next Slice Recommendations

### Option A — IVF-P2: Live Slot Injection Proof
Demonstrate SSR-rendered component where SlotValues are updated by the host page
(e.g. contract execution result returned to the page → JSON injected into
`data-ig-slots` → JS runtime re-evaluates display rules). No websocket, no fetch in
view runtime — slot update is host responsibility.

### Option B — IVF-P2: Collection Rendering Proof
Extend ViewArtifact with `collections` concept: a named list of element instances
each carrying their own `node_params`. SSR renders all items; JS runtime re-renders
on UIState change (e.g. active item). Tests the `match` display rule with `param`.

### Option C — IVF-P2: `.igv` View DSL Parser Sketch
Sketch a minimal `.igv` source syntax that compiles to a ViewArtifact JSON.
Not canonical — design candidate only. Tests whether the artifact format is
ergonomic as a compilation target before committing to DSL design decisions.

**Recommended: Option A** — slot injection is the missing link between the contract
execution pipeline and the view layer. It validates the isomorphism claim end-to-end.
