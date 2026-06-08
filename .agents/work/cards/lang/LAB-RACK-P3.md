# LAB-RACK-P3

**Card ID:** LAB-RACK-P3
**Category:** lang / web
**Track:** lab-rack-contractref-vm-dispatch-preflight-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 25/25 PASS

---

## D — Deliverables

- `igniter-view-engine/fixtures/rack_core/hello_handler_standalone.ig`
- `igniter-view-engine/fixtures/rack_core/direct_call_attempt.ig`
- `igniter-view-engine/fixtures/rack_core/contractref_annotation.ig`
- `igniter-view-engine/proofs/verify_p3_contractref_dispatch.rb` — **main deliverable, 25/25 PASS**
- `lab-docs/lang/lab-rack-contractref-vm-dispatch-preflight-v0.md`
- `.agents/work/cards/lang/LAB-RACK-P3.md` (this receipt)

---

## S — Summary

Proved the precise gap map for ContractRef-as-handler-boundary in the lab compiler/VM.

Key findings:

| Layer | Finding |
|-------|---------|
| Parser | **NO GAP** — `ContractRef[A,B]` compiles as `type_ref` in SemanticIR |
| TypeChecker | **GAP** — direct `ContractName(args)` call rejected (OOF-TY0 / unknown-function) |
| SemanticIR | **PARTIAL** — form-resolved calls preserve `kind:call, fn:ContractName` IR identity |
| VM entrypoint | **GAP** — VM always executes `contracts[0]`; no entrypoint selector |
| VM dispatch | **GAP** — `OP_CALL` covers stdlib only; user contracts → "Unknown/unimplemented function" |

Baseline: HelloHandler standalone compiles and executes on VM, returns result=200.

---

## Proof Matrix Coverage

| Item | Status |
|------|--------|
| P3-1: P2 continuity | ✅ 1 check |
| P3-2: HelloHandler baseline compile + exec | ✅ 2 checks |
| P3-3: Direct call TypeChecker gap | ✅ 3 checks |
| P3-5: ContractRef type annotation finding | ✅ 3 checks (P3-DISPATCH-04/05, P3-IR-06) |
| P3-6: Dispatcher absent from SemanticIR | ✅ 1 check |
| P3-7: HelloHandler SemanticIR shape | ✅ 2 checks |
| P3-8: HelloHandler compute node kind=literal | ✅ 1 check |
| P3-9: Form-dispatch igapp IR reference | ✅ 2 checks |
| P3-10: HelloHandler VM execution | ✅ 2 checks |
| P3-11: VM entrypoint + dispatch structural gap | ✅ 2 checks |
| P3-12: No real network I/O | ✅ 1 check |
| P3-13: No accept-loop authority | ✅ 2 checks (SURFACE-02/03) |
| P3-14: No canon/stable/production claims | ✅ 1 check |
| P3-15: Gap packet complete + next route | ✅ 2 checks |

---

## Gaps NOT closed by this card

| Gap | Status | Path |
|-----|--------|------|
| ContractRef runtime dispatch | Open | VM source extension (OP_CALL user-contract case) |
| VM entrypoint selection | Open | VM source extension (--entry flag) |
| TypeChecker cross-contract call routing | Open | TypeChecker + form-table extension |
| Route dispatch table | Open | LAB-RACK-P4 (static table, no VM changes needed) |

---

## Closes gap in

- LAB-RACK-P2 row: "Dynamic ContractRef dispatch in VM → Open → LAB-RACK-P3"
  → Now: gap precisely characterised at each layer. TypeChecker (shallowest gap) → VM entrypoint
    → VM OP_CALL dispatch. ContractRef type annotation is NOT a parser gap.

---

## Next route recommendation

**LAB-RACK-P4: Route dispatch (static handler table)**
Prove a URL route-dispatch table encoded as a single pure contract — bypasses VM entrypoint
gap and OP_CALL gap by keeping dispatch in the data-plane. No VM source changes needed.
Directly extends HelloHandler baseline from P3.
