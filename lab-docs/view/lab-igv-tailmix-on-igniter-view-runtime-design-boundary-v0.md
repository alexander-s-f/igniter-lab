# LAB-IGV-TAILMIX-P1: Tailmix-on-Igniter View Runtime — Design Boundary

**Track:** `lab-igv-tailmix-on-igniter-view-runtime-design-boundary-v0`
**Status:** OPEN → CLOSED (design report complete)
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Recommendation status:** **design-locked → proof candidate** (architecture agreed; no syntax adopted, no code written)
**Authority:** No implementation authority. No canon claim. No stable API. No new grammar adopted. No JS-VM. No Ruby runtime dependency. No public framework claim.

---

## 0. Reading frame

This card fixes the architecture for a **view template + interaction layer for Igniter
applications**, derived from a concrete target: a **Tauri-hosted IDE for Igniter, written
in Igniter** (fractal/self-hosting), with mostly form/CRUD views and *bounded*
interactivity. It deliberately reuses, rather than reinvents, three things already
established in the lab:

- the **app-state model** (LAB-APP-STATE-P1/P2): host-owned state, pure transition
  contracts, lifecycle vocabulary, the six-term separation;
- the existing **view-engine** (`ViewArtifact`, `.igv` sketch, `igniter_view_runtime.js`,
  IVF P2–P9) whose standing boundary is **"no contract execution inside the view runtime"**;
- the **idea** of Tailmix (declarative state→HTML-attribute engine; events compiled to an
  instruction set; isomorphic SSR↔JS) — **the idea, reimplemented natively on Igniter, not
  the Ruby gem.**

No syntax is adopted here. `.igv` snippets and the definition/render JSON shapes are
**illustrative candidates** for comparison and to make the architecture concrete.

---

## 1. Target and goal

**Target.** A Tauri IDE for Igniter. Tauri = webview + a **Rust backend process**.

**Decisive consequence.** The canonical **native `igniter-vm` (Rust) runs in the Tauri
backend**; the webview talks to it over IPC (exactly the `igniter-ide` bridge:
`load_contract`/`dispatch_traced`/…). Therefore **no client-side VM is needed** — not a
hand-written JS VM (rejected in the discussion as tripling the Ruby↔Rust parity burden),
not WASM, not SIR→JS codegen. Contracts execute on the **one canonical VM**; the browser is
just another **host**, and the app-state model already says the host owns state.

**Goal.** Define a view template (`.igv`) with an expressive surface whose under-the-hood
model is **Tailmix-on-Igniter**: declarative `:local` interactivity compiled to an inert,
content-addressed **definition** artifact, interpreted client-side by one tiny generic JS
instruction interpreter, with everything semantic escalating to an Igniter contract. Decide
the **`igv render` API** so that many component instances do not re-ship behavior
(the redundancy bottleneck).

**Fractality is dogfooding, not a bootstrap paradox.** The IDE's *logic* is Igniter
contracts; the *runtime* is Rust. Like VS Code (TypeScript) on Node (C++): no circularity.
Building it will, however, force exactly the open app-state gaps — see §9.

---

## 2. Locked decisions (this card)

| # | Decision |
|---|----------|
| **D1** | No client-side VM. Contracts run on the native Rust `igniter-vm` in the Tauri backend; webview ↔ VM over IPC. |
| **D2** | No Ruby in the runtime. Tailmix is reimplemented as an Igniter-native artifact layer (its *idea*, not the gem). |
| **D3** | "Tailmix-on-Igniter" = four parts only: (a) `.igv` DSL, (b) `.igv`→**definition JSON** compiler, (c) one tiny generic JS **instruction interpreter**, (d) an explicit **escalation seam** to contracts. No fifth part; the interpreter must not become a VM. |
| **D4** | Three interactivity tiers, owned by lifecycle: `:local` → Tailmix definitions (client JS); `:session`/`:durable` → Igniter contracts (Rust VM via IPC); raw text editing → host widget. Ownership is **disjoint** (no shared state across engines) to avoid tri-parity. |
| **D5** | The **single seam** between `:local` and `:session` is `dispatch(event)` — a host-routed event that becomes an Igniter contract dispatch. One explicit, inspectable bridge. |
| **D6** | **type vs instance separation.** A `definition` is per component **type**, static, **content-addressed** (hash); a render emits only per-**instance** binding (def-ref hash + initial state + slot values). This is G1 (state-instance identity) in UI form. |
| **D7** | **Static, build-time component set** (confirmed for the IDE). `.igv` compiles to a **single definition bundle** loaded once at window init into a client registry. `render` returns `{ html, def_refs }` only — no inline definitions, no per-render redundancy. |
| **D8** | The `:local` **instruction vocabulary is closed and frozen** (§6). Anything outside it escalates via `dispatch` to a contract. Fail-closed, mirroring the storage-capability effect-name discipline. |
| **D9** | Definitions are **inert inspectable artifacts** (content-addressed like SIR `source_hash`), diffable/cacheable across launches, debuggable via the `node_id`/source-map track. They are NOT behavior authority and carry no capability. |
| **D10** | A **bounded parity** obligation replaces Tailmix's Ruby-SSR↔JS parity: Igniter-side initial render ↔ JS interpreter must yield the same DOM for the closed instruction set; verified by a diff-oracle (§7). Bounded, not open-ended. |

