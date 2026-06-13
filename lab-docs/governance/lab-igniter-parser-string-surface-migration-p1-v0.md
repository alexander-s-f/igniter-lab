# LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1

**Route:** APP MIGRATION / IGNITER_PARSER / STRING SURFACE
**Status:** CLOSED / PROVED — 49/49 PASS
**Date:** 2026-06-13
**Gate:** LANG-STDLIB-STRING-SURFACE-P3 CLOSED (char_at dual-toolchain) + LANG-STDLIB-STRING-SUBSTRING-P2 CLOSED (substring dual-toolchain)

---

## Summary

Recheck and source migration of `igniter_parser` after `stdlib.string.char_at` and
`stdlib.string.substring` reached dual-toolchain status. The app was blocked at
`OOF-IMP2 unknown stdlib module path 'stdlib.string'` in both toolchains since Wave P7.

After migration:
- **IP-P01 RESOLVED** — OOF-IMP2 gone in both toolchains
- **IP-P02 RESOLVED** — `char_at` compiles cleanly
- **IP-P05 RESOLVED** — `substring` imported and used for token text extraction
- **IP-P06 NOW-ACTIVE** — stringly `call_contract("empty"/"append")` is the new dominant blocker

---

## Before / After

| Metric | Wave P7 (before) | P1 (after) |
|---|---|---|
| Ruby status | oof / 1 diag | oof / 7 diags |
| Rust status | oof / 1 diag | oof / 5 diags |
| First blocker | OOF-IMP2 `stdlib.string` | OOF-TY0 `call_contract("empty")` |
| IP-P01 | ACTIVE | **RESOLVED** |
| IP-P02 | PENDING-BEHIND-P01 | **RESOLVED** |
| IP-P05 | PENDING-BEHIND-P01 | **RESOLVED** |
| IP-P06 | hidden behind P01 | **NOW-ACTIVE** |

The diagnostic count increased (1→7 Ruby, 1→5 Rust) because removing the OOF-IMP2
import blocker allowed both TCs to advance into typecheck, where the 5 stringly sites
now produce individual OOF-TY0 errors.

---

## Source Change — `lexer.ig`

**Changed:** `igniter-lab/igniter-apps/igniter_parser/lexer.ig`

```diff
-import stdlib.string.{ char_at }
+import stdlib.string.{ char_at, substring }

+  -- Extract token text via byte slice: "module" is 6 bytes starting at state.pos.
+  -- IP-P05: substring now available (LANG-STDLIB-STRING-SUBSTRING-P2).
+  compute token_text = substring(state.source, state.pos, 6)

   compute new_token = {
     kind: "Keyword",
-    text: "module",
+    text: token_text,
     line: state.line
   }
```

The `token_text` extraction demonstrates `substring(String, Integer, Integer) -> String`
in a real lexer context: "extract 6 bytes from position `state.pos` in `state.source`."
This pattern — single-step, deterministic, byte-based — is exactly what the parser
report described as the future use of `substring`.

**Files NOT changed:** `parser.ig`, `api.ig`, `types.ig`.
Stringly `call_contract` sites are NOT migrated here — those are IP-P06, routed to
`LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`.

---

## Remaining Diagnostics

### Ruby (oof / 7)
```
OOF-TY0: call_contract: unknown callee 'empty' — not found in this module (initial_tokens)
OOF-P1:  Unresolved symbol: initial_tokens
OOF-TY0: call_contract: unknown callee 'empty' — not found in this module (initial_nodes)
OOF-TY0: call_contract: unknown callee 'empty' — not found in this module (empty_children)
OOF-P1:  Unresolved symbol: empty_children
OOF-TY0: call_contract: unknown callee 'append' — not found in this module (new_nodes)
OOF-TY0: call_contract: unknown callee 'append' — not found in this module (next_tokens)
```

OOF-P1 entries are cascade from OOF-TY0 (symbol undefined because call_contract failed).

### Rust (oof / 5)
```
OOF-TY0: call_contract: unknown callee 'empty' — not found in this module (initial_tokens)
OOF-TY0: call_contract: unknown callee 'empty' — not found in this module (initial_nodes)
OOF-TY0: call_contract: unknown callee 'empty' — not found in this module (empty_children)
OOF-TY0: call_contract: unknown callee 'append' — not found in this module (new_nodes)
OOF-TY0: call_contract: unknown callee 'append' — not found in this module (next_tokens)
```

### Call contract site map

| File | Callee | Shape | Status |
|---|---|---|---|
| `api.ig` | `"empty"` (×2) | EMPTY_CONSTRUCTOR | IP-P06 |
| `api.ig` | `"LexNextToken"` | Tier 1 literal | clean (no error) |
| `api.ig` | `"ParseModuleDecl"` | Tier 1 literal | clean (no error) |
| `parser.ig` | `"empty"` | EMPTY_CONSTRUCTOR | IP-P06 |
| `parser.ig` | `"append"` | ACCUMULATING | IP-P06 |
| `lexer.ig` | `"append"` | ACCUMULATING | IP-P06 |

Tier 1 literal callees (`"LexNextToken"`, `"ParseModuleDecl"`) resolve correctly — no error.
Stringly stdlib callees (`"empty"`, `"append"`) do not — routed to IP-P06.

---

## Pressure Classification After Migration

| ID | New Status | Resolved By |
|---|---|---|
| IP-P01 | RESOLVED | LANG-STDLIB-STRING-SURFACE-P3 (inventory entry enables import) |
| IP-P02 | RESOLVED | LANG-STDLIB-STRING-SURFACE-P3 (char_at TC dispatch) |
| IP-P03 | PENDING-BEHIND-P06 | Unchanged — no loop/recursion construct added |
| IP-P04 | ACTIVE-DESIGN-PRESSURE | Unchanged — arena AST is accepted app pattern |
| IP-P05 | RESOLVED | LANG-STDLIB-STRING-SUBSTRING-P2 + this migration (source updated) |
| IP-P06 | NOW-ACTIVE | 3×empty + 2×append now blocking both TCs |
| IP-P07 | PENDING-BEHIND-P06 | Unchanged |

---

## Non-Goals Confirmed

- No parser loops or recursion added to any file
- No `call_contract("empty"/"append")` migration done (IP-P06 route)
- No canon or self-hosting claim
- No new `stdlib.string` entries created (inventory unchanged in this card)
- No runtime authority changes

---

## Proof

**Runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_parser_string_surface_migration_p1.rb`
**Result:** 49/49 PASS

| Section | Checks | Topic |
|---|---|---|
| A | 6 | IP-P01 RESOLVED — OOF-IMP2 cleared both TCs |
| B | 5 | IP-P02 RESOLVED — char_at clean |
| C | 7 | IP-P05 RESOLVED — substring imported + used |
| D | 5 | Ruby TC current diagnostics (call_contract only) |
| E | 5 | Rust TC current diagnostics (call_contract only) |
| F | 6 | Source state inventory |
| G | 5 | IP-P06 exposed — stringly dominant blocker |
| H | 5 | Pressure registry state |
| I | 5 | Authority / no overclaim |

---

## Next Route

**IP-P06** — `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`

Migrate 5 stringly stdlib sites:
- 3 × `call_contract("empty")` → `compute name : Collection[T] = []` or typed seed
- 2 × `call_contract("append", coll, elem)` → `append(coll, elem)`

This is the same shape as the prior migration (arch_patterns, bloom_filter, decision_tree).
The igniter_parser 5 sites were already tracked in
`LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1` as deferred (blocked by IP-P01).
They are now unblocked.
