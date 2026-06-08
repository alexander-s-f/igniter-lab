# LAB-RACK-P4

**Card ID:** LAB-RACK-P4
**Category:** lang / web
**Track:** lab-rack-static-route-dispatch-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 27/27 PASS

---

## D — Deliverables

- `igniter-view-engine/fixtures/rack_core/route_dispatch.ig`
- `igniter-view-engine/fixtures/rack_core/path_param_extract.ig`
- `igniter-view-engine/proofs/verify_p4_route_dispatch.rb` — **main deliverable, 27/27 PASS**
- `lab-docs/lang/lab-rack-static-route-dispatch-v0.md`
- `.agents/work/cards/lang/LAB-RACK-P4.md` (this receipt)

---

## S — Summary

Proved that Rack-like route dispatch is expressible as a single `pure contract`
using data-plane logic only. Two contracts compiled clean; 5 route cases proven
correct at algebra level; path param extraction confirmed.

**Proven:**
- 5-route data-plane table compiles as a single pure contract (`RouteDispatch`)
- Route algebra correct for all 5 cases (exact, param, method-sensitive, 404, 405)
- Path param extraction: `split(path, "/")` + `last(segments)` → `:id` correctly isolated
- SemanticIR confirms: `if_expr` with `stdlib.text.starts_with` condition nodes; `stdlib.text.split` + `last` chain

**Gaps found (new findings not in P3):**

| Gap | Detail |
|-----|--------|
| VM stdlib.text.* | Compiler emits `fn:"stdlib.text.starts_with"` but VM OP_CALL only handles bare `"starts_with"` — namespace mismatch blocks execution |
| TypeChecker `==` and `<` | OOF-TY0 on `==` and `<` for all types; dispatch uses `starts_with` workaround |

---

## Proof Matrix Coverage

| Item | Status |
|------|--------|
| P4-1: Both contracts compile clean | ✅ 4 checks |
| P4-2: GET / → 200 | ✅ 1 check |
| P4-3: GET /articles/:id → 200 + param | ✅ 3 checks |
| P4-4: POST /articles → 201 | ✅ 1 check |
| P4-5: GET /missing → 404 | ✅ 1 check |
| P4-6: POST /articles/:id → 405 | ✅ 1 check |
| P4-7: RouteDispatch SemanticIR shape | ✅ 2 checks |
| P4-8: starts_with stdlib call confirmed in IR | ✅ 2 checks |
| P4-9: split+last chain confirmed in IR | ✅ 2 checks |
| P4-10: VM stdlib.text.* gap characterised | ✅ 3 checks |
| P4-11..13: Closed-surface scan | ✅ 4 checks |
| P4-14: Gap packet complete | ✅ 2 checks |

---

## Gaps NOT closed by this card

| Gap | Status | Path |
|-----|--------|------|
| VM stdlib.text.* execution | Open | LAB-RACK-P5 (add `stdlib.text.*` cases to vm.rs OP_CALL handler) |
| TypeChecker `==` and `<` | Open | TypeChecker extension for String/Integer equality and `<` |
| ContractRef runtime dispatch | Open (from P3) | VM extension |
| VM entrypoint selection | Open (from P3) | VM extension |

---

## Next route recommendation

**LAB-RACK-P5: VM stdlib.text.* alignment**
Add `stdlib.text.starts_with`, `stdlib.text.split`, `stdlib.text.contains`,
`stdlib.text.length` (and other needed text ops) to the VM's `OP_CALL` handler
in `igniter-vm/src/vm.rs`. This single change unblocks full route dispatch
execution on the VM, converting the P4 algebra proof into a full end-to-end
VM execution proof.

Alternatively: add alias matching (bare name → stdlib.text.* equivalence)
so both `"starts_with"` and `"stdlib.text.starts_with"` resolve to the same handler.
