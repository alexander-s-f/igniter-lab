# TodoApp API — Next Product Slice Readiness (LAB-TODOAPP-API-NEXT-PRODUCT-SLICE-READINESS-P42)

Date: 2026-06-24. Type: readiness packet (planning only; no production code). Lab, not canon.

Grounded in live source read this pass — not stale cards:
[`routes.igweb`](../../server/igniter-web/examples/todo_postgres_app/routes.igweb),
[`todo_handlers.ig`](../../server/igniter-web/examples/todo_postgres_app/todo_handlers.ig),
[`API.md`](../../server/igniter-web/examples/todo_postgres_app/API.md),
[`host.example.toml`](../../server/igniter-web/examples/todo_postgres_app/host.example.toml),
[`IMPLEMENTED_SURFACE.md`](../../server/igniter-web/IMPLEMENTED_SURFACE.md),
`src/lib.rs` (`map_decision`, `surrogate_id`, `build_request_input`), and the live e2e/dispatch tests.

## 1. Current Todo API surface (live)

| Method & path | Handler → mechanism | Implemented today | Notes |
| --- | --- | --- | --- |
| `GET /health` | `Health` → `Respond` | ✅ both modes | plain 200 `ok`. |
| `GET /accounts/:account_id/todos` | `AccountTodoIndex` → **two-stage** `ReadThen` (`FindAccount` → `CheckAccountThenList` → `ListTodosByAccount`) | ✅ machine mode | existing+rows→200; existing+empty→`200 []`; missing account→**404** (P38); denied→403; host err→503. `carry` threads `account_id`; `MAX_READ_HOPS=8`. |
| `GET /accounts/:account_id/todos/:todo_id` | `AccountTodoShow` → `ReadThen` (`FindTodo`) | ✅ machine mode | row→200; absent→404 `todo not found`. |
| `POST /accounts/:account_id/todos` | `AccountTodoCreate` → `InvokeEffect{todo-create}` | ✅ machine mode | object body `{"title"}` (P35, legacy string deprecated P40); host surrogate id `todo_<blake3>` (P36); keyless/blank→400; same-key+diff-body→409; replay→200 dedup. |
| `POST /accounts/:account_id/todos/:todo_id/done` | `AccountTodoDone` → `InvokeEffect{todo-done}` | ✅ machine mode | full-row **upsert** (`INSERT … ON CONFLICT DO UPDATE`), sets `done="true"`, **does not preserve title**; replay→200 dedup. |

Substrate already proven (so a slice that reuses it is cheap):

- `ReadThen` sequential/nested staged reads + opaque `carry`, bounded loop; `StagedReadHost` real Postgres
  read with **multi-source** allowlist (`[postgres.read.*]`, `extra_sources`); read freshness + opt-in replay.
- `MachineEffectHost` real Postgres write for ops **`insert,upsert` only**; ingress dedup gate
  (`dedup_strict`) → 409 conflict; write receipts; bearer passport per effect target.
- Decision arms in `map_decision`: `Respond`, `RespondView`, `InvokeEffect`, `Render`, `RenderView`
  (**no `RespondError`**). Host transport signals: `body_json`/`body_kind`, `surrogate_id`, `map_get_string`.

## Questions answered

1. **Usable end-to-end today:** full account-scoped Todo CRUD-minus-DU — health, list (with
   exists-vs-empty), show, create, mark-done — over real local Postgres with idempotency/replay/conflict.
2. **Most value, least new substrate:** the **error envelope** (P39 design already locked) — it touches no
   DB/adapter/predicate substrate, only a new decision arm + prelude type, and improves *every* endpoint.
3. **Forces new language/runtime work:** `delete` (new DELETE write op + adapter path), `update/PATCH`
   (partial-update adapter, today only full-row upsert), `pagination/keyset` (predicate ops beyond `eq`
   + ORDER BY + cursor in the read plan/adapter). `account/auth boundary` forces an identity/claims model.
4. **Improves confidence/operability over feature count:** error-envelope implementation and CI/smoke
   hardening; the former is design-ready and cross-cutting.
5. **Exact next card:** `LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43` (see §3 and §5).

## 2. Candidate comparison

