# igniter-3d — the 3D POC, re-homed over igniter-frame

`igniter-3d` re-homes the deterministic 3D POC (originally proven in Ruby under
`igniter-3d-poc/`, G3D-P1) onto the **`igniter-frame`** runtime — the first of two domains over one
runtime (the GUI engine is P8). It is a thin domain crate: the 3D world is igniter-frame world
facts, the tick is an `IntentReducer`, the projection is igniter-frame's `Camera`, and the render
is a `WireframeRenderHost` implementing igniter-frame's `RenderHost` trait.

```text
igniter-machine     = state kernel                         (NOT a dependency here)
igniter-frame       = projection ports + Frame + FrameRuntime + Camera + RenderHost
igniter-3d (this)   = cube world facts + tick reducer + wireframe host over igniter-frame
```

It depends on `igniter_frame` with **`default-features = false`** → there is no `igniter-machine`
in the core/browser path.

## What it reuses (the re-home, not a fork)

| 3D concern | igniter-frame primitive |
|---|---|
| world (cube) | one `{x,y,z}` FACT per vertex (`v0..v7`) |
| tick (rotate) | an `IntentReducer` via `FrameRuntime::dispatch("tick")` |
| projection | `Camera` (perspective) + `project_snapshot` |
| frame / digest / lineage | `Frame` + `render_digest()` + `tick → effect → frame` |
| render (wireframe) | `WireframeRenderHost: RenderHost` (same boundary as the 2D `SvgRenderHost`) |

## Proof

```bash
cargo test                                                     # 6 native tests (machine-free)
cargo build --release --target wasm32-unknown-unknown --features wasm   # WASM build proof
```

- determinism + byte-identical replay (native, in-browser, and **native == wasm**: a 30-tick run's
  first/last digests are identical native and in the browser — literally the same Rust);
- a projection-heavy wireframe (12 edges + 8 vertices) through the `RenderHost` boundary;
- `igniter_3d_bg.wasm` contains no `igniter-machine` / `TBackend` / `rocksdb` symbols.

## Live browser (spinning cube)

```bash
cargo install wasm-bindgen-cli --version 0.2.125   # match the wasm-bindgen dep
web/build.sh                                        # build wasm + glue + serve 127.0.0.1:8732
# open http://127.0.0.1:8732/index.html
```

The cube auto-ticks; JS only calls `rt.tick()` and draws `rt.render_svg()` — all rotation,
perspective, and wireframe are Rust (WASM). "Verify replay" runs 30 ticks twice in the browser and
confirms byte-identical digests. The generated `web/igniter_3d.js` + `igniter_3d_bg.wasm` are build
artifacts (gitignored); `index.html` + `build.sh` are sources.

## Boundary / status

Lab-only. No GPU, no window, no network beyond localhost, no UI framework. Not Igniter Lang canon.
The Ruby `igniter-3d-poc/` remains the original math proof; this crate is its re-home onto the
shared runtime.
