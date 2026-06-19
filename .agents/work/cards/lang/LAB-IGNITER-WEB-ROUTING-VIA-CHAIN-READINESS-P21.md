# LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-READINESS-P21 - multi-via chain design

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab readiness
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-VIA-CHAIN-P21

## Intent

Design the next safe `via` step for IgWeb after P20: **multiple route-level
`via` guards**, evaluated left-to-right, with short-circuit behavior and clear
handler argument ordering.

This is a readiness/design card, not an implementation card. Produce one
packet that answers the questions below, grounded in live compiler/lowering
facts, and close this card with the recommended implementation slice.

The design must preserve the established IgWeb rule:

```text
.igweb projection dialect -> deterministic, inspectable generated .ig -> real compiler/typechecker
```

No server routing table, no dynamic dispatch, no effect/capability identity in
`.igweb`, and no canon claim.

## Why This Needs Readiness First

P20 proved one route-level guard:

```igweb
route GET "/accounts/:account_id/todos/:todo_id"
  via LoadAccount(account_id) as account
  -> AccountTodoShow
```

Lowering uses the built-in sealed `Result`:

```ig
match call_contract("LoadAccount", req, capture(..., 1)) {
  Ok { value } => call_contract("AccountTodoShow", req, value, capture(..., 2))
  Err { error } => error
}
```

Live compiler facts from P20:

1. `Result[T,E]` is matchable as `Ok { value }` / `Err { error }`.
2. `Result` is constructed by lowercase `ok(..)` / `err(..)`, not by
   `Ok { value: ... }` record literals.
3. `match` arms are single expressions.
4. `via as <name>` is currently author-facing only; generated `.ig` binds the
   success payload as `value`.
5. A naive nested chain shadows `value` in inner `Ok` arms.

So multi-`via` is not just “repeat P20”. It needs a deliberate lowering and
handler argument model.

## Authority

Lab readiness only.

This card may create:

- one readiness packet under `lab-docs/lang/`;
- this card's closing report.

This card must not change:

- `lang/igniter-compiler/src/igweb.rs`;
- compiler/typechecker/VM semantics;
- `server/igniter-web` or `server/igniter-server`;
- `.igweb` syntax implementation;
- examples/fixtures except if used only as quoted snippets in the packet.

If live code contradicts this card, live code wins and the packet must say so.

## Verify First

Read these current surfaces before writing the packet:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `lang/igniter-compiler/tests/fixtures/igweb_via/handlers.ig`
- `lab-docs/lang/lab-igniter-web-routing-via-p20-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-via-readiness-p19-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `server/igniter-web/README.md`
- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-server/src/protocol.rs`

Also grep live compiler sources for the relevant `Result` and `match` support
if needed. Do not rely on old sketch text when the compiler disagrees.

## Questions To Answer

### Q1. Should P21 implement multi-`via`, or first introduce a composite-context convention?

Compare:

A. Syntax-level chain:

```igweb
route GET "/accounts/:account_id/projects/:project_id/todos/:todo_id"
  via LoadAccount(account_id) as account
  via LoadProject(account, project_id) as project
  -> ProjectTodoShow
```

B. Composite guard:

```igweb
route GET "/accounts/:account_id/projects/:project_id/todos/:todo_id"
  via LoadProjectTodoContext(account_id, project_id) as ctx
  -> ProjectTodoShow
```

Decide whether syntax-level chaining is worth opening now, or whether the next
implementation should first document/fixture the composite guard pattern.

### Q2. If syntax-level chain is accepted, what is the exact grammar?

Candidate v0:

```igweb
route METHOD "pattern"
  via GuardA(arg, ...) as a
  via GuardB(a, arg, ...) as b
  -> Handler
```

Answer:

- Can later guards consume earlier guard contexts by `as` name?
- Can later guards consume both contexts and remaining path params?
- Are zero-arg guards allowed?
- Is `via` still route-level only?
- Does `via` remain forbidden after `->`?
- Are duplicate `as` names rejected?

### Q3. What should handler argument ordering be?

P20 order is:

```text
req, guard_context, unconsumed_path_captures_in_path_order
```

For multiple guards, choose and justify one order. Candidate:

```text
req, ctx_a, ctx_b, ..., unconsumed_path_captures_in_path_order
```

Make sure the rule stays readable for agents and humans and does not depend on
hidden type inference.

### Q4. What does “consumed” mean in a chain?

P20 consumes path params passed to the guard. For chains, define whether these
are consumed:

- path params passed to any guard;
- prior guard contexts passed to later guards;
- prior guard contexts not passed to later guards;
- captures used only in a failed guard path.

Be explicit about which values reach the final handler.

### Q5. What lowering avoids the `Ok { value }` shadowing problem?

Evaluate at least three strategies:

A. Nested matches with generated local names, if `.ig` supports renaming or
   intermediate compute bindings.
B. Nested matches using fixed `value`, relying on scope shadowing but arranging
   handler expression carefully.
C. Composite-context guard only (no syntax-level chain in P21).
D. Introduce generated helper contracts or wrapper records in generated `.ig`.

Do not assume `.ig` supports a construct until verified.

### Q6. Can generated `.ig` bind intermediate contexts outside nested match arms?

Verify whether generated `.ig` can express something like:

```ig
compute account_result = call_contract("LoadAccount", req, ...)
compute project_result = ...
```

and then branch/match safely. If not, say so. If yes, describe exact generated
shape and how errors short-circuit.

### Q7. What is the failure model?

The likely rule is left-to-right short-circuit:

