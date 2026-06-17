# lab-frame-ig-binding-effect-bridge-p18-v0 — ViewArtifact action → capability-IO receipt

**Card:** `LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18` (host-side, in `igniter-machine`)
**Status:** CLOSED — implemented + proven. A declared ViewArtifact action invokes a real capsule
(serving authority) and then performs its output as a declared capability-IO effect (HOST authority)
→ a receipt in `__receipts__`. Local + proof-scoped: fake executor only. No real HTTP/TLS/SparkCRM/
network; no browser authority.

## What it proves

P17 ran a declared action through `CoordinationHub::invoke` and returned the real capsule result.
P18 adds the effect line:

```text
declared ViewArtifact action
  → [P17 gates] declared + registered + recipe-match
  → CoordinationHub::invoke(SERVING passport, pool)   = real capsule activation (pure, no effect)
  → capsule output is DATA (the effect payload)
  → validate the action's declared `effect` intent
  → run_write_effect_atomic(HOST effect passport, …)  = the host PERFORMS the effect
  → receipt in __receipts__ + state/id back to the caller
```

This closes the loop the P15 thesis named: a UI action becomes a real capability-IO receipt, while
the browser/ui-kit stays machine-free.

## Implementation (`igniter-machine/src/frame_binding_effect.rs`)

`FrameBindingEffectBridge` (additive; composes existing surfaces, no new primitive):

- `handle_effect_action(artifact_json, action, invoke_payload, idempotency_key, serving_passport,
  pool_id, hub)`:
  1. runs `FrameBindingBridge::handle_action` (P17 gates 1–3 + `CoordinationHub::invoke` under the
     **serving** passport) → the real capsule result;
  2. validates the action's declared `effect` block (`parse_effect` → `EffectDecl{capability_id,
     operation, scope}`; missing/invalid → `MalformedEffect` BEFORE the executor);
  3. builds a `WriteRequest{capability_id, operation, idempotency_key, payload:{result}}` — the
     capsule output is DATA, the host performs the effect;
  4. `run_write_effect_atomic(single_flight, executors, receipts, clock, EFFECT passport, scope, …)`
     → a receipt; returns `FrameBindingEffectResult{invoke_result, receipt_state, receipt_key,
     result}` (`receipt_key = "<capability_id>:<idempotency_key>"` — an id, no secret).
- `FrameBindingEffectRefusal::{Binding(FrameBindingRefusal), MalformedEffect, EffectError}` — the
  serving-line refusal and the effect-line malformed/error are distinct.

**Double authority** is structural: the SERVING passport (vendor) authorizes the capsule activation;
a SEPARATE HOST effect passport authorizes the capability-IO effect. The vendor/browser authority is
never reused for the effect. The bound artifact declares the effect:

```json
"actions": { "record": { "contract": "Add", "input": {"a":"$form.a","b":"$form.b"},
  "effect": { "capability_id": "IO.FrameFixture", "operation": "record", "scope": "write" } } }
```

## Proof

**Native** (6 tests, `igniter-machine/tests/frame_binding_effect_tests.rs`, `--no-default-features`;
fixture mirrors `capability_io_bridge_tests.rs` + `frame_binding_tests.rs` — a real `Add` capsule in a
production pool, an `EchoCapabilityExecutor`/`FakeWriteExecutor`, a host effect passport):

| acceptance | test |
|---|---|
| 1, 2, 3 — invoke (Add→42) then effect → `Committed` receipt in `__receipts__`, result+state+key | `declared_action_invokes_capsule_then_performs_effect_with_receipt` |
| 7 — same idempotency key replays; executor runs once | `replay_same_idempotency_key_runs_effect_once` |
| 5 — malformed/absent effect intent refuses before executor, no receipt | `malformed_effect_refuses_before_executor_no_receipt` |
| 4 — the effect needs its OWN host authority (wrong scope → `Denied`, no receipt) | `the_effect_needs_its_own_host_authority` |
| 8 — unknown external fate maps to `UnknownExternalState`, no panic | `unknown_external_state_maps_to_receipt_state_without_panic` |
| 6 — P17 declaration gate still refuses before invoke | `p17_declaration_gate_still_refuses_before_invoke` |

## Verification (exact)

```text
cd igniter-machine && cargo test --no-default-features   → 276 passed, 0 failed
        (270 prior + 6 new frame_binding_effect_tests)
cd igniter-ui-kit  && cargo test                         → 34 passed (unchanged)
cd igniter-ui-kit  && cargo check --features wasm --target wasm32-unknown-unknown   → Finished
rg "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport" igniter-ui-kit
        → only comment/doc lines (no dependency)
```

Warnings: pre-existing dependency warnings (igniter-compiler / igniter-vm / igniter-tbackend);
`frame_binding_effect.rs` adds none.

## Acceptance vs. card (all 9)

1 ✅ declared/registered action invokes a real capsule + valid effect intent · 2 ✅ fake executor
commits, receipt in `__receipts__` · 3 ✅ result includes action result + receipt state + receipt key
· 4 ✅ double authority (serving ≠ host effect passport; wrong host authority → Denied) · 5 ✅
malformed intent refuses before executor, no receipt · 6 ✅ P17 declaration gate still refuses before
invoke · 7 ✅ idempotent — same key, executor runs once · 8 ✅ unknown maps to a receipt state, no
panic · 9 ✅ `igniter-ui-kit` has no machine dependency (only comments).

## Decisions

- **additive bridge**: `FrameBindingEffectBridge` composes `FrameBindingBridge` (P17) +
  `run_write_effect_atomic` (capability-IO) — no new primitive, no `bridge_effect.rs` refactor.
- **double authority is structural**: two passports (serving for invoke, host for the effect); the
  effect has its own scope gate, proven by a `Denied` on the wrong host authority.
- **capsule output is data; host performs the effect**: the action declares the effect; the capsule
  result becomes the payload; the host executes via capability-IO.
- **serving invoke vs. effect are distinct**: serving refusal (`Binding`) ≠ effect outcome/refusal;
  a malformed effect refuses before the executor (no receipt).
- **fake executor only**: `Echo`/`FakeWriteExecutor`; no real network/SparkCRM (a later, human-gated
  step).

## Next (gated — not started)

- **`LAB-FRAME-CONSOLE-ACTION-LINEAGE-P*`** — the console records host action/receipt lineage
  alongside frames (the IDE-shell shows the bind + receipt in its timeline).
- **`LAB-FRAME-IGV-BINDING-SYNTAX-P1`** — `.igv` text syntax over the now-code-proven JSON manifest +
  host bridges (invoke + effect).
- a real executor over local TLS / SparkCRM stays behind the existing human-gated machine live gate.
