# Lab: Compiler Liveness, Non-Progress Detection, and Audit Boundary

Status: research-complete / design-ready
Date: 2026-06-08
Card: LAB-COMPILER-LIVENESS-P1
Authority: lab-only — not canon, not production, not stable API
Predecessor: LAB-PROOF-HYGIENE-P1 (process-level harness timeout)

---

## 1. Problem Statement

LAB-PROOF-HYGIENE-P1 added BoundedCommand to kill runaway `igniter_compiler`
processes from the outside. That fix protects the machine. It does not answer
the deeper question:

> Should the compiler detect and report its own non-progress, or must the
> machine operator always be the last line of defense?

Igniter-Lang's Covenant (Language Covenant, Postulates 14 and 27) is explicit:

- **Postulate 14 — Loops Are Managed**: Every repetition belongs to a loop class
  with a compiler-verified contract. There is no unbounded loop.
- **Postulate 27 — Accountability as Architecture**: Every language primitive
  exists to make accountability legible. "Managed loops" are named as a
  first-class accountability primitive.

The Covenant mandates managed loops *in the language*. It does not yet mandate
managed loops *in the compiler itself*. This is a gap. The compiler that enforces
Postulate 14 does not yet enforce it on its own execution.

This document maps liveness risks per compiler stage, proposes a diagnostic
taxonomy, designs an audit receipt shape, and recommends an implementation route.

---

## 2. Scope and Authority Boundary

This document:
- maps RISK only — it does not implement anything
- is lab-only; no canon changes
- proposes `E-COMPILER-*` diagnostic codes — these are NOT canon OOF codes
  (see Language Covenant CR-002: lab diagnostic codes require a formal PROP to
  become OOF canon)
- does not alter language semantics, `max_steps` semantics, or proof harness behavior

---

## 3. Stage-by-Stage Liveness Risk Map

### 3.1 Lexer (Rust)

**Mechanism**: The `tokenize()` loop drives on a character position `pos` that
only increases via `advance()`. The loop condition `pos >= self.chars.len()` is
checked on every iteration. The fallback `_` arm in `next_token()` calls
`advance()` unconditionally, consuming any unrecognized character.

**Verdict: STRUCTURALLY BOUNDED.** O(n) in input length. No liveness risk.

**Action needed**: None.

---

### 3.2 Parser (Rust)

**Mechanism**: The outer parse loop is:

```rust
while !self.peek_type(TokenType::Eof) {
    match self.parse_top_decl() {
        Ok(Some(...)) => { /* push result */ }
        _ => { self.advance(); }  // fallback: always advances
    }
}
```

The `_` fallback ensures the outer loop always advances. This is safe.

**Inner loops**: All inner `while !peek_type(RBrace) && !peek_type(Eof)` loops
terminate at either `}` or EOF. The Eof token is always present in the token
stream.

**Risk area 1 — `parse_import` `loop {}`**: The import parser uses an explicit
`loop` with break conditions that depend on specific token types. If an
adversarial input sequence never produces the break condition, this loop would
spin. The current token-advance pattern appears safe, but no step counter
enforces this.

**Risk area 2 — `skip_until_olap_clause_boundary()`**: Uses a depth counter to
track `{`/`}` nesting. Currently has no explicit EOF guard inside the loop body
(relies on `while let Some(tok) = self.current()` returning `None` at EOF).
If `current()` never returns `None` due to an implementation gap, this could
spin.

**Risk area 3 — `read_ident_or_keyword()`**: Includes logic for dotted paths
(`stdlib.IO.*` handling). The `continue` branch consumes one character per
iteration, but the break condition depends on peek(1) being an uppercase/lowercase
match. A carefully crafted input could slow this loop but not spin it.

**Verdict: LOW RISK.** The advance-on-fallback pattern prevents indefinite
outer spinning. Inner loops depend on Eof as a universal terminator.

**Most likely actual hang cause**: Not parser logic — external subprocesses
(cargo, compiler binary) that hang, which P1 already addressed.

**Action needed**: P2 — add loop step counter and log at threshold; verify
`parse_import` break conditions cover all token sequences.

