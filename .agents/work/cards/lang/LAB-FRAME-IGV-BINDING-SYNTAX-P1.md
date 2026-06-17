# LAB-FRAME-IGV-BINDING-SYNTAX-P1

Status: CLOSED 2026-06-16 — implemented + proven (machine-free)
Lane: frame / ui-kit / authoring syntax
Owner: Opus

## Result

Proof doc: `lab-docs/lang/lab-frame-igv-binding-syntax-p1-v0.md`. Implemented `igniter-ui-kit/src/igv.rs`
(machine-free, serde_json only): `lower_igv(src) -> Result<Value, IgvError>` — a line-oriented parser
that lowers a tiny `.igv` text (`view/source/field/action{input,validate,effect}/sidebar/inspector/
submit`) DETERMINISTICALLY to the proven ViewArtifact JSON. `IgvError{line,msg}` stable diagnostics
(`impl Display`). Canonical fixture `web/lead_review.igv` lowers to the same shape as the hand-written
`lead_review_bound.view.json` (proven byte-identical via equal workbench render digest). Sources →
P16 `{contract,mode:"read"}`; actions → `{contract,input,validate,effect:{capability_id,operation,
scope}}` (P17/P18 shape). Deterministic: sorted-key Map + ordered arrays.

**Verification:** `cd igniter-ui-kit && cargo test` → **42 passed, 0 failed** (8 new igv + 34 existing,
unchanged). `cargo check --features wasm --target wasm32-unknown-unknown` → Finished. Boundary
`rg ... igniter-ui-kit/src` → no machine references. All 8 acceptance: lowering returns JSON, minimal
fixture accepted by binding host + source runs through fixture, deterministic byte-stable, sources/
actions lower to P16/P17/P18 shapes, stable line-positioned errors, existing behavior unchanged (`.igv`
≡ hand-written artifact), ui-kit machine-free. Next gates (NOT started): richer `.igv` / `.igv`→console
live demo / real executor (human-gated).
Skill: idd-agent-protocol

## Intent

Implement the first **lab-only `.igv` syntax** over the already proven ViewArtifact JSON manifest.

The stack now has code proof for:

```text
ViewArtifact JSON
  -> ui-kit component tree / FrameRuntime
  -> console replay + diff + host action lineage
  -> host-side .ig binding bridges (P17/P18)
```

P1 should add a tiny text authoring layer:

```text
.igv text -> deterministic ViewArtifact JSON -> existing compiler/runtime/tests
```

This is sugar over the lab ViewArtifact artifact. It is **not** Igniter language canon and must not
change `.ig`.

## Verify-First Inputs

Read these before designing syntax:

- `igniter-ui-kit/src/view_artifact.rs`
- `igniter-ui-kit/tests/view_artifact_tests.rs`
- `igniter-ui-kit/src/binding.rs`
- `igniter-ui-kit/tests/binding_tests.rs`
- `igniter-console/src/lib.rs`
- `igniter-console/tests/console_action_lineage_tests.rs`
- `igniter-machine/src/frame_binding.rs`
- `igniter-machine/src/frame_binding_effect.rs`
- `lab-docs/lang/lab-frame-viewartifact-p12-v0.md`
- `lab-docs/lang/lab-frame-ig-binding-readiness-p15-v0.md`
- `lab-docs/lang/lab-frame-ig-binding-p16-v0.md`
- `lab-docs/lang/lab-frame-ig-binding-machine-bridge-p17-v0.md`
- `lab-docs/lang/lab-frame-ig-binding-effect-bridge-p18-v0.md`
- `lab-docs/lang/lab-frame-console-action-lineage-p19-v0.md`

Ground truth beats old design notes. If the JSON manifest shape differs from this card, follow live
code.

## Required Boundary

`.igv` is lab-only authoring syntax:

- no `igniter-lang` canon change;
- no `.ig` parser/compiler/typechecker changes;
- no machine dependency in `igniter-ui-kit`;
- no host authority, passport, receipt, or executor in the browser path;
- no arbitrary string dispatch beyond the existing declared `sources` / `actions` manifest.

The lowering target is the existing ViewArtifact JSON. Behavior belongs to existing JSON consumers.

## Minimal Syntax Scope

Support one useful slice only: a bound lead-review/workbench style screen with one source and one
action.

The exact syntax is up to live implementation, but it should map cleanly to the proven JSON fields:

```text
view LeadReview workbench {
  source leads contract ListLeads bind leads

  action submit_lead contract SubmitLeadReview {
    input lead_id = $selection.lead_id
    input notes = $form.notes
    effect IO.FrameFixture.record scope write
  }

  region list bind leads
  region inspector bind $selection
}
```

This is a sketch, not authority. Prefer the smallest grammar that can lower deterministically to
current ViewArtifact JSON.

## Acceptance

1. Parser/lowering exists in `igniter-ui-kit` (or a clearly named adjacent lab module) and returns
   ViewArtifact JSON / `serde_json::Value`.
2. A minimal `.igv` fixture lowers to a valid ViewArtifact accepted by existing
   `view_artifact` / `binding` code.
3. Lowering is deterministic: parse -> JSON -> parse/compile produces byte-stable output where the
   existing artifact tests expect stability.
4. `sources` lower to the P16 source manifest shape and still use the fixture host path.
5. `actions` lower to the P16/P17/P18 action manifest shape:
   - `contract`;
   - `input`;
   - optional `effect { capability_id, operation, scope }`.
6. Invalid `.igv` produces small, source-positioned diagnostics or at least stable error messages
   for v0.
7. Existing ViewArtifact JSON behavior is unchanged.
8. `igniter-ui-kit` remains machine-free.

## Suggested Tests

Add focused tests, for example:

- `parse_minimal_workbench_igv`;
- `igv_lowers_to_existing_viewartifact_json`;
- `igv_bound_source_runs_through_fixture_host`;
- `igv_action_manifest_matches_p18_bridge_expectations`;
- `invalid_igv_reports_stable_error`;
- boundary grep / no machine dependency if feasible in proof doc.

Prefer asserting structured JSON fields rather than brittle full pretty-printed text.

## Verification

Run at minimum:

```bash
cd igniter-ui-kit && cargo test
cd igniter-ui-kit && cargo check --features wasm --target wasm32-unknown-unknown
rg -n "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB" igniter-ui-kit
```

If `igniter-console` is touched:

```bash
cd igniter-console && cargo test
```

## Deliverables

- implementation module for `.igv` parsing/lowering;
- native tests;
- proof doc: `lab-docs/lang/lab-frame-igv-binding-syntax-p1-v0.md`;
- close this card with exact commands and pass counts;
- optional pointer from P19 proof doc.

## Closed Surface

Not in this card:

- no real machine invocation;
- no capability executor;
- no SparkCRM/HTTP/TLS/live network;
- no JetBrains plugin work;
- no broad UI redesign;
- no full DSL/grammar ambition;
- no claim that `.igv` is canonical Igniter language.

This card only makes the proven ViewArtifact manifest easier to author.
