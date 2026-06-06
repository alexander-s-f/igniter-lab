# Track: lab-contract-invocation-forms-lowering-preflight-v0

Date:    2026-06-04
Card:    LAB-FORMS-P4
Depends: LAB-FORMS-P2, LAB-FORMS-P1
Status:  complete
Result:  pass (FPRE-1..FPRE-10 preflight matrix established)
Route:   conditional_accept_with_remaining_blockers

*Preflight evidence and candidate recommendation. Lab-local workspace.*
*No canonical syntax authority or implementation authority is claimed.*

---

## D — Done

Converted the self-issued forms lowering design into a protocol-honest preflight packet for a future Architect-owned S3 route. This document reconciles the findings of the experimental Rust compiler proofs (`LAB-FORMS-P1` and `LAB-FORMS-P2`) into a structured preflight specification.

---

## S — Preflight Matrix (FPRE-1..FPRE-10)

| ID | Focus Area | Lab Status / Stance | Constraint / Invariant |
|----|------------|---------------------|------------------------|
| **FPRE-1** | Current Lab Status | `sidecar_resolution_only` | SemanticIR is type-blind and unchanged; resolution trace exists only in output sidecars (`form_resolution_trace.json`). |
| **FPRE-2** | Main Compiler Blocker | Type-directed dispatch | Resolver currently does name-only lookup; filtering candidates by operand type is the primary blocker before lowering. |
| **FPRE-3** | Real Lowering Target | `ContractInvocation` / `Call` | Form trigger symbols must desugar and compile into canonical AST explicit call nodes. |
| **FPRE-4** | Post-Lowering IR | No form-trigger leakage | After the lowering pass, the SemanticIR must not retain form-trigger meaning (no raw operators/methods in lowered nodes). |
| **FPRE-5** | Syntax DX Sugar | Optional candidate only | `form:` shorthand is a candidate DX sugar; the canonical syntax remains explicit `form (left) "+" (right)`. |
| **FPRE-6** | Ambiguity Resolution | Strict `E-FORM-AMBIG` error | real ambiguity must refuse compilation (no winner); declaration order must not act as a semantic tie-breaker. |
| **FPRE-7** | First Runtime Stance | Inlining / Monomorphization | The compiler flattens and monomorphizes called contracts into the caller graph prior to assembly. |
| **FPRE-8** | Future Runtime Stance | VM subroutine linker | A runtime VM stack frame linker and registry is deferred to a future execution phase. |
| **FPRE-9** | Operator Policy | `+` / `++` separation | `+` is numeric/Additive only; `++` is a distinct and independent concatenation/append candidate. |
| **FPRE-10**| Authority Boundary | Preflight evidence only | No canonical authority, implementation authority, or stable API claims are made. |

---

## T — Trace / Evidence & Hardening Summary

The matrix above is derived directly from the `LAB-FORMS-P2` hardening run, which proved the following behaviors in the Rust lab-local compiler:
*   **H1 (E-FORM-AMBIG)**: Confirmed that ambiguity results in an compilation error with zero resolved form entries (`resolved_forms: []`).
*   **H2 (Miss Classification)**: Differentiated between primitive pass-throughs (known ops, correct pass-through) and unresolved triggers (unknown ops, diagnostic emitted).
*   **H3 (SemanticIR Sidecar Stance)**: Verified that SemanticIR retains generic `binary_op` nodes and has zero lowered `contract_invocation` nodes, proving that resolution currently lives in sidecars only.
*   **H4 (+ Policy Gate)**: Confirmed that `+` is successfully matched for Numeric types but rejected by the typechecker for String concatenation, while `++` is parsed as an independent concat trigger.

---

## R — Blocker List & Future S3 Candidate Recommendation

### Blocker List Before Mainline Implementation Authorization
1.  **Typechecker API for Type Annotations**: The compiler typechecker must expose resolved types for every expression node, enabling the `FormResolver` to execute type filtering.
2.  **Monomorphizer Integration**: Generic contracts (e.g. `Add[T: Additive]`) must have their trait bounds resolved and monomorphized prior to type filtering.
3.  **Scope Table Enforcement**: The resolver must consume module scopes (filtering out form entries hidden by `hiding` or prioritized by `overriding` clauses).
4.  **Graph Inlining Compiler Pass**: An AST/compute-graph flattening pass must be written to inline the dependency nodes of called contracts (like `Add`) into the caller's node list before bytecode assembly.

### Recommended Future S3 Route Target
Upon successful closure of the loops and recursion route (`R248`), the Architect Supervisor may authorize a new route:

```text
Route: future S3 route after current Main Line slot clears
Track: contract-invocation-forms-lowering-and-execution-boundary-v0
Goal: Design / authorize boundary for type-directed dispatch and lowering
Focus:
- Treat `form:` as optional DX candidate only, explicit form as canonical.
- Enforce type-directed candidate filtering.
- Implement strict compile error for ambiguity (`E-FORM-AMBIG`).
- Rewrite generic operations to lowered `ContractInvocation` / `Call` nodes.
- First runtime stance: monomorphize and inline called graphs; defer VM dynamic linking.
- Keep stable API, public grammar, and production runtime claims closed.
```
