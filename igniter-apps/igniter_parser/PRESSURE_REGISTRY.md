# Igniter Parser Pressure Registry

Status: APP-RECHECK-WAVE-P6 candidate
Last checked: 2026-06-13
Scope: app-pressure evidence only; not a canon stdlib or compiler proposal.

## Current Live Check

Rust compile:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/igniter_parser/types.ig ../igniter-apps/igniter_parser/lexer.ig ../igniter-apps/igniter_parser/parser.ig ../igniter-apps/igniter_parser/api.ig --out /tmp/igniter_parser_p6_probe.igapp
```

Result:

- `status`: `oof`
- `parse`: `ok`
- `multifile_resolve`: `oof`
- diagnostics: 1
- first diagnostic: `OOF-IMP2 unknown stdlib module path 'stdlib.string' from module 'ParserLexer'`
- Rust `source_hash`: `sha256:96413f3b77ac1364dbb32f7f0e6ab87b723dbf1612074f663be61d41eeb35074`

Ruby/canon compile:

- `status`: `oof`
- `pass_result`: `oof`
- diagnostics: 1
- first diagnostic: `OOF-IMP2 unknown stdlib module path 'stdlib.string' from module 'ParserLexer'`
- Ruby `source_hash`: `sha256:dc95f772d8cb36b5b0dfb76723f46517cf8197971165cbdc08271ca9e333d27d`

The two toolchains agree on the current first blocker.

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
| IP-P01 | ACTIVE | Missing `stdlib.string` import surface | Both Rust and Ruby stop at `OOF-IMP2` for `import stdlib.string.{ char_at }` in `lexer.ig` | `LANG-STDLIB-STRING-SURFACE-P1` |
| IP-P02 | PENDING-BEHIND-P01 | Character access primitive | `LexNextToken` calls `char_at(state.source, state.pos)`; parser work requires byte/character indexing | `LANG-STDLIB-STRING-CHAR-AT-P1` |
| IP-P03 | PENDING-BEHIND-P01 | Parser loop/state-machine pressure | `LexNextToken` and `ParseModuleDecl` model one step at a time; report notes need for repeated state folding or managed recursion | `LAB-PARSER-STATE-MACHINE-P1` |
| IP-P04 | ACTIVE-DESIGN-PRESSURE | Flat AST arena pattern | `AstNode.children_ids: Collection[String]` avoids recursive `AstNode` nesting | Keep as app pattern; revisit only if recursive data types are opened |
| IP-P05 | PENDING-BEHIND-P01 | String slicing/token accumulation | Report names `substring` as future requirement; current code only reaches `char_at` import blocker | `LANG-STDLIB-STRING-SLICE-P1` after char_at |
| IP-P06 | ACTIVE | Stringly stdlib constructor calls | `api.ig` and `parser.ig` use `call_contract("empty")` / `call_contract("append", ...)`; currently hidden behind P01 | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1` |
| IP-P07 | PENDING-BEHIND-P01 | Self-hosting scope boundary | App proves architectural shape, not a complete parser; only 3 contracts and no full token stream loop yet | Keep out of canon until stdlib.string + state iteration are defined |

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
