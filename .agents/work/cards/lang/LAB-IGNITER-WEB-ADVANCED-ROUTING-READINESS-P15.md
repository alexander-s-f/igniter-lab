# LAB-IGNITER-WEB-ADVANCED-ROUTING-READINESS-P15 — scope/resources/nested/via shape

Status: CLOSED
Date: 2026-06-19
Lane: standard / research-readiness
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-ADVANCED-ROUTING-P15

## Intent

Research the next IgWeb routing DX layer after the flat `.igweb` route proof:

- route groups / `scope`;
- explicit `resources` sugar;
- nested routes/resources;
- route composition through parent/guard contracts (`via` or equivalent).

The goal is a beautiful, transparent Igniter-shaped routing pattern, not Rails-style hidden magic.
Borrow successful Rails/Rack ergonomics, but keep IgWeb inspectable, deterministic, and agent-friendly.

## Authority

This is a **readiness/design card only**. Do not implement parser/lowering changes.

`.igweb` remains a **Projection Dialect**: authored sugar that deterministically lowers to ordinary,
inspectable `.ig`. The generated `.ig` and existing compiler/VM/server path remain the behavioral
truth.

## Verify First

Read current live surfaces before proposing syntax:

- `server/igniter-web/README.md`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-web/examples/todo_app/todo_handlers.ig`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md`
- `lab-docs/lang/lab-igniter-web-runner-p12-v0.md`
- `lab-docs/lang/lab-igniter-web-runner-check-p14-v0.md`

Live code wins over this card. If a surface moved after P14, follow live code and report the delta.

## Core Question

What is the smallest advanced routing model that gives real web-app DX without turning IgWeb into:

- a second hidden runtime;
- a server route table;
- a controller convention system;
- a domain-specific framework baked into core;
- or a DSL whose generated behavior is hard for humans and agents to inspect?

## Candidate Syntaxes To Evaluate

Evaluate at least these four layers separately. Do not collapse them into one large feature.

### 1. `scope` as prefix + param grouping

Example pressure:

```igweb
scope "/accounts/:account_id" {
  route GET "/todos"          -> AccountTodosIndex
  route GET "/todos/:todo_id" -> AccountTodoShow
}
```

Research:

- should `scope` be the first advanced primitive?
- how do nested params merge?
- how does it lower to flat routes?
- what happens on duplicate param names?
- should route order remain pure source order?

### 2. `resources` as explicit authoring macro

Example pressure:

```igweb
resource todos "/todos" {
  index  GET    -> TodoIndex
  create POST   -> TodoCreate requires idempotency
  show   GET    "/:id" -> TodoShow
  update PATCH  "/:id" -> TodoUpdate requires idempotency
  delete DELETE "/:id" -> TodoDelete requires idempotency

  member POST "/:id/done" -> TodoDone requires idempotency
}
```

Research:

- should contracts always be named explicitly in v0?
- should conventional names (`TodoIndex`) be rejected/deferred?
- which REST actions belong in v0, and which are overreach?
- should unsupported actions fail at lowering time?
- how do key/idempotency requirements compose with resources?

### 3. nested resources as `scope + resources`, not hidden parent loading

Example pressure:

```igweb
resource accounts "/accounts" {
  show GET "/:account_id" -> AccountShow

  nested "/:account_id" {
    resource todos "/todos" {
      index GET -> AccountTodosIndex
      show  GET "/:todo_id" -> AccountTodoShow
    }
  }
}
```

Research:

- should `nested` exist, or should plain `scope` be enough?
- should nested resources be sugar over explicit `scope`?
- how are parent/child param names chosen without Rails magic?
- can the lowered `.ig` remain flat and boring?

### 4. route composition / `via` as contract pipeline

Example pressure:

```igweb
scope "/accounts/:account_id" via LoadAccount {
  route GET "/todos/:todo_id" -> TodoShow
}
```

Possible meaning:

```text
extract account_id
  -> call_contract("LoadAccount", req, account_id)
  -> on success call_contract("TodoShow", req, account, todo_id)
  -> on failure map to explicit Decision (404/403/500?)
```

Research:

- is `via` a routing feature, or a separate request-pipeline feature?
- what type does the parent contract return?
- where does failure mapping live?
- how are names bound into the child input?
- can this stay static `call_contract`, with no dynamic dispatch?
- should P15 recommend deferring `via` until `scope/resources` are proven?

## Required Analysis

Produce a readiness packet:

`lab-docs/lang/lab-igniter-web-advanced-routing-readiness-p15-v0.md`

It must include:

1. **Current surface summary**: what flat `.igweb` supports today and how it lowers.
2. **Design principles**:
   - transparent lowering;
   - explicit contract names;
   - source-order determinism;
   - generated `.ig` remains inspectable;
   - no server route table;
   - no hidden controller conventions;
   - no effect authority in routing sugar.
