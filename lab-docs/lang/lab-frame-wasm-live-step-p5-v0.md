# lab-frame-wasm-live-step-p5-v0 — the frame runtime compiles to (and is callable from) WASM

**Card:** `LAB-FRAME-WASM-LIVE-STEP-P5` (in the `igniter-frame` crate)
**Status:** CLOSED as **build-proof + runtime-proof** (Meta-Architect's named fallback for P5 when a
full live-browser harness is too infrastructure-noisy). A real `wasm32` artifact with the runtime
exports + machine-free linkage is proven; the *live in-browser run* (wasm-bindgen-CLI glue + served
page + click-through) is **P6**.

## Why WASM next (not igniter-ide, not re-home)

P4 showed a viewer PLAYING Rust-computed frames. The next qualitative step is the Rust loop itself
being able to LIVE in the browser — that is the test of whether `igniter-frame` is genuinely a
frontend runtime, not a frame exporter. Only after that does re-homing GUI/3D become a move onto a
proven substrate rather than a port for its own sake.

## What was built

1. **A synchronous runtime** (`src/runtime.rs`, machine-free): `FrameRuntime` runs the SAME P3 loop
   — `derive_intent` → reducer → re-project — but SYNCHRONOUSLY. No async, no reactor, no
   `block_on`. It holds the world directly and uses `project_snapshot` (the sync core extracted
   from `project_frame`). This is what makes it cleanly WASM-callable (no executor to ship).
   - `click(css_x, css_y) -> bool`: maps a real pointer to frame coords, hit-tests the CURRENT
     frame, and on a hit applies the intent as a STATE change, then advances. Input never mutates
     the frame; the next `render_svg` is a RE-PROJECTION. Returns whether an effect happened.
   - `render_svg` / `render_digest` / `frame_index` / `lineage_json` — read the current state.
2. **WASM bindings** (`src/wasm.rs`, feature `wasm`): a thin `#[wasm_bindgen] WasmRuntime`
   delegating to `FrameRuntime`. The browser calls `new` / `render_svg` / `click` / `frame_index` /
   `lineage_json` / `render_digest` / `reset`. ALL logic stays in Rust; JS renders the returned SVG
   and forwards pointer coords — it computes no intent.
3. **`wasm` feature** independent of `machine`: `--no-default-features --features wasm` pulls
   wasm-bindgen + the machine-free core, NO kernel. `crate-type = ["cdylib", "rlib"]`.

## Proof

**Build proof** (`wasm32-unknown-unknown`):

```bash
rustup target add wasm32-unknown-unknown
cargo build --target wasm32-unknown-unknown --no-default-features --features wasm   # Finished, clean
```

- a real `target/wasm32-unknown-unknown/debug/igniter_frame.wasm` (~5.8 MB debug) is produced;
- the `WasmRuntime` exports are present in the binary (`render_svg`, `click`, `frame_index`,
  `lineage_json`, `render_digest`, `reset` — via the wasm-bindgen describe shims);
- the linked wasm contains **NO `igniter_machine` / `TBackend` / `rocksdb`** symbols → machine-free
  is real at the binary level, not just at the source level.

**Runtime proof** (5 native tests, `tests/wasm_runtime_tests.rs`, import only `igniter_frame` — the
EXACT Rust the browser calls; `#[wasm_bindgen]` is a thin shell):

| acceptance | test |
|---|---|
| click updates state through the same loop (hit → intent → effect → re-project) | `click_hit_advances_state_and_moves_entity` (e1 sx 150→200) |
| a miss produces no effect, no advance, unchanged frame | `click_miss_no_effect_no_advance` |
| frame digest + lineage (`input → effect → frame`) visible | `lineage_visible_after_hit` |
| deterministic replay of a captured click log → byte-identical digests | `deterministic_replay_of_click_log` (e1 150→200→250→300) |
| reset reproduces the initial scene exactly (replay substrate) | `reset_returns_to_initial_scene` |

Full crate: 22 native green (6 extract + 5 input-loop + 6 host + 5 runtime) + the wasm32 build.

## Acceptance vs. card

| acceptance | status |
|---|---|
| `igniter-frame` builds to WASM without `igniter-machine` | ✅ compiles + linked wasm has no machine symbols |
| browser calls Rust `init/render/click` | ✅ `WasmRuntime` exports present in the wasm |
| click updates state through same `input_step` | ✅ `FrameRuntime.click` = the P3 loop, sync (native-tested) |
| host JS does not compute intent | ✅ all logic in Rust; JS only renders SVG + forwards coords |
| frame digest / lineage visible | ✅ `render_digest` + `lineage_json` exports |
| deterministic replay of a captured click log | ✅ native test + `reset` |
| no GPU, no heavy UI framework, no machine dependency | ✅ |
| **live in-browser run** | ⏭ **P6** (needs wasm-bindgen-CLI JS glue + a served page) |

## Decisions

- **synchronous runtime for the frontend edge**: the async ports are for the machine adapter; the
  in-memory runtime bypasses them (`project_snapshot` + pure hit-test/reducer) so WASM ships no
  executor. Same loop, same determinism.
- **`wasm` feature ⟂ `machine` feature**: the binary proof shows the kernel is genuinely absent.
- **thin bindings**: `WasmRuntime` only delegates; the loop is testable natively (the browser runs
  identical Rust).

## Closed (held) / next

- **P6 = live browser**: run wasm-bindgen-CLI to emit the JS glue, serve a one-file page that loads
  the `.wasm`, render `render_svg()` into the DOM, forward `pointerdown` → `click()` → re-render;
  show live lineage + a replay strip. (Held here only to avoid infra noise; the runtime is ready.)
- then **re-home** `igniter-3d-poc` (tick ≅ reducer) + `igniter-gui-engine` (hit-test ≅
  `derive_intent`) over `igniter-frame`; and **`igniter-ide`** time-travel viewer over `__frames__`.
- No GPU, no UI framework, demo reducer only, core compiles machine-free.
