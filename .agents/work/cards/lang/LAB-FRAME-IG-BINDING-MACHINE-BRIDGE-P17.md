# Card: LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17 — host-side binding to real CoordinationHub

Status: CLOSED 2026-06-16 — implemented + proven (host-side, machine suite green)
Skill: idd-agent-protocol
Lane: lang / frame / machine bridge implementation

## Result

Proof doc: `lab-docs/lang/lab-frame-ig-binding-machine-bridge-p17-v0.md`. Implemented host-side
`igniter-machine/src/frame_binding.rs`: `FrameBindingBridge::handle_action(artifact_json, action,
payload, passport, pool, hub, registry)` runs the gates — (1) declared in `actions.<name>`, (2)
registered in `ContractRegistry`, (3) `action.contract == ServiceRecipe.entry_contract` — all BEFORE
`CoordinationHub::invoke`, which then enforces passport / `ActivateCapsule` grant / production. Real
`Add` capsule activation returns `5`; serving INVOKE only (no `__receipts__` capability-IO receipt);
the `ContractRegistry` is the declaration gate, not an executor; no new machine primitive.
`FrameBindingResult::{Ok,Refused}`, `FrameBindingRefusal::{BadArtifact,MissingDeclaration,
NotRegistered,NoRecipe,RecipeMismatch,Pool}`.

**Verification:** `cd igniter-machine && cargo test --no-default-features` → **270 passed, 0 failed**
(incl. 6 new `frame_binding_tests`, fixture mirrors `coordination_recipe_tests`). `cd igniter-ui-kit
&& cargo test` → **34** (P16 fixture tests unchanged). `cargo check --features wasm --target
wasm32-unknown-unknown` → Finished. Boundary `rg` → only 3 COMMENT lines in igniter-ui-kit match
(no dependency). All 9 acceptance met. "Before invoke" proven via unchanged `__coord_audit__` count
on gate refusals; "no receipt" via zero `__receipts__` facts. Next gates (NOT started):
`LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18` (action → declared capability-IO receipt, fake executor),
`LAB-FRAME-CONSOLE-ACTION-LINEAGE-P18`, `LAB-FRAME-IGV-BINDING-SYNTAX-P1`.
Owner: Opus

## Why this card exists

P15 designed the `.ig` binding boundary. P16 implemented the smallest fixture
proof in `igniter-ui-kit`:

```text
ViewArtifact sources/actions
  -> fixture host registry
  -> scoped validation / deterministic fixture receipt
```

P17 replaces the fixture action executor with a real host-side machine bridge:

```text
declared ViewArtifact action
  -> host ContractRegistry double gate
  -> CoordinationHub::invoke(passport, production_pool, payload)
  -> real capsule activation result + coordination audit
```

This is still local and in-lab. It is not live IO and not SparkCRM.

## Verify-first inputs

Read these live files first:

- `igniter-ui-kit/src/binding.rs`
- `igniter-ui-kit/web/lead_review_bound.view.json`
- `igniter-machine/src/registry.rs`
- `igniter-machine/src/coordination.rs` (`ServiceRecipe`, `accept_recipe`, `invoke`)
- `igniter-machine/tests/coordination_recipe_tests.rs`
- `igniter-machine/tests/service_bridge_replica_tests.rs`
- `lab-docs/lang/lab-frame-ig-binding-readiness-p15-v0.md`
- `lab-docs/lang/lab-frame-ig-binding-p16-v0.md`
- `.agents/work/cards/lang/LAB-FRAME-IG-BINDING-P16.md`

Live code wins over docs if they disagree.

## Goal

Implement a proof-local host bridge that can invoke one declared action through
the real `CoordinationHub` serving path.

The proof must show:

1. action is declared in the ViewArtifact manifest;
2. action contract is registered in host `ContractRegistry`;
3. passport/pool/recipe gates are enforced by `CoordinationHub::invoke`;
4. a real capsule is resumed and dispatched;
5. the browser/UI-kit core remains machine-free.

## Preferred implementation shape

Keep this host-side. Do **not** make `igniter-ui-kit` depend on
`igniter-machine`.

Preferred narrow location:

```text
igniter-machine/src/frame_binding.rs
```

or another clearly host-side module if live code suggests a cleaner boundary.

Suggested types:

```rust
FrameBindingBridge
FrameBindingAction
FrameBindingResult
FrameBindingRefusal
```

