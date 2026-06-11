# LAB-FUNCTION-RECURSION-P2 — Mutual Recursion SCC Readiness

**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Route:** LAB PROOF / READINESS / NO PRODUCTION SEMANTICS
**Status:** CLOSED — PASS 42/42
**Date:** 2026-06-11
**Predecessor:** LAB-FUNCTION-RECURSION-P1 (66/66 PASS)
**Method:** Empirical — Rust lab compiler invocations + proof-local SCC model

---

## Core Question

Should function recursion evidence (`decreases fuel`) be required **per function** or **per recursive SCC**?

**Answer: Per-SCC.** Pure mutual recursion is a correctness bug in the current per-function model.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Fixtures (5 + 2 inline) | `igniter-lab/igniter-view-engine/fixtures/function_recursion/p2_case*.ig` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_function_recursion_p2.rb` | 42/42 PASS |
| Lab doc | `igniter-lab/lab-docs/governance/lab-function-mutual-recursion-scc-readiness-proof-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-FUNCTION-RECURSION-P2.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Empirical Results

Rust lab compiler invoked on each fixture via `Open3.capture3`. JSON output checked for `"rule": "OOF-L4"`.

| Case | Pattern | status | OOF-L4? | Classification |
|------|---------|--------|---------|----------------|
| 1 | Self-recursive, no evidence | oof | YES | **Correct** |
| 2 | Self-recursive, decreases fuel | ok | no | **Correct** |
| 3 | Pure mutual A→B→A, no evidence | ok | **NO** | **CORRECTNESS BUG** |
| 4 | Pure mutual, only A has evidence | ok | no | **Bounded Gap** |
| 5 | Pure mutual, both have evidence | ok | no | Correct intent / unvalidated |
| Mixed-no-dec | A self+mutual, no evidence | oof | YES on A | Correct |
| Mixed-A-dec | A has evidence, B via A only | ok | no | **Bounded Gap** |

---

## Key Finding: Correctness Bug in Case 3

Pure mutual recursion (`def ping() { pong() }` and `def pong() { ping() }`) compiles with **zero diagnostics**. No OOF-L4. No warnings. Status ok.

**Root cause:** `is_recursive(body, fn_name)` checks if `fn_name` appears as a call in `body`. For `ping`, it checks if "ping" is called within `ping`'s body — `false` (only "pong" is called). The OOF-L4 loop in the typechecker is never entered for either function.

**Why this is a correctness bug (not a gap):**
- The OOF-L4 gate exists to require acknowledgment of potential non-termination
- Pure mutual recursion IS potential non-termination
- Any recursive program can bypass OOF-L4 by routing calls through another function
- Allowing this silently contradicts the gate's stated safety purpose
- This is an HONESTY VIOLATION: the language claims to gate unbounded recursion but doesn't for mutual cycles

**Cases 3, 4, and 5 are IDENTICAL from the compiler's perspective:**
Whether 0, 1, or 2 functions in a pure mutual pair have `decreases fuel`:
- All three produce `status: ok, diagnostics: []`
- The annotation on mutual-only functions is **inert** — parsed but never validated

---

## SCC Recommendation: PER-SCC

**Rule:** All members of any non-trivial SCC in the def function call graph must carry `decreases fuel`.

**Algorithm (for P3/P4 implementation):**
1. Build call graph of def functions (per-module)
2. Find SCCs via Tarjan's (O(V+E))
3. For each SCC with size ≥ 2 OR self-loop: every member must have `decreases fuel`
4. Missing member → OOF-L4 (or OOF-L4-MUTUAL — P3 decides canonical code)

---

## Spreadsheet Mapping

eval_expr ↔ eval_ref = **mixed SCC** (not pure mutual):
- eval_expr: self-recursive + calls eval_ref → OOF-L4 fires today (SS-P02)
- eval_ref: calls eval_expr only → NOT flagged today (SS-P03 bounded gap)
- NOT Case 3 (correctness bug) — bounded gap because eval_expr IS gated

| Fix | Change | Closes |
|-----|--------|--------|
| Minimal (SS-P02) | `decreases fuel` on eval_expr | Removes OOF-L4 compile error |
| Full safe (SS-P03) | `decreases fuel` on eval_ref too | SCC-complete coverage |

---

## Design Options

| Option | Model | Assessment |
|--------|-------|-----------|
| A (current) | Per-function self-only | Correctness bug (Case 3 undetected) |
| B (recommended) | Per-SCC | Correct; closes bug and gaps |
| C (defer) | Accept bug as v0 | REJECTED — honesty violation |

Option C rejected: allowing OOF-L4 to be structurally bypassed via mutual indirection contradicts the gate's purpose.

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Empirical | 10 | Compiler invocations for all 7 patterns |
| B — Classification | 8 | Bug vs gap; identical behavior cases 3/4/5; honesty argument |
| C — SCC Analysis | 8 | Proof-local model maps all cases; per-SCC rule |
| D — Spreadsheet Mapping | 6 | eval_expr↔eval_ref; SS-P02/SS-P03 |
| E — Design Options | 5 | A/B/C compared; C eliminated |
| F — Route Recommendation | 5 | Gap confirmed; per-SCC; P3 route |

**Total: 42/42 PASS**

---

## Authority Closed

No Rust/Ruby compiler changes / No new syntax / No VM/runtime / No app fixture edits / No stdlib work / Recommendation only (no implementation authorized in P2).

---

## Open Questions for P3

1. SCC algorithm: Tarjan's or Kosaraju's for the Rust implementation?
2. Diagnostic code: reuse OOF-L4 with different message, or new OOF-L4-MUTUAL?
3. Cross-module SCCs: per-module scope for v0; cross-module deferred
4. max_steps for def functions: orthogonal HOLD from P1 — P3 decides

---

## Next Route

**LAB-FUNCTION-RECURSION-P3** — SCC detection implementation design proof

P3 scope: Implement Tarjan's in proof-local model; validate against P2 case matrix; define exact Rust + Ruby typechecker change spec; proof matrix ≥ 50 checks; produce implementation plan.
