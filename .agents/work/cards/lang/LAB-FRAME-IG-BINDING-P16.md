# Card: LAB-FRAME-IG-BINDING-P16 — one source + one action over a fixture host binding

Status: CLOSED 2026-06-16 — implemented + proven (native + live browser)
Lane: lang / frame / binding implementation
Owner: Opus

## Result

Proof doc: `lab-docs/lang/lab-frame-ig-binding-p16-v0.md`. Implemented `igniter-ui-kit/src/binding.rs`
(machine-free): `FixtureContractRegistry` (named handlers + per-contract call counters;
`lead_review()` = `ListLeads`/`ValidateLeadReview`/`SubmitLeadReview`), `BoundViewHost::from_artifact`
(parses `sources`/`actions`, resolves the sidebar `bind` under the **double gate** — declared in
artifact AND registered in host — then builds a `WorkbenchRuntime` with source leads + artifact
fields via the new additive `view_artifact::parse_fields`), submit interception (`act:submit` →
`submit()`: gather `$selection.lead`/`$form.values` from the frame → declared `validate` → scoped
`err:<lead>` or fixture `SubmitLeadReview` → content-addressed `fixture-receipt:<digest>`). State
ownership preserved: view-local selection/drafts ≠ host-owned errors/receipt (overlay, not a
view-local fact). `BindingError::{Parse,MissingDeclaration,NotRegistered,Schema}`; `BindingReceipt`
explicitly a FIXTURE receipt. Bound artifact `web/lead_review_bound.view.json`; `WasmBoundHost` +
`web/bound.html`.

**Verification:** `cd igniter-ui-kit && cargo test` → 34 tests (8 new binding + 9 view_artifact + 9
forms + 8 composition; P9/P10/P12 unchanged). `cd igniter-frame && cargo test` → 22 (untouched). WASM
clean of machine/CoordinationHub/passport symbols. Live `bound.html` headless-verified: leads from
`ListLeads` (1 call), empty submit → validation blocks (`SubmitLeadReview` 0), filled submit →
`fixture-receipt:…` (content-addressed), selection stays local. All 10 acceptance met (console left
unchanged per the explained branch). Next gate: `LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17` (real
CoordinationHub/passport, host-side, no external IO) — NOT started.

## Why this card exists

`LAB-FRAME-IG-BINDING-READINESS-P15` defined the boundary:

```text
ViewArtifact fact-to-frame contour
  emits declared source/action requests
HOST resolves them against declared/registered contracts
  then returns data/result/receipt as view-state facts
```

P16 is the smallest implementation proof of that boundary. It must prove one
data source and one submit action without using the real machine, real
`CoordinationHub`, live effects, `.igv`, or external IO.

## Verify-first inputs

Read these live files before editing:

- `igniter-ui-kit/src/view_artifact.rs`
- `igniter-ui-kit/src/composition.rs`
- `igniter-ui-kit/web/lead_review.view.json`
- `igniter-ui-kit/tests/view_artifact_tests.rs`
- `igniter-console/src/lib.rs`
- `igniter-console/tests/console_tests.rs`
- `igniter-machine/src/registry.rs`
- `lab-docs/lang/lab-frame-ig-binding-readiness-p15-v0.md`
- `.agents/work/cards/lang/LAB-FRAME-IG-BINDING-READINESS-P15.md`

Live code wins over readiness text if they disagree.

## Goal

Implement a proof-local ViewArtifact binding adapter that supports:

1. one declared read source (`sources.leads`);
2. one declared submit action (`actions.submit_lead`);
3. one validation failure path mapped to scoped view errors;
4. one deterministic receipt-like success result applied back into frame state;
5. no browser/machine authority.

This is a binding proof, not a production bridge.

## Required shape

Add a small host-side binding layer, preferably inside `igniter-ui-kit` unless
live code shows a cleaner crate boundary.

Suggested names are flexible, but the model should be explicit:

```rust
FixtureContractRegistry
BoundViewHost
BindingRequest
BindingResponse
BindingReceipt
```

The host adapter may be fixture-only and deterministic:

- `ListLeads` returns a deterministic lead list, replacing inline
  `data.leads`.
- `ValidateLeadReview` rejects one known invalid state and returns scoped field
  diagnostics.
- `SubmitLeadReview` returns a deterministic receipt-like record, for example
  `receipt:submit_lead:<n>` or a stable digest.

Use this only to prove the ViewArtifact binding semantics. Do not claim this is
the final public API.

## Artifact extension for the proof

Add a bound fixture artifact adjacent to the existing browser fixtures, for
example:

```text
igniter-ui-kit/web/lead_review_bound.view.json
```

