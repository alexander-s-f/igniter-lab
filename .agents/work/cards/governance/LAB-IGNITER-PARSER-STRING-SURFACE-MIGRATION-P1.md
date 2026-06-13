# LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1

**Status:** CLOSED / PROVED — 49/49 PASS
**Route:** APP MIGRATION / IGNITER_PARSER / STRING SURFACE
**Date:** 2026-06-13
**Authority:** app migration + pressure registry update

## Summary

Recheck and source migration of `igniter_parser` after `stdlib.string.char_at` (P3)
and `stdlib.string.substring` (P2) reached dual-toolchain. Cleared the OOF-IMP2
import blocker that had stalled the app since Wave P7.

## Results

| IP | Before | After |
|---|---|---|
| IP-P01 (import surface) | ACTIVE — OOF-IMP2 | **RESOLVED** |
| IP-P02 (char_at) | PENDING-BEHIND-P01 | **RESOLVED** |
| IP-P05 (substring) | PENDING-BEHIND-P01 | **RESOLVED** |
| IP-P06 (stringly calls) | hidden behind P01 | **NOW-ACTIVE** |

## Source Change

**`igniter-lab/igniter-apps/igniter_parser/lexer.ig`**
- Import extended: `stdlib.string.{ char_at, substring }`
- Added `compute token_text = substring(state.source, state.pos, 6)`
- `new_token.text` changed from `"module"` to `token_text`

`parser.ig`, `api.ig`, `types.ig` — unchanged (IP-P06 migration is a separate card).

## Current State

**Ruby:** oof / 7 — all OOF-TY0 for `call_contract("empty"/"append")` + OOF-P1 cascades
**Rust:** oof / 5 — all OOF-TY0 for `call_contract("empty"/"append")`

Tier 1 literal callees (`"LexNextToken"`, `"ParseModuleDecl"`) compile cleanly.

## Proof

**Runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_parser_string_surface_migration_p1.rb`
**Result:** 49/49 PASS

## Lab Doc

`igniter-lab/lab-docs/governance/lab-igniter-parser-string-surface-migration-p1-v0.md`

## Next

**IP-P06** — stringly stdlib migration (5 sites: 3×empty + 2×append).
Route: `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1` (igniter_parser sites were already
tracked there as deferred; now unblocked).
