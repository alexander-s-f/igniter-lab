# Igniter Parser Pressure Registry

Updated: 2026-06-13 (LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4 — IP-P06 RESOLVED; igniter_parser DUAL-CLEAN ok/0 both toolchains)
Last checked: 2026-06-13
Scope: app-pressure evidence only; not a canon stdlib or compiler proposal.

## Current Live Check

Rust compile:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/igniter_parser/types.ig ../igniter-apps/igniter_parser/lexer.ig ../igniter-apps/igniter_parser/parser.ig ../igniter-apps/igniter_parser/api.ig --out /tmp/igniter_parser_p6_probe.igapp
```

Result (as of LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4, 2026-06-13):

- `status`: `ok`
- `diagnostics`: 0
- contracts: `LexNextToken`, `ParseModuleDecl`, `ParseSource`
- stages: parse ok / classify ok / typecheck ok / emit ok / assemble ok

Ruby/canon compile:

- `status`: `ok`
- `diagnostics`: 0

**DUAL-CLEAN** — both toolchains agree: ok/0, 3 contracts.

## Source Inventory

Files:

- `types.ig` — `ParserTypes`; types `Token`, `AstNode`, `LexerState`, `ParserState`
- `lexer.ig` — `ParserLexer`; contract `LexNextToken`; imports `stdlib.string.{ char_at }`
- `parser.ig` — `ParserCore`; contract `ParseModuleDecl`
- `api.ig` — `ParserApi`; contract `ParseSource`

The app is a self-hosted parser prototype. It uses a flat AST arena (`children_ids`) instead of recursive AST types.

## Pressures

| ID | Status | Pressure | Evidence | Route |
|---|---|---|---|---|
| IP-P01 | **RESOLVED** | Missing `stdlib.string` import surface | OOF-IMP2 cleared by LANG-STDLIB-STRING-SURFACE-P3 (char_at dual-toolchain) — inventory entry enables import resolution | LANG-STDLIB-STRING-SURFACE-P3 CLOSED |
| IP-P02 | **RESOLVED** | Character access primitive | `char_at(state.source, state.pos)` compiles cleanly in both toolchains — no OOF-TY0 | LANG-STDLIB-STRING-SURFACE-P3 CLOSED |
| IP-P03 | PENDING-BEHIND-P06 | Parser loop/state-machine pressure | `LexNextToken` and `ParseModuleDecl` model one step at a time; report notes need for repeated state folding or managed recursion | `LAB-PARSER-STATE-MACHINE-P1` |
| IP-P04 | ACTIVE-DESIGN-PRESSURE | Flat AST arena pattern | `AstNode.children_ids: Collection[String]` avoids recursive `AstNode` nesting | Keep as app pattern; revisit only if recursive data types are opened |
| IP-P05 | **RESOLVED** | String slicing/token accumulation | `substring(state.source, state.pos, 6)` added to `lexer.ig`; compiles cleanly both toolchains; `token_text` used in `new_token.text` | LANG-STDLIB-STRING-SUBSTRING-P2 CLOSED |
| IP-P06 | **RESOLVED** | Stringly stdlib constructor calls | All 5 sites migrated: `api.ig` 2×empty → typed `[]`; `parser.ig` 1×empty + 1×append → typed `[]` + `append()`; `lexer.ig` 1×append → `append()`. Both TCs ok/0. | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4 CLOSED |
| IP-P07 | PENDING-BEHIND-P06 | Self-hosting scope boundary | App proves architectural shape, not a complete parser; only 3 contracts and no full token stream loop yet | Keep out of canon until stringly migration + state iteration are defined |

## Wave P6 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic — `OOF-IMP2 unknown stdlib module path 'stdlib.string' from module 'ParserLexer'`. Ruby: oof / 1 diagnostic — same `OOF-IMP2`. Both toolchains agree on the first blocker. LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 has no effect: the app is stopped at import resolution before TC runs. IP-P01 ACTIVE — `LANG-STDLIB-STRING-SURFACE-P1` is the dominant route. IP-P06 stringly stdlib constructor calls confirmed active but hidden behind P01. No new pressures. No regressions. First full fleet inclusion in Wave P6.

## P6 Inclusion

Include `igniter_parser` in `APP-RECHECK-WAVE-P6`.

Expected P6 classification:

- Rust: `oof`, first blocker `OOF-IMP2 stdlib.string`
- Ruby: `oof`, first blocker `OOF-IMP2 stdlib.string`
- Dominant route: `LANG-STDLIB-STRING-SURFACE-P1`

## Interpretation

This app is not currently a clean baseline. It is valuable because it cleanly exposes the next practical frontier for self-hosting:

1. string import surface,
2. character access,
3. deterministic state-machine iteration,
4. migration away from stringly stdlib constructors.

The flat arena AST pattern is accepted as app-local evidence only. It does not authorize recursive data types or a compiler-level AST package.

## Non-Goals

- Do not implement `stdlib.string` inside this app.
- Do not special-case `call_contract("empty")` or `call_contract("append")`.
- Do not treat the arena AST model as a canon data-structure decision.
- Do not widen runtime authority; all pressure here is pure compile-time/stdin-source processing.

## Wave P7 Recheck Summary (2026-06-13)

Rust: oof / 1 diagnostic (`OOF-IMP2: unknown stdlib module path 'stdlib.string'`) — unchanged. Ruby: oof / 1 diagnostic (`OOF-IMP2: unknown stdlib module path 'stdlib.string'`) — unchanged. IP-P01 ACTIVE. Route: `LANG-STDLIB-STRING-SURFACE-P1`. No new pressures. No regressions.

## LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 (2026-06-13)

Gate: LANG-STDLIB-STRING-SURFACE-P3 CLOSED (char_at dual-toolchain) + LANG-STDLIB-STRING-SUBSTRING-P2 CLOSED (substring dual-toolchain).

**Source change:** `lexer.ig` — import extended to `stdlib.string.{ char_at, substring }`; `compute token_text = substring(state.source, state.pos, 6)` added; `new_token.text` changed from hardcoded `"module"` to `token_text`.

**Ruby result:** oof / 7 diagnostics — all OOF-TY0 for `call_contract("empty"/"append")` + OOF-P1 cascades. No OOF-IMP2. No char_at or substring errors.

**Rust result:** oof / 5 diagnostics — all OOF-TY0 for `call_contract("empty"/"append")`. No OOF-IMP2. No char_at or substring errors.

**IP-P01 RESOLVED** — OOF-IMP2 for `stdlib.string` is gone in both toolchains.
**IP-P02 RESOLVED** — `char_at(state.source, state.pos)` compiles cleanly.
**IP-P05 RESOLVED** — `substring(state.source, state.pos, 6)` compiles cleanly; token text extraction pattern demonstrated.
**IP-P06 NOW-ACTIVE** — 3×`call_contract("empty")` + 2×`call_contract("append")` expose stringly stdlib pattern. Dominant blocker. Route: `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`.

Proof: `igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_parser_string_surface_migration_p1.rb` — 49/49 PASS.

## Wave P8 Recheck Summary (2026-06-13)

Rust: oof / 5 diagnostics — changed from Wave P7. Prior: oof / 1 (OOF-IMP2 stdlib.string). Now: 5× OOF-TY0 (`call_contract: unknown callee 'empty'` ×3; `call_contract: unknown callee 'append'` ×2). Ruby: oof / 7 diagnostics — changed from Wave P7. Prior: oof / 1 (OOF-IMP2 stdlib.string). Now: 3× OOF-TY0 (unknown callee 'empty') + 2× OOF-TY0 (unknown callee 'append') + OOF-P1 (`Unresolved symbol: initial_tokens`) + OOF-P1 (`Unresolved symbol: empty_children`).

**IP-P01 RESOLVED** — `stdlib.string` import now recognized in both toolchains. No OOF-IMP2 diagnostics.
**IP-P02 RESOLVED** — `char_at` compiles cleanly.
**IP-P05 RESOLVED** — `substring` compiles cleanly.
**IP-P06 NOW-ACTIVE** — 3 sites with `call_contract("empty")` + 2 sites with `call_contract("append")` block both toolchains (OOF-TY0). Ruby additionally shows 2 OOF-P1 cascades: `initial_tokens` and `empty_children` unresolved downstream of the empty callee. Dominant route: `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`.

Resolved by: LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 (gate-closed before Wave P8). Net: was oof/1+oof/1 → now oof/5+oof/7. Progress: first blocker cleared; deeper stringly pattern exposed.

## LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4 (2026-06-13)

Gate: LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 CLOSED (IP-P01/P02/P05 resolved).

**Sites migrated (5 total):**

| File | Site | Before | After |
|---|---|---|---|
| `api.ig` | initial_tokens | `call_contract("empty")` | `compute initial_tokens : Collection[Token] = []` |
| `api.ig` | initial_nodes | `call_contract("empty")` | `compute initial_nodes : Collection[AstNode] = []` |
| `parser.ig` | empty_children | `call_contract("empty")` | `compute empty_children : Collection[String] = []` |
| `parser.ig` | new_nodes | `call_contract("append", state.nodes, module_node)` | `append(state.nodes, module_node)` |
| `lexer.ig` | next_tokens | `call_contract("append", state.tokens, new_token)` | `append(state.tokens, new_token)` |

**Tier-1 callees preserved (user contracts, not stdlib):** `call_contract("LexNextToken")`, `call_contract("ParseModuleDecl")`.

**Ruby result:** ok / 0 diagnostics — DUAL-CLEAN.
**Rust result:** ok / 0 diagnostics — DUAL-CLEAN. Contracts: `LexNextToken`, `ParseModuleDecl`, `ParseSource`.

**IP-P06 RESOLVED** — all stringly stdlib constructor sites migrated.
**igniter_parser DUAL-CLEAN** — first fully clean compile result in both toolchains.

Proof: `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p4.rb` — 51/51 PASS.