---

### 3.3 Classifier (Rust)

**Mechanism**: Single-pass over `parsed.contracts` and `parsed.declarations`
(Vec iterators). The inner loops over `loop_body`, symbol resolution, and
dependency collection are all O(n) in AST size with no recursive descent.

**Verdict: STRUCTURALLY BOUNDED.** No liveness risk.

**Action needed**: None.

---

### 3.4 Typechecker (Rust) — `infer_expr` / `check_recur_in_expr`

**Mechanism**: `infer_expr` is a mutually recursive function over the `Expr` AST.
It calls itself on `left`, `right`, `object`, `operand`, `cond`, `then`,
`else_block`, and lambda `body` sub-expressions. No depth counter. No cycle
detection.

```rust
fn infer_expr(&self, expr: &Expr, ...) -> TypedExpression {
    match expr {
        Expr::BinaryOp { left, right, .. } => {
            let left_typed = self.infer_expr(left, ...);   // recursive
            let right_typed = self.infer_expr(right, ...); // recursive
            ...
        }
        Expr::IfExpr { cond, then, else_block } => {
            // three recursive calls
        }
        ...
    }
}
```

Helper functions `check_recur_in_expr`, `expr_has_call`, `is_recursive`,
`rewrite_concat_calls`, and `syntactic_decrease` are similarly recursive over
the AST.

**Stack overflow risk**: An adversarially deep expression tree (e.g., 10,000
levels of `(((a + b) + c) + d)...`) would exhaust Rust's call stack. Rust stack
overflow produces a SIGSEGV on Linux — not a clean diagnostic, and not a hang
but a crash. The proof harness would interpret this as a failed process.

**Non-progress risk**: O(n) in expression node count per contract declaration;
O(n × declarations) per contract; O(n × declarations × contracts) overall. For
a well-formed program this is fine. A program with thousands of declarations and
deeply nested expressions could be slow but not non-terminating.

**Verdict: MEDIUM RISK.** Stack overflow is a real risk for adversarial inputs.
No infinite loop risk for well-formed inputs. No cycle detection needed (the
AST is a tree, not a graph).

**Action needed**: P3 — depth counter with E-COMPILER-BUDGET at limit.

---

### 3.5 Typechecker (Ruby) — `infer_expr` / `check_loop_body`

**Mechanism**: The Ruby typechecker (`lib/igniter_lang/typechecker.rb`)
similarly recurses over JSON AST hashes. Ruby's default call stack is ~10,000
frames (typically configurable via `RUBY_THREAD_STACK_SIZE`). Very deep
expression nesting would produce `SystemStackError`, which is a fast fail —
not a hang.

The outer loop `classified_contract.fetch("declarations").each` is bounded by
declaration count.

**Verdict: LOW-MEDIUM RISK.** SystemStackError is a clean failure, not a hang.
No infinite loop risk.

**Action needed**: P3 — depth counter in `infer_expr`, wrap with rescue
`SystemStackError` and emit `E-COMPILER-BUDGET` instead of crashing.

---

### 3.6 Form Resolver (Rust) — `walk_expr`

**Mechanism**: `walk_expr` is recursive over the `Expr` AST, same depth risk
as `infer_expr`. The resolve_trigger function is O(candidates) per expression
node — candidates come from a finite registry, so it's bounded per call but
accumulates as AST depth grows.

**Verdict: MEDIUM RISK.** Stack overflow for adversarial deep nesting.

**Action needed**: P3 — same depth counter approach as typechecker.

---

### 3.7 Monomorphizer (Rust)

**Mechanism**: Iterates over `parsed.impls` × `parsed.contracts`. For each
generic contract with matching impls, it clones the contract and substitutes
types via `substitute_type_ref` and `substitute_expr` — both recursive over the
AST but bounded by AST size.

A module with N generic contracts × M impl declarations produces N×M
specializations. This is bounded by input size, but quadratic growth is
possible for large codebases.

