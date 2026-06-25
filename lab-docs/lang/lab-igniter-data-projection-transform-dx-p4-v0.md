# lab-igniter-data-projection-transform-dx-p4-v0

Card: `LAB-IGNITER-DATA-PROJECTION-TRANSFORM-DX-READINESS-P4`
Route: standard / language-DX readiness · Skill: idd-agent-protocol
Status: readiness packet (no code changed; no new syntax claimed; no canon claim)
Date: 2026-06-25
Builds on: P1 boundary · P2 materialization · P3 contract-and-errors packets.

> **Authority boundary.** DX study only. Implements nothing, claims no new keyword. Every concrete claim is
> cited against live source or a green test. `transform` is **not** asserted to be a language construct.

---

## Headline

**v0 transform DX ships on what exists today** — `map`/`filter`/`fold` + per-row "view contract" helpers
(+ comprehension for inline projections). It is *sufficient and green* for the Todo HTML list (14/14
`todo_view_app_tests` pass). **No new syntax is a prerequisite.**

**But the card's framing is right, and the honest finding confirms the team's insight:** a transform is
conceptually a *graph of steps with hierarchy*, and `.ig` flattens it two ways — **edges become strings**
(`call_contract("Name", …)` into one global namespace) and **pipelines become name-chained `compute`s**
(dataflow `a→b→c` encoded in variable names, not syntax). The single highest-leverage, lowest-risk DX
follow-up is a **pipeline operator `|>`** that lowers byte-identically to nested HOFs (exactly as
comprehension already lowers to `map`/`filter`) — it restores the *flow* dimension the graph has and the text
loses. A deeper, larger lever (scoped/nested contracts) restores the *containment* dimension; named as
pressure, not recommended for v0.

---

## 1. The flatness diagnosis (why this card exists)

An Igniter program is a graph: contracts are nodes, `call_contract` references are edges. In a visualization
that graph has natural hierarchy. The **textual** form projects that 2-D graph onto a 1-D list of
equally-ranked statements, losing two dimensions:

1. **Flow is name-encoded, not syntactic.** A pipeline `rows → filter → map → wrap` becomes:
   ```text
   compute pending : Collection[TodoRow]  = filter(rows, r -> r.done == false)
   compute body    : Collection[HtmlNode] = map(pending, r -> call_contract("TodoRowToNode", r))
   compute view    : ViewArtifact         = call_contract("FormView", "Todos", body)
   ```
   The edges (`pending→body→view`) live in the *variable names*; the reader reconstructs the flow.
2. **Edges are strings into a flat namespace.** `call_contract("TodoRowToNode", r)` — the edge is a string
   literal; the subgraph "this view owns these helpers" is not expressible. Helpers (`MakeLabel`, `FormView`,
   `TodoLabel`) are equal-rank siblings (`server/igniter-web/examples/todo_view_app/todo_views.ig:78-148`).

This is exactly "beautiful as a graph, flat mesh as code." It is a **DX problem, not a capability problem** —
the computation works; the *form* hides the structure.

