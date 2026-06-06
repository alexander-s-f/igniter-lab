# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P2

Card: LAB-IGNITER-VIEW-FRAMEWORK-P2
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-igniter-isomorphic-view-artifact-mvp-boundary-v0
Status: done
Date: 2026-06-06
P1 baseline: 37/37 IVF-P1 checks PASS (regression confirmed)
P2 structural: 18/18 IVF-P2 checks PASS
P2 dynamic: 15/15 IVF-P2-DOM checks PASS (Node.js DOM proof, no browser)
Artifact digest: sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404 (unchanged — P2 adds no new schema fields)

---

## [D] Decisions

**D1 — filterSlotValues is applied at two checkpoints, not one.**
Both the `IgniterComponent` constructor (hydration-time, reading `data-ig-slots`) and
`updateSlots()` (runtime, host injection) call the same `filterSlotValues(incoming, declaredSlots)`
function. A single guard at construction-time would miss post-load injections. A single guard
in `updateSlots` would leave the hydration path unguarded. Both are required.

**D2 — Node param validation is warning-only; unknown keys are not removed.**
`validateNodeParams` flags unknown param keys in `component.diagnostics` but does not strip
them from `nodeParams` before rule evaluation. Display rules reference params only via
`["param", "key"]` expressions — an unknown key is silently unreferenced by any rule. Removing
it would not improve safety and would break development-time debugging (devs want to see
what's actually in params). Warning serves the developer without disrupting rendering.

**D3 — Digest mismatch is warning-only with rationale documented in source.**
The artifact content is the source of truth; the digest is an integrity signal, not a security
gate. Failing closed on digest mismatch would break components on valid cache-busted or
hot-reload deployments. The mismatch is logged to `console.warn` and recorded in
`component.diagnostics`. Hosts that require stricter policy can check `component.diagnostics`
after `hydrate()` and hide/error the component themselves. This keeps policy out of the runtime.

**D4 — componentRegistry exposed as IgniterView.components keyed by view_id.**
The host page needs a stable, synchronous reference to the component instance after hydration.
A registry keyed by `view_id` is the simplest interface. Last writer wins on duplicate
`view_id` (lab scope — not a production concern).

**D5 — Node.js DOM proof uses vm.createContext, not eval or jsdom.**
The proof script loads `igniter_view_runtime.js` via Node's built-in `vm` module into a
controlled sandbox with a minimal DOM mock (~50 lines, zero npm). This keeps the proof
self-contained and avoids conflating "proof harness uses eval" with "runtime uses eval".
The runtime itself has no eval — verified by IVF-P2-12b.

---

## [S] Shipped

### Modified files

| File | Change |
|---|---|
| `igniter-view-engine/igniter_view_runtime.js` | Added: `filterSlotValues`, `validateNodeParams`, `this.diagnostics`, slot guard in constructor, param validation in `_render()`, `updateSlots()` prototype method, `componentRegistry`, P2 helpers in public surface, digest mismatch diagnostic push, updated header comment |

### New files created

| File | Description |
|---|---|
| `igniter-view-engine/run_ivf_dom_proof.js` | Node.js dynamic proof runner: 15 checks, minimal DOM mock, outputs `out/ivf_p2_dom_proof.json` |
| `igniter-view-engine/run_ivf_proof_p2.rb` | Ruby P2 structural proof runner: 18 checks + P1 regression gate + Node.js integration |
| `igniter-view-engine/ivf_p2_browser_proof.html` | Self-contained browser proof: 20 assertions, live demo controls, diagnostic log display |
| `lab-docs/lab-igniter-view-live-slot-injection-and-hydration-hardening-v0.md` | Design doc: protocol, decisions, proof matrix, host integration pattern |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P2.md` | This handoff |

### Generated outputs (in `igniter-view-engine/out/`)

| File | Description |
|---|---|
| `ivf_p2_dom_proof.json` | Node.js dynamic proof result: 15/15 PASS |
| `ivf_p2_proof_summary.json` | Ruby P2 structural proof result: 18/18 PASS |

### Existing files untouched

- `igniter-lang/**` — not edited
- `tailmix/**` — not edited
- `igniter-view-engine/lib/view_artifact.rb` — not edited
- `igniter-view-engine/lib/ssr_renderer.rb` — not edited
- `igniter-view-engine/fixtures/tabs_artifact.rb` — not edited
- `igniter-view-engine/run_ivf_proof.rb` — not edited (P1 proof unchanged, runs as regression gate)

---

## [T] Proof Matrix

### P1 regression (37/37)

All P1 checks confirmed passing after P2 modifications. No regressions.

### P2 structural checks (18/18)

| Check | Result | What it verifies |
|---|---|---|
| IVF-P2-1 | ✅ PASS | `updateSlots` prototype method in JS source |
| IVF-P2-2 | ✅ PASS | `filterSlotValues` function in JS source |
| IVF-P2-3 | ✅ PASS | `validateNodeParams` function in JS source |
| IVF-P2-4 | ✅ PASS | `this.diagnostics = []` in constructor |
| IVF-P2-5 | ✅ PASS | `updateSlots` writes `dataset.igSlots` |
| IVF-P2-6 | ✅ PASS | `updateSlots` calls `this._render()` |
| IVF-P2-7 | ✅ PASS | `_render()` calls `validateNodeParams` against schema |
| IVF-P2-8 | ✅ PASS | Malformed `data-ig-param` → empty params + `malformed_param` diagnostic |
| IVF-P2-9 | ✅ PASS | Digest mismatch: warning-only, component always constructed |
| IVF-P2-10 | ✅ PASS | `filterSlotValues` called in constructor on raw `data-ig-slots` |
| IVF-P2-11 | ✅ PASS | `filterSlotValues` + `validateNodeParams` in `IgniterView` public surface |
| IVF-P2-12a | ✅ PASS | No `.innerHTML=` (P1 preserved) |
| IVF-P2-12b | ✅ PASS | No `eval()` (P1 preserved) |
| IVF-P2-12c | ✅ PASS | No `fetch()` (P1 preserved) |
| IVF-P2-12d | ✅ PASS | UIState `hasOwnProperty` guard intact (P1 preserved) |
| IVF-P2-13 | ✅ PASS | SSR renderer: no contract execution added |
| IVF-P2-14 | ✅ PASS | P1 proof runner: 37/37 still pass |
| IVF-P2-15 | ✅ PASS | Node.js DOM proof: 15/15 pass |
| **Total** | **18/18** | |

### P2 dynamic checks — Node.js DOM proof (15/15)

| Check | Result | What it verifies dynamically |
|---|---|---|
| IVF-P2-DOM-1 | ✅ PASS | `filterSlotValues`: declared key passes |
| IVF-P2-DOM-2 | ✅ PASS | `filterSlotValues`: undeclared key dropped |
| IVF-P2-DOM-3 | ✅ PASS | `filterSlotValues`: diagnostics for rejected keys |
| IVF-P2-DOM-4 | ✅ PASS | `validateNodeParams`: unknown key → `param_key_unknown` |
| IVF-P2-DOM-5 | ✅ PASS | `validateNodeParams`: all declared → empty diagnostics |
| IVF-P2-DOM-6 | ✅ PASS | Empty declared schema → all incoming rejected |
| IVF-P2-DOM-7 | ✅ PASS | Constructor: undeclared slot filtered at hydration |
| IVF-P2-DOM-8 | ✅ PASS | `updateSlots(valid)`: slotValues updated, render fires |
| IVF-P2-DOM-9 | ✅ PASS | `updateSlots(undeclared)`: key rejected, diagnostic appended |
| IVF-P2-DOM-10 | ✅ PASS | `updateSlots`: persisted to `dataset.igSlots` |
| IVF-P2-DOM-11 | ✅ PASS | Slot mutation via `interaction_rules` blocked (P1 fence) |
| IVF-P2-DOM-12 | ✅ PASS | `component.diagnostics` is an Array |
| IVF-P2-DOM-13 | ✅ PASS | `updateSlots(null/42/string)` → no throw |
| IVF-P2-DOM-14 | ✅ PASS | UIState interaction works after slot update |
| IVF-P2-DOM-15 | ✅ PASS | P2 helpers in `IgniterView` public surface |
| **Total** | **15/15** | |

---

## [R] Risks and Recommendations

**Risk 1 — Concurrent updateSlots calls are not guarded.**
If two host-page callers invoke `updateSlots` concurrently (possible in async/await contexts),
the `Object.assign(this.slotValues, filtered)` calls may interleave. In a browser's
single-threaded JS environment this is not an actual race (event loop), but the _render()
calls may fire twice. Mitigation: a debounce or batch flag in P3 if needed.

**Risk 2 — componentRegistry uses the view's view_id as key.**
If two components with the same view_id exist on the same page (e.g. two tab panels from the
same artifact), the second registration overwrites the first. Lab scope: acceptable. For a
canonical version, the registry should key on a unique instance id (e.g. the root element
itself, or a generated uuid).

**Risk 3 — validateNodeParams is warning-only; no type checking of values.**
The current implementation only checks key presence against the schema. Type checking
(e.g. "id" should be a string, not a number) is not implemented. Unknown keys produce warnings
but wrong-typed values produce no signal. This is a compile-time validation gap, not a
security concern — the display rules evaluate what they get, and wrong types produce
`null`/`undefined` from `["param", "id"]`, which will trigger the falsy branch of any
condition.

**Recommendation: IVF-P3 — `.igv` View DSL Sketch**
P1 and P2 prove that ViewArtifact JSON is a sound isomorphic contract between Ruby SSR and
the JS runtime. The next question is ergonomics: is this artifact format easy to author by
hand? Or does it need a DSL? Sketching `.igv` syntax → compiler → ViewArtifact JSON would
validate the artifact design before it ossifies. If the artifact is a poor compile target,
P3 is the right moment to reshape it — before P4 or higher layers depend on its structure.
