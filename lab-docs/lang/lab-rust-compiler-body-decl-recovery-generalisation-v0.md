# Lab Doc: Rust Compiler Body-Declaration Recovery Generalisation v0

**Card:** LAB-COMPILER-LIVENESS-P6
**Track:** lab-rust-compiler-body-decl-recovery-generalisation-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PARSER-HARDENING
**Authority:** Lab evidence only. Not canon. Not production.
**Date:** 2026-06-09
**Depends:** LAB-COMPILER-LIVENESS-P5 (peek_type EOF fix; parse_body_decl_with_recovery)
**Status:** Closed — 54/54 PASS

---

## 1. Purpose

P5 introduced `parse_body_decl_with_recovery` and applied it to `output` and `compute` — the two arms identified as hang sources. P6 extends this recovery to every remaining body-declaration keyword that can return `Err` from its inner parser and has no inner `{}` block:

| P5 coverage | P6 adds |
|---|---|
| `output`, `compute` | `input`, `capability`, `effect`, `read`, `snapshot`, `escape`, `stream`, `fold_stream`, `invariant`, `lead`, `max_steps` |

P6 also audits and explicitly classifies the three remaining arms that still use `.ok()`:
- `decreases` — always returns `Ok`; `.ok()` is a semantic no-op, not a silent drop
- `window`, `loop`, `for` — have inner `{}` blocks; deferred to P7 (need `skip_to_matching_brace`)

---

## 2. Audit Findings

### 2.1 `name_token()` always advances on both success and error

A key discovery of this audit: **every helper function that could trigger recovery (`name_token`, `expect_type`, `expect_kw`, `expect_value`) calls `self.advance()` unconditionally before checking the token type.** This means:

- `name_token()` on a non-identifier token: advances, returns `Err`
- `expect_type(Colon)` on a keyword: advances past the keyword, returns `Err`

**Consequence for recovery:** when `input x` (missing colon) is parsed:
1. `name_token()` → advances past "x", returns `Ok("x")`
2. `expect_type(Colon)` → advances past the NEXT token (e.g., "output") → returns `Err`

The next body-boundary keyword is consumed by the failed `expect_type` call. With `parse_body_decl_with_recovery`, the OOF-P1 diagnostic correctly names the consumed token ("Expected Colon, got Keyword(output)"), but the subsequent `output` declaration is lost (it was the consumed token).

**Mitigation:** Use literal tokens (e.g., IntLit `42`) as the malformed element in fixtures where multiple independent failures must be demonstrated. `name_token()` fails immediately on `42` (after consuming it), without consuming the next keyword. `skip_until_body_boundary()` then stops at the next keyword intact.

**P7 opportunity:** A future "peek-first" variant of `expect_type` that only advances when the token matches could preserve the next-keyword boundary in recovery. This is a deeper parser design change deferred to P7.

### 2.2 Arms with inner `{}` blocks — deferred to P7

Three arms have inner brace blocks:

| Arm | Inner block | Problem |
|-----|------------|---------|
| `window` | `window "label" { key: val, ... }` | `skip_until_body_boundary` stops at `{`-block's `}`, not contract's `}` |
| `loop` | `loop name in source { body }` | Same: stops at loop body's closing `}` |
| `for` | `for name item in source { body }` | Same |

For these three, outer recovery would produce misleading parse state: after the inner `}` is consumed by `skip_until_body_boundary`, the parser would try to continue body declarations from inside the loop/window, or mis-consume the contract's closing `}` as content.

**P7 solution:** Implement `skip_to_matching_brace(depth=1)` which tracks brace nesting depth and stops after the matched closing `}`. This allows safe recovery from any depth of inner block.

### 2.3 `decreases` — always `Ok`

`parse_decreases_body_decl` returns `Ok` unconditionally. It falls back to `variant = "unknown"` if no identifier follows — it never calls `expect_type` or `expect_kw`. The `.ok()` arm is equivalent to `Some(decl)` in all code paths. No change needed.

---

## 3. Changes to `parse_body_decl`

All 11 newly-wrapped arms follow the same pattern. For each keyword `K`:

```rust
// Before P6 (silent drop, no diagnostic on Err):
"K" => { self.advance(); self.parse_K_decl().ok() }

// After P6 (OOF-P1 emitted, recovery to next boundary):
"K" => {
    self.advance();
    self.parse_body_decl_with_recovery("K", tok.line, tok.col,
        |p| p.parse_K_decl())
}
```

The `parse_body_decl_with_recovery` helper (introduced in P5) provides:
1. At least one token consumed on error (guaranteed progress)
2. OOF-P1 diagnostic with keyword name and source location
3. `skip_until_body_boundary()` to advance to the next recoverable position

No changes to the inner parser functions — only the dispatch in `parse_body_decl`.

---

## 4. Full Arm Classification After P6