A third, sharper finding makes the flatness *structural*, not just stylistic: **you cannot inline a
row→record map.** `map(todos, t -> { tag: t.title })` does **not** compile — the `{` after `->` parses as a
lambda *block*, not a record literal (`lang/igniter-compiler/tests/collection_comprehension_tests.rs:137-140`:
"strictly MORE expressive than the explicit `map(…, t -> { … })`, whose `{` after `->` parses as a lambda
block"). So to project a collection of records you are *pushed* into either a comprehension or a flat helper
contract. That is *why* `todo_views.ig` routes every node through `MakeLabel`/`TodoLabel` — not only to hide
defaults, but because inline record-mapping is unavailable.

---

## 2. Current feasible syntax (verified green)

The view-transform substrate is live and passing — `cargo test --test todo_view_app_tests` →
**14 passed, 0 failed** (run 2026-06-25), including:
- `list_html_maps_domain_collection_to_nodes` — `map(domain collection -> nodes)` renders;
- `pending_html_filters_then_maps_domain_collection` — `filter` then `map` (the transform pipeline);
- `helper_authored_html_is_byte_identical_to_direct_records` — helper contracts are byte-identical sugar.

Live forms available for a `Collection[<Row>] → Collection[HtmlNode] → RenderView` transform:

| Form | Status | Where proven |
| --- | --- | --- |
| `filter(coll, x -> pred)` | live | `todo_views.ig:161`; `query_engine/eval.ig:76` |
| `map(coll, x -> call_contract("Helper", x))` | live | `todo_views.ig:144,162` |
| `fold(coll, init, (acc, x) -> …)` | live | `query_engine/eval.ig:66` |
| per-row "view contract" helper (`<Row> -> HtmlNode`) | live | `todo_views.ig:131-136` (`TodoLabel`) |
| field helper hiding wide-record defaults (`MakeLabel`/`MakeButton`/`MakeSelect`) | live | `todo_views.ig:78-108` |
| `FormView`/wrapper helper (`Collection[HtmlNode] -> ViewArtifact`) | live | `todo_views.ig:92-97` |
| comprehension `[ E for x in C if P ]` (incl. record-literal element) | live, byte-identical to `map`/`filter` | `collection_comprehension_tests.rs:1-5, 137-149` |
| record spread `{ ...base, field: v }` | live | `record_spread` cards (P1) |
| nested `map`/`filter`/`fold` inside HOF lambdas | live | nested-HOF cards (P1) |
| nested `filter_map`/`reduce` inside HOF lambdas | **NOT** live (OOF-COL-NESTED) | use `call_contract` workaround |
| inline `map(c, x -> { record literal })` | **NOT** live (`{`→block) | use comprehension or helper |
| pipeline operator `\|>` | **NOT** present | — |
| bare-name contract call (`TodoRowToNode(r)`) | **NOT** present (calls are stringly) | — |
| default field values in `type` decls | **NOT** present | — |

---

## 3. Recommended Todo HTML authoring shape (v0, current syntax)

Two idioms; pick per case. Both compile today.

**Idiom A — per-row view contract + `map` (recommended default).** Best when the node build is reusable or
the target record is wide-with-defaults (like `HtmlNode`’s 7 fields):

```text
type TodoRow      { id : String  account_id : String  title : String  done : Bool }   -- app owns (P3)
type DatasetMeta  { source : String  count : Integer  truncated : Bool }              -- provenance (P3)

-- the per-row transform IS a pure contract (transform = convention, §5)
pure contract TodoRowToNode {
  input r : TodoRow
  compute node : HtmlNode = call_contract("MakeLabel", r.title)   -- reuse the P20 default-hiding helper
  output node : HtmlNode
}

pure contract AccountTodoIndexFromRows {
  input req  : Request
  input rows : Collection[TodoRow]       -- typed projection crosses here (P2/P3)
  input meta : DatasetMeta
  compute pending : Collection[TodoRow]  = filter(rows, r -> r.done == false)
  compute body    : Collection[HtmlNode] = map(pending, r -> call_contract("TodoRowToNode", r))
  compute view    : ViewArtifact         = call_contract("FormView", "Todos", body)
  compute d       : Decision             = RenderView { status: 200, view: view }
  output d : Decision
}
```

**Idiom B — comprehension (inline, no helper).** Best for a one-off projection where the node is simple; it
is the *only* way to inline a record literal (§1):

```text
compute body : Collection[HtmlNode] =
  [ { kind: "label", id: "", label: "", text: r.title, required: false, action: "", options: [] }
    for r in rows if r.done == false ]
```

Idiom B is honest about the verbosity: the flat 7-field `HtmlNode` literal is noisy inline, which is exactly
why Idiom A’s `MakeLabel` exists. **Recommend Idiom A as the default; Idiom B for trivial inline cases.**

---

## 4. Pain-point table (honest)

| Pain | Today | Root cause | Lever (deferred pressure) | Severity for Todo list |
| --- | --- | --- | --- | --- |
| Dataflow is name-encoded, not syntactic | flat `compute a; compute b; compute c` | no pipeline/composition syntax | **pipeline `\|>`** (sugar → nested HOF) — *#1 lever* | low now, high as views grow |
| Edges are stringly into a flat namespace | `call_contract("Name", …)` | no bare-name static call in `.ig` bodies | non-stringly call form | medium |
| Helpers can't be scoped to their transform | flat sibling contracts | no nested/scoped contracts | scoped/section grouping — *the containment lever* | medium |
| Inline record map impossible | `map(c, t -> { … })` → `{`=block | `->` `{` parser ambiguity | comprehension (live) **or** lambda-block-vs-record disambiguation | low (comprehension/helper cover it) |
| Wide-record literal verbosity | 7-field `HtmlNode` everywhere | no default field values; no default to spread from | default field values **or** `{ ...DEFAULT_NODE, text: t }` convention | low (helpers hide it) |
| `filter_map`/`reduce` not nestable in HOF | OOF-COL-NESTED | eval_ast nesting gap | existing nested-HOF cards | low (use `call_contract`/`fold`) |

**Reading of the table:** none of these *block* the Todo HTML list (Idiom A clears every one via existing
helpers/HOFs). But the top three rows are the same flatness the team flagged — they bite as views grow from a
flat list to grouped/conditional/computed layouts.

---

## 5. transform-as-convention vs transform-as-syntax (Q3)

**Recommendation: transform stays a *convention over pure contracts*, not a keyword.** A transform already
*is* a pure contract — the per-row `TodoRowToNode`, or a `map`/comprehension over one. A `transform` keyword
would be redundant with `pure contract` + `map`, and the card boundary forbids claiming it anyway.

What *is* worth standardizing is the **naming convention** so the transform is legible both in code and in the
graph visualization the team values: a per-row projection contract named `<Row>To<Target>` (e.g.
`TodoRowToNode`, `TodoRowToViewModel`). A recognizable convention lets the IDE/graph view *render the
transform edge as a transform* — a cheap, zero-language-change win that directly serves the "beautiful as a
graph" goal. (This is a docs/convention card, not a language change.)

---

## 6. Is collection comprehension a prerequisite? (Q2 — explicit decision)

**Decision: comprehension is *available now and recommended for inline projections*, but it is NOT a
prerequisite for Todo HTML.** Idiom A (helper-contract `map`) ships the list with zero reliance on
comprehension. Comprehension is the *better inline* form (and the only inline record-literal form, §1), but
the Todo HTML list is not blocked on it. So: **use comprehension where it reads better; do not gate the Todo
HTML slice on it.** (Caveat: a comprehension body still cannot nest `filter_map`/`reduce` — OOF-COL-NESTED — so
multi-stage inline projections route through a helper or `fold`.)

---

## 7. The DX follow-up that matters: pipeline operator `|>`

This is the honest answer to "the language is good at computation but flat as a graph." The highest-leverage,
lowest-risk lever is a **pipeline operator** that turns the name-chained `compute` sequence into a legible
left-to-right flow:

```text
-- aspirational (NOT implemented; lowers byte-identically to the nested HOF form below)
compute body : Collection[HtmlNode] =
  rows
  |> filter(r -> r.done == false)
  |> map(r -> call_contract("TodoRowToNode", r))

-- lowers to the EXACT proven form:
compute body : Collection[HtmlNode] =
  map(filter(rows, r -> r.done == false), r -> call_contract("TodoRowToNode", r))
```

Why this is the right first DX card:
- **Philosophy-fit (high).** Igniter already embraces *deterministic lowering sugar that compiles to explicit
  `.ig`*: `.igweb` → `.ig` (`igweb.rs`), `.igv` → ViewArtifact JSON, and comprehension → `map`/`filter`
  *byte-identical, no new SIR node* (`collection_comprehension_tests.rs:5`). `|>` is the same move applied to
  the *flow* dimension. No new runtime, no new value, no new SIR kind.
- **Restores the lost dimension.** It makes the graph’s *edges syntactic* (flow reads top-to-bottom /
  left-to-right) instead of reconstructed from variable names — the precise flatness the team named.
- **Risk-free.** Pure parse-time sugar; the lowered form is already proven green (§2). Drift-proof like
  comprehension.
- **Composes with everything here.** `rows |> filter(...) |> map(TodoRowToNode)` is exactly Idiom A, made
  legible.

It does **not** solve *containment* (helpers scoped to their transform) — that is a larger, separate lever
(scoped/nested contracts or a `section`/grouping construct). Name it as the deeper follow-up; do not bundle it
with `|>`.

---

## 8. Recommended next cards

| Card | Type | Why / when |
| --- | --- | --- |
| `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` (impl) | implementation | **The next Todo-HTML slice (Q7):** after typed crossing (P2/P3), render the Todo list from *typed read rows* — `Collection[TodoRow] → map(TodoRowToNode) → FormView → RenderView` over a fake-adapter read. Joins the read half to the proven view half. Idiom A; DB-free harness. |
| `LAB-LANG-PIPELINE-OPERATOR-READINESS` (language-DX) | readiness | The `\|>` sugar (§7). Highest-leverage DX lever; pure lowering to nested HOF. Recommend authoring this on the language-DX axis. |
| `LAB-LANG-TRANSFORM-CONVENTION` (docs) | convention | Standardize the `<Row>To<Target>` per-row view-contract naming so code + graph view render transforms legibly (§5). Zero language change. |
| *(pressure, not yet)* scoped/nested contracts; non-stringly `.ig` calls; default field values | language pressure | The *containment* dimension + edge legibility + record verbosity. Larger; name as pressure, revisit when richer views demand it. |

---

## Verification

```bash
rg -n "map\(|filter\(|fold\(|reduce\(|for .* in|\.\.\.|HtmlNode|ViewArtifact|RenderView|TodoLabel|FormView" \
  server/igniter-web/examples apps/igniter-apps lang/igniter-compiler \
  > /tmp/igniter-transform-dx-grep.txt        # 1376 hits

cargo test --test todo_view_app_tests          # 14 passed, 0 failed (run from server/igniter-web, 2026-06-25)
git diff --check                               # clean
```

---

## Reporting

- **Current DX verdict:** sufficient and **green** for the Todo HTML list — `map`/`filter`/`fold` + per-row
  view-contract helpers (+ comprehension for inline) carry v0 with **no new syntax as a prerequisite**
  (`todo_view_app_tests` 14/14). The flatness the team named is real (flow is name-encoded; edges are
  stringly; inline record-map is impossible) but does not *block* the list.
- **Transform syntax recommendation:** keep `transform` a **convention over pure contracts** (`<Row>To<Target>`
  view contracts), not a keyword. Adopt **comprehension** for inline projections (available now, not a
  prerequisite). Recommend a **pipeline operator `|>`** as the next language-DX card — deterministic sugar
  lowering byte-identically to nested HOFs, restoring the *flow* dimension; defer the *containment* lever
  (scoped contracts) as larger pressure.
- **Next Todo HTML slice:** `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` — render the list from typed read
  rows (Idiom A), DB-free, after the P2/P3 crossing.
- **Language follow-up:** `LAB-LANG-PIPELINE-OPERATOR-READINESS` (#1), `LAB-LANG-TRANSFORM-CONVENTION` (docs);
  scoped-contracts / non-stringly-calls / default-fields named as deeper pressure.
