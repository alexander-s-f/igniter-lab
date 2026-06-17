# LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18

Status: CLOSED 2026-06-16 — implemented + proven (host-side, capability-IO receipt)
Lane: frame / machine / capability-IO
Skill: idd-agent-protocol

## Result

Proof doc: `lab-docs/lang/lab-frame-ig-binding-effect-bridge-p18-v0.md`. Implemented host-side
`igniter-machine/src/frame_binding_effect.rs`: `FrameBindingEffectBridge::handle_effect_action(...)`
runs the P17 gated invoke (SERVING passport) → real capsule result, validates the action's declared
`effect` block (`MalformedEffect` before executor), then `run_write_effect_atomic` under a SEPARATE
HOST effect passport → receipt in `__receipts__`. Returns `FrameBindingEffectResult{invoke_result,
receipt_state, receipt_key="<cap>:<idem>", result}`. Double authority (serving≠effect) structural;
idempotent via single-flight; capsule output is DATA, host performs the effect. Additive — composes
`FrameBindingBridge` + `run_write_effect_atomic`, no new primitive, no `bridge_effect.rs` refactor.
`FrameBindingEffectRefusal::{Binding, MalformedEffect, EffectError}`.

**Verification:** `cd igniter-machine && cargo test --no-default-features` → **276 passed, 0 failed**
(270 + 6 new `frame_binding_effect_tests`). `cd igniter-ui-kit && cargo test` → **34** (unchanged).
`cargo check --features wasm --target wasm32-unknown-unknown` → Finished. Boundary `rg ... igniter-ui-kit`
→ only comments (no machine dependency). All 9 acceptance: happy invoke+effect→Committed receipt,
idempotent replay (executor once), malformed-effect refused pre-executor (no receipt), wrong host
authority → Denied (double authority), unknown→UnknownExternalState (no panic), P17 gate still
refuses pre-invoke, ui-kit machine-free. Next gates (NOT started): console action/receipt lineage,
`.igv` binding syntax, real executor (human-gated live).
Owner: Opus

## Intent

Close the next gate after `LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17`.

P17 proved:

```text
ViewArtifact declared action
  -> ContractRegistry double gate
  -> ServiceRecipe entry-contract match
  -> CoordinationHub::invoke
  -> real capsule activation result
```

P18 must prove the next host-side step:

```text
declared ViewArtifact action
  -> real CoordinationHub::invoke
  -> capsule output is a pure effect intent
  -> host executes that intent through capability-IO
  -> receipt fact is written
```

This is still local and proof-scoped. Use a fake/local capability executor. Do not use real HTTP,
SparkCRM, TLS, browser authority, or external network.

## Verify-First Inputs

Read these before designing the shape:

- `igniter-machine/src/frame_binding.rs`
- `igniter-machine/tests/frame_binding_tests.rs`
- `igniter-machine/src/bridge_effect.rs`
- `igniter-machine/tests/capability_io_bridge_tests.rs`
- `igniter-machine/src/write.rs`
- `igniter-machine/src/single_flight.rs`
- `igniter-machine/src/capability.rs`
- `igniter-machine/tests/service_bridge_replica_tests.rs`
- `igniter-lab/lab-docs/lang/lab-frame-ig-binding-machine-bridge-p17-v0.md`
- `igniter-lab/lab-docs/lang/lab-frame-ig-binding-p16-v0.md`

Ground truth beats this card. If API names differ, follow the live code and document the delta.

## Required Shape

Build the bridge in `igniter-machine`, not `igniter-ui-kit`.

The browser/ui-kit path remains machine-free:

- no `igniter-machine` dependency in `igniter-ui-kit`;
- no `CoordinationHub`, `CapabilityPassport`, secret, or receipt in the browser path;
- no arbitrary string dispatch.

The host bridge must keep the P15/P17 declaration gates:

1. action is declared in the `ViewArtifact`;
2. action contract is registered in `ContractRegistry`;
3. action contract matches the accepted `ServiceRecipe.entry_contract`;
4. only then may `CoordinationHub::invoke` run.

Then add the effect bridge:

5. invoked capsule output must be validated as a declared effect intent;
6. host-owned effect passport executes the effect through capability-IO;
7. receipt is written to `__receipts__`;
8. result exposes the receipt state/id without leaking secrets or authority into UI state.

## Acceptance

1. **Happy path:** declared/registered action invokes a real capsule and produces a valid effect
   intent.
2. **Receipt path:** fake/local executor commits and a receipt appears in `__receipts__`.
3. **Result shape:** returned value includes action result plus receipt state and receipt key/id.
4. **Double authority:** serving passport authorizes capsule activation; separate host effect
   passport authorizes capability-IO. Do not reuse browser/vendor authority for the effect.
5. **Malformed intent:** bad/missing effect intent refuses before executor; no receipt.
6. **Declaration gate:** missing action declaration / missing registry / recipe mismatch still refuse
   before invoke, as P17 proved.
7. **Idempotency:** same idempotency key replays; fake executor call count stays one.
8. **Unknown path:** fake timeout/unknown maps to receipt state and does not panic.
9. **Boundary:** `igniter-ui-kit` still has no real dependency on `igniter-machine`,
   `CoordinationHub`, or `CapabilityPassport` beyond comments/docs.

## Suggested Implementation Route

Prefer an additive host-side module or an additive extension around `FrameBindingBridge`.

Possible names:

- `FrameBindingEffectBridge`
- `FrameBindingEffectResult`
- `FrameBindingEffectRefusal`

Do not fold this into `igniter-ui-kit`. Do not make `ContractRegistry` execute anything; it remains
the declaration/registration gate.

Use the existing capability-IO substrate where possible:

- `CapabilityExecutorRegistry`
- `WriteRequest`
- `run_write_effect_atomic`
- `SingleFlight`
- `FakeWriteExecutor` / `EchoCapabilityExecutor`
- `RECEIPTS_STORE`

If `bridge_effect.rs` can be safely reused, reuse it. If its ingress/webhook shape is too specific,
factor only the smallest shared helper. Avoid broad refactors.

## Proof Fixture

Use a capsule fixture that returns an effect intent, for example:

```json
{
  "capability_id": "IO.FrameFixture",
  "operation": "record",
  "idempotency_key": "frame-action-1",
  "payload": { "value": 42, "correlation_id": "frame-corr-1" }
}
```

The exact shape may differ if live code has an established intent schema. The important point:
capsule output is data; host performs the effect.

## Verification

Run at minimum:

```bash
cd igniter-machine && cargo test --no-default-features
cd igniter-ui-kit && cargo test
cd igniter-ui-kit && cargo check --features wasm --target wasm32-unknown-unknown
rg -n "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport" igniter-ui-kit
```

Expected boundary result: only comments/docs may mention machine concepts from `igniter-ui-kit`.

## Deliverables

- implementation in `igniter-machine` only;
- native tests proving the acceptance list;
- proof doc: `lab-docs/lang/lab-frame-ig-binding-effect-bridge-p18-v0.md`;
- close this card with exact commands and pass counts;
- optionally add a one-line pointer from the P17 proof doc.

## Closed Surface

Not in this card:

- no real SparkCRM executor;
- no real HTTP/TLS/network;
- no browser/wasm authority;
- no `.igv` syntax;
- no compiler/language changes;
- no fanout of effects;
- no operator console lineage UI.

This card is the local host-side bridge from UI action to capability-IO receipt, nothing more.
