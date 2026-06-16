# Card: LAB-FRAME-WASM-LIVE-STEP-P5 — the frame runtime compiles to + is callable from WASM

> In the `igniter-frame` crate (over the ports — NOT the machine). Builds on
> `LAB-FRAME-RENDERER-HOST-P4`. Related: [[project-gui-3d-exploration]].

**Status: CLOSED as build-proof + runtime-proof 2026-06-16** (Meta-Architect's named fallback for
P5 when a full live-browser harness is too infra-noisy). Real `wasm32` artifact + machine-free
linkage + native runtime tests. **Live in-browser run = P6.** Design doc:
`lab-docs/lang/lab-frame-wasm-live-step-p5-v0.md`.

## Goal (met, minus live-run)

Prove `igniter-frame` is a real frontend runtime: the SAME loop runs in WASM, machine-free, the
browser calling Rust for render/click; JS computes no intent.

## Implementation

- `src/runtime.rs` (machine-free): `FrameRuntime` — the P3 loop run SYNCHRONOUSLY (no async/reactor/
  `block_on`); holds the world directly + `project_snapshot` (sync core extracted from
  `project_frame`). `click(css_x,css_y)->bool` (map→hit-test→intent→state→advance; input never
  mutates the frame), `render_svg`/`render_digest`/`frame_index`/`lineage_json`, `demo()`.
- `src/wasm.rs` (feature `wasm`): thin `#[wasm_bindgen] WasmRuntime` delegating to `FrameRuntime`.
- `wasm` feature ⟂ `machine`; `crate-type = ["cdylib","rlib"]`.

## Proof

- **Build**: `cargo build --target wasm32-unknown-unknown --no-default-features --features wasm` →
  real `igniter_frame.wasm` (~5.8 MB debug); `WasmRuntime` exports present in the binary; NO
  `igniter_machine`/`TBackend`/`rocksdb` symbols linked → machine-free at binary level.
- **Runtime** (5 native tests, `tests/wasm_runtime_tests.rs`, import only `igniter_frame`):
  `click_hit_advances_state_and_moves_entity` (sx 150→200), `click_miss_no_effect_no_advance`,
  `lineage_visible_after_hit`, `deterministic_replay_of_click_log` (150→200→250→300),
  `reset_returns_to_initial_scene`. Crate 22 native green + the wasm32 build.

## Acceptance

builds to WASM w/o machine ✅ · browser calls Rust init/render/click ✅ (exports in wasm) · click
updates state through same loop ✅ (native-tested) · host JS computes no intent ✅ · digest/lineage
visible ✅ · deterministic replay ✅ · no GPU/UI-framework/machine-dep ✅ · **live in-browser run ⏭ P6**.

## Decisions

- sync runtime for the frontend edge (async ports = machine adapter only; WASM ships no executor);
- `wasm` feature independent of `machine` (binary proof: kernel absent);
- thin bindings (loop testable natively → browser runs identical Rust).

## Next

- **P6 live browser**: wasm-bindgen-CLI glue + served one-file page; `render_svg()`→DOM,
  `pointerdown`→`click()`→re-render; live lineage + replay strip.
- re-home `igniter-3d-poc` (tick ≅ reducer) + `igniter-gui-engine` (hit-test ≅ `derive_intent`);
- `igniter-ide` time-travel viewer over `__frames__` + lineage.
