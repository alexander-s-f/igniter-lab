# LAB-LANG-RECORD-CONSTRUCTION-IN-LAMBDA-P1 - recover record literals inside lambda bodies

Status: CLOSED
Lane: language / VM eval_ast / science pressure
Type: diagnostic + implementation proof
Delegation code: OPUS-LANG-RECORD-CONSTRUCTION-IN-LAMBDA-P1
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Kuramoto exposed a live language limitation:

```ig
map(nodes, o -> { theta: next_theta, omega: o.omega })
```

or parenthesized record construction inside a lambda parses/typechecks far enough to be tempting, but fails in VM/eval path. The current workaround is to return `Collection[Float]` and let the external driver re-pair `{theta, omega}`.

This card removes that workaround if the fix is local and safe.

## Goal

Make record construction inside lambda bodies work through the real compiler and VM, or produce a precise diagnostic if it is too large for this slice.

Target proof:

```ig
type Oscillator { theta : Float omega : Float }

pure contract Advance {
  input nodes : Collection[Oscillator]
  compute next : Collection[Oscillator] =
    map(nodes, o -> { theta: o.theta + 1.0, omega: o.omega })
  output next : Collection[Oscillator]
}
```

## Verify first

Read:

- `lab-docs/lang/lab-vm-nested-hof-eval-ast-recovery-p3-v0.md`
- `lab-docs/lang/lab-vm-nested-fold-map-reduce-aggregate-p4-v0.md`
- `lang/igniter-vm/src/vm.rs` eval_ast and lambda paths
- record literal tests in compiler and VM
- `igniter-home-lab/apps/emergence/kuramoto/kuramoto_per_omega_tick.ig`
- `igniter-emergence/kernels/kuramoto_per_omega_tick.ig`

Confirm the exact failure mode on current HEAD before editing.

## Implementation guidance

Prefer the smallest eval_ast recovery that reuses existing record literal evaluation semantics. Do not refactor HOFs broadly unless necessary.

If the emitter or typechecker is the real blocker, stop and document it with a targeted next card instead of widening the patch.

## Acceptance

- [x] A minimal map-to-record fixture compiles and runs.
- [x] Record fields preserve expected values and types.
- [x] Nested HOF tests from P3/P4 remain green.
- [x] Existing record literal tests remain green.
- [x] Kuramoto-shaped `Collection[Oscillator] -> Collection[Oscillator]` fixture works.
- [x] Error behavior for malformed record literals is unchanged or improved.
- [x] No syntax change.
- [x] No package/web/machine changes.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-22)

**Verify-first on HEAD decided the card:** record construction inside lambda bodies **already executes** — the
prior wall was the **nested `map`/`sum` coupling** inside the record (fixed by P3/P4 `eval_ast` recovery), not
the record literal. On current HEAD the **parenthesized** form runs, including the full Kuramoto per-ω tick
returning `Collection[Oscillator]` (`[{theta:0.13414709, omega:0.5}, {theta:0.86585, omega:-0.5}]` exact).

**No production code changed.** This card = regression-lock + documentation: new e2e test file
`lang/igniter-vm/tests/record_construction_in_lambda_tests.rs` (2 passed: minimal map-to-record + Kuramoto-shaped),
P3/P4 nested-HOF 5 green, record-literal tests intact, `git diff --check` clean.

**Boundary (honest):** **bare** `o -> { field: … }` parses as a block (`OOF-P0`), so the record literal must be
**parenthesized** `o -> ({ … })`. That parser disambiguation is explicitly out of scope (`No syntax change`);
parens are the supported shape. The `Collection[Float]` + driver re-pairing workaround is now removable.

**Proof doc:** `lab-docs/lang/lab-lang-record-construction-in-lambda-p1-v0.md`. **Next:** simplify the
`kuramoto_per_omega_tick.ig` kernels (home-lab + `igniter-emergence`) to return `Collection[Oscillator]`
directly and drop driver-side re-pairing.

## Closed scope

No record spread, no punning, no pattern matching changes, no collection comprehensions, no scientific result changes.

## Next

After this, simplify the Kuramoto per-omega kernel so the pure `.ig` tick can return `Collection[Oscillator]` directly and the driver no longer owns re-pairing.
