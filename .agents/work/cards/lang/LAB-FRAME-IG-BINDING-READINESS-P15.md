# Card: LAB-FRAME-IG-BINDING-READINESS-P15 — ViewArtifact bind/action to .ig boundary

> Readiness/design card for the first bridge between the `igniter-frame` /
> `igniter-ui-kit` authoring stack and real `.ig` contracts/effects. Builds on
> `LAB-FRAME-DX-AUTHORING-MODEL-P11`, `LAB-FRAME-VIEWARTIFACT-P12`, and
> `LAB-FRAME-CONSOLE-CHECKPOINT-P14`.

**Status:** CLOSED 2026-06-16 — readiness/design doc written, no code.
**Skill:** `idd-agent-protocol` (authority boundary, verify-first, smallest artifact).
**Lane:** readiness/design only. No parser/compiler/runtime implementation.

## Result

Doc: `lab-docs/lang/lab-frame-ig-binding-readiness-p15-v0.md`. Thesis: **the bind is the JOIN of the
two Igniter contours** — the UI's fact-to-frame emits a *declared* action; the **host** runs it
through the proven wire-to-effect path (`request → passport → contract → effect → receipt`) and the
result/receipt returns as a new view-state fact. Verified the real machine surfaces first
(`ContractRegistry{contracts: HashMap<String,Value>}` + `register`/`get`; `CoordinationHub::invoke(
passport, pool) -> Result<Value, PoolRefusal>` against a signed `ServiceRecipe{capsule_digest,
entry_contract,…}`; `run_write_effect`/`handle_effect` receipts) — these are host-side, NOT in the UI
path. Five declared binding classes (data/selection/validation/action/effect). Hard rule: callable
only if **declared in the artifact AND registered in the host** (double gate; no arbitrary string
dispatch). State ownership split: view-local (`__focus__`/`__selection__`/`fld:*` drafts/`err:<scope>`)
≠ domain (`.ig` data/contracts) ≠ effect receipts (machine) ≠ derived (projector). Browser/WASM is
authority-free (no passport/secret); effects go through capability-IO, never the UI reducer; no
machine in the browser path. Concrete `sources`/`actions` JSON sketch + lead-review end-to-end +
7 failure modes + redaction guardrails. Named next (NOT started): **`LAB-FRAME-IG-BINDING-P16`** —
one source + one action over a FIXTURE host `ContractRegistry` (deterministic, authority-explicit,
machine-free browser path); real `CoordinationHub`/passport execution + external effects stay later
gates.

## Why this card exists

P11 answered the authoring model:

```text
Rust kit API      = platform/widget authoring
ViewArtifact JSON = first portable app-authoring layer
.igv              = later sugar over ViewArtifact
.ig               = business logic / state / effects authority, NOT UI markup
```

P12 implemented the first portable artifact:

```text
ViewArtifact JSON -> igniter-ui-kit tree -> igniter-frame FrameRuntime
```

P12 deliberately left `bind` / `action` as a seam. Today the keys exist in
ViewArtifact JSON, but they resolve locally. This card must define what it means
to bind a view to real `.ig` data and effects **before** any implementation.

The core question:

```text
How does a ViewArtifact read data from .ig and send actions to .ig without
turning .ig into UI markup or letting UI code gain hidden authority?
```

## Verify-first inputs

Read these before writing:

- `igniter-frame/README.md`
- `igniter-ui-kit/README.md`
- `igniter-ui-kit/src/view_artifact.rs`
- `igniter-ui-kit/src/lib.rs`
- `igniter-ui-kit/src/composition.rs`
- `igniter-console/README.md`
- `lab-docs/lang/lab-frame-dx-authoring-model-p11-v0.md`
- `lab-docs/lang/lab-frame-viewartifact-p12-v0.md`
- `lab-docs/lang/lab-frame-app-authoring-checkpoint-p14-v0.md`
- `.agents/work/cards/lang/LAB-FRAME-VIEWARTIFACT-P12.md`
- `.agents/work/cards/lang/LAB-FRAME-CONSOLE-CHECKPOINT-P14.md`

Then verify current `.ig` execution surfaces from live code/docs before proposing
any call shape. Do not assume old docs are current.

## Authority boundary

Hold this line:

```text
ViewArtifact describes screen structure and bindings.
.ig owns business logic, validation, state queries, and effects.
The host/bridge owns authority, execution, receipts, and failure handling.
The browser host maps events only.
```

This bridge must not imply:

- `.ig` is UI markup;
- ViewArtifact can execute arbitrary contracts by string without a declared binding;
- UI state facts are the same as domain facts;
- browser/WASM has effect authority;
- `igniter-machine` becomes a UI dependency in the browser/core path;
- `.igv` exists or is authorized.

## Deliverable

