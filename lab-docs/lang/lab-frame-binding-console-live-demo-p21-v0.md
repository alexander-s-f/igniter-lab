# lab-frame-binding-console-live-demo-p21-v0 — host action/receipt lineage in a live browser

**Card:** `LAB-FRAME-BINDING-CONSOLE-LIVE-DEMO-P21` (browser/demo proof over P20)
**Status:** CLOSED — proven LIVE in a real browser. The P20 bridge-to-console handoff
(`HostActionRecord` JSON → console lineage) now renders in the actual IDE-shell page. Presentation
only — no new machine primitive, no live IO, console stays machine-free.

## What it proves

P20 proved (host-side, in Rust) that a real P18 bridge result serializes to a `HostActionRecord` JSON
that the console renders. P21 shows that same shape rendering in the browser:

```text
host-side bridge result  →  HostActionRecord JSON (static fixture, the exact P20 shape)
  →  WasmConsole.attach_action(json)  →  the IDE-shell lineage panel shows action + receipt
```

The fixture is the literal output shape of `FrameBindingEffectResult::to_host_action_json` — but fed
as static data, so the browser needs no machine.

## Implementation (smallest diff — `igniter-console/web/` only, no src change)

- Two deterministic fixtures matching the P20 `HostActionRecord` shape (no passport, no secret, no
  machine handle): `web/host_action_committed.json` (`effect_state: "committed"`) and
  `web/host_action_unknown.json` (`effect_state: "unknown_external_state"`).
- `web/console.html` gains two demo buttons that `fetch` a fixture and call the EXISTING
  `WasmConsole.attach_action` (shipped in P19), then select the live frame and re-render. A status
  line echoes `action (contract) → state receipt_id`.
- No change to `igniter-console` Rust source; the wasm already exported `attach_action`.

## Proof (live, headless browser)

Served `igniter-console/web/console.html` at `127.0.0.1:8735`. Verified via real DOM events:

- driving a viewer interaction records a frame, then clicking **▶ attach committed** attaches the
  fixture → the lineage panel shows **`action: submit_lead (SubmitLeadRevi…)`** and
  **`receipt: committed IO.LeadReview:id…`** (purple), the receipt id SHORTENED in the SVG;
- `lineage_json().host_action` carries the COMPLETE record:
  `{action_id, action_name:"submit_lead", contract:"SubmitLeadReview", pool_id:"leads-svc",
  invoke_digest:"blake3:1a2b3c4d5e6f7a8b", effect_receipt_id:"IO.LeadReview:idem-7f3a91",
  effect_state:"committed", idempotency_key:"idem-7f3a91", correlation_id:"corr-lead-42"}` — the full
  ids stay in the JSON while the SVG shows only the shortened prefix (redaction);
- the **▶ attach unknown** button renders `effect_state: "unknown_external_state"` without panic;
- the existing replay strip, frame viewer, textual diff, and visual diff overlay remain intact
  (the live DOM/render check selected Grace and observed the diff overlay + diff panel together with
  the new action/receipt lines).

Screenshot: **not persisted as a repo artifact**. The browser proof was a live headless DOM/render
check; repeat by serving `igniter-console/web/console.html`, clicking the demo buttons, and checking
the lineage panel/status line.

## Verification (exact)

```text
cd igniter-console && cargo test                                                  → 21 passed, 0 failed (unchanged)
cd igniter-console && cargo build --release --target wasm32-unknown-unknown --features wasm   → Finished
rg "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB"
   igniter-console igniter-ui-kit
        → no dependency (clean)
```

## Acceptance vs. card (all 8)

1 ✅ the browser demo displays a host action record in the lineage panel · 2 ✅ shows action name +
contract + receipt state + receipt id prefix (shortened) · 3 ✅ `lineage_json` contains the complete
host-action fields · 4 ✅ the payload is deterministic + redacted (no passport, secret, or machine
handle) · 5 ✅ existing console replay/diff/action-lineage tests pass (21) · 6 ✅ console WASM build
passes · 7 ✅ boundary grep: console/ui-kit machine-free · 8 ✅ proof doc records commands + the live
browser evidence.

## Decisions

- **smallest diff**: static JSON fixtures + two demo buttons reuse the P19 `attach_action` export; no
  Rust change.
- **the fixture IS the P20 shape**: the browser feeds the exact `HostActionRecord` JSON the host
  bridge emits — proving the same data renders, without a machine in the browser.
- **redaction holds in the UI**: the SVG shows a shortened receipt id; the full ids live only in
  `lineage_json` (the existing console pattern).

## Next (gated — not started)

- a host-side e2e demo that starts from a REAL P18 bridge run, writes the `HostActionRecord` JSON, and
  opens the browser (presentation glue; still no live external IO);
- richer `.igv` (multiple actions/regions) if a second real screen needs it;
- a real SparkCRM executor only behind the separate human-gated live packet.
