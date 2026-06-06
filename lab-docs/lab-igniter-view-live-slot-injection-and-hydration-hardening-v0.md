# Igniter View — Live Slot Injection & Hydration Hardening

Status: `experimental · lab-only · no-canon · no-public-api · no-stable-syntax`
Track: `lab-igniter-isomorphic-view-artifact-mvp-boundary-v0`
Card: `LAB-IGNITER-VIEW-FRAMEWORK-P2`
Date: 2026-06-06
Proof: 18/18 IVF-P2 structural checks + 15/15 Node.js DOM proof + 37/37 P1 baseline — **ALL PASS**
Artifact digest: `sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404`

Builds on: `lab-igniter-isomorphic-view-artifact-mvp-boundary-v0.md` (LAB-IGNITER-VIEW-FRAMEWORK-P1)

---

## 1. What Was Added in P2

P2 closes the loop between contract execution and the view layer — without violating any P1
safety contract. Three capabilities were added to `igniter_view_runtime.js`:

| Capability | Mechanism | Proof check |
|---|---|---|
| Live slot injection | `component.updateSlots(newValues)` | IVF-P2-DOM-8, IVF-P2-B-11 |
| Slot key filtering (incoming) | `filterSlotValues(incoming, declaredSlots)` | IVF-P2-DOM-1..3 |
| Slot key filtering (hydration) | `filterSlotValues` called in constructor | IVF-P2-DOM-7, IVF-P2-10 |
| Node param validation | `validateNodeParams(params, schema)` in `_render()` | IVF-P2-DOM-4..5, IVF-P2-7 |
| Malformed param safety | `try/catch` → `{}` fallback + diagnostic | IVF-P2-8 |
| Digest mismatch stance | Warning-only; component always hydrated | IVF-P2-9 |
| Diagnostics log | `component.diagnostics[]` array | IVF-P2-4, IVF-P2-DOM-12 |
| Component registry | `IgniterView.components` keyed by view_id | hydrate() change |

All P1 safety contracts are fully preserved (37/37 P1 checks still pass).

---

## 2. Live Slot Injection Protocol

### Host-page responsibility

The view runtime **never** fetches data. Slot values come from outside — typically from the
host page receiving a contract execution receipt (via whatever transport the host uses: fetch,
server-push, etc.). Once the host has new slot values, it calls:

```javascript
// Host page, after receiving contract results:
const component = IgniterView.components["igniter.lab.tabs_panel"];
component.updateSlots({ has_warnings: true });
```

That is the only API the host needs. The view runtime does the rest.

### What updateSlots does (internal)

```
component.updateSlots(newSlotValues)
  │
  ├─ 1. Type guard: reject non-objects silently (console.warn, return)
  │
  ├─ 2. filterSlotValues(newSlotValues, artifact.slots)
  │       ├─ declared keys  → filtered.has_warnings = true  ← passes through
  │       └─ undeclared keys → rejected, diagnostic pushed to component.diagnostics
  │
  ├─ 3. Object.assign(this.slotValues, filtered)
  │       └─ slotValues now has updated declared values only
  │
  ├─ 4. this.root.dataset.igSlots = JSON.stringify(this.slotValues)
  │       └─ persisted for dev-tool / rehydration visibility
  │
  └─ 5. this._render()
          └─ all display_rules re-evaluated with updated scope.slotValues
              └─ patchElement: className, aria-*, data-* attributes updated
```

The display_rules evaluator reads `scope.slotValues` — the same object that `updateSlots`
mutated. No new code path needed for the evaluator. Isomorphism preserved.

---

## 3. Slot Key Filtering

### Two checkpoints

| Checkpoint | Location | Trigger |
|---|---|---|
| Hydration guard | `IgniterComponent` constructor | SSR-seeded `data-ig-slots` parsed |
| Update guard | `updateSlots()` | Host calls `updateSlots(newValues)` |

Both checkpoints use the same `filterSlotValues(incoming, declaredSlots)` function.

### filterSlotValues semantics

```javascript
// Declared slots: artifact.slots = { "has_warnings": { type: "boolean", ... } }
// Incoming:       { "has_warnings": false, "injected_evil": "xss" }
// Result:
//   filtered:     { "has_warnings": false }     ← only declared keys
//   diagnostics:  [{ type: "slot_key_rejected", key: "injected_evil", ... }]
```

Filtering is **fail-safe** for declared keys (they always pass through) and **fail-closed**
for undeclared keys (they are silently dropped with a diagnostic).

### Why not fail-closed on the whole update?

Failing closed on a single undeclared key would be too strict — it would break valid updates
that mix new declared keys with accidentally-included unknown keys. The per-key approach is
more useful in practice: known keys take effect, unknown keys are flagged for the developer.

---

## 4. Node Param Validation

`_render()` now validates `data-ig-param` JSON keys against `elemDef.node_params_schema`.

