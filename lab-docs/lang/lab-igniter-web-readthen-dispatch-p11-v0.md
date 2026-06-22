# lab-igniter-web-readthen-dispatch-p11-v0

**Card:** `LAB-IGNITER-WEB-READTHEN-DISPATCH-P11`
**Status:** CLOSED
**Date:** 2026-06-22
**Lane:** server / IgWeb / staged reads

---

## Summary

P11 implements the first live staged-read decision surface for IgWeb:

```text
Serve(req) -> ReadThen { plan, then }
host executes QueryPlan through PostgresReadExecutor
host dispatches continuation `then` with rows_json
continuation returns final Decision
```

This is intentionally not `.igweb` sugar. The fixture authors `ReadThen` directly
in `.ig`, and the host intercepts it before `map_decision`.

## Implementation

- `lang/igniter-compiler/src/igweb.rs`
  - Adds `ReadThen { plan : Unknown, then : String }` to the IgWeb prelude `Decision`.
- `server/igniter-web/src/read_dispatch.rs`
  - Adds `StagedReadHost` and `StagedReadResult`.
  - Wraps `CapabilityExecutorRegistry` + `TBackend` and executes read plans through the machine effect path.
- `server/igniter-web/src/lib.rs`
  - Adds `IgWebLoadedApp::dispatch_with_read(req, &StagedReadHost)`.
  - Dispatches entry asynchronously, intercepts `ReadThen`, executes the host read, and dispatches the continuation.
- `server/igniter-web/tests/fixtures/read_then_fixture/read_then_fixture.ig`
  - Fixture app with `FetchTodosEntry` and `FetchTodosContinuation`.
- `server/igniter-web/tests/readthen_dispatch_tests.rs`
  - Feature-gated proof tests under `--features machine`.

## Boundary

Closed surfaces stayed closed:

- no `.igweb` `read ... as ...` syntax
- no parser keyword for `read`
- no live Postgres requirement
- no raw SQL
- no typed row destructuring
- no hidden DB authority in `.ig`
- no background mailbox

Rows cross the continuation seam as `rows_json : String` in v0.

## Verification

Commands run during curation:

```text
cargo test --features machine --test readthen_dispatch_tests
cargo test --features machine
cargo test --test igweb_lowering_tests
git diff --check
```

Key counts:

- `readthen_dispatch_tests`: 6 passed
- `server/igniter-web cargo test --features machine`: 120 passed
- `igweb_lowering_tests`: 11 passed

Important acceptance cases:

- found rows -> continuation -> final `Respond` 200
- empty rows -> continuation-owned 404
- denied source/field fails before adapter
- raw-SQL key is refused before adapter
- staged path runs inside Tokio without nested `block_on`
- fixture has no capability id, DSN, raw SQL, or DB handle

## Notes

`ReadThen` is not added to `igniter-server::ServerDecision`. It is an IgWeb
application-level `Decision` arm intercepted by the machine-enabled IgWeb host.
Transport remains route/domain-free.

The next step is productization: wire staged read and effect execution through the
runner/operator path instead of only direct test harnesses.
