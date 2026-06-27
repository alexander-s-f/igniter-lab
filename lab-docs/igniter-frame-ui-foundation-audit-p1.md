# IGNITER-FRAME-UI-FOUNDATION-AUDIT-P1 - dual-lens audit: problems + the unpause path for UI/GUI/3D/gamedev

Status: OPEN - findings + forward direction (no code changed)
Lane: igniter-lab / frame-ui / foundation + unpause
Type: audit (problem lens) + opportunity synthesis (solution lens)
Date: 2026-06-26
Skill: idd-agent-protocol

## Onboarding

Lab/frontier evidence, not authority. **Dual-lens** pass over the frame-ui stack
(10 crates, ~7.6k LOC Rust + Ruby legacy): **Lens 1** = find what BREAKS; **Lens 2**
= find the insights/solutions to bring this area out of pause and prove Igniter
applies across **all UI/GUI + 3D + game-dev** directions with **pleasant DX**.
First-hand reads of `igniter-frame` core + `igniter-render-html`; 3 dual-lens
subagent passes (ui-kit, 3d/gui/wasm, console+legacy). Code-first verify-first.

## Executive Decision

```text
decision=DUAL-LENS - the architecture is the strongest UI thesis I've seen and it is NOT stuck on a bug; it is parked at one clean human gate behind a fully-proven (P1->P21, 114 tests, machine-free, WASM-clean) stack. The unpause is a small set of high-leverage moves, not a rescue.
problem_severity=LOW - 1 browser-reachable panic (empty leads), dormant attribute-XSS (esc lacks "/'), one cross-arch determinism crux (world_digest over raw f64 + std sin/cos). The crash surface is otherwise clean.
the_thesis_HOLDS=ONE FrameRuntime genuinely drives 2D/3D/GUI/HTML by swapping only Projector + RenderHost; frames are content-addressed + byte-identical + replayable; UI state IS facts/receipts (machine feature). Verified in code, not just claimed.
unique_wedge=deterministic, replayable, time-travel-debuggable, FACT-SOURCED UI - a position no React/Svelte/Bevy/egui holds. The console already fuses replay + visual diff + receipt lineage INTO the runtime.
keystone=(1) re-point the IDE preview off the 91k-LOC Ruby view-engine onto the Rust projector [retires legacy + promotes the Rust stack into the live IDE in one move] (2) recursive container + integer layout pass [kills the per-screen-projector tax] (3) enrich the frame DATA model (3D pos+topology+z+material) then a wgpu/canvas RenderHost + a dt tick driver [makes "3D/gamedev" real, not wireframe-only] (4) make the console an EDITOR not just a debugger
next=FRAME-UI-IDE-PREVIEW-REHOME-P2 + FRAME-UI-LAYOUT-VOCAB-P2 + FRAME-UI-WGPU-HOST-P2 + FRAME-UI-CONSOLE-AUTHOR-P2
```

## The thesis holds — and the wedge is unique (verified in code)

`igniter-frame` is a machine-agnostic projection runtime (builds `--no-default-
features`, zero machine dep) with three ports — `FrameSource` / `FrameSink` /
`RenderHost` — plus `Projector`, `Camera`, `hit_test`, and a deterministic input
loop `state → frame → input → intent → state` (`igniter-frame/src/lib.rs`). The
domains (`igniter-3d`, `igniter-gui`, `igniter-ui-kit`, `igniter-render-html`) are
**thin** crates that swap a `Projector` + a `RenderHost` over the SAME runtime. This
is real: one loop drives a 3D camera scene, a GUI layout, a forms kit, and an HTML
projection.

**What no mainstream UI framework has (the wedge):**
- **One runtime, N domains** — not a per-domain engine (Bevy/egui/React each own one
  domain; this is one `state→frame→input→intent→state` for all of them).
- **Content-addressed, byte-identical frames** — every frame carries `world_digest`
  + `render_digest` (blake3 of canonical JSON); replay is proven bit-identical.
- **Fact-sourced lineage to a real kernel** — under the `machine` feature, frames /
  inputs / effects are bitemporal facts with receipts; UI state *is* facts.
- **Time-travel + visual diff + receipt lineage fused INTO the runtime** — the
  console is "Redux DevTools + visual diff + receipt lineage" built into the engine,
  not bolted on (replay strip → time-travel; `diff_frames` node-level added/removed/
  moved/changed; `input→effect→frame` digest lineage).

That is a genuinely defensible "Igniter for UI" position. The work is not to invent
it — it exists and is proven — but to **lift three structural ceilings and retire the
legacy** so it becomes pleasant and complete.

## LENS 1 — Problems (small, clean codebase)

