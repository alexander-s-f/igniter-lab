# LAB-FRAME-VIEW-IGC-RUN-ELEMENT-EXTRACTION-P3 — proof packet

Status: CLOSED — mirror REMOVED via real runtime extraction (igniter-vm fallback); one documented
runtime gap on the `map` path.
Card: `.agents/work/cards/lang/LAB-FRAME-VIEW-IGC-RUN-ELEMENT-EXTRACTION-P3.md`
Lane: igniter-lab / frame-ui / view-language-pressure / runtime extraction proof
Date: 2026-06-27

## Result

The last mirror from P2 is gone. A real runtime now PRODUCES the `Element` tree, and the **exact runtime
output** drives both the bridge test and the live demo fixture — no hand-written mirror remains.

```text
list_view_inline.ig --(igc compile)--> .igapp --(igniter-vm run)--> {…,"result": Element,…}
   --(.result)--> render_ig_view --> WidgetRenderHost --> SVG  (live + tested)
```

## 1. Compile (canonical command)

```bash
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/list_view_inline.ig --out /tmp/frame-list-inline.igapp
```
→ `status: ok`. The `.igapp` is a directory (`manifest.json`, `contracts/`, …). `list_view_dynamic.ig`
also compiles `ok` (but does not run — see §3).

## 2. Runtime path used — `igniter-vm run` (FALLBACK, stated explicitly)

`igc run` was attempted first (preferred) and is **BLOCKED** by passport constraints:
- input must be a named object (`input JSON must be an object`), then
- `passport passport_kind must be artifact_passport` — it requires a full `artifact_passport`
  (passport_kind/schema, a matching `artifact_digest`, `semantics_profile`, the
  `delegated-experimental:ivm-proof` runtime). Constructing a valid digest-matched passport + that
  experimental C-resident IVM is heavy and orthogonal to the extraction seam, so it was not pursued.
  **No `igc run` production-readiness is claimed.**

Fallback used (allowed by the card, documented here — lab VM, NOT canon/public runtime authority):

```bash
cd lang/igniter-vm
cargo run -- run --contract /tmp/frame-list-inline.igapp --entry ListView \
  --inputs /tmp/frame-list-inline-input.json --json
```
→ `{"status":"success", … "result": <Element tree> …}`.

## 3. Why the STATIC sibling, not the dynamic specimen — a real compiler↔VM parity gap

`list_view_dynamic.ig` (the `map`-based one) compiles `ok` but **fails to EXECUTE** on igniter-vm:

```text
{"error":"VM evaluation failed: map expects exactly 2 arguments, got 1","status":"error"}
```

So the canon compiler typechecks `map(coll, x -> call_contract("Leaf", …))`, but the lab VM rejects it
at runtime (a `map`-arity lowering/eval gap). Fixing the VM is out of this card's scope (no compiler/VM
feature work). Per the card's allowance ("`list_view_dynamic.ig` OR a minimal sibling"), the **static**
`list_view_inline.ig` is the runtime source of truth here; it produces the identical Element *shape*
without `map`. (One-line consistency edit: its `Leaf` now sets `intent: "select"`, matching the dynamic
specimen's `Leaf`, so the runtime output renders as rows.)

## 4. Input JSON

```json
{ "lead_labels": ["Review Ada's lead", "Call Grace back", "Send Linus the quote"],
  "sel_title": "Review Ada's lead" }
```
(`list_view_inline.ig::ListView` consumes only `sel_title`; the dynamic one would consume both.)

## 5. Output shape + extraction rule

Runtime envelope: `{ latency_us, observations, result, status }`. **Extraction rule = `.result`** (the
`Element` tree). Captured verbatim to the checked-in fixture
`frame-ui/igniter-frame/tests/fixtures/list_view_inline.runtime.json` (the full envelope, runtime-
produced, not hand-authored).

## 6. Comparison to the P2 mirror — mirror REMOVED

The P2 demo fixture `frame-ui/igniter-frame/web/list_view.element.json` was a hand-authored mirror. It
is now **overwritten with the extracted runtime `.result`**, so the live demo renders real runtime
output. Test `runtime_result_matches_the_demo_fixture` asserts `envelope.result == web fixture` — i.e.
the demo and the test both consume the same real runtime tree; no mirror remains anywhere.

## 7. Render proof through `render_ig_view`

Integration test `tests/ig_runtime_bridge_tests.rs` (`include_str!`s the runtime envelope fixture,
extracts `.result`, calls `render_ig_view`):
- `runtime_produced_element_tree_renders_through_the_bridge` — the runtime tree renders; all five
  authored labels (`Review Ada's lead`, `Call Grace back`, `Send Linus the quote`, `+ add item`,
  `mark done`) + a button rect survive runtime → bridge → SVG.
- `runtime_result_matches_the_demo_fixture` — demo fixture ≡ runtime `.result`.

**Live** (`/ig.html`): the demo renders the runtime fixture (5 labels, leads as rows via the `select`
intent, the add + mark-done buttons); no console errors.

## 8. Tests run

`cargo test` (from `frame-ui/igniter-frame`): **67 passed / 0 failed** (adds the 2 runtime-bridge
tests). `git diff --check`: clean. Cargo.lock not touched.

## 9. Blockers / next step

- **Resolved:** runtime extraction is real for the static specimen; the mirror is removed.
- **Open (documented):** the **`map` compiler↔VM parity gap** blocks runtime extraction from the
  `map`-based `list_view_dynamic.ig`. This is the precise missing runtime piece. Next card options:
  1. `LAB-VM-MAP-LAMBDA-CALLCONTRACT-PARITY-Pn` — route the `map expects 2 args, got 1` gap to the VM
     owners (compiler accepts it; VM must execute it) so the dynamic specimen runs end-to-end.
  2. `igc run` passport path — build a digest-matched `artifact_passport` to run via the gated IVM
     (heavier; only if production-runtime evidence is wanted).
- Out of scope and unchanged: ASK1 (cross-module refs), ASK2 (invocation-form sugar), optional/default
  fields (HELD).
