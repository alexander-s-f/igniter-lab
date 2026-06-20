# LAB-IGNITER-WEB-READ-GUARD-HOST-READINESS-P5 - IgWeb read guard host seam

Status: CLOSED
Lane: standard
Type: readiness / architecture
Delegation code: OPUS-IGWEB-READ-GUARD-HOST-P5
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4` proved final write execution:

```text
IgWeb handler returns final InvokeEffect
  -> igniter-web maps it to ServerDecision::InvokeEffect
  -> MachineEffectHost executes through machine ingress
  -> fake write executor commits + receipt
```

Reads are a different problem. A route-level `via` guard or context binding needs data **before** the final
handler can respond or invoke a write. A pure `.ig` guard can build a `QueryPlan` value, but it cannot pause
VM dispatch, perform IO, then resume the route with rows/context.

P5 is the readiness/design slice for that missing host seam. It must decide the smallest honest shape for:

```text
IgWeb route/guard expresses read intent
  -> host executes read capability under host-owned authority
  -> rows/context are fed into an authored handler
  -> final Respond / Render / InvokeEffect remains ordinary
```

This is not a live Postgres slice. It should use fake read semantics and the already proven Postgres read
boundary where useful.

## Goal

Produce a grounded readiness packet that designs the first IgWeb read-guard host seam and names the next
implementation card.

The packet must answer:

- what new decision/protocol shape is needed, if any;
- whether reads should be modeled as route `via`, app/scope `guard`, or a staged host decision;
- how `QueryPlan`/relational contracts map to the existing fake `PostgresReadExecutor`;
- how read rows become handler context without giving `.igweb` or `.ig` capability authority;
- how the seam composes with P4 final writes, P16 render, and TodoApp API shape.

## Verify First

Read live code/docs before writing the packet:

- `lab-docs/lang/lab-igniter-web-effect-host-readiness-p3-v0.md`
- `lab-docs/lang/lab-igniter-web-effect-host-write-p4-v0.md`
- `server/igniter-server/src/effect_host.rs`
- `server/igniter-server/tests/effect_machine_tests.rs`
- `server/igniter-web/src/lib.rs`
  - `map_decision`
  - `IgWebServerApp::call`
  - `runner`
- `server/igniter-web/examples/todo_postgres_app/`
- `server/igniter-web/tests/todo_postgres_app_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `lang/igniter-compiler/src/igweb.rs`
  - `via`
  - context composition (`let`/`guard`) if present
  - current prelude `Decision`
