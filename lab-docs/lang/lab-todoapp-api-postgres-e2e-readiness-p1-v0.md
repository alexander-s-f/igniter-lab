# lab-todoapp-api-postgres-e2e-readiness-p1-v0 — real Todo API over IgWeb + Postgres

**Card:** `LAB-TODOAPP-API-POSTGRES-E2E-READINESS-P1` · **Delegation:** `OPUS-TODOAPP-API-POSTGRES-E2E-P1`
**Status:** READINESS / DESIGN (v0) — turns the proven web + relational + Postgres pieces into a bounded
plan for a real local Todo API. **No code, no DB/DDL, no dependencies, no examples changed, no canon.**
**Authority:** Lab readiness. The future TodoApp owns app/domain meaning; `igniter-server` owns only
transport/process/middleware; `igniter-machine` owns capability execution/receipts/idempotency/reconcile;
Postgres schema is operator-owned outside Igniter.

---

## 1. Executive summary

Every **authoring + lowering + intent** layer for a real Todo API already exists and is proven: the
`igweb-serve` runner, the full routing stack (`scope`/`resource`/nested/route-level `via`/composite guards,
exercised live by `todo_v2_app`), the pure relational contract shape (`QueryPlan`/`WriteIntent` records),
the bridge from a `QueryPlan` to the fake read executor, **typed reads (P10, now done)**, the
`PostgresWriteExecutor` + `run_write_effect` receipts + read-only reconcile, and **`let`/`guard` context
composition (P26, now done)**. The one missing piece is **host-side effect EXECUTION for the web path**:
`igweb-serve` today *observes* `InvokeEffect` (maps it to `ServerDecision::InvokeEffect`, a `202`) and
never runs it, and a `via` guard is a *pure* `call_contract` that cannot itself perform Postgres IO. So a
single request cannot yet read/write a real database. The recommended first card is therefore the **app
shape with observed effects (no DB)**, then a **new IgWeb effect-host seam** (precedent:
`igniter-machine` `frame_binding` P17/P18) before real read/write wiring.

## 2. Verify-first facts (live; supersedes the card's precondition list)

- `server/igniter-web/examples/todo_v2_app/{igweb.toml,routes.igweb,todo_handlers.ig}` — **already** the
  full proven surface: `scope "/accounts/:account_id" { resource todos { index/show/create/done … via
  Load…(…) as ctx … requires idempotency } }`, lowering to a pure `Serve(Request) -> Decision`.
- `server/igniter-web/src/lib.rs:171` — `InvokeEffect` is **observed** (`ServerDecision::InvokeEffect`), not
  executed; `bin/igweb-serve.rs:7` "no live effect execution"; the manifest **rejects** `[effects]`
  (`lib.rs:390`). So the runner has **no effect authority** and runs no capability IO.
- `runtime/igniter-machine/src/postgres_read.rs` — `PostgresReadExecutor : CapabilityExecutor`,
  `QueryPlan{source,op,projection,filters:[{field,op,value}],limit}`, allowlist gates + clamp + raw-SQL
  refusal; **P10** added `PostgresReadValueKind` typed decode (`allow_source_typed`).
- `runtime/igniter-machine/src/postgres_write.rs` — `PostgresWriteExecutor : CapabilityExecutor`,
  `PostgresWriteIntent{operation,target,key,values,correlation_id}`, `run_write_effect` two-phase receipt,
  `PostgresWritePolicy{target,key,columns}`, `reconcile_postgres_unknown_write` (read-only).
- `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig` — pure `QueryPlan`/`WriteIntent`
  contracts compile (P2); `relational_queryplan_bridge_tests.rs` — the shape reaches the fake executor (P3).
- **Delta vs the card:** both listed "Open" prerequisites are now **CLOSED** — `LAB-MACHINE-POSTGRES-TYPED-READ-P10`
  (typed reads) and `LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26` (`let`/`guard`). So the plan is *less* blocked
  than the card assumed; the real remaining blocker is the **effect-host seam**, not P10/P26.

## 3. App boundary (Q1)

A new example: `server/igniter-web/examples/todo_postgres_app/` (alongside `todo_app`/`todo_v2_app`).

**App-authored:** `igweb.toml` (manifest: entry, sources, `[server] loopback`, `[middleware] trace`);
`routes.igweb` (routes + guards); `.ig` types + handlers + relational `QueryPlan`/`WriteIntent` contracts.
**Host-owned (NOT in `.igweb`/`.ig`, NOT app DX):** the read/write **policy** (source/field/kind + target/
key/columns allowlists), the **effect-target → capability** map, DSN env names, secret provider — these
live in host config / the lab harness. **Not app-authored Rust:** the runner is generic; the app writes
zero Rust. Optional: a SQL DDL **fixture snippet** (doc/test header only), never a migration runner.

## 4. Schema ownership + suggested DDL shape (Q2)

Minimal local schema (operator-owned, **outside** Igniter; shown for the lab, not applied here):

