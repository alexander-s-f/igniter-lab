# lab-frame-console-action-lineage-p19-v0 — host action/receipt lineage in the console

**Card:** `LAB-FRAME-CONSOLE-ACTION-LINEAGE-P19` (in `igniter-console`)
**Status:** CLOSED — implemented + proven (native + live browser). The IDE-shell now displays the
host-side bound-action lineage (`frame → action → invoke → effect receipt`) next to each frame, as
plain data, time-traveled per frame. The console stays frame/UI-shell only — NO machine dependency.

## What it proves

P17/P18 proved the host-side binding path (`action → CoordinationHub::invoke → capability-IO effect →
receipt`). P19 makes that lineage VISIBLE in the console: the host produces action/receipt records
elsewhere (the machine), and the console renders + scrubs them as data — closing the developer-visible
loop `frame event → host action → capsule invoke → effect receipt → next frame`.

## Implementation (`igniter-console/src/lib.rs`, machine-free)

- `HostActionRecord` — plain data (NOT a machine handle): `action_id`, `action_name`, `contract`,
  `pool_id`, `invoke_digest`, `effect_receipt_id`, `effect_state`, `idempotency_key`,
  `correlation_id`. `from_json` parses it from a string (the host/JS feeds it in).
- `FrameRecord` gains `host_action: Option<HostActionRecord>` (default `None`).
- `Console::attach_action(record)` / `attach_action_json(json)` — attach to the latest (live) frame:
  the host calls this after running a bound action that produced that frame.
- `lineage_json()` includes a `host_action` object for the selected frame when present.
- `render_svg()` lineage panel adds two compact lines when the selected frame carried an action:
  `action: <name> (<contract>)` and `receipt: <state> <short id>` (state-coloured: committed green,
  denied red, unknown amber). Long ids/digests are shortened in the SVG; the raw JSON keeps full ids.
  The lineage panel grew (158→200px) and the diff panel moved down to fit.
- `WasmConsole.attach_action(json)` exposes it to the browser.

Time-travel is inherent: the panel + `lineage_json` read `self.log[selected]`, so scrubbing shows the
selected frame's OWN action lineage, not always the latest. Frames with no action render exactly as
before.

## Proof

**Native** (7 tests, `igniter-console/tests/console_action_lineage_tests.rs`; the existing 7
console + 7 diff-highlight tests stay green → 21 total):

| acceptance | test |
|---|---|
| 1, 2 — a frame carries a host action; `lineage_json` includes it | `frame_carries_host_action_in_lineage_json` |
| 3 — the SVG lineage panel shows a compact action/receipt line | `render_panel_shows_action_and_receipt_line` |
| 4 — scrubbing shows the selected frame's own action (not the latest) | `time_travel_shows_selected_frames_own_action` |
| 5 — no-action frames preserve the existing lineage display | `frames_without_action_preserve_existing_lineage` |
| 6 — long ids shortened in SVG, full in raw JSON | `long_ids_are_shortened_in_the_svg_but_full_in_json` |
| (data-in) — `from_json` attaches a record | `from_json_attaches_action` |
| 7 — replay strip / viewer / diff / overlay intact | `existing_console_surfaces_intact` |

**WASM build**: `cargo build --release --target wasm32-unknown-unknown --features wasm` → Finished;
`WasmConsole.attach_action` present; no `igniter-machine`/`rocksdb`/`CoordinationHub` symbols.

**Live browser** (`web/console.html`, headless-verified): after a real interaction (select Grace), a
host action record (`{action_name:"submit_lead", contract:"SubmitLeadReview", effect_state:"committed",
effect_receipt_id:"IO.FrameFixture:idem-7f3a91", …}`) was attached via `con.attach_action(json)`; the
lineage panel rendered `action: submit_lead (SubmitLeadRevi…)` + `receipt: committed IO.FrameFixture:…`
and `lineage_json` carried the full record — alongside the intact replay strip, embedded viewer,
visual diff overlay, and frame-diff panel.

## Verification (exact)

```text
cd igniter-console && cargo test                                                    → 21 passed, 0 failed
cd igniter-console && cargo build --release --target wasm32-unknown-unknown --features wasm   → Finished
rg "igniter-machine|igniter_machine|CoordinationHub|CapabilityPassport|TBackend|RocksDB" igniter-console igniter-ui-kit
        → no real dependency (only comments/docs/test strings)
```

## Acceptance vs. card (all 8)

1 ✅ frame carries action (name/contract/receipt) · 2 ✅ `lineage_json` includes it · 3 ✅ SVG panel
shows a compact line · 4 ✅ time-travel shows the selected frame's action · 5 ✅ no-action frames
unchanged · 6 ✅ ids shortened in SVG, full in JSON · 7 ✅ replay/viewer/diff/overlay intact · 8 ✅
no real machine dependency in console/ui-kit.

## Decisions

- **records are plain data**: the console renders + time-travels them; the machine produces them
  (P17/P18). `HostActionRecord` holds no machine handle, so the console boundary is preserved.
- **attach to the live frame**: a host action annotates the frame it produced; scrubbing shows each
  frame's own lineage.
- **redaction**: long ids/digests are shortened in the SVG (the existing `short` helper); the raw
  JSON keeps full ids (the existing console pattern) — receipts expose ids/state, not secrets.
- **additive**: no change to the replay strip / viewer / diff / overlay; the lineage panel grew.

## Next (gated)

- **`LAB-FRAME-IGV-BINDING-SYNTAX-P1`** — DONE: `igniter-ui-kit/src/igv.rs` lowers a tiny `.igv` text
  deterministically to the proven ViewArtifact JSON (machine-free). See
  `lab-frame-igv-binding-syntax-p1-v0.md`.
- an end-to-end demo wiring the real P18 host bridge → `attach_action` (host-side glue), behind the
  existing human-gated machine boundary.