- `lab-docs/lang/lab-igniter-web-routing-via-readiness-p19-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md`
- `lab-docs/lang/lab-igniter-web-context-composition-readiness-p25-v0.md`
- `lab-docs/lang/lab-igniter-web-context-composition-p26-v0.md`
- `lab-docs/lang/lab-igniter-relational-contracts-readiness-p1-v0.md`
- `lab-docs/lang/lab-igniter-relational-queryplan-bridge-p3-v0.md`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs`

Confirm or correct:

- `MachineEffectHost` is final-effect oriented; it executes an already-returned `InvokeEffect`.
- `via` and `guard` are pure VM-level constructs; they cannot perform IO.
- `QueryPlan` is structural JSON (`source`, `op`, `projection`, `filters`, `limit`), raw SQL rejected.
- fake read executor exists and can prove host gating without live DB.
- P4 found a sync/async boundary: `IgWebServerApp::call` uses internal `block_on`, so full async runner
  productization is not solved here.

## Central Design Pressure

Do **not** collapse reads into final `InvokeEffect`.

Write:

```text
route -> final InvokeEffect -> host executes -> response/receipt
```

Read guard:

```text
route -> read intent -> host executes -> enriched context -> authored handler -> final decision
```

The second shape requires either:

- a staged decision from `.ig`/IgWeb (`ReadThenRespond`, `ReadThenInvoke`, `ReadThenRender`, or more generic);
- an app-host callback API that can re-enter a handler with read rows;
- a host-provided guard primitive;
- or an explicit decision that names a continuation contract.

This packet must choose the smallest v0 path and reject tempting but unsafe shortcuts.

## Questions To Answer

### Q1. What is the minimal read seam?

Compare at least:

- **A. `ReadThenRespond/ReadThenInvoke` decision** — route returns query plan plus continuation contract.
- **B. `ReadThen { query, then_contract, mode }` generic staged decision** — one primitive, several final kinds.
- **C. host-backed `via`** — `via LoadTodo` becomes a host read automatically.
- **D. final `InvokeEffect` used for reads** — likely wrong because it cannot feed rows into handler.
- **E. pre-dispatch middleware** — likely too coarse; lacks route params and handler context.

Recommend one v0 and explain why.

### Q2. What does `.ig` author?

Options:

- query contract returns a `QueryPlan`;
- guard contract returns `Result[QueryPlan, Decision]`;
- route syntax carries `read LoadTodo(...) as todo -> Handler`;
- context-composition `guard` lowers to staged read.

Keep authoring explicit and inspectable. No hidden DB handle, no SQL, no DSN, no capability identity.

### Q3. How are rows/context represented?

Decide whether v0 returns:

- raw `Collection[RecordJson]`;
- a single row / not-found decision;
- a typed context record built by a follow-up handler;
- or JSON `Value` passed as a string.

Be honest about current VM/type constraints. Prefer the smallest form that can be compiled and tested.

### Q4. Where does authority live?

Specify host-owned:

- target/read-binding or source allowlist;
- capability passport;
- `PostgresReadPolicy`;
- row limit clamp;
- fake vs real adapter choice.

Specify app-owned:

- product meaning;
- logical query name or source intent;
- fallback/not-found behavior if appropriate.

### Q5. How does this compose with P4 writes?

Example target flow:

```text
POST /accounts/:account_id/todos/:todo_id/done
  -> read account/todo context
  -> if found and authorized, final InvokeEffect todo-done
  -> P4 write host executes and receipts