- first `Err { error }` returns `error` unchanged;
- later guards and handler are not evaluated;
- generated `.ig` makes that structure visible.

Confirm whether this is the right v0 rule. Do not invent status-code mapping.
Guard-owned failure mapping remains the P20 policy.

### Q8. How does idempotency compose?

For mutating routes:

```igweb
route POST "/accounts/:account_id/todos"
  via LoadAccount(account_id) as account
  via CheckWritePolicy(account) as policy
  -> AccountTodoCreate requires idempotency
```

The existing keyless 400 should probably stay **outermost**, before all guards.
Confirm and show the expected generated shape.

### Q9. How does chain compose with scope/resource/nested?

P20 proved single `via` through scoped resource actions. Define whether chain
should be allowed in:

- plain route;
- route inside `scope`;
- resource action;
- nested scope + resource action.

If all are allowed, state that lowering must still pass through the existing
flattened route path and preserve 404/405 grouping.

### Q10. What should be rejected in P21?

List exact line-positioned `IgwebError` cases. Include at minimum:

- duplicate `as` names;
- unknown guard arg name;
- guard references a later `as` name;
- route param and context name collision, if rejected;
- `via` after `->`;
- `via` on scope/resource headers, if still closed;
- empty/bad names;
- ambiguous consumption behavior.

### Q11. What acceptance tests should the implementation card require?

Write a concrete test matrix for a future implementation card, including:

- exact lowering snippet(s);
- left-to-right short-circuit shape;
- handler receives contexts then remaining captures;
- context consumed by later guard but still optionally passed to handler, if
  that is the chosen rule;
- idempotency outermost;
- resource/scope composition;
- duplicate/unknown/bad-shape errors;
- real multifile compiler proof;
- non-`Result` guard still fails normal compiler/typechecker;
- server/runner unchanged.

### Q12. What is the recommended next card?

Choose one:

- `LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-P22` — implementation of syntax-level
  multi-`via`;
- `LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22` — document/prove composite
  guard pattern first;
- `LAB-IGNITER-WEB-ROUTING-VIA-SCOPE-READINESS-P22` — scope-level inheritance
  first;
- another clearly bounded card.

Explain why.

## Required Deliverable

Create:

```text
lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md
```

The packet must include:

1. executive summary;
2. verify-first facts from live code;
3. explicit recommendation;
4. rejected alternatives;
5. proposed grammar, if any;
6. proposed lowering shape, with generated `.ig` sketch;
7. handler argument and consumption rules;
8. failure/idempotency/resource-scope composition rules;
9. implementation acceptance test matrix;
10. next-card recommendation.

Then update this card with a compact closing report and mark `Status: CLOSED`.

## Acceptance

- [x] Readiness packet exists at the required path.
- [x] Packet is grounded in P20 live facts: `Ok { value }`, `Err { error }`,
      lowercase `ok(..)`/`err(..)`, and P20 single-`via` lowering.
- [x] Packet answers Q1-Q12 explicitly.
- [x] Packet does not claim implementation or canon authority.
- [x] Packet preserves Projection Dialect boundary.
- [x] Packet does not require server/runner changes for route-level chain.
- [x] Packet explains the `value` shadowing hazard and a concrete mitigation.
- [x] Packet includes an implementation test matrix suitable for Opus/Codex.
- [x] No code, fixtures, compiler, server, runner, or docs outside the packet
      and this card are changed.
- [x] Closing report states the recommended next card.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md` — readiness packet,
**no code** (`git diff` clean; only the packet + this card are new). Answers Q1–Q12.

**Decisive verify-first facts (live code):**
- `match` arm body is a single expression and pattern bindings are bare field names with **no rename**
  (`parser.rs:110-120`). Combined with `Result`'s fixed `value` field, **nesting guards shadows the outer
  context** → a syntax-level chain over built-in `Result` is **structurally impossible** for a handler
  needing ≥2 contexts.
- **Records construct as bare `{ field: value }` literals** (type from annotation), NOT `TypeName {…}` —
  this is why P20's `Account {…}` failed; `lead_router/pipeline.ig:104`.
- **`lead_router` is already a live multi-step guard chain** (`variant Pipe { Proceed{ctx}, Reject{…} }`
  threading an accumulating `Ctx`), proving the composite/threaded-context pattern compiles today.

**Recommendation:** do the **composite-context guard FIRST** (one P20 `via` + a guard that internally chains
and returns one context record) — zero `.igweb` change, maximal transparency, covers the real multi-load
needs. Syntax-level `via A … via B …` is **fully designed** in the packet (§5) but **deferred**: it's only
expressible via bespoke per-guard variants with distinct success-field = `as` name (`Loaded { account } /
Reject { decision }`), a convention shift away from the built-in `Result` P20 proved — real cost, marginal
gain.

**Next card:** `LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22` (document + fixture-prove the composite-guard
pattern over the unchanged P20 lowering). Open the syntax-chain card (`…-VIA-CHAIN-P23`, §5) only if
composite guards prove too clunky; scope-level `via` inheritance stays a separate later track.

## Closed Surfaces

Do not implement multi-`via` in this card. Do not change parser/lowering. Do not
change compiler/typechecker/VM. Do not add source-map. Do not change
`igniter-web`, `igniter-server`, runner, examples, package manager, dialect
registry, SparkCRM, DB, live network, or canon docs.

## Notes For The Agent

This is a design pressure point. Prefer a smaller honest next step over a clever
syntax that makes generated `.ig` hard to inspect. IgWeb should stay transparent
for humans and agents: sugar is allowed only when the lowered shape remains
obvious.