**[BLOCKER] Empty `leads` array panics the public authoring entry.**
`workbench_from_value` validates `fields` non-empty but never checks `leads`
(`ui-kit/src/view_artifact.rs:160`); `Workbench::initial_world` then does
`self.leads[0]` unconditionally (`ui-kit/src/composition.rs:90`). A `workbench`
artifact with `"data":{"leads":[]}` compiles, then panics — **reachable from the
WASM `WasmWorkbench::from_artifact`** (`ui-kit/src/wasm.rs:69`), so a malformed
artifact fetched in the browser aborts the instance. Reproduced
(`index out of bounds: len is 0`). One-line guard mirroring the `fields` check.

**[PROBLEM] Dormant attribute-XSS: `esc()` escapes `& < >` but not `"`/`'`.**
The shared `esc` (`gui/src/lib.rs:125`, `ui-kit/src/lib.rs:355`, `composition.rs:344`,
`binding.rs:436`) is **safe today** — every call site lands in SVG `<text>` *element
content*, never an attribute — but goes live the instant any host writes a world
string into an SVG/HTML **attribute** (a future `link href`/`title`/`class`, or an
HTML render host). Plus the already-found `safe_url` control-char bypass in
`igniter-render-html`. Fix: add `"`/`'` + an attribute-vs-text-context distinction.

**[PROBLEM] Cross-arch determinism crux — `world_digest` over raw f64 + std trig.**
Screen digests are arch-stable (integer `sx/sy`, and `render_digest` excludes the
f64 world coords). But `world_digest` hashes the **raw f64** world snapshot, and the
3D tick uses **std `f64::sin/cos`** (`igniter-3d/src/lib.rs:72`) — not the lab's
deterministic `det_*` trig. So the *world* digest (the replay anchor) is not
guaranteed bit-identical cross-arch. This is the exact f64-fragility flagged in the
VM/stdlib audits, here on the UI replay anchor. Fix: route the tick through `det_*`
and canonicalize/round f64 before the world digest. **Determinism is otherwise solid**
(id-sorted nodes, integer screen coords, BTreeMap key order, no time/RNG in projection).

**[PROBLEM] Console embeds the target SVG verbatim** (`console/src/lib.rs:331`,
`replacen("<svg ", …)`): the console escapes its own chrome but trusts the kit's
render hosts to have escaped the embedded frame. The escaping discipline lives in the
kit, not at the console sink — load-bearing before the console ingests untrusted
artifacts.

**[INSIGHT] Crash surface otherwise clean + stringly-erosion at the field layer.**
`project_snapshot`/`hit_test`/parsers use `unwrap_or`/`saturating_mul` throughout (no
panic on malformed world data); the field vocabulary (`FieldKind = Text|Select|
Checkbox`) and `.igv` `input` values (`igv.rs:148`, forced to `String`) stringly-erase
— closer to "stringly-typed form" than "typed component" for a stack whose pitch is
typed/fact-sourced UI.

## LENS 2 — The unpause: ceilings, roadmap, differentiator

**Why it's paused (stated + code-verified):** the wave P1→P21 is fully CLOSED and
green (114 tests, all machine-free, WASM-clean), parked at ONE clean human gate —
"a real executor over local TLS / SparkCRM, behind the existing human-gated machine
live gate." Crossing it moves from machine-free lab into real external IO — a human
decision, the "no dead-end" seam held open. **It is not stuck on a bug.**

### The three structural ceilings (what actually blocks strong development)

- **Ceiling A — the node tree is FLAT and layouts are hardcoded coordinate math.**
  Every screen that isn't "form"/"workbench" requires a new Rust projector with
  hand-tuned `i64` constants (`MARGIN`/`GAP`/columns, `composition.rs`). There is no
  recursive container node, so you cannot compose a panel-in-list-in-panel. This is
  the #1 DX tax and the reason `.igv` is stuck authoring one template.
- **Ceiling B — the frame DATA model is screen-points-only; the GPU/3D gap is the
  data model, not missing wgpu code.** `Camera::project` destroys z into 2D `(sx,sy)`
  **before** the host runs; `Frame` carries id-sorted screen points with no depth /
  topology / transforms / materials / z-order. The cube only renders because
  `WireframeRenderHost` re-derives edges from a hardcoded const `EDGES` table —
  topology lives in the *renderer*, not the data. A wgpu host would have nothing to
  draw; `RenderHost` returns `String`, not draw calls.
- **Ceiling C — game-loop: right shape, wrong driver.** `(world,intent)→deltas` is a
  game step, but there is no `dt` / fixed timestep / held-input state / animation /
  physics; a fixed `ANGLE_STEP` couples motion speed to frame rate. It is an
  event-driven UI loop wearing a game-loop label.

### Legacy map (retire vs re-home)

| Ruby crate | Verdict |
|---|---|
| `igniter-3d-poc` (~409 LOC) | SUPERSEDED + DEAD → `igniter-3d`. **Archive now.** |
| `igniter-gui-engine` (~7.4k LOC) | SUPERSEDED + effectively DEAD → `igniter-gui`. **Archive now.** |
| `igniter-view-engine` (~91k LOC Ruby/JS) | **DANGLING — `KEEP_LIVE`.** Still the live `igniter-ide` preview backend (~20 hardcoded `resolve_workspace_path("frame-ui/igniter-view-engine/…")`). The `.igv` *format* IS re-homed (`ui-kit/src/igv.rs::lower_igv`); only the Ruby *tree* lingers as the IDE's preview server. |