```

Decide whether P5 needs to model this now or defer to TodoApp API.

### Q6. How does this compose with P16 Render?

Can the continuation produce `Respond`, `RespondView`, `Render`, or `InvokeEffect` uniformly?

Avoid a read seam that only works for JSON responses and cannot later render HTML.

### Q7. How are errors mapped?

At minimum:

- policy denied / unknown source / raw SQL -> app-visible error or server 500?
- not found -> app-owned `Decision`?
- read unavailable -> retryable/unknown external state?
- malformed query plan -> permanent failure?

Tie this to existing `EffectOutcome`/`OutcomeKind` taxonomy where appropriate, without exposing machine internals to app code.

### Q8. What is the runner/productization boundary?

P4 proved direct host execution, not full socket-loop productization due `block_on` nesting.

Decide whether the read seam readiness should depend on:

- solving async `IgWebServerApp::call`;
- a proof-only direct dispatch harness;
- or a staged runner card first.

Do not hide the runtime boundary.

### Q9. What is the smallest implementation proof after this packet?

Name the next card and define its tests. Likely shape:

`LAB-IGNITER-WEB-READ-GUARD-HOST-P6`

Possible proof:

- one authored Todo route;
- query intent maps to fake `PostgresReadExecutor`;
- found row feeds continuation;
- not found returns authored 404;
- denied source fails before adapter;
- no live DB;
- no final write yet, unless tiny.

### Q10. What is explicitly rejected for v0?

Include:

- raw SQL;
- live Postgres;
- ORM/schema inference;
- automatic DB reads from arbitrary `via`;
- server route table;
- `[effects]` or DB authority in app manifest;
- capability identity in `.igweb`/`.ig`;
- streaming or async jobs;
- public listener/product CLI.

## Expected Recommendation Bias

The likely winning direction is a **staged read decision with explicit continuation**, because it preserves
the core authority split:

```text
.ig/.igweb produces data: QueryPlan + continuation name + app fallback semantics
host executes read capability under host policy
host re-enters/continues with rows/context
final app decision remains ordinary
```

But Opus must verify this against live compiler/VM constraints and may choose a different shape if it is
smaller and safer.

## Closed Scope

- No code changes.
- No `.igweb` grammar changes.
- No `igniter-server` or `igniter-web` implementation changes.
- No live Postgres, DSN, DDL, migrations, pooling, TLS, or schema setup.
- No raw SQL.
- No TodoApp implementation.
- No runner productization.
- No async runtime fix.
- No source-map/diagnostics implementation.
- No canon/stable API claim.

## Required Deliverables

- readiness packet:
  - `lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md`
- closing report in this card;
- exact recommended next implementation card with acceptance tests;
- explicit list of rejected shortcuts.

## Acceptance

- [x] Live `MachineEffectHost`/P4 write proof read and correctly characterized.
- [x] Live IgWeb `via`/context composition constraints read and correctly characterized.
- [x] Live relational `QueryPlan`/fake read executor read and correctly characterized.
- [x] Final writes and mid-request reads are kept separate.
- [x] At least five design alternatives compared.
- [x] Recommended v0 seam is explicit.
- [x] Authority split is explicit.
- [x] Error mapping is explicit.
- [x] Runner sync/async boundary is explicitly acknowledged.
- [x] Next implementation card is named with concrete tests.
- [x] No code changed.

---

## Closing Report (2026-06-20)

**Deliverable:** `lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md` — readiness packet, **no
code** (`git diff` clean). Answers Q1–Q10; ≥5 alternatives compared.

**Verify-first (live):** the prelude `Decision` has only final arms (`Respond`/`InvokeEffect`/`RespondView`/
`Render`/`RenderView`) — **none is staged**; `via`/`let`/`guard` (P20/P26) lower to pure `call_contract`
(no IO); `MachineEffectHost` executes an *already-returned* final effect; the fake `PostgresReadExecutor`
gates without a live DB. Note: `RenderView` is the P19 addition and does not change the read-seam conclusion.

**Recommendation (Q1=B):** a **generic staged `ReadThen { plan, then }` decision** — the app's Serve returns
a query plan + continuation-contract name; the host executes the read under host policy; re-enters the named
continuation with rows; the continuation returns an **ordinary** final `Decision` (uniform across
Respond/RespondView/InvokeEffect/Render/RenderView, so it composes with P4 writes and P16/P19 render).
Rejected: host-magic `via` (hidden IO authority), final-`InvokeEffect`-for-reads (can't feed rows),
pre-dispatch middleware (too coarse).

**Honest constraints surfaced:** rows reach the continuation as a **JSON string** in v0 (typed row
destructuring deferred); not-found = empty rows → app-owned 404 vs infra failure → host-mapped error; the
**same `block_on` boundary as P4** is *worse* here (the host must re-enter the app for the continuation), so
v0 must be a **direct-dispatch harness**, not the full async runner.

**Next card:** `LAB-IGNITER-WEB-READ-GUARD-HOST-P6` — a machine-gated direct-dispatch harness (no new
`.igweb`/prelude change): query contract → fake `PostgresReadExecutor` (policy-gated) → continuation, with 9
acceptance tests (found→200, not-found→app-404, denied source/field before adapter, clamp, raw-SQL refusal,
no identity in `.ig`, default build unchanged, no live DB). Downstream: `LAB-TODOAPP-API-READ-P*`, the staged
`read …` syntax + `ReadThen` arm, `…-EFFECT-HOST-RUNNER-P*`.

## Suggested Verification Commands

Read-only commands only, unless the card is explicitly amended:

```bash
rg -n "ReadThen|InvokeEffect|RespondView|Render|via|guard" lang/igniter-compiler/src/igweb.rs server/igniter-web/src/lib.rs
rg -n "QueryPlan|PostgresRead|FakePostgres" runtime/igniter-machine/src runtime/igniter-machine/tests
rg -n "MachineEffectHost|run_invoke_effect|serve_loop_effect" server/igniter-server/src server/igniter-server/tests
git diff --check
```

If any command reveals that a claimed primitive does not exist, correct the packet rather than preserving
the card's wording.

## Next

Expected next card after this readiness:

- `LAB-IGNITER-WEB-READ-GUARD-HOST-P6` — fake read guard proof.

Downstream:

- `LAB-TODOAPP-API-READ-P*` — Todo API read route through fake/local Postgres.
- `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*` — productize machine-enabled runner and resolve sync/async
  boundary.