It should use a minimal form of the P15 sketch:

```json
{
  "artifact": "view",
  "version": 0,
  "layout": "workbench",
  "sources": {
    "leads": { "contract": "ListLeads", "mode": "read" }
  },
  "actions": {
    "submit_lead": {
      "contract": "SubmitLeadReview",
      "input": { "lead": "$selection.lead", "fields": "$form.values" },
      "validate": "ValidateLeadReview",
      "effect": "fixture_receipt"
    }
  },
  "regions": {
    "sidebar": { "component": "List", "bind": "leads", "on_select": "select" },
    "main": {
      "component": "Form",
      "for_each": "selected",
      "fields": [ "... same field shape as existing lead_review.view.json ..." ],
      "submit": { "label": "Submit", "action": "submit_lead" }
    },
    "inspector": { "component": "KeyValuePanel", "bind": "selected" }
  }
}
```

The exact JSON may vary, but the source/action manifest must be data-oriented
and explicitly declared.

## Double-gate rule

A source/action may run only if both are true:

1. it is declared in the ViewArtifact `sources`/`actions` manifest;
2. the fixture host registry has the named contract registered.

Missing declaration or missing registry entry must fail before any fixture
contract is executed.

This rule is the core of P16. Test it directly.

## State ownership requirements

Preserve the P15 split:

- selection and drafts remain view-local facts;
- `sources.leads` populates the workbench data;
- validation diagnostics become scoped view errors such as `err:<lead>`;
- submit success becomes a view-state fact carrying receipt id/status;
- fixture receipts are NOT capability-IO receipts and must be named as such.

The browser/UI path remains authority-free. The fixture host owns resolution.

## Acceptance

1. A bound artifact with `sources.leads` loads leads from fixture `ListLeads`,
   not inline `data.leads`.
2. Existing unbound `lead_review.view.json` still compiles and behaves
   byte-identically to current tests.
3. Missing `sources.leads` declaration is rejected clearly.
4. `sources.leads.contract = "Unknown"` is rejected by registry lookup before
   any fixture call.
5. Clicking/selecting remains local and does not call fixture contracts.
6. Submit action resolves only through `actions.submit_lead` + fixture registry.
7. Validation failure writes scoped view errors and produces no success receipt.
8. Submit success writes a deterministic receipt-like view fact and updates the
   projected frame/inspector/lineage enough for tests to observe it.
9. Console integration can display the action/receipt result, or a proof-local
   test explains why the console layer remains unchanged in P16.
10. No dependency from `igniter-ui-kit` browser/core path to `igniter-machine`.

## Required tests

Add focused tests, likely in `igniter-ui-kit/tests/` plus optional
`igniter-console/tests/` if console lineage changes.

At minimum cover:

- bound source success;
- missing manifest declaration;
- missing fixture registry contract;
- local selection does not call host;
- validation failure path;
- submit success path with deterministic receipt-like id;
- unbound P12 behavior still passes.

Prefer call counters in the fixture host so tests can prove what did and did not
cross the host boundary.

## Verification

Required:

```bash
cd igniter-ui-kit
cargo test
```

Required if console files are touched:

```bash
cd igniter-console
cargo test
```

Recommended if shared frame traits are touched:

```bash
cd igniter-frame
cargo test
```

Do not run or require `igniter-machine` tests unless this card unexpectedly
touches machine files. If machine files become necessary, stop and route the
change to a later bridge card.

## Deliverables

- Bound fixture adapter code.
- Bound fixture artifact JSON.
- Focused tests.
- Proof doc:
  `lab-docs/lang/lab-frame-ig-binding-p16-v0.md`
- Update/close this card with implementation summary and verification output.
- Update the nearest frame/UI surface doc only if this repo already tracks P16
  implemented surface there. Do not create a new authority document just for
  this slice.

## Closed surfaces

Do not do these in P16:

- No `.igv`.
- No `.ig` parser/compiler changes.
- No real `CoordinationHub`.
- No real `CapabilityPassport`.
- No real capability-IO receipt.
- No external IO, SparkCRM, HTTP, TLS, or RocksDB.
- No browser-held secrets, passports, or contract authority.
- No arbitrary string dispatch from ViewArtifact to host.
- No new stable public API claim.
- No UI restyle or console redesign.

## Next route after P16

If P16 closes cleanly, the likely next cards are:

- `LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17` — host-side adapter to real
  `CoordinationHub`/passport, still local and no external IO.
- `LAB-FRAME-IGV-BINDING-SYNTAX-P1` — text syntax over the proven ViewArtifact
  manifest, only after P16 proves the JSON shape in code.

Do not start either route in this card.
