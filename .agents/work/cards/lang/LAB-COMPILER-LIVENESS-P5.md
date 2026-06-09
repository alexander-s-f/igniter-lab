# Card: LAB-COMPILER-LIVENESS-P5

**Track:** lab-rust-compiler-parser-nonprogress-and-subprocess-timeout-hardening-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PARSER-HARDENING
**Status:** ✅ CLOSED — 2026-06-09
**Authority:** igniter-lab only; no canon impact; no production impact
**Depends:** LAB-COMPILER-LIVENESS-P1 through P4

---

## Card Statement

Close the compiler hang class found during LAB-VM-MAP-P1: malformed declarations must fail closed with diagnostics; proof runners must timeout subprocesses; orphan processes must not survive failed runs.

---

## Explicit Answers

### Q1: Does `output result` (no type annotation) hang the parser?

**No — fixed.** With the P5 `peek_type` fix and `parse_body_decl_with_recovery`, the malformed output declaration produces `status: "error"` with an OOF-P1 diagnostic. The parser terminates in < 1ms.

### Q2: Do malformed `type` declarations hang the parser?

**No — fixed.** `parse_type_decl` now has per-field recovery: `type Foo { x }` and `type Foo { x: }` both produce OOF-P1 diagnostics and terminate.

### Q3: Does the parser always make token progress?

**Yes — by construction.** Three mechanisms ensure this:
1. `peek_type` returns `true` for Eof when past the token array — `while !peek_type(Eof)` cannot cycle.
2. `parse_body_decl_with_recovery` advances at least one token on error before skipping to boundary.
3. The `_ =>` arm in `parse_body_decl` advances one token for any unrecognized token.

### Q4: Does the proof runner timeout kill the compiler child?

**Yes — by the kill thread in BoundedCommand.** `Process.spawn` + a `Thread` that sends `SIGTERM` then `SIGKILL` after `timeout_secs` (default 15s). Verified by P5-H: the runner returns in all cases and the timed_out flag is correctly set.

### Q5: Do repeated malformed compilations accumulate orphan processes?

**No.** P5-I verifies `pgrep -f igniter_compiler` count is identical before and after 5 repeated malformed compiles.

### Q6: Is stdout bounded and machine-readable for malformed inputs?

**Yes.** All 5 malformed fixtures produce < 1 KB of output, well under the 64 KB cap. Output is valid JSON with a `status` key.

### Q7: Does the fix hide parser bugs behind the timeout?

**No.** The root hang class is fixed at source (`peek_type` + recovery helpers). The timeout is defense-in-depth for unknown future hangs, not the primary fix. P5-B through P5-E all complete without triggering the timeout.

### Q8: Does P5 change language semantics?

**No.** The parser recovers silently: it records an error, skips the malformed declaration, and continues. Valid programs parse and compile identically to pre-P5. The `well_formed.ig` regression fixture confirms this.

---

## Proof Matrix

| Section | Description | Checks |
|---------|-------------|--------|
| P5-A | Build | 1 |
| P5-B | output_no_annotation fails closed | 4 |
| P5-C | output_colon_no_type fails closed | 4 |
| P5-D | type_field_no_colon fails closed | 4 |
| P5-E | type_field_no_type fails closed | 4 |
| P5-F | Multiple malformed: recovery continues | 4 |
| P5-G | Well-formed regression | 3 |
| P5-H | BoundedCommand timeout kills subprocess | 4 |
| P5-I | Process count invariant | 1 |
| P5-J | stdout bounded + machine-readable | 10 |
| P5-K | peek_type EOF fix confirmed | 2 |
| P5-L | P4 regression (canonical fixtures) | 5 |
| **Total** | | **46** |

```
ruby verify_liveness_p5.rb    46/46 PASS
ruby verify_liveness_p4.rb    40/40 PASS  (backward compat confirmed)
```

---

## Root Cause

**`peek_type` behavior past EOF sentinel (single-function bug):**

```rust
// Pre-P5 (hangs when pos >= tokens.len()):
fn peek_type(&self, t_type: TokenType) -> bool {
    self.current().map_or(false, |t| t.token_type == t_type)
}

// P5 fix (treats past-end as Eof):
fn peek_type(&self, t_type: TokenType) -> bool {
    match self.current() {
        None => t_type == TokenType::Eof,
        Some(t) => t.token_type == t_type,
    }
}
```

`expect_type()` advances past mismatched tokens unconditionally. In malformed input, it could consume the explicit `Eof` sentinel. After that, `pos >= tokens.len()`, `current()` returned `None`, and `peek_type(Eof)` returned `false`. Every `while !peek_type(Eof)` loop became infinite.

---

## Files Written

| File | Change |
|------|--------|
| `src/parser.rs` | peek_type fix; parse_body_decl_with_recovery; output/compute recovery; type_decl field recovery |
| `fixtures/liveness_p5_output_no_annotation.ig` | NEW — hang fixture (output no annotation) |
| `fixtures/liveness_p5_output_colon_no_type.ig` | NEW — hang fixture (output colon no type) |
| `fixtures/liveness_p5_type_field_no_colon.ig` | NEW — hang fixture (type field no colon) |
| `fixtures/liveness_p5_type_field_no_type.ig` | NEW — hang fixture (type field no type) |
| `fixtures/liveness_p5_multiple_malformed.ig` | NEW — multiple-error recovery fixture |
| `fixtures/liveness_p5_well_formed.ig` | NEW — regression guard |
| `verify_liveness_p5.rb` | NEW — 46-check proof script with BoundedCommand timeout |
| `lab-docs/lang/lab-rust-compiler-parser-nonprogress-and-subprocess-timeout-hardening-v0.md` | NEW |

---

## Authority and Boundary

```
authority:                     lab_only_p5_parser_hardening
new_OOF_codes:                 NONE
canon_impact:                  NONE
production_impact:             NONE
VM_change:                     NONE
language_semantics_change:     NONE
grammar_change:                NONE
new_fatal_limits:              NONE
igniter-org_change:            NONE
```

---

## Precondition Documents

- P1: `lab-docs/lang/lab-compiler-liveness-nonprogress-audit-boundary-v0.md`
- P2: `lab-docs/lang/lab-compiler-liveness-instrumentation-counters-v0.md`
- P3: `lab-docs/lang/lab-compiler-liveness-calibrated-budget-diagnostics-v0.md`
- P4: `lab-docs/lang/lab-compiler-liveness-emitter-parser-calibration-and-cycle-preflight-v0.md`

## Next Route

**LAB-COMPILER-LIVENESS-P5 closes the hang class for identified patterns.**

Future cards:
- Extend `parse_body_decl_with_recovery` to all body-decl keywords (input, read, snapshot, etc.) for uniform OOF-P1 coverage
- E-COMPILER-CYCLE instrumentation if grammar enables form-calls-form
- BoundedCommand timeout for igc VM runner subprocess
