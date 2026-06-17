# lab-frame-ig-binding-machine-bridge-p17-v0 — ViewArtifact action → real CoordinationHub

**Card:** `LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17` (host-side, in `igniter-machine`)
**Status:** CLOSED — implemented + proven. A declared ViewArtifact action invokes a REAL capsule
through `CoordinationHub` serving (passport + production pool + signed recipe). Still in-lab, local;
NOT live IO, NOT SparkCRM, NOT a capability-IO effect/receipt.

## What it proves

P16 ran the bound action through a fixture executor. P17 swaps that for the real thing: the action
resolves to a registered contract and is executed by activating a real capsule through the proven
coordination serving path — closing the loop the P15 thesis described (the UI's fact-to-frame emits a
declared action; the host runs it through wire-to-effect / serving).

```text
declared ViewArtifact action  (actions.add → contract "Add")
  → host ContractRegistry double gate   (declared AND registered)
  → recipe entry-contract match          (action.contract == ServiceRecipe.entry_contract)
  → CoordinationHub::invoke(passport, production_pool, payload)   (REAL capsule resume + dispatch)
  → real result (Add{a:2,b:3} → 5) + coordination audit
```

The bridge lives in `igniter-machine` **on purpose**: `igniter-ui-kit` and the browser stay
machine-free. The UI emits a declared action *request*; this host bridge runs it.

## Implementation (`igniter-machine/src/frame_binding.rs`)

- `FrameBindingBridge::parse_action(artifact_json, name)` — parses ONLY `actions.<name>.contract`
  from a ViewArtifact JSON string (no UI render/compile, no ui-kit dependency).
- `FrameBindingBridge::handle_action(artifact_json, action_name, payload, passport, pool_id, hub,
  registry)` — the gates, in order:
  1. **declared** — `actions.<name>` present → else `MissingDeclaration`;
  2. **registered** — `registry.get(contract).is_some()` (the `ContractRegistry` is the declaration/
     metadata gate, NOT an executor) → else `NotRegistered`;
  3. **recipe match** — `action.contract == hub.read_recipe(pool).entry_contract` → else
     `RecipeMismatch` (or `NoRecipe`);
  gates 1–3 refuse **before** any invoke. Then `CoordinationHub::invoke` enforces passport /
  `ActivateCapsule` grant / production-pool / signed-recipe — surfaced as `FrameBindingRefusal::Pool`.
- `FrameBindingResult::{Ok(Value), Refused(FrameBindingRefusal)}`;
  `FrameBindingRefusal::{BadArtifact, MissingDeclaration, NotRegistered, NoRecipe, RecipeMismatch,
  Pool}`.

No new machine primitive: the bridge composes existing `ContractRegistry` (gate) +
`CoordinationHub::invoke` (executor). It runs the serving invoke only — no capability-IO write
effect, so no `__receipts__` fact.

## Proof

**Native** (6 tests, `igniter-machine/tests/frame_binding_tests.rs`, `--no-default-features`; fixture
mirrors `coordination_recipe_tests.rs` — a real `Add` capsule, signed `ServiceRecipe{entry_contract:
"Add"}`, vendor passport + `ActivateCapsule` grant):

| acceptance | test |
|---|---|
| 1, 6, 7 — declared+registered invokes the real capsule (→ 5), audits, NO receipt | `declared_registered_action_invokes_real_capsule_and_audits_without_a_receipt` |
| 2 — missing declaration refuses before invoke (audit unchanged) | `missing_declaration_refuses_before_invoke` |
| 3 — missing registry entry refuses before invoke | `missing_registry_entry_refuses_before_invoke` |
| 4 — action/recipe entry-contract mismatch refuses before invoke | `recipe_entry_contract_mismatch_refuses_before_invoke` |
| 5 — missing `ActivateCapsule` grant refused by the coordination gate | `missing_grant_is_refused_by_the_coordination_gate` |
| (robustness) — unparseable artifact refused | `bad_artifact_json_is_refused` |

"Before invoke" is proven by snapshotting the `__coord_audit__` fact count and asserting it is
UNCHANGED on the gate-1/2/3 refusals (a real invoke always writes an audit fact). "No receipt" is
proven by asserting zero facts in the `__receipts__` store after a successful invoke.

## Verification (exact)

```text
cd igniter-machine && cargo test --no-default-features    → 270 passed, 0 failed
cd igniter-ui-kit  && cargo test                          → 34 passed (P9 9 + P10 8 + P12 9 + P16 8, unchanged)
cd igniter-ui-kit  && cargo check --features wasm --target wasm32-unknown-unknown   → Finished (compiles)
rg "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport" igniter-ui-kit
        → only 3 COMMENT lines match (lib.rs doc, binding.rs doc, Cargo.toml comment); no dependency
```

Warnings: the machine suite emits pre-existing dependency warnings (igniter-compiler / igniter-vm /
igniter-tbackend unused-import + `right: _` match warnings) unrelated to this card; `frame_binding.rs`
adds none.

## Acceptance vs. card (all 9)

1 ✅ real invoke → 5 · 2 ✅ missing declaration refuses pre-invoke · 3 ✅ missing registry refuses
pre-invoke · 4 ✅ recipe mismatch refuses pre-invoke · 5 ✅ missing grant refused by coordination gate
· 6 ✅ audit written on success · 7 ✅ no `__receipts__` from the serving path · 8 ✅ `igniter-ui-kit`
has no machine dependency (only comments) · 9 ✅ P16 fixture tests stay green.

## Decisions

- **bridge is host-side**: in `igniter-machine`, composing existing surfaces; the UI/browser path is
  untouched and machine-free.
- **double gate + recipe match before invoke**; coordination gate (passport/grant/production) inside
  invoke. No arbitrary dispatch — declared-in-artifact AND registered-in-host AND recipe-bound.
- **`ContractRegistry` is the declaration gate, not an executor**; the executor is the proven
  coordination invoke.
- **serving invoke only**: no capability-IO effect/receipt this card (that is the effect-bridge gate).

## Next (gated — not started)

- **`LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18`** — DONE: `igniter-machine/src/frame_binding_effect.rs`
  performs the capsule output as a declared capability-IO effect → receipt in `__receipts__` (double
  authority, idempotent, fake executor). See `lab-frame-ig-binding-effect-bridge-p18-v0.md`.
- **`LAB-FRAME-CONSOLE-ACTION-LINEAGE-P18`** — the console records host action/receipt lineage
  alongside frames.
- **`LAB-FRAME-IGV-BINDING-SYNTAX-P1`** — `.igv` text syntax over the now-code-proven JSON manifest +
  host bridge.
