# LAB-LANG-PARSE-BARE-IDENT-BEFORE-BRACE-P1

Date: 2026-06-28
Status: DONE — stale claim FALSIFIED with live evidence; regression-locked; specimen cleaned up
Lane: igniter-lab / lang / parser / grammar hygiene / app-pressure
Depends-On (context): `lab-frame-3d-game-eq-workaround-removal-p6-v0.md`,
`lab-frame-3d-game-ig-mesh-descriptor-p7-v0.md`

`igniter-compiler` parser scope + one specimen cleanup. No new syntax, no grammar rewrite, no
frame-ui/game-specific parser hack, no VM/equality work (P6 owned that), no form vocabulary.

## Outcome

**The reported parser ambiguity does NOT reproduce on the live compiler.** A bare *value* identifier
immediately before `{` in an `if` condition parses correctly — `if b.id == target { ... }` and
`if ready { ... }` compile clean. The P6/P7 specimens used the reversed/workaround spelling
(`if target == b.id {`) out of caution that was never actually verified against the parser. This card
falsifies that caution, locks the natural shapes with regression tests, and switches the game
specimen to the natural spelling (byte-identical, `==` is symmetric).

## Phase 0 — reproduce (falsified)

Compiled each shape through the real `igniter_compiler`:

| # | Shape | Result |
| --- | --- | --- |
| 1 | `if b.id == target { 1 } else { 0 }` (field eq, bare ident before `{`) | **compiles ok** |
| 2 | `if current == target { 1 } else { 0 }` (bare ident eq) | **compiles ok** |
| 3 | `if ready { 1 } else { 0 }` (bare Bool) | **compiles ok** |
| 4a | `if target == b.id { 1 } else { 0 }` (workaround) | compiles ok |
| 4b | `if ready == true { 1 } else { 0 }` (workaround) | compiles ok |
| 5 | `{ id: target, ready: ready }` (record literal) | compiles ok |

Game-exact nested shape `if b.id == target { if b.px > 0 { 700 } else { 0 } } else { 0 }` also
compiles ok and runs **byte-identically** to the workaround `if target == b.id { ... }` (both → 700
for `{b:{id:3,px:5},target:3}`).

## Root cause of the (non-)ambiguity — why the value-ident case is unambiguous

The construct-vs-block decision is in `parser.rs` primary-expression parsing (the `TokenType::Ident`
arm, ~`3683`):

```rust
// PROP-044 P3: PascalCase ident immediately followed by { → variant construct
let first_char = tok.value.chars().next().unwrap_or('a');
if first_char.is_uppercase() && self.peek_type(TokenType::LBrace) {
    return self.parse_variant_construct_expr(tok.value);
}
Ok(Expr::Ref { name: tok.value })
```

The variant-construct trigger fires **only for a PascalCase ident** immediately before `{`. A
lowercase value identifier (`target`, `current`, `ready`, …) before `{` is parsed as a plain
`Expr::Ref`, so the `{` is free to open the `if` body. Hence the natural `if <expr ending in a
lowercase ident> { ... }` is unambiguous **by design**.

The only shape that legitimately does NOT parse as an if-body is a **PascalCase** comparand before
`{` (e.g. `if b.id == Foo { ... }`) — there `Foo { ... }` is a genuine variant construct. That is
correct behavior (a type/variant name), not a bug, and is locked as a boundary test.

## Phase 1 — fix

**No parser change required.** The grammar already disambiguates correctly via the PascalCase gate.

## Regression tests

`lang/igniter-compiler/tests/if_cond_bare_ident_before_brace_tests.rs` (7 tests, in-process
Lexer→Parser→Classifier→TypeChecker; asserts no `parse_errors` and no `type_errors`):

- `field_eq_before_block_parses_as_if_not_construct` (#1)
- `bare_ident_eq_before_block_parses_as_if_not_construct` (#2)
- `bare_bool_condition_parses` (#3)
- `control_reversed_and_eq_true_still_parse` (#4a/#4b)
- `record_literal_still_parses` (#5 — no record-literal regression)
- `game_exact_nested_natural_spelling_parses` (the exact game shape)
- `pascalcase_before_brace_is_still_a_construct_not_an_if_body` (boundary lock — proves the
  disambiguation is by case, intentionally)

## Phase 2 — app-pressure cleanup

`lab-docs/lang/specimens/dx-view-d/vm_game_app.ig` `KickBody` switched from the workaround
`if target == b.id { ... }` to the natural `if b.id == target { ... }` (kx/kz/ky), and the stale
"so the comparand before `{` does not mis-parse as a record construct" comment replaced with a note
pointing here. `==` is symmetric, so the VM output is byte-identical — the committed
`vm_game_*.runtime.json` fixtures are unchanged and `ig_vm_game_tests` stays green; the edited
specimen still compiles `ok`.

## Verification

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test if_cond_bare_ident_before_brace_tests  # 7/7
cargo test --manifest-path lang/igniter-compiler/Cargo.toml                                                # full crate, 0 failures
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_vm_game_tests                      # 9/9
igniter_compiler compile lab-docs/lang/specimens/dx-view-d/vm_game_app.ig --out …                          # "status": "ok"
git diff --check                                                                                           # PASS
```

## Non-goals (unchanged)

No form-vocabulary, no record-defaults/builders, no VM equality work, no app-specific syntax
workaround. The PascalCase-construct behavior is intentionally preserved.

## Note on P6/P7

The P6/P7 proof packets remain accurate historical records (they chose the workaround spelling at the
time). This card supersedes the "comparand before `{` must be a field access" guidance: for a
lowercase value identifier it is unnecessary. Future specimens may spell `if b.id == target { ... }`
naturally.
