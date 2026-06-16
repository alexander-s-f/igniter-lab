# igniter-gui — a GUI over igniter-frame

`igniter-gui` re-homes the GUI engine's reactive loop (mirrored from the Ruby `igniter-gui-engine`,
NGUI-P1..P13) onto the **`igniter-frame`** runtime — the third of three domains over one runtime
(2D point UI, 3D sim, GUI). It is a thin domain crate; the runtime, projection port, hit-test, input
loop, and render boundary all come from igniter-frame.

```text
igniter-machine     = state kernel                       (NOT a dependency here)
igniter-frame       = FrameRuntime + Projector + hit_test + RenderHost + lineage/replay
igniter-gui (this)  = widget facts + LayoutProjector + gui_reducer + GuiRenderHost
```

Depends on `igniter_frame` with **`default-features = false`** → no `igniter-machine` in the
core/browser path.

## What it reuses

| GUI concern | igniter-frame primitive |
|---|---|
| widgets | world FACTS (`{role, label, done, on_click}`) |
| layout | `LayoutProjector` (a `Projector` — orthographic box stack) |
| hit-test → intent | box-aware `hit_test` + `derive_intent`, via `FrameRuntime::click` |
| update (toggle / add + recount) | an `IntentReducer` |
| render | `GuiRenderHost` (rects + labels + checkboxes), a `RenderHost` |
| frame / digest / lineage / replay | `Frame` + `render_digest` + `input → effect → frame` |

It exercises two domain-neutral generalizations added to igniter-frame for boxed UIs: a pluggable
`Projector` (orthographic layout vs. perspective camera) and box hit-testing (`ProjectedNode.sw/sh`);
point domains (2D/3D) are unaffected and their digests unchanged.

## Proof

```bash
cargo test                                                     # 8 native tests (machine-free)
cargo build --release --target wasm32-unknown-unknown --features wasm   # WASM build proof
```

A real UI: a "+ add task" button, toggleable task rows, and a live counter. Clicking a row fires its
`toggle` intent (reducer flips `done` + recomputes the counter + re-layout); clicking "add" appends a
row and the stack reflows; the display widget is hit but has no intent. Deterministic replay of a UI
event log yields identical frames.

## Live browser

```bash
cargo install wasm-bindgen-cli --version 0.2.125   # match the wasm-bindgen dep
web/build.sh                                        # build wasm + glue + serve 127.0.0.1:8733
# open http://127.0.0.1:8733/index.html
```

Click the widgets; JS only maps the pointer and draws `rt.render_svg()` — layout, hit-test, intent,
and the reducer run in Rust (WASM). "Verify replay" replays a UI event log twice and confirms
byte-identical frames. The generated `web/igniter_gui.js` + `igniter_gui_bg.wasm` are build artifacts
(gitignored); `index.html` + `build.sh` are sources.

## Boundary / status

Lab-only. No window, no GPU, no network beyond localhost, no UI framework. Not Igniter Lang canon.
The Ruby `igniter-gui-engine/` remains the original disciplined engine; this crate mirrors its
reactive-loop essence onto the shared runtime.
