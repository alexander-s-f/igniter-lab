# LAB-APP-STATE-P1

**Card:** LAB-APP-STATE-P1
**Track:** lab-application-state-modules-and-instance-composition-boundary-v0
**Status:** CLOSED — RESEARCH REPORT COMPLETE
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Skill:** IDD Agent Protocol
**Lane:** standard (design-boundary research; no protected surface touched)
**Category:** lang / architecture
**Recommendation status:** research-only → proof candidate (NOT design-ready; no keyword adopted)

---

## Authority surface

- **Decides behavior today:** nothing in this card — it is research. Behavior authority remains with existing accepted PROPs/spec.
- **Evidence source:** repo/spec review (PROP-015, PROP-031/Ch10, PROP-035/Ch12, PROP-045, Ch2), debugger feasibility report, and lab pressure tracks (Query/Storage, Epistemic Outcome).
- **Authorized writes (exactly three):**
  - `lab-docs/lang/lab-application-state-modules-and-instance-composition-boundary-v0.md`
  - `.agents/work/cards/lang/LAB-APP-STATE-P1.md`
  - `.agents/portfolio-index.md`
- **Closed surfaces:** compiler, parser, VM, runtime state implementation, new keyword adoption, canon edits, public/stable API claims, IDE UI work, framework-compat work.

---

## Goal

Analyze the application-level state and composition problem in Igniter from the pain
upward — without assuming a keyword, `state` declaration, service object, actor model,
module visibility, or host-owned state is the answer. Compare ≥4 routes, recommend one
(or a staged sequence) without smuggling implementation authority, and produce an exact
next route.

---

## Deliverable

Report: `lab-docs/lang/lab-application-state-modules-and-instance-composition-boundary-v0.md`
— all 9 required sections present (problem statement; existing language inventory;
application pressure model; ≥4 design alternatives; evaluation matrix; recommended route;
non-recommendations; open questions; boundary statement).

Five routes compared: **A** Host-Owned + Pure Reducers · **B** Descriptive State Vocabulary
· **C** Capability-Carried State Handles · **D** Composition Manifest (`.igapp`) ·
**E** Lifecycle-Scope Promotion.

---

## Central finding

Igniter already has a state-**lifetime** vocabulary (`:local/:session/:window/:durable/
:audit`) but **no state-holder**: it pushes holding outside the language and treats
contracts as pure transforms over snapshots. The "flat application" pain is not missing
state — it is that the **composition** of (stateful facts + lifetimes + holders + the
public operations that transition them) is **invisible in source**. The missing pieces
are precisely three: **state-instance identity**, a **named app-fact↔holder binding**, and
an **app-assembly artifact**. Everything else (typed values, lifetimes, external boundary,
effect character, queryable purpose) already exists and should be reused.

---

## Explicit answers (core questions)

1. **Where does long-lived state live?** Outside the language — in stores/hosts, reached
   via `read … from "<store>"` + lifecycle + capabilities. The language holds nothing.
2. **What owns an instance?** Today: nothing in source; identity is host-keyed. In-source
   instance identity is one of the three missing pieces.
3. **Role of a module?** Namespace + fragment-class/purity authority. **Not** a holder,
   visibility, instance, or composition unit (PROP-015 non-goals).
4. **Public ops vs internal helpers?** Signalled today only by modifier (`effect` vs
   `pure`) + `intent` convention; no visibility mechanism. A real public/internal boundary
   is missing (candidate: app-scope `expose`/`internal`, deferred).
5. **Avoid a flat list of contracts?** By making the app's **state vocabulary + transition
   wiring** inspectable as metadata (Routes B/E), not by adding a holder.
6. **Avoid hidden mutable object state?** Keep the holder external; model transitions as
   value→value contracts with receipts; never adopt a service/actor that holds+mutates
   fields (breaks honesty/debuggability/proofability).
7. **Keep composition inspectable?** Reuse the `intent`/`module_map` precedent: app model
   as inert, queryable metadata joinable to the node-anchored value trace by fact-name.
8. **Explicit-in-source vs runtime/host vs out-of-scope?** In source: state-value types,
   transition contracts, effect/capability boundaries, (proposed) descriptive state
   vocabulary. Host: holding, hot-state pumping, UI event routing, instance keying.
   Out of language scope (for now): UI rendering, framework wiring.

Boundary answers: opens StorageCapability execution = **No**; touches Ruby canon = **No**;
opens DB/SQL/ORM/runtime/storage authority = **No**; adopts a keyword = **No**.

---

## Recommendation & next route

**Staged:** Stage 0 = Route A discipline as the canonical app shape (already true, no
authority needed). Stage 1 = **B⊕E hybrid prototyped proof-locally** (descriptive state
vocabulary over existing lifecycle classes), **zero compiler/parser/VM/keyword changes**.
Defer C (use only at the durable boundary) and D (manifest) until the proof shows metadata
is insufficient.

**Exact next card:** **`LAB-APP-STATE-P2`** — proof-local code-editor app-state model:
host-owned state values + pure/effect transition contracts + descriptive state vocabulary
over existing lifecycle classes; validate inspectability + the six-term separation under
editor pressure; deliver a gap packet naming which of {instance identity, fact-holder
binding, app assembly, public/internal visibility} metadata cannot express. That gap packet
gates any future proposal-authoring card. (Alternatives if P2 reveals it: a module-surface
research follow-up, a proposal-authoring card if one design proves ready, or a hold.)

---

## Acceptance bar — self-check

| Bar | Met |
|-----|-----|
| Real architectural pain identified clearly | ✅ §1 flat-surface; holder-vs-lifetime distinction |
| ≥4 alternatives compared seriously | ✅ five routes (A–E) + matrix |
| Recommendation does not smuggle implementation authority | ✅ research-only; no keyword; holder stays external |
| Distinguishes value / instance / holder / transition / module / capability | ✅ §0 table, used throughout |
| Produces an exact next route | ✅ LAB-APP-STATE-P2 |
| Portfolio updated | ✅ |

---

*LAB-ONLY. Research / design boundary. No implementation authority. No canon claim. No stable API. No runtime state-holder authorization.*
