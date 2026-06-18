# Card: LAB-IGNITER-WEB-ROUTING-DX-SHAPE-P2 — choose the beautiful IgWeb routing authoring shape

**Lane:** standard / research-shape-selection
**Skill:** idd-agent-protocol
**Status:** CLOSED (shape-selection packet)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Delegation label:** OPUS-SERVER-WEB-DX-B
**Authority:** Lab research/design only. No canon claim. No compiler/server implementation.

## Why this card exists

P1 proved the architectural boundary: a pure Igniter web app should map
`Request -> Decision`, and `igniter-server` must stay a generic Rack/Puma-like
substrate. But P1's honest sketch still risks accepting an ugly authoring pattern:
large nested `if/else`, manual `starts_with`, and awkward segment extraction.

That would be the wrong point to freeze. We have travelled too far to make web
routing feel like accidental compiler workaround code.

This card chooses a **developer-facing routing shape** for IgWeb before any P2
implementation. The question is not merely "can it compile?" but:

> What is the most expressive, compact, Igniter-native way to describe web routing
> without turning `igniter-server` into a domain router or pretending Igniter is a
> general-purpose DSL language when it is not?

## Core guardrail

Do **not** implement the Todo adapter yet if the routing shape is still ugly.
This card is allowed to reject P1's suggested `LAB-IGNITER-WEB-ROUTING-TODO-P2`
implementation route and replace it with a better prerequisite.

## Read first (verify-first, live code wins)