| Candidate | Product value | New substrate forced | Architectural ambiguity | Verdict |
| --- | --- | --- | --- | --- |
| **5. Error envelope impl** | Med-High (uniform `{error:{code,message}}` for every app error; client ergonomics) | **None** — `RespondError` decision arm in `map_decision` + prelude type + `.ig` lowering | **Low** — design locked by P39 | **RECOMMENDED** |
| 2. Delete | Med (CRUD completeness) | **Yes** — new `delete` write op in allowlist + a DELETE path in `TokioPostgresWriteAdapter` (today INSERT…ON CONFLICT only); delete-idempotency semantics | Low-Med | Runner-up (next feature slice) |
| 1. Update / toggle / PATCH title | Med | **Yes** — partial-update adapter (today full-row upsert drops title); toggle-off semantics | Med (PATCH vs full-row) | Parked behind delete |
| 3. Pagination / keyset reads | Med (scales list) | **Yes** — predicate ops `gt/lt` (today `QueryFilter.op = eq` only), ORDER BY, cursor in QueryPlan + read adapter | Med-High (cursor design) | Parked |
| 4. Account / auth boundary | High (real multi-tenant) | **Yes, large** — identity/claims, bearer→account scope mapping; `AccountExists` is fixture logic today | **High** (auth model, canon-adjacent) | Parked (needs its own readiness) |
| 6. CI / product smoke hardening | Low-Med (operability) | None | Low | Ongoing, not a "slice" |
| 7. API docs / client fixture gen | Low-Med (DX) | None-Low | Low-Med | Parked (do after envelope) |

## 3. Recommendation

**Implement the error envelope** — promote the P39 design
(`lab-docs/lang/lab-todoapp-api-error-envelope-readiness-p39-v0.md`) into a real, app-scoped
`RespondError` decision. It is the slice with the best ratio of product value to architectural risk:

- **Zero new substrate.** No DB op, no adapter change, no new read predicate, no migration. It adds one
  decision arm (`RespondError`) to `map_decision`, one typed prelude record (`ApiError{code,message}` +
  `RespondError{status,error}`), and lowers the app's existing 400/404/405 `Respond` errors to it.
- **Cross-cutting.** Every app-authored error gets a stable machine-readable shape, ending the current
  two-families split (`{"body":"…"}` app vs `{"error":"…"}` host) for the app side. Host-owned shapes
  stay unchanged (P39 explicitly keeps write outcomes carrying `status/detail/correlation_id`).
- **Design-locked, low ambiguity.** P39 already compared 5 options and recommended exactly this
  (app-scoped prelude variant; defer the global cross-crate envelope). Implementation is mechanical.
- **Unblocks DX work.** Candidate 7 (client fixtures/OpenAPI-ish) is far cleaner once errors are typed.

Sequence after it: **delete (P44)** as the next user-visible feature (call out the DELETE adapter
substrate up front), then update/PATCH, then pagination. Auth boundary needs its own readiness packet
before any code.

## 4. Rejected / parked candidates

- **Account/auth boundary** — highest value but highest ambiguity and largest new substrate (identity,
  claims, per-account authorization). `AccountExists` is fixture logic today; doing this right is a
  multi-card track, likely canon-adjacent. Park behind a dedicated readiness packet.
- **Pagination/keyset** — needs predicate ops beyond `eq` and ordering/cursor in both the `.ig` QueryPlan
  and the read adapter. Real but not yet pressured (lists are small, `limit:50`). Park.
- **Update/PATCH** — partial update conflicts with the current full-row upsert model; do after delete so
  the write-op surface is extended once, coherently.
- **CI/smoke hardening** — already covered by `check_implemented_surface.sh`,
  `check_todo_product_surface.sh`, and the realigned operator smoke; treat as ongoing maintenance, not a
  product slice.
- **API docs/client fixture gen** — valuable for DX but should follow the typed error envelope.

## 5. Acceptance matrix for the recommended card (`LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43`)

| # | Acceptance criterion |
| --- | --- |
| 1 | A typed IgWeb prelude `RespondError { status : Integer, error : ApiError }` with `ApiError { code : String, message : String }` is added to the shared prelude (`PRELUDE_SOURCE`), not to igniter-server/canon. |
| 2 | `map_decision` (`src/lib.rs`) gains a `RespondError` arm that serializes `{"error":{"code","message"}}` at the given status; existing arms unchanged. |
| 3 | App-authored errors in `todo_handlers.ig` (create-body 400, account-not-found 404, todo-not-found 404; method/route 405 if app-owned) are lowered to `RespondError` with stable `code` values owned by the app. |
| 4 | Host-owned shapes (staged-read 403/503, write-outcome `status/detail/correlation_id`, unbound-target 502) are **unchanged** (no cross-crate change to igniter-server/igniter-machine). |
| 5 | No status-code changes — only error **body shape** changes for app errors; success bodies unchanged. |
| 6 | `tests/todo_error_contract_tests.rs` updated to assert the new `{"error":{"code","message"}}` shape + codes; no DSN/token/SQL leak preserved. |
| 7 | `API.md` Error-contract table updated to the typed envelope; `IMPLEMENTED_SURFACE.md` flips `RespondError` from `designed`/deferred to implemented. |
| 8 | No new DB op, adapter, predicate, or migration. No new runner code beyond the decision arm. `git diff --check` clean. |

## Follow-up

- `LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43` — implement the above (recommended next).
- `LAB-TODOAPP-API-DELETE-P44` — delete slice; call out the DELETE write-op/adapter substrate.
- `LAB-TODOAPP-API-AUTH-BOUNDARY-READINESS-Pxx` — separate readiness before any auth code.
