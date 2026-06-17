# lab-frame-ig-binding-p16-v0 — ViewArtifact bound to a fixture `.ig` host

**Card:** `LAB-FRAME-IG-BINDING-P16` (in `igniter-ui-kit`, over `igniter-frame`)
**Status:** CLOSED — proven (native + live browser). The smallest implementation of the P15 boundary:
a ViewArtifact declares one data source + one submit action; a FIXTURE host resolves them under the
double gate and returns data / scoped errors / a deterministic receipt. No real machine, no
`CoordinationHub`, no passport, no capability-IO, no external IO, no `.igv`.

## What it proves

The P15 readiness defined the bind as the join of the two contours. P16 implements its smallest
honest slice:

```text
bound ViewArtifact (sources + actions)
   │  data bind: sources.leads
   ▼
FixtureContractRegistry (ListLeads / ValidateLeadReview / SubmitLeadReview)   ← host-owned, deterministic
   │  DOUBLE GATE: declared in artifact  AND  registered in host
   ▼
BoundViewHost  →  WorkbenchRuntime (leads from the source; view-local selection/drafts)
   │  submit (only) crosses to the host  →  validate → scoped errors  OR  fixture receipt
   ▼
host-owned domain result (errors / receipt) surfaced to the view (overlay) — NOT a view-local fact
```

## Implementation (`igniter-ui-kit/src/binding.rs`, machine-free)

- **`FixtureContractRegistry`** — named handlers (`name -> fn(&Value) -> BindingResponse`) + per-
  contract call counters (so tests prove exactly what crossed the boundary). `lead_review()`
  registers `ListLeads` (deterministic leads), `ValidateLeadReview` (rejects empty priority / unset
  stage → field diagnostics), `SubmitLeadReview` (a content-addressed `fixture-receipt:<digest>`).
  Mirrors the machine's `ContractRegistry` shape but is fixture-only.
- **`BoundViewHost::from_artifact(json, registry)`** — parses the `sources`/`actions` manifest;
  resolves the sidebar's `bind: "leads"` under the **double gate** (declared in `sources` AND
  registered in the host) → `ListLeads` → builds a `WorkbenchRuntime` with the source leads + the
  artifact's fields (via `view_artifact::parse_fields`). Missing declaration → `MissingDeclaration`;
  unknown contract → `NotRegistered` — both BEFORE any contract runs.
- **interaction**: `click`/`key` forward to the workbench (view-local: selection, focus, drafts,
  cycle, toggle). The submit button (`act:submit`) is INTERCEPTED → `submit()`: gather the payload
  from the projected frame (`$selection.lead`, `$form.values`), run the declared `validate` contract
  (gated) → on rejection store scoped `err:<lead>` (host-owned) + no receipt; else run the declared
  submit contract (gated) → a fixture receipt; success clears prior scoped errors.
- **state ownership** (P15): selection/drafts are view-local (the workbench world); scoped errors +
  the last receipt are host-owned domain/effect results; the receipt is surfaced as a render overlay,
  not mixed into the view-local fact store. `BindingReceipt` is explicitly named a FIXTURE receipt,
  not a capability-IO receipt.

`view_artifact::parse_fields` was added (additive) so the host builds a workbench from a bound
artifact's `regions.main.fields`. No change to the unbound P12 path.

## Proof

**Native** (8 tests, `igniter-ui-kit/tests/binding_tests.rs`, machine-free; P9/P10/P12 stay green →
34 in the crate):

