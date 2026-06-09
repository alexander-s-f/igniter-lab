# LAB-SIDEKIQ-P4: JobReceipt Schema

**Category:** lang
**Track:** `lab-sidekiq-jobreceipt-schema-proof-v0`
**Status:** CLOSED / PROVED — 46/46 PASS
**Date closed:** 2026-06-09
**Agent:** Igniter-Lang Implementation Agent
**Role:** implementation-agent
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Depends on

- LAB-SIDEKIQ-P2 (static job dispatch table — 54/54)
- LAB-SIDEKIQ-P3 (BudgetedLocalLoop retry policy — 43/43)
- LAB-RACK-P11 (`call_contract` TypeChecker literal callee resolution — 47/47)
- LAB-RACK-P13 (nominal record typechecking — 47/47)

---

## Goal

Prove that a Sidekiq-like job execution surface can return a structured single-output
`JobReceipt` record using P13 nominal record typechecking, replacing raw Integer
retry/job outputs with a typed receipt validated at compile time.

---

## Scope

### Proved in P4

- **`type JobReceipt { ... }` declaration accepted** — 5-field schema parsed and
  registered in `type_shapes`
- **P13 `check_record_literal_shape` validates all 5 fields** — missing/extra/wrong-type
  fields each produce OOF-TY0 at compile time
- **P11 Tier 1 resolves `"ReceiptJob"` to `JobReceipt`** — literal callee dispatch
  propagates the named record type through the registry `single_output_type`
- **P11 Tier 2 dynamic callee stays `Unknown`** — P13 does not upgrade `call_contract`
  nodes (only `RecordLiteral` nodes)
- **P2 and P3 regressions green** — dispatch table and retry policy unchanged

### Not opened in P4

- **VM record construction** — `ReceiptJob` is not executed through the VM; P4 is
  TypeChecker/SemanticIR proof only
- **Enum/status type system** — `status` is a String vocabulary; no enum type
- **Async retry** — permanently closed
- **Queue storage** — permanently closed
- **Effect-callee dispatch** — deferred (P10/P11 output typing)
- **Multi-output callee** — deferred
- **Nested record types as field values** — not addressed

---

## Deliverables

| File | Status |
|---|---|
| `igniter-view-engine/fixtures/sidekiq_core/jobreceipt_schema.ig` | ✅ Written |
| `igniter-view-engine/proofs/verify_sidekiq_p4_jobreceipt_schema.rb` | ✅ 46/46 |
| `lab-docs/lang/lab-sidekiq-jobreceipt-schema-proof-v0.md` | ✅ Written |
| `.agents/work/cards/lang/LAB-SIDEKIQ-P4.md` | ✅ This file |
| `.agents/portfolio-index.md` updated | ✅ P4 row added |

---

## Key Findings

1. **P4 required zero new compiler code** — `check_record_literal_shape`,
   `output_type_hints`, and `build_contract_registry` from P11/P13 compose cleanly
   for `JobReceipt`. This validates the genericity of the P13 mechanism.

2. **P11 Tier 1 propagates named record types** — `single_output_type` stores
   `serde_json::Value`, which accommodates any named type (not just primitives). The
   `ReceiptDispatcher.receipt` compute node resolves to `JobReceipt` via Tier 1 without
   needing P13 in the dispatcher itself.

3. **P13 does not interfere with Tier 2** — `DynamicReceiptDispatcher.receipt` stays
   `Unknown` even with `output receipt : JobReceipt` annotation. Unknown-compat remains
   active for output type annotation mismatches.

4. **All 5 field shape violations fail closed** — missing, extra, wrong-type-String,
   wrong-type-Integer-on-String-field, wrong-type-String-on-Integer-field all produce
   OOF-TY0 with the field name and record type named in the diagnostic message.

5. **P5 blocker is VM record construction** — field values are validated at compile time
   but not yet accessible at VM runtime (VM record construction is deferred to P14/P5).

---

## P5 Recommendation

**VM record construction** — execute a contract with `JobReceipt` output end-to-end
through the VM. Prove that field values are accessible at runtime (field-by-field access
or full record output). This is the P14 recommendation from LAB-RACK-P13 applied to the
Sidekiq path.

---

## Boundary

Lab-only. No Sidekiq compatibility claim. No canon grammar change. No production runtime.
TypeChecker/SemanticIR proof only; VM record construction deferred. No public API stability.
`call_contract` is lab-only.
