# LAB-FRAME-DX-VIEW-LANGUAGE-DESIGN-P1 — reconciling igniter-purity with view-expressiveness

Status: DESIGN RESEARCH (working backwards, "as if it already exists"). No code yet — a design space
to choose from.
Lane: igniter-lab / frame-ui / DX / language-pressure
Date: 2026-06-27
Method: wishful authoring — write the source we WISH we could write for a real app, then read off what
each style demands of the language/compiler. Test every candidate against one rule: **clear, concise,
maintainable — NOT "yank some Rust under the hood that hands back a string."**

## The two axes (the thing we kept avoiding)

- **Axis A — igniter (`.ig`).** Ideal at PURITY: typed records/variants, contracts as pure
  `input → compute → output`, determinism, no mutation, effects injected. Weak at EXPRESSIVENESS:
  building a nested, repeated, conditional STRUCTURE by hand is painful (no record spread, required
  fields only, no string escapes, manual collection unroll, no terse nested literal). `.ig` is a great
  *function* language and a poor *tree-literal* language.
- **Axis B — view.** Inherently a NESTED, DATA-BOUND, INTERACTIVE TREE. Wants: nesting, repeat,
  conditional display, value binding, event→intent, read at a glance. This is a *structure* problem.

They are different universes. The mistake is to force one axis to do the other's job: make `.ig`
express the whole tree (verbose, pollutes the pure language), or make a view DSL compute values
(re-grows an impure mini-language and loses determinism).

## Working backwards from a real app: "Lead Workbench"

Grounded in the existing lead domain (`apps/igniter-apps/lead_router/types.ig`, `lead_review.igv`).
State: a list of leads `{name, stage, hot}` + a selection. Intents: `select(id)`, `add()`,
`toggle_hot()`, `set_stage(s)`. Below, the SAME app authored three ways "as if it already exists."

### Candidate A — view authored IN `.ig` (fix igniter's expressiveness)

Add tree-literal + comprehension + event sugar to `.ig` itself:

```ig
view LeadWorkbench(s: Workbench) -> Screen {
  col pad 16 gap 12 {
    row flex 1 gap 12 {
      col fixed 248 pad 12 gap 8 {
        for lead in s.leads {
          row item key lead.id selected (lead.id == s.sel) on click select(lead.id) {
            label lead.name
          }
        }
        button add tone:add on click add() { "＋ add lead" }
      }
      col flex 1 pad 18 gap 14 {
        title s.selected.name
        segment of ["new","qualified","won"] value s.selected.stage on pick set_stage(it)
        toggle on s.selected.hot on click toggle_hot()
      }
    }
  }
}
```

What it COSTS the language: block/brace tree syntax, `for … in`, `on <event> <intent>`, `bind`/value
holes, `selected (expr)`, string interpolation. That is essentially **a whole view-DSL grafted onto
the pure language** — every one of these is view-only and pollutes `.ig`. Axis A purity *erodes* to buy
Axis B expressiveness. (Verdict: wrong direction — makes the pure language carry view concerns.)

### Candidate B — a dedicated `.igv` template; the HOLES are `.ig` expressions

The structure is a declarative template (good at nesting); the *values, conditions, repetition keys,
and intent args* are pure `.ig` expressions in `{…}` / `(…)` holes:

```igv
screen LeadWorkbench(s: Workbench) {
  col pad=16 gap=12 {
    row flex=1 gap=12 {
      col fixed=248 pad=12 gap=8 {
        each lead in s.leads {
          row.item key={lead.id} selected={lead.id == s.sel} -> select(lead.id) {
            label "{lead.name}"
          }
        }
        button.add -> add() { "＋ add lead" }
      }
      col flex=1 pad=18 gap=14 {
        title "{s.selected.name}"
        segment value={s.selected.stage} options={["new","qualified","won"]} -> set_stage($value)
        toggle on={s.selected.hot} -> toggle_hot()
        note.dim "{s.done_count} of {s.total} done"
      }
    }
  }
}
```

The template is NOT igniter — it is a view dialect tuned for nesting. But every `{…}` hole is a pure
`.ig` expression (so values stay deterministic, typed, replayable), and `-> intent(args)` names an
`.ig` reducer action. **The structure-plane is the template; the value-plane is `.ig`.** This is the
split the two axes were asking for.

### Candidate C — `.igv` is pure SUGAR that lowers to an `.ig` contract

Identical surface to B, but with a semantic commitment: the `.igv` compiles (desugars) to a pure `.ig`
contract `LeadWorkbench(s: Workbench) -> Frame` — the projector — so there is exactly ONE semantic
universe (igniter), with a friendly tree-skin on top. `each` lowers to a managed map/fold over
`s.leads`; `{hole}` lowers to a compute; `-> select(id)` lowers to an `intent` value on the node;
nesting lowers to nested descriptor records. No new runtime, no Ruby, no opaque Rust — the view IS an
`.ig` value, produced by a real lowering (the way World-A's `compile` already turns JSON → a typed
`Screen`, but general and terse).