```javascript
// Example: node_params_schema = { "id": "string" }
// data-ig-param = '{"id":"overview","typo_key":"abc"}'
//
// Result:
//   nodeParams used = { "id": "overview", "typo_key": "abc" }
//   diagnostics: [{ type: "param_key_unknown", key: "typo_key", ... }]
//   DOM patching proceeds normally — "typo_key" is harmlessly ignored by rules
```

**Decision: warning-only for param validation.**
Unknown param keys are not removed from `nodeParams` before rule evaluation — they are just
flagged. Display rules reference only params via `["param", "key"]` expressions, so an unknown
key is silently unused. Removing it would not improve safety; warning serves the developer
without disrupting rendering.

**Malformed `data-ig-param` (invalid JSON):** fails to `{}` (empty params) + diagnostic.
The element renders with `nodeParams = {}`. If the display rule depends on a missing param
(e.g. `["param", "id"]` → undefined), the `eq` condition evaluates to false. The "inactive"
branch of the display rule fires. No exception, no blank screen.

---

## 5. Digest Mismatch Stance

**Decision: warning-only.**

```
DOM data-ig-artifact-digest ≠ artifact.artifact_digest
  → console.warn (logged)
  → component.diagnostics.push({ type: "digest_mismatch", ... })
  → component is ALWAYS constructed and hydrated
  → no throw, no return, no blank component
```

**Rationale:** The artifact content is the source of truth. The digest is an integrity
signal, not a security gate. A mismatch can occur due to:
- Cache-busted artifact re-generation (common in dev)
- Hot-reload during development
- Deploy where CDN serves old HTML but new artifact JSON

In all these cases, failing closed would break the component unnecessarily. The right
response is: log it, flag it for the developer, continue. The host can inspect
`component.diagnostics` and take action if needed.

**Stricter policy path:** If a production context requires fail-closed on digest mismatch,
the host can check `component.diagnostics` after `hydrate()` completes:

```javascript
// Host-side (after hydrate):
const component = IgniterView.components["my.view"];
const mismatch = component.diagnostics.find(d => d.type === "digest_mismatch");
if (mismatch) { component.root.hidden = true; showError(); }
```

The view runtime provides the signal; the policy belongs to the host.

---

## 6. Diagnostics Log

`component.diagnostics` is a plain array of `{type, ...}` objects, accumulated from:

| Event | type | When |
|---|---|---|
| Undeclared slot key at hydration | `slot_key_rejected` | Constructor, `filterSlotValues` |
| Undeclared slot key via updateSlots | `slot_key_rejected` | `updateSlots()`, `filterSlotValues` |
| Malformed `data-ig-slots` | `malformed_slots` | Constructor, JSON.parse fail |
| Malformed `data-ig-param` | `malformed_param` | `_render()`, JSON.parse fail |
| Unknown node param key | `param_key_unknown` | `_render()`, `validateNodeParams` |
| Artifact digest mismatch | `digest_mismatch` | `hydrate()`, after component construction |

The array is accessible to the host page and dev tools. It is append-only (never cleared
by the runtime). Host pages may inspect it at any time.

---

## 7. Proof Evidence

### P1 baseline (regression gate)

37/37 checks — ALL PASS. See `out/ivf_proof_summary.json`.

### P2 structural checks (Ruby source analysis)

18/18 checks — ALL PASS. See `out/ivf_p2_proof_summary.json`.

| Check | What it verifies |
|---|---|
| IVF-P2-1 | `updateSlots` prototype method present in JS source |
| IVF-P2-2 | `filterSlotValues` function present |
| IVF-P2-3 | `validateNodeParams` function present |
| IVF-P2-4 | `this.diagnostics = []` in constructor |
| IVF-P2-5 | `updateSlots` writes `dataset.igSlots` |
| IVF-P2-6 | `updateSlots` calls `this._render()` |
| IVF-P2-7 | `_render()` calls `validateNodeParams` |
| IVF-P2-8 | Malformed param → `malformed_param` + empty params |
| IVF-P2-9 | Digest mismatch is `warning-only`, component always constructed |
| IVF-P2-10 | `filterSlotValues` called in constructor on raw slots |
| IVF-P2-11 | P2 helpers exposed in public `IgniterView` surface |
| IVF-P2-12a..d | P1 safety preserved: no innerHTML, no eval, no fetch, UIState guard intact |
| IVF-P2-13 | SSR renderer has no contract execution |
| IVF-P2-14 | P1 proof runner: 37/37 still pass |
| IVF-P2-15 | Node.js DOM proof: 15/15 pass |

### P2 dynamic checks (Node.js DOM proof — no browser required)

15/15 checks — ALL PASS. See `out/ivf_p2_dom_proof.json`.

