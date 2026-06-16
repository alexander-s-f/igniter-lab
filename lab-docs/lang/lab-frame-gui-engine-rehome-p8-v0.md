# lab-frame-gui-engine-rehome-p8-v0 — the GUI reactive loop, re-homed over igniter-frame

**Card:** `LAB-FRAME-GUI-ENGINE-REHOME-P8` (new crate `igniter-gui`, over `igniter-frame`)
**Status:** CLOSED — proven (native + live browser). The GUI engine's reactive loop (layout →
hit-test → intent → update → re-layout) now runs over igniter-frame's actual ports/runtime — the
THIRD domain over one runtime (2D point UI, 3D sim, GUI), machine-free, deterministic, replayable.

## Why GUI after 3D (and before the IDE)

3D proved projection-heavy rendering + a time tick. GUI is the other shape: real layout, rectangular
widgets, and pointer→intent semantics. With both done, `igniter-frame` carries three classes over
one runtime, so `igniter-ide` (P9) becomes an app over a mature frame, not an experiment.

## Two domain-neutral generalizations to igniter-frame (so it carries GUI, not just points)

Both are pluggable strategies, mirroring the swappable `RenderHost` from P7; no GUI logic entered
the kernel, and all P3–P7 digests are unchanged (point nodes keep the `[id,sx,sy]` digest shape):

1. **Pluggable projection** — a `Projector` port (`world → Frame`). `CameraProjector` (perspective
   points) is the default; the GUI supplies a `LayoutProjector` (orthographic box stack).
   `FrameRuntime::with_projector(...)` selects it; `new(...)` still defaults to the camera, so
   igniter-3d and the 2D demo are untouched.
2. **Box hit-testing** — `ProjectedNode` gained `sw`/`sh` (optional screen box size) + `data`
   (render payload). `hit_test` tests box widgets by point-in-rect first, then falls back to the
   point-radius test. Point-only scenes behave exactly as before.

## The re-home (`igniter-gui`, depends on `igniter_frame` default-features = false → no machine)

| GUI concern | igniter-frame primitive it uses |
|---|---|
| widgets | world FACTS (`{role, label, done, on_click}`) |
| layout | `LayoutProjector` (a `Projector`) — vertical box stack |
| hit-test → intent | box-aware `hit_test` + `derive_intent`, via `FrameRuntime::click` |
| update (toggle / add + recount) | an `IntentReducer` |
| render | `GuiRenderHost` (rects + labels + checkboxes), a `RenderHost` |
| frame / digest / lineage / replay | igniter-frame `Frame` + `render_digest` + `input→effect→frame` |

A small but real interface: a "+ add task" button, toggleable task rows, and a live counter. Clicking
a row fires its `toggle` intent → the reducer flips `done` and recomputes the counter → re-layout.
Clicking "add" appends a row and the stack reflows. The display widget is hit but has no `on_click`,
so it produces no intent.

## Proof

**Native** (8 tests, `igniter-gui/tests/gui_tests.rs`, import only `igniter_gui`):
`layout_renders_widgets_as_boxes`, `click_toggle_marks_done_and_updates_counter`,
`click_add_appends_row_and_relayouts`, `display_widget_has_no_intent`,
`hit_test_uses_box_not_radius` (a corner click ~160px from centre still hits — proves rect not
radius), `deterministic_replay_of_ui_event_log`, `lineage_uses_the_same_runtime_discipline`,
`reset_returns_to_initial_ui`.

**WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → a 162 KB
`.wasm`; `igniter_gui_bg.wasm` has no `igniter-machine` / `TBackend` / `rocksdb` symbols.

**Live browser** (`igniter-gui/web/index.html`, headless-verified): a real `pointerdown` on a row →
`[x]` + counter `1 / 2 done`, lineage `input:0 → effect:0 → frame:1`; on "add" → a new `task 3` row
+ relayout (6 rects) + `1 / 3 done`; an in-browser "Verify replay" of a 5-event log is
byte-identical. JS only maps the pointer + draws `rt.render_svg()`.

## Acceptance vs. card

| acceptance | status |
|---|---|
| GUI engine uses igniter-frame ports/runtime where applicable | ✅ Projector + FrameRuntime + hit_test + IntentReducer + RenderHost |
| hit-test → intent maps to `derive_intent`/`input_step` | ✅ `FrameRuntime::click` → box `hit_test` → `derive_intent` |
| layout/update reducer maps to `IntentReducer` | ✅ `gui_reducer` (update); layout via the `Projector` |
| frame/digest/lineage preserved | ✅ same model; box digests extend, point digests unchanged |
| deterministic replay of a UI event log | ✅ native + in-browser |
| browser/WASM proof if feasible | ✅ live (not just build-proof) |
| no `igniter-machine` in browser/core path | ✅ `default-features=false`; no machine symbols in wasm |
| old GUI-engine tests ported or mirrored | ✅ core concerns mirrored (layout/hit-test/intent/reactive update/render) in 8 native tests |

## Decisions

- **re-home = mirror onto the runtime, not port 2900 Ruby lines**: the Ruby `igniter-gui-engine`
  remains the original disciplined engine; `igniter-gui` mirrors its reactive-loop essence
  (SceneTree≈facts, hit-test/intent, reduce→relayout→reframe) onto igniter-frame.
- **layout is a projection, update is a reducer**: clean split — `LayoutProjector` (positions) vs.
  `gui_reducer` (state). Both are igniter-frame ports.
- **box hit-test is domain-neutral**: it lives in igniter-frame (any boxed UI benefits), gated on
  `sw`/`sh` so point scenes are unaffected.

## Next

- **P9 `igniter-ide`**: a time-travel frame viewer + replay strip + lineage inspector + frame diff
  over `__frames__` — now an app over a substrate with THREE proven domains, not one demo.
