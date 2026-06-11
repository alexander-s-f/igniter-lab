# Lab: Function Mutual Recursion SCC Readiness Proof

**Document ID:** lab-function-mutual-recursion-scc-readiness-proof-v0.md
**Track:** function-level-managed-recursion-and-mutual-recursion-boundary-v0
**Lab work item:** LAB-FUNCTION-RECURSION-P2
**Route:** LAB PROOF / READINESS / NO PRODUCTION SEMANTICS
**Date:** 2026-06-11
**Proof result:** 42/42 PASS
**Predecessor:** LAB-FUNCTION-RECURSION-P1 (66/66 PASS — analytical model)
**Compiler used:** Rust lab compiler (igniter-lab/igniter-compiler/target/release/igniter_compiler)

---

## 1. Core Question

Should function recursion evidence (`decreases fuel`) be required **per function** or **per recursive SCC**?

---

## 2. Empirical Method

P2 compiles five fixture files against the Rust lab compiler and examines the JSON diagnostic output. Section A of the proof runner invokes the compiler directly via `Open3.capture3` and checks for `rule: "OOF-L4"` in the diagnostics array.

---

## 3. Fixture Inventory

| Fixture | Pattern | Rust result | Classification |
|---------|---------|-------------|---------------|
| `p2_case1_self_no_decreases.ig` | Self-recursive, no evidence | OOF-L4 | **Correct** |
| `p2_case2_self_with_decreases.ig` | Self-recursive, decreases fuel | ok | **Correct** |
| `p2_case3_pure_mutual_no_decreases.ig` | Pure mutual A→B→A, no evidence | ok (silent) | **Correctness Bug** |
| `p2_case4_pure_mutual_partial_decreases.ig` | Pure mutual, only A has evidence | ok (silent) | **Bounded Gap** |
| `p2_case5_pure_mutual_all_decreases.ig` | Pure mutual, both have evidence | ok (silent) | Correct intent / unvalidated |
| Mixed-no-dec (inline) | A self+mutual, A lacks evidence | OOF-L4 on A | Correct (A detected) |
| Mixed-A-dec (inline) | A has evidence, B participates via A | ok | **Bounded Gap** |

---

## 4. Key Findings

### F-1: Correctness Bug (Case 3)

**Pure mutual recursion (A→B, B→A with no self-calls) compiles completely silently** — no OOF-L4, no warnings, status ok, zero diagnostics.

This is a correctness bug, not just a gap. The safety property that the `OOF-L4` gate enforces is: *"every function that could loop infinitely must acknowledge it with `decreases fuel`."* Pure mutual recursion is unbounded recursion. The gate is COMPLETELY BYPASSED for any recursive program that avoids direct self-calls.

**Why it's a correctness bug (not merely a gap):**
- A programmer writing `def ping() { pong() }` and `def pong() { ping() }` gets no warning
- The `OOF-L4` gate EXISTS to prevent exactly this kind of silent infinite loop
- The bypass is structural: any recursive program can avoid the gate by routing calls through another function
- This is an honesty violation — the language claims to gate unbounded recursion but doesn't

### F-2: Root cause: is_recursive() is self-only

```rust
fn is_recursive(body: &BlockBody, fn_name: &str) -> bool
```

This function checks if `fn_name` appears as a call target in `body`. For `ping`, it checks if "ping" is called within `ping`'s body. Since `ping` only calls "pong", `is_recursive(ping.body, "ping")` returns `false`. Similarly for `pong`. Neither is checked.

### F-3: Bounded Gaps (Cases 4 and 7)

Cases 4 and 7 are bounded gaps (less severe than Case 3):
- Case 4: ping has `decreases fuel` but pong doesn't; cycle undetected for both
- Case 7 (mixed): ax self-recurses with fuel, bx calls ax but has no annotation

In these cases, at least one function carries an annotation. But the annotation on the annotated function is also unvalidated for the mutual part — the Rust checker only validates self-call annotations. The mutual SCC is invisible to the current checker.

### F-4: Cases 3, 4, and 5 produce identical compiler behavior

For pure mutual recursion, whether you annotate 0, 1, or 2 functions: the result is always `status: ok, diagnostics: []`. The `decreases fuel` annotation on pure mutual-only functions is currently **inert** — parsed successfully but never checked.

### F-5: Per-SCC is the correct model and is required for honesty

The three options compared:

| Option | Description | Assessment |
|--------|-------------|-----------|
| A (current) | Per-function self-only | Has a correctness bug (Case 3) |
| B (recommended) | Per-SCC — all SCC members must have evidence | Correct; closes all gaps |
| C (defer) | Accept Case 3 as known v0 bug | HONESTY VIOLATION |

