# LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9 - Typed write intent through MachineEffectHost contour

Status: CLOSED
Lane: parallel / IgWeb / TodoApp API / effect-host
Type: implementation-proof
Delegation code: OPUS-IGNITER-WEB-EFFECT-HOST-RUNNER-P9
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-TODOAPP-API-LOCAL-POSTGRES-P8` proved the local-Postgres Todo shape over real adapters, but with one
honest gap:

```text
P8 write path = app-authored structured WriteIntent
             -> direct run_write_effect(...)
             -> real TokioPostgresWriteAdapter
```

That proves the typed payload reaches the real adapter, but it does **not** prove the full served web contour:

```text
IgWeb app returns InvokeEffect(input = structured WriteIntent)
  -> MachineEffectHost
  -> machine ingress / capsule activation
  -> capability executor
  -> receipt
```

Earlier cards proved adjacent pieces:

- P4 / P7: `InvokeEffect.input` can carry structured JSON across `MachineEffectHost`.
- P8: the same structured JSON can drive `PostgresWriteIntent::from_args` and a real adapter.
- Server/machine already have `MachineEffectHost`, `IngressRouter`, `EffectBridgeConfig`, `SingleFlight`,
  `run_write_effect_atomic`, and receipt semantics.

The missing proof is the join: **the full `MachineEffectHost` path must preserve / shape the app's typed
write intent as the capability payload**, instead of masking it behind a generic placeholder capsule.

## Goal

Prove the smallest typed-write effect-host runner contour:

```text
POST /accounts/:account_id/todos
  -> IgWeb todo_postgres_app
  -> InvokeEffect { target: "todo-create", input: WriteIntent, idempotency_key }
  -> MachineEffectHost target binding
  -> machine route / shaping capsule
  -> PostgresWriteIntent::from_args(capsule output)
  -> fake PostgresWriteExecutor or real adapter-gated path
  -> committed receipt
```

Use fake executor first unless live code makes the real adapter equally small. This card is about the **host
contour**, not about local DB DDL.

## Verify First

Read live code before editing:

- `server/igniter-server/src/effect_host.rs`
- `server/igniter-server/tests/effect_machine_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `server/igniter-web/tests/todo_postgres_api_write_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/{routes.igweb,todo_handlers.ig,igweb.toml}`
- `runtime/igniter-machine/src/{ingress.rs,bridge_effect.rs,frame_binding_effect.rs}`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/src/write.rs`
- `lab-docs/lang/lab-igniter-web-structured-effect-input-p7-v0.md`
- `lab-docs/lang/lab-igniter-web-effect-host-write-p4-v0.md`
- `lab-docs/lang/lab-todoapp-api-local-postgres-p8-v0.md`

Confirm or correct:

- whether `MachineEffectHost::run_invoke_effect` currently feeds `InvokeEffect.input` into the capsule;
- whether the capsule output or the original app input becomes the final write payload;
- whether a typed write-shaping capsule can be authored in `.ig` today;
- whether the generic `WriteRecord` capsule is a proof artifact that should be replaced for Todo;
- whether this belongs in `igniter-web` tests, `igniter-server` tests, or `igniter-machine` tests.

Live code wins over this card.

## Recommended Shape

Prefer an implementation proof in `server/igniter-web` because the pressure starts at the IgWeb app:

```text
server/igniter-web/tests/todo_postgres_effect_host_runner_tests.rs
```

The proof may introduce a tiny test-only machine route / capsule, for example:

```ig
module TodoWriteBridge

import IgWebPrelude
import TodoHandlers

pure contract ShapeTodoWrite(input: Unknown) -> (intent: Unknown) {
  intent = input
}
```

That example is only illustrative. If `Unknown` pass-through is not supported or too weak, choose a typed
record shape that matches `PostgresWriteIntent`, or a tiny Rust test-capsule service if that is the existing
machine pattern. Document the choice.

The important invariant:

```text
app logical target + structured input
  -> host target binding + capsule route
  -> final capability payload is the same typed WriteIntent shape
