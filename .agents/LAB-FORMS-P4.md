# IDD Card: LAB-FORMS-P4

Card:     LAB-FORMS-P4
Skill:    IDD Agent Protocol
Role:     research-agent
Lane:     cross_project (lab-local execution, evidence only)
Track:    lab-contract-invocation-forms-lowering-preflight-v0
Status:   complete
Result:   pass (FPRE-1..FPRE-10 matrix established)
Started:  2026-06-04

---

## Contract

Convert the self-issued forms lowering design into a protocol-honest preflight
packet for a future Architect-owned S3 route, without claiming future S3 route after current Main Line slot clears
authority, canonical syntax authority, implementation authorization, runtime
support, stable API, or public grammar support.

## Authority Surface

| Surface | Status |
|---------|--------|
| `igniter-lab/lab-docs/lab-contract-invocation-forms-lowering-preflight-v0.md` | Open (create) |
| `igniter-lab/.agents/LAB-FORMS-P4.md` | Open (create) |
| `igniter-lang/**` | CLOSED — read-only |
| `igniter-lab/igniter-compiler/**` | CLOSED — read-only |
| Mainline docs/tracks/proposals/spec | CLOSED |
| Runtime/API/CLI/package surfaces | CLOSED |

## Requirements Matrix

- [x] **FPRE-1**: Lab status from P2 is `sidecar_resolution_only`.
- [x] **FPRE-2**: Type-directed dispatch (TYPE FILTER) is the main blocker.
- [x] **FPRE-3**: Real lowering target in SemanticIR is explicit `ContractInvocation` or `Call`.
- [x] **FPRE-4**: SemanticIR must not retain form-trigger meaning after lowering.
- [x] **FPRE-5**: `form:` shorthand is marked as an optional DX sugar candidate only.
- [x] **FPRE-6**: Ambiguity is `E-FORM-AMBIG` error, not declaration-order winner.
- [x] **FPRE-7**: First runtime strategy is graph inlining/monomorphization during compile/assemble.
- [x] **FPRE-8**: VM dynamic linker / subroutine frames are deferred.
- [x] **FPRE-9**: `+` is numeric/Additive only; `++` is independent concat/append.
- [x] **FPRE-10**: No canonical authority or implementation authority is claimed.

## Steps

- [x] Write `lab-docs/lab-contract-invocation-forms-lowering-preflight-v0.md` with preflight spec.
- [x] Formulate lowering/type-dispatch/ambiguity/runtime matrix.
- [x] Document blocker list before implementation authorization.
- [x] Outline exact future S3 candidate recommendation.