Option C is not acceptable. The `OOF-L4` gate exists to require acknowledgment of potential non-termination. Allowing a structural bypass via mutual indirection contradicts the gate's stated purpose. Option B is required.

---

## 5. Proof Section Results

| Section | Checks | Focus |
|---------|--------|-------|
| A — Empirical | 10 | Rust compiler behavior for all 5 cases + 2 mixed; OOF-L4 presence/absence |
| B — Classification | 8 | Bug vs gap vs correct; identical behavior for cases 3/4/5; honesty argument |
| C — SCC Analysis | 8 | Proof-local SCC model maps all cases; per-SCC rule correctly accepts/rejects each |
| D — Spreadsheet Mapping | 6 | eval_expr↔eval_ref = mixed case; SS-P02 fix; SS-P03 recommendation |
| E — Design Options | 5 | Option A/B/C compared; Option C eliminated on honesty grounds |
| F — Route Recommendation | 5 | SCC gap confirmed; per-SCC required; no P2 compiler changes |

**Total: 42/42 PASS**

---

## 6. SCC Recommendation

**Recommendation: PER-SCC**

All members of any non-trivial SCC in the `def` function call graph must carry `decreases fuel`.

**Formal rule:**
1. Build the call graph of all `def` functions in the module
2. Find all SCCs using Tarjan's algorithm (O(V+E))
3. For each SCC of size ≥ 2, or any single-node SCC with a self-loop:
   - Every member function MUST have `decreases: Some("fuel")`
   - If any member lacks it: emit OOF-L4 for that member

**Notes:**
- Cross-module SCCs: deferred to P4 (single-module call graph is sufficient for v0)
- Indirect cycles (A→B→C→A): fully covered by SCC algorithm
- The max_steps question (from P1 F-4): orthogonal; per-SCC rule applies regardless of whether max_steps is required
- OOF-L4 code: reuse for self-recursive case; proof-local name "OOF-L4-MUTUAL" for mutual case (P3 decides canonical code)

---

## 7. Spreadsheet Mapping

**eval_expr ↔ eval_ref** = **mixed SCC** (not pure mutual):
- eval_expr: self-recursive (calls itself) AND calls eval_ref
- eval_ref: calls eval_expr only (no self-call)
- Current Rust: OOF-L4 fires for eval_expr (self-recursive), not for eval_ref

The spreadsheet is NOT Case 3 (pure mutual). It is a Mixed Case:
- SS-P02 minimal fix: `decreases fuel` on eval_expr removes OOF-L4 (Rust already gates the self-recursive part)
- SS-P03 under per-SCC model: `decreases fuel` required on BOTH eval_expr AND eval_ref

The eval_ref gap (SS-P03) is a BOUNDED GAP (not a correctness bug), because eval_expr IS gated. However, calling `eval_ref()` directly provides no annotation to the user. Under per-SCC, eval_ref must be annotated.

---

## 8. Authority Closed

- No Rust parser changes in P2
- No Rust typechecker changes in P2
- No Ruby typechecker changes in P2
- No VM/runtime behavior opened
- No new syntax
- No app fixture edits (spreadsheet files untouched)

The `decreases fuel` annotation on `def` functions (parser/typechecker path) is ALREADY IMPLEMENTED in the Rust lab. P2 only reads and measures that implementation.

---

## 9. Open Questions for P3

1. **SCC algorithm choice**: Tarjan's (iterative) vs Kosaraju's for the Rust implementation? Both O(V+E), but Tarjan's produces one pass vs Kosaraju's two.

2. **Diagnostic code for mutual gap**: Reuse `OOF-L4` with different message, or introduce `OOF-L4-MUTUAL`? The proof uses "OOF-L4-MUTUAL" as a proof-local label.

3. **Cross-module SCCs**: If module A has `def f()` calling `g()` from module B, and B's `def g()` calls `f()` — is this a cross-module SCC? P3 scope: per-module only. Cross-module deferred.

4. **max_steps for def functions**: P1 established this as a HOLD. P3 should decide: require max_steps for SCC members (aligning with fuel_bounded contract) or leave as annotation-only?

---

## 10. Next Route

**LAB-FUNCTION-RECURSION-P3** — SCC detection implementation design proof

P3 scope:
- Implement Tarjan's SCC algorithm in proof-local model
- Validate against the P2 case matrix (all 7 patterns)
- Define the exact typechecker change spec for Rust
- Define Ruby parity implementation spec
- Proof matrix ≥ 50 checks
- Produce implementation plan for P4
