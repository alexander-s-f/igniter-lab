# lab-igniter-data-projection-boot-diagnostic-p8-v0

Card: `LAB-IGNITER-DATA-PROJECTION-BOOT-DIAGNOSTIC-P8`
Route: standard / implementation proof · Skill: idd-agent-protocol
Status: implemented (build/check-time structural diagnostic) · dynamic drift remains first-dispatch (not over-claimed) · no canon claim
Date: 2026-06-25
Builds on: P6 typed-row-crossing · **P7 boot-reconciliation** (`lab-docs/lang/lab-igniter-data-projection-boot-reconciliation-p7-v0.md`)

> **Authority boundary.** Lab evidence only. A host-side build/check-time validation that reuses P7's
> compiled metadata; no language/`.igweb`/Decision-grammar/policy-semantics change; **no canon claim.** Does
> not route around P7 — it lifts P7's *source-independent* failures earlier and leaves the rest as P7 had them.

---

## Headline

The **source-independent** half of P7's typed-`ReadThen` reconciliation now fails the runner **at build/check
time, before any listener bind**, with a stable `PROJECTION_SCHEMA_INVALID` diagnostic (exit 12). The
**source-dependent** half (host-kind ⇎ row-type drift, which needs the runtime `plan.source`) stays exactly
where P7 left it — a first-dispatch guard — and is *not* over-claimed as boot-checked.

`validate_read_continuations(machine)` scans loaded contracts, classifies each with P7's
`classify_continuation`, and emits a diagnostic for any continuation whose crossing shape is broken
*regardless of which source feeds it*. It surfaces through `igweb-serve check`, through the machine-mode
runner before bind, and through the `check_app_dir` library path.

---

## Verify-first answers

1. **Which contracts are reachable as `ReadThen.then` targets from static metadata?** None are *statically
   bound*: `ReadThen { then: "X" }` is built in a contract body and `then` can be any string. So rather than
   chase `then` literals, the check scans **every loaded contract** and asks "if this were reached as a
   continuation, is its crossing shape structurally valid?" — a superset that needs no dataflow.
2. **Can the host enumerate + classify every continuation without executing the app?** Yes —
   `machine.registry` holds every assembled contract's `input_ports`; `classify_continuation` (P7) reads them.
   No dispatch.
3. **Which invalid shapes are source-independent (true boot diagnostics)?** (a) declares **both** `rows_json`
   and `rows`; (b) `rows` is a **scalar** `Collection[<scalar>]` or a non-collection; (c) `rows :
   Collection[<AppRow>]` whose `<AppRow>` is **unrecoverable** from `type_defs` or has a field with **no v0
   projection landing** (e.g. `Float`). All depend only on the contract + its type defs, never on a source.
4. **Static source/projection metadata today?** None. `plan.source`/`projection` are produced at runtime by
   the contract body (`FetchTypedTodos` → `ListTypedTodos(req.path)`), so host-kind ⇎ row-type drift cannot be
   boot-checked. It stays first-dispatch (P7). Confirmed — not faked.
5. **Where does the diagnostic live?** A small `read_continuation::validate_read_continuations(machine)` helper
   + an `IgWebLoadedApp::validate_read_continuations` method, called from `runner::check_app_dir` and the
   machine-mode binary before bind. No new schema language, no `.ig` parsing.
6. **How it surfaces:** `igweb-serve check <dir>` → exit 12 + `[PROJECTION_SCHEMA_INVALID]` on stderr;
   `igweb-serve --host-config …` → same diagnostic *before* the listener binds; `check_app_dir` →
   `RunnerError::ReadContinuation` (classifies to `DiagCode::ProjectionSchemaInvalid`).

## Exact boot-checkable subset (source-INDEPENDENT)

