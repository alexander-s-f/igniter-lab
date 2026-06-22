# lab-lang-record-construction-in-lambda-p1-v0 — record literals inside lambda bodies

**Card:** `LAB-LANG-RECORD-CONSTRUCTION-IN-LAMBDA-P1` · **Delegation:** `OPUS-LANG-RECORD-CONSTRUCTION-IN-LAMBDA-P1`
**Status:** CLOSED (implementation proof) — record construction inside a HOF lambda body **already executes**
on current HEAD; the fix landed via the nested-HOF recovery (P3) + nested-fold (P4). This card is a
**regression-lock + documentation**: **no production code change** (the substrate already does it), a new e2e
test, and the honest boundary. **No syntax change, no package/web/machine change.**

## Verify-first on current HEAD (the decisive finding)

Built `igniter-compiler` + `igniter-vm` at HEAD (P3 + P4 landed) and re-confirmed the exact behavior:

| form | result |
|---|---|
| **parenthesized** `map(nodes, o -> ({ theta: o.theta + 1.0, omega: o.omega }))` | **compiles + EXECUTES** → `[{theta:1.0, omega:0.5}, {theta:2.0, omega:-0.5}]` (fields + types preserved) |
| **Kuramoto-shaped** record tick returning `Collection[Oscillator]` (record field contains nested `sum(map(...))` coupling) | **compiles + EXECUTES** → `[{theta:0.13414709, omega:0.5}, {theta:0.86585, omega:-0.5}]` (exact) |
| **bare** `map(nodes, o -> { theta: …, omega: … })` | **parse error** `OOF-P0: Unexpected token: Colon` — a bare `{` after `->` parses as a block, not a record |

**Why the earlier "wall" is gone:** the prior failure (`Unsupported operator: stdlib.collection.map`) was the
**nested `map`/`sum` coupling** inside the record's `theta` field, not the record construction itself. P3
made nested `map`/`sum` execute in `eval_ast`; the record-literal node already evaluated there. With both in
place, the **parenthesized** record literal — including the full per-oscillator Kuramoto tick — runs.

## Outcome

- **Record construction in lambda bodies works (parenthesized).** The Kuramoto per-ω tick can return
  `Collection[Oscillator]` directly; the `Collection[Float]` + external re-pairing workaround is **no longer
  required**.
- **Bare `{…}` stays a parse-as-block** — a parser disambiguation that is explicitly **out of scope**
  (`No syntax change`). The parenthesized form is the supported shape.
- **No production code changed** — the fix is P3/P4. This card adds a regression test that locks the behavior
  so a future `eval_ast`/HOF change cannot silently re-break record-returning kernels.

## Tests & commands

```text
$ cd lang/igniter-vm && cargo test --test record_construction_in_lambda_tests   → 2 passed
$ cd lang/igniter-vm && cargo test --test nested_hof_eval_execution_tests       → 5 passed (P3/P4 intact)
$ cd lang/igniter-compiler && cargo test record                                 → green (record-literal tests intact)
$ git diff --check                                                              → clean (only a new test file added)
```

New: `lang/igniter-vm/tests/record_construction_in_lambda_tests.rs` — e2e (real `igc` + `igniter-vm run`,
sibling-compiler guarded):
- `minimal_map_to_record_executes_with_fields_preserved` — `o -> ({theta: o.theta+1.0, omega: o.omega})`,
  asserts theta incremented, omega carried through, both Float.
- `kuramoto_per_omega_record_tick_executes` — the per-ω tick returning `Collection[Oscillator]`, asserts the
  coupled-dynamics theta values and omega preservation.

## Acceptance — mapping

- [x] A minimal map-to-record fixture compiles and runs (parenthesized).
- [x] Record fields preserve expected values and types.
- [x] Nested HOF tests from P3/P4 remain green.
- [x] Existing record literal tests remain green.
- [x] Kuramoto-shaped `Collection[Oscillator] -> Collection[Oscillator]` fixture works.
- [x] Error behavior for malformed record literals unchanged (no source change).
- [x] No syntax change; no package/web/machine change.
- [x] `git diff --check` clean.

## Deferred / next

- **Bare `{…}`-in-lambda** parser disambiguation (so `o -> { field: … }` need not be parenthesized) — a
  separate grammar slice, out of this card's `No syntax change` scope. Low priority: parens already work.
- **Next (per card):** simplify `kuramoto_per_omega_tick.ig` (home-lab + `igniter-emergence`) to return
  `Collection[Oscillator]` directly, and drop the driver-side `{theta, omega}` re-pairing — a clean follow-on
  now that the substrate supports it. (Determinism/results unchanged; the re-pairing was a workaround, not a
  modelling choice.)

---

*Implementation proof. 2026-06-22. Record construction inside lambda bodies executes on current HEAD
(parenthesized) — the P3/P4 nested-HOF recovery removed the wall; the per-ω Kuramoto tick now returns
`Collection[Oscillator]` directly. Regression-locked with 2 e2e tests; no production code changed; bare
`{…}`-as-block left to a future grammar slice per `No syntax change`.*
