# lab-frame-3d-poc-rehome-p7-v0 — the 3D POC, re-homed over igniter-frame

**Card:** `LAB-FRAME-3D-POC-REHOME-P7` (new crate `igniter-3d`, over `igniter-frame`)
**Status:** CLOSED — proven (native + live browser). The deterministic 3D world no longer has its
own standalone model: it runs over igniter-frame's actual ports/runtime, stays deterministic and
replay-identical, renders a projection-heavy wireframe through the SAME `RenderHost` boundary as the
2D UI, and plays live in the browser — machine-free.

## Why 3D first (not the GUI engine, not the IDE)

The 3D POC already proved deterministic world/tick/render, and it is the smaller, sharper test of
whether `igniter-frame` is a real runtime: it forces *projection-heavy* rendering (8 vertices + 12
edges per object, not one point per entity) and a *time tick* (not just pointer input). Re-homing it
first means `igniter-ide` later gets TWO domains over one runtime, not one demo.

## What this re-home actually reuses (the point)

| 3D concern | igniter-frame primitive it now uses |
|---|---|
| world (cube) | world FACTS — one `{x,y,z}` fact per vertex (`v0..v7`) |
| world tick (rotate) | an `IntentReducer` dispatched via `FrameRuntime::dispatch("tick")` |
| projection | `Camera` (already perspective) + `project_snapshot` |
| frame / digest / lineage | igniter-frame `Frame` + `render_digest()` + `input→effect→frame` |
| render (wireframe) | `WireframeRenderHost` implementing the `RenderHost` trait |

`igniter-3d` depends on `igniter_frame` with **`default-features = false`** → no `igniter-machine`
in the core path. It is a thin domain crate, not a fork of the runtime.

## Generalization made to igniter-frame (so it carries 3D, not just 2D)

`FrameRuntime` gained two things, both used by the 2D demo too:

- a **swappable render host** (`Box<dyn RenderHost>`) — `SvgRenderHost` (2D points) ↔
  `WireframeRenderHost` (3D edges) over one boundary;
- a **`dispatch(action)`** path — a system/tick event (no hit-test) applied through the reducer with
  the same "intent → effect → next frame" discipline + lineage (`tick:N → effect:N → frame:N+1`).

No 3D math entered igniter-frame; the kernel of the runtime is unchanged. (22 igniter-frame tests
still green.)

## Proof

**Native** (6 tests, `igniter-3d/tests/cube3d_tests.rs`, import only `igniter_3d`):
`wireframe_renders_through_render_host_boundary` (12 `<line>` + 8 `<circle>`),
`tick_advances_and_changes_the_frame`, `world_tick_is_deterministic` (two runs → identical digest
streams), `replay_is_byte_identical` (>5 distinct frames → genuinely rotating),
`lineage_uses_the_same_runtime_discipline` (`tick:0 → effect:0 → frame:1`),
`reset_returns_to_initial_frame`.

**WASM build proof**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → a
154 KB `.wasm`; `wasm-bindgen --target web` → glue; `igniter_3d_bg.wasm` contains no
`igniter-machine` / `TBackend` / `rocksdb` symbols.

**Live browser** (`igniter-3d/web/index.html`, headless-verified): the cube auto-ticks (12 edges +
8 vertices in the DOM `<svg>`), lineage `tick:N → effect:N → frame:N+1`; an in-browser "Verify
replay" runs 30 ticks twice → **byte-identical** (31 distinct frames). JS only calls `rt.tick()` +
draws `rt.render_svg()` — all rotation/perspective/wireframe is Rust.

**Same runtime, native == wasm**: a 30-tick run's first/last digests are identical native and in the
browser:

```
first = sha256:d2dc48356…   last = sha256:5119bc888…   (native AND browser)
```

This is the P6 property carried to 3D: it is literally the same Rust, not a JS re-implementation.

## Acceptance vs. card

| acceptance | status |
|---|---|
| 3D POC uses igniter-frame ports/runtime (no separate model) | ✅ world=facts, tick=reducer via `FrameRuntime`, project=`Camera`, render=`RenderHost` |
| 3D world tick deterministic | ✅ native + browser |
| frame/render digest byte-identical replay | ✅ native, browser, and native==wasm |
| browser/WASM host plays 3D frames through same render-host boundary | ✅ live spinning wireframe |
| no GPU/window | ✅ headless SVG only |
| `igniter-machine` not a dependency of the core browser path | ✅ `default-features=false`; clean dep tree; no machine symbols in wasm |

## Decisions

- **re-home = reuse, not fork**: `Cube3dRuntime` wraps `FrameRuntime`; the 3D domain is facts + a
  reducer + a `RenderHost`. The only runtime change was the two domain-neutral generalizations.
- **wireframe over the RenderHost boundary**: proves the boundary handles projection-heavy output,
  not only one-point-per-entity UI.
- **machine-free by construction**: `default-features = false` on `igniter_frame`.
- **determinism via quantized rotation** (round vertex coords to 1e-6) — replay-stable digests.

## Next

- **P8**: re-home `igniter-gui-engine` (its hit-test→intent ≅ `derive_intent`, its layout reducer ≅
  an `IntentReducer`) over `igniter-frame` — the second domain done, the GUI one.
- then **`igniter-ide`** — a time-travel viewer + replay strip + lineage inspector + frame diff,
  now over a substrate with TWO proven domains (2D UI + 3D sim), not one demo.
