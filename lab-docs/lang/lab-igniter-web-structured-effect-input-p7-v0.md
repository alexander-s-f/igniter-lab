# lab-igniter-web-structured-effect-input-p7-v0 — structured InvokeEffect input

**Card:** `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7` · **Delegation:**
`OPUS-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7`
**Status:** CLOSED (lab implementation-proof). Implements **Alternative A** from the P6 readiness: a `.ig`
command contract emits a structured record as `InvokeEffect.input`, the VM serializes it to a clean JSON
object, `igniter-web` passes it through as `serde_json::Value`, and the host builds a
`PostgresWriteIntent` with typed `values` — **no string wrapper, no JSON-string parse, no protocol change,
no new decision arm**. Authority stays host-side. No live Postgres, no canon claim.
**Authority:** Lab tooling (effect-host seam).

## Exact prelude type change

`lang/igniter-compiler/src/igweb.rs`, `variant Decision`:

```diff
- InvokeEffect { target : String, input : String, idempotency_key : String }
+ InvokeEffect { target : String, input : Unknown, idempotency_key : String }
```

`Unknown` is the **open structured-payload sentinel**: a variant field declared `Unknown` accepts any
record/value, validated downstream at the host (never in `.ig`). This required one typechecker relaxation in
`infer_variant_construct` (the variant-field shape check), mirroring the existing **D3** rule in
`structurally_assignable` ("expected `Unknown` accepts any"):

```diff
- if actual_name != expected_name && actual_name != "Unknown" {
+ if actual_name != expected_name && actual_name != "Unknown" && expected_name != "Unknown" {
```

This only *relaxes* (adds an exemption); it never tightens. No existing variant field is declared `Unknown`,
so the only field it opens is `InvokeEffect.input`. `RespondView.view : View` / `RenderView.view :
ViewArtifact` stay nominal and concrete.

## Exact `map_decision` change

`server/igniter-web/src/lib.rs`:

```diff
  "InvokeEffect" => ServerDecision::InvokeEffect {
      target: get_str("target"),
-     input: json!({ "input": get_str("input") }),
+     input: fields.get("input").cloned().unwrap_or(Value::Null),
      correlation_id,
      idempotency_key: { … },
  },
```

This is the verbatim `RespondView` record-pass-through (`fields.get("view").cloned()`). The protocol field
`ServerDecision::InvokeEffect.input` was already `serde_json::Value` — unchanged.

## Migrated fixtures/tests

- `examples/todo_postgres_app/todo_handlers.ig`: both mutating handlers now carry the **whole structured
  intent**:
  ```diff
  - InvokeEffect { target: "todo-create", input: intent.operation, idempotency_key: intent.key }
  + InvokeEffect { target: "todo-create", input: intent,           idempotency_key: intent.key }
  ```
  (`AccountTodoCreate` + `AccountTodoDone`). `intent : WriteIntent` carries
  `operation/target/key/values/correlation_id` — exactly the keys `PostgresWriteIntent::from_args` reads, so
  the typed `values` cross nested. `idempotency_key` stays its own field (`intent.key`).
- `tests/todo_postgres_api_write_tests.rs`: stale "input is a String today" header corrected; **+2 tests**
  (`structured_intent_maps_to_postgres_write_values`, `raw_sql_in_structured_input_is_refused`).
- `tests/todo_postgres_effect_host_tests.rs`: **+1 test** (`structured_input_crosses_as_clean_object`).

## JSON evidence — no string wrapper

The app's create decision `input` (observed live, then asserted):

```json
{"operation":"insert","target":"todos","key":"evt-1","correlation_id":"",
 "values":{"account_id":"7","title":"","done":"false"}}
```

A **clean JSON object** — not `{"input":"<string>"}`, no `__arm`/`__variant` discriminants (plain records
serialize tag-free, per the `RespondView` precedent). Nested `values` preserved.

## Fake-host `PostgresWriteIntent.values` evidence

`structured_intent_maps_to_postgres_write_values`: the VM-serialized intent feeds
`PostgresWriteIntent::from_args(&intent)` directly (no parsing) →

```text
operation = "insert"   target = "todos"   key = "evt-1"
values    = { "account_id": "acct-7", "title": "", "done": "false" }   (structured object, not a string)
```