Drift to flag: `igniter-render-html` re-implements the ViewArtifact schema
independently of ui-kit (a second parser that can drift; it already has a `link`
node ui-kit's compiler lacks).

### The unpause roadmap (ranked — each is a "paused → developing" lever)

1. **Re-point the IDE preview off `igniter-view-engine` onto the Rust projector**
   (`igniter-render-html`/ui-kit). ONE move that kills the only real dangle, removes
   the 91k-LOC Ruby liability, AND promotes the Rust stack into the **live IDE** — the
   console's replay/diff/lineage tooling becomes the IDE's preview engine. Highest
   leverage; everything else is additive. (Archive 3d-poc + gui-engine alongside.)
2. **Recursive container + integer layout pass** (Ceiling A). Add a `Stack`/`Row`/
   `Grid` container `Component` that nests children + a pure-integer layout pass
   computing `sx/sy/sw/sh` (replacing the hand-tuned constants). Turns "author a
   screen" from "write a Rust projector" into "compose nodes," composes cleanly with
   the deterministic digest (layout = pure integer math), and unblocks lists/tables/
   nesting. Then **generalize `.igv`** to all layouts + a data-bound `list`/`table`.
3. **Enrich the frame data model, then a real renderer** (Ceilings B+C). Carry
   pre-projection 3D position + topology/mesh + z-order + material on
   `ProjectedNode`/`Frame` BEFORE building a **`WgpuRenderHost`** (or canvas) — that
   one move forces the `RenderHost` generalization (draw calls, not `String`), the
   depth model, and a **`dt` tick driver** (deterministic fixed timestep) into the
   open at once, and turns the cube's edges from a renderer const into data. This is
   the credibility move for the "3D/gamedev is real" claim.
4. **Make the console an EDITOR, not just a debugger.** It already has hit-test
   chrome, `diff_frames`, and the ViewArtifact compiler. Add author-in-console (edit
   node → recompile → new frame → diff vs prior). "Igniter for UI" made tangible:
   author a screen as data, watch it replay and diff live.
5. **Cross the human gate** (a real executor over local TLS) to light up the full
   `.ig`-action → effect → receipt → console-lineage loop live. A human decision, not
   an engineering blocker.

### The differentiator to lean into: DETERMINISTIC UI ACROSS ARCHITECTURES

Fix the Ceiling-A/B/C ceilings AND route the tick through the lab's `det_*` trig +
the **qemu golden-bit gate** (latent in the VM tests, per the VM audit) → frames are
**bit-identical across x86_64 / aarch64 / riscv64**. No other UI/game framework can
claim deterministic, replayable, content-addressed, cross-arch UI. Combined with the
fact-sourced lineage, that is the unique product: *a UI/game runtime you can replay,
diff, time-travel, and reproduce bit-for-bit on any machine.* This ties frame-ui
directly into the emergence/determinism line and the embedded-swarm (riscv64/ESP32)
readiness — the same deterministic core renders on a phone, a Pi, and a microcontroller.

## Keystone recommendation

- **FRAME-UI-IDE-PREVIEW-REHOME-P2** — re-point the IDE preview onto the Rust
  projector; archive 3d-poc + gui-engine; refactor card before deleting view-engine.
  The single paused→developing lever.
- **FRAME-UI-LAYOUT-VOCAB-P2** — recursive container + integer layout pass + `.igv`
  generalization (Ceiling A). The authoring-DX keystone.
- **FRAME-UI-WGPU-HOST-P2** — enrich the frame data model → `WgpuRenderHost` + `dt`
  tick driver (Ceilings B+C). The gamedev-credibility keystone.
- **FRAME-UI-CONSOLE-AUTHOR-P2** — author-in-console (Ceiling E / DX).
- Quick reliability wins alongside: empty-`leads` guard (1 line), `esc()` `"`/`'` +
  attribute context (1 line), `safe_url` control-char fix, `det_*` trig in the tick.

The architecture is the strongest UI thesis in the series and it is proven, not
aspirational. The unpause is **retire the Ruby legacy, lift the flat-layout and
screen-points ceilings, give it one real renderer, and let the console author** —
turning "a deterministic time-travel UI runtime" into a compelling, pleasant-DX
"Igniter for UI / GUI / 3D / gamedev" story.

## Boundary / not covered

Lab evidence only; no code changed. Completes the foundation sweep (TBackend →
compiler → stdlib → VM → machine → web/server → frame-ui; sibling docs in
`lab-docs/`). The `igniter-ide` (Tauri app) itself and the Ruby view-engine internals
were characterized, not deep-audited — the IDE-preview re-home (move 1) needs its own
scoping card.
