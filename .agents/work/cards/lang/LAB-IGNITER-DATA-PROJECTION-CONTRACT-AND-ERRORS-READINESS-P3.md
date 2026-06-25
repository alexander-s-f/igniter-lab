# LAB-IGNITER-DATA-PROJECTION-CONTRACT-AND-ERRORS-READINESS-P3

Status: CLOSED (readiness packet delivered 2026-06-25)
Route: standard / architecture readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-data-projection-contract-and-errors-p3-v0.md`.

**Pattern (philosophy + DX):** a continuation input type is a *typed read contract* the host satisfies by
**reconciling it against its schema authority at load time** — the same posture as resolving `*_env`
secrets before bind. The host honors `Collection[<AppRow>]` *by proof, not by trust*.

**Projection contract choice (Q1):** the **continuation input type** `input rows : Collection[<AppRow>]` is
the single declaration point — app writes exactly what `query_engine`/`batch_importer` already write
(`apps/igniter-apps/query_engine/eval.ig:74`). The host derives the spec from the compiled IR
(`lang/igniter-vm/src/compiler.rs:213` — inputs carry `{name,type}`; introspected like
`discover_effect_surface`, `service_loop.rs:67`). Rejected: `row_type` on `ReadThen` (redundant),
`QueryPlan` type name (mixes responsibilities), host-config row-type (wrong authority + forbidden).

**Authority split (Q2):** host = schema authority (`PostgresReadPolicy.field_kinds`,
`postgres_read.rs:296,328`) + reconciliation enforcer; app = row type (advisory mirror,
`todo_handlers.ig:14`) + transform + product semantics. Must match: projection ⊆ allowlist (already enforced)
+ per-field host-kind assignable to `<AppRow>` field type (matrix mirrors `structurally_assignable`
`typechecker.rs:3198` + `text_arg_compatible` `:3567`).

**Error taxonomy headline (Q4/Q5):** **schema drift = boot-time runner diagnostic
`DiagCode::ProjectionSchemaDrift`, fail-closed before bind** (slots into `runner_diag.rs:26-79` scheme),
NOT a per-request status; transient→503; gate denial→403; residual host-promise violation→502 (not 422/500);
empty/not-found stay app-owned 200/404. App business logic never sees schema concerns. Implementation nuance:
boot reconciliation preferred; first-dispatch-cached is the pragmatic v0 fallback (dynamic `ReadThen` plans
make full boot enumeration non-trivial).

**Meta/provenance (Q3):** fixed `DatasetMeta { source, count, truncated }` crosses as a sibling
`input meta` (`truncated` ← `row_limit_clamped` `postgres_read.rs:513`). `effective_limit`/`schema_version`
excluded (v0); digests/receipts/DSN host-only. `Dataset[T]` deferred (no user-record generics).

**No new `Decision` variants (Q6):** confirmed — `ReadThen` unchanged; provenance is data, not control.

**The shortcut explicitly called out:** "just cross records, let the typechecker sort it" skips
reconciliation → re-imports P2 silent-wrong / path-dependent field errors into app runtime. Reconciliation is
the fundamental piece that makes `Collection[AppRow]` a promise rather than a hope.

**Next card:** `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` (host materializer + boot/first-dispatch
reconciliation + `rows`/`meta` crossing; fake-adapter harness; the drift test proves the shortcut wasn't
taken), after queued P4/P5 readiness.

**Boundary honored.** No code / host-config / compiler / runtime / Todo-HTML change; no canon claim. Docs
only (packet + this report). `git diff --check` clean; grep → `/tmp/igniter-projection-contract-errors-grep.txt`
(824 hits).

## Goal

Design the **contract shape** for typed data projection and the **error taxonomy** for projection
mismatches.

P2 answers "can the VM materialize `Collection[AppRow]`?" This card answers:

> How does the host know *which* row type to project, what provenance crosses, and which errors are
> host-owned vs app-owned?

## Current Authority

- P1 packet: Data Projection Boundary recommendation.
- P2 packet: materialization feasibility (read it first if available).
- Live `ReadThen`/host config/read executor source decides actual integration points.

## Questions To Answer

1. Where should the projection target be declared?
   - continuation input type only (`input rows : Collection[TodoRow]`);
   - `ReadThen` carries `row_type`;
   - `QueryPlan` carries a type/schema name;
   - host config maps `source -> row type`;
   - another shape.
2. How does host avoid trusting app too much?
   - app owns record meaning;
   - host owns allowlist, source, field kinds, bounds;
   - what must match between `projection` fields and `AppRow` fields?
3. What provenance crosses?
   - fixed `DatasetMeta { source, count, truncated }`;
   - include `effective_limit`?
   - include `schema_version`?
   - keep `plan_digest`, receipt IDs, DSN/capability host-only?
4. What is the error taxonomy?
   - denied field/source/op;
   - adapter failure;
   - missing/wrong-kind field during typed projection;
   - extra fields;
   - null handling;
   - truncated/clamped reads;
   - product empty/not-found.
5. What HTTP status should typed projection mismatch become in IgWeb?
   - 500, 503, 502, 422?
   - Should it be stable runner diagnostic or per-request host error?
6. Does this need new `Decision` variants?
   - Prefer no, unless evidence says otherwise.
7. What is the smallest implementation after P2?

## Design Bias

Do **not** put schema drift into app business logic. If the host promised `Collection[TodoRow]`, rows
that enter `.ig` should already be total and typed. App validation is for untrusted request/file/API
payloads, not host-owned relational rows.

## Boundary

Allowed:

- Write a readiness packet.
- Update this card.
- Include pseudo-code and error tables.

Closed:

- No code changes.
- No host config format changes.
- No compiler/runtime implementation.
- No Todo HTML implementation.
- No canon claim.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-data-projection-contract-and-errors-p3-v0.md`

Must include:

- recommended declaration point for row type;
- whether `DatasetMeta` crosses and its exact fields;
- mismatch taxonomy and HTTP/runner mapping;
- host/app authority split;
- minimal P4/P-implementation card.

## Verification

Run:

```bash
rg -n "ReadThen|rows_json|carry|HostError|Denied|row_limit_clamped|effective_limit|PostgresReadValueKind|Request" \
  server/igniter-web runtime/igniter-machine lang/igniter-compiler \
  > /tmp/igniter-projection-contract-errors-grep.txt

git diff --check
```

## Acceptance

- [x] Packet exists.
- [x] It chooses where projection target is declared.
- [x] It defines `DatasetMeta` or explicitly rejects it for v0.
- [x] It assigns ownership/status for every mismatch case.
- [x] It keeps schema drift out of app business logic.
- [x] It proposes the next implementation slice.
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- projection contract choice;
- error taxonomy headline;
- meta/provenance choice;
- next card.
