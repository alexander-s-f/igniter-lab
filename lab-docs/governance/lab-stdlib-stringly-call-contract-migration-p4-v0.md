# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4

**Status:** CLOSED — PROVED  
**Date:** 2026-06-13  
**Gate:** LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 CLOSED (IP-P01/P02/P05 resolved)  
**Proof:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p4.rb` — 51/51 PASS  

---

## Summary

Final stringly stdlib migration for `igniter_parser`. Migrated all 5 remaining
`call_contract("empty")` / `call_contract("append")` sites across `api.ig`,
`parser.ig`, and `lexer.ig`. Both toolchains reached ok/0 — the first DUAL-CLEAN
result for `igniter_parser`.

This closes IP-P06 (dominant blocker after IP-P01/P02/P05 resolution) and removes
the last non-Tier-1 stringly stdlib call in the app.

---

## Context

After `LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1` resolved IP-P01/P02/P05
(stdlib.string import surface), the next blocker was IP-P06: 3×`call_contract("empty")`
and 2×`call_contract("append")` producing OOF-TY0 in both toolchains.

- Ruby: oof / 7 diagnostics (OOF-TY0 ×5 + OOF-P1 cascades ×2)
- Rust: oof / 5 diagnostics (OOF-TY0 ×5)

Tier-1 literal callees (`call_contract("LexNextToken")`, `call_contract("ParseModuleDecl")`)
are user contracts — they were preserved unchanged. The migration shapes apply only to
stdlib constructor calls.

---

## Migration Shapes Applied

### EMPTY_CONSTRUCTOR shape

`call_contract("empty")` has no type information — the compiler cannot infer
the element type. Canonical replacement: typed compute declaration.

```
# Before
compute initial_tokens = call_contract("empty")

# After (typed [] form)
compute initial_tokens : Collection[Token] = []
```

### ACCUMULATING shape

`call_contract("append", coll, elem)` → bare `append(coll, elem)` with import.

```
# Before
call_contract("append", state.tokens, new_token)

# After
append(state.tokens, new_token)
```

---

## Sites Migrated

| File | Variable | Shape | Import Added |
|---|---|---|---|
| `api.ig` | `initial_tokens` | EMPTY_CONSTRUCTOR → `Collection[Token] = []` | no |
| `api.ig` | `initial_nodes` | EMPTY_CONSTRUCTOR → `Collection[AstNode] = []` | no |
| `parser.ig` | `empty_children` | EMPTY_CONSTRUCTOR → `Collection[String] = []` | no |
| `parser.ig` | `new_nodes` | ACCUMULATING → `append(state.nodes, module_node)` | `stdlib.collection.{ append }` |
| `lexer.ig` | `next_tokens` | ACCUMULATING → `append(state.tokens, new_token)` | `stdlib.collection.{ append }` |

`api.ig` does not import `stdlib.collection` because it uses only typed `[]` (no `append` call).

---

## Tier-1 Callees Preserved

`api.ig` continues to use:

```
compute lex_state_1  = call_contract("LexNextToken", initial_lexer)
compute parse_state_1 = call_contract("ParseModuleDecl", initial_parser)
```

These are user-defined contracts, not stdlib callees. They are not part of the
stringly stdlib pattern and must not be migrated.

---

## Production Files Changed

| File | Change |
|---|---|
| `igniter-lab/igniter-apps/igniter_parser/api.ig` | 2×EMPTY_CONSTRUCTOR migrated |
| `igniter-lab/igniter-apps/igniter_parser/parser.ig` | 1×EMPTY_CONSTRUCTOR + 1×ACCUMULATING migrated; `stdlib.collection.{ append }` import added |
| `igniter-lab/igniter-apps/igniter_parser/lexer.ig` | 1×ACCUMULATING migrated; `stdlib.collection.{ append }` import added |

## Files NOT Changed

- `igniter-lang/lib/igniter_lang/typechecker.rb` — no compiler change; append dispatch pre-existing
- `igniter-lab/igniter-compiler/src/typechecker.rs` — no compiler change
- `igniter-lang/docs/spec/stdlib-inventory.json` — stdlib.collection.append pre-existing
- `igniter-lab/igniter-apps/igniter_parser/types.ig` — unchanged

---

## Compile Results

### Before (from LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1)

- Ruby: oof / 7 diagnostics
- Rust: oof / 5 diagnostics

### After (this card)

- Ruby: **ok / 0 diagnostics** — DUAL-CLEAN
- Rust: **ok / 0 diagnostics** — contracts: `LexNextToken`, `ParseModuleDecl`, `ParseSource`

---

## Proof Results

```
LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4
Result: 51/51 PASS  (0 FAIL)
```

| Section | Checks | Topic |
|---|---|---|
| A | 7 | Stringly sites removed |
| B | 8 | Canonical forms present |
| C | 3 | Tier-1 callees preserved |
| D | 6 | Ruby full-app compile ok/0 |
| E | 6 | Rust full-app compile ok/0 |
| F | 6 | SIR canonical names |
| G | 5 | String surface regression |
| H | 5 | Pressure registry |
| I | 5 | Authority / no overclaim |
| **Total** | **51** | |

---

## Pressure Registry Impact

| ID | Previous | Now |
|---|---|---|
| IP-P01 | RESOLVED | RESOLVED |
| IP-P02 | RESOLVED | RESOLVED |
| IP-P05 | RESOLVED | RESOLVED |
| IP-P06 | NOW-ACTIVE | **RESOLVED** |

`igniter_parser` is now **DUAL-CLEAN** — ok/0 in both Ruby and Rust toolchains.

---

## No-Claim Boundary

This card does not:
- Introduce a new stdlib function
- Change any compiler file
- Change the stdlib inventory
- Change `types.ig`
- Authorize Tier-1 `call_contract` callees to be rewritten as direct calls

The `stdlib.collection.append` dispatch was pre-existing in both toolchains before this card.
