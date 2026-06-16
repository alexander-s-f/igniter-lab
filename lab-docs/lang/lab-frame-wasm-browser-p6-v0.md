# lab-frame-wasm-browser-p6-v0 — the frame runtime runs LIVE in a real browser

**Card:** `LAB-FRAME-WASM-BROWSER-P6` (in the `igniter-frame` crate)
**Status:** CLOSED — proven LIVE in a real browser (headless verification via the preview harness).
The P5 honest gap ("`.wasm` + exports + native tests, but the browser never ran the glue/page") is
now closed: wasm-bindgen glue generated, a localhost page loads `WasmRuntime`, a real
`pointerdown` drives `click()`, the SVG re-renders from `render_svg()`, and a replayed click log
produces **byte-identical digests to the native runtime**.

## What was built (tooling kept separate from logic)

- **Tooling**: `cargo install wasm-bindgen-cli --version 0.2.125` (matches the `wasm-bindgen` dep in
  `Cargo.lock`); `cargo build --release --target wasm32-unknown-unknown --no-default-features
  --features wasm` → a 146 KB release `.wasm`; `wasm-bindgen --target web --out-dir web` → ES-module
  glue (`web/igniter_frame.js` 8 KB + `web/igniter_frame_bg.wasm` 120 KB). One script:
  `web/build.sh`.
- **The page** (`web/index.html`, no framework, no bundler): imports the glue as an ES module,
  `await init()` loads the wasm, `new WasmRuntime()`. On `pointerdown` it maps the browser client
  coords → the runtime's CSS space and calls `rt.click(cssX, cssY)` — that is ALL the JS does. It
  then injects `rt.render_svg()` into the DOM and shows `frame_index` / `render_digest` /
  lineage (`input → effect → frame`). A "Replay click log" button calls `rt.reset()` then replays a
  captured log, collecting `render_digest()` after each step.

```text
real pointerdown  →  JS: client → CSS coords (mapping only)  →  rt.click()  [Rust/WASM:
                      hit-test → intent → state → next frame]  →  rt.render_svg() → DOM
```

The host JS computes no intent. The whole loop is the Rust runtime.

## Proof (live, headless browser)

- **WASM loaded + callable**: `frame_index() == 0`, `render_digest() == sha256:884ff3aa4…`, the
  scene `<svg>` is in the DOM, e1 at `cx="150"`.
- **Real pointer → state change**: a dispatched `PointerEvent('pointerdown')` at e1's on-screen
  position (client ≈ 159,204) → `frame_index == 1`, the DOM `<svg>` now has `cx="200"`, lineage
  `input:0 → effect:0 → frame:1`, digest `sha256:6d8855560…`. The move came from a RE-PROJECTION of
  new state, not a frame patch.
- **Deterministic replay in-browser**: the captured log `[(300,400),(400,400),(500,400)]` →
  digests `[884ff3aa4, 6d8855560, ec2cc9406, 6dd6a1f81]` — **byte-identical** to the native
  `render_demo` / P5 native tests; e1 ends at `cx="300"`, `frame_index == 3`.
- **Boundary**: `igniter_frame_bg.wasm` contains no `igniter-machine` / `TBackend` / `rocksdb`
  symbols; the page talks only to `127.0.0.1`; no UI framework.

## Acceptance vs. card

| acceptance | status |
|---|---|
| wasm-bindgen glue generated | ✅ `web/igniter_frame.js` + `igniter_frame_bg.wasm` |
| local page served | ✅ `127.0.0.1:8731` (python http.server) |
| browser loads `WasmRuntime` | ✅ `await init()` + `new WasmRuntime()` |
| pointer/click calls `click()` | ✅ real `pointerdown` → `rt.click(cssX,cssY)` |
| SVG re-renders from `render_svg()` | ✅ DOM `<svg>` updates `cx` 150→200→…→300 |
| lineage / render_digest visible | ✅ panel + verified by eval |
| captured click log replay → same digests | ✅ byte-identical to native |
| JS does not compute intent | ✅ JS only maps client→CSS + forwards |
| no `igniter-machine`, localhost-only, no heavy framework | ✅ |

## Decisions

- **tooling vs logic** kept apart: the CLI install + glue gen + serve are a build step (`build.sh`);
  the runtime logic was untouched from P5. The browser runs the SAME Rust.
- **`--target web`** (ES module, no bundler) — the smallest honest harness; the page is one file.
- **mapping-only host**: JS maps client→CSS coords (the runtime's `Viewport` does CSS→frame); intent
  stays in Rust. The boundary from P4/P5 holds in the browser.
- **generated glue gitignored**: `web/igniter_frame.js` + `_bg.wasm` are build artifacts
  (`web/build.sh` regenerates them); only `index.html` + `build.sh` are sources.

## Closed (held) / next

The browser loop is now real. Held: no GPU, no UI framework, demo reducer only, localhost only.
Next, now that the runtime is a proven interactive frontend core:

- **re-home** `igniter-3d-poc` (its tick ≅ an `IntentReducer`) + `igniter-gui-engine` (its
  hit-test→intent ≅ `derive_intent`) over `igniter-frame` — a move onto a proven substrate, not a
  port for its own sake.
- **`igniter-ide`** — a time-travel frame viewer + replay strip over `__frames__` + the lineage
  chain, now that the live loop + deterministic replay are demonstrated end to end.
