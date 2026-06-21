# lab-stdlib-statistics-descriptive-p2-v0 — pure-.ig descriptive statistics

**Card:** `LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2` · **Delegation:** `OPUS-STDLIB-STATISTICS-DESCRIPTIVE-P2`
**Status:** CLOSED (implementation proof) — `Mean`/`Variance`/`Stddev` over `Collection[Float]` →
`Option[Float]`, authored as **pure `.ig` contracts** (P1's bias), proven end-to-end through the real
compiler + VM. **No VM builtin** — they compose live `count`/`sum`/`map`/`to_float`/`det_sqrt` (P7/P8/P10).
Empty → `none()`; population variance, two-pass, fixed authored-order. v0 assumes finite input.

## Prerequisite gate (verify-first)

`LAB-STDLIB-NUMERIC-TO-FLOAT-P8` is **CLOSED** and `to_float(Integer)->Float` is live (typecheck arm,
`eval_math_call` source, VM) — so `sum(xs) / to_float(count(xs))` compiles. The P1 gate is satisfied; this
card proceeded (it would otherwise have stopped at a readiness note per its own instruction).

## Implementation home decision

The three statistics are **authored `.ig` contracts** (called by name / `--entry`), **not** bare stdlib
functions. The live stdlib `.ig` files (`math.ig`) are *declarative signatures whose implementation is
Rust-wired*; an authored pure-`.ig` contract is **not** auto-importable as a bare callable. So v0 ships as:
- a **regression test** that compiles the contracts and runs them through the real compiler + VM
  (`lang/igniter-vm/tests/stdlib_statistics_tests.rs`), and
- a reusable **library file** `igniter-home-lab/apps/emergence/lib/statistics.ig` (the research consumer).

Making `mean/variance/stddev` *bare-importable* like `sum` would need either the stdlib Rust-wiring path or a
pure-`.ig` library/import mechanism — that is the **packaging follow-on** (P1's "next" note), deliberately
out of scope here. The functions are *proven* and *reusable by inclusion* today.

## Semantics (exact)

- **Empty:** `none()` (Option, never a sentinel `0`). The `m` mean is **empty-guarded** (`if n==0 {0.0}`) so
  the empty case never even computes a discarded `NaN` in an intermediate `compute`.
- **`mean(xs)`** = `sum(xs) / to_float(count(xs))`.
- **`variance(xs)`** = **population** two-pass: `m = mean`; `sum(map(xs, x -> (x-m)*(x-m))) / to_float(count)`.
  Two-pass `Σ(x−m)²` (not `Σx² − n·m²`) — numerically stable, no catastrophic cancellation. **Population
  `/N`**, not sample `/(N-1)`; sample variance is a future separate function (no ambiguity in v0).
- **`stddev(xs)`** = `det_sqrt(variance)` — the **replay-safe** square root (P5), so `stddev` is
  cross-arch-reproducible to the same story as `det_sqrt`.
- **Finite input:** v0 assumes finite values. A non-finite *element* is not refused (no live `is_finite`
  predicate); the deterministic `det_*` math line already refuses to *produce* non-finite, so data fed from
  it is finite by construction. `is_finite`-based strict refusal is a named follow-on.

## Reduction determinism

All reductions are **fixed authored-order** `sum`/`fold` — **no hidden parallel reassociation.** `mean` and
`variance` are exact rational reductions of the inputs in source order; `stddev` inherits `det_sqrt`'s
determinism. Re-running yields identical results (deterministic by construction).

## Live results (real compiler + `igniter-vm run`)

```text
Mean([1,2,3])     → some(2.0)                  Mean([])     → none()
Variance([1,2,3]) → some(0.6666666666666666)   Variance([]) → none()      (= population 2/3)
Stddev([1,2,3])   → some(0.816496580927726)                               (= det_sqrt(2/3))
```

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_statistics_tests   → 5 passed (mean some/none, variance some/none, stddev det_sqrt)
$ cd lang/igniter-vm && cargo test                                  → green EXCEPT pre-existing unrelated vmg13
$ git diff --check                                                  → clean
```

The tests run through the **real compiler + VM** (compile the `.ig`, `igniter-vm run --entry`), asserting on
the `Resulting Output:` record — not string inspection of source. (The run stdout's bytecode listing names
both `Some`/`None` constructors, so assertions check the result record specifically.)

**Pre-existing unrelated VM failure** (not mine): `vm_candidate_proof_tests::
test_proof_vmg13_local_loops_and_service_loops` — parallel agent's loop/temporal work, fails on a clean tree.

## Acceptance — mapping

- [x] `mean([])` → `none()`; `mean([1,2,3])` → `some(2.0)`.
- [x] `variance([1,2,3])` → population `2/3` (`0.6666666666666666`).
- [x] `stddev([1,2,3])` uses `det_sqrt` → `0.816496580927726`.
- [x] Fixed authored-order reduction stated; no hidden parallel reassociation.
- [x] Pure `.ig` compiles through the real compiler (home decision documented).
- [x] Tests run through real compiler+VM, not only string inspection.
- [x] Empty behavior uses `Option[Float]` (`none`), not sentinel `0`.
- [x] `to_float` used explicitly; no implicit numeric coercion added.
- [x] `git diff --check` clean.

## Files

- `lang/igniter-vm/tests/stdlib_statistics_tests.rs` (new, 5 e2e tests; embeds the `.ig` library).
- `igniter-home-lab/apps/emergence/lib/statistics.ig` (reusable library artifact).

## Blockers for the rest (named)

- **`median`/`percentile`** — need a **sort primitive** (none in `.ig`).
- **`covariance`/`correlation`** — need **paired iteration / `zip`** over two collections.
- **`histogram`** — bucketing (dataframe-ish; out of scope).
- **bare-importable packaging** — a pure-`.ig` library/import mechanism (or Rust-wiring) so these are callable
  like `sum` rather than by `call_contract`/entry.

## Next

If bare-importability is wanted: a small **library-packaging** card. Otherwise the next stats slice is
`covariance`/`correlation` — only after `zip`/paired iteration exists. For the emergence line, these stats now
enable order-parameter summaries and finite-size scaling (`~1/√N`) measurements in the rigor contract.

---

*Implementation proof. 2026-06-21. `Mean/Variance/Stddev : Collection[Float] -> Option[Float]`, pure `.ig`
(no VM builtin), deterministic fixed authored-order two-pass + `det_sqrt`; empty → `none()`; population
variance. Proven through the real compiler + VM: `some(2.0)`, `some(2/3)`, `some(√(2/3))`, empty → `none()`.
5 e2e tests green; `git diff --check` clean. Home = authored contracts (test + home-lab library file);
bare-importable packaging deferred.*