## The reconciliation: the "right planes"

```
            STRUCTURE plane                         VALUE / DECISION plane
        (nesting, repeat, layout)                 (what each datum/condition is)
        ──────────────────────────                ──────────────────────────────
 author:  declarative .igv template     ×           pure .ig expressions in holes
 good at:  Axis-B expressiveness                      Axis-A purity & types
 lowers to:         one IR  →  a pure projector contract  (state → descriptor/Frame)
 binds to:          .ig reducer  (intent, state) -> deltas      [already an .ig idiom]
```

- Don't make `.ig` express the tree (it's weak there) → the **template** owns structure.
- Don't make the view DSL compute values (it would re-grow an impure language) → **`.ig` holes** own
  values/decisions, staying pure/typed/deterministic.
- They meet at ONE IR: the typed descriptor (our `Frame` / ViewArtifact), produced by a pure function
  of state. That descriptor is the *plane of contact* between the universes.
- The logic half needs no new universe: the reducer is already the `.ig` `(state, event) -> state`
  contract (`event_sourcing.ig:12-53`).

This passes the "no opaque Rust string" test: the surface is a real, typed, lowered language — the
holes are `.ig`, the output is a descriptor value, determinism/replay are preserved end to end.

## Recommendation

**Candidate B's surface + Candidate C's semantics:** a declarative `.igv` (nesting + `each` +
`{.ig holes}` + `-> intent`) that LOWERS to a pure projector contract over the frame-ui descriptor IR;
the logic half stays `.ig` `(intent, state) -> deltas`. Structure-plane = template; value-plane = `.ig`;
contact-plane = the typed descriptor. This adds NO view concerns to the pure `.ig` core (unlike A) and
NO new runtime/impurity (unlike World-B Ruby), and it generalizes World-A's compile from "2 layouts"
to "the layout-DSL + canon widget vocab we already built."

## What stays open (validate by building the smallest "as if exists")

1. **Hole language scope.** How much `.ig` is allowed in a `{hole}` — field access + comparisons +
   small expressions only, or full contract calls? (Lean minimal first: paths, comparisons, literals,
   `?:`, interpolation.)
2. **`each` semantics.** Managed map over a collection (keys, ordering) — lower to the same managed
   iteration `.ig` already wants (fold/`recur`), so it pressures the SAME canon gap (`AP-P03` fold).
3. **Intent binding to `.ig`.** `-> set_stage($value)` must name a real reducer action; do we generate
   the intent enum from the `.igv`, or declare it in `.ig` and check against it? (Prefer: `.ig` owns the
   action set; `.igv` is checked against it — fail closed on an unknown intent, like the empty-leads card.)
4. **Where lowering lives.** A new `.igv` front-end in `igniter-frame`/ui-kit that emits a projector,
   reusing `layout::parse` (P4) for structure and the canon widget vocab (P8) for leaves.
5. **The proof slice.** Re-author ONE existing screen (list) as ~20 lines of this `.igv`, compile to a
   projector, run it live byte-comparable to the hand-written one — proving ~300 LOC Rust → ~20 LOC view
   WITHOUT losing determinism. That single proof tells us if the plane-split holds.

## Candidate D — elements ARE contracts; `div { … }` is invocation-form sugar (stay 100% in igniter)

Alex's counter-idea, and after a verify-first pass on the spec/proposals it is the strongest framing —
**there is no separate `.igv` dialect at all.** A view is igniter: an `elements.ig` (analogous to
`types.ig`) of element CONTRACTS, nested to a tree, with a sugar "invocation form" so you write
`div { … }` / `col { row { … } }` and stay in the language.

Verify-first result (canon `igniter-lang` + gov), each piece marked real / proposed / absent:

| piece | status | evidence |
|---|---|---|
| `module html.elements { … }` | **IMPLEMENTED** (parser live) | PROP-015 accepted; `docs/spec/ch2-source-surface.md:30-34` |
| invocation-form sugar `div { … }` → contract call | **PROPOSED, real** (deferred) | `LANG-FORM-VOCABULARY` literally lowers `div { … }` → `call_contract("ViewDiv", …)`; P3=declare-only, **P4 invocation deferred** |
| `contract_shape` / `implements` | **PROPOSED** (pending) | PROP-016 — BUT shapes declare **PORTS, not data**: a `Div` and `Span` each REDECLARE attrs; **no attribute inheritance** |
| `composes` / `>>` composition | **PROPOSED** (pending) | PROP-016 / PROP-002 — sequential/explicit wiring, **NOT a parent-with-children tree** |
| elements/components as contracts | **ABSENT from canon** | only pressure-specimen sketches; no PROP |

