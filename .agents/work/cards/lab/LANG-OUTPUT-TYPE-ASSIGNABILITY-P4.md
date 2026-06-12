# LANG-OUTPUT-TYPE-ASSIGNABILITY-P4

**Status:** CLOSED — RUST PARITY PROOF — 45/45 PASS
**Track:** lang / typechecker / output-boundary
**Route:** IMPLEMENTATION PROOF
**Date:** 2026-06-12
**Grounding:** LANG-OUTPUT-TYPE-ASSIGNABILITY-P1/P2/P3 + APP-RECHECK-WAVE-P2
**Prev:** LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 (Ruby 70/70)

---

## Goal

Rust TC parity for structural output type assignability. Implement `structurally_assignable()`
and `type_display()` in `typechecker.rs`, replace the output boundary OOF-TY0 block
(including LAB-RACK-P9 guard) with OOF-TY1, and prove 45 checks.

---

## Scope

- `igniter-lab/igniter-compiler/src/typechecker.rs` — two new methods + output boundary
- `igniter-lab/igniter-compiler/verify_output_type_assignability_p4.rb` — 45-check proof runner
- Output boundary only. No Ruby changes. No parser, emitter, assembler, or VM changes.

---

## Changes

### Output boundary (lines ~1231–1245) — REPLACED

```rust
// BEFORE: LAB-RACK-P9 guard + outer-name-only OOF-TY0
if self.type_name(&actual) != self.type_name(&expected)
    && self.type_name(&actual) != "Unknown"
    && !self.blocking_rule_present(&type_errors) {
    type_errors.push(ClassifierDiagnostic {
        rule: "OOF-TY0".to_string(),
        message: format!("Type mismatch: expected {}, got {}",
                         self.type_name(&expected), self.type_name(&actual)),
        ...
    });
}

// AFTER: structural check + OOF-TY1
if !self.structurally_assignable(&actual, &expected)
    && !self.blocking_rule_present(&type_errors) {
    type_errors.push(ClassifierDiagnostic {
        rule: "OOF-TY1".to_string(),
        message: format!("Output type mismatch: expected {}, got {}",
                         self.type_display(&expected), self.type_display(&actual)),
        ...
    });
}
```

### New methods (inserted after `fn type_name`)

```rust
fn structurally_assignable(&self, actual: &serde_json::Value, expected: &serde_json::Value) -> bool {
    if self.type_name(expected) == "Unknown" { return true; }   // D3
    if self.type_name(actual) == "Unknown"   { return false; }  // D2
    if self.type_name(actual) != self.type_name(expected) { return false; }
    let actual_params = actual.get("params").and_then(|p| p.as_array()).cloned().unwrap_or_default();
    let expected_params = expected.get("params").and_then(|p| p.as_array()).cloned().unwrap_or_default();
    if actual_params.len() != expected_params.len() { return false; }
    actual_params.iter().zip(expected_params.iter()).all(|(a, e)| {
        self.structurally_assignable(&self.type_ir(a), &self.type_ir(e))
    })
}

fn type_display(&self, type_info: &serde_json::Value) -> String {
    let name = self.type_name(type_info);
    let params = type_info.get("params").and_then(|p| p.as_array()).cloned().unwrap_or_default();
    if params.is_empty() { return name; }
    let rendered: Vec<String> = params.iter().map(|p| self.type_display(&self.type_ir(p))).collect();
    format!("{}[{}]", name, rendered.join(","))
}
```

---

## Decision D6 Implemented

LAB-RACK-P9 guard (`&& self.type_name(&actual) != "Unknown"`) removed from Rust TC output
boundary. The guard is superseded by D2 in `structurally_assignable()`:
- D2: `actual Unknown → false` at all depths replaces the shallow guard
- D3: `expected Unknown → true` preserves Unknown-permissive semantics where declared

---

## Proof

**Runner:** `igniter-lab/igniter-compiler/verify_output_type_assignability_p4.rb`
**Result:** 45/45 PASS

| Section | Topic | Checks |
|---------|-------|--------|
| B | Source structure: methods in TC_RS | 6 |
| C | OOF-TY1: outer name mismatch | 5 |
| D | OOF-TY1: actual Unknown scalar + Collection depth | 6 |
| E | OOF-TY1: param mismatch, same outer container | 5 |
| F | OOF-TY1: nested parametric types | 4 |
| G | Permissive PASS — no OOF-TY1 | 5 |
| I | rule_engine blocked (LAB-RACK-P9 gone) | 5 |
| J | Regression — prior PASS contracts unaffected | 5 |
| K | OOF-TY0 NOT at output boundary; LAB-RACK-P9 removed | 4 |

---

## Safety-Positive Evidence

`rule_engine ExecuteRules` — `active_decisions : Collection[RuleDecision]` where actual is
`Collection[Unknown]` — now emits OOF-TY1 in the Rust TC.

Previously SILENT via LAB-RACK-P9 guard: `self.type_name(&actual) != "Unknown"` was false
for `Unknown`, so the outer-name check was skipped. For `Collection[Unknown]`, the outer
name is `Collection` (not `Unknown`), so the LAB-RACK-P9 guard didn't help either — that
was the deeper silence.

Both silences are now resolved:
- Scalar Unknown → D2 in `structurally_assignable()` → false → OOF-TY1
- Collection[Unknown] → recursion → D2 at depth-1 → false → OOF-TY1

---

## Non-Goals

- No Ruby TC changes (P3 handles Ruby)
- No dynamic dispatch feature
- No validation receipt design
- No VM or runtime changes