| Check | What it verifies dynamically |
|---|---|
| IVF-P2-DOM-1 | `filterSlotValues`: declared key passes |
| IVF-P2-DOM-2 | `filterSlotValues`: undeclared key dropped from `filtered` |
| IVF-P2-DOM-3 | `filterSlotValues`: diagnostics[] populated for rejected keys |
| IVF-P2-DOM-4 | `validateNodeParams`: unknown key produces `param_key_unknown` diagnostic |
| IVF-P2-DOM-5 | `validateNodeParams`: all-declared params → empty diagnostics |
| IVF-P2-DOM-6 | Empty declared schema → all incoming keys rejected |
| IVF-P2-DOM-7 | Constructor: undeclared slot from `data-ig-slots` filtered at hydration |
| IVF-P2-DOM-8 | `updateSlots(valid)`: slotValues updated, display rules re-evaluated |
| IVF-P2-DOM-9 | `updateSlots(undeclared)`: key rejected, diagnostic appended |
| IVF-P2-DOM-10 | `updateSlots`: result persisted to `dataset.igSlots` |
| IVF-P2-DOM-11 | Slot key via `interaction_rules` → still blocked (P1 fence intact) |
| IVF-P2-DOM-12 | `component.diagnostics` is an Array |
| IVF-P2-DOM-13 | `updateSlots(null/42/string)` → no throw |
| IVF-P2-DOM-14 | UIState interaction still works after slot update |
| IVF-P2-DOM-15 | `filterSlotValues` + `validateNodeParams` in `IgniterView` public surface |

### Browser proof

`ivf_p2_browser_proof.html` — 20 browser-executed assertions demonstrating live interaction.
Open in any browser. The proof covers: live slot injection, display rule re-evaluation,
diagnostic log, slot mutation block, no forbidden APIs.

---

## 8. Host Integration Pattern

```javascript
// ── Complete host-page integration sketch ──────────────────────────────────
//
// 1. SSR: Ruby renders HTML with artifact inlined + initial slot values
//    (host already does this in P1)
//
// 2. After page load, IgniterView.hydrate() runs automatically:
//    - reads artifact from <script type="application/json">
//    - seeds UIState from data-ig-state
//    - seeds SlotValues from data-ig-slots (filtered against artifact.slots)
//    - binds events, renders display_rules
//
// 3. Host executes a contract (via whatever transport):
//    const receipt = await myHostClient.runContract("diagnostics", inputs);
//
// 4. Host extracts slot values from receipt:
//    const slotValues = {
//      has_warnings: receipt.outputs.has_warnings   // from Igniter contract output
//    };
//
// 5. Host calls updateSlots — view re-renders:
//    IgniterView.components["igniter.lab.tabs_panel"].updateSlots(slotValues);
//
// 6. Optionally inspect diagnostics:
//    console.log(component.diagnostics);
//
// The view runtime does nothing between steps 4 and 5 — it waits passively
// for the host to push new slot values. No polling, no subscription, no fetch.
```

The key insight: **contract execution is the host's responsibility, not the view runtime's.**
The runtime only knows how to: receive filtered slots, re-evaluate pure display rules,
patch DOM attributes. This keeps the runtime minimal and the security boundary clean.

---

## 9. Safety Contracts — Unchanged from P1

All P1 safety contracts remain in force:

| Contract | Status in P2 |
|---|---|
| No `.innerHTML =` | ✓ Preserved |
| No `eval()` | ✓ Preserved |
| No `fetch()` | ✓ Preserved |
| No `localStorage.*` | ✓ Preserved |
| No `CustomEvent` / `dispatchEvent` | ✓ Preserved |
| No contract execution | ✓ Preserved |
| Banned opcodes fail closed | ✓ Preserved |
| Slot mutation via interaction_rules blocked | ✓ Preserved (IVF-P2-DOM-11) |
| Unknown opcodes fail closed | ✓ Preserved |
| UIState domain guard (hasOwnProperty) | ✓ Preserved |

P2 adds **no new security attack surface**. The only new external API is `updateSlots()`,
which filters its inputs before use.

---

## 10. What This Is Not (Non-Claims)

| Claim | Status |
|---|---|
| Canonical Igniter language feature | **No** — lab prototype only |
| Stable public API | **No** — everything may change |
| Production-ready frontend framework | **No** |
| React / Svelte replacement | **No** |
| WebSocket / SSE integration | **No** — transport is host responsibility |
| Contract execution from view runtime | **No** — explicitly forbidden |
| Portability to other runtimes | **No guarantee** |

---

## 11. Next Slice Recommendations

### Option A — IVF-P3: `.igv` View DSL Sketch
A minimal text DSL that compiles to a ViewArtifact JSON. Design question: is the artifact
format ergonomic as a compilation target? Validates the shape before committing to a parser.

### Option B — IVF-P3: Collection Rendering
Extend ViewArtifact with a `collections` key — a named list of element instances each carrying
their own `node_params`. SSR renders all items; JS re-renders on UIState change. Tests the
`match` display rule with multiple param values.

### Option C — IVF-P3: Multi-Slot Contract Binding
Demonstrate a component with 3+ slot values, all updating simultaneously from one
`updateSlots` call. Tests filtering, diagnostic accumulation, and render coherence at scale.

**Recommended: Option A** — the DSL sketch validates the artifact design before it ossifies.