So the idea is **real in its bones** — and crucially, *canon already wants the `div { … }` sugar*
(LANG-FORM-VOCABULARY targets exactly it). But two LOAD-BEARING pieces are gaps:

1. **Nested-tree composition.** Contracts compose sequentially (`>>`) or by explicit wiring — there is
   NO "a contract invocation contains child invocations as a tree" primitive. To nest today you thread
   `children: Collection[ViewElement]` by hand — i.e. you hit **exactly Axis-A's named weakness** (bad
   at nested literals). The fix that makes D fly: let an invocation-form's `{ … }` BODY carry nested
   child-forms as the `children` arg. That brace-body-as-children is the missing nesting primitive (an
   extension of LANG-FORM-VOCABULARY P4). It is not yet proposed.
2. **Attribute reuse.** `shape` is ports, not data, so it does not give attribute inheritance. Reuse a
   shared `Attrs` record threaded into every element instead (workable, not "inheritance").

### The convergence (why this reframes B/C, not competes with it)

Look at Candidate B's surface again: `col { row.item key={…} -> select(…) { label "{…}" } }`. If `col` /
`row` / `label` are **element-contracts** and `{ … }` is **invocation-form-with-children**, then B's
"template" simply IS igniter invocation-forms — the `{hole}` is an ordinary igniter expression, `each`
is a managed fold, `-> intent` is an intent value. **B/C and D are the same surface; D is the
principled framing of it: it's igniter sugar, not a side-dialect that lowers.** The verify-first shows
canon is already walking toward that sugar.

### Revised recommendation

