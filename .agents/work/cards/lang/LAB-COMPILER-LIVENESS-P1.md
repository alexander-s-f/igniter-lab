Card: LAB-COMPILER-LIVENESS-P1
Category: lang
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-compiler-liveness-nonprogress-audit-boundary-v0
Route: EXPERIMENTAL / LAB-ONLY / RESEARCH-DESIGN
Date: 2026-06-08
Status: complete

---

## Summary

Research and design for compiler liveness diagnostics. The question: if the proof
harness timeout protects the machine (P1), what protects the language? The
compiler should detect and report its own non-progress rather than silently
hanging or crashing.

This card is design-only. No compiler code was changed.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Research/design doc | `lab-docs/lang/lab-compiler-liveness-nonprogress-audit-boundary-v0.md` | ✅ written |
| Agent card | `.agents/work/cards/lang/LAB-COMPILER-LIVENESS-P1.md` | ✅ this file |

---

## Liveness Risk Map (summary)

| Stage | Risk | Primary cause |
|-------|------|--------------|
| Lexer (Rust) | NONE | `advance()` always increases `pos`; bounded by input length |
| Parser (Rust) | LOW | Outer loop safe (advance-on-fallback); `parse_import` `loop{}` unverified |
| Classifier (Rust) | NONE | Single-pass over finite Vec; no recursion |
| Typechecker (Rust) | MEDIUM | `infer_expr` / `check_recur_in_expr` recursive; no depth limit |
| Typechecker (Ruby) | LOW-MEDIUM | `infer_expr` recursive; SystemStackError is clean fail |
| Form Resolver (Rust) | MEDIUM | `walk_expr` recursive; no depth limit |
| Monomorphizer (Rust) | LOW-MEDIUM | O(N×M) specializations; no counter |
| SemanticIR Emitter (Rust) | MEDIUM | `lower_expr_for_targets` / `build_pipeline` recursive |
| Assembler (Rust) | LOW | Flat iteration; no deep recursion |

**No infinite loop risk** in well-formed programs. Main risks are:
- Stack overflow (Rust SIGSEGV / Ruby SystemStackError) for adversarially deep
  expression nesting — fast crash, not hang
- Parser `loop{}` in `parse_import` — unverified exit coverage for all token sequences

---

## Proposed Diagnostic Taxonomy

```
E-COMPILER-BUDGET            — step/depth/fuel counter exceeded in a compiler pass
E-COMPILER-CYCLE             — cycle detected (reserved for future import graph / type alias)
E-COMPILER-NONPROGRESS       — no progress in a bounded window (parser loops)
E-COMPILER-INTERNAL-INVARIANT — compiler invariant violated (structured panic replacement)
```

These are **NOT OOF codes**. Per Language Covenant CR-002, lab diagnostic codes
require a formal PROP to become canon OOF codes.

**Four-way distinction (must be preserved):**
- Source program rejected → OOF-* codes
- Compiler internal non-progress → E-COMPILER-* codes
- Proof harness external timeout → BoundedCommand [TIMEOUT] label
- Runtime budget exhaustion → max_steps / runtime domain

---

## Proposed Audit Receipt Shape

The compiler emits a `"liveness_failures"` array in the compilation report JSON:

```json
{
  "kind": "compiler_liveness_failure",
  "code": "E-COMPILER-BUDGET",
  "pass": "typechecker.infer_expr",
  "budget_kind": "stack_depth",
  "limit": 1000,
  "reached": 1001,
  "context": { "contract": "Foo", "node": "bar", "expr_kind": "binary_op" },
  "is_source_program_fault": false,
  "is_compiler_internal": true,
  "compilation_blocked": true,
  "harness_timeout": false,
  "runtime_budget_exhaustion": false
}
```

Key invariant: `is_source_program_fault: false` distinguishes this from OOF.

---

## Proposed Implementation Gates

### P2 — Instrumentation-Only Counters
- Add depth parameter to `infer_expr`, `walk_expr`, `lower_expr_for_targets`
- Add step counter to `parse_import` inner loop
- Non-fatal; log at threshold; no behavior change
- Produces empirical depth distribution data

