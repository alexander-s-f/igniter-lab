# LAB-IGNITER-WEB-TRACE-CORRELATION-READ-FRESHNESS-P58

Status: DONE
Route: standard / IgWeb product hardening / read freshness
Skill: idd-agent-protocol

## Goal

Resolve the subtle freshness mismatch found during P55:

```text
P23 fixed: no client x-correlation-id => uncorrelated reads run fresh.
trace=true changes: no client x-correlation-id => middleware derives a deterministic correlation from method+path+body.
Read host sees that derived value as explicit => identical GETs can replay a stale read snapshot.
```

P55 worked around this in demo/operator scripts by sending a unique
`x-correlation-id` per logical read. That is acceptable for demo stability, but
the engine/product contract needs one clear rule: **only client-supplied
correlations should opt reads into replay**, while trace-generated correlations
should not accidentally turn ordinary GETs into stale replay.

## Current authority

Read first:

- `.agents/work/cards/lang/LAB-TODOAPP-API-READ-FRESHNESS-P23.md`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-server/src/host.rs`
- `server/igniter-server/src/middleware.rs`
- `server/igniter-web/examples/todo_postgres_app/igweb.toml`
- `server/igniter-web/scripts/todo_postgres_smoke.sh`
- `server/igniter-web/scripts/todo_demo.sh`
- `server/igniter-web/tests/readthen_dispatch_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`

Live code wins. P23 is the semantic baseline, P55 is the symptom/evidence.

## Verify first

Confirm the exact path:

1. `trace=true` with no incoming `x-correlation-id` derives or injects a
   deterministic correlation.
2. That correlation reaches `StagedReadHost` indistinguishably from a
   client-supplied correlation.
3. Identical GETs can replay under trace even though they had no client
   correlation.

If any of these are already false in live code, close as proof-only and update
docs/scripts accordingly.

## Candidate fixes to evaluate

Compare at least three, then choose the smallest correct layer:

- mark request correlation provenance (`client` vs `trace-derived`) and let
  read replay opt in only for `client`;
- make trace correlation response-only/log-only, not an input to read replay;
- change read replay to require an explicit replay marker/header in addition to
  correlation;
- keep script-only unique IDs and document as product contract (likely reject:
  too easy for clients to get stale reads by accident).

Do not weaken explicit retry replay: a client that **does** send the same
`x-correlation-id` for the same read plan should still replay.

## Required proof

Add focused tests that separate all three cases:

1. no client correlation, `trace=false` => same plan runs fresh (P23 baseline);
2. no client correlation, `trace=true` => same plan also runs fresh;
3. explicit client `x-correlation-id`, same plan => replays;
4. distinct plans never collide (P12/P23 regression).

Prefer no-DSN fake/read-host tests for the core rule. If a socket-level test is
cheap, add one to prove middleware provenance survives the request path.

## Boundaries

- No new Todo route.
- No DB schema change.
- No write-idempotency semantics change.
- No broad receipt rewrite unless verify-first proves unavoidable.
- No production claim; this is product-hardening of the lab runner semantics.

## Acceptance

- [x] Exact failure path is reproduced or disproved.
- [x] Chosen fix distinguishes client-supplied vs trace-generated correlation,
      or otherwise makes the replay opt-in rule unambiguous.
- [x] Explicit client correlation replay still works.
- [x] Uncorrelated reads are fresh with `trace=false` and `trace=true`.
- [x] Existing `todo_postgres_smoke.sh` and `todo_demo.sh` no longer need
      unique read IDs — the workaround was removed; both run plain reads.
- [x] `scripts/check_todo_product_surface.sh` still passes.
- [x] Relevant `cargo test` targets pass (commands in closing).
- [x] `git diff --check` clean.

## Closing

### Failure path — reproduced (live)

Confirmed all three steps against the real binary + local Postgres, with NO client
`x-correlation-id`:

1. `trace = true` (the app's `igweb.toml`) + no incoming correlation → `LoadedMiddleware`
   (`src/machine_runner.rs`) derived a deterministic `corr-<hash(method+path+body)>` and
   wrote it into `req.correlation_id`.
2. `StagedReadHost::idem_key_for` (`src/read_dispatch.rs`) saw that value as an explicit
   client correlation → keyed the read receipt `"{corr}:{plan_digest}"`.
3. Two identical GETs shared that key → the second **replayed** the first snapshot.
   Live: `list (empty) → create → list` returned `{"items":[]}` instead of the new row.

### Provenance rule (the fix)

**Only a client-supplied `x-correlation-id` opts a read into replay.** A correlation
synthesized by the trace middleware is tagged with a marker header
`x-correlation-source: trace`; the read host treats a trace-tagged correlation exactly
like *no* correlation (fresh `auto-{n}` key, P23). A client retry that sends its own
`x-correlation-id` (marker absent) still replays.

### Chosen layer — why

**Candidate 1 (mark provenance), implemented as a marker header**, over the alternatives:

- Picked at the **read-host key derivation** + a 1-branch change in the **trace
  middleware**. Smallest layer that fixes the bug without disturbing the authority split.
- *Preserves all observability*: the derived correlation still flows to the response
  echo, the app input (`build_request_input`), and the write/effect receipt — only **read
  replay** ignores it. (Candidate 2 "response/log-only" would have stripped trace
  correlation from write receipts + app input — an observability regression.)
- No `ServerRequest` struct change (no broken construction sites), no receipt/machine
  rewrite, no new route, no schema change.
- Safety direction is robust: the only way to get a stale read is to send a real client
  `x-correlation-id` and repeat the plan — the explicit opt-in. A client can never get an
  *accidental* stale read.

### Changed after the fix

- `src/read_dispatch.rs` — `idem_key_for` honors the marker; added
  `CORRELATION_SOURCE_HEADER` / `CORRELATION_SOURCE_TRACE` consts.
- `src/machine_runner.rs` — `LoadedMiddleware::prepare_request` marks a derived
  correlation, leaves a client one unmarked; added `trace_correlation_provenance_tests`.
- `tests/readthen_dispatch_tests.rs` — added `trace_derived_correlation_runs_fresh`.
- `scripts/todo_postgres_smoke.sh` + `scripts/todo_demo.sh` — **removed** the P55
  unique-correlation-per-read workaround; both now issue plain uncorrelated reads.
- Docs: `examples/todo_postgres_app/API.md` (Reads & freshness), `DEMO.md` §5,
  `IMPLEMENTED_SURFACE.md` read-freshness row — all state the final truth + new tests.

### Regression tests + command output

- `cargo test --features machine --test readthen_dispatch_tests` → 11 pass, incl.
  `uncorrelated_same_plan_reads_run_fresh` (trace=false baseline),
  `trace_derived_correlation_runs_fresh` (trace=true, **the P58 case**),
  `explicit_same_correlation_same_plan_replays` (client retry still replays),
  `distinct_plans_never_collide` (P12).
- `cargo test --features machine --lib trace_correlation_provenance` → 2 pass
  (middleware marks derived, not client).
- `cargo test --features machine` → all suites green.
- `cargo test --features postgres --test todo_postgres_local_e2e_tests
  local_read_after_write_is_fresh_same_process -- --test-threads=1` → 1 pass (live).
- `scripts/todo_postgres_smoke.sh` → 21/21 PASS with plain reads.
- `scripts/todo_demo.sh start|smoke|html` → PASS with plain reads.
- `scripts/check_implemented_surface.sh` / `check_todo_product_surface.sh` /
  `check_todo_demo_surface.sh` → PASS. `git diff --check` clean.

### Remaining lab-only limitation

Product-hardening of the lab runner semantics only — no production claim. The sync
`ServerApp` + `TraceApp` path (`igniter-server/src/middleware.rs`) does not feed a
`StagedReadHost`, so it has no read-replay surface and was left unchanged; if a read host
is ever wired into that path, it should adopt the same marker convention.
