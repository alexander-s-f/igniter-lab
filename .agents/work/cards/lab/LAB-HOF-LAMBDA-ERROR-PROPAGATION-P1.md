# LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1

**Status:** CLOSED — PROVED 35/35 — DIVERGENCE CLASSIFIED + RECOMMENDATION EXPLICIT  
**Route:** LAB SAFETY / RUBY-RUST DIAGNOSTIC PARITY  
**Date:** 2026-06-13  
**Predecessor:** LAB-UNKNOWN-FIELD-ACCESS-P1

## Goal

Classify and route the Rust/Ruby divergence where HOF lambda body errors are propagated in Ruby but discarded in Rust.

Triggered by `LAB-UNKNOWN-FIELD-ACCESS-P1`: Ruby propagates `OOF-P1` from `filter(raw_decisions, d -> d.action ...)`; Rust typechecks map/filter lambda bodies using local `temp_errors` and discards them, then only blocks later through `OOF-TY1` at the output boundary.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-UNKNOWN-FIELD-ACCESS-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-unknown-field-access-p1-safety-boundary-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/rule_engine/engine.ig`

## Questions

1. Which HOFs use discarded temporary error buffers in Rust: `map`, `filter`, `fold`, others?
2. Which Ruby HOFs propagate errors directly?
3. Is Rust silencing intentional for speculative lambda inference, or a correctness gap?
4. What errors must propagate: OOF-P1 field/ref, OOF-COL3 predicate type, OOF-COL4 fold body, arithmetic/type errors?
5. What is the minimal Rust parity fix, if any?

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc | `igniter-lab/lab-docs/lang/lab-hof-lambda-error-propagation-p1-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_hof_lambda_error_propagation_p1.rb` | 35/35 PASS |
| This card | `igniter-lab/.agents/work/cards/lab/LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

## Findings (5 Questions Answered)

**Q1 — Which Rust HOFs use discarded temp_errors?**
- `filter` (line 3054): temp_errors, params correctly bound to element type — **correctness gap**
- `map` (line 3145): temp_errors, params correctly bound to element type — **correctness gap**
- `flat_map`/`and_then` (line 3211): temp_errors, params hardcoded Integer — **arguable**
- `Expr::Lambda` arm (line 4093): temp_errors, params hardcoded Integer — **intentional**

Rust HOFs with no lambda body typecheck at all: `fold`, `find`, `any`, `all`.

**Q2 — Which Ruby HOFs propagate errors directly?**
- `filter`/`map` via `infer_collection_hof_call` (line 2547): same `type_errors`
- `fold` via `infer_fold_call` (line 2711): same `type_errors`

**Q3 — Intentional or correctness gap?**
- `Expr::Lambda`: INTENTIONAL — hardcoded Integer params signal speculation placeholder; always returns Unknown
- `flat_map`: ARGUABLE — same Integer-placeholder class as Expr::Lambda; defer
- `filter`/`map`: CORRECTNESS GAP — params correctly typed to Collection element type; silencing unjustified

**Q4 — Which errors must propagate from filter/map bodies?**
OOF-P1 (field/ref on Unknown or missing field), OOF-TY0 (body type mismatch), all other body content errors.
OOF-COL3 (predicate Bool check) already propagates correctly — no change needed.

**Q5 — Minimal Rust parity fix?**
For `filter` (line 3054) and `map` (line 3145): remove `let mut temp_errors = Vec::new();`
and replace `&mut temp_errors` with `type_errors` in the lambda body typecheck section.
**NOT AUTHORIZED in P1.**

## Verdict: PROVED 35/35 — RECOMMENDATION EXPLICIT

```
Result: 35/35 PASS
VERDICT: PASS — LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 PROVED

  Rust filter/map temp_errors (gap):        lines 3054, 3145
  Rust flat_map temp_errors (arguable):     line  3211
  Rust Expr::Lambda temp_errors (intent.):  line  4093
  Ruby type_errors propagation:             lines 2547, 2711

  Ruby map body OOF-P1:     PROPAGATES
  Rust map body OOF-P1:     SILENCED (OOF-TY1 compensates at output boundary)
  Ruby filter body OOF-P1:  PROPAGATES
  Rust filter body OOF-P1:  SILENCED (OOF-COL3 propagates separately)

  Safety impact: MAINTAINED (OOF-TY1 output boundary compensates)
  Diagnostic fidelity: IMPAIRED in Rust (body-site errors not visible)

  Recommendation:
    filter + map:   IMPLEMENT PARITY (correctly typed params — no justification for temp_errors)
    flat_map:       DEFER (Integer placeholder params — arguable)
    Expr::Lambda:   PRESERVE AS INTENTIONAL (speculation placeholder, always-Unknown return)
```

## Proof Matrix (35 checks / 7 sections)

| Section | Checks | Result |
|---------|--------|--------|
| A — HOF landscape source census | 5 | 5/5 PASS |
| B — Ruby propagation model | 6 | 6/6 PASS |
| C — Rust silencing via binary | 7 | 7/7 PASS |
| D — Expr::Lambda arm: intentional speculation | 5 | 5/5 PASS |
| E — flat_map / and_then: arguable, defer | 4 | 4/4 PASS |
| F — Parity policy | 5 | 5/5 PASS |
| G — Closed surfaces | 3 | 3/3 PASS |

## Authority Closed

- No changes to `typechecker.rs` or `typechecker.rb`
- No new OOF codes
- No HOF lambda error propagation changes

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 | Implement Rust parity for filter/map (requires explicit upgrade) |
| LAB-RULE-ENGINE-BASELINE-P1 | Re-freeze rule_engine baseline post P-series |
