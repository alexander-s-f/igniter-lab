# LAB-IGV-TAILMIX-P1

**Card:** LAB-IGV-TAILMIX-P1
**Track:** lab-igv-tailmix-on-igniter-view-runtime-design-boundary-v0
**Status:** CLOSED — DESIGN BOUNDARY COMPLETE (design-locked)
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Skill:** IDD Agent Protocol
**Lane:** standard (design boundary; no protected surface touched)
**Category:** view / architecture
**Recommendation status:** design-locked → proof candidate (no syntax adopted, no code)

---

## Authority surface

- **Decides behavior today:** nothing — this is design. Behavior authority stays with existing accepted PROPs/spec + the canonical Rust VM.
- **Evidence source:** the design discussion, LAB-APP-STATE-P1/P2, igniter-view-engine (ViewArtifact/`.igv`/`igniter_view_runtime.js`/IVF series), Tailmix (`/Users/alex/dev/projects/tailmix`), debugger/srcmap tracks.
- **Authorized writes (exactly three):**
  - `lab-docs/view/lab-igv-tailmix-on-igniter-view-runtime-design-boundary-v0.md`
  - `.agents/work/cards/view/LAB-IGV-TAILMIX-P1.md`
  - `.agents/portfolio-index.md`
- **Closed surfaces:** client-side VM (JS/WASM/SIR→JS codegen), Ruby runtime / Tailmix gem, new adopted grammar, contract execution in the view runtime, instruction-vocabulary growth into computation, compiler/parser/VM change, client-side capability authority, canon/stable/public/framework API.
- **Implementation files touched by this card:** **none.**

---

## Goal

Fix the architecture for a view template + interaction layer for Igniter apps, derived from
a concrete target — a **Tauri IDE for Igniter, written in Igniter** (fractal), mostly
CRUD/forms with bounded interactivity. Reimplement the *idea* of Tailmix natively on Igniter
(no Ruby gem), define the `igv render` API so many component instances don't re-ship behavior,
and produce an exact next route. Component set is **static (build-time known)**.

---

## Locked decisions

D1 no client-side VM (native Rust VM in the Tauri backend; webview↔VM over IPC) ·
D2 no Ruby runtime (Tailmix idea, not gem) ·
D3 four parts only: `.igv` DSL → definition-JSON compiler → one tiny generic JS instruction
interpreter → escalation seam; interpreter must not become a VM ·
D4 three tiers by lifecycle — `:local`→Tailmix, `:session`/`:durable`→contracts, raw text→host
widget; disjoint ownership (no shared state across engines) ·
D5 single seam = `dispatch(event)` → host → contract ·
D6 type-vs-instance: definition is per-type content-addressed; render emits per-instance binding
only (G1 in UI form) ·
D7 static build-time component set → one definition bundle loaded once; `render → {html, def_refs}` ·
D8 closed/frozen `:local` instruction vocabulary, fail-closed; beyond it → dispatch ·
D9 definitions are inert content-addressed inspectable artifacts (like SIR), not authority, no
capability ·
D10 bounded parity (Igniter render ↔ JS interpreter) via a diff-oracle.

---

## Explicit answers

| Question | Answer |
|---|---|
| Need a JS VM for the Tauri IDE? | **No** (D1) — native Rust VM in the backend over IPC |
| Keep Ruby / the Tailmix gem? | **No** (D2) — reimplement the idea on Igniter |
| What is "Tailmix-on-Igniter"? | 4 parts (D3): `.igv` → definition JSON → tiny generic JS interpreter → dispatch seam |
| How is the redundancy bottleneck solved? | type-vs-instance split (D6): definition per-type content-addressed + deduped + shipped once; render = instance binding only |
| `igv render` shape? | `{ html, def_refs }` (D7); definitions delivered once via a build-time bundle, never inlined per render |
| Where does `:local` end and `:session` begin? | by lifecycle (D4); the single seam is `dispatch` (D5) |
| Does it execute contracts client-side? | No — preserves the view-engine "no contract execution in view runtime" boundary |
| Client-side capability = security? | No — honesty/structure only; real authority stays backend-side |
| Touches canon / adopts grammar / changes compiler? | No / No / No |

---

## Deliverable

Design report: `lab-docs/view/lab-igv-tailmix-on-igniter-view-runtime-design-boundary-v0.md`
— target/goal, 10 locked decisions, the 4-part model, tier/lifecycle ownership, type-vs-instance
content-addressing + render API, closed instruction vocabulary, bounded parity + diff-oracle,
scope/closed surfaces, risks, open questions, next route, boundary statement.

---

## Next route

**`LAB-IGV-TAILMIX-P2`** — proof-local Tailmix-on-Igniter definition + render + diff-oracle,
**zero compiler/parser/VM change**: one tiny component (`FileTreeRow`: `toggle` + `style/otherwise`)
→ content-addressed definition JSON; prove `render → {html, def_refs}` ships instance binding only
and N instances → 1 definition (hash dedup); reference applier (oracle) for the closed vocabulary,
diff-tested against `igniter_view_runtime.js` / a minimal interpreter over `(definition, state, event)`
triples; fail-closed unknown-`op`; `dispatch` produces a host event (not a `:local` mutation).
Target ~40–60 checks, lab-only, no Tauri required.

The IDE itself then becomes the pressure case driving the app-state follow-ups
(G1 instance identity for open buffers, G4 visibility for command palette, G3 assembly for
event→op→fact) → `LAB-APP-STATE-P3` / `LAB-APP-ASSEMBLY-P1`.

---

## Acceptance bar — self-check

| Bar | Met |
|-----|-----|
| Architecture fixed from a concrete target, not abstractly | ✅ Tauri IDE, static components |
| VM-strategy decided with rationale | ✅ D1 — no client VM; native Rust VM in backend |
| Redundancy bottleneck resolved | ✅ D6/D7 content-addressed type-vs-instance |
| Recommendation smuggles no implementation authority | ✅ design-only; no syntax adopted; no code |
| Six-term / G1 separation honored | ✅ definition=type, binding=instance |
| Exact next route produced | ✅ LAB-IGV-TAILMIX-P2 |
| Portfolio updated | ✅ |

---

*LAB-ONLY. Design boundary. No implementation authority. No canon claim. No stable API. No new grammar adopted. No client-side VM. No Ruby runtime.*