---

## 3. "Tailmix-on-Igniter" — the four parts (D3)

1. **`.igv` DSL (declaration).** Expressive surface: `state`, `element`, conditional
   attribute blocks (`style/otherwise`, `match/on`), `on :event → toggle/set/dispatch`.
   Authoring-time only.

2. **Compiler `.igv` → definition JSON.** Like the SIR emitter has a bytecode backend, the
   view pipeline emits a **definition**: a per-type instruction set (data, not JS),
   content-addressed by hash.

3. **One tiny generic JS instruction interpreter (the runtime).** Fixed, not per-app, not a
   VM. Reads `data-*` attributes, maintains `:local` state, applies attribute effects, wires
   events per the definition. This is the *only* client JS authored, shipped once (~few KB).

4. **Escalation seam to contracts.** Anything semantic is `dispatch`ed (D5) → host → Igniter
   contract over IPC → Rust VM.

> Two distinct "instruction sets" must never be conflated: **(1)** Tailmix-tier attribute
> instructions (interpreted by the tiny JS, `:local`); **(2)** Igniter SIR/bytecode (executed
> by the Rust VM, `:session`+). The definition JSON is strictly (1). Adding arithmetic/loops
> to (1) is the slippery slope back to the JS-VM we rejected — forbidden by D8.

---

## 4. Layering and lifecycle ownership (D4, D5)

| Tier | What | Owner | lifecycle |
|------|------|-------|-----------|
| Presentational / attribute | open/closed panel, active tab, aria, classes, local widget state, `on:click→toggle` | **Tailmix definition** (client JS interpreter) | `:local` |
| Semantic app-state | open file, run, save, diagnostics, command palette, open-buffer set | **Igniter contract** via Tauri IPC → Rust VM | `:session` / `:durable` |
| Raw text editing | cursor, keystroke in the code editor | **host widget** (Monaco/CodeMirror/native) | out of language (hot-path) |

```
.igv ──compile──▶ definition bundle (content-addressed, shipped once) ──▶ JS instr-registry
                                                                          │ applies :local
render(props) ──▶ { html: instance-binding + def_refs } ─────────────────▶ DOM
                                                                          │ dispatch(event)   ← the single seam (D5)
                                                                          ▼
                                                      Tauri IPC ──▶ native igniter-vm (Rust)
                                                                   :session/:durable contracts
```

Ownership is **disjoint**: the three engines never hold the *same* fact, so they never need
to agree on it — which is how a tri-runtime stack avoids a three-way parity nightmare.

---

## 5. type-vs-instance, the render API, and the redundancy bottleneck (D6, D7)

The redundancy the target flagged (many components → repeated behavior payload) is the
**type-vs-instance seam** (G1 from LAB-APP-STATE), not an API accident. Fix = separate by
**cardinality**:

- **definition** — per **type**, static, content-addressed, **deduplicated**, shipped once.
- **html** — per render, carries only **instance binding** (def-ref hash + initial state +
  slot values). No behavior inlined.

