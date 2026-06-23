# LAB-TODOAPP-API-CREATE-BODY-COMPAT-POLICY-P40 — legacy string-body window

**Date:** 2026-06-23
**Type:** readiness + small doc hardening (NO behavior change)
**Delegation:** OPUS-TODOAPP-API-CREATE-BODY-COMPAT-POLICY-P40
**Depends on:** LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35 (object body landed; legacy string kept)
**Authority note:** lab evidence only — a Todo example-app choice is not global Igniter canon.

## TL;DR recommendation

**Keep the legacy string body for now, but mark it explicitly DEPRECATED (option 2).** Do NOT remove it in
this card — removal is broad churn, not a tiny correction (see §1). This card makes only the safe doc
hardening (relabel legacy "deprecated"; object body is the sole canonical example) and **names the removal
follow-up card**. It also surfaces a live finding: **the operator smoke script is stale/broken** (legacy
body *and* a pre-P36 id assumption) and is flagged for a separate fix.

## 1. Live state (cited)

### The behavior (unchanged since P35)

`ResolveCreateTitle` (`server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`) accepts the v1
object body `{ "title": … }` via `map_get_string(req.body_json, "title")` OR the legacy v0 bare JSON string
body (`req.body` when `body_kind == "string"`); anything else resolves to `""` → 400.

### What still uses / requires string bodies

- **No app/runner path *requires* a string body.** Object body is fully wired end-to-end (P35), proven
  through the real binary by `subprocess_product_command_read_write_replay_e2e`
  (`tests/todo_postgres_local_e2e_tests.rs`, sends `{ "title": "Buy milk via P35" }`).
- **~10 test files still *use* string bodies** (they predate P35): `json!("Buy milk")` appears in
  `todo_postgres_effect_host_tests.rs` (the shared `app_request` helper, line 222),
  `todo_postgres_effect_host_runner_tests.rs:272`, `todo_postgres_api_read_write_e2e_tests.rs:285`,
  `async_machine_runner_tests.rs`, `todo_igweb_serve_e2e_tests.rs`, and others. They are load-bearing for
  the current suite — not a single compat test.
- **The operator smoke `scripts/todo_postgres_smoke.sh` still sends a legacy string body** (`WRITE_TITLE`,
  `--data "\"$WRITE_TITLE\""`, lines 73-74 / 131-134) — and is **additionally broken by P36**: it assumes
  `id == idempotency_key` (`CREATE_KEY` used as the row id for show/done/DB checks, lines 71, 142-156), but
  P36 makes the row id `todo_<surrogate>`. As written it would 404 on show and read 0 create-receipts.
  → flagged for a dedicated fix (object body + minted-id discovery); out of this card's scope.

### Tests that pin the dual contract

- `tests/todo_postgres_app_tests.rs::create_body_contract_object_and_legacy_string` — accepts both
  `{"title":"Buy milk"}` and `"Buy milk"`; rejects the failure matrix. **This is the intentional legacy
  coverage to keep.**
- `tests/todo_error_contract_tests.rs` — invalid-body 400s.

### Response-header capability

`igniter_server::protocol::ServerResponse` carries `pub headers: BTreeMap<String, String>`
(`server/igniter-server/src/protocol.rs:58`), and `ServerResponse::json` already sets `content-type`. So a
`Deprecation`/`Warning` header is technically possible **without a cross-crate change** — but emitting it
*only* for legacy bodies needs the runner to branch on `req.body_kind == "string"` for a create, which is a
small runner behavior addition (option 3), not a doc-only change. Deferred (see §3).

## 2. Options compared

