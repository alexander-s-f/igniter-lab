# LAB-IGV-TAILMIX-P4

**Card:** LAB-IGV-TAILMIX-P4
**Track:** lab-igv-tailmix-igv-compiler-proof-v0
**Status:** CLOSED — PROOF COMPLETE (47/47 PASS)
**Route:** LAB PROOF / VIEW RUNTIME COMPOSITION / NO TOOLCHAIN CHANGE
**Skill:** IDD Agent Protocol
**Lane:** standard (proof-local; no protected surface touched)
**Category:** view / architecture

---

## Authority surface

- **Decides behavior today:** nothing — proof-local only.
- **Evidence source:** LAB-IGV-TAILMIX-P1 D1–D10 + P2 proof + P3 proof + sidebar.igv.
- **Authorized writes (exactly ten):**
  - `igniter-view-engine/fixtures/igv_tailmix/compiled_sidebar_definition.json`
  - `igniter-view-engine/fixtures/igv_tailmix/compiled_definition_bundle.json`
  - `igniter-view-engine/fixtures/igv_tailmix/invalid_unknown_op.igv`
  - `igniter-view-engine/fixtures/igv_tailmix/invalid_duplicate_component.igv`
  - `igniter-view-engine/fixtures/igv_tailmix/invalid_child_missing_component.igv`
  - `igniter-view-engine/fixtures/igv_tailmix/invalid_event_missing_state.igv`
  - `igniter-view-engine/fixtures/igv_tailmix/invalid_state_default_type.igv`
  - `igniter-view-engine/fixtures/igv_tailmix/invalid_malformed_block.igv`
  - `igniter-view-engine/fixtures/igv_tailmix/invalid_missing_component_name.igv`
  - `igniter-view-engine/proofs/verify_lab_igv_tailmix_p4.rb`
  - `lab-docs/view/lab-igv-tailmix-igv-compiler-proof-v0.md`
  - `.agents/work/cards/view/LAB-IGV-TAILMIX-P4.md`
  - `.agents/portfolio-index.md`
- **Implementation files touched by this card:** **none.**
- **P2/P3 files reused unchanged:** `sidebar.igv`, `definition_bundle.json`, `igv_tailmix_interpreter.js`

---

## Goal

Build a proof-local `.igv → definition JSON` compiler for the P3 candidate syntax.
Prove that the compiled output matches the hand-authored P3 definitions exactly (same
`def_id` hashes). Prove content-addressability, bundle generation, compatibility with
the P3 render/oracle/interpreter stack, and fail-closed behavior on 7 error categories.

---

## Result: 47/47 PASS

| Section | Checks | Result |
|---------|--------|--------|
| COMPILE | 10 | PASS |
| ADDR | 6 | PASS |
| BUNDLE | 7 | PASS |
| COMPAT | 10 | PASS |
| FAILCLOSED | 14 | PASS |

---

## Explicit answers

| Question | Answer |
|----------|--------|
| Compiler output matches hand-authored Sidebar def_id? | **Yes** — COMPILE-04 |
| Compiler output matches hand-authored FTR def_id? | **Yes** — COMPILE-05 |
| Same source twice → same hashes? | **Yes** — COMPILE-08 |
| Comments and blank lines stripped (no effect on hash)? | **Yes** — ADDR-01, ADDR-04 |
| Semantic change → different def_id? | **Yes** — ADDR-02/03 |
| Semantic change in one component affects the other's def_id? | **No** — ADDR-05 |
| Component-block order in source affects def_ids? | **No** — ADDR-06 |
| Compiled bundle_id matches hand-authored? | **Yes** — BUNDLE-04 |
| Compiled bundle compatible with P3 render/oracle/interpreter? | **Yes** — COMPAT-01..10 |
| 7 error categories each raise CompileError with correct message? | **Yes** — FC-01..14 |
| Any toolchain/VM/public API file touched? | **No** |

---

## Gap packet (open, non-blocking)

| # | Gap | Severity |
|---|-----|----------|
| OQ-1 | Slot bracket-type syntax (`List[X.Props]`) silently stripped | non-blocking |
| OQ-2 | Multi-event elements not tested | non-blocking |
| OQ-3 | Dispatch payload mapping from slot values | non-blocking |
| OQ-4 | Multi-level nesting | non-blocking |
| OQ-5 | Multi-error reporting | non-blocking |

---

## Acceptance bar — self-check

| Bar | Met |
|-----|-----|
| 45–70 checks | ✅ 47/47 |
| Compiled Sidebar def_id matches hand-authored | ✅ COMPILE-04 |
| Compiled FTR def_id matches hand-authored | ✅ COMPILE-05 |
| Same source → same hash (content-addressability) | ✅ COMPILE-08, ADDR-01..06 |
| Compiled bundle_id matches hand-authored | ✅ BUNDLE-04 |
| P3 render/oracle/interpreter compatible with compiled bundle | ✅ COMPAT-01..10 |
| 7 error categories fail closed (CompileError raised, message correct) | ✅ FC-01..14 |
| No toolchain/runtime/public API authority | ✅ |
| Portfolio updated | ✅ |

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API.*
*No compiler/parser/VM change. No contract execution. No client-side VM. No Ruby runtime.*
