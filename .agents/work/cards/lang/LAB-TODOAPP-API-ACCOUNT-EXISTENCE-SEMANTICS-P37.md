# LAB-TODOAPP-API-ACCOUNT-EXISTENCE-SEMANTICS-P37 - distinguish empty account from missing account

Status: CLOSED — 2026-06-23
Lane: TodoApp API / ReadThen semantics / readiness
Type: readiness packet
Delegation code: OPUS-TODOAPP-API-ACCOUNT-EXISTENCE-SEMANTICS-P37
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

Current list semantics can conflate:

- account exists and has zero todos -> should be `200 []`
- account does not exist -> should be `404`

Earlier hardening accepted the simpler behavior while ReadThen/effect-host productization was still
settling. Now ReadThen is runner-integrated and Todo API is becoming product-shaped, so the semantic
gap deserves a focused design.

## Goal

Design the smallest implementation slice that gives product-correct account existence behavior
without smuggling database knowledge into `.ig` or the generic server.

## Verify first

Read live source and docs:

- Todo read route and continuations in `server/igniter-web/examples/todo_postgres_app`
- `ReadThen` implementation and async runner path in `server/igniter-web/src`
- fake/read host policy and Postgres read executor in `runtime/igniter-machine/src`
- Todo API tests for found/empty/missing behavior
- current `IMPLEMENTED_SURFACE.md` and Todo runbook docs

## Questions to answer

Compare at least these options:

1. two-stage reads: `AccountExists` ReadThen, then `ListTodos`;
2. one query plan that returns an account row plus todo rows;
3. app-level continuation that receives rows plus host metadata;
4. host magic that treats empty rows as missing account;
5. denormalized account-exists fixture/policy for v0 tests only.

Answer:

- Can current `ReadThen` handle a continuation that returns another `ReadThen`, or is runner work needed?
- Should empty result be app-owned 404 only when the query is `FindAccount`, not when it is `ListTodos`?
- What exact `.ig` contracts and host policies would be added?
- What is the failure taxonomy for denied account source vs missing account vs empty todos?
- Which first implementation card is smallest and testable with fake executor?

## Acceptance

- [x] Packet cites live current behavior and tests; no stale status claims.
- [x] At least 5 alternatives compared.
- [x] Recommends one implementation slice with file/test scope.
- [x] Defines expected HTTP matrix: existing+rows, existing+empty, missing account, denied source/field, adapter failure.
- [x] Keeps server generic and DB authority in host policy.
- [x] States whether nested/staged `ReadThen` is required.
- [x] No production code changes except optional doc pointer.
- [x] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-todoapp-api-account-existence-semantics-p37-v0.md
```

## Closed surfaces

- No schema migration in this card.
- No object-body/id-generation changes.
- No hidden host interpretation of product meaning.
- No server route table or DB-specific server logic.

## Closing report

**Date:** 2026-06-23

### Design Findings
Created and verified the readiness packet document:
`lab-docs/lang/lab-todoapp-api-account-existence-semantics-p37-v0.md`

1. **Option Comparison**: Evaluated 5 design options (Two-Stage Reads, One JOIN Query Plan, Host Metadata Continuation, Host Magic 404 on Empty, Denormalized Test Fixture). Recommended Option 1 (Two-Stage Reads) as it keeps the generic server/runner free of database and product knowledge.
2. **Nested `ReadThen` Requirements**: Evaluated `IgWebLoadedApp::dispatch_with_read` in `lib.rs` and confirmed that sequential/nested `ReadThen` execution is not supported today (re-dispatch returns unmapped decision 500). Proposed a clean `loop` solution in `dispatch_with_read` to enable generic nested read capabilities.
3. **Policies & Contracts**: Designed the new `FindAccount` and `CheckAccountThenList` contracts in `.ig` along with a multi-source schema/allowlist block for `host.toml`.
4. **HTTP Matrix Defined**: Defined HTTP responses for existing+rows (200), existing+empty (200), missing account (404), policy denied (403), and adapter error (503/500).
5. **No Code Modification**: Adhered strictly to the card scope by not making any behavior modifications to production code. Verified diff/formatting cleanliness.
