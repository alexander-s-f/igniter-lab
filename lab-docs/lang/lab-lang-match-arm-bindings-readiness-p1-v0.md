# lab-lang-match-arm-bindings-readiness-p1-v0 — local bindings inside match/if branches

**Card:** `LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1` · **Delegation:** `OPUS-LANG-MATCH-ARM-BINDINGS-P1`
**Status:** READINESS / DESIGN (v0) — designs the smallest `.ig` surface for **branch-local bindings**, the
one real expressiveness ceiling app work hit. **No implementation; pure-graph lowering preserved; no
canon claim.** Surface-ergonomics lane (P0), discipline: sugar lowers to existing SIR, no new authority.

## 1. Executive summary — the ceiling is a half-built `let`, not a missing feature

The decisive verify-first finding: **`let` bindings already exist in the grammar but do not resolve.**
A `let` inside an if-branch block fails with **`OOF-P1: Unresolved symbol`** — the name is never bound into
scope. So the fix is mostly a **scope-resolution bug fix + a small grammar extension**, not new syntax:

1. **fix `let`-in-block scoping** so a `let name = expr` binds `name` for the rest of the block (today the
   typechecker only reads the let's *expr* for escape analysis, never registers the *name*);
2. **let a match arm body be a block** (today it is a single expression), reusing the existing `BlockBody`.

Recommended v0 = **Alternative A (block arm with local `let`/computes)** — it reuses `BlockBody` +
`parse_let_stmt` that if/else branches already use; the only *new* surface is "a match arm may be a block."

## 2. Live grammar / typechecker findings (verified)

| Fact | Evidence |
|---|---|
| match arm body = **single expression** | `parser.rs` `parse_match_arm_inner`: `body = self.parse_expr()` |
| if/else branches **are blocks** | `parse_if_expr`: `then = self.parse_block_body()` |
| `BlockBody` already supports **`let` stmts + a return expr** | `BlockBody { stmts: Vec<Stmt>, return_expr }`; `parse_block_body` loops on `let` → `parse_let_stmt`, else expr-stmt; last expr = `return_expr` |
| `let` syntax already parses | `parse_let_stmt`: `let <name> = <expr>` → `Stmt::Let { name, expr }` |
| **but `let` does NOT bind** | a contract with `if x==1 { let a = x  a } else { 0 }` → **`OOF-P1: Unresolved symbol: a`**; the same contract without `let` (`{ x }`) → **`status: ok`** |
| typechecker only reads let *exprs*, never registers the *name* | `typechecker.rs` handles `Stmt::Let { expr, .. }` solely via `collect_expr_escape_refs` (escape analysis); no scope insertion |
| `{` in **expression** position is record-only | `parse_record_or_block` always parses `key: value` → `Expr::RecordLiteral` (never a block) |
| **no `.ig` fixture uses `let`** | `rg "let " --glob '*.ig'` → none — which is why the latent scope bug went unnoticed |
| emitter already lowers a `BlockBody` | `emitter.rs:188` "the body (BlockBody {stmts, return_expr}) is lowered to a right-nested chain" |

**So:** the machinery (`let`, `BlockBody`, block lowering) is ~80% present and used by if/else, but the
binding never reaches scope, and match arms can't use a block at all.

## 3. Which app cases are blocked (Q1)

- **Multi-`via` / nested guards (P20):** built-in `Result`'s success field is the fixed name `value`, so
  nesting `match gA { Ok { value } => match gB(value) { Ok { value } => … } }` **shadows** the outer
  `value` — the handler in the inner arm cannot see the first context. P20 had to narrow to single-`via`.
- **Context accumulation:** building one record from several intermediate computations inside a single arm
  (no place to name the intermediates).
- **Any arm needing >1 step** — currently forced into extra contracts (composite-guard workaround, P22).

These are **hard blocks** (shadowing), not mere verbosity (Q8).

## 4. Alternatives (Q2)

| # | Form | Verdict |
|---|---|---|
| **A** | **block arm with local `let`/compute** `=> { let ctx = … ; <expr> }` | **RECOMMEND** — reuses existing `BlockBody`+`let`; only new surface is "arm may be a block"; most Igniter-native |
| B | `let … in …` expression | reject — a *second* binding form competing with block `let` |
| C | `where` suffix | reject — awkward with multiple bindings; new construct |
| D | pattern alias `Ok { value as account }` | **partial** — solves *renaming/shadowing* but not multi-step computation; consider as a **complement** to A if cheap |
| E | do nothing (bless composite-guard) | reject — P20/P21/P22 show the workaround cost is real and recurring |

A is smallest because the building blocks already exist; the implementation is **fix `let` scope + accept a
block as an arm body**, not invent a construct.

## 5. Recommended v0 syntax & lowering (Q3)

```ig
match guard {
  Ok { value } => {
    let account = value                 -- branch-local binding; renames the fixed `value`
    let summary = call_contract("Summarize", account)
    call_contract("Handler", req, account, summary)   -- final expr = the arm's value
  }
  Err { error } => error
}
```

**Lowering:** a `let name = expr` lowers to a **named intermediate graph node** — exactly the shape a
top-level `compute name = expr` already produces — scoped to the block; the block's `return_expr` (and later
stmts) reference it by name. The block lowers to the emitter's existing right-nested chain (`emitter.rs:188`)
terminating in the return expr. **No new SIR node kind** (reuse the compute/binding node); **SIR parity:**
`{ let a = e  f(a) }` must lower identically to `f(e)` inlined (pure, so referentially transparent — the
parity test).

