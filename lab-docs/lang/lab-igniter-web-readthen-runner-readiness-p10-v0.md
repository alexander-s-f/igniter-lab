# lab-igniter-web-readthen-runner-readiness-p10-v0 — staged read continuation runner seam

**Card:** `LAB-IGNITER-WEB-READTHEN-RUNNER-P10` · **Delegation:** `OPUS-IGNITER-WEB-READTHEN-RUNNER-P10`
**Status:** READINESS / DESIGN (v0) — designs the smallest **staged read / continuation** seam that drives
the read through a host (not a test hand-orchestration), preserving the app/host authority split. **No
implementation, no new `.igweb` syntax, no live Postgres, no effect-write change, no server-core domain,
no canon claim.**
**Authority:** Lab. App owns product meaning + the logical `QueryPlan` value + the not-found `Decision`;
host owns source/field policy, clamp, adapter, DSN, and infra failures; server owns transport; machine
owns the read executor + receipts. Builds on the read-guard-host readiness
(`lab-igniter-web-read-guard-host-readiness-p5-v0.md`) and the P6 direct-dispatch harness.

**Status as of 2026-06-22:** `ReadThen` is `designed` and `harness-proven`, but not `implemented` and not
`runner-integrated`. Live source has no `ReadThen` arm in `lang/igniter-compiler/src/igweb.rs`,
`server/igniter-web/src/lib.rs`, `server/igniter-server/src/protocol.rs`, or `lang/igniter-vm/src`. Current
final decisions are `Respond`, `InvokeEffect`, `RespondView`, `Render`, and `RenderView` in the IgWeb prelude,
mapped to server decisions by `map_decision`; server protocol has `Respond`, `Invoke`, and `InvokeEffect`.
The hand-orchestrated read host tests prove the staged shape, but that does not make the arm active in
compiler/prelude/runner code.

---

## 1. Executive summary

P5 designed `ReadThen` and P6 proved read→continuation **hand-orchestrated in a test** (two direct
`machine.dispatch` calls inside one outer runtime). The missing piece is making the app actually **emit**
a staged decision and a **host driver** complete it — not a test orchestrating dispatch by hand. Live code
makes the shape slightly smaller than P5 sketched: the prelude now has a generic **`Unknown`** payload type
(used by `InvokeEffect { input : Unknown }`), so the staged arm is `ReadThen { plan : Unknown, then :
String }` with no new prelude QueryPlan type.

The central runner finding is unchanged and decisive: `IgWebServerApp::call` is **sync** and does an
**internal `block_on`** on a per-instance current-thread runtime (`lib.rs:106,119`). A staged read needs
async IO *between* the entry dispatch and the continuation dispatch — which **cannot** nest inside that
`block_on`. The fix is the one the write effect-host already uses: **drive the staged read in an async host
function that owns the await chain and calls `machine.dispatch(...).await` directly**, bypassing the sync
`call` — exactly as the harnesses and `MachineEffectHost::run_invoke_effect` do today. So the smallest safe
seam is a **host async staged driver + the `ReadThen` arm + a harness proof**, NOT the full async socket
runner (still deferred).

Recommended next implementation card: **`LAB-IGNITER-WEB-READTHEN-DISPATCH-P11`** (§ "Next").

## 2. Verify-first (live, file:line)

- **No `ReadThen` arm yet.** Prelude `variant Decision` = `Respond` / `InvokeEffect { input : Unknown }` /
  `RespondView` / `Render` / `RenderView` (`igweb.rs` PRELUDE_SOURCE:66-72). `lib.rs map_decision` handles
  all five as **final** decisions; unknown tag → 500 (`lib.rs:164-223`). No staged arm, no `read` syntax.
- **`Unknown` exists** as the open structured-payload type (`InvokeEffect.input : Unknown`); `map_decision`
  lifts it verbatim (`fields.get("input").cloned()`). So a `plan : Unknown` carries the app-built QueryPlan
  JSON with no new prelude type.
- **Sync `call` + internal `block_on`** (`lib.rs`): `IgWebServerApp` stores a per-instance
  `tokio::runtime` (current-thread, `:106`) and every request does `self.rt.block_on(self.machine.dispatch(
  &self.entry, input))` (`:119`). `machine.dispatch` is **async**. This is the only app-layer `block_on`.
- **Staged read TODAY = harness only.** `todo_postgres_read_host_tests.rs` (`#[cfg(feature="machine")]`):
  one outer `rt().block_on(async { … })` does `dispatch("ListTodosByAccount").await` → `host_read(plan,
  policy, fake_adapter).await` → `rows_json = to_string(result["rows"])` → `dispatch("TodoIndexFromRows",
  {req, rows_json}).await`. **No nested `block_on`** because one runtime owns the whole chain, and the app's
  sync `call` is bypassed (direct `dispatch`). The read-then-write e2e sequences a continuation
  `InvokeEffect` through `MachineEffectHost::run_invoke_effect` in the **same** outer runtime.
