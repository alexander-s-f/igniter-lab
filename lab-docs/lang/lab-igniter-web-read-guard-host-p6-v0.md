# lab-igniter-web-read-guard-host-p6-v0 — direct-dispatch read-guard host proof

**Card:** `LAB-IGNITER-WEB-READ-GUARD-HOST-P6` · **Delegation:** `OPUS-IGWEB-READ-GUARD-HOST-P6`
**Status:** CLOSED (lab implementation proof) — the first mid-request **read** seam, proven as a
direct-dispatch harness (mirrors P4's write proof): a **real** `.ig` query contract produces a `QueryPlan`,
the **host** runs it through the fake `PostgresReadExecutor` under a host `PostgresReadPolicy`, and the rows
feed a **real** `.ig` continuation contract that returns an ordinary final `Decision`.
**No live Postgres/DSN/DDL, no new `.igweb` syntax, no `ReadThen` prelude arm, no runner productization, no
typed row destructuring, no write execution, no canon.**
**Authority:** Lab. App owns the logical query + not-found `Decision`; host owns the read policy + executor;
`.ig` names no capability id, scope, DSN, or SQL.

## 1. Executive summary

The read half is end-to-end real with **both `.ig` ends dispatched for real**:
`ListTodosByAccount("acct-7") -> QueryPlan` → host `PostgresReadExecutor<FakePostgresAdapter>`
(allowlist + clamp gate) → rows → `rows_json` → `TodoIndexFromRows(req, rows_json) -> Decision` →
`Respond 200` (found) or `Respond 404` (empty rows = app not-found). Host gates (denied source/field, raw
SQL) refuse before the adapter; the row-limit clamp applies; the authored `.ig` carries no DB authority.
Both contracts run via `IgniterMachine::dispatch` **called directly in the async harness** (not through
`IgWebServerApp::call`), so the P4 `block_on` nesting never arises.

## 2. Verify-first (live)

- `IgniterMachine::load_program(paths, entry)` merges files via `multifile::compile_units` and **registers
  every contract** (`machine.rs:196-216`); `dispatch(name, inputs)` looks the contract up in that registry
  (`machine.rs:289-302`) — so a harness can dispatch **any** loaded contract, async, directly.
- `PostgresReadExecutor` + `FakePostgresAdapter` + `run_effect` are in the machine **default** build
  (only the *real* tokio-postgres adapter is `postgres`-gated); the fake gates by allowlist/clamp and
  refuses raw SQL without a live DB (P3/P10). Confirmed.
- VM-dispatched `Decision` output is the variant record `{ "__arm": "Respond", "status", "body", … }` —
  the same shape `igniter-web`'s `map_decision` reads. Asserted on the continuation's result.
- `via`/`guard` remain pure (P20/P26) — unchanged; this seam adds no IO to them.

## 3. Implementation

- **`server/igniter-web/tests/fixtures/read_harness/read_harness.ig`** — the authored read half: `QueryPlan`
  /`QueryFilter` types + `MakeFilter` factory + `ListTodosByAccount(account_id) -> QueryPlan` +
  `TodoIndexFromRows(req, rows_json : String) -> Decision` (empty rows → 404, else 200 with rows).
- **`server/igniter-web/tests/todo_postgres_read_host_tests.rs`** (`#![cfg(feature = "machine")]`, 4 tests)
  — loads the prelude + fixture into a fresh `IgniterMachine`, dispatches the query contract, runs the plan
  through `PostgresReadExecutor` under a host policy, serializes rows → `rows_json`, dispatches the
  continuation, asserts the final `Decision`.

No app/manifest/runner/server/machine/compiler **source** changed — only a new test + fixture. The new test
is `machine`-gated, so the default `igniter-web` suite is unchanged.

## 4. What is proven (4 tests, `--features machine`)

| test | proves |
|---|---|
| `found_rows_flow_query_to_continuation_200` | real `ListTodosByAccount` → structural `QueryPlan`; host read → 2 rows (`query_count==1`); `rows_json` → real `TodoIndexFromRows` → `Respond 200` carrying the rows |
| `empty_rows_are_app_not_found_404` | empty fake source → `rows_json == "[]"` → continuation returns the **app-owned 404** (not an infra error) |
| `host_gates_before_adapter_and_clamp` | denied **source** + forbidden **field** + **raw-SQL** key each refused **before the adapter** (`query_count==0`); the contract's `limit:50` **clamped** to a policy cap of 1 (`effective_limit==1`, `row_limit_clamped==true`) |
| `authored_fixture_has_no_forbidden_surface` | the authored `.ig` code (comments stripped) has no `select `/`insert`/`where`/`capability_id`/`io.postgres`/`passport`/`dsn`/`scope`; the only DB-ish token is the logical `source: "todos"` |

## 5. Error mapping (P5 split, honored)

- **Succeeded(rows)** → continuation runs with the rows.
- **Empty rows** → legitimate **app not-found** (continuation 404), not an infra error.
- **Denied** (unknown source / forbidden field / raw SQL) → host `Denied`/`PermanentFailure`
  **before the adapter** — machine internals not exposed to the app code.
- Clamp is a host policy adjustment, not a denial.

## 6. Honest scope

- **Direct-dispatch harness, not the full async socket loop** — the same P4 §5 `block_on` boundary applies
  (and is worse for reads: the host must re-enter the app for the continuation). The harness dispatches both
  contracts directly via `IgniterMachine::dispatch().await`, avoiding `IgWebServerApp::call`'s internal
  `block_on`. Productizing a runner (resolve sync/async + a two-phase staged dispatcher) is a follow-up.
- **Rows reach the continuation as a JSON string** (`rows_json : String`) — P5's humble v0. Typed row
  destructuring into `.ig` records is deferred.
- **No staged `.igweb` syntax / `ReadThen` prelude arm yet** — the harness stands in for the eventual
  `read … as rows -> Handler` lowering. No write execution in this card.

## 7. Verification commands + exact counts

```text
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_read_host_tests
  → 4 passed; 0 failed
$ cd server/igniter-web && cargo test                  → 49 passed; 0 failed (read test gated to 0)
$ cd server/igniter-web && cargo test --features machine → 58 passed; 0 failed (49 + read 4 + effect-host 5)
$ cd runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests → 6 passed
$ cd runtime/igniter-machine && cargo test --no-default-features --test postgres_read_tests → 10 passed
$ git diff --check                                     → clean
```

Source scan over the authored app/fixture: the only `capability`/`dsn`/`scope` hits are in `host_policy.md`
(the host-config *doc*, non-authoritative) and `.ig`/`.igweb` *comments* describing the boundary — no
forbidden tokens in authored code (test 4 asserts this on comment-stripped source).

## 8. Next

1. `LAB-TODOAPP-API-READ-P*` — a product-shaped Todo read route over this proven seam (toward the staged
   `read …` form).
2. staged `.igweb` `read … as rows -> Handler` syntax + the `ReadThen` prelude arm (the eventual authoring
   surface this harness stands in for).
3. read-then-write composition with P4 (continuation returns `InvokeEffect`).
4. `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*` — productize the runner; resolve the sync/async boundary for
   both writes and the two-phase staged read.

---

*Lab implementation proof. Compiled 2026-06-20; 4 machine-gated read-seam tests green (query→host
read→continuation: found 200, empty 404, gates-before-adapter + clamp, no authored DB surface); default
igniter-web 49 + machine 58 green; igniter-machine read/bridge suites green. Real `.ig` on both ends via
`IgniterMachine::dispatch`. No live DB, new syntax, prelude arm, or runner productization.*
