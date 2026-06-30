# LAB-IGNITER-WEB-TRACE-CORRELATION-READ-FRESHNESS-P58

Status: TODO
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

- [ ] Exact failure path is reproduced or disproved.
- [ ] Chosen fix distinguishes client-supplied vs trace-generated correlation,
      or otherwise makes the replay opt-in rule unambiguous.
- [ ] Explicit client correlation replay still works.
- [ ] Uncorrelated reads are fresh with `trace=false` and `trace=true`.
- [ ] Existing `todo_postgres_smoke.sh` and `todo_demo.sh` either no longer need
      unique read IDs, or their comments/docs state the final truth accurately.
- [ ] `scripts/check_todo_product_surface.sh` still passes.
- [ ] Relevant `cargo test` targets pass (include exact commands in closing).
- [ ] `git diff --check` clean.

## Reporting

Close with:

- the exact provenance rule for correlations;
- the chosen layer and why;
- what scripts/docs changed after the fix;
- regression tests and command output summary;
- any remaining lab-only limitation.