**Verdict: LOW-MEDIUM RISK.** No infinite loop. Quadratic in (generic contracts
× impls) in the worst case. No cross-specialization cycles — monomorphization
uses a flat pass over pre-existing impls, not a fixpoint iteration.

**Action needed**: P4 — specialization counter; emit E-COMPILER-BUDGET if
total specializations exceed limit.

---

### 3.8 SemanticIR Emitter (Rust) — `lower_expr_for_targets` / `build_pipeline`

**Mechanism**: `lower_expr_for_targets` recursively walks a JSON value tree.
`build_pipeline` recursively unwraps `call` chains (pipeline depth = number of
chained filter/map/fold calls). Both are bounded by IR depth.

For `build_pipeline`: a pipeline of depth N means N recursive calls. Typical
pipeline depth is 3–10; adversarial inputs could be much deeper.

**Verdict: MEDIUM RISK.** Stack overflow for adversarial nesting/pipeline depth.

**Action needed**: P3 — depth counter.

---

### 3.9 Assembler (Rust)

**Mechanism**: Iterates over contracts and declarations in the SemanticIR JSON.
All traversals are over finite (already-typed, already-lowered) structures.
No recursion beyond flat inner loops.

**Verdict: LOW RISK.**

**Action needed**: P4 — node counter for very large programs.

---

### 3.10 Summary Risk Table

| Stage | Risk | Risk cause | Action gate |
|-------|------|-----------|-------------|
| Lexer | NONE | Structurally bounded | — |
| Parser | LOW | `loop{}` in import; no step counter | P2 |
| Classifier | NONE | Single-pass over finite Vec | — |
| Typechecker (Rust) | MEDIUM | `infer_expr` stack depth, no limit | P3 |
| Typechecker (Ruby) | LOW-MEDIUM | SystemStackError (clean fail) | P3 |
| Form Resolver | MEDIUM | `walk_expr` stack depth, no limit | P3 |
| Monomorphizer | LOW-MEDIUM | O(N×M) specializations, no counter | P4 |
| SemanticIR Emitter | MEDIUM | `lower_expr_for_targets` / `build_pipeline` stack | P3 |
| Assembler | LOW | Flat iteration | P4 |

---

## 4. Loops That Are Structurally Bounded by Input Size

These loops terminate because they exhaust a finite, pre-computed list:

- `for contract in &classified.contracts` — bounded by contract count
- `for decl in &contract.declarations` — bounded by declaration count
- `for imp in matching_impls` — bounded by impl count
- `tokens.push(tok)` in lexer — bounded by source length
- `for inner in loop_body` in classifier — bounded by loop body declaration count
- Form resolver `for contract in &typed.contracts` outer loop — bounded

No fuel or step counter needed for these — they cannot spin.

---

## 5. Loops That Need Explicit Step/Fuel Counters

These loops cannot be bounded structurally without additional instrumentation:

| Location | Loop pattern | Risk | Proposed counter |
|----------|-------------|------|-----------------|
| `parser.rs` `parse_import` | `loop {}` | LOW | per-import token consumption counter |
| `typechecker.rs` `infer_expr` | mutual recursion over AST | MEDIUM | call depth counter |
| `typechecker.rs` `rewrite_concat_calls` | AST rewrite recursion | MEDIUM | call depth counter (shares with infer_expr) |
| `form_resolver.rs` `walk_expr` | AST walk recursion | MEDIUM | call depth counter |
| `emitter.rs` `lower_expr_for_targets` | JSON tree recursion | MEDIUM | call depth counter |
| `emitter.rs` `build_pipeline` | call chain unwrap recursion | MEDIUM | pipeline depth counter |
| `monomorphizer.rs` total | N×M specialization loop | LOW | specialization count counter |

---

## 6. Loops That Need Cycle Detection

Currently: **none require cycle detection** in the existing compiler.

Rationale:
- The parser's AST is a tree, not a graph — no back-edges possible.
- The classifier and typechecker operate on trees produced by the parser.
- The monomorphizer uses a pre-existing flat impls list; it cannot re-expand
  a newly created specialization into further impls (no fixpoint iteration).
