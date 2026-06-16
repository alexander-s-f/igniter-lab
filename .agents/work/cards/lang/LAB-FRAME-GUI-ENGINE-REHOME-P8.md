# Card: LAB-FRAME-GUI-ENGINE-REHOME-P8 — the GUI reactive loop, re-homed over igniter-frame

> New crate `igniter-lab/igniter-gui`, over the `igniter-frame` ports/runtime (NOT the machine).
> Builds on `LAB-FRAME-3D-POC-REHOME-P7`. Related: [[project-gui-3d-exploration]].

**Status: CLOSED 2026-06-16 — proven (native + live browser).** The GUI engine's reactive loop runs
over igniter-frame's ports/runtime — the THIRD domain (2D UI + 3D sim + GUI) over one runtime,
machine-free, deterministic, replayable. Design doc:
`lab-docs/lang/lab-frame-gui-engine-rehome-p8-v0.md`.

## Goal (met)

Mirror the GUI engine (layout → hit-test → intent → update → re-layout) onto igniter-frame as a
third real interface domain, so `igniter-ide` later sits over a mature frame.

## igniter-frame generalizations (domain-neutral, pluggable; P3–P7 digests unchanged)

1. **`Projector` port** (`world → Frame`): `CameraProjector` (perspective, default) vs.
   `LayoutProjector` (GUI box stack). `FrameRuntime::with_projector(...)`; `new(...)` still defaults
   to camera (3D/2D untouched).
2. **Box hit-test**: `ProjectedNode` += `sw`/`sh` (box size) + `data` (render payload); `hit_test`
   does point-in-rect for boxes, else radius. Point scenes unaffected; box digests extend
   `[id,sx,sy]→[id,sx,sy,w,h,data]`, points keep `[id,sx,sy]`.

## The re-home (`igniter-gui`, `igniter_frame` default-features=false → no machine)

widgets = FACTS · layout = `LayoutProjector` (`Projector`) · hit-test→intent = box `hit_test` +
`derive_intent` via `FrameRuntime::click` · update (toggle/add+recount) = `IntentReducer` · render =
`GuiRenderHost` (`RenderHost`). A real UI: add-button + toggleable task rows + live counter.

## Proof

- **Native** (8 tests `gui_tests.rs`): layout boxes, toggle+counter, add+relayout, display-no-intent,
  `hit_test_uses_box_not_radius` (corner click ~160px from centre hits), deterministic replay,
  lineage discipline, reset.
- **WASM build**: release wasm32 162 KB, no machine symbols.
- **Live browser** (`igniter-gui/web/index.html`): real `pointerdown` on a row → `[x]` + `1/2 done`,
  lineage `input:0→effect:0→frame:1`; add → `task 3` + relayout (6 rects) + `1/3 done`; in-browser
  Verify-replay byte-identical over 5 UI events. JS maps pointer + draws only.

## Acceptance

uses igniter-frame ports/runtime ✅ · hit-test→intent maps to derive_intent/input_step ✅ ·
layout/update reducer maps to IntentReducer ✅ · frame/digest/lineage preserved ✅ · deterministic
replay of UI event log ✅ (native+browser) · browser/WASM proof ✅ (live) · no machine in browser/core
path ✅ · old GUI-engine tests mirrored ✅ (core concerns, 8 native tests).

## Decisions

- re-home = mirror reactive-loop essence onto the runtime, not port 2900 Ruby lines (Ruby
  igniter-gui-engine stays the original engine);
- layout = projection, update = reducer (clean split, both igniter-frame ports);
- box hit-test domain-neutral in igniter-frame (gated on sw/sh).

## Next

- P9 `igniter-ide`: time-travel frame viewer + replay strip + lineage inspector + frame diff over
  `__frames__` — an app over a substrate with THREE proven domains.
