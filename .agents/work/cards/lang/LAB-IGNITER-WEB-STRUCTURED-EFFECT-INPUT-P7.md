# LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7 - Carry structured InvokeEffect input

Status: CLOSED
Lane: standard / TodoApp API / effect-host
Type: implementation-proof
Delegation code: OPUS-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P6` found that the Rust protocol and machine write intent
already carry `serde_json::Value`. The remaining string chokepoints are:

- IgWeb prelude `Decision::InvokeEffect.input : String`;
- `igniter-web` `map_decision` reading `input` with `get_str("input")` and wrapping it as
  `json!({ "input": <string> })`.

This blocks real Todo/Postgres writes because app-authored `WriteIntent.values` must cross the seam as a
structured JSON object, not a string.

## Goal

Implement Alternative A from P6:

```ig
InvokeEffect {
  target: "todo-create",
  input: { title: req.title, done: false },
  idempotency_key: req.idempotency_key
}
```

Expected Rust decision:

```text
ServerDecision::InvokeEffect {
  target: "todo-create",
  input: { "title": "...", "done": false },
  idempotency_key: Some(...)
}
```

No string wrapper, no JSON string parse, no protocol change.

## Verify First

Read live code before editing:

- `lang/igniter-compiler/src/igweb.rs`
  - prelude `Decision`;
  - current `InvokeEffect` arm;
  - examples/tests that emit `InvokeEffect`;
- `server/igniter-web/src/lib.rs`
  - `map_decision`;
  - `RespondView` / `RenderView` pass-through precedent;
- `server/igniter-server/src/protocol.rs`
  - `ServerDecision::InvokeEffect.input`;
- `server/igniter-server/src/effect_host.rs`
  - effect host input passing;
- `runtime/igniter-machine/src/postgres_write.rs`
  - `PostgresWriteIntent::from_args`;
- affected tests/fixtures:
  - `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`;
  - `server/igniter-web/tests/todo_postgres_api_write_tests.rs`;
  - `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`;
  - `server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs`;
  - generic example/builder tests that still use string input;
- proof doc:
  - `lab-docs/lang/lab-igniter-web-structured-effect-input-readiness-p6-v0.md`.

Confirm or correct:

- whether normal `.ig` record literals in a variant arm serialize tag-free;
- whether `input` can be typed as a permissive/open field in the prelude without introducing user generics;
- whether the smallest viable prelude type is `Unknown`, `Value`, a local app record, or a dedicated open
  sentinel already used elsewhere;
- exact test fixtures that must migrate from string input to record input.

Live code wins over this card.

## Recommended Shape

Prefer one arm, no second decision variant:

1. Re-type prelude `InvokeEffect.input` so an app-shaped record is accepted.
2. Change `map_decision` to pass `fields.get("input").cloned().unwrap_or(Value::Null)` through directly.
3. Migrate Todo/Postgres write fixtures to put structured values in `input`.
4. Keep `target` and `idempotency_key` unchanged.
5. Add or update fake-host tests proving `input` reaches `PostgresWriteIntent.values` as typed JSON.

If live typechecking cannot support a truly open record field, choose the narrowest app-local workaround and
document it. Do **not** add `InvokeStructuredEffect` unless all single-arm paths fail.

## Required Acceptance

- [x] `.ig` prelude accepts structured record input for `InvokeEffect` (`input : Unknown`).
- [x] `map_decision` passes structured input as `serde_json::Value` without string wrapping.
- [x] Plain record input serializes tag-free (no `__arm` / `__variant`).
- [x] Nested record input is preserved (`values` sub-object).
- [x] Existing target and idempotency fields remain unchanged (idempotency stays its own field).
- [x] Todo/Postgres create/done command fixtures use structured input (`input: intent`).
- [x] Fake-host proof maps structured input to `PostgresWriteIntent.values`.
- [x] Receipt/replay behavior remains unchanged.
- [x] App-authored files still contain no capability id / operation / scope / DSN / raw SQL.
- [x] Existing RenderView/RespondView behavior remains green.
- [x] Existing IgWeb builder/runner tests remain green.
- [x] `server/igniter-web cargo test` green (52/0, no features).
- [x] `server/igniter-web cargo test --features machine` green (72/0; one pre-existing flaky read test isolated).
- [x] `runtime/igniter-machine postgres_write_tests` green (10/0).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Outcome:** structured `InvokeEffect.input` lands as **pure pass-through** (Alternative A). Proof doc:
`lab-docs/lang/lab-igniter-web-structured-effect-input-p7-v0.md`.

**Changes (4 small edits + 3 proof tests):**
- prelude `input : String` → `input : Unknown` (the open structured-payload sentinel);
- typechecker `infer_variant_construct` exempts expected-`Unknown` fields (mirrors the D3 rule in
  `structurally_assignable`; relax-only, opens only this field);
- `map_decision` `InvokeEffect.input` → `fields.get("input").cloned()` (verbatim `RespondView` pass-through);
- fixture: both mutating handlers carry the whole structured `intent` (`input: intent`).

**Proof:** the app's create decision `input` is a clean JSON object
(`{operation,target,key,correlation_id,values:{…}}`) — no `{"input":"<string>"}` wrapper, tag-free; it feeds
`PostgresWriteIntent::from_args` directly → typed `values` survive nested; raw SQL in the payload is refused
by the host gate; receipt/replay (one effect per key) unchanged; the app names no capability identity.

**Tests:** api_write 4/0, effect_host 6/0, e2e 2/0 (all stable across repeated runs); igniter-web 52/0
(no-feat) + 72/0 (machine); machine `postgres_write_tests` 10/0; compiler 172/0; igweb lowering 11/0;
`git diff --check` clean.

**Pre-existing unrelated flaky test (isolated):**
`todo_postgres_api_read_tests::product_todos_index_found_returns_200` (+3 siblings) — parallel tests share a
per-pid temp `prelude.ig`, an I/O race causing intermittent `missing module declaration` load failures.
**Confirmed pre-existing** (fails identically with P7 changes `git stash`ed, ~2/5 full-file runs). A separate
fix task was filed (unique temp dir per test).

**Next:** `LAB-TODOAPP-API-LOCAL-POSTGRES-P8` — swap the fake executor for a real local-Postgres adapter
(gated DSN/adapter/runner). The structured write payload now crosses the seam and builds a typed
`PostgresWriteIntent`.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-structured-effect-input-p7-v0.md
```

It must include:

- exact prelude type change;
- exact `map_decision` change;
- migrated fixtures/tests;
- JSON evidence showing no string wrapper;
- fake-host `PostgresWriteIntent.values` evidence;
- receipt/replay evidence;
- authority boundary statement;
- exact test commands and counts;
- next step toward local Postgres.

Update this card with a closing report.

## Closed Scope

- No live Postgres / DSN / DDL.
- No new decision arm.
- No effect execution in `.ig`.
- No capability id / operation / scope in app-authored files.
- No runner async productization.
- No queue/job/export semantics.
- No canon claim.

## Suggested Next

If P7 lands cleanly, open:

```text
LAB-TODOAPP-API-LOCAL-POSTGRES-P8
```

with a real local-Postgres gated proof, using the now-structured write payload.
