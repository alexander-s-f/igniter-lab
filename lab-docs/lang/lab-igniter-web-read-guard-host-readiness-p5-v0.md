# lab-igniter-web-read-guard-host-readiness-p5-v0 — IgWeb read-guard host seam

**Card:** `LAB-IGNITER-WEB-READ-GUARD-HOST-READINESS-P5` · **Delegation:** `OPUS-IGWEB-READ-GUARD-HOST-P5`
**Status:** READINESS / ARCHITECTURE (v0) — designs the missing mid-request **read** seam (a pure guard
can't pause dispatch to do IO). **No code, no `.igweb`/prelude change, no live Postgres, no canon.**
**Authority:** Lab. App owns product meaning + logical query intent; host owns read capability authority +
policy + execution; server owns transport; machine owns the read executor + receipts.

## 1. Executive summary

P4 proved **final writes**: a handler returns `InvokeEffect`, the host executes it. **Reads are different**:
a route needs data *before* the handler can respond, and a pure `via`/`guard` (P20/P26) is a VM-level
`call_contract` that can build a `QueryPlan` *value* but cannot perform IO. The smallest correct shape is a
**generic staged decision** `ReadThen { plan, then }`: the app's Serve returns a query plan plus a
continuation-contract name; the host executes the read under host policy; the host re-enters the named
continuation with the rows; the continuation returns an **ordinary** final `Decision`
(`Respond`/`RespondView`/`InvokeEffect`/`Render`/`RenderView`). This preserves the authority split and
composes with P4 writes plus the P16/P19 render paths. The first impl proof should be a
**direct-dispatch harness** (like P4) — query
contract → fake `PostgresReadExecutor` → continuation — not a new `.igweb` syntax or the full async runner.

## 2. Verify-first (live, file:line)

- **Final-effect host (P4):** `effect_host.rs` `MachineEffectHost::run_invoke_effect` executes an
  *already-returned* `InvokeEffect`; it is final-effect oriented, not a mid-dispatch read. Confirmed.
- **Decision arms (live prelude):** `variant Decision` has `Respond`, `InvokeEffect`, `RespondView`,
  `Render`, and P19's `RenderView`. `igniter-web/src/lib.rs` `map_decision` handles all of them as
  *final* response/effect decisions. **None is staged** — a read seam still needs a NEW staged arm.
- **`via`/`guard` are pure (`igweb.rs`):** `via Guard(args) as name` (P20) and `let`/`guard` context
  bindings (P26) lower to pre-resolved `call_contract` expressions (`Route.guard_calls`, `apply_bindings`).
  They run in the one pure VM dispatch — **no IO**. A `guard` returning `Result[QueryPlan, Decision]` makes
  a plan value, not rows.
- **`QueryPlan` + fake read executor:** structural JSON (`source/op/projection/filters/limit`, raw SQL
  refused); `FakePostgresAdapter` + `PostgresReadExecutor` gate by allowlist + clamp without a live DB
  (P3 bridge); P10 added typed decode. Confirmed.
- **Runner boundary (P4 §5):** `IgWebServerApp::call` does an internal `block_on`; the staged read needs
  the host to **re-enter** the app (call the continuation = another `block_on` dispatch), so the full async
  socket runner is blocked on the *same* boundary. Not solved here.

## 3. Central design — never collapse reads into a final effect

```text
WRITE (P4): route → final InvokeEffect → host executes → response/receipt
READ  (P5): route → ReadThen{plan, then} → host executes read → rows → continuation(then) → final Decision
```

The read shape needs a **staged decision naming a continuation** — not a final effect (which can't feed
rows back), not a host-magic `via` (which would give a pure guard hidden IO authority).

## 4. Alternatives (Q1) — recommend **B, a generic `ReadThen`**

| Option | Verdict |
|---|---|
| **A. `ReadThenRespond` / `ReadThenInvoke`** (kind-specific staged decisions) | works, but proliferates one arm per final kind |
| **B. generic `ReadThen { plan, then }`** — one staged primitive; the continuation returns ANY final `Decision` | **v0** — one arm, composes with Respond/RespondView/InvokeEffect/Render/RenderView uniformly (Q6) |
| **C. host-backed `via`** (`via LoadTodo` auto-reads) | **reject** — gives a *pure* guard hidden IO authority; breaks the P20 invariant that `via` is a static `call_contract` |
| **D. final `InvokeEffect` for reads** | **reject** — a final effect can't feed rows into a continuation (the card's core pressure) |
| **E. pre-dispatch middleware** | **reject** — too coarse; no route params / handler context |

B subsumes A and keeps `via`/`guard` pure.

## 5. What `.ig`/`.igweb` authors (Q2)

- **Query intent:** the proven query contract `ListTodosByAccount(account_id) -> QueryPlan` /
  `FindTodo(account_id, todo_id) -> QueryPlan` (P2/P3) — structural, no SQL.
- **Future staged syntax** (a later card, not v0): `read LoadTodos(account_id) as rows -> AccountTodoIndex`
  lowering the Serve arm to `ReadThen { plan: <built by LoadTodos>, then: "AccountTodoIndex" }`.