- **Read executor** (`runtime/igniter-machine/src/postgres_read.rs`): `QueryPlan { source, op, projection,
  filters, order_by, limit }` (:53-60); `PostgresReadResult { Rows(Vec<Value>), Unavailable, Transient,
  QueryError }` (:402-407) → `succeeded` / `unknown` / `retryable` / `permanent`; success result =
  `{ kind: "rows"|"empty", source, rows: [...], count, effective_limit, row_limit_clamped }`. Rows are
  JSON `Value` objects (P10 typed-decode kinds applied by the real adapter; fake preserves typed JSON).
- **Runner has no read/effect execution.** `igweb-serve` uses `serve_loop` (not the effect variant);
  `MachineEffectHost` exists (`server/igniter-server/src/effect_host.rs`) but the bin doesn't drive it.
  Effect/read execution lives in test harnesses only.

**Delta vs P5:** (a) `plan : Unknown` is now the clean carrier (no prelude QueryPlan type needed); (b) the
write path already established the "sync `call` returns a decision, async host executes" two-phase pattern —
the staged read is the same pattern with a *continuation re-dispatch* added.

## 3. Exact `Decision` arm shape

```ig
variant Decision {
  Respond      { status : Integer, body : String }
  InvokeEffect { target : String, input : Unknown, idempotency_key : String }
  RespondView  { status : Integer, view : View }
  Render       { status : Integer, artifact_json : String }
  RenderView   { status : Integer, view : ViewArtifact }
  ReadThen     { plan : Unknown, then : String }            -- NEW (staged)
}
```

- **`plan : Unknown`** — the app-built `QueryPlan` value (the proven query contract
  `ListTodosByAccount(account_id) -> QueryPlan` returns it; the entry does `compute plan = call_contract(
  "ListTodosByAccount", account_id)`). Carried verbatim like `InvokeEffect.input`; the host validates it
  against policy. **No raw SQL, no DSN, no capability id** — it's the same structural QueryPlan JSON P3/P10
  already gate.
- **`then : String`** — the continuation contract name (a static literal the app authors), dispatched by
  the host with the rows. Not a dynamic dispatch in `.ig` (the app writes the literal name).
