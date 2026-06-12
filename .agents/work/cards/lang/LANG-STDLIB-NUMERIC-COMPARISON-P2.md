# LANG-STDLIB-NUMERIC-COMPARISON-P2 — Numeric Comparison Operators Implementation Planning

**Track:** lang / stdlib / numeric / comparison  
**Route:** IMPLEMENTATION PLANNING / NO IMPLEMENTATION  
**Status:** CLOSED — PLANNING COMPLETE  
**Date:** 2026-06-12  
**Predecessor:** LANG-STDLIB-NUMERIC-COMPARISON-P1 (37/37 PASS)

---

## Goal

Produce a concrete, file-specific implementation plan for `<`, `<=`, `>=` (and promotion of existing `>`): insertion points in Ruby TC, Ruby emitter, Rust TC; inventory promotion plan; SIR qualification gap disposition; proof matrix for P3.

No implementation.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Planning doc | `igniter-lang/.agents/work/proposals/LANG-STDLIB-NUMERIC-COMPARISON-P2-implementation-planning-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/lang/LANG-STDLIB-NUMERIC-COMPARISON-P2.md` | Written |
| Portfolio entry | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Decision: Ruby + Rust in P3 (no split)

Rust gap is only 2 arms (`<=`, `>=`). Ruby gap is 3 arms (`<`, `<=`, `>=`). Both toolchains complete in a single P3 implementation card — no P4 split.

---

## Authorized Files

| File | Phase | Change |
|------|-------|--------|
| `igniter-lang/lib/igniter_lang/typechecker.rb` | P3 | 3 `when` arms in `operator_type` (~9 lines) |
| `igniter-lang/lib/igniter_lang/semanticir_emitter.rb` | P3 | 3 `when` arms in `operator_for` pre-TC path (~12 lines) |
| `igniter-lab/igniter-compiler/src/typechecker.rs` | P3 | 2 match arms in `operator_type` (~24 lines) |
| `igniter-lang/docs/spec/stdlib-inventory.json` | P3 | Promote `gt` + add `lt`/`lte`/`gte` |

---

## Key Findings

### Ruby TC (`typechecker.rb`)

Insertion after line 1207 (`["stdlib.integer.gt", type_ir("Bool")]`), before `when "&&"`:

```ruby
when "<"
  type_errors << type_mismatch(type_ir("Integer"), type_ir("#{left_name}<#{right_name}"), node_name) unless unknown?(left, right) || left_name == "Integer" && right_name == "Integer"
  ["stdlib.integer.lt", type_ir("Bool")]
when "<="
  type_errors << type_mismatch(type_ir("Integer"), type_ir("#{left_name}<=#{right_name}"), node_name) unless unknown?(left, right) || left_name == "Integer" && right_name == "Integer"
  ["stdlib.integer.lte", type_ir("Bool")]
when ">="
  type_errors << type_mismatch(type_ir("Integer"), type_ir("#{left_name}>=#{right_name}"), node_name) unless unknown?(left, right) || left_name == "Integer" && right_name == "Integer"
  ["stdlib.integer.gte", type_ir("Bool")]
```

### Ruby SIR Emitter (`semanticir_emitter.rb`)

Typed path (`semantic_expr`): **NO CHANGE** — TC converts `binary_op` → `call { fn: "stdlib.integer.lt" }` before emitter. Ruby SIR output: `call { fn: "stdlib.integer.lt", resolved_type: Bool, args: [...] }`.

Pre-TC path (`operator_for`): insertion after line 1004 (`["stdlib.integer.gt", "Bool"]`), before `when "&&"` — same three arms using `unknown_type?` guard.

### Rust TC (`typechecker.rs`)

Insertion after line 4183 (closing `}` of `"<"` arm), before `_ =>`. `<=` and `>=` only — Rust already has `<` at line 4170. Pattern matches existing `"<"` arm exactly: `(left_name != "Integer" || right_name != "Integer") && left_name != "Unknown" && right_name != "Unknown"` guard.

### SIR Qualification Gap — EXPLICITLY DEFERRED

Rust emitter outputs `binary_op { "op": "<=" }` (raw symbol). Ruby outputs `call { "fn": "stdlib.integer.lte" }` (qualified name). Gap exists today for `>` (P1 D-03/D-04 baseline). Not a TC correctness blocker. Deferred to separate SIR emitter qualification card.

### Inventory

| Entry | Action |
|-------|--------|
| `stdlib.integer.gt` | Promote: `orphaned/sketch` → `lab-implemented/stable`; add `diagnostics: ["OOF-TY0"]` |
| `stdlib.integer.lt` | ADD: `lab-implemented`, `dual-toolchain` (Rust already live; Ruby added in P3) |
| `stdlib.integer.lte` | ADD: `lab-implemented`, `dual-toolchain` |
| `stdlib.integer.gte` | ADD: `lab-implemented`, `dual-toolchain` |

### App Pressure Resolved

- `arch_patterns/pipeline.ig:30,108` — `amount < 1`, `balance < amount`: Ruby OOF-TY0 cleared
- `neural_net/activations.ig:26` — `x < (0 - 2500)` sigmoid: Ruby OOF-TY0 cleared
- `vector_math/geometry.ig:38-41` — explicit `>=` workaround with nested `<`/`>` pairs: workaround continues to compile; native `>=` available for future cleanup

---

## Proof Matrix Summary

| Card | Target | Sections | Key topics |
|------|--------|---------|-----------|
| P3 | ≥42 checks / 9 sections | A: regression / B: Ruby `<` happy / C: Ruby `<=` + `>=` happy / D: Rust `<=` + `>=` happy / E: OOF-TY0 guards / F: Unknown permissive / G: SIR shape / H: app fixtures / I: inventory |

---

## Authority Closed

No parser changes. No Rust emitter changes. No VM. No new OOF codes. No Decimal. No unary operators. No `==` changes.

---

## Next Routes

| Card | Scope |
|------|-------|
| **LANG-STDLIB-NUMERIC-COMPARISON-P3** | Ruby + Rust implementation + proof ≥42 PASS |
