# LAB-FRAME-VIEW-DYNAMIC-RUNTIME-BRIDGE-P4 — proof packet

Status: CLOSED — the DYNAMIC (`map`-built) specimen's real runtime output renders through the bridge;
no static fallback, no hand mirror.
Card: `.agents/work/cards/lang/LAB-FRAME-VIEW-DYNAMIC-RUNTIME-BRIDGE-P4.md`
Lane: igniter-lab / frame-ui / VM-UI payoff / dynamic runtime bridge
Date: 2026-06-27

## Result

P3 removed the hand mirror using the static `list_view_inline.ig`. The canon `map` parity fix
(`lab-vm-map-lambda-callcontract-parity`) then made the DYNAMIC specimen executable. This card consumes
that payoff: `list_view_dynamic.ig` — whose rows are built by
`map(lead_labels, l -> call_contract("Leaf", a_row, l))` — now runs on `igniter-vm` with
`status: success`, and its **real runtime Element tree renders through `render_ig_view`**.

```text
list_view_dynamic.ig --(igc compile)--> .igapp --(igniter-vm run)--> {"result": Element,"status":"success"}
   --(.result)--> render_ig_view --> WidgetRenderHost --> SVG   (tested + drives the live demo)
```

## Commands (exact, command-produced fixture)

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rm -rf /tmp/frame-list-dynamic.igapp
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig --out /tmp/frame-list-dynamic.igapp     # status: ok

cat > /tmp/frame-list-dynamic-input.json <<'JSON'
{ "lead_labels": ["Review Ada's lead", "Call Grace back", "Send Linus the quote"],
  "sel_title": "Review Ada's lead" }
JSON

cargo run --manifest-path lang/igniter-vm/Cargo.toml -- run \
  --contract /tmp/frame-list-dynamic.igapp --entry ListView \
  --inputs /tmp/frame-list-dynamic-input.json --json
# -> {"status":"success", … "result": <Element tree built by map> …}
```

The `map` runtime gap reported in P3 (`map expects exactly 2 arguments, got 1`) is GONE — the dynamic
specimen now returns `status: success`.

## Runtime fixture + extraction rule

- Fixture: `frame-ui/igniter-frame/tests/fixtures/list_view_dynamic.runtime.json` (the full envelope,
  captured verbatim from the run above — not hand-authored).
- Extraction rule: **`.result`** (the Element tree).

## Demo fixture — unchanged, now provable from the dynamic path

The dynamic runtime `.result` is **byte-identical** to (a) the P3 static-inline runtime `.result` and
(b) the live demo fixture `frame-ui/igniter-frame/web/list_view.element.json`. So `map`-built and
hand-unrolled construction CONVERGE on the same tree, and the demo fixture needs no change — it is now
backed by the dynamic specimen's output. (Test `demo_fixture_equals_dynamic_runtime_result` enforces
this; `dynamic_and_inline_runtime_trees_are_identical` proves the convergence.)

## Tests

`tests/ig_runtime_bridge_tests.rs` (run: `cargo test --test ig_runtime_bridge_tests`, 4/4):
- `dynamic_runtime_element_tree_renders_through_the_bridge` — headline: the dynamic `.result` renders;
  `.result.tag == "row"`; all labels survive (`Review Ada's lead`, `Call Grace back`,
  `Send Linus the quote`, `+ add item`, `mark done`); button rect present.
- `demo_fixture_equals_dynamic_runtime_result` — demo == dynamic `.result` (mirror stays removed).
- `dynamic_and_inline_runtime_trees_are_identical` — map ≡ manual (P3 stays green, superseded as the
  headline by the dynamic path).
- `static_inline_runtime_tree_still_renders` — P3 static proof remains green.

Full crate suite: **69 passed / 0 failed.** `git diff --check`: clean. No `Cargo.lock`, no VM/compiler/
canon/view-syntax changes.

## Remaining gap

None for the view bridge: the full `.ig`-authored → compile → dynamic runtime → frame-ui render loop is
proven with the `map`-based specimen and real runtime output. Out of scope / unchanged: ASK1
(cross-module refs), ASK2 (invocation-form sugar), optional/default fields (HELD), and the
passport-gated `igc run` path (igniter-vm is the lab runtime used here, not canon authority).
