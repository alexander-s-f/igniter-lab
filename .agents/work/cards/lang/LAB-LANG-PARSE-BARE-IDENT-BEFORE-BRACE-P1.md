# LAB-LANG-PARSE-BARE-IDENT-BEFORE-BRACE-P1

Status: CLOSED (2026-06-28) — stale claim falsified; regression-locked; specimen cleaned up
Lane: igniter-lab / lang / parser / grammar hygiene / app-pressure
Mode: standard
Skill: idd-agent-protocol

## Context

`LAB-FRAME-3D-GAME-EQ-WORKAROUND-REMOVAL-P6` fixed the real VM equality gap:
`==` / `!=` now execute through the `stdlib.primitive.eq/ne` OP_CALL path.

After that fix, a smaller syntax problem remained visible in the game specimen:
some expressions that end in a bare identifier immediately before `{` appear to
mis-parse as record/variant construction or otherwise fail before the intended
`if` body is understood.

P6/P7 therefore avoided natural spelling in a few places:

```ig
-- natural, but reported as parser-sensitive
if b.id == target { ... } else { ... }
if flag { ... } else { ... }

-- workaround shape used in the specimen
if target == b.id { ... } else { ... }
if flag > 0 { ... } else { ... }
```

This is small, but toxic: it makes agents distrust the language surface and
write expressions backwards. Fix or precisely falsify it while the pressure is
fresh.

## Goal

Reproduce, characterize, and if feasible fix the parser ambiguity around a bare
identifier immediately before `{`, especially in `if` conditions.

The desired outcome is that normal expression order works:

```ig
if b.id == target { 1 } else { 0 }
if ready { 1 } else { 0 }
```

without regressing record literals, call/construct syntax, or form vocabulary
work.

## Current Authority

Read live code first:

- `lang/igniter-compiler/src/parser.rs`
- parser / compiler tests under `lang/igniter-compiler/tests`
- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig`
- `lab-docs/lang/lab-frame-3d-game-eq-workaround-removal-p6-v0.md`
- `lab-docs/lang/lab-frame-3d-game-ig-mesh-descriptor-p7-v0.md`
- related form/parser cards if the grammar area has moved recently

Live compiler behavior wins over old proof text.

## Phase 0 — Reproduce Exactly

Create the smallest fixtures or parser tests that isolate:

1. field/lhs equality before a block:
   `if b.id == target { 1 } else { 0 }`
2. bare identifier equality before a block:
   `if current == target { 1 } else { 0 }`
3. bare `Bool` condition:
   `if ready { 1 } else { 0 }`
4. working control cases:
   `if target == b.id { 1 } else { 0 }`
   `if ready == true { 1 } else { 0 }`
5. record literals still parse:
   `{ id: target, ready: ready }`

Record exact error messages and AST/SIR shape if available. If the reported
problem is already fixed, close as a verification card and update the stale
comment/doc source.

## Phase 1 — Fix Narrowly If Feasible

If the bug is local parser lookahead, fix it narrowly.

Likely rules to preserve:

- `{ field: value }` remains the record literal under typed annotation.
- Existing variant/record construct syntax, if any, keeps current behavior.
- `if <expr> { ... } else { ... }` should parse the full expression before
  treating `{` as the block opener.
- No special case for frame-ui or game specimens.

Do not introduce a new syntax feature or broad grammar rewrite. If the ambiguity
requires a language decision, stop and write the decision packet instead.

## Phase 2 — App-Pressure Cleanup

If the parser fix lands, update the game specimen only where it improves clarity:

- change workaround spelling to natural `b.id == target` if it now works;
- change integer flag workarounds to `Bool` only if the type/VM surface is ready;
- keep behavior byte-identical and avoid unrelated game refactors.

If the fix is parser-only and game cleanup would widen the card, leave the app
unchanged and document the next cleanup card.

## Acceptance

- [x] Stale claim **falsified** with live evidence: all natural shapes compile ok (Phase 0 table).
- [x] Regression tests cover the four key shapes (+ record literal + game-exact + PascalCase
      boundary): `tests/if_cond_bare_ident_before_brace_tests.rs` 7/7.
- [x] Natural `if b.id == target { ... }` compiles; record literals still parse.
- [x] `if ready { ... }` works (bare lowercase Bool ⇒ `Ref` ⇒ `{` opens body).
- [x] No frame-ui-specific parser hacks (no parser change at all).
- [x] `vm_game_app.ig` switched to natural spelling; `ig_vm_game_tests` 9/9 green; byte-identical
      (`==` symmetric, fixtures unchanged, specimen recompiles ok).
- [x] Proof packet written (`lab-docs/lang/lab-lang-parse-bare-ident-before-brace-p1-v0.md`).
- [x] `git diff --check` clean.

## Report (2026-06-28)

**Falsified, not fixed** — no parser change needed. Verify-first compiled all five card shapes
(plus the game-exact nested shape): every one compiles ok, including the supposedly-broken
`if b.id == target { ... }` and `if ready { ... }`. Root cause of the (non-)ambiguity: the
variant-construct trigger in `parser.rs` (`TokenType::Ident` arm) fires **only for a PascalCase**
ident before `{`; a lowercase value identifier before `{` parses as `Expr::Ref`, leaving `{` to open
the `if` body. The P6/P7 workaround (`if target == b.id {`) was unverified caution.

Locked with 7 regression tests (incl. a boundary test proving a PascalCase comparand before `{` IS
still a construct — the disambiguation is intentional, by case). Phase 2: `KickBody` in the game
specimen now spells the natural `if b.id == target { ... }` (kx/kz/ky) with the stale comment
replaced; `==` is symmetric so the committed game fixtures are unchanged and `ig_vm_game_tests` stays
9/9, the specimen recompiles `ok`.

Files: `lang/igniter-compiler/tests/if_cond_bare_ident_before_brace_tests.rs` (new, 7 tests),
`lab-docs/lang/specimens/dx-view-d/vm_game_app.ig` (KickBody natural spelling + comment),
packet `lab-docs/lang/lab-lang-parse-bare-ident-before-brace-p1-v0.md`.

Verification: parser regression 7/7; full compiler suite 0 failures; `ig_vm_game_tests` 9/9;
specimen compiles `ok`; `git diff --check` PASS.

## Suggested Verification

Adapt exact test targets after discovery:

```sh
cargo test --manifest-path lang/igniter-compiler/Cargo.toml parser
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test <new_parser_test_target>
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_vm_game_tests
git diff --check
```

Use `--test <target>` for integration tests. Do not rely on a trailing filter if
it might run zero tests.

## Non-goals

- No form-vocabulary implementation.
- No record-defaults/builders.
- No VM equality work; P6 already handled that.
- No app-specific syntax workaround.