| Arm | P6 status | Inner `{}`? | Notes |
|-----|-----------|-------------|-------|
| `output` | ✅ P5 (already recovered) | No | |
| `compute` | ✅ P5 (already recovered) | No | |
| `input` | ✅ P6 | No | |
| `capability` | ✅ P6 | No | |
| `effect` | ✅ P6 | No | |
| `read` | ✅ P6 | No | Has optional-keyword attribute loop (safe: uses `break`) |
| `snapshot` | ✅ P6 | No | |
| `escape` | ✅ P6 | No | Simplest: just `name_token()` |
| `stream` | ✅ P6 | No | |
| `fold_stream` | ✅ P6 | No | |
| `invariant` | ✅ P6 | No | Has attribute loop (safe: bounded by keyword matching) |
| `lead` | ✅ P6 | No | |
| `max_steps` | ✅ P6 | No | Can Err from `expect_type(IntLit)` |
| `decreases` | ✅ Always Ok | No | `.ok()` retained; documented as semantic no-op |
| `window` | ⏳ P7-deferred | **YES** | Needs `skip_to_matching_brace` |
| `loop` | ⏳ P7-deferred | **YES** | Needs `skip_to_matching_brace` |
| `for` | ⏳ P7-deferred | **YES** | Needs `skip_to_matching_brace` |
| `uses` | ✅ Manual recovery | No | Already had explicit `skip_until_body_boundary` |
| `pipeline`/`step`/`scoped_by`/`tenant_free` | ✅ Manual recovery | No | Already had explicit skip + OOF |
| `_` (unknown) | ✅ Always advances | No | `_ =>` arm always calls `advance()` |

---

## 5. Token-Progress Guarantee After P5+P6

With P5 (`peek_type` EOF fix) and P6 (all non-`{}` arms recovered):

**Statement:** The `parse_body_decl` function makes guaranteed token progress in every code path:

1. `parse_body_decl_with_recovery` arms: on `Err`, advances at least one token + skips to boundary
2. `decreases` arm: `parse_decreases_body_decl` always returns `Ok` after consuming at least the first token (or immediately if nothing to parse)
3. `window`, `loop`, `for`: inner parsers always advance on both success and error (all helpers call `advance()` unconditionally)
4. `uses`: explicit `advance()` or `skip_until_body_boundary()`
5. `pipeline`/`step`/`scoped_by`/`tenant_free`: explicit `skip_invalid_body_decl()`
6. `_ =>`: explicit `advance()`

**Combined with the P5 `peek_type` EOF fix:** no `while !peek_type(Eof)` loop can cycle.

---

## 6. Proof Matrix

| Section | Description | Checks |
|---------|-------------|--------|
| P6-A | Build | 1 |
| P6-B | input: malformed emits OOF-P1 | 4 |
| P6-C | capability + stream: 2 independent OOF-P1s | 4 |
| P6-D | effect + read: 2 independent OOF-P1s | 4 |
| P6-E | Multi-keyword: 3 OOF-P1s in one contract | 4 |
| P6-F | Recovery continues: output succeeds after errors | 2 |
| P6-G | Deferred arms (window/loop/for) do not hang | 4 |
| P6-H | decreases always Ok — .ok() is no-op | 1 |
| P6-I | Well-formed regression | 3 |
| P6-J | stdout bounded + JSON for all P6 fixtures | 12 |
| P6-K | No new OOF codes | 1 |
| P6-L | P5 regression (hang class + canonical) | 14 |
| **Total** | | **54** |

```
ruby verify_liveness_p6.rb    54/54 PASS
ruby verify_liveness_p5.rb    46/46 PASS  (backward compat)
ruby verify_liveness_p4.rb    40/40 PASS  (backward compat)
```

---

## 7. What P6 Does NOT Do

- No changes to inner parser functions (only dispatch in `parse_body_decl`)
- No language semantic changes
- No new OOF diagnostic codes (only OOF-P1, pre-existing)
- No `expect_type`-advance behavior changed (a `window`/`loop`/`for` fix there is P7)
- No canon impact, no runtime/VM changes

---

## 8. Files Changed

| File | Change |
|------|--------|
| `src/parser.rs` | `parse_body_decl`: 11 arms migrated from `.ok()` to `parse_body_decl_with_recovery`; 3 arms documented as P7-deferred; `decreases` documented as always-Ok |
| `fixtures/liveness_p6_input_malformed.ig` | NEW |
| `fixtures/liveness_p6_capability_stream_malformed.ig` | NEW |
| `fixtures/liveness_p6_multi_keyword_recovery.ig` | NEW |
| `fixtures/liveness_p6_read_effect_malformed.ig` | NEW |
| `fixtures/liveness_p6_deferred_no_hang.ig` | NEW |
| `fixtures/liveness_p6_well_formed_regression.ig` | NEW |
| `verify_liveness_p6.rb` | NEW — 54-check proof script |
| `lab-docs/lang/lab-rust-compiler-body-decl-recovery-generalisation-v0.md` | This doc |

---

## 9. Authority and Boundary

```
authority:                     lab_only_p6_body_decl_recovery
new_OOF_codes:                 NONE (OOF-P1 pre-existing)
canon_impact:                  NONE
production_impact:             NONE
VM_change:                     NONE
language_semantics_change:     NONE
grammar_change:                NONE
new_fatal_limits:              NONE
igniter-org_change:            NONE
```

---

## 10. Next Route — P7

**P7: `skip_to_matching_brace` and recovery for `window`, `loop`, `for`**

To safely recover from failures inside declarations with inner `{}` blocks, the parser needs a function that advances past a complete `{...}` block (tracking nesting depth). With that:

1. If `parse_window_decl` fails after opening `{`, skip to the matching `}` and emit OOF-P1
2. If `parse_loop_or_service_loop_decl` fails before or during the body, skip the whole `{...}` and emit OOF-P1
3. Same for `parse_for_loop_decl`

P7 should also consider whether `expect_type`'s unconditional-advance behavior should be changed to a peek-before-advance model for specific contexts — this would prevent the "next keyword consumed as mismatched token" effect seen in P6-F.
