# LAB-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4 - Measure TodoApp language ergonomics after P2/P7

Status: CLOSED
Lane: parallel / language-surface / ergonomics
Type: research-scorecard
Delegation code: OPUS-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Recent language-surface work shipped several app-pressure features:

- signature-bound contracts `(inputs) -> (outputs) { ... }`;
- fallible binding `?` over `Result`;
- collection comprehensions `[node for item in items if pred]`;
- structured `InvokeEffect.input`;
- IgWeb context composition / guards / resources / RenderView.

The user explicitly wants to evaluate language-surface work along two axes:

1. **ergonomics** — can people/agents write real app logic compactly and readably?
2. **effectiveness/performance** — can the model run competitively enough? (covered by a separate bench card)

This card owns the ergonomics axis only. Do not make performance claims here.

## Goal

Create a concrete before/after scorecard from real TodoApp files:

```text
current authored TodoApp API + views
  vs
same logic rewritten using the newest surface where useful
```

The output should identify which syntax features materially reduce friction and which pain points remain.

## Verify First

Read live files before scoring:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_view_app/` (if present; find live path)
- `lang/igniter-compiler/tests/{signature_contract_surface_tests,fallible_binding_tests,collection_comprehension_tests}.rs`
- `lab-docs/lang/lab-lang-signature-bound-contract-surface-p2-v0.md`
- `lab-docs/lang/lab-lang-fallible-binding-p2-v0.md`
- `lab-docs/lang/lab-lang-collection-comprehension-p2-v0.md`
- `lab-docs/lang/lab-igniter-web-viewartifact-helper-contracts-p20-v0.md`

Confirm or correct:

- which TodoApp files already use the new sugar;
- whether examples still show older explicit `input/compute/output` shape;
- where verbosity remains: records, repeated `QueryFilter`, `WriteValues`, `HtmlNode`, explicit args,
  manual continuation plumbing, idempotency guards, or `Result`/`Option` handling.

Live code wins over this card.

## Deliverable Shape

Produce a scorecard doc:

```text
lab-docs/lang/lab-lang-app-pressure-ergonomics-scorecard-p4-v0.md
```

Include:

- a table of representative snippets;
- old/current form vs improved proposed form;
- measurable counts:
  - lines;
  - tokens or rough lexical units;
  - repeated field names;
  - number of helper contracts;
  - number of places a route arg must be repeated;
- qualitative notes:
  - readability for a human;
  - readability for an agent;
  - diagnostic locality;
  - authority-boundary visibility;
- one recommended next language-surface card.

If useful, add a **new fixture only** under compiler tests showing the improved form compiles. Do not rewrite
product examples unless the card explicitly justifies a tiny migration.

## Suggested Examples To Score

At minimum score:

1. `ListTodosByAccount` / `QueryPlan` construction.
2. `CreateTodo` / `MarkTodoDone` structured `WriteIntent`.
3. Todo HTML list ViewArtifact construction.
4. One guard/continuation flow.
5. One failure path with `Result` or app-owned 404.

## Questions To Answer

1. Which shipped sugar gives the largest real reduction?
2. Does signature-bound contract syntax improve graph readability or hide important node structure?
3. Does `?` reduce guard/Result boilerplate in actual app code, or is it blocked by current types?
4. Do comprehensions solve ViewArtifact list pressure?
5. Are helper contracts still needed after comprehensions?
6. Where does the app still feel "too graph-ceremonial"?
7. Where is explicitness valuable enough to keep?
8. What syntax would be harmful because it hides authority?
9. Which next language card should be prioritized under TodoApp pressure?
10. Which changes are only documentation/example migrations, not language changes?

## Required Acceptance

- [x] Scorecard uses live TodoApp files (todo_handlers.ig, routes.igweb, todo_views.ig), not imagined examples.
- [x] Five snippets compared (conditional list, plain list, contract ceremony, read-intent record, guard/failure path).
- [x] Numeric friction metrics reported (7-row table: nodes, nesting depth, body keywords, repeated names, route-arg repetition, HtmlNode fields, helper count).
- [x] Human and agent ergonomics discussed separately.
- [x] Authority-boundary readability scored (preserved by all three surfaces).
- [x] "Do not add" recommendation included (effectful/await operator or implicit Decision short-circuit that hides InvokeEffect).
- [x] One next implementation card proposed (`LAB-LANG-RECORD-FIELD-PUNNING-P2`).
- [x] Fixtures compile through the real compiler (`app_pressure_scorecard_tests`, 3/3).
- [x] No performance claims.
- [x] No product behavior changes.
- [x] No canon claim.

---

## Closing Report (2026-06-21)

**Outcome:** ergonomics scorecard delivered: `lab-docs/lang/lab-lang-app-pressure-ergonomics-scorecard-p4-v0.md`.

**Method:** scored 5 live TodoApp snippets current-vs-improved; backed every improved form with a compile
fixture (`tests/app_pressure_scorecard_tests.rs`, 3/3 green) that also proves the three surfaces **compose**
(signature + comprehension + filter; signature + `?` + `call_contract` Result).

**Key findings:**
- **Biggest wins:** signature-bound has the broadest reach (every contract sheds input/compute/output
  ceremony); comprehensions give the deepest per-site cut on ViewArtifact list/conditional-list rendering
  (`TodoPendingHtml`: 2 authored nodes → 1, inside-out `map(filter)` → linear).
- **`?` is latent here:** the app sidesteps `Result` via Bool flags + `via` routing, so `?`'s benefit only
  appears when a handler inlines a `Result`-returning guard (`E == O`) — proven to compile, not yet used.
- **Helpers still needed** for default-heavy `HtmlNode` records (7 fields, 5 defaulted) — comprehensions
  handle the collection, not per-element field verbosity.
- **Authority boundary preserved** across all three surfaces (InvokeEffect/Respond*/requires/pure stay
  explicit nodes).
- **Do-not-add:** an effectful/`await`-style operator or implicit Decision short-circuit that hides the
  effect/authority node behind a glyph.
- **Remaining friction:** field punning, defaulted records, `or_else` Option-unwrap, route-arg repetition.

**Recommended next card:** `LAB-LANG-RECORD-FIELD-PUNNING-P2` (parser-only `{ name }` ⇒ `{ name: name }`;
highest-frequency remaining friction; composes with record spread; no authority impact). Optional-field
defaults stay on the canon PROP track.

**Verification:** `cargo test --test app_pressure_scorecard_tests` 3/3; full igniter-compiler 175/0;
`git diff --check` clean. No perf claims, no product changes, no canon claim.

## Required Verification

If adding compile fixtures:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test <new_or_existing_test>
git diff --check
```

If doc-only:

```bash
git diff --check
```

## Closed Scope

- No benchmarking/perf.
- No local Postgres.
- No runner changes.
- No broad rewrite of TodoApp examples.
- No new syntax unless explicitly limited to a compile fixture.
- No canon claim.

## Suggested Next

Likely outputs:

- a tiny migration card for TodoApp examples to showcase signature/comprehension syntax;
- or a language implementation card for the single biggest remaining app-pressure pain point.
