# LAB-APP-STATE-P2

**Card:** LAB-APP-STATE-P2
**Track:** lab-code-editor-app-state-model-proof-local-v0
**Status:** CLOSED — PROOF COMPLETE (70/70)
**Route:** LAB PROOF / APP-STATE MODEL / NO KEYWORD
**Skill:** IDD Agent Protocol
**Lane:** standard (proof-local lab proof; no protected surface touched)
**Category:** lang / architecture
**Decision:** **A — metadata is enough for now** (hold proposals; document convention)

---

## Authority surface

- **Decides behavior today:** nothing changes — proof-local fixtures + runner only.
- **Evidence source:** lab Rust compiler SIR, Ruby TypeChecker, lab VM, proof-local sidecar registry.
- **Authorized writes:** the two fixtures + sidecar registry under `igniter-view-engine/fixtures/app_state/`, the proof runner, the lab doc, this card, the portfolio index.
- **Closed surfaces:** `state{}`/new keyword, `public/private/internal`, module instances, service/actor/class holder, app-manifest semantics, storage execution, parser/compiler/VM change, canon/public/stable/framework API.
- **Implementation files touched by this card:** **none.** (Working-tree `.rs` edits — `typechecker.rs` from LAB-TC-ARRAY-P2 earlier this session; `igniter-vm/*` from prior sessions — are unrelated to this card.)

---

## Goal

Test the P1 B⊕E recommendation: model a code-editor application's state using existing
Igniter concepts only, and discover which parts of app architecture are inspectable as
inert metadata vs which truly need a future proposal — keeping the six P1 terms separate.

---

## Result

**70/70 PASS** across 9 sections (COMPILE 5 · SHAPE 13 · LIFECYCLE 10 · TRANSITION 12 ·
PUBLIC 5 · DURABLE 6 · HOST 4 · GAP 8 · CLOSED 7). Regressions clean (LAB-TC-ARRAY-P1
27/27, LAB-QUERY-P3 44/44). No implementation files touched.

- State values = 11 typed records; transitions = 8 pure CORE contracts `(snapshot+event)→next`, VM-verified (composite `ApplyEdit` preserves nested records).
- **E path works in-language:** `:local/:session/:window/:durable/:audit` ride `output` lifecycle into SIR `output_ports[].lifecycle`.
- Durable save/load = `effect`+`IO.StorageCapability` / `observed` read-from-store — no storage execution. Split into a second fixture (VM rejects unbound-capability igapp load — F3).
- Holder stays host-owned; no mutable object; hot/session transitions need no capability.
- Descriptive app vocabulary carried in a proof-local sidecar registry (`intent` is **not parseable** in the lab toolchain — F2).

---

## Seven proof questions (answers)

1. Host state as typed records? **Yes** (11 records, typed).
2. Transitions as pure snapshot+event→next? **Yes** (7 pure, VM round-trips).
3. Lifecycle describes lifetime w/o holders? **Yes — in-language** (SIR output lifecycle).
4. Public vs internal from current surfaces? **Partially** — effect/observed inferable; pure public-op vs pure-helper indistinguishable (visibility gap G4).
5. Durable save/load as effect boundary w/o storage? **Yes** (effect + capability; pure stub).
6. Agent can ask "what state does this app own?" **Yes** — `(type_tag, lifecycle)` from SIR; instance/holder/visibility/wiring from sidecar.
7. Which P1 gaps remain non-language? **All four**, but all expressible as inert sidecar metadata, none blocking.

---

## Gap packet

| # | Gap | SIR | Sidecar | Note |
|---|-----|-----|---------|------|
| G1 | state-instance identity | absent (ports: name/type/lifecycle/required only) | `instance_key_source` | arguably correctly host-owned |
| G2 | fact↔holder binding | absent (no holder field) | `holder_class` + `holders{}` | partly proxied by lifecycle + `read from` |
| G3 | app assembly (event→op→fact) | absent (flat contract set) | `on_event`+`transitions` | largest surface; defer hardest |
| G4 | public/internal visibility | absent (pure-op==pure-helper modifier) | `visibility` | **smallest, cleanest — first candidate** |

---

## Decision & next route

**A — metadata is enough for now.** Everything needed to express, run, and *inspect* the
editor app-state model is achievable with zero new language surface (lifecycle in-language +
inert sidecar). No gap is blocking; adopting a surface now would be premature design-lock.

**Action:** hold proposals; the lab doc + registry sidecar document the proof-local convention.

**Held candidate (only on real pressure):** public/internal visibility (G4) → `LAB-MODULE-SURFACE-P1`.
Larger gaps held further: G2 → `LAB-APP-STATE-P3`; G3 → `LAB-APP-ASSEMBLY-P1`.

---

## Acceptance bar — self-check

| Bar | Met |
|-----|-----|
| Proof runner PASS, 40–60 checks | ✅ 70/70 (exceeds range; all green) |
| Report answers the 7 questions | ✅ §3 |
| Gap packet concrete, not generic | ✅ §4 — per-gap SIR-absent/sidecar-present + ranking |
| Lifecycle metadata expressible in fixture or documented | ✅ expressible in-language (E path; SIR output lifecycle) |
| No implementation files touched (unless justified+authorized) | ✅ none touched by this card |
| Decision classified A/B/C | ✅ A, with held B-candidate |
| Portfolio updated | ✅ |

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API. No runtime state-holder. No new keyword.*
