# LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3 - IgWeb effect execution seam

Status: CLOSED
Lane: standard
Type: readiness / architecture boundary
Delegation code: OPUS-IGWEB-EFFECT-HOST-P3
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-TODOAPP-API-POSTGRES-E2E-READINESS-P1` identified the missing link for a real DB-backed Todo API:
IgWeb can author routes, guards, relational `QueryPlan`/`WriteIntent` values, and `InvokeEffect`
decisions, but the generic `igweb-serve` runner still observes effects instead of executing them.

Important verify-first correction: `igniter-server` already has a machine-backed effect path:

```text
server/igniter-server/src/effect_host.rs
MachineEffectHost + serve_once_effect + serve_loop_effect
```

So this card must not rediscover or reimplement a generic server effect host. The job is to design the
IgWeb/web-app seam that composes the existing machine-backed host path with `igniter-web` apps, and to
separate final write effects from mid-request read guards.

## Goal

Produce a readiness packet that answers:

> What is the smallest correct host seam that lets an IgWeb app execute read/write intents through
> `igniter-machine` capability executors without putting capability authority, DB handles, DSNs, or
> server route tables into `.igweb`, `.ig`, or `igniter-server` core?

No code in this card.

## Verify First

Read live code and docs before designing. Paths may have moved after repo reorganization.

- `server/igniter-server/src/effect_host.rs`
- `server/igniter-server/src/protocol.rs`
- `server/igniter-server/src/host.rs`
- `server/igniter-server/src/serving_loop.rs`
- `server/igniter-web/src/lib.rs`
  - especially `map_decision`, `InvokeEffect`, `RespondView`, and the embedded `runner` module
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/examples/todo_v2_app/`
- `server/igniter-web/examples/todo_postgres_app/` if present
- `runtime/igniter-machine/src/ingress.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs`
- `runtime/igniter-machine/tests/postgres_read_tests.rs`
- `runtime/igniter-machine/tests/postgres_write_tests.rs`
- `lab-docs/lang/lab-todoapp-api-postgres-e2e-readiness-p1-v0.md`
- `lab-docs/lang/lab-todoapp-api-shape-p2-v0.md`
- `lab-docs/lang/lab-igniter-relational-queryplan-bridge-p3-v0.md`
- `lab-docs/lang/lab-machine-postgres-typed-read-p10-v0.md`

Confirm or correct these starting facts:

- `MachineEffectHost` already maps logical `target -> machine ingress route` and executes
  `ServerDecision::InvokeEffect` through `IngressRouter::handle_effect`.
- `igniter-web` currently maps VM `InvokeEffect` into `ServerDecision::InvokeEffect`, but the generic
  runner path is still observed/machine-free.
- The runner manifest has intentionally rejected effect authority so far.
- Final write effects and mid-request read guards are different problems.
- Pure `.igweb` route guards cannot themselves perform Postgres IO unless a host seam provides a value.

## Questions To Answer

### Q1. What gap remains if `MachineEffectHost` already exists?

Separate:

- final response `InvokeEffect` execution;
- route-level read guards needing rows before handler dispatch;
- future async/background effects;
- operator configuration and deploy packaging.

Do not call existing server work "missing" if live code already implements it.

### Q2. What is the v0 execution target?

Compare:

- **A. Write-only final `InvokeEffect` execution** via existing `MachineEffectHost`.
- **B. Read-only guard execution**: `QueryPlan` produced by a guard/contract becomes a host-executed
  `PostgresReadExecutor` call whose rows feed handler context.
- **C. Unified read/write intent host** for both query and effect intents.

Recommend the smallest first implementation slice and explain why.

### Q3. Where does host authority live?

Design host/operator config for:

- logical app target -> machine route / capability executor;
- read `source/field/kind` allowlists;
- write `target/key/columns` allowlists;
- DSN env names;
- effect passport / authorization material;
- duplicate/idempotency policy.

The app may name logical targets and produce structured intents. It must not name capability ids,
scopes, DSNs, raw SQL, routes-to-pools, or secrets.

### Q4. Should `[effects]` return to `igweb.toml`?

The P12 runner rejected `[effects]` to keep machine-free authoring safe. Revisit carefully:

- Is `[effects]` author-owned, operator-owned, or a separate host manifest?
- Should a machine-enabled runner accept a different file, for example `igweb.host.toml`?
- How do we avoid app packages smuggling live authority?
- What is the no-Rust user DX?

### Q5. How should final writes work?

Map VM `Decision.InvokeEffect` to existing `ServerDecision::InvokeEffect` and then to `MachineEffectHost`.

Answer:

- what target string means;
- how `input`, `correlation_id`, and `idempotency_key` flow;
- how keyless mutating requests fail before executor;
- how receipts/replay/reconcile remain machine-owned;
- which tests prove no capability identity crosses the app protocol.

### Q6. How should reads work?

This is the harder seam.

Current `via` guards are pure `call_contract`. A DB-backed guard needs rows or not-found context before
calling the handler.

Evaluate options:

- guard returns a `QueryPlan`, host executes it, then calls a handler with rows/context;
- route decision returns a structured `ReadThenRespond` / `ReadThenInvoke` plan;
- VM host callback/interceptor around selected `call_contract` names;
- staged app: pure route match -> host executes query -> pure handler dispatch.