```sql
CREATE TABLE accounts ( id text PRIMARY KEY, name text );
CREATE TABLE todos (
  id text PRIMARY KEY, account_id text NOT NULL, title text, done boolean,
  inserted_at timestamptz DEFAULT now()
);
CREATE TABLE effect_receipts (              -- required by machine writes (P3/P8)
  idempotency_key text PRIMARY KEY, correlation_id text, target text, business_key text
);
```

- **Migrations: operator-owned**, out of scope; DDL lives as a fixture snippet (like the P10
  `igniter_typed_read` header), not a runner.
- **Schema names are HOST POLICY names** (`allow_source_typed("todos", &[("id",Text),("done",Boolean),
  ("inserted_at",Timestamp), …])` + `PostgresWritePolicy{target:"todos",key:"id",columns:[…]}`); the `.ig`
  `type Todo` is an **advisory mirror**, not authority.
- **Test setup** uses a dedicated throwaway local DB via `IGNITER_PG_DSN` (a separate `IGNITER_PG_WRITE_DSN`
  for writes), **never** SparkCRM/dev business DBs; tests skip cleanly when env is unset.

## 5. Routes (Q3)

The first surface = **exactly `todo_v2_app`'s proven shape, no new syntax**:

```igweb
app TodoPgWeb entry Serve {
  handlers TodoPgHandlers
  route GET "/health" -> Health
  scope "/accounts/:account_id" {
    resource todos "/todos" {
      index  GET                    via LoadAccountTodos(account_id) as ctx           -> AccountTodoIndex
      show   GET    "/:todo_id"      via LoadTodoContext(account_id, todo_id) as ctx   -> AccountTodoShow
      create POST                   via LoadAccountTodos(account_id) as ctx           -> AccountTodoCreate requires idempotency
      member POST   "/:todo_id/done" via LoadTodoContext(account_id, todo_id) as ctx  -> AccountTodoDone requires idempotency
    }
  }
}
```

`requires idempotency` on mutating routes (keyless → 400). **P26 (`let`/`guard`) is available but NOT
required** for v0 — single route-level `via` + a composite-context guard already covers it (the
`todo_v2_app` precedent). Use `let`/`guard` later only if multi-context ergonomics demand it.

## 6. Read flow (Q4)

Route → `via` guard contract → the guard *would* build a `QueryPlan` (`ListTodosByAccount(account_id) ->
QueryPlan`, `FindTodo(account_id, todo_id) -> QueryPlan`). **The central gap:** the Serve contract is
dispatched **purely**, so nothing executes the `QueryPlan` mid-request — a pure guard can return a plan
*value*, not rows. Two honest stages:

- **v0 (P2, no DB):** handlers return canned/empty `Respond` (as `todo_v2` does), and the relational
  `QueryPlan` contracts exist + compile. Reads are *shape-proven*, not executed.
- **Real reads (later):** a **host effect-host seam** runs the guard's `QueryPlan` through the (P10-typed)
  `PostgresReadExecutor`, then dispatches the handler with the rows as the guard's `Ok` context. This needs
  the new seam (§9), not the current runner.

Not-found = `Option[Todo]` / guard-owned `404` (the `via` `Err { error }` returns `Respond 404`). Fields
typed by P10: `id`/`title`/`account_id` Text, `done` Boolean, `inserted_at` Timestamp. **No ORM** — the
relation is the `ListTodosByAccount` contract; rows are plain records, no lazy fields.

## 7. Write flow (Q5)

Mutating route → handler returns `InvokeEffect { target: "todo-create"|"todo-done", input, idempotency_key }`.

- **v0 (P2):** the runner **observes** this as a `202 ServerDecision::InvokeEffect` — **not executed**
  (current behaviour). This is the honest write surface today.
- **Real writes (later):** the effect-host seam maps the logical `target` → `PostgresWriteExecutor` +
  `PostgresWriteIntent` and runs `run_write_effect` → machine receipt + PG `effect_receipts` (two-layer
  idempotency). Smallest safe e2e write = the **fake** write adapter behind the seam (no real DB), then a
  dedicated-local-PG slice. `UnknownExternalState` → `reconcile_postgres_unknown_write` (read-only lookup,
  never re-transacts). `correlation_id` comes from the host (the `[middleware] trace` layer already
  populates it — proven in the P12 runner trace).

**Observed `InvokeEffect` (v0) is strictly separated from real machine execution (later)** — the runner
names a logical target only; capability identity/DSN/receipts stay host-side.

## 8. Host config / effect binding (Q6)

Host-owned, outside the app:
- **read policy:** `PostgresReadPolicy::allow_source_typed("todos", &[(field, kind)…])` (+ accounts).
- **write policy:** `PostgresWritePolicy{ target:"todos", key:"id", columns:["account_id","title","done"] }`.
- **effect-target map:** `"todo-create" → (IO.PostgresWrite, insert)`, `"todo-done" → (IO.PostgresWrite,
  update)` — the seam's lookup table; the contract names only the logical target.