**Definition (per type, emitted once into the bundle):**
```json
{ "def_id": "sha256:ab12…", "component": "FileTreeRow",
  "states": { "expanded": { "default": false } },
  "elements": {
    "row":    { "rules": [ { "when": "state.expanded",
                             "classes": ["open"], "aria": { "expanded": true },
                             "else": { "classes": ["closed"], "aria": { "expanded": false } } } ] },
    "toggle": { "on": { "click": [ { "op": "toggle", "target": "state.expanded" } ] } }
  } }
```

**Render output (per instance):**
```json
{ "html": "<div data-igv=\"FileTreeRow\" data-igv-def=\"sha256:ab12…\" data-igv-state='{\"expanded\":false}'>…<button data-igv-el=\"toggle\">…</button></div>",
  "def_refs": ["sha256:ab12…"] }
```

→ N instances of one type = **1 definition + N tiny instance bindings**. Redundancy gone.

**API: `render(component, props) -> { html, def_refs }`.** The user's intuition
`[html, definitions]` is right *in spirit*, but `definitions` must be content-addressed +
deduplicated + register-once, never re-emitted per render.

**Delivery (static build-time set — D7, confirmed for the IDE).** `.igv` compiles to **one
static definition bundle** (like compiling SIR), loaded once at window init into the client
registry, cached on disk by hash across launches. `render` returns only `{ html, def_refs }`.
Partial re-render (a panel, a list fragment) ships only fragment HTML + refs; definitions
are never re-sent.

> (Out of scope here, recorded for completeness: a *dynamic* component set would instead use a
> runtime registry with a `definitions_delta` — defs not yet seen this session, keyed by hash.
> The IDE does not need this.)

---

## 6. The closed `:local` instruction vocabulary (D8)

