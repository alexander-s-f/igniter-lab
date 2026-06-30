# LAB-FRAME-VIEW-DYNAMIC-RUNTIME-BRIDGE-P4

Status: CLOSED (2026-06-27)
Route: standard / frame-ui / VM-UI payoff / dynamic runtime bridge
Skill: idd-agent-protocol

## Goal

Replace the remaining static-runtime bridge proof with the now-working dynamic
specimen:

```text
list_view_dynamic.ig
  -> Ruby igc compile
  -> igniter-vm run
  -> runtime Element JSON
  -> frame-ui render_ig_view
```

P3 removed the hand mirror using `list_view_inline.ig`. P1 then fixed the
`map(..., label -> call_contract(...))` runtime gap. This card should consume
that payoff: prove frame-ui can render the dynamic runtime-produced tree, with
no hand-written mirror and no fallback to the static sibling.

## Current Authority

Live source wins.

Read first:

- `lab-docs/lang/lab-frame-view-igc-run-element-extraction-p3-v0.md`
- `lab-docs/lang/lab-vm-map-lambda-callcontract-parity-p1-v0.md`
- `lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig`
- `frame-ui/igniter-frame/tests/ig_runtime_bridge_tests.rs`
- `frame-ui/igniter-frame/tests/fixtures/list_view_inline.runtime.json`
- `frame-ui/igniter-frame/web/list_view.element.json`

Known live facts:

- P3 static proof is closed: runtime output from `list_view_inline.ig` feeds the
  bridge and demo.
- P1 dynamic parity is closed: `list_view_dynamic.ig` compiles and `igniter-vm
  run --entry ListView` returns `status: success`.
- `frame-ui/igniter-frame/Cargo.lock` may be dirty from another agent. Do not
  stage or rewrite it unless this card truly changes dependencies.

## Scope

Allowed:

- Add a dynamic runtime fixture produced by the real runtime.
- Update or add focused frame-ui bridge tests that read the dynamic runtime
  envelope and render `.result`.
- Optionally update the demo fixture to dynamic runtime `.result` if it remains
  generated/proven and the test asserts equality.
- Write proof doc and closing report.

Closed:

- No VM/compiler fixes.
- No `.igv`, `.ig.html`, view syntax, invocation-form sugar, or cross-module
  references.
- No `igc run` passport work.
- No hand-written Element mirror.
- No unrelated frame-ui refactors.

## Required Steps

1. Re-run the dynamic compile:

   ```bash
   cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
   rm -rf /tmp/frame-list-dynamic.igapp
   ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
     /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
     lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig \
     --out /tmp/frame-list-dynamic.igapp
   ```

2. Run it:

   ```bash
   cat > /tmp/frame-list-dynamic-input.json <<'JSON'
   {
     "lead_labels": ["Review Ada's lead", "Call Grace back", "Send Linus the quote"],
     "sel_title": "Review Ada's lead"
   }
   JSON

   cargo run --manifest-path lang/igniter-vm/Cargo.toml -- run \
     --contract /tmp/frame-list-dynamic.igapp \
     --entry ListView \
     --inputs /tmp/frame-list-dynamic-input.json \
     --json
   ```

3. Capture the full runtime envelope as a checked-in fixture only if it is
   command-produced. The fixture name should make the source obvious, for
   example:

   ```text
   frame-ui/igniter-frame/tests/fixtures/list_view_dynamic.runtime.json
   ```

4. Add/adjust tests:

   - `status == success`
   - `.result.tag == "row"`
   - all dynamic labels survive render:
     `Review Ada's lead`, `Call Grace back`, `Send Linus the quote`,
     `+ add item`, `mark done`
   - demo fixture, if updated, equals runtime `.result`

## Acceptance

- [ ] Dynamic runtime fixture is produced by real commands, not hand-authored.
- [ ] Frame bridge renders dynamic runtime `.result`.
- [ ] Static P3 proof remains green or is intentionally superseded with a clear
      doc note.
- [ ] No VM/compiler/canon/view-syntax changes.
- [ ] `cargo test -p igniter_frame --test ig_runtime_bridge_tests` passes.
- [ ] `git diff --check` passes.

## Required Proof Packet

Create:

```text
lab-docs/lang/lab-frame-view-dynamic-runtime-bridge-p4-v0.md
```

Include exact compile/run commands, runtime fixture path, extraction rule,
bridge test names, whether demo fixture changed, and any remaining gap.

## Closing Report

- **Result:** GREEN. The DYNAMIC `map`-built specimen now runs on igniter-vm (`status: success` — the
  P3 `map` parity gap is fixed), and its real runtime `.result` renders through `render_ig_view`. No
  static fallback, no hand mirror. Packet: `lab-docs/lang/lab-frame-view-dynamic-runtime-bridge-p4-v0.md`.
- **Runtime path:** `cargo run --manifest-path lang/igniter-vm/Cargo.toml -- run --contract
  /tmp/frame-list-dynamic.igapp --entry ListView --inputs … --json` → success.
- **Files changed:**
  - `frame-ui/igniter-frame/tests/fixtures/list_view_dynamic.runtime.json` — NEW, command-produced
    runtime envelope of the dynamic specimen.
  - `frame-ui/igniter-frame/tests/ig_runtime_bridge_tests.rs` — headlined on the dynamic fixture; added
    `dynamic_runtime_element_tree_renders_through_the_bridge`, `demo_fixture_equals_dynamic_runtime_result`,
    `dynamic_and_inline_runtime_trees_are_identical`; kept `static_inline_runtime_tree_still_renders`.
  - `lab-docs/lang/lab-frame-view-dynamic-runtime-bridge-p4-v0.md` — NEW proof packet.
  - Demo fixture `web/list_view.element.json`: UNCHANGED — dynamic `.result` is byte-identical to it
    (and to the inline `.result`); no edit needed.
  - **No Cargo.lock, no VM/compiler/canon/view-syntax changes.**
- **Fixture path / extraction:** `tests/fixtures/list_view_dynamic.runtime.json`; rule `.result`.
- **Demo fixture changed?** No — already equals the dynamic `.result` (map ≡ manual convergence,
  asserted by `dynamic_and_inline_runtime_trees_are_identical`).
- **Tests:** `cargo test --test ig_runtime_bridge_tests` → 4/4; full crate suite 69/0; `git diff --check`
  clean.
- **Remaining gap:** none for the view bridge — the `.ig` → compile → DYNAMIC runtime → frame-ui render
  loop is closed end-to-end. ASK1/ASK2 unchanged (canon pressure); optional fields HELD; `igc run`
  passport path still out of scope (igniter-vm used, lab runtime, not canon authority).
- **Next card:** none required for the bridge. Candidate follow-ons: push ASK1/ASK2 on canon tracks
  (now with end-to-end UI evidence), or wire intents to an `.ig`-shaped reducer to make the bridged view
  interactive (view+logic loop).
