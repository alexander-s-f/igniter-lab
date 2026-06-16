# igniter-frame — derived projection runtime

`igniter-frame` is the **projection runtime** over the `igniter-machine` substrate
(LAB-FRAME-PROJECTION-EXTRACT-P2). The machine stays a *boring state kernel* (facts, receipts,
capsules, capability IO, recovery); turning that state into an observable representation is a
**consumer** of the machine — a leaf/runtime layer, not the kernel.

```text
igniter-machine        = state kernel (TBackend facts / receipts / capsules / capability IO)
igniter-frame (this)   = projection ports + Frame + Camera + render-host abstraction
igniter-gui-engine     = UI/layout/hit-test over igniter-frame   (future)
igniter-3d-poc / -sim  = world/tick/camera/renderer              (future)
igniter-ide            = concrete app consuming those            (future)
```

This is the inverse of the wire-to-effect contour:

```text
wire-to-effect:  HTTP → capsule → intent → effect → receipt
fact-to-frame:   machine facts/capsule → world snapshot → Frame → receipt/render
```

## The boundary (the point of P2)

The **core is machine-agnostic** — it depends only on three ports and builds with zero
igniter-machine dependency:

```bash
cargo build --no-default-features   # core only — does NOT compile igniter-machine
cargo test                          # core + machine adapter — 6 checks green
```

- `FrameSource` — read the world to project (a `ProjectionSource`).
- `FrameSink` — record a frame receipt (`ReceiptLineage`).
- `RenderHost` — turn a frame into an artifact (swappable edge: SVG/JSON now, canvas/wgpu later).
- `IntentSink` — apply an input intent as a STATE effect (P3 input loop), never a frame mutation.

## The input loop (P3): `state → frame → input → intent → state`

`igniter-frame` is an interface RUNTIME, not a frame exporter. `input_step` hit-tests an input
against the current frame → an `Intent`, applies it through `IntentSink` (an effect that writes a
new state fact), then RE-PROJECTS the next frame. The input never patches the frame. Lineage
chains `input_receipt → effect_receipt → frame_receipt`; the loop is deterministic (same state +
same input log → same frames). The domain logic is a pure `IntentReducer` (`(intent, world) →
world deltas`) — a game tick or a GUI reducer plugs in here.

The `machine` feature (default-on) adds `machine_source::{TBackendFrameSource, TBackendFrameSink}`
binding the ports to `igniter_machine::backend::TBackend` (world facts in `__world__`, frame
receipts in `__frames__`). The machine itself knows nothing about `Frame`/`Camera`/`RenderHost`.

## Proof (6 checks — same as FP-P1, post-extraction)

`tests/frame_projection_tests.rs`: project-from-machine-facts; deterministic replay (byte-identical
digests); fact change → predictable frame change (sx 200→250); render-host swappable (SVG/JSON);
frame-is-a-fact (`__frames__` → time-travel history); empty-world stable.

## The renderer host (P4): render + forward, thin

`host.rs` (machine-free) renders a `Frame`, maps a real pointer event to frame coordinates
(`Viewport::pointer_to_frame`), and FORWARDS it to `input_step` — it computes no intent (the P3
loop does, in Rust). `MemWorld` is an in-memory `FrameSource + FrameSink + IntentSink`, so the
whole loop runs with zero kernel (browser/WASM-ready). `drive(world, camera, viewport,
pointer_log)` plays a captured pointer log → `HostFrame`s (SVG + lineage). `cargo run --example
render_demo` emits real Rust-computed frames an interactive browser viewer can play.

## WASM (P5): the runtime compiles to + is callable from the browser

`src/runtime.rs` (machine-free) runs the SAME P3 loop SYNCHRONOUSLY — `FrameRuntime` holds the
world directly and uses `project_snapshot` (the sync core of `project_frame`), so there is no async
/ reactor / `block_on` to ship. `src/wasm.rs` (feature `wasm`) is a thin `#[wasm_bindgen]
WasmRuntime` over it: the browser calls `new` / `render_svg` / `click(css_x,css_y)` / `frame_index`
/ `lineage_json` / `render_digest` / `reset`. All logic stays in Rust; JS renders the SVG and
forwards pointer coords (it computes no intent).

```bash
rustup target add wasm32-unknown-unknown
cargo build --target wasm32-unknown-unknown --no-default-features --features wasm
# → target/wasm32-unknown-unknown/debug/igniter_frame.wasm, machine-free (no kernel symbols linked)
```

The `wasm` feature is independent of `machine`; the linked `.wasm` contains no `igniter_machine`/
`TBackend`/`rocksdb` symbols. `tests/wasm_runtime_tests.rs` proves the exact runtime natively
(hit→move, miss→no-op, lineage, deterministic replay, reset).

## Live browser (P6): the runtime runs in a real browser

`web/index.html` (no framework, no bundler) loads the wasm as an ES module, holds one
`WasmRuntime`, and on `pointerdown` maps the browser client coords → the runtime's CSS space and
calls `rt.click()`. JS does nothing else — the hit-test → intent → state → next-frame loop is the
Rust runtime; the SVG is injected from `rt.render_svg()`. Build + serve:

```bash
cargo install wasm-bindgen-cli --version 0.2.125   # match the wasm-bindgen dep
web/build.sh                                        # build wasm + glue + serve 127.0.0.1:8731
# open http://127.0.0.1:8731/index.html
```

Proven live (headless): a real `pointerdown` on the dot moves it (DOM `<svg>` `cx` 150→200), lineage
`input→effect→frame` updates, and replaying the captured click log yields digests byte-identical to
the native runtime (`884ff3aa4, 6d8855560, ec2cc9406, 6dd6a1f81`). The generated `web/igniter_frame.js`
+ `igniter_frame_bg.wasm` are build artifacts (gitignored); `index.html` + `build.sh` are sources.

## Projection-agnostic runtime (P7/P8)

`FrameRuntime` is pluggable in two domain-neutral ways, so one runtime carries many domains:

- a **`Projector` port** (`world → Frame`): `CameraProjector` (perspective points, default) for
  2D/3D, or an orthographic box-layout projector for a GUI. `FrameRuntime::with_projector(...)`
  selects it; `new(...)` defaults to the camera.
- a **swappable `RenderHost`** (`SvgRenderHost` points / wireframe / GUI rects) and, alongside
  `click` (pointer), a **`send(action, params)`** system-intent path: `dispatch(action)` =
  `send(action, Null)` (a 3D/animation tick), and `send("type", {char})` routes a keystroke to a
  focused field (the host catches the DOM key, the reducer owns the value). Lineage is `<action>:N`.

`ProjectedNode` carries optional `sw`/`sh` (a screen box) + `data` (render payload); `hit_test` does
point-in-rect for box widgets and radius for points, so a GUI of rectangles and a 2D/3D scene of
points share one entry point. Point digests are unchanged (`[id,sx,sy]`). These power the sibling
domains `igniter-3d` (wireframe sim) and `igniter-gui` (layout/hit-test/intent).

## Boundary / status

Lab-only. No GUI / window / GPU / network. No stable schema or public API. Not Igniter Lang canon.
`Frame`/`Camera`/projection moved here OUT of `igniter-machine` so the kernel stays boring and
different projection domains (IDE frame, GUI layout, game world, 3D scene, trace viewer) can
diverge in their own crates without ontology soup in the machine.

## Next

`renderer-host` (browser SVG/canvas, live frames) and `input-loop` (user input → intent → effect/
tick, back through capability-IO) build on these ports — without risking turning the machine into a
do-everything combine.