- **DSN env:** `IGNITER_PG_DSN` (read), `IGNITER_PG_WRITE_DSN` (write); loopback-only server; secret
  provider = env.
- **Invariant:** `.igweb` never names a capability id, scope, DSN, table DDL, or secret (manifest rejects
  `[effects]`; `InvokeEffect` carries a logical target string only).

## 9. Runner / deploy story for local lab (Q7)

- **v0:** existing `igweb-serve check` (dry build) + `igweb-serve` loopback with **observed** `InvokeEffect`
  — **no new Rust, app stays no-authored-Rust**.
- **Real DB e2e:** needs a **new lab harness** that wires the runner's effect decisions to the machine
  capability executors (read + write) and feeds read rows back into handler dispatch. This is the
  **effect-host seam** — classified as **lab proof infrastructure, NOT app authoring DX** (the app still
  writes zero Rust). Precedent: `igniter-machine` `frame_binding` P17/P18 already bridges the *frame* path
  (`CoordinationHub::invoke` + `run_write_effect_atomic` under passport/double-gate); the web path needs an
  analogous bridge. It deserves its own readiness card before wiring.

## 10. Phased implementation plan (Q8)

1. **`LAB-TODOAPP-API-SHAPE-P2`** *(smallest, fully doable today)* — author `todo_postgres_app/` (manifest +
   routes + handlers + relational `QueryPlan`/`WriteIntent` contracts); prove `igweb-serve check` builds it,
   loopback serves health/index/show/create/done with `Respond` + **observed** `InvokeEffect`, the
   relational contracts compile, and `igniter-server` stays serde-only. **No DB.**
2. **`LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3`** *(new prerequisite)* — design the host seam that executes
   a Serve's read/write intents through the capability executors and returns results, grounded in the
   `frame_binding` precedent. (Blocks all real DB flow.)
3. **`LAB-TODOAPP-API-READ-P4`** — wire the seam to the **fake** then **P10-typed real** read executor; GET
   routes return real rows; not-found via `Option`/guard-404.
4. **`LAB-TODOAPP-API-WRITE-P5`** — wire the write seam; idempotent write + receipt (fake → dedicated-local
   PG); `UnknownExternalState` reconcile.
5. **`LAB-TODOAPP-API-E2E-P6`** — full local loopback read+write+receipt+reconcile; views/assets later.

Justification: the app shape (P2) is unblocked and de-risks everything; real execution (P4/P5) cannot
proceed until the effect-host seam (P3) exists — so P3 is sequenced before P4/P5, not after.

## 11. Closed surfaces (Q9)

Assets/views; real auth/session secrets; public listener; production/staging DB; SparkCRM/vendor schema;
raw SQL from contracts; ORM/ActiveRecord model layer; migrations runner; pooling/TLS. And in P1: no code,
DB, DDL, dependency, or example change.

## 12. Success criteria for the first card (Q10 — for `…-API-SHAPE-P2`)

- **Files:** `todo_postgres_app/{igweb.toml, routes.igweb, todo_handlers.ig, relational_todo.ig}` +
  a host-policy doc snippet (read/write allowlists + effect-target map).
- **Commands:** `igweb-serve check examples/todo_postgres_app` → ok; an `igweb-serve` loopback test;
  the relational contracts compile clean through the real compiler (no `OOF-TY0`).
- **Loopback behavior table (observed, no DB):**

  | request | result |
  |---|---|
  | `GET /health` | 200 |
  | `GET /accounts/7/todos` | 200 (canned/empty body) |
  | `GET /accounts/7/todos/9` | 200 |
  | `POST /accounts/7/todos` (no key) | 400 (keyless idempotency) |
  | `POST /accounts/7/todos` (keyed) | 202 **observed** `InvokeEffect target=todo-create` |
  | `POST /accounts/7/todos/9/done` (keyed) | 202 **observed** `InvokeEffect target=todo-done` |
  | `GET /missing` | 404 · `DELETE /accounts/7/todos` | 405 |

- **DB env skip:** P2 uses **no DB** (no env, no skip path). Real-DB skip behaviour starts at P4/P5.
- **Receipt assertions:** none in P2 (effects observed only); receipts begin at P5.
- **Dependency boundary:** `igniter-server` normal tree stays serde-only; default machine build
  Postgres-free.

## Next card

`LAB-TODOAPP-API-SHAPE-P2` — the app-files-only, observed-effects, no-DB shape proof. Immediately after,
`LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` (the host effect-execution seam) gates the real read/write
slices. Both P10 (typed reads) and P26 (let/guard) are already in hand, so the path is clear once the
effect-host seam is designed.

---

*Readiness/design only. Compiled 2026-06-19; grounded in live `todo_v2_app`, `igweb-serve`/`lib.rs`
(observed-effect runner), `postgres_read.rs`/`postgres_write.rs` (P10 typed read + write executor +
receipts), the relational P2/P3 proofs, and the now-CLOSED P10/P26. No code, DB, dependency, or example
change.*
