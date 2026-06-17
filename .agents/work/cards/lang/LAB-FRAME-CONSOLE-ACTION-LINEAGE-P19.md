# LAB-FRAME-CONSOLE-ACTION-LINEAGE-P19

Status: CLOSED 2026-06-16 — implemented + proven (native + live browser)
Lane: frame / console / host-lineage
Owner: Opus

## Result

Proof doc: `lab-docs/lang/lab-frame-console-action-lineage-p19-v0.md`. Implemented in
`igniter-console/src/lib.rs` (machine-free): `HostActionRecord` (plain data — action_id/action_name/
contract/pool_id/invoke_digest/effect_receipt_id/effect_state/idempotency_key/correlation_id + from_json),
`FrameRecord.host_action: Option<…>`, `Console::attach_action`/`attach_action_json` (annotate the live
frame), `lineage_json` includes `host_action` for the selected frame, `render_svg` lineage panel adds
`action: <name> (<contract>)` + `receipt: <state> <short id>` (state-coloured, ids shortened; raw JSON
keeps full ids; panel grew 158→200, diff panel moved). `WasmConsole.attach_action(json)`. Time-travel
is per-frame (reads `log[selected]`); no-action frames unchanged; replay strip/viewer/diff/overlay intact.

**Verification:** `cd igniter-console && cargo test` → **21 passed, 0 failed** (7 console + 7
diff-highlight + 7 new action-lineage). `cargo build --release --target wasm32-unknown-unknown
--features wasm` → Finished (`attach_action` exported, no machine symbols). Boundary
`rg ... igniter-console igniter-ui-kit` → no real machine dependency (only comments/docs). All 8
acceptance. LIVE `console.html`: attached a `submit_lead`/`committed` record → lineage panel showed
`action: submit_lead (SubmitLeadRevi…)` + `receipt: committed IO.FrameFixture:…`. Next gate (NOT
started): `.igv` binding syntax / an end-to-end demo wiring the real P18 host bridge → `attach_action`.
Skill: idd-agent-protocol

Note: earlier docs may mention `LAB-FRAME-CONSOLE-ACTION-LINEAGE-P18`; P18 is now the effect
bridge. This card is the same next-route under the next free number: P19.

## Intent

Now that P17/P18 proved the host-side binding path:

```text
ViewArtifact action
  -> CoordinationHub::invoke
  -> capability-IO effect
  -> receipt in __receipts__
```

make the console/IDE-shell able to display that lineage next to frames:

```text
frame event -> host action -> capsule invoke -> effect receipt -> next frame
```

This is a console/lineage visualization slice. It must not make `igniter-console` depend on
`igniter-machine`.

## Verify-First Inputs

Read these before implementing:

- `igniter-console/src/lib.rs`
- `igniter-console/tests/console_tests.rs`
- `igniter-console/tests/console_diff_highlight_tests.rs` if present
- `igniter-ui-kit/src/binding.rs`
- `igniter-ui-kit/tests/binding_tests.rs`
- `igniter-machine/src/frame_binding.rs`
- `igniter-machine/src/frame_binding_effect.rs`
- `igniter-machine/tests/frame_binding_effect_tests.rs`
- `lab-docs/lang/lab-frame-ig-binding-machine-bridge-p17-v0.md`
- `lab-docs/lang/lab-frame-ig-binding-effect-bridge-p18-v0.md`
- `lab-docs/lang/lab-frame-console-diff-highlight-p15-v0.md` if present

Live code wins over this card.

## Required Boundary

`igniter-console` remains frame/UI-shell only:

- no `igniter-machine` dependency;
- no `CoordinationHub`, `CapabilityPassport`, `TBackend`, RocksDB, or executor imports;
- no real host invocation;
- no external network;
- no browser authority.

The console may display host lineage records as data. The host/machine produces those records
elsewhere; the console only renders and time-travels them.

## Suggested Shape

Add a small console-side lineage data model, for example:

```rust
pub struct HostActionRecord {
    pub action_id: String,
    pub action_name: String,
    pub contract: String,
    pub pool_id: Option<String>,
    pub invoke_digest: Option<String>,
    pub effect_receipt_id: Option<String>,
    pub effect_state: Option<String>,
    pub idempotency_key: Option<String>,
    pub correlation_id: Option<String>,
}
```

Use whatever shape fits the current console code best. The key is that it is plain data, not a
machine handle.

Attach the record to frame history in the console so the lineage panel can show:

- action name / contract;
- capsule invoke digest or result digest;
- effect receipt id and state;
- idempotency key / correlation id;
- redacted/short form where appropriate.

## Acceptance

1. A frame can carry a host action record with action name, contract, and receipt id/state.
2. `Console::lineage_json()` includes the action/effect lineage for the selected frame.
3. `Console::render_svg()` lineage panel displays a compact action/receipt line.
4. Time-travel/scrubbing shows the selected frame's own host action lineage, not always the latest.
5. Frames with no host action preserve the existing lineage display.
6. Redaction/shortening: long ids/digests are shortened in the SVG display; raw JSON may keep full
   ids if that is the existing console pattern.
7. Existing replay strip, frame viewer, textual diff, and visual diff overlay remain intact.
8. Boundary check proves `igniter-console` and `igniter-ui-kit` have no real machine dependency.

## Tests

Add or extend native console tests. Expected proof shape:

- host action record appears in `lineage_json`;
- SVG panel contains action name + receipt state/id short form;
- scrubbing between two frames changes the displayed action lineage;
- no-action frames remain unchanged;
- existing console/diff tests still pass.

## Verification

Run at minimum:

```bash
cd igniter-console && cargo test
cd igniter-console && cargo build --release --target wasm32-unknown-unknown --features wasm
rg -n "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB" igniter-console igniter-ui-kit
```

Expected boundary result: no real machine dependency. Comments/docs/test strings are acceptable if
they only describe the boundary.

## Deliverables

- implementation in `igniter-console` only;
- native tests;
- proof doc: `lab-docs/lang/lab-frame-console-action-lineage-p19-v0.md`;
- close this card with exact commands and pass counts;
- optional pointer from P18 proof doc.

## Closed Surface

Not in this card:

- no machine invocation from the console;
- no capability executor;
- no SparkCRM/HTTP/TLS/live network;
- no `.igv` syntax;
- no JetBrains plugin work;
- no product IDE shell beyond the existing console.

This card makes receipts visible in the frame console. It does not create new authority.
