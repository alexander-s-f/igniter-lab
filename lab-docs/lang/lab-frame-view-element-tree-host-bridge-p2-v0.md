# LAB-FRAME-VIEW-ELEMENT-TREE-HOST-BRIDGE-P2 — proof packet

Status: CLOSED — bridge proven; mirror-vs-runtime honestly stated; stale `map` comments cleaned.
Card: `.agents/work/cards/lang/LAB-FRAME-VIEW-ELEMENT-TREE-HOST-BRIDGE-P2.md`
Lane: igniter-lab / frame-ui / view-language-pressure / proof
Date: 2026-06-27

## Result

The smallest bridge from a **pure `.ig` authored `Element` tree** into the live frame-ui host path is
proven: an `Element { tag, attrs{dir,main,flex,pad,gap}, text, intent, children }` tree maps →
`LayoutBox` → `solve` → canonical widget nodes → the shared `WidgetRenderHost`, and renders nested
container + leaf/button structure with dynamic labels preserved — no new language feature, no `.igv`,
no parser sugar, no cross-module refs.

## 1. `.ig` specimens compile (re-verified, canonical command)

```bash
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/<file>.ig --out /tmp/frame-<file>.igapp
```

| specimen | status | stages |
|---|---|---|
| `elements.ig` | **ok** | parse/classify/typecheck/emit/assemble all ok |
| `list_view_inline.ig` | **ok** | all ok |
| `list_view_dynamic.ig` | **ok** | all ok (dynamic list via `map(... -> call_contract("Leaf", ...))`) |

## 2. Frame-ui host path used

`frame-ui/igniter-frame/src/ig_bridge.rs`:
- `element_to_layout(el, path, &mut info)` — recurse the Element JSON into a `LayoutBox`, assigning a
  stable path-id (`"0"`, `"0/1"`, …) per node and recording `(tag, text, intent, pad)`. Structure from
  `attrs`: `flex == 1 ⇒ Flex(main)`, else `Fixed(main)`; `dir` ⇒ Row/Col; `pad`/`gap` carried.
- `solve` (the P1 layout engine) → integer rects.
- `node_for(rect, info)` — map each Element to a canonical widget node (see §4).
- `WidgetRenderHost::render` (the P8 shared host) → SVG.
- wasm `render_ig_view(json, w, h)` + `web/ig.html` (+ `web/list_view.element.json`).

## 3. Real `.ig` runtime output, or mirrored JSON? — **MIRRORED JSON (stated honestly)**

The proof uses a JSON value that **mirrors the type-verified `Element` schema** that
`list_view_dynamic.ig` emits (its `output : Element`), NOT the output of an executed `.ig` run. Why:
`igc run` is the production VM surface — it requires a full `artifact_passport` (matching digests,
`semantics_profile`, capability) and a `delegated-experimental:ivm-proof` runtime. That is a heavy,
passport-gated path orthogonal to the rendering seam this card proves.

**Smallest honest next step to remove the mirror (Q3):** stand up `igc run` for one specimen with a
minimal valid passport (digest of the compiled `.igapp` + `core-pure-v0.1` profile) and an `--input`
JSON for `(lead_labels, sel_title)`, capture the emitted `Element` JSON, and feed THAT (byte-for-byte)
into `render_ig_view`. The bridge is engine-agnostic about how the JSON was produced, so only the
production step changes. That is a separate card (suggested below), not this one.

## 4. Adapter / mapping rules (`node_for`)

| Element `tag` | condition | canonical widget kind |
|---|---|---|
| `button` | — | `button` (`tone: add` if `intent=="add"`, else `go`); carries `intent` |
| `leaf` | has `intent` | `row` (label = text; clickable later) |
| `leaf` | no `intent` | `label` |
| `col` / `row` | `pad > 0` | `panel` (visible container) |
| `col` / `row` | `pad == 0` | `none` (purely structural — shapes layout, draws nothing) |
| anything else | — | **`note` tone=warn `?unknown tag: <tag>`** (fail closed, see §5) |

The adapter lives only in frame-ui proof space; no product semantics moved into compiler/canon.

## 5. Fail-closed behavior

- **Malformed Element JSON** → `render_ig_view` returns an SVG error card (`bad Element JSON: …`), no
  panic. Test: `malformed_json_is_total_no_panic`.
- **Unknown tag** → rendered as a VISIBLE warn marker (`?unknown tag: <tag>`), never silently dropped.
  Test: `unknown_tag_fails_closed_visibly`.
- Missing/zero attrs degrade to `0` (saturating layout), no panic.

## 6. Tests (focused frame-ui proof)

`cargo test -p igniter_frame` (run from `frame-ui/igniter-frame`): **65 passed / 0 failed.** Bridge
tests:
- `ig_element_tree_lays_out_like_the_handwritten_list` — the `.ig` tree lays out IDENTICALLY to the
  hand-written list: sidebar `Fixed(248)`, detail fills the rest, items at y `12/60/108/156`.
- `renders_ig_tree_to_svg_through_the_shared_host` — leads' text + buttons survive into the SVG;
  routed through canonical widgets (button rounded rect present).
- `unknown_tag_fails_closed_visibly`, `malformed_json_is_total_no_panic`, `deterministic_render`.

`git diff --check`: clean.

**Proven LIVE** (browser, `/ig.html`): the `.ig` Element tree renders through frame-ui (sidebar rows +
`＋ add item`, detail title + green `mark done`); editing the JSON reflows the view (added a 4th lead →
it flows in, add shifts down); no console errors. Machine-free + wasm32 clean (zero kernel symbols).

## 7. Stale-comment cleanup

Corrected the false "no `map`/fold" blocker (disproven by `list_view_dynamic.ig`) in:
- `specimens/dx-view-d/list_view_manual.ig` (module note + the `PAIN #3` line)
- `specimens/dx-view-d/list_view_inline.ig` (module note)
Preferred wording applied: the static/manual specimens intentionally avoid `map` for readability; the
dynamic sibling proves map-based body construction.

## 8. What remains for ASK1 / ASK2 (out of scope here)

- **ASK1 — cross-module contract refs** (`LANG-TYPED-CONTRACT-REF`): still the real blocker for a
  reusable `elements.ig` library (today the element contracts must be inlined into the view module).
  Not implemented here; pure-language pressure, no canon change in this card.
- **ASK2 — invocation-form body-as-children** (`LANG-FORM-VOCABULARY`): the `col { row { leaf } }`
  ergonomics over today's working manual threading. Not implemented here.
- **Optional/default fields**: HOLD (totality/determinism trap) — unchanged.

The bridge now provides end-to-end UI evidence, so ASK1/ASK2 can be pushed on the canon tracks with a
live demo behind them, not abstractly.

## Next card (suggested)

`LAB-FRAME-VIEW-IGC-RUN-ELEMENT-EXTRACTION-P3` — produce the `Element` JSON from a real `igc run` of
`list_view_dynamic.ig` (minimal passport + input) and feed it byte-for-byte into `render_ig_view`,
removing the mirror. Optionally then wire intents to an `.ig`-shaped reducer to make the bridged view
interactive (close the view+logic loop).