| acceptance | test |
|---|---|
| 1 — bound source loads leads from `ListLeads` (not inline), 1 call | `bound_source_loads_leads_from_fixture` |
| 2 — unbound `lead_review.view.json` still byte-identical | `unbound_artifact_still_byte_identical` |
| 3 — missing `sources.leads` declaration rejected | `missing_source_declaration_is_rejected` |
| 4 — unknown contract rejected by registry before any call | `unknown_contract_is_rejected_by_registry_before_any_call` |
| 5 — selection/typing stay local, call no contracts | `selection_and_typing_stay_local_and_call_no_contracts` |
| 6/8 — submit double-gate refusal when a contract is unregistered | `submit_action_double_gate_refuses_when_contract_unregistered` |
| 7 — validation failure → scoped errors, no receipt, submit not called | `validation_failure_writes_scoped_errors_and_no_receipt` |
| 8 — submit success → deterministic fixture receipt, errors cleared | `submit_success_produces_a_deterministic_fixture_receipt` |

Call counters prove the boundary: after load only `ListLeads` ran (1); selection/typing add zero
contract calls; a failed validation calls `ValidateLeadReview` but never `SubmitLeadReview`.

**WASM build**: `WasmBoundHost.from_artifact` in the `.wasm`; no `igniter-machine` / `TBackend` /
`rocksdb` / `CoordinationHub` / `CapabilityPassport` symbols.

**Live browser** (`igniter-ui-kit/web/bound.html`, headless-verified): the page fetches
`lead_review_bound.view.json` and `WasmBoundHost.from_artifact`s it. Verified via real DOM events:
leads load from the source (`ListLeads` calls = 1, validate = 0); submitting Ada empty → validation
blocks (`ValidateLeadReview` = 1, `SubmitLeadReview` = 0, no receipt); filling priority + cycling
stage then submitting → `SubmitLeadReview` = 1 and a receipt `fixture-receipt:…` (content-addressed —
a different draft yields a different id); selecting another lead stays local (no extra contract
calls). The browser holds no authority and never links the machine.

## Acceptance vs. card (all 10)

1 ✅ source-loaded leads · 2 ✅ unbound byte-identical · 3 ✅ missing declaration rejected · 4 ✅
unknown contract rejected pre-call · 5 ✅ local interaction calls nothing · 6 ✅ submit resolves only
via `actions.submit_lead` + registry · 7 ✅ validation → scoped errors, no receipt · 8 ✅ deterministic
fixture receipt + observable · 9 ✅ console unchanged (see below) · 10 ✅ no machine dep in the
UI/browser path.

**On acceptance 9 (console):** P16 leaves `igniter-console` unchanged. The console consumes a plain
`WorkbenchRuntime` (the view layer); the bind lives one level up in the host (`BoundViewHost`). Wiring
the console to observe host actions/receipts in its lineage is a deliberately separate step (it would
mean the console records host action records alongside frames) — out of this slice's scope. The live
`bound.html` already shows the action/receipt result, satisfying the "display the result" branch.

## Decisions

- **double gate** is the core invariant: declared-in-artifact AND registered-in-host; neither alone
  authorizes a call; both checked before execution. No arbitrary string dispatch.
- **fixture, explicitly**: the registry, receipts, and validation are deterministic fixtures; nothing
  here touches the real machine or claims a stable API. `BindingReceipt` is named a fixture receipt.
- **state ownership preserved**: view-local (selection/drafts) ≠ host-owned (errors/receipt); the
  receipt is a derived overlay, not a view-local fact.
- **browser authority-free**: the fixture host runs in-process and deterministically; it holds no
  secret/passport; real authority (passport, `CoordinationHub`) is a later gate.

## Next (gated)

- **`LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17`** — DONE: `igniter-machine/src/frame_binding.rs`
  replaces this fixture executor with the real `CoordinationHub::invoke` serving path (double gate +
  recipe match before invoke; real `Add` capsule → 5; no receipt; ui-kit stays machine-free). See
  `lab-frame-ig-binding-machine-bridge-p17-v0.md`. Next gate:
  `LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18` (action → declared capability-IO receipt, fake executor).
- **`LAB-FRAME-IGV-BINDING-SYNTAX-P1`** — `.igv` text syntax over the now-code-proven ViewArtifact
  manifest, after the JSON shape is settled.
- console action/receipt lineage — record host action records alongside frames so the IDE-shell shows
  the bind in its timeline.