The bridge may parse only the minimal `actions` manifest from a ViewArtifact JSON
string. It does not need to render or compile the UI.

## Execution model

For v0, focus on one action path. Data sources may remain host snapshots or
fixture data; do not invent a full `.ig` query/source substrate in this card.

Action flow:

```text
handle_action(artifact_json, action_name, payload, passport, pool_id)
  -> parse actions.<action_name>
  -> ContractRegistry.get(action.contract) must exist
  -> read accepted ServiceRecipe for pool
  -> action.contract must match recipe.entry_contract
     (or document a stricter equivalent gate)
  -> CoordinationHub::invoke(passport, pool_id, payload)
  -> return result or refusal
```

The existing `ContractRegistry` is declaration/metadata authority, not an
executor. Do not turn it into arbitrary dynamic execution.

## Required proof fixture

Use an in-memory production pool with a real capsule, following
`coordination_recipe_tests.rs`:

- machine with `contract Add { input a: Integer input b: Integer compute sum = a + b output sum: Integer }`;
- checkpoint bytes as capsule;
- developer signs `ServiceRecipe { entry_contract: "Add", ... }`;
- vendor/runtime passport gets `ActivateCapsule`;
- bridge action payload `{ "a": 2, "b": 3 }` returns `5`.

Use a minimal ViewArtifact action manifest such as:

```json
{
  "artifact": "view",
  "version": 0,
  "layout": "workbench",
  "actions": {
    "add": { "contract": "Add", "input": { "a": "$form.a", "b": "$form.b" } }
  }
}
```

The exact surrounding UI shape may be minimal; the action manifest is what
matters.

## Acceptance

1. Declared + registered action invokes real `CoordinationHub::invoke` and
   returns the real capsule result (`5` for Add).
2. Missing action declaration refuses before `CoordinationHub::invoke`.
3. Missing `ContractRegistry` entry refuses before `CoordinationHub::invoke`.
4. Action contract mismatch vs accepted recipe entry contract refuses before
   invoke.
5. Bad/missing passport or missing `ActivateCapsule` grant is refused by the
   existing coordination gate.
6. Successful invoke writes the expected coordination audit fact.
7. Bridge tests prove no capability-IO receipt/external effect is produced by
   this card.
8. `igniter-ui-kit` still has no `igniter-machine` dependency.
9. P16 fixture tests remain green.

## Required tests

Add focused tests, likely under `igniter-machine/tests/`:

- success: declared+registered action -> Add result;
- missing declaration;
- missing registry entry;
- recipe/action mismatch;
- missing grant/passport refusal;
- audit written on success;
- no `__receipts__` facts from this serving-only path.

Add a small boundary check if useful:

```bash
rg -n "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport" igniter-ui-kit
```

Only comments should match.

## Verification

Required:

```bash
cd igniter-machine
cargo test --no-default-features
```

Required regression:

```bash
cd igniter-ui-kit
cargo test
cargo check --features wasm --target wasm32-unknown-unknown
```

Report exact pass counts and any existing warnings.

## Deliverables

- Host-side bridge implementation.
- Tests.
- Proof doc:
  `lab-docs/lang/lab-frame-ig-binding-machine-bridge-p17-v0.md`
- Close this card with verification output.
- Update the P16 proof doc or P14 checkpoint only with a small pointer if it
  prevents drift.

## Closed surfaces

Do not do these in P17:

- No `igniter-ui-kit -> igniter-machine` dependency.
- No machine in the browser/WASM core path.
- No external IO, SparkCRM, HTTP, TLS, RocksDB, or live endpoint.
- No capability-IO write effect or receipt. This card proves serving invoke,
  not effect execution.
- No `.igv`.
- No parser/compiler changes.
- No arbitrary string dispatch. Action must be manifest-declared and registry-
  registered.
- No production/live readiness claim.

## Next route after P17

If P17 closes cleanly, likely next cards:

- `LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18` — action result becomes a declared
  capability-IO intent/receipt, still local fake executor first.
- `LAB-FRAME-IGV-BINDING-SYNTAX-P1` — text syntax over the now-proven JSON
  manifest + host bridge.
- `LAB-FRAME-CONSOLE-ACTION-LINEAGE-P18` — console records host action/receipt
  lineage alongside frames.

Do not start those routes here.
