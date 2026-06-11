# lab-ruby-function-recursion-parity-proof-v0

**Track:** ruby-canon / recursion parity
**Lane:** LAB PROOF / BOUNDED IMPLEMENTATION
**Status:** CLOSED — PASS 52/52
**Date:** 2026-06-11
**Proof runner:** `igniter-lang/experiments/function_recursion_proof/verify_lab_ruby_function_recursion_p1.rb`
**Predecessor:** LAB-FUNCTION-RECURSION-P1 (OOF-L4 canonical in Rust; self-recursive def function gate)

---

## Research Question

Does the Ruby canon pipeline implement OOF-L4 parity with the Rust typechecker for
self-recursive `def` functions? If not, what is the minimal bounded change?

---

## Answer

**No** — prior to this work, the Ruby pipeline had three gaps:

1. **Parser**: did not parse `decreases fuel` on `def` function declarations (parse error)
2. **Classifier**: did not propagate `functions` array from parsed program to classified result
3. **Typechecker**: had no OOF-L4 check for self-recursive `def` functions

All three gaps are now closed. Ruby emits OOF-L4 for self-recursive `def` functions missing
`decreases fuel`, matching Rust behavior at `typechecker.rs:357-370`.

---

## Authorized Changes

| File | Change | Size |
|------|--------|------|
| `igniter-lang/lib/igniter_lang/parser.rb` | Parse `decreases fuel` in `parse_function_decl` | ~15 lines |
| `igniter-lang/lib/igniter_lang/classifier.rb` | Propagate `functions` to classified program | ~3 lines |
| `igniter-lang/lib/igniter_lang/typechecker.rb` | OOF-L4 check + `fn_self_recursive?` + `fn_body_has_call?` + `fn_expr_has_call?` | ~45 lines |

All three files pass `ruby -c`.

---

## Parser Change: `parse_function_decl`

The `decreases fuel` annotation goes between the return type and the opening `{`:

```
def name(params) -> ReturnType decreases fuel { body }
```

`fuel` is an `:ident` token (not in KEYWORDS — only `fuel_bounded` is a keyword).
The parser reads `decreases` as a keyword lookahead, then reads the following token as the
evidence label. The `decreases` key is added to the function AST node only when present.

---

## Classifier Change

The classifier now passes `functions` from the parsed program through to the classified
result (same pattern used for `contracts`). Without this, the typechecker received an
empty functions array regardless of what was parsed.

---

## Typechecker Change

Three new private methods implement self-call detection, mirroring Rust `is_recursive()`:

- `fn_self_recursive?(fn)` — entry point; extracts body and name, delegates to body walker
- `fn_body_has_call?(body, fn_name)` — walks `stmts` array and `return_expr` in a block
- `fn_expr_has_call?(expr, fn_name)` — dispatches on expr kind:
  - `call`: checks `fn` key (not `fn_name` — Ruby AST uses `"fn"`)
  - `binary_op`: recurse left + right
  - `unary_op`: recurse operand
  - `field_access` / `index_access`: recurse object (and index)
  - `if_expr`: recurse cond, then-block (`"then"` key), else-block (`"else"` key)
  - default: false

The check is self-only, matching current Rust behavior (mutual recursion detection is a
separate P3 track). The `"fn"` key and `"if_expr"/"then"/"else"` keys are Ruby AST
conventions confirmed from fixture round-trips.

---

## Fixture Inventory

| File | State | Purpose |
|------|-------|---------|
| `fixtures/non_recursive.ig` | Clean | Baseline: no def functions → 0 errors |
| `fixtures/self_recursive_no_evidence.ig` | OOF-L4 expected | `factorial` without `decreases fuel` |
| `fixtures/self_recursive_with_fuel.ig` | Clean | `factorial` + `count_down` both with `decreases fuel` |
| `fixtures/non_recursive_caller.ig` | Clean | `five_factorial` calls `factorial` (recursive) but is not itself recursive |

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Parser | 8 | `decreases fuel` parsed; round-trip preserved; no parse error with/without annotation |
| B — Classifier | 7 | `functions` propagated; count correct; `decreases` key preserved |
| C — Typechecker | 11 | OOF-L4 emitted for bare recursion; not emitted with fuel; exact message format |
| D — Regression | 7 | Contract OOF-R* unaffected; loop contracts unaffected; no spurious OOF-L4 on non-recursive functions |
| E — Parity | 7 | Message identical to Rust; rule code is "OOF-L4"; non-recursive caller safe |
| F — Traversal | 7 | `fn_expr_has_call?` hits call/binary_op/if_expr/nested paths; no false positives |
| G — Authority | 5 | No mutual recursion; no VM; no max_steps; no new OOF code; no Rust changes |

**Total: 52/52 PASS**

---

## Scoping Decisions

| Question | Answer |
|----------|--------|
| Self-recursive `def` functions: OOF-L4 on missing `decreases fuel`? | YES — implemented |
| Mutual recursion (SCC-level) detection? | NO — separate track (LAB-FUNCTION-RECURSION-P3) |
| `max_steps` requirement for `def` functions? | NO — HOLD from P1; not gated here |
| New OOF diagnostic codes? | NO — OOF-L4 is canonical; no new codes introduced |
| Contract-level OOF-R* codes affected? | NO — regression confirmed (D-01..D-07) |
| Ruby `ruby -c` pass? | YES — all three modified files |

---

## Pre-existing Gap (Not Caused By This Work)

`source/loops_and_recursion.ig` uses old loop syntax `loop Name in source` but the
current Ruby parser grammar is `loop Name item in source max_steps: N { body }`.
This file fails to parse today. It is not caused by these changes and is separate work.

---

## Open Questions for P3

1. Should Ruby also implement SCC-level mutual recursion detection (Tarjan's algorithm)?
2. What canonical OOF code covers mutual recursion gap in Ruby (OOF-L4-MUTUAL vs extend OOF-L4)?
3. Should `decreases fuel` on `def` functions require `max_steps N` in Ruby (parity with fuel_bounded contract)?

---

## Authority Closed

Mutual recursion detection / SCC classification / VM runtime / Rust typechecker changes /
max_steps enforcement for def functions / new OOF diagnostic codes / spreadsheet app edits /
stdlib changes / parser syntax additions beyond `decreases fuel`.
