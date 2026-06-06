# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P1

Card: LAB-IGNITER-VIEW-FRAMEWORK-P1
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-igniter-isomorphic-view-artifact-mvp-boundary-v0
Status: done
Date: 2026-06-06
Proof: 37/37 IVF-P1 checks PASS
Artifact digest: sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404

---

## [D] Decisions

**D1 — ViewArtifact is the single isomorphic source of truth.**
Both the Ruby SSR renderer and the vanilla JS micro-runtime consume the identical
ViewArtifact JSON. No rendering logic is duplicated between Ruby and JS — both
implement the same pure expression evaluator over the same rule array format.
The artifact is content-addressed (SHA-256 of canonical sorted serialization).

**D2 — UIState and SlotValue are structurally separated at schema level.**
`ui_states` and `slots` are separate keys in the artifact. `ViewArtifact.new` raises
`ArgumentError` at build time on key overlap or slot mutation attempt. The JS runtime's
`executeInstructions` checks `hasOwnProperty.call(scope.uiState, target)` — slots
are never in `uiState`, so slot mutation fails closed silently. Three layers enforce
this: build time → SSR → JS runtime.

**D3 — display_rules and interaction_rules are separate arrays evaluated by separate logic.**
`applyDisplayRules` is a pure function → computed patch. `executeInstructions` is the
mutation path → UIState diff. They cannot interfere. No event scope leaks into display
evaluation (no `["event", ...]` domain in display rules).

**D4 — Artifact is inlined as `<script type="application/json">`, not fetched.**
The JS micro-runtime reads the artifact from a DOM script tag, not from a network
request. This means `fetch` is entirely absent from the view runtime. The SSR renderer
emits the script tag alongside the component HTML.

**D5 — JS runtime patches class / aria / data attributes only; never innerHTML.**
`patchElement()` sets `el.className`, `el.setAttribute("aria-*")`,
`el.setAttribute("data-*")`. No `.innerHTML =`, no `textContent =`, no `style.cssText`.
Verified by regex check in proof runner (IVF-P1-5a, IVF-P1-5b, IVF-P1-5c).

**D6 — All forbidden opcodes fail closed in the JS runtime.**
Unknown opcode → `console.error` + `return` (not continue, not ignore). Banned opcode
→ same. Target key not in UIState → same. The evaluator has no fallthrough on security
boundaries.

---

## [S] Shipped

### New files created

| File | Description |
|---|---|
| `igniter-view-engine/lib/view_artifact.rb` | ViewArtifact class: schema, validation, digest, serialization |
| `igniter-view-engine/lib/ssr_renderer.rb` | Ruby SSR renderer: display_rules evaluation, HTML emission, hydration attrs |
| `igniter-view-engine/igniter_view_runtime.js` | Vanilla JS micro-runtime: hydration, event binding, display_rules eval, DOM patcher |
| `igniter-view-engine/fixtures/tabs_artifact.rb` | Minimal fixture: tabs + one UIState + one SlotValue + one node_param |
| `igniter-view-engine/run_ivf_proof.rb` | 37-check proof runner (all pass) |
| `lab-docs/lab-igniter-isomorphic-view-artifact-mvp-boundary-v0.md` | This design/proof document |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P1.md` | This handoff card |

### Generated outputs (in `igniter-view-engine/out/`)

| File | Description |
|---|---|
| `tabs_view_artifact.json` | Machine-readable ViewArtifact export with digest |
| `tabs_ssr_output.html` | Full SSR HTML specimen: inlined artifact + hydration-ready component |
| `ivf_proof_summary.json` | Structured proof result matrix |

### Existing files untouched
- `igniter-lang/**` — not edited
- `tailmix/**` — not edited
- `igniter-view-engine/lib/igniter_view_engine.rb` — not edited
- `igniter-view-engine/lib/parser_builder.rb` — not edited
- `igniter-view-engine/run_proof.rb`, `run_ir_proof.rb`, `run_vsafe_proof.rb` — not edited
- `igniter-ide/src/lib/gui_interaction_ir.ts` — not edited

---

## [T] Proof Matrix

| Check | Result | What it verifies |
|---|---|---|
| IVF-P1-1 | ✅ PASS | ViewArtifact schema: all required keys present and machine-readable |
| IVF-P1-2 | ✅ PASS | UIState / SlotValue distinct keys, no overlap |
| IVF-P1-2b | ✅ PASS | ViewArtifact raises on overlap at build time |
| IVF-P1-3a..3i | ✅ PASS (9) | SSR renderer: all hydration attrs, display rule evaluation, determinism, script tag |
| IVF-P1-4 | ✅ PASS | Artifact JSON matches JS runtime expectations |
| IVF-P1-5a..5c | ✅ PASS (3) | JS: className, setAttribute, no .innerHTML= |
| IVF-P1-6a..6b | ✅ PASS (2) | Slot mutation fails closed: Ruby build-time + JS runtime source check |
| IVF-P1-7a..7f | ✅ PASS (6) | No eval, no innerHTML write, no fetch, no localStorage API, no CustomEvent, banned list present |
| IVF-P1-8 | ✅ PASS | No React/Svelte/Vue/HTMX/Tailmix API calls; no import/require |
| IVF-P1-9, 9b | ✅ PASS (2) | No contract execution in JS runtime or Ruby SSR renderer |
| IVF-P1-10a..10c | ✅ PASS (3) | Digest format, digest changes on mutation, digest in SSR HTML |
| IVF-P1-11a..11d | ✅ PASS (4) | Fixture: complete SSR specimen, hidden panel, visible panel, all element hooks |
| IVF-P1-12 | ✅ PASS | Mainline files untouched |
| IVF-P1-13a..13b | ✅ PASS (2) | non_claims present, safety_policy documented |
| **Total** | **37/37** | |

---

## [R] Risks and Recommendations

**Risk 1 — SlotValue injection mechanism is host-dependent (not yet defined).**
The current proof seeds slot values from Ruby at SSR time. How the host page updates
`data-ig-slots` after contract execution (e.g. via a fetch result processed by the
host app, not the view runtime) is not yet specified. This is intentional scope
deferral — but it must be addressed before the slot model is useful in production.

**Risk 2 — The `["slot", key]` domain in display_rules is read-only by convention.**
The JS evaluator's `evaluate()` function simply reads `scope.slotValues[args[0]]`.
There is no runtime type check that the slot key was declared in `artifact.slots`. A
bad actor with access to `data-ig-slots` could inject keys that are then read by
display rules. Mitigation: scope.slotValues should be filtered at hydration time to
only include keys declared in `artifact.slots`. (Not yet implemented — IVF-P2 item.)

**Risk 3 — Content of `data-ig-param` is not validated against `node_params_schema`.**
The JS runtime reads node params from `data-ig-param` but does not type-check against
the artifact's `node_params_schema`. This is fine for the current lab scope but is a
compile-time validation gap for any future canonical version.

**Recommendation: IVF-P2 — Live Slot Injection Proof.**
Define the host protocol for updating `data-ig-slots` after contract execution. The
view runtime re-evaluates display_rules on a call to `component.updateSlots(newValues)`.
This closes the loop between contract execution pipeline and the view layer without
introducing fetch or websocket into the view runtime itself.

Secondary recommendation: add `validateSlotKeys()` at hydration time in the JS runtime
to filter `data-ig-slots` against `artifact.slots` declared keys.
