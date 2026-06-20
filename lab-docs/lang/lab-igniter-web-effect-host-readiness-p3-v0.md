# lab-igniter-web-effect-host-readiness-p3-v0 — IgWeb effect execution seam

**Card:** `LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` · **Delegation:** `OPUS-IGWEB-EFFECT-HOST-P3`
**Status:** READINESS / ARCHITECTURE BOUNDARY (v0) — designs the IgWeb/web-app seam that composes the
**already-built** `igniter-server` machine-backed effect host with `igniter-web` apps. **No code, no deps,
no live Postgres, no DDL, no public listener, no canon.**
**Authority:** Lab readiness. App owns product meaning; host owns authority/execution; server owns
transport; machine owns receipts/idempotency/reconcile.

## 1. Executive summary + correction to P1

**P1 was wrong on one point and this card corrects it:** the machine-backed effect path is **not** missing
— `igniter-server` already ships `MachineEffectHost` + `serve_once_effect*` + `serve_loop_effect`
(`effect_host.rs`), which execute a `ServerDecision::InvokeEffect` through `IngressRouter::handle_effect`
→ `CoordinationHub` → capability executor → receipt, carrying **no** capability identity across the
protocol. So **final write effect execution is already a solved, built contour.** The only reason
`todo_postgres_app` *observes* effects is that the generic `igweb-serve` runner wires the **plain**
`serve_loop`, not `serve_loop_effect` + a configured `MachineEffectHost`. The genuinely missing seam is
**mid-request read guards** (pure `via` guards cannot perform IO; the effect host executes a *final*
decision, not a mid-dispatch read that feeds handler context). **Recommended v0: a machine-enabled IgWeb
runner that executes final `InvokeEffect` writes through the existing host against a fake write executor —
wiring, not new architecture. Reads get their own later seam.**

## 2. Verify-first (live code, file:line)

| Surface | Fact |
|---|---|
| `server/igniter-server/src/effect_host.rs:34` | `MachineEffectHost` holds `target_routes: BTreeMap<String,String>` — **infra binding only** (`target → machine ingress route`), no `(method,path)→action` table |
| `effect_host.rs:58` | `bind_target(target, machine_route)` — the host's only product-adjacent knob (topology, not meaning) |
| `effect_host.rs:8-20` | comment: app decides `InvokeEffect{target}`; host holds `target→route/pool`; **no `capability_id`/`operation`/`scope` crosses the protocol**; execution IS `handle_effect` (adds no effect semantics) |
| `effect_host.rs:232` | `serve_loop_effect(listener, ReloadableApp, MachineEffectHost, ServingPolicy)` — bounded loop, identical to `serve_loop` but dispatches through the effect host; loopback-guarded; no spawn/daemon |
| `effect_host.rs:212` | `serve_once_effect_reloadable_observed` — snapshot app, `dispatch(req, decision, effect_host)`, records `AppIdentity` |
| `runtime/igniter-machine/src/ingress.rs:205` | `IngressRouter::handle_effect`: passport → route → production pool + `ServiceRecipe` → invoke via hub → normalized HTTP response + audit |
| `server/igniter-web/src/lib.rs:171` | the runner maps VM `InvokeEffect` → `ServerDecision::InvokeEffect` (target/input/idempotency_key) — **already the exact shape the effect host consumes** |
| `server/igniter-web/src/bin/igweb-serve.rs:10,48` | `igweb-serve` uses the **plain** `serve_loop` (observed effects), **not** `serve_loop_effect` |
| `server/igniter-web/examples/todo_postgres_app/` | the P2 app emits `InvokeEffect{target: "todo-create"|"todo-done"}` — observed today |

**Conclusion:** the write contour is built and proven (`postgres_write_tests`, ingress P7/P10/P11); only the
**runner choice** (`serve_loop` vs `serve_loop_effect` + a configured host) separates observed from executed.

## 3. The four problems, separated (Q1)

