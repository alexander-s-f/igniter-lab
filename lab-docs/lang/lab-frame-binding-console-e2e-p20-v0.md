# lab-frame-binding-console-e2e-p20-v0 — host bridge receipt → console-visible lineage

**Card:** `LAB-FRAME-BINDING-CONSOLE-E2E-P20` (host-side integration, in `igniter-machine` tests)
**Status:** CLOSED — implemented + proven. The first end-to-end demo glue: a declared action runs
the P17/P18 host bridge (real capsule invoke + fake capability-IO effect → receipt), the host
serializes the result to a plain `HostActionRecord` JSON, and the machine-free console renders that
action/receipt lineage. No live IO; fake executor only.

## The full lab loop (proven)

```text
ViewArtifact action ("record" → contract Add, effect IO.FrameFixture)
  → FrameBindingEffectBridge (P18): P17 gates + CoordinationHub::invoke (real Add capsule → 42)
                                    + run_write_effect_atomic (host effect passport) → receipt
  → FrameBindingEffectResult.to_host_action_json(...)   = a plain HostActionRecord JSON (host-side)
  → Console::attach_action_json(json)                   = the machine-free console stores it on a frame
  → Console::lineage_json / render_svg                  = "action: record" + "receipt: committed IO.FrameFixture:idem-1"
```

The console consumes DATA only — it never sees a passport, receipt object, `CoordinationHub`, or any
machine handle.

## Implementation

- **Host-side conversion** (`igniter-machine/src/frame_binding_effect.rs`): a tiny additive helper
  `FrameBindingEffectResult::to_host_action_json(action_id, action_name, contract, pool_id,
  idempotency_key, correlation_id) -> Value` projects the bridge result into the
  `HostActionRecord` shape the console (P19) already renders. It carries an id / state / digest
  (`effect_receipt_id` = the receipt key, `effect_state` = `WriteState::as_str()`, `invoke_digest` =
  a blake3 of the capsule result) — never a secret. This stays host-side.
- **No new console/ui-kit surface**: the console's P19 `attach_action_json` + lineage rendering are
  reused unchanged.

## Dependency direction (the boundary)

The integration test drives the whole stack from the top, so it lives in `igniter-machine/tests/`
with a DEV dependency on `igniter_console` + `igniter_ui_kit`. This is the kernel's *test* reaching
up to an app — not the app depending on the kernel:

- `igniter-console` / `igniter-ui-kit` still have **no** dependency on `igniter-machine` (they use
  `igniter_frame` with `default-features = false`, so the `machine` feature is OFF → no back-edge →
  no dependency cycle).
- The host glue that knows `FrameBindingEffectBridge` / passports / receipts stays in
  `igniter-machine`. The console only ever sees the serialized `HostActionRecord` JSON.

## Proof

**Native** (3 integration tests, `igniter-machine/tests/frame_binding_console_e2e_tests.rs`,
`--no-default-features`):

| acceptance | test |
|---|---|
| 1–5 — committed bridge receipt → HostActionRecord JSON → console lineage + render | `e2e_committed_action_renders_action_and_receipt_in_console` |
| 6 — idempotent replay through the bridge → console shows one receipt id (executor once) | `e2e_idempotent_replay_shows_one_receipt_id` |
| 7 — unknown/timeout → `effect_state = "unknown_external_state"`, console renders, no panic | `e2e_unknown_effect_state_renders_without_panic` |

## Verification (exact)

```text
cd igniter-machine && cargo test --no-default-features   → 279 passed, 0 failed
        (276 prior + 3 new frame_binding_console_e2e_tests)
cd igniter-console && cargo test                         → 21 passed (unchanged)
cd igniter-ui-kit  && cargo test                         → 42 passed (unchanged)
rg "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB"
   igniter-console igniter-ui-kit
        → no dependency (only a comment line in ui-kit/Cargo.toml describing the boundary)
```

Warnings: pre-existing dependency warnings (igniter-compiler / igniter-vm / igniter-tbackend); this
card adds none.

## Acceptance vs. card (all 8)

1 ✅ the P18 bridge produces a committed fake effect receipt · 2 ✅ the bridge output converts to a
plain `HostActionRecord` JSON · 3 ✅ `Console::attach_action_json` accepts + stores it on the frame ·
4 ✅ `Console::lineage_json` includes full action/receipt fields · 5 ✅ `Console::render_svg` shows a
compact action + receipt state/id · 6 ✅ same idempotency key replays → one receipt id (executor
once) · 7 ✅ unknown/timeout → `effect_state = "unknown_external_state"`, renders without panic · 8 ✅
`igniter-console` / `igniter-ui-kit` remain machine-free (boundary grep clean).

## Decisions

- **kernel test reaches up**: the e2e lives in `igniter-machine/tests` with a DEV dep on the apps —
  the only place that can legitimately see both the bridge and the console without inverting the
  app→kernel boundary (which stays: console/ui-kit never depend on the machine).
- **the handoff is a serialized record**, not a Rust object: `to_host_action_json` is the seam; the
  console takes JSON, so the same proof would hold across a process/IPC boundary (a real host).
- **fake executor only**: `Echo`/`FakeWriteExecutor`; no real network/SparkCRM (human-gated later).

## What this closes

The whole `.ig`-binding contour is now proven end to end, in lab, without live IO:

```text
.igv → ViewArtifact JSON → ui-kit/FrameRuntime → console (replay/diff/lineage)
     → host bridge: double-gate → CoordinationHub::invoke → capability-IO receipt
     → HostActionRecord JSON → console action/receipt lineage VISIBLE
```

…with the UI/browser path machine-free at every layer (boundary grep enforced).

## Next (gated — not started)

- a live browser demo (pre-compute a `HostActionRecord` from a real bridge run, serve it to
  `console.html`) — presentation only;
- richer `.igv` (multiple actions/regions) when a second real screen needs it;
- a real executor over local TLS / SparkCRM — behind the existing human-gated machine live gate.