- There is no import graph traversal (imports are flat name lists, not followed
  recursively by the compiler).
- Type aliases, if ever added, would require cycle detection at the classifier.

**Future risk**: If the compiler ever adds:
- import graph following (recursive module loading)
- type alias expansion (alias A = B, alias B = A)
- fixpoint-based type inference
- cross-contract dependency analysis for graph compilation

...cycle detection would be needed. A `HashSet<visited_node_id>` guard is the
minimum; a proper Tarjan SCC pass would be appropriate for import graphs.

---

## 7. Loops That Need Recursion Depth Guards

| Function | Language | Max depth today | Proposed limit |
|----------|----------|----------------|----------------|
| `infer_expr` (Rust) | Rust | None | 1000 AST levels |
| `check_recur_in_expr` (Rust) | Rust | None | 1000 AST levels |
| `rewrite_concat_calls` (Rust) | Rust | None | 1000 AST levels |
| `walk_expr` (Rust) | Rust | None | 1000 AST levels |
| `lower_expr_for_targets` (Rust) | Rust | None | 500 IR levels |
| `build_pipeline` (Rust) | Rust | None | 100 pipeline stages |
| `infer_expr` (Ruby) | Ruby | ~10,000 frames | 500 AST levels |
| `substitute_expr` (Rust) | Rust | None | 1000 AST levels |

All limits should be env-configurable for research use:

```
IGNITER_COMPILER_MAX_EXPR_DEPTH   (default: 1000)
IGNITER_COMPILER_MAX_PIPELINE_DEPTH (default: 100)
IGNITER_COMPILER_MAX_SPECIALIZATIONS (default: 10000)
```

---

## 8. Which Errors Should Become Diagnostics Rather Than Process Timeout

| Current behavior | Should become |
|-----------------|---------------|
| Stack overflow (SIGSEGV/SystemStackError) | `E-COMPILER-BUDGET` with depth + pass name |
| Slow compilation on huge input | `E-COMPILER-BUDGET` warning at threshold, error at hard limit |
| Parser `loop{}` spinning on adversarial input | `E-COMPILER-NONPROGRESS` with token count + pass name |
| Proof harness SIGTERM (10s timeout) | Remains proof-harness-only; no change needed |
| Cargo build timeout (120s) | Remains proof-harness-only; no change needed |

---

## 9. Proposed Diagnostic Taxonomy

### 9.1 Why Not Reuse OOF Codes?

OOF codes (`OOF-P1`, `OOF-R2`, `OOF-L1`, etc.) represent language-level
errors: violations of the source program against language rules. They answer
the question: "What is wrong with this source program?"

Liveness diagnostics represent **compiler-internal non-progress**. They answer
a different question: "What is wrong with the compiler's ability to process this
input?" The program may be perfectly valid; the compiler may still fail to make
progress on it (e.g., adversarially deep nesting, or a compiler bug).

Conflating these would violate the Covenant's honesty axiom: the programmer
would receive an "OOF" error implying their source is wrong when actually the
compiler cannot process it.

**Rule**: `E-COMPILER-*` codes are compiler-internal. They do not appear in
the OOF registry. Promoting them to OOF status requires a PROP (per CR-002).

### 9.2 Proposed Code Family

```
E-COMPILER-BUDGET
  Meaning: A compiler pass exceeded its step/depth/fuel budget.
  Fields:  pass, budget_kind, limit, reached, context
  Severity: error (compilation blocked)
  Example: "typechecker.infer_expr: stack depth 1001 > limit 1000 in contract Foo node bar"

E-COMPILER-CYCLE
  Meaning: A compiler pass detected a cycle in a structure it cannot process.
  Fields:  pass, cycle_kind, cycle_path, context
  Severity: error (compilation blocked)
  Example: "classifier.type_aliases: cycle detected A -> B -> A"
  Note: Not currently reachable — reserved for future type alias / import graph work.

E-COMPILER-NONPROGRESS
  Meaning: A compiler pass made no forward progress in a bounded time window.
  Fields:  pass, elapsed_ms, tokens_consumed, context
  Severity: error (compilation blocked)
  Example: "parser.parse_import: 5000 tokens consumed, 0 progress in last 500"
  Note: Requires a watchdog or a per-pass progress counter.

E-COMPILER-INTERNAL-INVARIANT
  Meaning: The compiler detected an internal invariant violation.
  Fields:  pass, invariant, context, message
  Severity: error (compilation blocked; possible compiler bug)
  Example: "typechecker: contract 'Foo' has 0 output declarations but passed emit gate"
  Note: This is for compiler self-checks — assertions the compiler makes about its
        own intermediate state. Currently expressed as Rust panics; should become
        auditable diagnostics instead.
```

