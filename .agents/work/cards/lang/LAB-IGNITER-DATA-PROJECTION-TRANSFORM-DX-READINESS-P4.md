# LAB-IGNITER-DATA-PROJECTION-TRANSFORM-DX-READINESS-P4

Status: CLOSED (DX readiness packet delivered 2026-06-25)
Route: standard / language-DX readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-data-projection-transform-dx-p4-v0.md`.

**Current DX verdict:** sufficient and **GREEN** for the Todo HTML list — `map`/`filter`/`fold` + per-row
"view contract" helpers (+ comprehension for inline) carry v0 with **no new syntax as a prerequisite**.
Verified live: `cargo test --test todo_view_app_tests` → **14 passed, 0 failed** (incl.
`list_html_maps_domain_collection_to_nodes`, `pending_html_filters_then_maps_domain_collection`,
`helper_authored_html_is_byte_identical_to_direct_records`).

**Flatness diagnosis (the team's insight, confirmed):** a transform is a graph of steps with hierarchy;
`.ig` flattens it — (1) flow is name-encoded in `compute` variable names, not syntactic; (2) edges are
stringly `call_contract("Name",…)` into one flat namespace; (3) **inline record-map is structurally
impossible** — `map(c, t -> { … })` parses `{` as a lambda block, not a record literal
(`collection_comprehension_tests.rs:137-140`), which is *why* `todo_views.ig` routes every node through
`MakeLabel`/`TodoLabel` helpers. Real DX problem, not a capability problem; doesn't block the list.

**Transform = convention, not keyword (Q3):** a transform IS a pure contract (`<Row>To<Target>` view
contract) or a `map`/comprehension over one; a `transform` keyword would be redundant with `pure contract` +
`map`. Recommend standardizing the `<Row>To<Target>` naming so code + graph-viz render transforms legibly.

**Comprehension (Q2):** available now + recommended for inline projections (the only inline record-literal
form), but **NOT a prerequisite** — Idiom A (helper `map`) ships the list without it. Don't gate Todo HTML on
it. (Body still can't nest `filter_map`/`reduce` — OOF-COL-NESTED.)

**#1 DX follow-up — pipeline operator `|>`:** deterministic parse-time sugar lowering **byte-identically** to
nested HOFs (same move as comprehension→map/filter `collection_comprehension_tests.rs:5`, `.igweb`→`.ig`).
Restores the *flow* dimension (edges syntactic, not name-encoded). Risk-free, philosophy-fitting. Defer the
*containment* dimension (scoped/nested contracts) as a larger separate lever.

**Next cards:** (impl) `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` = next Todo-HTML slice (render list
from typed read rows, Idiom A, DB-free); (lang-DX) `LAB-LANG-PIPELINE-OPERATOR-READINESS`; (docs)
`LAB-LANG-TRANSFORM-CONVENTION`. Scoped-contracts / non-stringly-calls / default-field-values named as deeper
pressure.

**Boundary honored.** No code / route / compiler / runtime change; no `transform`-keyword claim; no canon
claim. Docs only. `git diff --check` clean; grep → `/tmp/igniter-transform-dx-grep.txt` (1376 hits);
`todo_view_app_tests` 14/14 (read-only run, no source touched).

## Goal

Study the **authoring DX after typed rows cross**:

```text
Collection[TodoRow]
  -> transform
  -> Collection[TodoViewModel] / Collection[HtmlNode]
  -> RenderView
```

This card is about the shape of `transform` in Igniter, not the host crossing itself.

## Current Authority

- P1 data-projection packet.
- P2/P3 if available.
- Live language support for records, HOFs, comprehensions, record spread, helpers.
- Todo view helper cards and current `todo_view_app`.

## Pressure To Read

- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `apps/igniter-apps/query_engine/`
- `apps/igniter-apps/batch_importer/`
- cards/docs for:
  - record spread / record ergonomics;
  - collection comprehension;
  - HOF `map/filter/fold/reduce`;
  - ViewArtifact helper contracts.

## Questions To Answer

1. Is existing `map/filter/fold + helper contracts` enough for v0 transform DX?
2. Does Todo HTML list pressure require collection comprehensions now, or can HOFs carry it?
3. Do we need a named `transform` construct, or is "transform" just a convention over pure contracts?
4. What does an ideal Todo row-to-view chain look like in current syntax?
5. What is too verbose today?
   - record literals;
   - helper contracts;
   - nested HOFs;
   - lack of let/signature-bound syntax;
   - lack of collection comprehension.
6. Which language-pressure card should be next, if any?
7. What should Todo HTML P-next implement after typed crossing?

## Design Bias

Avoid inventing new syntax before proving existing HOF/helper-contract style is insufficient. But be honest:
if Todo HTML list is unreadable without collection comprehensions or row-view helper conventions, say so.

## Boundary

Allowed:

- Write a readiness packet.
- Include pseudo-code in both current syntax and aspirational syntax.
- Recommend language follow-up cards.

Closed:

- No implementation.
- No Todo HTML route changes.
- No compiler/runtime changes.
- No claim that `transform` is a language keyword.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-data-projection-transform-dx-p4-v0.md`

Must include:

- current feasible syntax examples;
- pain-point table;
- whether collection comprehension is required now or later;
- recommended Todo HTML authoring shape;
- next DX cards if needed.

## Verification

Run:

```bash
rg -n "map\\(|filter\\(|fold\\(|reduce\\(|for .* in|\\.\\.\\.|HtmlNode|ViewArtifact|RenderView|TodoLabel|FormView" \
  server/igniter-web/examples apps/igniter-apps lang/igniter-compiler \
  > /tmp/igniter-transform-dx-grep.txt

cargo test --test todo_view_app_tests
git diff --check
```

Run Cargo from `server/igniter-web`.

## Acceptance

- [x] Packet exists.
- [x] It distinguishes transform-as-convention from transform-as-new-syntax.
- [x] It gives current-syntax Todo row-to-HTML pseudo-code.
- [x] It decides whether collection comprehension is prerequisite.
- [x] It identifies the first Todo HTML card after typed crossing.
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- current DX verdict;
- transform syntax recommendation;
- next Todo HTML slice;
- any language follow-up.
