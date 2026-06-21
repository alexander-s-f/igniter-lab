# LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P6 - Preserve structured write intents across InvokeEffect

Status: CLOSED
Lane: standard / TodoApp API / effect-host
Type: readiness / design
Delegation code: OPUS-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P6
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-TODOAPP-API-READ-WRITE-E2E-P5` stitched the fake-host read and write seams into one product-shaped
proof, but it left one honest blocker:

```text
InvokeEffect.input is string-only, so the app-authored WriteIntent cannot cross the web/effect-host seam as
a structured value.
```

Today that is fine for proving target/key/receipt/replay shape, but it is not enough for a real Postgres
write, because `PostgresWriteIntent.values` must remain typed/structured.

This card should decide the smallest way for IgWeb decisions to carry structured effect input while keeping
authority outside `.ig` / `.igweb`.

## Goal

Answer:

```text
How should IgWeb represent and serialize structured effect input so a `.ig` command contract can produce a
PostgresWriteIntent-like value, the handler can emit it, and the host can execute it without string parsing
or app-owned capability authority?
```

This is readiness only. Do not implement the protocol here.

## Verify First

Read live surfaces:

- `lang/igniter-compiler/src/igweb.rs`
  - IgWeb prelude `Decision`
  - `InvokeEffect` arm shape
  - generated handler / idempotency lowering
- `server/igniter-web/src/lib.rs`
  - `map_decision`
  - `InvokeEffect` handling
  - `Render` / `RenderView` precedent for structured payload serialization
- `server/igniter-server/src/protocol.rs`
  - `ServerDecision::InvokeEffect`
  - payload fields and JSON shape
- `server/igniter-server/src/effect_host.rs`
  - `MachineEffectHost`
  - `EffectBridgeConfig`
  - dispatch/input expectations
- `runtime/igniter-machine/src/postgres_write.rs`
  - `PostgresWriteIntent`
  - `WriteValues`
  - idempotency and receipt behavior
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- tests:
  - `server/igniter-web/tests/todo_postgres_api_write_tests.rs`
  - `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
  - `server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs`
- proof docs:
  - `lab-docs/lang/lab-todoapp-api-write-p4-v0.md`
  - `lab-docs/lang/lab-todoapp-api-read-write-e2e-p5-v0.md`
  - `lab-docs/lang/lab-igniter-web-render-decision-p16-v0.md`
  - `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p19-v0.md`

Confirm or correct:

- exact current type of `InvokeEffect.input` in `.ig` prelude;
- exact current type of `ServerDecision::InvokeEffect.input`;
- whether `RenderView` already serializes arbitrary VM records cleanly into JSON;
- whether effect host currently expects string, JSON value, or bytes;
- whether idempotency key stays a separate field and must not be hidden inside input;
- whether app-authored files currently name only logical target, never capability id / operation / scope.

Live code wins over this card.

## Alternatives To Compare

### A. Add a structured `input_json` / `input` value to InvokeEffect

Example shape:

```ig
InvokeEffect { target: "todo-create", input: intent, idempotency_key: req.idempotency_key }
```

where `input` can be a record value serialized by the VM. This is likely the preferred direction if the Rust
protocol can carry `serde_json::Value`.

### B. Keep string input but standardize JSON encoding

App serializes a JSON string and host parses it. This is easy at the Rust boundary but poor for `.ig` because
string escaping and JSON construction are not the intended authoring model.

### C. Split arms: `InvokeEffect` string + `InvokeStructuredEffect`

Avoids breaking current arm, but duplicates semantics and may create two paths to the same authority seam.

### D. Make writes use `Render`-style staged decision

Too broad for this card. Writes already fit final `InvokeEffect`; only the input payload is too narrow.

### E. Host-side command-name convention

The app emits target/key only and host reconstructs values. Reject unless all values are host-known; it moves
domain semantics into host and breaks the boundary.

## Required Questions

Answer directly:

1. Which exact field(s) are string-only today?
2. Can VM-serialized records be carried as `serde_json::Value` without variant tags for normal records?
3. What should happen to existing string-based `InvokeEffect` tests?
4. Is this a source-compatible prelude change, or does it need a second arm?
5. How does idempotency stay separate from structured input?
6. How does the host bind logical `target` to capability config without app-owned authority?
7. How does this map to `PostgresWriteIntent` and `WriteValues`?
8. What are the denial cases (raw SQL, capability id, operation/scope in app input, oversized payload)?
9. What is the smallest implementation card after readiness?
10. Does this unblock local Postgres write, or is another runner/effect-host card still needed?

## Required Deliverable

Create:

```text
lab-docs/lang/lab-igniter-web-structured-effect-input-readiness-p6-v0.md
```

It must include:

- live current protocol shape;
- alternatives comparison;
- recommended v0 representation;
- migration/backward-compat story for existing string input tests;
- exact authority boundary;
- target test matrix for implementation;
- local Postgres dependency chain after this card.

Update this card with a closing report.

## Closed Scope

- No implementation.
- No live Postgres / DSN / DDL.
- No effect execution in `.ig`.
- No capability id / operation / scope in app-authored `.ig` / `.igweb`.
- No raw SQL.
- No runner async productization.
- No queue/job/export semantics.
- No canon claim.

## Suggested Next

If readiness chooses a representation, open:

```text
LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7
```

Then follow with:

```text
LAB-TODOAPP-API-LOCAL-POSTGRES-P8
```

only after structured write intent crosses the seam and fake-host tests prove typed values survive.

---

## Closing Report (2026-06-20)

**Outcome: PROCEED with Alternative A.** Deliverable:
`lab-docs/lang/lab-igniter-web-structured-effect-input-readiness-p6-v0.md` (all 10 questions answered against
live code).

**Headline finding — the seam is narrower than the blocker stated:**
- Rust protocol `ServerDecision::InvokeEffect.input` is **already `serde_json::Value`** (`protocol.rs:101`),
  and `PostgresWriteIntent { target, values: Value }` with `from_args(&Value)` is **already structured**
  (`postgres_write.rs:46-55`). The *only* string chokepoints are the `.ig` prelude
  `InvokeEffect.input : String` (`igweb.rs:68`) and the web mapper `get_str("input")` (`lib.rs:182`).
- **Proven precedent exists:** `RespondView`/`RenderView` already carry a typed `.ig` **record** across the
  seam as a clean JSON object (`lib.rs:174-178`) — plain records serialize tag-free; only variant values
  carry `__arm`/`__variant`. Structured effect input reuses this exact path.

**Recommendation:** Alternative A (single arm). Re-type prelude `input : String` → an **open structured
record** (reuse Unknown-compat so any app-shaped record is accepted; structure validated host-side, like the
renderer validates `View`); `map_decision` passes `fields.get("input")` through as `Value` (the `RespondView`
pattern). Protocol/host/intent unchanged. Reject B (string-JSON), C (second arm — duplicate seam), D, E.

**Key answers:** idempotency stays a separate field (prelude + protocol), never inside `input`; capability
id/operation/scope/DSN/raw-SQL stay host-side (`target_routes` + `effect_passport` + signed recipe); app
names only logical `target` + `values`. Breaking `.ig` change for the `input` field (String→record) but
receipt/idempotency/replay shapes unchanged → P5 fake-host assertions survive.

**No code changed** (readiness). **Next:** `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7` (prelude + mapper +
fixture migration, fake-host proof that typed values survive target→values). Then — separately gated —
`LAB-TODOAPP-API-LOCAL-POSTGRES-P8` (real DSN/adapter/runner). P7 unblocks the payload; P8 does live
execution.