### 9.3 Code Relationships

```
OOF-*                     — source program violates language rules
E-COMPILER-BUDGET         — compiler budget exhausted (adversarial or huge input)
E-COMPILER-CYCLE          — compiler detected a cycle (future surfaces)
E-COMPILER-NONPROGRESS    — compiler made no progress (possible infinite loop path)
E-COMPILER-INTERNAL-INVARIANT — compiler invariant violated (compiler bug or malformed IR)

BoundedCommand timeout    — external process-level kill (proof harness only)
runtime max_steps         — language-level fuel (source program semantic)
```

These four domains must **never be conflated**. A receipt that conflates
"source program wrong" with "compiler couldn't process it" is dishonest and
violates Postulate 8 (Receipts Are Proof).

---

## 10. Audit Receipt Shape

When a liveness failure occurs, the compiler emits a structured diagnostic
packet alongside (or instead of) the normal compilation report:

```json
{
  "kind": "compiler_liveness_failure",
  "diagnostic_family": "E-COMPILER",
  "code": "E-COMPILER-BUDGET",
  "pass": "typechecker.infer_expr",
  "budget_kind": "stack_depth",
  "limit": 1000,
  "reached": 1001,
  "context": {
    "contract": "MyContract",
    "node": "compute_result",
    "expr_kind": "binary_op",
    "nesting_path": ["if_expr", "binary_op", "binary_op", "..."]
  },
  "message": "Compiler budget exceeded in typechecker.infer_expr: stack depth 1001 > limit 1000 in contract MyContract node compute_result",
  "is_source_program_fault": false,
  "is_compiler_internal": true,
  "compilation_blocked": true,
  "harness_timeout": false,
  "runtime_budget_exhaustion": false,
  "lab_only": true,
  "compiler_version": "0.1.x",
  "source_hash": "blake3:...",
  "advice": "Input expression nesting depth exceeds compiler budget. Refactor to shallower expression trees, or increase IGNITER_COMPILER_MAX_EXPR_DEPTH."
}
```

**Required fields**:
- `is_source_program_fault: false` — this is NOT an OOF; the source may be valid
- `is_compiler_internal: true` — distinguishes from runtime/harness failures
- `compilation_blocked: true` — compilation did not produce output
- `harness_timeout: false` — distinguishes from BoundedCommand kill
- `runtime_budget_exhaustion: false` — distinguishes from `max_steps`

This packet is written to stdout (the existing compilation output JSON) as an
additional `"liveness_failures"` array alongside `"diagnostics"`. It does not
replace the pass_result field — `pass_result` is set to `"error"` or `"oof"`.

---

## 11. Compiler Timeout vs Language-Level `max_steps` vs Proof Harness Timeout

This is a three-way distinction that must be preserved exactly:

| What | Who detects it | When | What it means | Audit artifact |
|------|---------------|------|--------------|---------------|
| `max_steps N` exhaustion | Runtime | At contract execution | Source program declared a fuel budget; it ran out | `OOF-R2` diagnostic; execution blocked |
| `E-COMPILER-BUDGET` | Compiler | During compilation | Compiler's own traversal exceeded internal budget | `compiler_liveness_failure` packet |
| BoundedCommand timeout | Proof harness | After wall-clock N seconds | Machine operator stopped waiting | `[TIMEOUT]` label in proof output; compiler exit forced |

