# Card: LAB-FRAME-WASM-BROWSER-P6 — the frame runtime runs LIVE in a real browser

> In the `igniter-frame` crate (over the ports — NOT the machine). Builds on
> `LAB-FRAME-WASM-LIVE-STEP-P5`. Related: [[project-gui-3d-exploration]].

**Status: CLOSED 2026-06-16 — proven LIVE** (headless browser via the preview harness). Closes the
P5 honest gap: glue generated, localhost page loads `WasmRuntime`, real `pointerdown` → `click()` →
SVG re-renders, replay → byte-identical digests to native. Design doc:
`lab-docs/lang/lab-frame-wasm-browser-p6-v0.md`.

## Goal (met)

Run the Rust frame runtime LIVE in a browser; JS only maps the pointer + calls Rust; deterministic
replay holds end to end.

## Implementation (tooling separate from logic)

- **Tooling** (`web/build.sh`): `wasm-bindgen-cli 0.2.125` (matches dep); `cargo build --release
  --target wasm32-unknown-unknown --no-default-features --features wasm`; `wasm-bindgen --target web
  --out-dir web` → `igniter_frame.js` + `igniter_frame_bg.wasm`; `python3 -m http.server`.
- **Page** (`web/index.html`, no framework/bundler): ES-module import, `await init()`,
  `new WasmRuntime()`; `pointerdown` → map client→CSS → `rt.click()`; inject `rt.render_svg()` into
  DOM; show `frame_index`/`render_digest`/lineage; "Replay click log" resets + replays in Rust.
- Runtime logic UNCHANGED from P5 (the browser runs the same Rust). Generated glue gitignored.

## Proof (live headless)

- wasm loaded: `frame_index 0`, digest `884ff3aa4…`, `<svg>` in DOM, e1 `cx="150"`.
- real `pointerdown` at e1 (client ≈159,204) → `frame_index 1`, DOM `<svg>` `cx="200"`, lineage
  `input:0→effect:0→frame:1`, digest `6d8855560…`.
- replay log `[(300,400),(400,400),(500,400)]` → `[884ff3aa4,6d8855560,ec2cc9406,6dd6a1f81]`
  **byte-identical to native render_demo/P5**; e1 `cx="300"`, `frame_index 3`.
- boundary: `igniter_frame_bg.wasm` no `igniter-machine`/`TBackend`/`rocksdb`; localhost only; no UI framework.

## Acceptance

glue generated ✅ · page served (127.0.0.1:8731) ✅ · browser loads WasmRuntime ✅ · pointer calls
click() ✅ · SVG re-renders from render_svg() ✅ · lineage/digest visible ✅ · replay → same digests ✅
(byte-identical) · JS computes no intent ✅ · no machine / localhost-only / no framework ✅.

## Decisions

- tooling (CLI/glue/serve) vs logic kept apart; runtime untouched from P5;
- `--target web` (one-file ES-module page, no bundler);
- mapping-only host (JS client→CSS; runtime CSS→frame; intent in Rust);
- generated `.js`/`_bg.wasm` gitignored, `build.sh` regenerates.

## Next

- re-home `igniter-3d-poc` (tick ≅ `IntentReducer`) + `igniter-gui-engine` (hit-test ≅
  `derive_intent`) over `igniter-frame` — now a proven interactive frontend core;
- `igniter-ide` — time-travel frame viewer + replay strip over `__frames__` + lineage.