The typed `values` survive nested + structured — the whole point of P7.

## Receipt / replay evidence

The host execution seam is unchanged: `keyed_create_executes_via_machine_host`,
`keyed_done_executes_via_machine_host`, and `replay_same_key_one_effect` stay green — a second call with the
same idempotency key still performs exactly one write effect (machine dedup), `attempts == 1`. Structured
input did not perturb receipt/replay behavior.

## Authority boundary statement

- **App (`.ig`):** logical `target` + structured `intent` (operation/target/key/values/correlation_id) +
  `idempotency_key`. The structured payload is **data**, never authority.
- **Host:** `target → machine route` binding, capability identity (`effect_passport` + signed recipe),
  operation/scope, and the **raw-SQL refusal** (`from_args` rejects `sql`/`raw_sql`/`query` keys — proven by
  `raw_sql_in_structured_input_is_refused`).
- The authored app contains **no** `capability_id` / `io.postgres` / `passport` / `dsn` / `select ` /
  `raw_sql` (asserted by `handlers_wire_command_contracts_with_no_identity`).

## Test commands & counts

```text
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_api_write_tests   → 4 passed
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests → 6 passed
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_api_read_write_e2e_tests → 2 passed
$ cd server/igniter-web && cargo test                            → 52 passed; 0 failed (no features)
$ cd server/igniter-web && cargo test --features machine         → 72 passed; 0 failed *
$ cd runtime/igniter-machine && cargo test --test postgres_write_tests → 10 passed
$ cd lang/igniter-compiler && cargo test                         → 172 passed; 0 failed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 11 passed
$ git diff --check                                               → clean
```

**\* Pre-existing unrelated flaky test (isolated):**
`tests/todo_postgres_api_read_tests.rs::product_todos_index_found_returns_200` (and its 3 file-siblings)
intermittently panic at the `load_program(...).expect(...)` with
`CompilationError("Multifile resolve errors: [\"missing module declaration … prelude.ig\"]")`. **Root cause:**
the 4 tests run in parallel within one process and write/read a **shared** temp `prelude.ig` keyed only by
pid (`igweb_api_read_p3_<pid>`) — a harness file-I/O race, not a compiler issue. **Confirmed pre-existing:**
with this card's changes `git stash`ed, the full file fails **identically** (~2/5 runs); the P7 read/write
behavior itself is correct (passes when run isolated and in every other suite). A separate fix task was
filed (unique temp dir per test). All P7 tests (write/effect-host/e2e) are stable across repeated runs.

## Next step toward local Postgres

`LAB-TODOAPP-API-LOCAL-POSTGRES-P8` (separately gated — real DSN / adapter / runner). The structured write
payload now crosses the seam and `from_args` builds a typed `PostgresWriteIntent`; P8 swaps the fake executor
for a real local-Postgres adapter behind an opt-in feature. Do not open P8 until this fake-host proof is in.

## Acceptance — mapping

- [x] `.ig` prelude accepts structured record input (`input : Unknown`).
- [x] `map_decision` passes structured input as `serde_json::Value`, no string wrapping.
- [x] Plain record input serializes tag-free.
- [x] Nested record input preserved (`values` sub-object).
- [x] `target` + `idempotency_key` unchanged (idempotency stays its own field).
- [x] Todo/Postgres create + done fixtures use structured input.
- [x] Fake-host proof maps structured input to `PostgresWriteIntent.values`.
- [x] Receipt/replay unchanged.
- [x] App-authored files contain no capability id / operation / scope / DSN / raw SQL.
- [x] RenderView/RespondView behavior green; IgWeb builder/runner tests green.
- [x] `server/igniter-web cargo test` + `--features machine` green (one pre-existing flaky read test isolated).
- [x] `runtime/igniter-machine postgres_write_tests` green (10/0).
- [x] `git diff --check` clean.

---

*Lab implementation-proof (2026-06-21). Structured `InvokeEffect.input` via the open `Unknown` sentinel +
the proven `RespondView` pass-through; typed `values` reach `PostgresWriteIntent` with no string parsing and
no protocol/arm change. One pre-existing harness-race flaky read test isolated (fails identically at baseline,
separate fix filed). Next: LAB-TODOAPP-API-LOCAL-POSTGRES-P8.*
