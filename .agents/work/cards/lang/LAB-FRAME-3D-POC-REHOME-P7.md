# Card: LAB-FRAME-3D-POC-REHOME-P7 — the 3D POC, re-homed over igniter-frame

> New crate `igniter-lab/igniter-3d`, over the `igniter-frame` ports/runtime (NOT the machine).
> Builds on `LAB-FRAME-WASM-BROWSER-P6`. Related: [[project-gui-3d-exploration]].

**Status: CLOSED 2026-06-16 — proven (native + live browser).** The deterministic 3D world runs
over igniter-frame's actual ports/runtime, stays replay-identical, renders a projection-heavy
wireframe through the SAME `RenderHost` boundary, plays live in the browser, machine-free. Design
doc: `lab-docs/lang/lab-frame-3d-poc-rehome-p7-v0.md`.

## Goal (met)

Re-home the 3D POC onto igniter-frame as the first of two domains over one runtime — proving the
runtime carries projection-heavy 3D + a time tick, not just 2D pointer UI.

## What it reuses

world = `{x,y,z}` FACTS (v0..v7) · tick = `IntentReducer` via `FrameRuntime::dispatch("tick")` ·
projection = `Camera` + `project_snapshot` · frame/digest/lineage = igniter-frame `Frame` ·
render = `WireframeRenderHost: RenderHost`. Depends on `igniter_frame` `default-features = false`
→ no machine.

## igniter-frame generalization (domain-neutral, 2D demo uses it too)

`FrameRuntime` gained a swappable `Box<dyn RenderHost>` (Svg ↔ Wireframe over one boundary) and a
`dispatch(action)` tick path (system event, no hit-test, same intent→effect→frame discipline +
lineage `tick:N→effect:N→frame:N+1`). No 3D math in the kernel; 22 igniter-frame tests still green.

## Proof

- **Native** (6 tests `igniter-3d/tests/cube3d_tests.rs`): wireframe boundary (12 line + 8 circle),
  tick advances+changes, deterministic tick, byte-identical replay, lineage discipline, reset.
- **WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → 154 KB
  `.wasm`, no machine symbols.
- **Live browser** (`igniter-3d/web/index.html`): auto-ticking cube (12 edges + 8 verts in DOM
  `<svg>`), lineage live, in-browser "Verify replay" 30 ticks ×2 → byte-identical (31 distinct).
- **native == wasm**: 30-tick first/last digests identical (`d2dc48356…` / `5119bc888…`) native AND
  browser → literally the same Rust.

## Acceptance

uses igniter-frame ports/runtime (no separate model) ✅ · tick deterministic ✅ · digest replay
byte-identical ✅ (native+browser+native==wasm) · browser plays 3D frames via same render-host ✅ ·
no GPU/window ✅ · machine not a dependency of core browser path ✅.

## Decisions

- re-home = reuse not fork (`Cube3dRuntime` wraps `FrameRuntime`);
- wireframe over the `RenderHost` boundary (projection-heavy, not one-point-per-entity);
- machine-free by construction (`default-features=false`);
- determinism via quantized rotation (round to 1e-6).

## Next

- P8: re-home `igniter-gui-engine` (hit-test→intent ≅ `derive_intent`, layout ≅ `IntentReducer`);
- then `igniter-ide` — time-travel viewer + replay strip + lineage inspector + frame diff over a
  substrate with TWO proven domains.