### P3 — Hard Limits with E-COMPILER-BUDGET
- Convert depth counters to hard limits (default 1000 for expr depth)
- Emit `E-COMPILER-BUDGET` diagnostic instead of stack overflow
- Verify with adversarial deep-nesting fixture
- Env-configurable: `IGNITER_COMPILER_MAX_EXPR_DEPTH` etc.

### P4 — Full Budget Guard
- Parser `loop{}` nonprogress counter → E-COMPILER-NONPROGRESS
- Monomorphizer specialization counter → E-COMPILER-BUDGET
- Assembler node counter → E-COMPILER-BUDGET
- Replace hot-path `panic!`/`unwrap()` with E-COMPILER-INTERNAL-INVARIANT

---

## Compiler Timeout vs Language `max_steps` vs Harness Timeout

| What | Detects | Domain | Audit artifact |
|------|---------|--------|---------------|
| `max_steps` exhaustion | Runtime | Language semantic | OOF-R2 |
| `E-COMPILER-BUDGET` | Compiler | Compiler internal | `liveness_failures` packet |
| BoundedCommand timeout | Proof harness | Machine protection | `[TIMEOUT]` label |

These must NEVER be conflated.

---

## What Must Remain Proof-Harness-Only

- SIGTERM / SIGKILL to process group — external OS signal; compiler must not
  attempt to kill itself
- Wall-clock timeout enforcement — compiler is not a watchdog
- Cargo build / cargo test timeout — not invoked by compiler binary

---

## Did Production/Canon Change?

No. This is a research/design card. No files outside `lab-docs/` and
`.agents/work/cards/lang/` were written.

---

## Explicit Answers

**Where can the compiler currently spin or grow without bound?**

The highest-risk pass is `infer_expr` in the Rust typechecker — recursive AST
traversal with no depth limit. In practice this produces a stack overflow crash
(SIGSEGV), not an infinite loop. The parser's `parse_import` `loop{}` is the
only true spin candidate, but it appears to have correct break conditions.

**Which loops are structurally bounded by input size?**

Lexer, classifier, outer typecheck contract/declaration loops, form resolver
outer loops, assembler, monomorphizer outer loops. All use Vec iterators over
pre-computed, finite lists.

**Which passes need explicit step/fuel counters?**

`infer_expr`, `walk_expr`, `lower_expr_for_targets`, `build_pipeline`,
`parse_import` inner loop, monomorphizer total.

**Which passes need cycle detection?**

None currently. Reserved for future: import graph traversal, type alias
expansion, fixpoint type inference.

**Which passes need recursion depth guards?**

`infer_expr`, `check_recur_in_expr`, `rewrite_concat_calls`, `walk_expr`,
`lower_expr_for_targets`, `build_pipeline`, `substitute_expr`.

**Which errors should become diagnostics rather than process timeout?**

Stack overflow → `E-COMPILER-BUDGET`. Parser `loop{}` spin → `E-COMPILER-NONPROGRESS`.
Internal panic → `E-COMPILER-INTERNAL-INVARIANT`.

**Should there be a reserved diagnostic family?**

Yes: `E-COMPILER-*`. Not OOF codes. CR-002 applies to promotion.

**How should compiler timeout differ from `max_steps` or recursion fuel?**

`max_steps` = language semantic in the source program, evaluated at runtime.
`E-COMPILER-BUDGET` = compiler's own internal budget, evaluated during
compilation, independent of source program semantics.
BoundedCommand timeout = machine-level wall-clock kill, independent of both.

**What must remain proof-harness-only?**

SIGTERM/SIGKILL, wall-clock watchdog, cargo subprocess timeout. Compiler native:
depth counters, cycle detection, budget diagnostics.

**Smallest first implementation slice:**

P2 (instrumentation counters, non-fatal) — zero behavior change, zero risk,
produces data to calibrate P3 limits. One session. Start here.

---

## Next Route

**LAB-COMPILER-LIVENESS-P2** — Instrumentation pass (P2 checklist):
- Add depth counters to `infer_expr`, `walk_expr`, `lower_expr_for_targets`
- Add step counter to `parse_import` inner loop
- Non-fatal; compile succeeds normally; log at depth > 100
- Produces empirical depth data for P3 calibration

Do NOT skip to P3 without P2 data. Choosing limits too low breaks real programs.

**LAB-COMPILER-LIVENESS-P3** opens after P2 data is reviewed.