```

## Required Acceptance

- [x] Uses the existing `examples/todo_postgres_app`; no authored app Rust.
- [x] Exercises `MachineEffectHost`, not direct `run_write_effect`.
- [x] Proves `InvokeEffect.input` is the source of the final write payload (via the shaping capsule).
- [x] Proves typed `PostgresWriteIntent::from_args` accepts the final payload.
- [x] Proves commit receipt through the machine host path.
- [x] Proves replay same idempotency key performs no second executor mutation.
- [x] Proves keyless mutation remains app-owned 400 before host execution.
- [x] No `capability_id`/DSN/passport/operation scope/raw SQL/`[effects]` in authored `.ig`/`.igweb`.
- [x] Host authority in Rust config: `target -> route`, passport, capability id, executor registry.
- [x] No server route tables or app-domain logic added to `igniter-server`.
- [x] No live Postgres; fake `PostgresWriteExecutor` over a fake adapter.
- [x] Default `igniter-web cargo test` Postgres-free (52/0).
- [x] Existing P4/P7/P8 tests green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Outcome:** the typed `WriteIntent` flows through the **full `MachineEffectHost` contour** and the final
capability payload IS that intent. New test `tests/todo_postgres_effect_host_runner_tests.rs` (4 tests).
Proof doc: `lab-docs/lang/lab-igniter-web-effect-host-runner-p9-v0.md`.

**Corrects P8's diagnosis (live):** the bridge does **not** mask the intent — `ingress.rs:640-645` envelopes
the *capsule output* as `{intent: <output>, correlation_id}`. The masking was the generic `WriteRecord`
capsule (output `{code}`). The fix = a **shaping capsule** `ShapeTodoWrite` whose output IS the `WriteIntent`
+ a one-key executor **decorator** (`IntentBridgeExecutor`) that lifts `args["intent"]` into the real
`PostgresWriteExecutor` (which reads `from_args(&req.args)` top-level, `postgres_write.rs:181`). No new
mechanism — just the capsule + executor shaping the contour already supports.

**Proof:** app `InvokeEffect{target:"todo-create", input:WriteIntent}` → host `target→/w` binding → shaping
capsule re-emits the intent → bridge envelope → decorator unwraps → `from_args` parses it (committed
`result.target == "todos"`, fake adapter writes 1 business row + 1 PG receipt) → committed receipt; replay
same key → `attempts()` stays 1; keyless → app-owned 400 before host (`attempts()==0`). App names no DB/effect
identity.

**Fake/real boundary:** real `PostgresWriteExecutor` (real from_args + policy gate) over a **fake** adapter —
host contour proven, not DDL (P8 + the operator-gated local-e2e cover the real adapter).

**Plumbing:** `async-trait` added to `igniter-web` **dev-dependencies** only (executor decorator's
`#[async_trait]`); no lib/default change.

**Tests:** runner 4/0; effect_host 6/0; api_write 4/0; local_e2e 5/0 (skip); default igniter-web 52/0;
full machine 76/0; `git diff --check` clean. (Pre-existing unrelated flaky `…read_tests::product_…` passed
this run; separate fix task filed.)

**Next:** `LAB-TODOAPP-API-LOCAL-POSTGRES-RECONCILE-P10`.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_write_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
git diff --check
```

If the proof introduces a new test target, include it explicitly.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-effect-host-runner-p9-v0.md
```

It must state:

- exact request path and IgWeb decision;
- exact `InvokeEffect.input` JSON;
- exact host binding (`target -> route`) and why it is infra authority;
- exact capsule / shaping route used;
- exact final capability payload;
- exact receipt/replay evidence;
- fake vs real adapter boundary;
- any live-code correction to P8's diagnosis;
- exact verification commands and counts.

Update this card with a closing report.

## Closed Scope

- No production public runner.
- No live DB requirement.
- No migration framework.
- No read-stage / `ReadThen`.
- No new `.igweb` syntax.
- No capability identity in app files.
- No canon claim.