**Critical rule**: A `E-COMPILER-BUDGET` error in the compiler does NOT mean
the source program's `max_steps` was wrong. A `max_steps` OOF in the runtime
does NOT mean the compiler had a liveness problem. A harness timeout means
neither — it means the clock ran out from the outside.

Conflating these would make the audit receipt dishonest.

---

## 12. What Must Remain Proof-Harness-Only

These protections must NOT be internalized into the compiler:

- **SIGTERM / SIGKILL to process group**: External OS signals. The compiler must
  not attempt to kill itself or its children.
- **Wall-clock timeout enforcement**: The compiler is not a watchdog. It cannot
  reliably measure wall time and kill itself. A watchdog thread with `SIGTERM`
  self-delivery is dangerous and unnecessary given the harness timeout.
- **Cargo build / cargo test timeout**: These are rustc/linker processes. The
  compiler binary does not invoke cargo. Harness-only.

These protections must BE internalized into the compiler:

- **Budget counters** per recursive pass (depth, step count)
- **Non-progress detection** in inner parser loops
- **Diagnostic packets** instead of silent crash or silent hang
- **Environment-configurable limits** so research can probe behavior

---

## 13. Proposed Implementation Gates

### P2: Instrumentation-Only Counters (no behavior change)

**Goal**: Learn the distribution of expression depths and step counts in real programs.

Changes:
- Add `depth: usize` parameter to `infer_expr` in Rust typechecker; increment
  on every recursive call; log (debug/trace) when depth > 100
- Same for `walk_expr` in form resolver, `lower_expr_for_targets` in emitter
- Add step counter to `parse_import` `loop{}`
- All counters are **non-fatal** — compile succeeds normally
- Emit no `E-COMPILER-*` codes
- Write depth/step data to a `"compiler_instrumentation"` field in the
  compilation report (optional, guarded by env flag)

Verification: run existing proofs; verify all pass; check instrumentation output.

**Outcome**: empirical data on actual depth/step distributions.

---

### P3: Depth Diagnostics in Typechecker + Form Resolver + Emitter

**Goal**: Convert step counters to hard limits; emit `E-COMPILER-BUDGET` instead
of stack overflow or silent slow compilation.

Changes (Rust compiler):
- `infer_expr`: add `depth: usize` parameter, return `E-COMPILER-BUDGET` error
  when `depth > IGNITER_COMPILER_MAX_EXPR_DEPTH` (default 1000)
- `check_recur_in_expr`, `rewrite_concat_calls`, `expr_has_call`: same
- `walk_expr` (form resolver): same
- `lower_expr_for_targets`: depth limit 500
- `build_pipeline`: depth limit 100

Changes (Ruby compiler):
- `infer_expr`: add `depth` counter, raise `E-COMPILER-BUDGET` (as a compiler
  error struct, not an exception) when depth > 500; rescue `SystemStackError`
  and emit same struct

Diagnostic format: `"liveness_failures"` array in compilation report JSON.

Verification:
- Craft a fixture with 1001-deep expression nesting → verify `E-COMPILER-BUDGET`
  fires, not crash
- Run all existing proof runners → verify 0 regressions

---

### P4: Full Compiler-Pass Budget Guard

**Goal**: Close the remaining unbounded surfaces; add per-compilation total budget.

Changes:
- Parser: add token-consumption counter to `parse_import` `loop{}` and
  `skip_until_olap_clause_boundary()`; emit `E-COMPILER-NONPROGRESS` when
  counter exceeds limit without progress
- Monomorphizer: add specialization counter; emit `E-COMPILER-BUDGET` when
  total specializations exceed `IGNITER_COMPILER_MAX_SPECIALIZATIONS` (default 10000)
- Assembler: add node counter; emit `E-COMPILER-BUDGET` when nodes exceed
  `IGNITER_COMPILER_MAX_NODES` (default 100000)
- Replace Rust `panic!` / `unwrap()` failures in internal paths with
  `E-COMPILER-INTERNAL-INVARIANT` — fail-closed with structured receipt
- Optional: add per-compilation total-token budget as CLI flag
  `--max-compile-budget N`