3. **Option matrix** for `scope`, `resources`, nested resources, and `via`.
4. **Recommended sequence**: likely P16/P17/P18 cards, ordered by risk.
5. **Concrete syntax proposal** for v0, with at least one Todo example and one nested account/todo example.
6. **Lowering sketch** showing the generated flat route arms and static `call_contract` calls.
7. **Param model**:
   - ordered captures;
   - named params;
   - duplicate names;
   - optional/missing values;
   - Unicode/regexp assumptions.
8. **Idempotency model** for resource/member mutating actions.
9. **404 vs 405 behavior** under scopes/resources/nesting.
10. **Agent/DX evaluation**: which form is easiest for humans and agents to read, generate, and debug.
11. **Risks and anti-magic list**: what Rails-like behavior is intentionally rejected or deferred.
12. **Acceptance tests for the first implementation card** (but do not implement them here).

## Strong Starting Thesis

Pressure-test this thesis; do not accept it blindly:

1. First implementation should be **`scope` only**:
   - prefix + param grouping;
   - lowers to the same flat route list;
   - no resource/controller conventions.
2. Second implementation should be **explicit `resources` sugar**:
   - still names every handler contract;
   - expands to ordinary route lines;
   - no automatic controller naming.
3. Third implementation may add **nested resources** as composition of `scope + resources`.
4. `via` should likely be deferred as a separate request-pipeline / guard-contract design, because it
   introduces failure mapping and typed context, not just path matching.

If you disagree, explain exactly which live constraint makes a different order better.

## Closed Surfaces

- No code changes.
- No parser/lowerer changes.
- No server changes.
- No runner changes.
- No package-manager work.
- No source-map implementation.
- No public bind / live effects / credentials.
- No canon claim.
- No "Rails clone" or hidden controller convention.

## Acceptance

- [x] Verify-first section cites current live files actually read.
- [x] Packet answers all 12 required analysis sections.
- [x] The recommendation preserves `.igweb` as Projection Dialect sugar.
- [x] The recommendation keeps server route-free and domain-free.
- [x] Syntax examples include flat, scoped, resource, nested, and `via` pressure.
- [x] The first implementation card is named and bounded.
- [x] This card is updated with closing report and status `CLOSED`.

## Suggested Next Card Name

If the thesis holds:

`LAB-IGNITER-WEB-ROUTING-SCOPE-P16`

Scope: implement only `scope "/prefix/:param" { route ... }` lowering to flat routes, with tests for
param merge, source order, duplicate-param refusal, 404/405, and no server changes.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-igniter-web-advanced-routing-readiness-p15-v0.md` — readiness/design
packet, no code. All 12 required analysis sections answered; thesis pressure-tested.

**Verify-first done.** Read live `igweb.rs` lowering + its tests, `igniter-web/src/lib.rs` (server
boundary) + `bin/igweb-serve.rs`, the todo_app example, and P0/P4/P12/P14 docs. Three live deltas
corrected the card's framing:

1. **Param names are author-facing only** — `handler_arm` discards the `:name`, handlers bind
   **positionally** via `capture(..., idx+1)`. So scope/resource/via name-merge is about authoring
   clarity + collision detection, not a runtime name→value map.
2. **Duplicate param names are not refused today** — `scope` makes prefix+route `:id` clashes routine,
   so duplicate-name refusal is *new behavior P16 must add*, not a regression.
3. **405-vs-404 is emergent from pattern grouping**, not a routing feature — any sugar that lowers
   same-path actions into one `matches(...)` group inherits correct 405 for free.

**Recommendation (thesis upheld + sharpened):**

- `LAB-IGNITER-WEB-ROUTING-SCOPE-P16` (first; lowest risk; pure prefix typography + duplicate-param
  refusal). **Named and bounded; 10 acceptance tests specified.**
- `LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P17` (closed action table as a **validator, not a generator**;
  explicit contract names; same-path grouping → 405).
- `LAB-IGNITER-WEB-ROUTING-NESTED-P18` (composition of `scope`-wraps-`resource`; **no `nested` keyword** —
  `scope` already nests).
- `LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19` (separate track; `via` is a guard-contract pipeline with
  typed context + failure mapping, not path matching — deferred, with a static `match`-over-`call_contract`
  lowering sketch so the deferral is informed).

**Two refinements vs the strong starting thesis** (both live-grounded): (a) nested resources need **no new
keyword**, so P18 is composition not a primitive; (b) the resource action table should **validate**
method/suffix and never **invent** contract names (consequence of delta #1).

`.igweb` preserved as a Projection Dialect throughout: every advanced form lowers to the **unchanged** flat
`.ig` with **zero new generated node types**; server stays route-free and domain-free. No code, parser,
server, runner, or canon change made.