Keep generated `.ig` inspectable and avoid hidden runtime authority.

### Q7. How does this compose with `let`/`guard` / composite context?

Account/User/ReqInfo style context composition should remain explicit.

Answer:

- which contexts are pure (`ReqInfo`, cookie parsing, timezone);
- which contexts require IO (`RequireUser`, `LoadAccount`, `LoadTodo`);
- whether IO guards must return one accumulated context record;
- what happens to P20/P26/P27 lowering assumptions.

### Q8. What is the local lab proof harness?

Design the first proof without live production DB:

- fake read executor first;
- fake write executor first;
- local loopback only;
- bounded serving loop;
- no public listener;
- no SparkCRM/vendor schema;
- optional dedicated local Postgres only behind env gate.

### Q9. What are the failure semantics?

Define how host-executed read/write failures map to web responses:

- denied policy;
- permanent schema/query error;
- retryable external state;
- unknown external state;
- not-found vs infra failure;
- correlation id and receipt visibility;
- never leak DSN, raw SQL, secret, or row values in infra errors.

### Q10. What should P4 implement?

Give one bounded next implementation card, not a broad framework.

Preferred candidates:

- `LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4` - machine-enabled runner/harness for final `InvokeEffect`
  against fake write executor.
- `LAB-IGNITER-WEB-READ-GUARD-HOST-P4` - fake read guard seam returning typed context.
- Or another smaller slice if verify-first shows a safer cut.

State why the chosen slice comes first.

## Required Output

Create:

- `lab-docs/lang/lab-igniter-web-effect-host-readiness-p3-v0.md`
- closing report in this card

The packet must include:

- verify-first summary with file/path evidence;
- explicit distinction between existing `igniter-server` `MachineEffectHost` and missing IgWeb runner/app seam;
- recommended v0 slice;
- rejected alternatives;
- next card name and acceptance sketch.

## Closed Scope

- No code changes.
- No new dependencies.
- No live Postgres.
- No DDL/migrations.
- No public listener.
- No SparkCRM/vendor schema.
- No server route table.
- No capability identity in `.igweb` or app `Decision`.
- No raw SQL.
- No canon claim.

## Acceptance

- [x] Packet is grounded in live code, not stale docs.
- [x] Existing `MachineEffectHost` is acknowledged correctly.
- [x] Final write effect execution and mid-request read guards are separated.
- [x] Host authority placement is explicit.
- [x] Runner/manifest shape is addressed without app-owned secrets.
- [x] Recommended P4 is bounded and testable.
- [x] No implementation, dependencies, DB, or server/core changes.

---

## Closing Report (2026-06-20)

**Deliverable:** `lab-docs/lang/lab-igniter-web-effect-host-readiness-p3-v0.md` — readiness packet, **no
code** (`git status` shows zero `.rs`/`.ig`/`.toml` changes; only the packet + this card are new). Answers
Q1–Q10.

**Decisive verify-first correction to P1:** the machine-backed effect path is **already built** —
`server/igniter-server/src/effect_host.rs` ships `MachineEffectHost` (`target_routes` infra binding +
`bind_target`) + `serve_loop_effect` + `serve_once_effect_reloadable_observed`, executing a
`ServerDecision::InvokeEffect` through `IngressRouter::handle_effect` (`ingress.rs:205`) → CoordinationHub →
capability executor → receipt, with **no capability identity crossing the protocol**. My P1 wrongly called
this missing; P3 corrects it. `igniter-web` already maps VM `InvokeEffect` → `ServerDecision::InvokeEffect`
(`lib.rs:171`) — the exact shape the host consumes. The **only** reason effects are observed: `igweb-serve`
wires the **plain** `serve_loop` (`bin:48`), not `serve_loop_effect` + a configured host.

**Recommendation:** v0 = **A, write-only final `InvokeEffect` execution** through the existing host —
**wiring, not new architecture**. Reads (B) are the genuinely missing seam: pure `via` guards can't do IO,
and the host runs a *final* decision, not a mid-dispatch read; reads need a new staged Decision
(`ReadThenRespond { plan, then }`, §7), deferred. Host authority (target→route bindings + read/write
allowlists + DSN env + passport) lives in a **host-owned file** (`igweb.host.toml`/harness config), **not**
`igweb.toml` — so the app stays machine-free, secret-free, no-Rust.

**Next card:** `LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4` — machine-enabled IgWeb runner/harness running
`todo_postgres_app`'s `todo-create`/`todo-done` through `MachineEffectHost` + `serve_loop_effect` against a
**fake** `PostgresWriteExecutor` (local loopback, no DB), proving executed writes + receipts + no identity
crossing the protocol. Bounded acceptance sketch included in §12.

## Notes

This card is the bridge between:

- IgWeb authoring (`routes.igweb`, `let`/`guard`, `resource`, `via`);
- relational contracts (`QueryPlan`, `WriteIntent`);
- Postgres capability executors;
- server process/transport/middleware.

The right outcome should make TodoApp real DB execution possible while preserving the core rule:

```text
app owns product meaning;
host owns authority and execution;
server owns transport;
machine owns receipts/idempotency/reconcile.
```