---

## 14. Implementation Checklist (for future P2/P3/P4 agents)

### P2 Checklist

- [ ] Add depth parameter to `infer_expr` (Rust typechecker)
- [ ] Add depth parameter to `walk_expr` (Rust form resolver)
- [ ] Add depth parameter to `lower_expr_for_targets` (Rust emitter)
- [ ] Add step counter to `parse_import` inner loop (Rust parser)
- [ ] Log (debug/trace) when depth > 100 in each function
- [ ] All existing proof runners pass 0 regressions

### P3 Checklist

- [ ] `infer_expr`: hard limit at `IGNITER_COMPILER_MAX_EXPR_DEPTH`; return
  `E-COMPILER-BUDGET` error from function (not panic)
- [ ] `check_recur_in_expr`, `rewrite_concat_calls`: same limit
- [ ] `walk_expr`: hard limit at same constant
- [ ] `lower_expr_for_targets`: hard limit 500
- [ ] `build_pipeline`: hard limit 100
- [ ] Ruby `infer_expr`: depth counter + rescue SystemStackError
- [ ] Craft adversarial fixture (1001-deep expression nesting)
- [ ] Verify `E-COMPILER-BUDGET` fires, compilation report has
  `"liveness_failures"` array, `pass_result` is `"error"` not `"ok"`
- [ ] Verify `is_source_program_fault: false` in receipt
- [ ] Run all existing proof runners: 0 regressions

### P4 Checklist

- [ ] `parse_import` loop: step counter → `E-COMPILER-NONPROGRESS`
- [ ] `skip_until_olap_clause_boundary()`: step counter → `E-COMPILER-NONPROGRESS`
- [ ] Monomorphizer: specialization counter → `E-COMPILER-BUDGET`
- [ ] Assembler: node counter → `E-COMPILER-BUDGET`
- [ ] Audit Rust `panic!` / `.unwrap()` / `.expect()` call sites in hot paths;
  replace with `E-COMPILER-INTERNAL-INVARIANT` where feasible
- [ ] Env vars: `IGNITER_COMPILER_MAX_EXPR_DEPTH`, `IGNITER_COMPILER_MAX_PIPELINE_DEPTH`,
  `IGNITER_COMPILER_MAX_SPECIALIZATIONS`, `IGNITER_COMPILER_MAX_NODES`
- [ ] All existing proof runners: 0 regressions

---

## 15. Remaining Risk After Full P4

| Risk | Residual severity | Why |
|------|-----------------|-----|
| Import cycles (future recursive module loading) | **DEFERRED** | Not implemented; cycle detection needed if added |
| Type alias cycles (future alias expansion) | **DEFERRED** | Not implemented; cycle detection needed if added |
| Cross-contract dependency fixpoint | **DEFERRED** | Not implemented; counter needed if added |
| Cargo / rustc hangs during proof | **MITIGATED (P1)** | BoundedCommand with SIGKILL |
| New pass added without budget guard | **LOW** | Requires hygiene discipline; documented in P4 checklist |
| Adversarial input below depth limits but quadratic | **LOW** | O(n²) is slow; not infinite; budget limits help |

---

## 16. Not Changed By This Document

- Canon language semantics — unchanged
- OOF diagnostic registry — unchanged
- `max_steps` language semantics — unchanged
- Proof harness BoundedCommand — unchanged
- Runtime, VM, release, public API — unchanged
- CI / release / packaging — not touched

---

## 17. Next Recommendation

**LAB-COMPILER-LIVENESS-P2**: Instrumentation pass (P2 checklist above).

Start there: it produces empirical data with zero behavior change, takes one
session, and validates that the depth/step instrumentation compiles and runs
correctly before P3 adds hard limits.

LAB-COMPILER-LIVENESS-P3 (hard limits, E-COMPILER-BUDGET) follows as a
separate card after P2 data is reviewed.

**Do not start P3 before reviewing P2 data.** The depth limits in P3 must be
calibrated against real program depths; choosing limits too low breaks real
programs, too high provides false safety.
