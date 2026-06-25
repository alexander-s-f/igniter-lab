# LAB-IGNITER-DATA-PROJECTION-BOOT-DIAGNOSTIC-P8

Status: CLOSED (2026-06-25) — build/check-time structural diagnostic `implemented`; dynamic drift stays first-dispatch (not over-claimed)
Route: standard / implementation proof
Skill: idd-agent-protocol

## Goal

Promote the static part of typed `ReadThen` projection reconciliation from P7's request-time guard into a
boot/build diagnostic where the runner can prove the route/app is structurally invalid before binding a
listener.

P7 already routes typed continuations from compiled metadata and reconciles host field policy against app row
types before continuation dispatch. It honestly left timing as request-time / first-dispatch because the
runtime `ReadThen.plan.source` may be dynamic. P8 should add the smaller structural pass that is possible
without guessing dynamic values.

## Current Authority

Read first:

- `lab-docs/lang/lab-igniter-data-projection-boot-reconciliation-p7-v0.md`
- `server/igniter-web/src/read_continuation.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/runner_diag.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/tests/typed_readthen_tests.rs`
- `server/igniter-web/tests/runner_tests.rs`
- `server/igniter-web/tests/igweb_serve_diagnostics_tests.rs`

Live code wins over this card. Do not route around P7; build on it.

## Problem

P7 can fail closed on:

- malformed continuation shape (`rows_json` and `rows`, scalar `rows`, unrecoverable row type);
- host/app row kind drift after a runtime `source` is known;
- per-request row materialization mismatch.

But the first category is independent of any database source. It can be reported as a runner diagnostic before
serving. The second category is partially boot-checkable only when a static source can be recovered from the
app/fixture/host binding; otherwise it must remain first-dispatch.

## Verify-First Questions

Answer in the proof doc:

1. Which app contracts are reachable as `ReadThen.then` targets from static compiled metadata?
2. Can the host enumerate every continuation contract and classify it with `classify_continuation` without
   executing the app?
3. Which invalid shapes are source-independent and therefore true boot diagnostics?
4. Is there any reliable static source/projection metadata today, or is plan.source still runtime-only?
5. Where should the diagnostic live: `runner_diag`, `build_app_dir`, `serve_loaded`, or a small explicit
   `validate_read_continuations` helper?
6. How does this surface through:
   - `igniter check`;
   - `igweb-serve --check`;
   - `igweb-serve` before binding?

If source/projection cannot be recovered statically, do **not** fake it. Keep policy-vs-row drift as
first-dispatch and say so.

## Implementation Bias

Add a small validation helper, not a new schema language:

```text
validate_read_continuations(machine) -> Vec<RunnerDiagnostic>
```

The helper may:

- scan registered contracts;
- classify continuation shapes using P7 metadata;
- emit diagnostics for source-independent invalid shapes;
- optionally validate static shapes that are truly recoverable from existing metadata.

It must not:

- parse authored `.ig`;
- infer contract purpose from names;
- execute a contract;
- create a sidecar schema file;
- require live Postgres.

## Boundary

Allowed:

- Narrow edits in `server/igniter-web`.
- A focused invalid typed-continuation fixture.
- Runner/CLI diagnostic tests.
- Proof doc in `lab-docs/lang/`.
- Update this card with closing report.

Closed:

- No `.igweb` syntax change.
- No new `Decision` arm.
- No live DB.
- No source parsing / regex over authored `.ig`.
- No policy semantics change.
- Do not remove P7 request-time reconciliation; it remains the authoritative guard for dynamic source cases.

## Required Proof Doc

Create:

`lab-docs/lang/lab-igniter-data-projection-boot-diagnostic-p8-v0.md`

Include:

- exact boot-checkable subset;
- exact remaining first-dispatch subset;
- diagnostic code/string chosen;
- how `check` and `serve` behave;
- tests and command counts.

## Acceptance