- `lab-docs/lang/lab-igniter-web-routing-pure-ig-p1-v0.md`
- `.agents/work/cards/lang/LAB-IGNITER-WEB-ROUTING-PURE-IG-P1.md`
- `igniter-server/README.md`
- `lab-docs/lang/lab-machine-igniter-server-wave-checkpoint-p14-v0.md`
- `igniter-server/src/protocol.rs`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-compiler/src/parser.rs`
- `igniter-compiler/src/project.rs`
- `igniter-compiler/tests/project_mode_tests.rs`
- `igniter-compiler/tests/project_overlay_tests.rs`
- `igniter-apps/web_router/serve.ig`
- `igniter-apps/web_router/types.ig`
- `igniter-apps/web_router/PRESSURE_REGISTRY.md`
- any current docs/tests mentioning `call_contract`, invocation forms, or dynamic dispatch
  (`rg -n "call_contract|invoke|invoc|dispatch|route" igniter-* igniter-apps lab-docs`)

## Goal

Produce a shape-selection packet that recommends one IgWeb routing authoring pattern
and rejects the alternatives with evidence.

The packet must distinguish three levels:

1. **Current valid `.ig`** — what compiles today.
2. **Lab sugar / lowering candidate** — ergonomic syntax that could lower to current
   `Request -> Decision` contracts without changing server core.
3. **Language gap** — features needed before this can be beautiful and canonical.

## Required output

Write:

`lab-docs/lang/lab-igniter-web-routing-dx-shape-p2-v0.md`

Then close this card with a compact report.

## Candidate shapes to evaluate

Evaluate at least these five. Add more only if useful.

### Shape A — Explicit entry contract

A plain `Serve(req)` contract with `if`/`match` and `call_contract`.

Questions:
- How ugly does it get for 7 Todo routes?
- Can nested method/path branching be made readable with helper contracts?
- Is this acceptable as lowered output but not authoring source?

### Shape B — Route records / route table as data

A pure `.ig` data model such as:

```igniter
type Route {
  method  : String
  pattern : String
  target  : String
}
```

and a matcher that finds the route.

Questions:
- Can current Igniter construct route records/collections ergonomically?
- Does dynamic `target -> call_contract(target, req)` exist safely today?
- Does this become stringly dispatch and lose typed/exhaustive properties?

### Shape C — Invoc / call forms as routing vocabulary

Investigate whether existing invocation/call forms can carry a route meaning:

```igniter
route GET "/todos"        -> TodoIndex
route POST "/todos"       -> TodoCreate
route GET "/todos/:id"    -> TodoShow(id)
route POST "/todos/:id/done" -> TodoDone(id)
```

This may be pseudo-syntax. The point is to ask whether an Igniter-native
**declaration/invocation form** can be the authoring layer, and what it would lower
to.

Questions:
- What existing syntax is closest: `call_contract`, assumptions, effects,
  entrypoint metadata, declarations, annotations, or `.igv`-style lowering?
- Can route declarations be represented as facts/artifact metadata rather than
  new language syntax?
- Would this require parser/compiler work, or can a lab preprocessor lower it?

### Shape D — Rails-like resource macro, but Igniter-owned

Example sketch:

```text
resource todos {
  index  GET    "/todos"          -> TodoIndex
  create POST   "/todos"          -> TodoCreate requires idempotency
  show   GET    "/todos/:id"      -> TodoShow
  done   POST   "/todos/:id/done" -> TodoDone requires idempotency
}
```

Questions:
- Is resource grouping genuinely helpful, or does it import Rails/controller
  baggage too early?
- Can this stay a pure authoring artifact that lowers to `Request -> Decision`?
- What product vocabulary belongs here versus in Todo contracts?

### Shape E — Host-tokenized route algebra

A framework-owned algebra where the host/adapter provides generic path tokens,
then `.ig` matches structured facts:

```igniter
type RouteMatch {
  method   : String
  resource : String
  action   : String
  id       : Option[String]
}
```

Questions:
- Does this solve WR-P04 without smuggling a route table into Rust?
- Where is the line between generic path normalization and app-owned routing?
- Can this remain domain-free and deterministic?

## Pressure fixtures

Evaluate each serious candidate against these, not just Todo happy path:

1. **Todo basic**
   - `GET /todos`
   - `POST /todos`
   - `GET /todos/:id`
   - `POST /todos/:id/done`
   - `GET /health`
   - unknown route 404
   - wrong method 405

2. **Nested/domain pressure**
   - `GET /accounts/:account_id/todos/:id`
   - `POST /accounts/:account_id/todos/:id/done`
   This is where middle-param extraction matters. If current language cannot do it,
   say so bluntly.

3. **Webhook pressure**
   - `POST /webhooks/:vendor`
   - duplicate/idempotency key propagation
   - no effect identity in the app decision

4. **Static/assets pressure (design only)**
   - `GET /assets/app.css`
   - confirm whether this belongs to IgWeb routing v0 or a separate raw-response/assets card.

## Beauty criteria

Score each candidate 1-5 on:

- **Igniter-native:** looks like contracts/facts/decisions, not ad hoc web code.
- **Explicit authority:** app owns route meaning; host owns effect authority.
- **Typed/exhaustive:** avoids stringly hidden dispatch where possible.
- **Readable at 20 routes:** scales beyond the Todo toy.
- **Lowerable:** can lower to current or near-current `Request -> Decision` shape.
- **Diagnosable:** bad route declaration yields structured diagnostics, not runtime mystery.
- **Server-clean:** requires no route table/config in `igniter-server` core.
- **Future-friendly:** does not block UI/assets/API/webhook cases.

Include a score table and explain the winner.

## Required hard questions

1. Is pure `.ig` the right authoring surface for routing, or should routing be an
   adjacent `.igweb` / `.igv`-style artifact that lowers to `.ig`?
2. If Igniter is not strong as a DSL, what is the smallest non-canonical sugar that
   improves authoring without lying about language capability?
3. Can route declarations be **facts** consumed by a generic matcher contract rather
   than syntax?
4. Does dynamic `call_contract(route.target, req)` preserve safety, or should route
   targets be statically lowered into explicit `match` arms?
5. How do we avoid rebuilding Rails controllers while still giving Rails-level route
   readability?
6. Which exact missing language features would make the winning shape clean?
7. What should P3/P4 be if the answer is "fix WR-P04 first"?

## Deliverable structure

The packet must include:

1. Executive summary: winner + why.
2. Live surface inventory: what current `.ig`/compiler/server actually support.
3. Candidate sketches A-E.
4. Pressure fixture comparison.
5. Beauty score table.
6. Recommended authoring pattern.
7. Lowering model: source authoring -> generated `.ig`/artifact -> `ServerDecision`.
8. Language gaps with exact IDs where known (`WR-P04`, `OOF-TY1`, etc.).
9. Rejected shapes and why.
10. Next cards: one language/card prerequisite if needed, and one eventual Todo proof card.

## Acceptance

- [ ] Answers all required hard questions.
- [ ] Compares at least shapes A-E with concrete sketches.
- [ ] Uses Todo + nested route + webhook pressure fixtures.
- [ ] Includes beauty score table.
- [ ] Clearly chooses one recommended pattern or explains why no pattern is ready.
- [ ] Separates current-valid `.ig`, lab sugar/lowering, and true language gaps.
- [ ] Keeps routing/domain semantics out of `igniter-server` core.
- [ ] Does not implement Rust routing/domain Todo code.
- [ ] Does not modify compiler/parser/server semantics.
- [ ] Does not claim canon syntax.
- [ ] Proposes the next 1-2 cards in the correct order.

## Closed surfaces

- No server-core route table.
- No `igniter-server` behavior changes.
- No compiler/parser changes.
- No new canonical `.ig` syntax.
- No DB/persistence.
- No live listener/public network.
- No SparkCRM/vendor live work.
- No Rails clone or controller model.
- No app-domain Rust implementation.

## Suggested conclusion shapes (not authority)

Possible outcomes:

1. **Winner = lab `.igweb`/artifact sugar lowering to explicit `Serve` contract.**
   Next: `LAB-IGNITER-WEB-ROUTING-LOWERING-P3`.

2. **Winner = pure `.ig` route records + static lowering of targets.**
   Next: language/card for record literals or route artifact construction if missing.

3. **Blocked = WR-P04 must land first.**
   Next: `LAB-IGNITER-WEB-PATH-PARAMS-WR-P04-P3` before Todo proof.

4. **Winner = explicit contract is good enough after helper contracts.**
   Next: `LAB-IGNITER-WEB-ROUTING-TODO-P3`, but only if the packet proves it remains readable.

Do not pick the fastest outcome. Pick the shape we will not be embarrassed to show
a developer six months from now.

---

## Closing report — 2026-06-18

**Outcome:** Shape-selection packet delivered — all 7 hard questions answered, shapes A–E sketched +
scored against Todo/nested/webhook/static fixtures, one winner chosen with evidence. Design only; no
code/compiler/server change.

**Deliverable:** `lab-docs/lang/lab-igniter-web-routing-dx-shape-p2-v0.md`.

**Winner: Shape C — a lab `.igweb` declarative route DSL that lowers deterministically to an explicit
`Serve` (`Request → Decision`) `.ig` contract**, exactly as `.igv` lowers to ViewArtifact today
(`igniter-ui-kit/src/igv.rs::lower_igv`). D's `resource {}` grouping folds in as optional sugar; A is
the lowered output; B and E are rejected. Score: C 38/40, D 37, A 34, E 29, B 21.

**Two decisive live findings:**
1. **No dynamic dispatch** — `call_contract` is a compile-time string literal (`typechecker.rs:44`) +
   static VM registry ("no dynamic dispatch", `emitter.rs:128`). So Shape B (dynamic
   `call_contract(route.target)`) **cannot compile** and would discard exhaustiveness; route targets
   MUST be **statically lowered** into explicit `match` arms (hard Q4).
2. **Lowering sugar is proven in-tree** (`.igv`→ViewArtifact, deterministic, lab-only, zero compiler
   change) — so beautiful authoring costs a lab `lower_igweb` tool, not a language change (hard Q1/Q2).

**Gated on the real gap:** clean `:id` and ALL nested/middle-param routes need **WR-P04 / OOF-TY1**
(`split`→`Collection[String]` + `nth` + ergonomic Option `match`). Bluntly: nested middle-param routes
are **not** expressible today, and no shape may fake it with a Rust route table.

**Rejected P1's immediate route:** `LAB-IGNITER-WEB-ROUTING-TODO-P2` is **superseded** — building a
Todo adapter on prefix-only matching would freeze the ugly pattern (the card's core guardrail).

**Next cards (ordered):** (1) **`LAB-IGNITER-WEB-PATH-PARAMS-WR-P04-P3`** — language/stdlib prerequisite
(`split` typing + `nth(Collection[T],Integer)->Option[T]` + Option-match ergonomics). (2)
**`LAB-IGNITER-WEB-ROUTING-LOWERING-P4`** — the `.igweb`→`Serve` `.ig` lowering tool (mirrors
`lower_igv`) + fixture-only Todo proof, once params work.

**Acceptance:** all boxes met — hard questions answered; A–E compared with sketches; Todo + nested +
webhook + static fixtures used; beauty score table included; one recommended pattern chosen;
current-`.ig` / lab-sugar / language-gap levels separated; routing/domain kept out of server core; no
Rust routing/Todo code; no compiler/parser/server change; no canon claim; next 1–2 cards proposed in
order.