1. **Final `InvokeEffect` execution** — *already possible*; gap = IgWeb runner wiring (`serve_loop_effect`
   + a `MachineEffectHost` with `bind_target` + a capability registry holding the write executor).
2. **Mid-request read guards** — *genuinely missing*. A pure `via` guard returns a `QueryPlan` *value*; the
   Serve contract is one pure dispatch, so nothing runs the plan mid-request and feeds rows back. Needs a
   new staged seam (§7).
3. **Async/background effects** — out of scope.
4. **Operator config / packaging** — a host-owned binding file, not the app manifest (§5).

## 4. v0 execution target (Q2) — recommend **A (write-only final InvokeEffect)**

| Option | Verdict |
|---|---|
| **A. write-only final `InvokeEffect`** via existing `MachineEffectHost` | **v0** — reuses 100% of the built contour; only wiring + config; proves the write loop e2e through IgWeb |
| B. read-only guard execution (`QueryPlan` → rows → handler context) | **defer** — needs a *new* staged-Decision seam (§7); bigger, riskier |
| C. unified read/write intent host | **reject for v0** — premature; do A, then B, then consider unifying |

A is smallest because the host, the ingress route, the capability executor, the receipt/replay/reconcile,
and the `ServerDecision::InvokeEffect` shape **all already exist** — the slice is a machine-enabled runner
variant binding `todo-create`/`todo-done` to a fake write executor's machine route.

## 5. Host authority + `[effects]` (Q3, Q4)

**Keep `igweb.toml` machine-free** (the P12 rule stays): the app manifest names no effect authority, and
the parser still rejects `[effects]`. A **machine-enabled runner** reads a **separate host-owned file**
(e.g. `igweb.host.toml`, or a Rust harness config in v0) holding:
- `target → machine route` bindings (`MachineEffectHost::bind_target`);
- read `source/field/kind` + write `target/key/columns` allowlists (the Postgres policies);
- DSN env names; the effect passport / authorization material; idempotency policy.

This preserves: (a) **no app-owned secrets** — the binding file is operator-owned, not in the app dir, so
an app package can't smuggle authority; (b) **no-Rust app DX** — the app dir is unchanged; only the host
adds a config. The app names only **logical targets + structured intents**; it never names capability ids,
scopes, DSNs, raw SQL, route-to-pool, or secrets.

## 6. Final writes (Q5)

`Decision.InvokeEffect{target,input,idempotency_key}` → (runner, `lib.rs:171`) `ServerDecision::InvokeEffect`
→ `MachineEffectHost::dispatch(target,…)` → `IngressRouter::handle_effect` → hub → `PostgresWriteExecutor`
→ machine receipt + PG `effect_receipts`. `target` is logical (`todo-create`); `input`/`idempotency_key`
flow through; `correlation_id` from the `[middleware] trace` layer. **Keyless mutating requests fail at the
`.igweb` 400 idempotency guard BEFORE the effect host** (already proven in P2). Receipts/replay/reconcile
stay machine-owned. **Test that no capability identity crosses the protocol:** assert the `ServerDecision`
carries only `target`/`input`/`idempotency_key` — no `capability_id`/`scope` (the P2 loopback test already
asserts this for the observed shape; the executed shape must keep it).

## 7. Reads — the harder seam (Q6), deferred

Pure `via` guards can't do IO. Evaluated:
- **(a) guard returns `QueryPlan`, host executes, then calls handler** — but the Serve contract is one pure
  dispatch; you can't pause mid-dispatch to inject rows.
- **(b) a staged read Decision** `ReadThenRespond { plan, then: "<Handler>" }` / `ReadThenInvoke{…}` — a new
  `Decision` variant the host executes: run the `QueryPlan` through `PostgresReadExecutor`, then re-dispatch
  the named handler with rows as context. **Recommended read design** (explicit, inspectable: plan +
  handler name are in the generated `.ig`).
- **(c) a VM host callback around `call_contract`** — **rejected**: hidden runtime authority, opaque.
- **(d) staged pure-match → host query → pure handler** — same shape as (b), the implementable form.