- **Why generic `ReadThen` (not `ReadThenRespond`/…):** the continuation returns ANY final `Decision`, so
  one staged arm composes with all five final arms uniformly (P5 §4 option B). Rejected: host-backed `via`
  (hidden IO authority in a pure guard) and read-as-`InvokeEffect` (a final effect can't feed rows back).

## 4. Continuation signature & argument order

```ig
pure contract <Continuation> {
  input req       : Request
  input rows_json : String     -- the read result rows as a JSON array string (v0)
  compute d : Decision = ...   -- branch found vs empty([]), return any final Decision
  output d : Decision
}
```

- **Order:** `req` first, then `rows_json` — matches the harness input `{ "req": …, "rows_json": … }`.
- **Rows = JSON string in v0** (P5 §6): the host serializes `result["rows"]` to a string; the continuation
  branches **found vs not-found** (empty array) and shapes a response. **Typed-row destructuring into `.ig`
  inputs is deferred** (records still infer to `Unknown`; a separate typed-row language slice). v0 proves
  the *seam*, not row destructuring.
- The host re-passes the **original `req`** (it holds the `ServerRequest`); the continuation never re-reads.

## 5. Host error mapping (Q: denied/permanent/retry/unknown)

Driven by the live `PostgresReadResult → EffectOutcome` taxonomy; **infra failure = host-owned, data
absence = app-owned**:

| Read outcome | Source | Driver result |
|---|---|---|
| `Succeeded(rows)` | executor | run the continuation with `rows_json` |
| `Succeeded` with **empty** rows | executor | **NOT an error** — continuation runs, returns the **app-owned** `Decision` (e.g. 404) |
| `Denied` (source/field not allowlisted, raw-SQL key) | gate **before adapter** | host **403** (machine internals redacted: no SQL/DSN/row leak) |
| `PermanentFailure` (malformed plan, invalid predicate, query error) | executor | host **400/500** |
| `Retryable` (adapter transient) | executor | host **503** (no false success) |
| `Unknown` (adapter unavailable) | executor | host **503/unknown** (no false success) |

Not-found stays **app product meaning** (empty rows → continuation → app 404); infra stays **host
responsibility** — the app never sees capability ids, SQLSTATE, or DSN. This reuses the existing
`OutcomeKind` without exposing it to `.ig`.

## 6. Runner config & authority boundary

- **Host-owned (runner/driver config):** the `PostgresReadPolicy` (allowlisted sources + fields + P10
  value-kinds), the row-limit **clamp**, the fake-vs-real **adapter** choice, the **DSN** (env, never in
  `.ig`), and the binding from a logical read target → policy/adapter. Same ownership the effect host has
  for writes (topology binding), not in the app manifest.
- **App-owned:** the `QueryPlan` value it builds (logical intent), the continuation name, and the
  not-found/fallback `Decision`. `.igweb`/`.ig` name **no** capability id, scope, DSN, raw SQL, or pool.
- **The block_on resolution (the core runner seam):** the staged driver is **async and owns the await
  chain**; it calls `machine.dispatch(entry).await` → `read_host.run(plan).await` →
  `machine.dispatch(then, {req, rows_json}).await`, all under **one** top-level runtime — **no nested
  `block_on`** (proven by the harnesses). It therefore **bypasses** `IgWebServerApp::call`'s sync
  per-instance `block_on`, exactly as `MachineEffectHost::run_invoke_effect` does for writes. Wiring this
  into the actual socket loop (an async `serve_loop`) is the larger, separately-deferred
  `…-ASYNC-RUNNER-P*`; the smallest seam is the driver + arm + harness.

## 7. Interaction with render / write after the continuation

The continuation returns **any final `Decision`**, mapped by the existing `map_decision`:

- `Respond` / `RespondView` → JSON response;
- `Render` / `RenderView` → HTML response (the P16/P19 raw-HTML seam);
- `InvokeEffect` → **read-then-write**: the driver hands it to `MachineEffectHost::run_invoke_effect`
  (P4/P7) in the **same** async context, executing the effect + receipt. (The harness already sequences a
  continuation effect this way.)

So one generic `ReadThen` composes with JSON, HTML, and write paths with no per-kind staged arms. v0 should
prove **read → Respond** and **read → RenderView**; read-then-write is the natural next composition (model
in the TodoApp API, not the seam card).

## 8. Tests the implementation card must require

Mirroring P6 but driven by the actual `ReadThen` decision through the host driver (`#[cfg(feature="machine")]`,
fake adapter, no live DB):

1. **found** → Serve returns `ReadThen{plan, then}`; driver runs read; continuation returns `200` carrying
   a shape derived from the rows;
2. **not-found** (fake source empty) → continuation returns the **app-owned 404** (empty rows, not an error);
3. **denied source** (not allowlisted) → denied **before the adapter** (`query_count == 0`), host 403;
4. **forbidden projection field** → denied before the adapter;
5. **row-limit clamp** applied (`effective_limit ≤ policy cap`);
6. **raw-SQL key** in the plan → permanent-fail before the adapter;
7. **no nested `block_on`** — the driver completes entry→read→continuation in one runtime (assert it runs
   without a runtime-panic; the driver uses `machine.dispatch().await`, not `call`);
8. **read → final render** — a continuation returning `RenderView` yields text/html (composition with P19);
9. **no capability id / scope / DSN / raw SQL** in the authored `.ig`;
10. **default (no-machine) build unchanged**; no `IGNITER_PG_DSN` / live DB.
11. *(stretch)* **read-then-write** — a continuation returning `InvokeEffect` executes through the effect
    host (may defer to a TodoApp-API card).

## 9. What stays deferred / rejected (unchanged from P5)

Full async socket runner (the `IgWebServerApp::call` sync `block_on` → async `serve_loop`), typed-row
destructuring into `.ig` inputs (v0 rows = JSON string), the `read … as rows -> Cont` `.igweb` **syntax**
(v0 needs no new syntax — the entry authors `ReadThen` via the query contract + continuation name; sugar is
a later card), live Postgres, raw SQL, ORM/schema inference, host-backed `via`, streaming, public listener,
collapsing reads into a final `InvokeEffect`.

## 10. Next card

**`LAB-IGNITER-WEB-READTHEN-DISPATCH-P11`** — `machine`-gated implementation of:
1. the `ReadThen { plan : Unknown, then : String }` prelude arm (+ `map_decision`/driver awareness — the
   sync `call` may surface `ReadThen` as a host-only 500 or a typed "staged" marker, since only the async
   driver completes it);
2. an **async host staged driver** `run_read_then(machine, read_policy, adapter, request) -> ServerDecision`
   that dispatches entry → runs the read (reusing `host_read` + `PostgresReadExecutor`) → dispatches the
   continuation → maps the final `Decision` (incl. `InvokeEffect` → effect host);
3. the §8 harness tests.

This is strictly the successor to P6 (P6 hand-orchestrated the two dispatches; P11 makes the app emit the
staged decision and a host driver complete it). The full async socket runner
(`…-ASYNC-RUNNER-P*`) and the `read …` `.igweb` syntax (`…-READ-SYNTAX-P*`) follow.

---

*Readiness/design only. Compiled 2026-06-22; grounded in live `lib.rs` (`IgWebServerApp::call` sync
`block_on`, `map_decision`), `igweb.rs` prelude `Decision` + `Unknown`, `postgres_read.rs`
(`QueryPlan`/`PostgresReadResult`), the P6 read-host harness, and `effect_host.rs`
(`MachineEffectHost::run_invoke_effect`). No code, prelude, server, runner, or DB change.*
