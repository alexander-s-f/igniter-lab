# IDD Card: LAB-FORMS-P1

Card:     LAB-FORMS-P1
Skill:    IDD Agent Protocol
Role:     research-agent
Lane:     cross_project (lab-local execution, evidence only)
Track:    lab-contract-invocation-forms-enhanced-proof-v0
Status:   complete
Result:   pass (12/12)
Started:  2026-06-04

---

## Contract

Run a bounded lab-local proof for enhanced contract invocation forms.
Focus: smallest compiler trust-boundary slice.
- Parse explicit contract forms
- Keep parser type-blind
- Resolve forms after type information
- Emit auditable form-resolution evidence
- Prove fail-closed behavior (P7/P8/P9)

## Authority Surface

| Surface | Status |
|---------|--------|
| `igniter-lab/igniter-compiler/**` | Open |
| `igniter-lab/lab-docs/lab-contract-invocation-forms-enhanced-proof-v0.md` | Open (create) |
| `igniter-lab/igniter-compiler/out/lab_contract_invocation_forms_enhanced_proof/**` | Open |
| `igniter-lang/**` | CLOSED — read-only |
| Mainline docs/tracks/proposals/spec | CLOSED |
| Runtime/API/CLI/package surfaces | CLOSED |
| Public docs | CLOSED |
| Release artifacts | CLOSED |

## Depends On (read-only context)

- `igniter-lang/docs/tracks/contract-invocation-forms-memory-recovery-and-dx-boundary-v0.md`
- `igniter-lab/lab-docs/PROP-Forms-Enhanced-v0.md`
- Archive Agent-C: PROP-Forms-v0 / C0 / C5 / C7

## Explicitly NOT in scope

- MultiKeywordForm
- AccumulatorRef / reduce syntax
- contract_shape inherited forms / FormShape
- Public `.igapp` schema authority
- Compiler passport emission
- Mainline parser/typechecker/SemanticIR changes
- Runtime form dispatch
- Stable grammar/API claims

## P1..P12 Requirements

- [ ] P1: `form (left) "+" (right)` parsed on a contract
- [ ] P2: parser remains type-blind, emits generic BinaryOp
- [ ] P3: lab-local Form Registry built from parsed forms
- [ ] P4: typed `a + b` resolves to ContractInvocation
- [ ] P5: output includes `form_resolution_trace`
- [ ] P6: output includes `form_table` evidence packet
- [ ] P7: `no_form` contracts fail closed when matched by form syntax
- [ ] P8: unresolved operator/form fails closed with clear diagnostic
- [ ] P9: ambiguous form candidates fail closed with clear diagnostic
- [ ] P10: explicit contract call valid even when form resolution blocked
- [ ] P11: runtime receives resolved contract meaning only; no runtime dispatch
- [ ] P12: `+` policy preserved: numeric only; `++` for concat

## Required Artifacts

- `out/lab_contract_invocation_forms_enhanced_proof/summary.json`
- `lab-docs/lab-contract-invocation-forms-enhanced-proof-v0.md`

## Return Format

Compact D/S/T/R packet:
- D: what was done
- S: what succeeded (P1..P12 status)
- T: trace / evidence
- R: recommendation for mainline intake

---

## Steps

- [x] Code: no_form_contracts tracking in FormRegistry (P7)
- [x] Code: no_form fail-closed in FormResolver (P7)
- [x] Code: ambiguity diagnostic in FormResolver (P9)
- [x] Code: unresolved diagnostic (P8)
- [x] Fixtures: positive / no_form / ambiguous / unresolved
- [x] cargo test  → ok (0 tests, 0 failures)
- [x] cargo run command matrix (4 runs) → pos=ok, nf=oof, amb=ok+W, unres=ok
- [x] summary.json produced
- [x] track doc written