- [x] Invalid continuation shape is caught before listener bind. — machine-mode validates before `TcpListener::bind`; `cli_check_reports_projection_schema_invalid`
- [x] `igniter check` or equivalent reports the same diagnostic. — `igweb-serve check` exit 12 + `[PROJECTION_SCHEMA_INVALID]`; `check_app_dir` → `RunnerError::ReadContinuation`
- [x] Diagnostic has a stable code/message suitable for CI. — `DiagCode::ProjectionSchemaInvalid` / `"PROJECTION_SCHEMA_INVALID"` (exit 12)
- [x] Valid P7 typed and legacy fixtures remain green. — `valid_fixture_has_no_boot_diagnostics`, regressions green
- [x] Dynamic source/policy reconciliation remains first-dispatch and is not over-claimed. — doc §"remaining first-dispatch subset"; P7 `dispatch_with_read` untouched
- [x] No authored `.ig` source parsing. — only `machine.registry` metadata (input_ports + type_defs)
- [x] No live Postgres requirement. — fake adapter / no DB
- [x] `cargo test --features machine --test typed_readthen_tests` green. — 9 passed
- [x] Relevant runner/diagnostic tests green. — runner_diag 12, runner_tests 17, igweb_serve_diagnostics 9
- [x] Full `server/igniter-web cargo test --features machine` green. — no FAILED; non-machine build/test-compile also green
- [x] `git diff --check` clean.

## Closing Report (2026-06-25)

**Files changed:**
- `src/runner_diag.rs` — `DiagCode::ProjectionSchemaInvalid` (`"PROJECTION_SCHEMA_INVALID"`, exit 12) + classify mapping + ALL_CODES.
- `src/read_continuation.rs` — `validate_read_continuations(machine) -> Vec<RunnerDiagnostic>`.
- `src/lib.rs` — `IgWebLoadedApp::validate_read_continuations`; `RunnerError::ReadContinuation`; `check_app_dir` runs the scan (machine-gated, fail-closed).
- `src/bin/igweb-serve.rs` — `check` exits with taxonomy code; machine-mode validates before bind.
- `tests/fixtures/invalid_continuation/invalid_continuation.ig` *(new)* — 3 invalid continuations + valid entry.
- `tests/boot_diagnostic_tests.rs` *(new)* — 6 tests (scan / check_app_dir / CLI).
- `lab-docs/lang/lab-igniter-data-projection-boot-diagnostic-p8-v0.md` *(new)* — proof doc.

**Boot vs request-time boundary:** boot/check = structural, source-INDEPENDENT (both rows_json+rows;
scalar/non-collection rows; `Collection[<AppRow>]` with unrecoverable row type or a field with no v0 landing).
Request-time (P7, unchanged) = source-DEPENDENT (host-kind ⇎ row-type drift → 500; row materialization
mismatch → 502). The boundary is the runtime `plan.source`, which has no static metadata today (built
dynamically in contract bodies) — so dynamic drift is honestly NOT moved to boot.

**Diagnostic example:** `igweb-serve: [PROJECTION_SCHEMA_INVALID] read continuation \`BadScalarRows\`: element
must be a record type, not a scalar`.

**Tests + counts (`--features machine`, DB-free):** `boot_diagnostic_tests` **6**; regressions `runner_diag`
**12**, `runner_tests` **17**, `igweb_serve_diagnostics_tests` **9**, `typed_readthen_tests` **9**,
`typed_row_crossing_tests` **9**, `readthen_dispatch_tests` **10**; full igniter-web suite green; non-machine
build + test-compile green; `git diff --check` clean.

**Next slice (per Reporting):** **Todo HTML over typed rows** — the data boundary is complete through P8;
recommend `LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P9` (read → typed `Collection[HtmlNode]` demo
over the runner, `meta.truncated` → load-more) ahead of stronger static plan metadata. Optional low-priority:
`LAB-IGNITER-DATA-PROJECTION-STATIC-PLAN-SOURCE` (recover literal-`source` continuations to move residual
drift to boot).

## Reporting

Close with:

- boot vs request-time boundary;
- diagnostic examples;
- exact tests/counts;
- whether the next slice should be Todo HTML over typed rows or stronger static plan metadata.