**No ordered effects / hidden authority (Q4):** a `let` is a pure named subexpression in the DAG — only data
dependency, no IO/effect/dispatch/sequencing. Determinism, replay, and receipts are untouched (P0 rule).

## 6. Scoping & shadowing (Q5, Q6)

- **Scope:** a `let` is visible only within its block, *after* its declaration (including the return expr
  and later `let`s). Outer names remain visible unless shadowed.
- **Duplicate `let` in one block** → **hard error** (`OOF-LET-DUP` or reuse an existing rule).
- **Shadowing an outer name** → **allowed but warned** (a soft diagnostic): it is pure/deterministic so not
  unsafe, but the warning prevents the silent-capture footgun. (The via case prefers *distinct* names —
  `account`/`project` — so it never relies on shadowing.)

## 7. Result/Option interaction (Q7) — the unlock

`match r { Ok { value } => { let x = value  … } Err { error } => error }` — the `let x = value`
**immediately renames** Result's fixed `value` to a distinct name, so a nested inner `match … { Ok { value }
… }` no longer collides. This is precisely what lets **multi-`via` work over the built-in `Result`** without
bespoke per-guard variants — a hard block becomes expressible (Q8: it **unlocks**, not just prettifies).

## 8. Acceptance tests for the implementation slice (Q9)

1. **parser:** a match arm accepts a `{ let … ; <expr> }` block; an if-branch block with `let` parses.
2. **typecheck (the bug fix):** `if x==1 { let a = x  a } else { 0 }` resolves `a` and compiles **clean**
   (today it is `OOF-P1`); a `let` name is in scope for later stmts + the return expr.
3. **duplicate let** in one block → `OOF` error; **outer-shadow** → soft diagnostic.
4. **emitter / SIR parity:** `{ let a = e  f(a) }` lowers to the same SIR as `f(e)` (pure inlining); **no new
   SIR node kind** introduced.
5. **VM end-to-end:** a contract using a block+`let` in a match arm evaluates to the expected value.
6. **the P20 multi-`via` shape** (`Ok { value } => { let account = value  match gB(account) { Ok { value } =>
   { let project = value  handler(req, account, project) } Err { error } => error } } …`) compiles + runs.
7. **non-web fixture:** an arithmetic accumulation (`match … => { let a = …  let b = …  a + b }`).
8. existing `match`/`if`/`Result`/`Option` fixtures stay green; `git diff --check` clean.

## 9. Non-goals (Q10 scope guard)

No `let … in` / `where`; no pattern-alias overhaul (D may ride along only if trivial); no user-generic type
changes; **no multi-`via` implementation** (a downstream card that *benefits* from this); no new effect/
capability semantics; no `.igweb` parser change beyond examples; no canon claim.

## 10. Smallest implementation card (Q10)

**`LAB-LANG-MATCH-ARM-BINDINGS-P2`** (implementation-proof):
1. **Fix `let`-binding scope resolution** in `BlockBody` typecheck/emit (the load-bearing part — today
   `OOF-P1: Unresolved symbol`); prove if-branch `let` compiles + runs.
2. **Accept a block as a match-arm body** (reuse `parse_block_body`).
3. Tests per §8, incl. one multi-guard/`via` fixture and one non-web (arithmetic) fixture; SIR-parity test.

The bug fix is the bulk; the grammar add is small. Both stay within the P0 discipline (lowers to existing
SIR, no new node kind, no authority).

---

*Readiness/design only. Compiled 2026-06-20; grounded in live `parser.rs` (match-arm = single expr;
`BlockBody`+`parse_let_stmt` in if/else; `{`-expr = record-only), `typechecker.rs` (`let` expr read for
escape analysis only — name never bound), and an empirical probe (`OOF-P1: Unresolved symbol: a` for
let-in-if). The ceiling is a half-built `let`: fix its scope + let match arms be blocks. No code change.*
