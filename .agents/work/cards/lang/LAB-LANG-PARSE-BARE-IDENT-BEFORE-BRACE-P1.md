# LAB-LANG-PARSE-BARE-IDENT-BEFORE-BRACE-P1

Status: OPEN
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

- [ ] Exact failure shape reproduced or the stale claim is falsified with live
      parser/compiler evidence.
- [ ] Minimal parser/compiler regression tests cover the four key shapes above.
- [ ] If fixed: natural `if b.id == target { ... }` compiles, and control cases
      for record literals still pass.
- [ ] If fixed: `if ready { ... }` either works, or the remaining blocker is
      named precisely (parser vs typechecker vs VM).
- [ ] No frame-ui-specific parser hacks.
- [ ] If `vm_game_app.ig` changes, `ig_vm_game_tests` stay green and behavior is
      unchanged.
- [ ] Proof packet or closing report written:
      `lab-docs/lang/lab-lang-parse-bare-ident-before-brace-p1-v0.md`.
- [ ] `git diff --check` clean.

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
