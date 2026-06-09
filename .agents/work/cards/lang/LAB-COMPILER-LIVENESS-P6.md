# Card: LAB-COMPILER-LIVENESS-P6

**Track:** lab-rust-compiler-body-decl-recovery-generalisation-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PARSER-HARDENING
**Status:** ✅ CLOSED — 2026-06-09
**Authority:** igniter-lab only; no canon impact; no production impact
**Depends:** LAB-COMPILER-LIVENESS-P5 (parse_body_decl_with_recovery; peek_type fix)

---

## Card Statement

Generalize body-declaration recovery so every body decl parser either succeeds, emits diagnostic + recovers, or proves it cannot hang. Remove remaining silent `.ok()` parser drops where unsafe.

---

## Explicit Answers

### Q1: How many `.ok()` arms in `parse_body_decl` needed migration?

**11 arms.** After P5 migrated `output` and `compute`, the remaining 11 are: `input`, `capability`, `effect`, `read`, `snapshot`, `escape`, `stream`, `fold_stream`, `invariant`, `lead`, `max_steps`.

### Q2: Which arms were explicitly NOT migrated and why?

**3 arms deferred (P7):** `window`, `loop`, `for` — all have inner `{}` blocks. `parse_body_decl_with_recovery` calls `skip_until_body_boundary()` on error, which stops at the FIRST `}` — the inner block's `}`, not the contract's. This would leave the parser in the wrong position.

**1 arm kept as `.ok()` (safe):** `decreases` — `parse_decreases_body_decl` always returns `Ok` (falls back to `variant="unknown"` if nothing to parse). `.ok()` is `Some(_)` in every code path; no silent drop possible.

**3 arms already had manual recovery:** `uses` (explicit skip + OOF-P0), `pipeline`/`step`/`scoped_by`/`tenant_free` (explicit skip + OOF-P2/PG3/PG5), `_ =>` (advance one token + OOF-P0).

### Q3: Does `name_token()` advance on error?

**Yes — always.** `name_token()` calls `advance()` unconditionally before checking the token type. If the token is not an Ident or Keyword, it has already been consumed before returning `Err`. This is the same for `expect_type`, `expect_kw`, `expect_value`.

**Key consequence for fixtures:** `input x` (missing colon) causes `expect_type(Colon)` to consume the next keyword (e.g., `output`). The OOF-P1 message correctly names the consumed token, but the `output` declaration is lost. Using `42` (IntLit) as the malformed token instead of an identifier allows multiple independent failures in one fixture, since `name_token(42)` fails quickly and `skip_until_body_boundary` stops at the next keyword intact.

### Q4: Is token progress now guaranteed for all `parse_body_decl` arms?

**Yes.** Combined with the P5 peek_type EOF fix:

1. Recovery arms: OOF-P1 + skip (always advances)
2. `decreases`: always Ok (always advances)
3. Deferred arms (`window`/`loop`/`for`): inner helpers all call `advance()` unconditionally; no infinite loop possible
4. Manual recovery arms: explicit advance / skip
5. `_ =>` fallback: always advances

No `while !peek_type(Eof)` loop can cycle.

### Q5: Do the P7-deferred arms (`window`, `loop`, `for`) hang with malformed input?

**No.** The P5 peek_type fix prevents all hanging. The only remaining gap is that malformed window/loop/for declarations produce no outer OOF-P1 — they fail silently (the arm returns `None` without any new diagnostic). P7 will add `skip_to_matching_brace` to fix this.

### Q6: Were any new OOF codes introduced?

**No.** Only the pre-existing `OOF-P1` code is used.

---

## Proof Matrix

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

## Files Written

| File | Change |
|------|--------|
| `src/parser.rs` | parse_body_decl: 11 arms → parse_body_decl_with_recovery; P7-deferred comment; decreases documented |
| `fixtures/liveness_p6_input_malformed.ig` | NEW |
| `fixtures/liveness_p6_capability_stream_malformed.ig` | NEW |
| `fixtures/liveness_p6_multi_keyword_recovery.ig` | NEW |
| `fixtures/liveness_p6_read_effect_malformed.ig` | NEW |
| `fixtures/liveness_p6_deferred_no_hang.ig` | NEW |
| `fixtures/liveness_p6_well_formed_regression.ig` | NEW |
| `verify_liveness_p6.rb` | NEW — 54-check proof script |
| `lab-docs/lang/lab-rust-compiler-body-decl-recovery-generalisation-v0.md` | NEW |

---

## Authority and Boundary

```
authority:                     lab_only_p6_body_decl_recovery
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

## Next Route — P7

**P7: `skip_to_matching_brace` and recovery for `window`, `loop`, `for`**

Required infrastructure: `skip_to_matching_brace(depth: usize)` that tracks `{`/`}` nesting and advances past a complete block. With this, all three deferred arms can be migrated to `parse_body_decl_with_recovery`.

Optional P7 scope: consider peek-before-advance for `expect_type` in specific contexts, to avoid consuming body-boundary keywords as mismatched tokens (the `input x → output consumed` behavior documented in P6-F).