- **v0 impl needs NO new syntax** — the harness (Q9) calls the query contract and the continuation directly
  (mirrors P4's direct-dispatch proof). No hidden DB handle, SQL, DSN, or capability identity in `.ig(web)`.

## 6. Rows / context representation (Q3) — honest

VM/type constraints (records infer to `Unknown`; typed row destructuring unsolved — the relational
fixtures pass rows as JSON, P2/P3/P10). So v0:
- the host runs the plan and gets `rows : Collection[Value]` (JSON, P10-typed);
- the continuation receives them as a **JSON string** input (`input rows_json : String`) — enough to branch
  **found vs not-found** (empty array) and echo/shape a response;
- **typed row records into `.ig` inputs are deferred** (needs the typed-row language work). v0 proves the
  *seam*, not row destructuring.

## 7. Authority split (Q4)

**Host-owned:** the read source/field allowlist + value kinds (`PostgresReadPolicy` / `allow_source_typed`,
P10), the capability passport, the row-limit clamp, the fake-vs-real adapter choice, and the logical
read-target → machine route binding. **App-owned:** product meaning, the logical query (the `QueryPlan` it
builds), and the not-found/fallback `Decision` in the continuation. `.igweb`/`.ig` name **no** capability
id, scope, DSN, raw SQL, or pool.

## 8. Composition with P4 writes (Q5) and P16 render (Q6)

- **Read-then-write:** a `ReadThen` whose continuation returns `InvokeEffect` chains straight into P4 (the
  host runs the continuation's effect). e.g. `POST …/done`: read the todo context → continuation returns
  `InvokeEffect todo-done` → P4 executes + receipts. v0 proves **read → Respond**; read-then-write is the
  natural next composition (model it in TodoApp API, not P6).
- **Render:** because the continuation returns *any* final `Decision`, it can return `Respond`,
  `RespondView`, `InvokeEffect`, `Render`, or `RenderView` — the existing `map_decision` handles all five
  (incl. `Render`/`RenderView` → HTML). The generic `ReadThen` (B) is what makes this uniform; a JSON-only read seam is
  rejected.

## 9. Error mapping (Q7)

Distinguish **infra failure** (host-owned) from **data absence** (app-owned):
- **Succeeded(rows)** → run the continuation with the rows.
- **Denied** (policy / unknown source / forbidden field / raw SQL) → **host-mapped error** (4xx/5xx),
  machine internals redacted (no SQL/DSN/row leak) — the app does not see capability details.
- **PermanentFailure** (malformed plan / query error) → host 5xx.
- **Retryable / UnknownExternalState** (adapter down) → host 503-style / unknown (no false success).
- **Not-found** (a legitimate empty result) is **NOT** an error — the continuation receives empty rows and
  returns the **app-owned** `Decision` (e.g. 404). This keeps not-found as app product meaning, infra
  failure as host responsibility, tied to the existing `OutcomeKind` taxonomy without exposing it to `.ig`.

## 10. Runner / productization boundary (Q8) — explicit

The staged read makes the boundary *worse* than P4: the host must re-enter the app (call the continuation),
which is another `IgWebServerApp::call` `block_on`. So v0 must be a **direct-dispatch harness** (compute
decisions off-runtime, execute the read async), **not** the full async socket runner. Resolving
`IgWebServerApp::call`'s sync `block_on` (async dispatch or `spawn_blocking`) + a two-phase staged
dispatcher is **runner productization**, deferred to `…-EFFECT-HOST-RUNNER-P*`. Not hidden.

## 11. Smallest next implementation proof (Q9)

**`LAB-IGNITER-WEB-READ-GUARD-HOST-P6`** — a `machine`-gated **direct-dispatch harness** (no new `.igweb`
syntax, no prelude/VM change), mirroring P4:
- author (in the Todo app `.ig`) a query contract `ListTodosByAccount(account_id) -> QueryPlan` and a
  continuation `AccountTodoIndex(req, rows_json : String) -> Decision`;
- harness: call the query contract → `QueryPlan` → serialize → run through the **fake**
  `PostgresReadExecutor` under a host `PostgresReadPolicy` (allowlist + clamp) → rows → call the
  continuation with `rows_json` → final `Respond`.

**Acceptance tests for P6:**
1. found rows → continuation returns `200` carrying (a shape derived from) the rows;
2. **not-found** (fake source empty) → continuation returns the **app-owned 404**;
3. **denied source** (not allowlisted) → read **denied before the adapter** (`query_count==0`);
4. forbidden projection field → denied before the adapter;
5. row-limit clamp applied (effective_limit ≤ policy cap);
6. raw-SQL key in the plan → permanent-fail before the adapter;
7. no capability id / scope / DSN / SQL in the authored `.ig`;
8. default (no-machine) build unchanged; no live DB / `IGNITER_PG_DSN`;
9. honest note: direct-dispatch harness, not the full async socket loop (P4 §5 boundary).

## 12. Rejected for v0 (Q10) / rejected shortcuts

raw SQL · live Postgres · ORM / schema inference · **automatic DB reads from arbitrary `via`** (via stays a
pure static `call_contract`) · server route table · `[effects]`/DB authority in the app manifest ·
capability identity in `.igweb`/`.ig` · streaming / async jobs · public listener / product CLI · **typed
row destructuring into `.ig` inputs** (deferred; v0 rows = JSON string) · **full async runner** (the P4
`block_on` boundary, deferred) · collapsing reads into a final `InvokeEffect` (the central anti-pattern).

## Next card

`LAB-IGNITER-WEB-READ-GUARD-HOST-P6` (above). Downstream: `LAB-TODOAPP-API-READ-P*` (Todo read route through
fake → local Postgres), then the staged `read …` `.igweb` syntax + `ReadThen` prelude arm, and
`…-EFFECT-HOST-RUNNER-P*` (productize the runner; resolve the sync/async boundary for both writes and the
two-phase staged read).

---

*Readiness/architecture only. Compiled 2026-06-20; grounded in live `effect_host.rs` (P4 final-effect host),
`igweb.rs` prelude `Decision` + pure `via`/`let`/`guard`, `lib.rs` `map_decision` (Respond/RespondView/
InvokeEffect/Render/RenderView), the fake `PostgresReadExecutor` (P3/P10). No code, prelude, server, or DB
change.*
