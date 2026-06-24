# LAB-TODOAPP-API-ERROR-ENVELOPE-READINESS-P39 - decide product error envelope

Status: CLOSED (2026-06-23) — readiness packet, NO production code (only the proof doc + an optional
one-line API.md pointer). Recommendation: PROCEED with the smallest app-scoped slice — a typed IgWeb
prelude `RespondError { status, error: ApiError{code,message} }` (mirrors the proven RespondView typed-body
pattern) for app-AUTHORED errors only; host read/write shapes stay as-is (write outcomes carry
status/detail/correlation_id/result that a flat envelope would lose — cited ingress.rs:111-120). `code`
values owned by the app; prelude owns only the shape (IgWeb framework, not igniter-server/canon). Defer the
global protocol envelope (option 4). 5 options compared; Todo code taxonomy defined; follow-up
RespondError implementation slice files/tests named (incl. a separate igweb.rs lowering follow-on for
compiler-generated guard errors). Proof:
`lab-docs/lang/lab-todoapp-api-error-envelope-readiness-p39-v0.md`. `git diff --check` clean.
Lane: TodoApp API / product polish / error contract
Type: readiness packet
Delegation code: OPUS-TODOAPP-API-ERROR-ENVELOPE-READINESS-P39
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P20 stabilized and documented the current Todo API error contract. It deliberately did **not** force a
global envelope because live responses have two owner-shaped families:

- app-owned `Respond` errors: `{"body":"..."}`;
- host/runner errors: `{"error":"..."}` or effect outcome objects.

That was the correct hardening step then. Now that P35/P36 made create bodies and ids product-shaped,
we should decide whether a product-level envelope is worth introducing, and where it belongs.

Candidate product envelope:

```json
{
  "error": {
    "code": "invalid_create_body",
    "message": "create body must provide a non-empty title"
  }
}
```

## Goal

Produce a readiness/design packet that decides the smallest safe path for Todo API error-envelope
polish without accidentally turning an example-app choice into global Igniter canon.

## Verify first

Read live source and tests:

- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/machine_runner.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `runtime/igniter-machine/src/ingress.rs`
- `server/igniter-web/tests/todo_error_contract_tests.rs`
- `server/igniter-web/tests/todo_postgres_*`
- P20 proof doc and closing report

## Questions to answer

Compare at least these options:

1. **Todo-local app envelope only** — app-owned errors return structured JSON string / new app decision,
   while host errors stay current.
2. **IgWeb prelude `RespondError` variant** — app can return typed error object; `map_decision` maps it.
3. **Runner-level normalization** — Todo runner wraps app/host errors into a product envelope at boundary.
4. **Global server/protocol error envelope** — all `ServerResponse` errors normalize across crates.
5. **Do nothing now** — keep current owner-shaped contract, improve docs/tests only.

Answer:

- Which layer owns product error `code` values?
- Can `.ig` author structured error objects without stringly JSON today?
- Would host-owned effect outcomes lose useful status/detail if normalized?
- What is the migration/compatibility risk for existing tests/apps?
- What first implementation slice is small enough for the next implementation card?

## Acceptance

- [x] Packet cites live current error mappings and tests.
- [x] At least 5 alternatives compared.
- [x] Recommends one path: proceed / defer / no-op.
- [x] Defines a concrete code taxonomy for Todo errors if proceeding.
- [x] Keeps host secrets and raw SQL out of every proposed body shape.
- [x] Separates Todo product contract from global Igniter canon.
- [x] Names exact files/tests for the next implementation slice.
- [x] No production code changes except optional doc pointer.
- [x] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-todoapp-api-error-envelope-readiness-p39-v0.md
```

## Closed surfaces

- No implementation in this card.
- No global `igniter-server` protocol change unless the packet explicitly justifies it as a future card.
- No rewrite of machine effect outcome receipts.
- No body-contract/id/account-existence behavior changes.
