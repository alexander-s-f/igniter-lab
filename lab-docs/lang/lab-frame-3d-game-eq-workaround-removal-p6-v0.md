# LAB-FRAME-3D-GAME-EQ-WORKAROUND-REMOVAL-P6 — proof packet

Status: CLOSED — workaround removed; the game reducer uses direct `==`. A regression contradicting P1
was found and fixed with a minimal, sanctioned VM change.
Card: `.agents/work/cards/lang/LAB-FRAME-3D-GAME-EQ-WORKAROUND-REMOVAL-P6.md`
Date: 2026-06-27

## Stale premise vs. live reality

The card's premise (per `LAB-VM-PRIMITIVE-EQ-PARITY-P1`: "`==` is supported, no VM change needed") does
NOT hold on the current VM binary. The card anticipated this ("if `b.id == target` still fails, stop and
write the exact failure shape") and sanctions a VM edit when live verification finds a regression
contradicting P1. It did.

## Exact failure shape (re-verified before editing)

`==` lowered to the OP_CALL builtin path failed at runtime:

```text
VM evaluation failed: OP_CALL: Unknown/unimplemented function 'stdlib.primitive.eq' with 2 arguments
```

This was NOT specific to the game or to `map`. Probed precisely:
- `Direct` (`compute eq = t == n`, no map) → FAIL `stdlib.primitive.eq`.
- `ViaMap` (`map(ns, x -> call_contract("Cmp", x, t))`) → FAIL `stdlib.primitive.eq`.
- **`vm_loop_app.ig` `View` (P7's "real `==`" case, `"lead:0" == state.sel`) → FAIL** `stdlib.primitive.eq`.

So the Ruby `igc` lowers `==` / `!=` to OP_CALL builtins `stdlib.primitive.{eq,ne}`, and the VM's OP_CALL
dispatch did not implement them — even though `OP_EQ` (`vm.rs:669`) and the binary-op evaluator
(`vm.rs:6322`, `"eq" => value_eq`) both support equality. The same builtin-name gap the arithmetic ops
had before the owners fixed `stdlib.integer.{add,sub,mul,div}` on this path (`vm.rs:2167`) — eq was just
not included. (P1's proof must have exercised a path/binary that did dispatch it; the current binary
does not, so committed `==`-dependent fixtures like the vm_loop selected rows were latently un-runnable.)

## The fix (minimal, sanctioned)

`lang/igniter-vm/src/vm.rs` — add an OP_CALL arm for `stdlib.primitive.eq` / `stdlib.primitive.ne` right
after the `stdlib.integer.{lt,gt,…}` arm, reusing the existing exact-equality helper
`value_eq_exact` (Decimal-aware) — exactly the pattern the arithmetic fix used:

```rust
"stdlib.primitive.eq" => { … Value::Bool(value_eq_exact(&args[0], &args[1])?) }
"stdlib.primitive.ne" => { … Value::Bool(!value_eq_exact(&args[0], &args[1])?) }
```

No new equality logic — `value_eq_exact` is the one already used by the binary-op evaluator; this only
gives it the OP_CALL builtin name the compiler emits. Overflow/totality unaffected.

## Verification (all run on the rebuilt VM)

- probe `ViaMap([1,3,5], t=3)` → `[false, true, false]` (status success).
- `vm_loop_app.ig View(sel="lead:1")` → success; selected leaf = `lead:1` (the P7 case runs again).
- game `Reduce(initial, target=1)` with **direct `==`** → success; body 1 `vy: 0 → 1400`, others untouched.
- the direct-`==` kick result is **byte-identical** to the committed workaround fixture
  (`vm_game_kick.runtime.json`), so no fixture change is needed.
- `cargo test` (frame-ui): **99 passed / 0 failed**; `ig_vm_game` 8/8 (incl. `click_hit_tests_…`).
- the interactive harness `examples/vm_game.rs` still prints `click→kick … kicks ONLY that body  ✓`.
- `git diff --check`: clean.

## Specimen change

`specimens/dx-view-d/vm_game_app.ig` `KickBody` now uses direct equality:

```text
compute ky = if target == b.id { 1400 } else { 0 }   -- (and kx/kz) — no more (NOT id<t)*(NOT id>t)
```

(The comparand before `{` is the field `b.id`, not a bare ident — `if target == b.id {`, not
`if b.id == target {` — so it doesn't mis-parse as a record construct. That surface nit is separate from
the equality gap.) The stale `stdlib.primitive.eq missing` comment is replaced with the current truth.

## Answers to the card's questions

1. Does direct `b.id == target` compile+run? — YES, after the OP_CALL `stdlib.primitive.eq` fix.
2. Behavior unchanged? — YES, byte-identical kick result; tests + harness green.
3. Stale comment, or a real gap? — a REAL gap (`stdlib.primitive.eq` absent on the OP_CALL path),
   regressing `==` everywhere it lowers to OP_CALL — contradicting P1. Now fixed.
4. Next card → below.

## VM-ownership note

This touched the VM owners' file (`vm.rs`) — sanctioned by the card's regression clause. It is additive
(two match arms, reusing `value_eq_exact`) and mirrors their own arithmetic fix. Owners should reconcile
this with `LAB-VM-PRIMITIVE-EQ-PARITY-P1` (whose "no VM change needed" did not hold on this binary).

## Next card (recommended)

`LAB-VM-OPCALL-BUILTIN-NAME-AUDIT-P1` — sweep the OP_CALL builtin dispatch for the FULL set of names the
`igc` emits vs. what the VM matches (arithmetic + eq are now aligned; check `ne`, ordering aliases,
string/bool eq, `not`/`and`/`or`, etc.), so no further `stdlib.*` name appears unimplemented at runtime
while the binary-op/OP_* paths support it.