(b)/(d) need a new Decision variant + runner staging — **bigger than writes**, so reads are a separate
readiness/impl after the write seam lands.

## 8. Composition with `let`/`guard` (Q7)

- **Pure contexts** (`ReqInfo`, cookie parse, timezone) stay pure guards — unchanged P20/P26/P27 lowering.
- **IO contexts** (`RequireUser`, `LoadAccount`, `LoadTodo`) need the read seam (§7, deferred); until then
  they remain fixture/canned (P2).
- IO guards return **one accumulated context record** (the P21/P22 composite-guard rule) — preserved.
- Writes (the v0 slice) touch **no** guard lowering: a final `InvokeEffect` is the handler's return, so
  P20/P26/P27 assumptions are untouched.

## 9. Local proof harness (Q8)

Fake write executor first; local loopback only; bounded `serve_loop_effect`; no public listener; no
SparkCRM/vendor schema; optional dedicated local Postgres behind an env gate. A lab harness (test or small
bin, classified as **proof infra not app DX**) wires `MachineEffectHost::bind_target("todo-create", "/w")`
(+ `todo-done`) + a fake `PostgresWriteExecutor` in the capability registry + `serve_loop_effect` against
the unchanged `todo_postgres_app`.

## 10. Failure semantics (Q9)

`handle_effect` already normalizes machine outcomes to status/body. Map: **denied** policy → 4xx;
**permanent** query/schema error → 5xx (no SQL/row leak); **retryable** external state → 503-style;
**unknown** external state → no false success, reconcile path (receipt unknown); **not-found** (read,
later) = data (`Option`/empty → 200), distinct from **infra** failure (5xx). `correlation_id` from trace
middleware; receipts host-visible. **Never leak** DSN, raw SQL, secret, or row values in infra errors — the
`InvokeEffect → handle_effect` path returns a normalized response, not adapter internals (an explicit
redaction test belongs in P4).

## 11. Rejected / deferred

- **Re-implementing a server effect host** — rejected; `MachineEffectHost`/`serve_loop_effect` exist.
- **`[effects]` in `igweb.toml`** — rejected; bindings go in a host-owned file, not the app manifest.
- **VM `call_contract` interceptor for reads** — rejected (hidden authority).
- **Unified read+write host (C)** — deferred until both halves are proven.
- **Read guards (B)** — deferred to a separate readiness after the write seam.

## 12. Next card (Q10)

**`LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4`** — a **machine-enabled IgWeb runner/harness** that runs
`todo_postgres_app`'s final `InvokeEffect` (`todo-create`/`todo-done`) through the existing
`MachineEffectHost` + `serve_loop_effect` against a **fake** `PostgresWriteExecutor`, over bounded local
loopback. **Why first:** it reuses the entire built write contour (smallest, lowest risk), proves IgWeb →
machine write execution e2e, and unblocks real writes — while reads wait on the new staged-read seam.

**Acceptance sketch for P4:**
- a machine-enabled runner/harness binds `todo-create`/`todo-done` → machine route + fake write executor;
- keyed `POST /accounts/7/todos` → write **executed**, a machine receipt persisted (not just observed 202);
- keyless mutating request → 400 **before** the effect host (unchanged);
- replay of the same idempotency key → executor runs once (receipt replay);
- the `ServerDecision` carries **no** `capability_id`/`scope` (no identity crosses the protocol);
- `igweb.toml` still rejects `[effects]`; bindings live in the host-owned config, not the app dir;
- default/no-machine build path unchanged; `igniter-server` core stays route/domain-free;
- no live DB, no DSN required (fake executor); local loopback only.

---

*Readiness/architecture only. Compiled 2026-06-20; grounded in live `effect_host.rs` (MachineEffectHost +
serve_loop_effect), `ingress.rs` (handle_effect), `igweb-serve`/`lib.rs` (plain serve_loop + observed
InvokeEffect), and the P2 app. Corrects P1: the write effect host already exists; the seam is runner
wiring + the (deferred) read stage. No code, deps, DB, or server-core change.*