Frozen set (≈ Tailmix's). Anything beyond → `dispatch` → contract.

| op | effect |
|----|--------|
| `toggle` | flip a boolean `:local` state key |
| `set` | set a `:local` state key to a literal |
| `add_class` / `remove_class` / `toggle_class` | class-list mutation on an element |
| `set_attr` / `set_aria` | attribute / aria mutation |
| `show` / `hide` | visibility toggle |
| `match` | select an effect block by a state value (Tailmix `match/on`) |
| `dispatch` | emit a host event → **the seam to contracts (D5)**; the ONLY way out of the `:local` tier |

No arithmetic, no loops, no data transforms, no IO. Those are contract territory. The
vocabulary is fail-closed: an unknown `op` is an error, never a silent no-op (mirrors the
storage-capability effect-name closed vocab).

---

## 7. Bounded parity and the diff-oracle (D10)

Dropping Ruby removes Tailmix's Ruby-SSR↔JS isomorphism but introduces a new, **bounded**
obligation: the **Igniter-side initial render** and the **client JS interpreter** must yield
the same DOM for the closed instruction set. Because the vocabulary is small and closed, this
is verifiable, not open-ended:

- a **reference applier** computes "definition + state → resolved attributes" deterministically;
- the JS interpreter must match it for every `(definition, state, event)` triple;
- the reference applier is the **diff-oracle** (same discipline proposed for SIR→JS codegen:
  the canonical side is the oracle, the client side is differentially tested).

This keeps the `:local` tier honest without a second full runtime to maintain.

---

## 8. Scope and closed surfaces

| Surface | Status |
|---------|--------|
| Client-side VM (JS / WASM / SIR→JS codegen) | **Closed** — not needed for the Tauri target (D1); revisit only for plain-browser deploy without a Rust backend, or sub-IPC-latency needs |
| Ruby runtime / Tailmix gem | **Closed** (D2) — idea reused, gem not |
| New adopted grammar | **Closed** — `.igv` snippets are candidates, nothing reserved |
| Contract execution in the view runtime | **Closed** — preserves the standing view-engine boundary; `:local` interpreter never runs contracts |
| Instruction vocabulary growth into computation | **Closed/frozen** (D8) |
| Compiler / parser / VM change | **Closed** — design only; zero implementation files |
| Capability authority client-side | **Closed** — client `:local` is honesty/structure, **not** security; real authority stays server/backend-side |
| Canon / stable / public / framework API | **Closed** — LAB-ONLY |

**Security note (recorded).** Anything in the webview is user-modifiable. Client-side
capability/denial structure is for *inspectability*, not enforcement; `effect`/`privileged`/
`irreversible` authority must remain in the Rust backend.

---

## 9. Risks and open questions

### Risks
- **Interpreter scope creep** → JS-VM by accident. Mitigated by D8 (frozen vocab, fail-closed).
- **Tri-runtime parity.** Mitigated by D4 (disjoint ownership) + D10 (bounded diff-oracle).
- **Definition/render drift.** Mitigated by D6/D9 (content-addressing; hash-keyed registry).
- **Hot-path latency.** Raw editing stays in the host widget (D4); contracts run on *semantic*
  events only — IPC-to-native-VM is sub-millisecond, fine for CRUD/forms.

### Open questions
**Blocking before P2:**
1. **`.igv` ↔ Tailmix-instruction compilation path:** does `.igv` emit definitions directly
   (single artifact path, preferred), or is there an intermediate IGV ViewArtifact that a
   second pass lowers to definitions? Affects where the compiler hook lives.
2. **Initial render producer:** the Rust/IGV backend renders initial HTML (no Ruby anywhere) —
   confirm the renderer that emits `data-igv-*` binding attributes lives on the Rust/view-engine
   side.
3. **`:local` ↔ `:session` boundary catalogue:** for the IDE, enumerate which facts are `:local`
   (Tailmix) vs `:session`/`:durable` (contracts) — the disjoint-ownership map (D4).

**Non-blocking:**
4. Definition bundle format details (single file vs per-type files; hash index shape).
5. Slot-value binding syntax in `.igv` (reuse view-engine slot linkage).
6. `dispatch` event schema (name + payload typing) at the seam.

---

## 10. Recommendation and next route

**Design-locked** (D1–D10), **research-only / proof candidate** — no syntax adopted, no code.

**Exact next card:** **`LAB-IGV-TAILMIX-P2`** — *proof-local Tailmix-on-Igniter definition +
render + diff-oracle*, with **zero compiler/parser/VM change**:
- take one tiny component (e.g. `FileTreeRow`: a `toggle` + a `style/otherwise` row);
- produce its **content-addressed definition JSON** (proof-local compile, hand-or-script
  generated — no language toolchain change);
- prove `render → { html, def_refs }` emits only instance binding, and **N instances → 1
  definition** (dedup by hash);
- implement a **reference applier** (oracle) for the closed vocabulary and **diff-test** the
  existing `igniter_view_runtime.js` (or a minimal interpreter) against it for
  `(definition, state, event)` triples;
- assert the closed-vocabulary fail-closed behavior (unknown `op` → error);
- assert the `dispatch` seam produces a host-event payload (not a `:local` mutation).

Target ~40–60 checks, PASS/FAIL, lab-only, no Tauri required (DOM proof can reuse the existing
`ivf_*_browser_proof` harness or a headless DOM).

**Then,** the IDE itself becomes the pressure case that drives the app-state follow-ups (§9).

---

## 11. Boundary statement

- **No implementation authority.** No compiler/parser/VM/runtime change; design only.
- **No canon claim.** Spec/proposals cited as context; lab tracks as evidence.
- **No stable API; no new grammar adopted** — `.igv`/JSON shapes are candidates.
- **No client-side VM; no Ruby runtime; no JS-VM.**
- **No framework/public claim.** LAB-ONLY.

---

## Depends on / continuity

| Source | Used for |
|--------|----------|
| LAB-APP-STATE-P1/P2 | host-owned state, pure transitions, lifecycle ownership, six-term + G1 type/instance seam |
| igniter-view-engine (ViewArtifact / `.igv` sketch / `igniter_view_runtime.js` / IVF P2–P9) | the view substrate + the "no contract execution in view runtime" boundary |
| LAB-TAURI-IVF-P10..P17 (existing series) | Tauri view-framework lineage this card continues |
| Tailmix (`/Users/alex/dev/projects/tailmix`) | the *idea*: declarative state→attribute engine, events→instruction-set, isomorphic SSR↔JS |
| LAB-DEBUGGER-FEASIBILITY-P1 / LAB-SRCMAP-P1 | content-addressed, node_id-anchored inspectability of definitions |
| PROP-035/Ch12 | the contract/capability seam that `dispatch` escalates into |

---

*LAB-ONLY. Design boundary. No implementation authority. No canon claim. No stable API. No new grammar adopted. No client-side VM. No Ruby runtime.*
