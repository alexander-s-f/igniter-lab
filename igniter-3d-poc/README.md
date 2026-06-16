# Igniter 3D POC — deterministic headless game core

`igniter-3d-poc` is a lab-only proof that the **Igniter model can express a 3D game loop**:
`(world, input, dt) -> world'` + a deterministic projection to a frame — the same
`(state, input) -> output + receipt` shape proven across the capability-IO and coordination
waves. Built in the Igniter discipline: pure transform, fail-closed, fact/receipt-shaped, no
GPU / window / network / VM.

## What it proves (G3D-P1, 10/10 green)

```bash
ruby run_poc.rb        # 10 passed, 0 failed → out/
```

- **4×4 matrix math** (model/view/perspective), perspective depth-divide (G3D-1).
- A **unit cube projects** to 8 screen vertices + 12 edges, on-canvas (G3D-2).
- **DETERMINISM**: two independent 30-tick runs yield byte-identical frame digests — the basis
  for lockstep netcode / replays / time-travel debugging (G3D-3).
- **REPLAY**: re-rendering a saved world snapshot reproduces a byte-identical frame (G3D-4).
- The cube **animates** (frame 0 ≠ frame 15) (G3D-5).
- **Fail-closed** camera params; **clip-safe** vertices behind the camera (G3D-6/7).
- **Receipt-shaped frames** (`frame_index` / `world_digest` / `screen_digest` /
  `source_receipt_id`), no absolute paths (G3D-8).
- Well-formed **SVG wireframe** (G3D-9); fully **headless** — no GPU/window/network/VM (G3D-10).

## The model (why this maps onto the machine)

| machine | this POC |
|---|---|
| capsule = immutable frame (content_digest) | `World` snapshot (`world_digest`) |
| pure dispatch `(state,input)->state'` | `World#step(dt)` — quantized, reproducible |
| receipt = bitemporal fact | receipt-shaped frame with `source_receipt_id` lineage |
| content-addressed replay | same seed + same ticks → byte-identical frames |

The angle quantization (`World::QUANTUM`, fixed-point grid) is what makes the evolution
reproducible bit-for-bit — the same lever a deterministic game engine needs for lockstep.

## Map

| Path | Purpose |
| --- | --- |
| `lib/engine3d.rb` | matrix math (`M`), `World`/`step`/`digest`, `Camera`/`project`, `Renderer` (SVG), `Frame` |
| `run_poc.rb` | G3D-P1 proof runner (10 checks) |
| `out/` | frame SVG/JSON artifacts + summary (gitignored) |

## Boundary

Lab-only POC. No stable schema / public API / release. No GPU / windowing / native renderer /
network / VM / contract dispatch. No performance/portability claim. Not Igniter Lang canon.

## The honest path to "full 3D game dev"

Proven here: the **deterministic state + projection core** (the hard, safety-critical part).
Remaining is integration + presentation, not invention:

1. **Renderer host** — start cheapest (SVG/canvas in browser; this POC already emits SVG), later
   a native `wgpu`/`skia` shell. The engine stays a pure projection; the host is a swappable edge.
2. **Real input loop** — wire a device to a hit-tester (the GUI engine already proves the logic).
3. **Machine as state kernel** — world state as machine facts/capsules; a tick as a dispatch;
   the GUI engine's `ExternalStateBridge` (`source_kind=tbackend/vm_trace`) is the existing seam.
4. **Physics / assets / richer meshes** — vec3 already here; add triangles, depth-sort, colliders.

**Why Igniter is a genuine differentiator for games:** determinism + bitemporal facts give
**lockstep netcode, exact replays, time-travel debugging, and anti-cheat for free** — the
expensive properties most engines bolt on, here as a property of the substrate.