| Shape | Detected by | Diagnostic |
| --- | --- | --- |
| declares both `rows_json : String` and `rows : Collection[...]` | `classify_continuation` → `Invalid` | `read continuation \`X\`: … declares BOTH …` |
| `rows : Collection[<scalar>]` / `rows : <non-collection>` | `classify_continuation` → `Invalid` | `… element must be a record type, not a scalar` |
| `rows : Collection[<AppRow>]`, `<AppRow>` unknown in `type_defs` | `app_row_shape` → `Err` | `… unknown row type \`<AppRow>\`` |
| `rows : Collection[<AppRow>]`, a field has no v0 landing (e.g. `Float`) | `app_row_shape` → `Err` | `… field \`amount\` has type \`Float\` with no v0 projection landing` |

All other shapes — including a contract that declares **neither** `rows` nor `rows_json` (a normal contract,
classified `LegacyRowsJson` by P7's back-compat default) — are sound and produce no diagnostic.

## Exact remaining first-dispatch subset (source-DEPENDENT)

Unchanged from P7, in `dispatch_with_read`:
- **host-kind ⇎ `<AppRow>`-type drift** (e.g. host `done : Text` vs `TodoRow.done : Bool`) → 500
  `projection_schema_drift`, reconciled when the runtime `plan.source` is known (allowlisted);
- **per-request row materialization mismatch** (missing field / wrong scalar in actual rows) → 502
  `projection_row_mismatch`.

These need a runtime source/rows and so cannot move to boot. Not over-claimed.

## Diagnostic code / string

- New `runner_diag::DiagCode::ProjectionSchemaInvalid` → `as_str()` = `"PROJECTION_SCHEMA_INVALID"`,
  `exit_code()` = **12** (distinct, non-`1`; covered by the existing `codes_have_distinct_nonzero_exit_codes`
  test, which now includes it).
- `RunnerError::ReadContinuation(String)` carries the joined per-continuation messages;
  `classify_runner_error` maps it to `ProjectionSchemaInvalid`.
- CLI render (via `RunnerDiagnostic::Display`): `igweb-serve: [PROJECTION_SCHEMA_INVALID] <message>` — a
  stable, CI-matchable string.

## How `check` and `serve` behave

- **`igweb-serve check <dir>`** (no socket): builds the loaded app, runs the scan; any diagnostic → exit 12 +
  stderr `[PROJECTION_SCHEMA_INVALID] read continuation \`BadScalarRows\`: …`; a sound app → `check ok`, exit 0.
- **`igweb-serve --host-config <…>`** (machine mode): after `build_loaded_app_from_dir`, runs the scan
  **before** `TcpListener::bind`; a diagnostic returns `Err(RunnerDiagnostic)` → `fail()` → exit 12, no socket
  opened.
- **Sync `igweb-serve <dir>`** (no `--host-config`): typed reads never run on this path (no read host; it uses
  `ServerApp::call`/`dispatch`, not `dispatch_with_read`), so the boot scan is not wired there; `check` is the
  universal static gate. Noted honestly.
- **`check_app_dir`** (library): same scan under `#[cfg(feature = "machine")]`; without the feature it is a
  pure dry-build (no typed-read surface compiled).

## Compatibility

P7 typed + legacy fixtures are structurally sound → **zero** diagnostics
(`valid_fixture_has_no_boot_diagnostics`, `check_app_dir_accepts_valid_app`, `cli_check_accepts_valid_app`).
The existing `runner_tests` (17) and `igweb_serve_diagnostics_tests` (9) stay green; the new `DiagCode` is
additive. P7 request-time reconciliation is untouched and remains authoritative for dynamic-source cases.

## Test matrix

`server/igniter-web` — `--features machine`, DB-free.

**`tests/boot_diagnostic_tests.rs` (6):**
- `validate_flags_invalid_typed_continuations` — the invalid fixture yields **exactly 3** diagnostics
  (`BadBothShapes`/both, `BadScalarRows`/record, `BadUnprojectableRow`/Float), all `ProjectionSchemaInvalid`;
  the valid `Serve` entry is not flagged.
- `valid_fixture_has_no_boot_diagnostics` — the P7 typed+legacy fixture → zero.
- `check_app_dir_rejects_invalid_continuations` — `Err(RunnerError::ReadContinuation)`, classifies to
  `ProjectionSchemaInvalid`, names the offending continuation.
- `check_app_dir_accepts_valid_app` — valid app dir passes.
- `cli_check_reports_projection_schema_invalid` — real `igweb-serve check` → exit **12**,
  `[PROJECTION_SCHEMA_INVALID]` on stderr, no `check ok`.
- `cli_check_accepts_valid_app` — real `igweb-serve check` on a valid app → exit 0, `check ok`.

**Regression (green):** `runner_diag` unit (12, incl. the new code), `runner_tests` (17),
`igweb_serve_diagnostics_tests` (9), `typed_readthen_tests` (9), `typed_row_crossing_tests` (9),
`readthen_dispatch_tests` (10); full `igniter-web --features machine` green; non-machine build + test-compile
green; `git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test boot_diagnostic_tests          # 6 passed
cargo test --features machine --lib runner_diag                     # 12 passed
cargo test --features machine --test runner_tests                   # 17 passed
cargo test --features machine --test igweb_serve_diagnostics_tests  # 9 passed
cargo test --features machine                                       # full suite green
cargo build                                                         # non-machine green
```

## Files changed

| File | Change |
| --- | --- |
| `src/runner_diag.rs` | `DiagCode::ProjectionSchemaInvalid` (`"PROJECTION_SCHEMA_INVALID"`, exit 12) + `classify_runner_error` mapping + `ALL_CODES`. |
| `src/read_continuation.rs` | `validate_read_continuations(machine) -> Vec<RunnerDiagnostic>` (scan + classify + `app_row_shape`). |
| `src/lib.rs` | `IgWebLoadedApp::validate_read_continuations`; `RunnerError::ReadContinuation`; `check_app_dir` runs the scan (machine-gated) and fails closed. |
| `src/bin/igweb-serve.rs` | `check` exits with the taxonomy code; machine-mode validates before bind. |
| `tests/fixtures/invalid_continuation/invalid_continuation.ig` *(new)* | three structurally-invalid continuations + a valid entry. |
| `tests/boot_diagnostic_tests.rs` *(new)* | 6 tests across the scan / `check_app_dir` / CLI surfaces. |

## Reporting

- **Boot vs request-time boundary:** boot/check = structural, source-independent (malformed shape; un-projectable
  `<AppRow>`); request-time = source-dependent (host-kind drift → 500; row mismatch → 502). The boundary is the
  runtime `plan.source`, which has no static metadata today (verify-first Q4).
- **Diagnostic examples:** `igweb-serve: [PROJECTION_SCHEMA_INVALID] read continuation \`BadScalarRows\`:
  element must be a record type, not a scalar`; `… \`BadUnprojectableRow\`: row type \`MoneyRow\` field
  \`amount\` has type \`Float\` with no v0 projection landing`.
- **Tests/counts:** `boot_diagnostic_tests` 6; regressions green (runner_diag 12, runner_tests 17,
  diagnostics 9, typed_readthen 9, typed_row_crossing 9, readthen 10); full suite green; diff clean.
- **Next slice:** the data boundary is done through P8 — recommend the next slice be **Todo HTML over typed
  rows** (read → typed `Collection[HtmlNode]` demo, P7's `RespondView` join + the LINK-NODE/HTML-expression
  arc), not stronger static plan metadata. Static `plan.source` recovery would only shrink the small remaining
  first-dispatch drift window and is lower value than shipping the visible read→HTML payoff. A separate
  `…-STATIC-PLAN-SOURCE` card can capture it if a use case demands boot-time drift detection.

## Next cards

- **`LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P9`** — read → typed `Collection[HtmlNode]` Todo list
  over the runner contour, using `meta.truncated` for "load more" (pairs with the HTML-expression / LINK-NODE arc).
- **`LAB-IGNITER-DATA-PROJECTION-STATIC-PLAN-SOURCE`** (optional/low-priority) — recover a static
  `(continuation → source)` binding where a contract builds a literal `QueryPlan.source`, to move the residual
  drift check to boot for those cases.
- **Deferred (named):** typed `Decimal`/`Timestamp` (`value.rs:82-91` bridge — would also give `Float`/Decimal
  a projection landing); nested `Json` → record; `Dataset[T]` (needs user generics); cross-source facts/decoder.
