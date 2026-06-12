# LAB-OUTPUT-TYPE-PARAMETER-CHECK-P1 — Output Type Parameter Check Safety Proof

**Track:** lab / safety  
**Route:** SAFETY PROOF / GAP DOCUMENTATION  
**Status:** CLOSED — PROVED 38/38 — READY FOR IMPLEMENTATION PLANNING  
**Date:** 2026-06-12  
**Predecessor:** LAB-UNKNOWN-OUTPUT-COERCION-P1

---

## Goal

Safety follow-up after LAB-UNKNOWN-OUTPUT-COERCION-P1. Scope: proof-local fixtures
only. Compare scalar vs parametric output assignability in both TypeCheckers. Identify
whether outer-name-only `type_name()` is the sole cause. Recommend structural
assignability rule. Verdict: HOLD / READY FOR IMPLEMENTATION PLANNING.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-lang/experiments/output_type_parameter_check_proof/verify_output_type_parameter_check_p1.rb` | 38/38 PASS |
| Governance doc | `igniter-lang/.agents/work/proposals/LAB-OUTPUT-TYPE-PARAMETER-CHECK-P1-output-type-parameter-gap-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/lab/LAB-OUTPUT-TYPE-PARAMETER-CHECK-P1.md` | Written |
| Portfolio entry | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Verdict: PROVED 38/38 — READY FOR IMPLEMENTATION PLANNING

```
Result: 38/38 PASS
VERDICT: PASS — LAB-OUTPUT-TYPE-PARAMETER-CHECK-P1

Root cause: type_name() reads only the outer 'name' field of a type hash.
  Collection[Integer] vs Collection[Text] => both 'Collection' => SILENT
  Map[String,Integer] vs Map[String,Text]  => both 'Map'        => SILENT
  The gap is NOT Unknown-specific: any parametric mismatch is silent.

Scope of silent gap at output boundary:
  Unknown -> T (scalar)                           SILENT in Rust (LAB-RACK-P9)
  Collection[Unknown] -> Collection[T]            SILENT in Ruby and Rust
  Collection[T1] -> Collection[T2] (T1 != T2)    SILENT in Ruby and Rust  <-- NEW
  Collection[Foo] -> Collection[Bar]              SILENT in Ruby and Rust  <-- NEW
  Map[K,V1] -> Map[K,V2]                          SILENT in Ruby and Rust  <-- NEW
  nested Collection[Collection[T1->T2]]           SILENT in Ruby and Rust  <-- NEW

Recommendation: structurally_assignable?(actual, expected)
  1. Unknown-permissive at depth 0 (preserve LAB-RACK-P9 for both TCs)
  2. Outer name must match
  3. All params must be recursively structurally_assignable?
  Fix: 2 files, ~20 lines each. element_type_from_collection already in Ruby TC.
  OOF: extend OOF-TY0 or add OOF-TY1 (planning-card decision).

Next route: LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 — implementation planning
```

---

## Proof Matrix (38 checks / 11 sections)

| Section | Topic | Checks | Result |
|---------|-------|--------|--------|
| A | Scalar Unknown → T (Ruby CAUGHT / Rust SILENT LAB-RACK-P9) | 3 | 3/3 PASS |
| B | Collection[Unknown] → Collection[T] (P1 confirmed) | 3 | 3/3 PASS |
| C | Collection[T1] → Collection[T2] — both known types | 5 | 5/5 PASS |
| D | Map[K,V1] → Map[K,V2] | 4 | 4/4 PASS |
| E | Nested parametric types | 4 | 4/4 PASS |
| F | type_name() outer-name-only: confirmed as sole cause | 5 | 5/5 PASS |
| G | blocking_rule_present? does not suppress output check | 3 | 3/3 PASS |
| H | element_type_from_collection exists, not wired in output check | 3 | 3/3 PASS |
| I | Rust TC parity — same outer-name-only pattern | 3 | 3/3 PASS |
| J | Structural assignability rule recommendation | 3 | 3/3 PASS |
| K | Verdict — READY FOR IMPLEMENTATION PLANNING | 2 | 2/2 PASS |

---

## Key Technical Findings

### Wider Than P1

P1 (LAB-UNKNOWN-OUTPUT-COERCION-P1) identified the gap for `Collection[Unknown]`.
This card proves the gap is NOT `Unknown`-specific. `Collection[Integer] → Collection[Text]`
is equally silent. The TypeChecker treats `Collection[Integer]` and `Collection[Text]` as
the same type at the output boundary.

### Root Cause: Single Line in Each TC

**Ruby TC (line 413):**
```ruby
if type_name(actual) != type_name(expected) && !blocking_rule_present?(type_errors)
```
`type_name` → `type.fetch("name")` (line 1358) — ignores `"params"` entirely.

**Rust TC (lines 1236-1237):**
```rust
if self.type_name(&actual) != self.type_name(&expected)
    && self.type_name(&actual) != "Unknown"
```
Same outer-name-only pattern. Rust additionally silences scalar `Unknown` via LAB-RACK-P9.

### Existing Infrastructure

`element_type_from_collection` (Ruby TC, line 1857) already reads `params[0]`.
It is called in `for_loop` and `budgeted_loop` type propagation but not wired into
the output boundary check. It can be reused or adapted for the fix.

### Blocking Guard Not the Cause

`blocking_rule_present?` does NOT include `OOF-TY0`. For
`Collection[Integer] → Collection[Text]` there are zero preceding errors — nothing
to block. The output check runs and silently passes.

---

## Recommended Rule

```ruby
def structurally_assignable?(actual, expected)
  return true if type_name(actual) == "Unknown"
  return false if type_name(actual) != type_name(expected)
  actual_params   = actual.fetch("params", [])
  expected_params = expected.fetch("params", [])
  return false if actual_params.length != expected_params.length
  actual_params.zip(expected_params).all? { |a, e| structurally_assignable?(a, e) }
end
```

Replace output check condition:  
`type_name(actual) != type_name(expected)` → `!structurally_assignable?(actual, expected)`

---

## Open for P2 (Planning-Card Decisions)

1. Unknown-permissive depth policy (depth-0 only vs all depths)
2. OOF code: extend OOF-TY0 with better message vs add OOF-TY1
3. Map multi-param: K-mismatch vs V-mismatch as separate diagnostics
4. Ruby Unknown strictness alignment with Rust

---

## Authority Closed

No changes to any source file. No new OOF codes. No dynamic dispatch proposal.
No plugin model changes. No runtime validation receipt design.

---

## Next Route

**LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2** — implementation planning  
Scope: decide Unknown-permissive policy, OOF code, implement `structurally_assignable?`
in both TCs, write regression proof runner.
