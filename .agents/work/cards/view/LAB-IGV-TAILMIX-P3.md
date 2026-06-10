# LAB-IGV-TAILMIX-P3

**Card:** LAB-IGV-TAILMIX-P3
**Track:** lab-igv-tailmix-nested-composition-bundle-dedup-slot-values-v0
**Status:** CLOSED — PROOF COMPLETE (70/70 PASS)
**Route:** LAB PROOF / VIEW RUNTIME COMPOSITION / NO TOOLCHAIN CHANGE
**Skill:** IDD Agent Protocol
**Lane:** standard (proof-local; no protected surface touched)
**Category:** view / architecture

---

## Authority surface

- **Decides behavior today:** nothing — proof-local only.
- **Evidence source:** LAB-IGV-TAILMIX-P1 D1–D10 + P2 proof + new Sidebar component.
- **Authorized writes (exactly six):**
  - `igniter-view-engine/fixtures/igv_tailmix/sidebar_definition.json`
  - `igniter-view-engine/fixtures/igv_tailmix/definition_bundle.json`
  - `igniter-view-engine/fixtures/igv_tailmix/sidebar.igv`
  - `igniter-view-engine/proofs/verify_lab_igv_tailmix_p3.rb`
  - `lab-docs/view/lab-igv-tailmix-nested-composition-bundle-dedup-proof-v0.md`
  - `.agents/work/cards/view/LAB-IGV-TAILMIX-P3.md`
  - `.agents/portfolio-index.md`
- **Implementation files touched by this card:** **none.**
- **P2 files reused unchanged:** `file_tree_row_definition.json`, `igv_tailmix_interpreter.js`

---

## Goal

Extend the P2 single-component proof to a composed set: `Sidebar` containing N `FileTreeRow`
instances. Prove bundle-level definition dedup, nested render binding, slot values driving
row count, per-instance state isolation, and oracle/interpreter parity across both components.

---

## Result: 70/70 PASS

| Section | Checks | Result |
|---------|--------|--------|
| TAILMIX-BUNDLE | 8 | PASS |
| TAILMIX-SIDEBAR | 6 | PASS |
| TAILMIX-COMPOSE | 10 | PASS |
| TAILMIX-SLOTS | 7 | PASS |
| TAILMIX-DEDUP2 | 5 | PASS |
| TAILMIX-ISOLATE | 6 | PASS |
| TAILMIX-ORACLE2 | 10 | PASS |
| TAILMIX-INTERP2 | 8 | PASS |
| TAILMIX-FAILCLOSED2 | 6 | PASS |
| TAILMIX-IGV | 4 | PASS |

---

## Explicit answers

| Question | Answer |
|----------|--------|
| Bundle contains 2 definitions only? | **Yes** — BUNDLE-05, DEDUP2-04 |
| N rows → 2 unique def_refs? | **Yes** — DEDUP2-01/02 (3 rows and 5 rows both = 2 unique) |
| Different slot values reuse same definitions? | **Yes** — SLOTS-01/02/05 |
| Per-row state isolation proven? | **Yes** — ISOLATE-02, ISOLATE-04 |
| Oracle/interpreter parity for Sidebar? | **Yes** — INTERP2-01 through 05 |
| Oracle/interpreter parity for nested FTR? | **Yes** — INTERP2-06/07 |
| Unknown op in nested component fails closed? | **Yes** — FAILCLOSED2-01/02 |
| Missing component in bundle returns nil? | **Yes** — FAILCLOSED2-03/04 |
| `.igv` sketch marked non-canon? | **Yes** — IGV-03 |
| Interpreter unchanged from P2? | **Yes** — `igv_tailmix_interpreter.js` reused unmodified |

---

## Gap packet (open, non-blocking)

| # | Gap | Severity |
|---|-----|----------|
| OQ-1 | `.igv` → definition compiler (hand-authored in P3) | non-blocking until P4 |
| OQ-2 | Slot value typing (`List[FileTreeRow.Props]` is illustrative) | non-blocking |
| OQ-3 | Nested event payload routing (row `path` → `dispatch` payload) | non-blocking until P4 |
| OQ-4 | Bundle cache busting / hot-reload invalidation | non-blocking |
| OQ-5 | Multi-level nesting (>1 level composition) | non-blocking |

---

## Next route

**`LAB-IGV-TAILMIX-P4`** — proof-local `.igv` → definition JSON compiler:
- Parse `sidebar.igv` candidate syntax → definition JSON.
- Verify compiled output matches hand-authored `sidebar_definition.json`.
- Content-addressability: same `.igv` → same `def_id`.
- ~40–50 checks; no public grammar claim; proof-local parser only.

Alternatively if IDE pressure redirects:
- **`LAB-APP-STATE-P3`** — G2 fact↔holder binding
- **`LAB-APP-ASSEMBLY-P1`** — G3 event→op→fact for command palette

---

## Acceptance bar — self-check

| Bar | Met |
|-----|-----|
| 50–70 checks | ✅ 70/70 |
| 2 definitions only (Sidebar + FTR) | ✅ BUNDLE-05, DEDUP2-04 |
| N FTR instances → 1 FTR definition | ✅ DEDUP2-01/05 |
| `def_refs` unique count == 2 regardless of N | ✅ DEDUP2-01/02 |
| Slot values vary per render; definitions unchanged | ✅ SLOTS-01/02/05 |
| Per-row state isolation proven | ✅ ISOLATE-02/04 |
| Oracle/interpreter parity for nested cases | ✅ INTERP2-01 through 08 |
| Unknown op / missing component fail closed | ✅ FAILCLOSED2-01 through 06 |
| `.igv` sketch non-canon | ✅ IGV-03 |
| No toolchain/runtime/public API authority | ✅ |
| Portfolio updated | ✅ |

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API.*
*No compiler/parser/VM change. No contract execution. No client-side VM. No Ruby runtime.*
