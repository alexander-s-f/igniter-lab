# LAB-FRAME-3D-GAME-IG-P5 — INTERACTION in `.ig` too → a fully interactive Igniter game on the VM

Status: CLOSED — a click hit-tests a body and an `.ig` reducer kicks it on `igniter-vm`. Logic, view,
AND interaction are all `.ig`. One VM gap found + worked around + routed.
Lane: igniter-lab / frame-ui / 3D + gamedev → igniter-vm
Date: 2026-06-27
Builds on: P3 (`.ig` logic), P4 (`.ig` view), P6 (the view+logic click→reducer pattern).

## Result

The game is now interactive THROUGH the language, the P6 way: the host hit-tests a click into a body
id; the `.ig` `Reduce(world, target)` kicks that body on the VM; the `.ig` `View` re-projects.

```text
Scene  --frame-ui scene_hit(click)-->  body id  --igniter-vm Reduce(world, id)-->  world'
       --igniter-vm View(world')-->  Scene'  --frame-ui render-->  SVG
```

## What's `.ig` (`specimens/dx-view-d/vm_game_app.ig`, compiles + runs)

- `Body` gains an integer `id`; `View`'s markers carry it (so a click maps back to a body).
- `contract KickBody(b, target) -> Body` — kick (up + radial-out impulse) the body whose `id == target`.
- `contract Reduce(world, target) -> World` — `map(world.bodies, b -> call_contract("KickBody", b, target))`.
- (plus P3's `Step` and P4's `View`/`ProjectBody`.)

`Reduce(initial, target=1)` on `igniter-vm` → body 1's `vy: 0 → 1400`, all others unchanged.

## Proven

- **Live, self-checked harness** (`examples/vm_game.rs`) — now ends with the interaction step:
  ```text
  click→kick   ·  hit-test marker 1 → .ig Reduce kicks ONLY that body (vy 0→1400)  ✓
  ```
  (after the existing `.ig` Step/View == Rust, replay, time-travel checks).
- **CI** (`tests/ig_vm_game_tests.rs`, 8/8): `scene_hit` at a marker centre → the body id; the `.ig`
  `Reduce(kick)` (fixture `vm_game_kick.runtime.json`) == the Rust mirror `kick_world_json`; only the
  clicked body is kicked; `scene_hit` misses empty space. **98 frame-ui tests pass / 0.**
- **Live browser** (`web/game_live.html`): six bodies fall; CLICK one → it's kicked up. Runs the Rust
  MIRRORS of `Step`/`View`/`Reduce` (proven bit-identical, cross-checked every harness run) — because the
  VM is native and rAF needs ~60fps. No console errors.

## VM gap found + worked around + routed

The `.ig` `Reduce`'s body match needs equality (`id == target`), but inside a `map`→`call_contract`
contract the VM's OP_CALL path does NOT dispatch `stdlib.primitive.eq` (`==` on Integer/String) —
`OP_CALL: Unknown/unimplemented function 'stdlib.primitive.eq'` — even though `<`/`>` (`stdlib.integer.lt/
gt`) ARE there (same shape as the now-fixed `stdlib.integer.add`). Equality used directly in a compute
works (the binary-op evaluator); via `map`→`call_contract` it doesn't.

WORKAROUND (so P5 closes today): express `id == target` with `<`/`>` only —
`hit = (NOT target>id) * (NOT target<id)` — no `==`. (Also: a bare-ident comparand right before `{`,
e.g. `if x < target {`, mis-parses as a record construct; written `if target > x {`.)

**Routed:** `LAB-VM-PRIMITIVE-EQ-OPCALL-PARITY` — dispatch `stdlib.primitive.eq` on the VM OP_CALL path
(mirror the `stdlib.integer.add` fix), so `.ig` reducers can use `==` inside `map`-called contracts.

## Frame-ui contribution

`game_loop.rs`: bodies thread an integer `id` through the JSON; `kick_world_json` (Rust mirror of the
`.ig` `Reduce`), `scene_hit` (host hit-test over a projected scene → body id). wasm `WasmSceneGame`
(live Rust-mirror game) + `web/game_live.html`.

## Net — the arc is fully closed

An Igniter app — **logic, view, AND interaction** — is authored entirely as `.ig`, runs on `igniter-vm`,
and is interactive: deterministic, replayable, time-travellable, click-driven. frame-ui is a thin,
machine-free render / hit-test / host shell. No `.igv` runtime, no "Rust that returns a string".

## Next options

- Route + land the `stdlib.primitive.eq` OP_CALL fix, then drop the `<`/`>` workaround for plain `==`.
- A real GPU render host (wgpu/WebGL) for filled z-buffered 3D.
- Author the 8-vertex cube wireframe projection in `.ig` for full 3D fidelity.
