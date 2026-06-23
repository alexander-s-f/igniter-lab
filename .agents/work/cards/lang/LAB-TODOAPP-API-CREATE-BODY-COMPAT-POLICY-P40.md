# LAB-TODOAPP-API-CREATE-BODY-COMPAT-POLICY-P40 - decide legacy string body window

Status: DONE (2026-06-23) — readiness + small doc hardening, NO behavior change. Policy: KEEP legacy
string body for the compatibility window but mark it DEPRECATED (object body is the sole canonical shape).
Removal deferred (broad: ~10 test files + the smoke still use string bodies) → named follow-up
LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL. Hardened: API.md + RUNBOOK relabel legacy "deprecated", object
body canonical. Live finding flagged: scripts/todo_postgres_smoke.sh is stale/broken (legacy body AND a
pre-P36 id==idempotency_key assumption) → separate fix task spawned. Proof:
`lab-docs/lang/lab-todoapp-api-create-body-compat-policy-p40-v0.md`. `git diff --check` clean.
Lane: TodoApp API / product polish / compatibility
Type: readiness + optional doc/test hardening
Delegation code: OPUS-TODOAPP-API-CREATE-BODY-COMPAT-POLICY-P40
Date: 2026-06-23
Skill: idd-agent-protocol

## Context

P35 made the preferred create body product-shaped:

```json
{ "title": "Buy milk" }
```

It intentionally kept the legacy v0 JSON-string body working:

```json
"Buy milk"
```

That compatibility window is useful while agents and tests converge, but it should not become permanent
by accident. We need an explicit policy: keep, warn, deprecate, or remove.

## Goal

Decide and document the compatibility policy for legacy create string bodies. If the safe answer is
already obvious from live tests/docs, make the small doc/test update in this card. If removal is
recommended, do **not** remove behavior here; open the implementation card.

## Verify first

Read live source and tests:

- `lab-docs/lang/lab-todoapp-api-create-object-body-p35-v0.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/RUNBOOK.md`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_app_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- any product smoke/check script for Todo API

## Questions to answer

Compare:

1. keep legacy string body indefinitely;
2. keep for lab compatibility, but mark deprecated in API.md;
3. add response header / warning surface for legacy clients;
4. remove legacy string body now;
5. move legacy support into tests only (not product docs).

Answer:

- Is there any current app/test/runner path that still requires string bodies?
- Do current response headers allow a deprecation warning without cross-crate changes?
- Is removing legacy support a product break or a cleanup?
- What should the product smoke use as the only canonical request?

## Acceptance

- [x] Packet or closing report states the chosen compatibility policy.
- [x] API.md clearly labels object body as canonical.
- [x] API.md clearly labels legacy string body as kept/deprecated/removed.
- [x] Product smoke/docs use object body as the primary example.
- [x] Tests still intentionally cover legacy compatibility if it remains supported.
- [x] No accidental stale claim says non-string/object bodies are categorically invalid.
- [x] If removal is recommended, a follow-up implementation card is named.
- [x] `git diff --check` clean.

## Proof

Preferred proof doc:

```text
lab-docs/lang/lab-todoapp-api-create-body-compat-policy-p40-v0.md
```

## Closed surfaces

- No behavior removal unless explicitly justified as a tiny safe doc/test-only correction.
- No error-envelope redesign.
- No request prelude changes.
- No schema/id/account-existence changes.
