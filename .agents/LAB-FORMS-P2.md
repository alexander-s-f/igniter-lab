# IDD Card: LAB-FORMS-P2

Card:     LAB-FORMS-P2
Skill:    IDD Agent Protocol
Role:     research-agent
Lane:     cross_project (lab-local execution, evidence only)
Track:    lab-contract-invocation-forms-hardening-proof-v0
Status:   complete
Result:   pass (H1-H7)
Started:  2026-06-04
Depends:  LAB-FORMS-P1

---

## Contract

Harden LAB-FORMS-P1 proof so frontier evidence is protocol-honest.
Specific behaviors to fix: H1 ambiguity must refuse (error not warning),
H2 miss classification honest, H3 sidecar claim explicit, H4 + policy tested,
H5-H7 verification.

## Authority Surface

| Surface | Status |
|---------|--------|
| `igniter-lab/igniter-compiler/**` | Open |
| `igniter-lab/lab-docs/lab-contract-invocation-forms-hardening-proof-v0.md` | Open (create) |
| `igniter-lab/.agents/LAB-FORMS-P2.md` | Open |
| `igniter-lab/igniter-compiler/out/lab_contract_invocation_forms_hardening_proof/**` | Open |
| `igniter-lang/**` | CLOSED |
| Mainline docs/proposals/spec/tracks | CLOSED |

## Hardening Requirements

- [x] H1: E-FORM-AMBIG (error, no winner) — ambiguity refuses compilation
- [x] H2: classify miss as primitive_pass_through vs unresolved_trigger
- [x] H3: mark SemanticIR as sidecar_resolution_only
- [x] H4: + policy fixture (Integer ok, String+ rejected, ++ separate)
- [x] H5: no_form still fail-closed after H1/H2
- [x] H6: explicit_call trace-visible
- [x] H7: P4→sidecar_pass, P8→primitive_pass_through, P9→pass (H1 applied)

## Steps

- [x] form_resolver.rs: E-FORM-AMBIG, no winner (H1)
- [x] form_resolver.rs: primitive_pass_through vs unresolved_trigger (H2)
- [x] Fixtures: hardening/ directory (H4 + all required)
- [x] cargo test + command matrix (5 runs)
- [x] summary.json with H1-H7 + corrected P1-P12
- [x] track doc
