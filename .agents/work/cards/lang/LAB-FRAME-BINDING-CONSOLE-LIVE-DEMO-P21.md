# LAB-FRAME-BINDING-CONSOLE-LIVE-DEMO-P21

Status: CLOSED 2026-06-16 — proven LIVE in a real browser (presentation over P20)
Lane: lab / frame-ui / demo-proof
Skill: idd-agent-protocol
Owner: Opus

## Result

Proof doc: `lab-docs/lang/lab-frame-binding-console-live-demo-p21-v0.md`. Smallest diff —
`igniter-console/web/` only (no Rust change): two deterministic fixtures (`host_action_committed.json`
committed + `host_action_unknown.json` unknown) matching the exact P20 `HostActionRecord` shape (no
passport/secret/handle) + two demo buttons in `console.html` that `fetch` a fixture and call the
existing `WasmConsole.attach_action` (P19). Live-verified (headless, 127.0.0.1:8735): clicking
**▶ attach committed** renders `action: submit_lead (SubmitLeadRevi…)` + `receipt: committed
IO.LeadReview:id…` in the lineage panel (id shortened in SVG; full ids in `lineage_json`); **▶ attach
unknown** renders `unknown_external_state` without panic; replay strip / viewer / diff / overlay all
intact. **Verification:** `igniter-console cargo test` → **21** (unchanged); `cargo build --release
--target wasm32-unknown-unknown --features wasm` → Finished; boundary `rg console ui-kit` → clean. All
8 acceptance met. Browser proof was live DOM/render verified; screenshot was **not persisted** as a
repo artifact. Next gates (NOT started): host-side demo glue from a real bridge run / richer `.igv` /
real SparkCRM executor (human-gated).

## Goal

Prove the already-implemented P20 bridge-to-console lineage in a real browser/demo surface:

```text
host-side bridge result
  -> HostActionRecord JSON
  -> console.attach_action(...)
  -> visible action/receipt lineage in the IDE shell
```

This is a presentation/browser proof over the proven P20 data shape. It is NOT a new machine primitive and NOT a live/SparkCRM integration.

## Verify-first anchors

Before changing anything, verify the live surfaces:

- `igniter-machine/src/frame_binding_effect.rs`
  - `FrameBindingEffectResult::to_host_action_json(...)`
- `igniter-machine/tests/frame_binding_console_e2e_tests.rs`
  - the canonical host-generated `HostActionRecord` shape
- `igniter-console/src/lib.rs`
  - `HostActionRecord`
  - `Console::attach_action_json`
  - `WasmConsole.attach_action`
- `igniter-console/web/console.html`
  - current browser demo shell
- `lab-docs/lang/lab-frame-binding-console-e2e-p20-v0.md`
  - P20 proof boundary

Live code wins over this card if details drift.

## Scope

Implement the smallest browser-visible proof that P20 lineage renders in the console:

1. Add a deterministic demo fixture or host-generated JSON payload representing one committed host action and, if cheap, one unknown action.
2. Wire the existing console browser demo so it can attach that record to a frame without requiring a running machine in the browser.
3. Show action name, contract, receipt state, and shortened receipt id in the lineage panel.
4. Keep the full idempotency key / correlation id / receipt id available in `lineage_json`.
5. Capture or document a live browser/screenshot proof if the local browser tooling is available.

Acceptable implementation shapes:

- static fixture JSON under `igniter-console/web/` or `igniter-console/tests/fixtures/`;
- a tiny demo-only JS button in `console.html` that calls `attach_action`;
- a host-side fixture generator only if it is simpler than maintaining static JSON.

Prefer the smallest diff.

## Hard boundaries

- Do NOT add `igniter-machine` as a dependency of `igniter-console` or `igniter-ui-kit`.
- Do NOT run SparkCRM, HTTP/TLS, external network, or live credentials.
- Do NOT move capability-IO execution into the browser.
- Do NOT invent a new action/receipt schema; use P20's `HostActionRecord` shape.
- Do NOT start product IDE shell work; this is still lab console proof.

## Acceptance

1. Browser demo can display a host action record in the lineage panel.
2. The displayed record includes action name, contract, receipt state, and receipt id prefix.
3. `lineage_json` contains the complete host-action fields.
4. The demo payload is deterministic and redacted: no passport, no secret, no machine handle.
5. Existing console replay/diff/action-lineage tests still pass.
6. `igniter-console` WASM build still passes.
7. Boundary grep confirms `igniter-console` and `igniter-ui-kit` remain machine-free except comments/docs.
8. Proof doc records exact commands and, if captured, screenshot path.

## Suggested verification

```bash
cd igniter-console
cargo test
cargo build --release --target wasm32-unknown-unknown --features wasm

cd ..
rg -n "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB" igniter-console igniter-ui-kit
```

If using a browser proof, run the existing local static-server workflow for `igniter-console/web/console.html` and record the screenshot path in the proof doc.

## Deliverables

- `lab-docs/lang/lab-frame-binding-console-live-demo-p21-v0.md`
- close this card with:
  - summary of demo surface
  - exact verification commands
  - boundary grep result
  - screenshot path or explicit "browser proof not run" note

## Next route

After P21, the natural next gates are:

- richer `.igv` authoring only if a second real screen needs it;
- host-side e2e demo glue that starts from a real P18 bridge run and opens the browser;
- real SparkCRM executor only behind the separate human-gated live packet.
