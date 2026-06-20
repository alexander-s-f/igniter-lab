# LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1 - Let/where bindings inside match arms

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: readiness / design
Delegation code: OPUS-LANG-MATCH-ARM-BINDINGS-P1
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The one real expressiveness ceiling found during IgWeb routing/context work was not "graphs are bad"; it was
that match arms are too narrow for readable pure branching.

Live pressure:

- built-in `Result[T,E]` uses fixed fields (`Ok { value }`, `Err { value/error }` depending on surface);
- pattern bindings cannot be renamed in the current surface;
- match-arm bodies are single expressions, so there is no local `let`/`compute` scope inside an arm;
- multi-`via`, nested guards, and context accumulation hit `value` shadowing and verbose composite-guard
  workarounds.

This card should design the smallest surface addition that preserves pure graph lowering.

## Goal

Answer:

```text
What is the minimal `.ig` syntax for local bindings inside match/if branches,
and how does it lower to the existing graph/SIR without new runtime authority?
```

This is readiness only. Do not implement parser/compiler changes here.

## Verify First

Read live surfaces:

- `lang/igniter-compiler/src/parser.rs` match/if grammar
- `lang/igniter-compiler/src/typechecker.rs` match/if typing
- `lang/igniter-compiler/src/emitter.rs` or lowering path for blocks/expressions
- fixtures using `match`, `Result`, `Option`, variants
- `lab-docs/lang/lab-igniter-web-routing-via-readiness-p19-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md`
- `lab-docs/lang/lab-igniter-web-context-composition-readiness-p25-v0.md`
- `lab-docs/lang/lab-igniter-web-context-composition-p26-v0.md` if present
- proposal/meta-proposal files for match-arm param unification, `let`, `where`, or block expressions.

Confirm or correct:

- whether match arms truly accept only one expression;
- whether block expressions already exist somewhere and can be reused;
- whether branch-local `compute` exists under another syntax;
- whether pattern alias/renaming exists;
- which cases are blocked by shadowing vs merely verbose.

## Alternatives To Compare

### A. Block arm with local computes

```ig
match result {
  Ok { value } => {
    compute ctx : Ctx = ...
    call_contract("Handler", req, ctx)
  }
  Err { value } => value
}
```

Likely most consistent with existing `compute` style if block expressions are plausible.

### B. `let ... in ...` expression

```ig
Ok { value } => let ctx = ... in call_contract("Handler", req, ctx)
```

Compact but introduces another binding form.

### C. `where` suffix

```ig
Ok { value } => call_contract("Handler", req, ctx)
  where ctx = ...
```

Readable for short expressions, but may be awkward with multiple bindings.

### D. Pattern alias / rename only

```ig
Ok { value as account }
```

Helps shadowing but does not solve multi-step computation inside an arm.

### E. Do nothing; bless composite-guard pattern

Acceptable only if the evidence says syntax cost is still lower than parser/typechecker risk. P21/P22
suggest this is not enough long-term.

## Required Questions

Answer directly:

1. Which exact app cases are blocked today?
2. Which syntax is smallest and most Igniter-native?
3. How does it lower to the graph/SIR?
4. Does it create ordered effects or hidden authority? It must not.
5. How are branch-local names scoped?
6. Can branch-local names shadow outer names? If yes, what diagnostics prevent footguns?
7. How does it interact with `Result` / `Option` built-ins?
8. Does it unlock multi-`via`, context accumulation, or only make them nicer?
9. What tests would prove parser/typechecker/emitter behavior?
10. What is the smallest implementation card after readiness?

## Required Deliverable

Create:

```text
lab-docs/lang/lab-lang-match-arm-bindings-readiness-p1-v0.md
```

It must include:

- live grammar/typechecker findings;
- alternative comparison;
- recommended v0 syntax;
- lowering sketch;
- acceptance tests for an implementation slice;
- explicit non-goals.

Update this card with a closing report.

## Closed Scope

- No implementation.
- No new effect/capability semantics.
- No multi-`via` implementation.
- No IgWeb parser changes unless only used as examples.
- No user-generic type changes.
- No pattern-matching overhaul beyond branch-local bindings design.
- No canon claim.

## Suggested Next

If readiness chooses a small syntax, open `LAB-LANG-MATCH-ARM-BINDINGS-P2` as an implementation-proof with
one multi-guard/context fixture and one non-web fixture.

---

## Closing Report (2026-06-20)

**Deliverable:** `lab-docs/lang/lab-lang-match-arm-bindings-readiness-p1-v0.md` — readiness/design, **no
code**. Answers Q1–Q10 with live findings, alternative comparison, recommended syntax, lowering sketch, and
an implementation test matrix.

**Decisive finding — the ceiling is a HALF-BUILT `let`, not a missing feature:**
- match arms accept only a single expression (`parse_match_arm_inner` → `parse_expr`); `{` in expression
  position is **record-only** (`parse_record_or_block` → `RecordLiteral`);
- **but** `BlockBody` + `parse_let_stmt` (block with `let` + return expr) **already exist** and are used by
  if/else branches, and the emitter already lowers `BlockBody`;
- **the gap:** `let` does **not bind** — `if x==1 { let a = x  a } else { 0 }` → **`OOF-P1: Unresolved
  symbol: a`** (control without `let` → `ok`). The typechecker reads a `let`'s *expr* for escape analysis
  but never registers its *name* in scope. No `.ig` fixture uses `let`, so the bug was latent.

**Recommendation: Alternative A — block arm with local `let`/compute**, because the building blocks already
exist. The implementation is mostly a **scope-resolution bug fix** + a small grammar add ("a match arm may
be a block"), not new syntax. Rejected B (`let..in`), C (`where`), E (do-nothing); D (pattern alias) may
ride along only if trivial.

**Lowering:** a `let name = expr` lowers to a named intermediate graph node (same shape as `compute`),
block-scoped; the block → emitter's existing right-nested chain. **No new SIR node kind, no ordered effects,
no authority** — pure DAG binding (P0 discipline). SIR-parity test: `{ let a=e  f(a) }` ≡ `f(e)`.

**The unlock:** `let x = value` immediately renames `Result`'s fixed `value`, so nested `Ok { value }`
matches no longer shadow → **multi-`via` over built-in `Result` becomes expressible** (a hard block, not
just verbosity).

**Next:** `LAB-LANG-MATCH-ARM-BINDINGS-P2` — (1) fix `let` scope resolution (the load-bearing bug; today
`OOF-P1`), (2) accept a block as a match-arm body; tests incl. a multi-`via` fixture + a non-web arithmetic
fixture + SIR-parity.
