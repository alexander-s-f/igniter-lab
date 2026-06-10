# LAB-IGV-TAILMIX-P2

**Card:** LAB-IGV-TAILMIX-P2
**Track:** lab-igv-tailmix-definition-render-diff-oracle-proof-v0
**Status:** CLOSED — PROOF COMPLETE (56/56 PASS)
**Route:** LAB PROOF / VIEW RUNTIME BOUNDARY / NO TOOLCHAIN CHANGE
**Skill:** IDD Agent Protocol
**Lane:** standard (proof-local; no protected surface touched)
**Category:** view / architecture

---

## Authority surface

- **Decides behavior today:** nothing — proof-local only. No toolchain or public API changed.
- **Evidence source:** LAB-IGV-TAILMIX-P1 design decisions D1–D10; proof-local definition JSON + interpreter.
- **Authorized writes (exactly five):**
  - `igniter-view-engine/fixtures/igv_tailmix/file_tree_row_definition.json`
  - `igniter-view-engine/fixtures/igv_tailmix/igv_tailmix_interpreter.js`
  - `igniter-view-engine/proofs/verify_lab_igv_tailmix_p2.rb`
  - `lab-docs/view/lab-igv-tailmix-definition-render-diff-oracle-proof-v0.md`
  - `.agents/work/cards/view/LAB-IGV-TAILMIX-P2.md`
  - `.agents/portfolio-index.md`
- **Closed surfaces:** compiler/parser/VM change, Tauri IPC, contract execution in view runtime,
  JS VM/WASM/SIR→JS codegen, eval/Function() in interpreter, capability authority in webview,
  canon/stable/public/framework API.
- **Implementation files touched by this card:** **none.**

---

## Goal

Validate the LAB-IGV-TAILMIX-P1 architecture with one tiny component (`FileTreeRow`):
- Content-addressed definition JSON (per type, D6).
- `render → { html, def_refs }` with per-instance binding only (D7).
- N instances → 1 definition / dedup proof (D6/D7).
- Reference applier oracle + diff-test against proof-local interpreter (D10).
- Dispatch seam: host event, not state mutation (D5).
- Fail-closed on unknown op (D8).

---

## Result: 56/56 PASS

| Section | Checks | Result |
|---------|--------|--------|
| TAILMIX-DEF | 8 | PASS |
| TAILMIX-RENDER | 8 | PASS |
| TAILMIX-DEDUP | 5 | PASS |
| TAILMIX-ORACLE | 10 | PASS |
| TAILMIX-INTERP | 8 | PASS |
| TAILMIX-DISPATCH | 6 | PASS |
| TAILMIX-FAILCLOSED | 6 | PASS |
| TAILMIX-CLOSED | 5 | PASS |

---

## Explicit answers

| Question | Answer |
|----------|--------|
| Does the definition carry a content-addressed hash? | **Yes** — `def_id: sha256:…`, verified by DEF-08 |
| Does `render` return `{ html, def_refs }` with no inlined behavior? | **Yes** — RENDER-07/08 |
| Do N instances share 1 definition? | **Yes** — DEDUP-02: unique def_refs across N renders == 1 |
| Does the oracle match the interpreter for all triples? | **Yes** — INTERP-01 through 08 |
| Does `dispatch` emit a host event without mutating state? | **Yes** — DISPATCH-03/06 |
| Does an unknown op fail closed? | **Yes** — FAILCLOSED-01 through 06 |
| Does the definition contain VM/SIR/capability? | **No** — CLOSED-01 through 03 |
| Does the interpreter use `eval`/`Function()`? | **No** — CLOSED-04 |

---

## Gap packet (open, non-blocking)

| # | Gap | Severity |
|---|-----|----------|
| OQ-1 | Slot values in render (how prop data arrives from contracts) | non-blocking until P3 |
| OQ-2 | Multi-component composition + bundle-level dedup | non-blocking until P3 |
| OQ-3 | Definition bundle format (single file vs hash-indexed registry) | non-blocking |
| OQ-4 | `.igv` DSL compilation path (hand-authored in P2) | non-blocking until P4+ |
| OQ-5 | `dispatch` event schema / typed payload at the seam | non-blocking |

---

## Next route

**`LAB-IGV-TAILMIX-P3`** — small component set + nested composition:
- Second component type + list of `FileTreeRow`s.
- Bundle dedup: 2 types → 2 definitions, regardless of N instances.
- Slot values: list items arriving from contracts via dispatch.
- `.igv` DSL sketch for 2 components (hand-authored defs, no compiler yet).
- Target ~50–60 checks.

Alternatively, if IDE pressure drives app-state gaps first:
- **`LAB-APP-STATE-P3`** — G2 fact↔holder binding
- **`LAB-APP-ASSEMBLY-P1`** — G3 event→op→fact wiring

---

## Acceptance bar — self-check

| Bar | Met |
|-----|-----|
| Proof runner PASS, 40–60 checks | ✅ 56/56 |
| N→1 definition dedup proven | ✅ DEDUP-02 |
| Per-instance state isolation proven | ✅ DEDUP-03/04 |
| `{ html, def_refs }` render contract proven | ✅ RENDER-01 through 08 |
| Oracle/interpreter parity proven | ✅ INTERP-01 through 08 |
| Unknown op fail-closed proven | ✅ FAILCLOSED-01 through 06 |
| `dispatch` emits host event; no state mutation | ✅ DISPATCH-01 through 06 |
| No implementation authority or public API authority claimed | ✅ |
| Portfolio updated | ✅ |

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API.*
*No compiler/parser/VM change. No contract execution in the view runtime.*
*No client-side VM. No Ruby runtime.*