**Adopt Candidate D as the DIRECTION** (one universe: view = igniter element-contracts + invocation-form
sugar), because it (a) keeps the pure language as the single semantic universe, (b) rides canon's OWN
`div { … }` proposal instead of a parallel engine, and (c) turns our work into *language pressure that
advances the core* — the precedent Alex flagged we can set. The price is two real, bounded language
gaps (brace-body-as-children nesting; attribute reuse) that we must push as proposals — versus B/C,
which dodges them with a side-dialect (faster, but a parallel surface that doesn't move canon).

### How to VALIDATE D cheaply (working backwards, "as if it exists")

Do NOT build the sugar/parser yet. Instead:
1. Author the IDEAL `elements.ig`: a `module html.elements` (or `frame.elements`) of element-contracts
   (`Col`, `Row`, `Label`, `Button`, …) with a shared `Attrs` record, returning the descriptor/Frame
   node — using ONLY today's live language (manual `children: Collection[Element]` threading).
2. Author ONE real screen (the list) over it, BOTH ways: (a) as-it-must-be-written-today (manual
   nesting — feel the Axis-A pain precisely), and (b) as-if-the-sugar-existed (`col { row { … } }`).
3. The delta between (a) and (b) IS the exact language pressure: write it up as a precise proposal ask
   (invocation-form brace-body-as-children + attr-reuse), grounded in a runnable specimen.
   If (a) is intolerable AND the gaps look too deep to land, THEN fall back to B/C (side-dialect).

This is the honest test of Alex's idea: it wins if element-contracts + the (proposed) `div { … }` sugar
give a clean surface with only bounded, canon-aligned gaps — and the specimen will show that directly.

## VALIDATION RESULTS — specimen compiled on the real `igc` (Candidate D)

Working backwards with runnable `.ig`, compiled by the canon Ruby compiler (`igniter-lang/bin/igc
compile`). Specimens in `lab-docs/lang/specimens/dx-view-d/`.

**What COMPILES today (`status: ok`, real compiler):**

1. `elements.ig` — element-contracts (`Col/Row/Leaf/Button`) + a RECURSIVE `Element { children:
   Collection[Element] }` type → `ok` standalone. The recursive view-node type and the element library
   are real on today's surface.
2. `list_view_inline.ig` — the full list screen, static, same module → `ok` (5 contracts).
3. `list_view_dynamic.ig` — **the realistic one: a DATA-BOUND, DYNAMIC, nested screen** →
   `ok`. A row per lead is `map(lead_labels, label -> call_contract("Leaf", a_row, label))`; the add
   button is appended with `append(...)`; nesting threads element outputs as children.

**The biggest assumed blocker was FALSE.** The design above feared "no fold/map (AP-P03) ⇒ dynamic
lists impossible." Verify-first killed that: `map` / `filter` / `fold` / `filter_map` / `append` all
exist in stdlib with lambdas (`p -> p.amount`, `(acc,x) -> …`), so a dynamic data-bound list compiles
today. **Candidate D's hardest worry evaporates.**

**The REAL, much narrower pressures (each grounded in actual compiler output):**

| # | pressure | evidence (real diagnostic) | severity / track |
|---|---|---|---|
| P1 | **cross-module `call_contract` is blocked** — an `elements.ig` LIBRARY can't be imported and called from a view module; must inline | `OOF-TY0: call_contract: unknown callee 'Leaf' — not found in this module` | the #1 real blocker for a reusable element library; active track **LANG-TYPED-CONTRACT-REF** (Rust live, Ruby planning) |
| P2 | **nesting needs a named `compute` per node** — no inline child nesting; this is the gap the `div { … }` sugar fills | (authoring shape in `list_view_inline.ig`) | the **invocation-form** sugar, already proposed (**LANG-FORM-VOCABULARY**, brace-body-as-children = deferred P4) |
| P3 | **attrs are verbose** — required-only records, no defaults/spread/shape-data ⇒ spell out every Attrs | (6 `a_*` computes in the specimen) | ergonomics; relates to PROP-016 shapes (but shapes are ports-not-data) |
| P4 | **a lambda body can't be a record literal** — `x -> { field: … }` parse-errors; must wrap in a contract call | `ParseError: Expected rbracket, got rbrace` / `Unexpected token: colon` | minor; element-contracts sidestep it (you call `Leaf`, not an inline record) |

**Verdict: Candidate D is strongly validated.** A dynamic, nested, data-bound view authored as PURE
igniter element-contracts COMPILES today. The distance from today's authoring (a) to the wished
`col { row { leaf } }` (b) is **only**: invocation-form sugar (proposed) + cross-module contract refs
(active track) + attrs ergonomics — NOT new semantics, and NOT a side-dialect. This rides canon's own
tracks and turns the work into precedent-setting language pressure, exactly as hoped. The (a)→(b) delta
IS the pressure ask: { LANG-TYPED-CONTRACT-REF for an `elements.ig` library · LANG-FORM-VOCABULARY
brace-body-as-children for `div { … }` · attrs defaults/spread }.

Recommended next: keep going on D — (i) a tiny **host bridge** that renders the compiled `Element`
tree through the frame-ui `WidgetRenderHost` (so the `.ig`-authored view runs live, closing the loop),
then (ii) write the precise language-pressure card from the (a)→(b) delta. Fall back to B/C only if the
host bridge exposes a deeper semantic gap.

### HOST BRIDGE — loop CLOSED (done)

`igniter-frame/src/ig_bridge.rs` maps an `.ig` `Element` tree (JSON) → a `LayoutBox` → `solve` →
canonical widget nodes → the shared `WidgetRenderHost`. The `Element` descriptor carries STRUCTURE
(`dir/main/flex/pad/gap`) but no coordinates — exactly the layout engine's input — so the same
machine-free pipeline that draws every hand-written screen draws the `.ig`-authored one. wasm
`render_ig_view(json, w, h)` + `web/ig.html` (+ `web/list_view.element.json`, the type-verified output
of `list_view_dynamic.ig`).

Evidence: `cargo test` 64/0 (adds 4 bridge tests — incl. the `.ig` tree lays out identically to the
hand-written list: sidebar `Fixed(248)`, items at y `12/60/108/156`; text survives into the SVG;
total on malformed JSON; deterministic). Machine-free + wasm32 clean, zero kernel symbols. **Proven
LIVE**: the page renders the `.ig` Element tree through frame-ui (sidebar rows + `＋ add item`, detail
title + green `mark done`), and editing the JSON reflows the view (added a 4th lead → it flows in, add
shifts down); no console errors. So a view authored as PURE igniter (Candidate D) runs live, machine-
free, through frame-ui — the descriptor IR is exactly what the host draws. The only remaining seam is
driving the live `igc run` VM to PRODUCE the JSON (vs. the type-verified fixture) — a passport-gated
follow-on, not a semantic gap. **Candidate D is validated end-to-end; no fallback to B/C needed.**

## Anchors

- recon that set this up: `lab-docs/lang/lab-frame-dx-authoring-surface-recon-p1-v0.md`
- `.ig` reducer idiom (the logic half, unchanged): `apps/igniter-apps/arch_patterns/event_sourcing.ig:12-53`
- the two existing view dialects: `frame-ui/igniter-ui-kit/src/view_artifact.rs` (A),
  `frame-ui/igniter-view-engine/lib/igv_compiler.rb` + `fixtures/*.igv` (B)
- the two halves we already built: `frame-ui/igniter-frame/src/layout.rs` (`parse`, structure),
  `…/widget_host.rs` (canon widget vocab, leaves)
- canon fold pressure `each` would lean on: `AP-P03` (collection fold/reduce)