| # | Option | Client impact | Effort / risk | Verdict |
| --- | --- | --- | --- | --- |
| 1 | Keep legacy indefinitely | none | none | ✗ risks accidental permanence (the exact thing this card guards against) |
| 2 | **Keep for the window, mark DEPRECATED in docs** | none | tiny (docs only) | ✓ **recommended** — honest, reversible, no churn |
| 3 | Add a `Deprecation` response header for legacy bodies | clients see a warning | small runner change (branch on `body_kind`); behavior addition | ⚖ viable later; out of this card's closed surface (no behavior change) |
| 4 | Remove legacy now | breaks every string-body caller | **broad** — migrate ~10 test files + the smoke first | ✗ not tiny; needs its own card |
| 5 | Legacy in tests only, drop from product docs | none | small | ✗ leaves docs silent on a still-accepted shape → stale-claim risk |

## 3. Answers to the card's questions

- **Any current path that still *requires* string bodies?** No path *requires* it; object body is fully
  wired. But ~10 test files and the smoke script still *use* it (legacy-by-habit), so it is load-bearing for
  tooling until they migrate.
- **Do response headers allow a deprecation warning without cross-crate changes?** Yes —
  `ServerResponse.headers` is writable in `igniter-web` alone. But scoping it to legacy bodies is a runner
  behavior addition, so it belongs to a future slice, not this no-behavior-change card.
- **Is removing legacy a product break or a cleanup?** A **cleanup** (lab example, no external clients), but
  a *broad* one: it must first migrate the smoke + ~10 test files to object bodies, then delete the legacy
  branch in `ResolveCreateTitle`. Not a tiny safe correction → a named follow-up card.
- **What should the product smoke use as the only canonical request?** The object body
  `{ "title": "…" }`. (The smoke must also be repaired for the P36 minted id — flagged separately.)

## 4. What this card changes (safe doc hardening only)

- `examples/todo_postgres_app/API.md` — legacy section relabeled **"Legacy v0 (deprecated; compatibility
  window)"**; object body remains the canonical/first example; the curl block already leads with the object
  body. No stale claim that object/non-string bodies are categorically invalid (the P35 matrix stands).
- `examples/todo_postgres_app/RUNBOOK.md` — same "deprecated" relabel on the create-body limitation line.
- No `.ig`, runner, prelude, schema, id, or account-existence change. No behavior removal.

## 5. Named follow-up cards

- **`LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL-PXX`** (implementation): migrate the smoke + the ~10
  string-body test files to object bodies, then remove the legacy branch in `ResolveCreateTitle` and the
  `body_kind == "string"` create acceptance. Gate on "no caller left on string bodies."
- **`LAB-TODOAPP-API-SMOKE-P35-P36-REALIGN-PXX`** (test/tooling fix, flagged this session): repair
  `scripts/todo_postgres_smoke.sh` — send `{ "title": … }` and discover the P36 minted id from the list
  response instead of assuming `id == idempotency_key`. Required before the smoke can pass again.
- Optional: **deprecation response header** (option 3) if/when clients need a machine-visible signal.

## 6. Acceptance (this card)

- [x] Chosen compatibility policy stated: **keep + deprecate** (option 2).
- [x] API.md labels object body as canonical.
- [x] API.md labels legacy string body as **kept/deprecated**.
- [x] Product **docs** use object body as the primary example (API.md curl leads with it). The smoke
      *script* is stale/broken (P35 body + P36 id) and is flagged for a dedicated fix — it cannot be
      corrected as a tiny doc-only change in this card.
- [x] Tests still intentionally cover legacy compatibility (`create_body_contract_object_and_legacy_string`).
- [x] No stale claim says non-string/object bodies are categorically invalid.
- [x] Removal recommended later → follow-up card named (§5).
- [x] `git diff --check` clean.

## 7. Honest caveats

- The "object body as the primary smoke request" acceptance is satisfied for **docs** but not for the
  **smoke script**, which is independently broken by P36 and needs a combined fix — deliberately deferred to
  the named follow-up rather than rewritten blind (it requires a live DSN + effect token + server run to
  verify, unavailable to a doc-only card).
- Recommendation is "keep + deprecate," not "remove," precisely because removal is broad (smoke + ~10 tests).
  The deprecation label is the smallest step that prevents the window from becoming permanent by accident.