Create one readiness/design doc:

```text
lab-docs/lang/lab-frame-ig-binding-readiness-p15-v0.md
```

Then close/update this card with a short result summary and next-route proposal.

Optional only if it prevents drift: add a one-line pointer from P14 checkpoint.
Do not edit canon language docs.

## Required sections in the doc

1. **Current state**
   - What P12 already implements.
   - Which ViewArtifact keys exist today (`bind`, `on_select`, `action`) and what
     they currently do locally.
   - What is not implemented.

2. **Binding taxonomy**
   Define at least these binding classes:
   - `data bind`: view reads a named collection/value from a `.ig` contract or host-provided snapshot.
   - `selection bind`: view-local selection chooses an item/key from data.
   - `validation bind`: form validation delegates to a `.ig` contract, if declared.
   - `action bind`: button/intent invokes a declared `.ig` contract/effect.
   - `effect bind`: action produces a host-executed effect with receipt, if the `.ig` contract declares it.

3. **State ownership model**
   Separate:
   - view-local state (`__focus__`, `__selection__`, field drafts, scoped errors);
   - domain state (`.ig` data/contracts/facts);
   - effect receipts / host audit;
   - derived inspector/frame state.

4. **Execution and authority model**
   - Who is allowed to call what.
   - How a ViewArtifact action resolves to a declared `.ig` contract.
   - What host authority/passport/capability must be present for effects.
   - Where failures are represented (view errors vs `.ig` diagnostics vs effect receipts).
   - Whether action execution is sync, async, or request/receipt style in v0.

5. **Artifact shape proposal**
   Provide a concrete ViewArtifact extension sketch for:
   - a data source;
   - a list bind;
   - a form field bind;
   - a submit action;
   - validation;
   - an effect-producing action.

   Example shape may vary, but must be explicit and data-oriented:

   ```json
   {
     "sources": {
       "leads": { "contract": "ListLeads", "mode": "read" }
     },
     "actions": {
       "submit_lead": {
         "contract": "SubmitLeadReview",
         "input": { "lead": "$selection.lead", "fields": "$form.values" },
         "effect": "optional-or-declared"
       }
     }
   }
   ```

6. **Minimal example**
   Use the existing lead-review workbench:
   - sidebar binds to `ListLeads`;
   - selection remains view-local;
   - main form drafts remain view-local;
   - submit invokes `SubmitLeadReview`;
   - inspector derives from selected data + drafts;
   - errors are scoped and replayable.

7. **Diagnostics and failure modes**
   Define expected failures:
   - missing source binding;
   - unknown contract/action;
   - type mismatch between view payload and `.ig` input;
   - validation failure;
   - effect denied;
   - effect unknown/retryable;
   - stale binding after ViewArtifact/schema change.

8. **Security / authority guardrails**
   - No arbitrary string dynamic dispatch from untrusted ViewArtifact.
   - All callable contracts/actions must be declared in the artifact and resolved by the host.
   - Browser/WASM cannot hold secrets or passports.
   - Effects go through host/capability IO path, not the UI reducer directly.
   - Redaction rules for any data shown in console/lineage.

9. **What not to implement yet**
   - No `.igv`.
   - No parser/compiler changes.
   - No live SparkCRM or external IO.
   - No new stable public API claim.
   - No machine dependency in UI-kit browser/core path.

10. **Next implementation route**
    Name the smallest P16 implementation card:
    - probably `LAB-FRAME-IG-BINDING-P16`;
    - proof-local host adapter;
    - fake `.ig` contract registry or fixture compile;
    - one read source + one submit action;
    - no external effects unless fake/receipt-local.

## Acceptance

- Answers how ViewArtifact `bind` / `action` should map to `.ig` without
  making `.ig` UI markup.
- Separates view-local state from domain state and effect receipts.
- Defines a concrete JSON extension sketch.
- Names who owns authority and failure handling.
- Rejects arbitrary dynamic string dispatch as a binding model.
- Keeps browser/WASM authority-free.
- Provides the lead-review example end-to-end at design level.
- Names one narrow implementation card and does not start it.
- No source code changes required.
- No canon edits.

## Closed surfaces

- Do not implement the bridge.
- Do not add `.igv`.
- Do not edit `igniter-lang` canon.
- Do not call live services.
- Do not add `igniter-machine` dependency to `igniter-ui-kit` core/browser path.
- Do not widen dynamic dispatch policy.

## Suggested next route if closed

```text
LAB-FRAME-IG-BINDING-P16
```

Recommended P16 shape:

```text
ViewArtifact with one source + one action
-> proof-local host binding registry
-> fake or fixture .ig contract execution
-> view state update / scoped errors / receipt-like action record
```

Keep P16 local, deterministic, and authority-explicit. External effects and `.igv`
remain later gates.
