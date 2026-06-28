# LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6

Status: CLOSED (2026-06-28)
Route: standard / main-audit / compiler / purity-effects
Skill: idd-agent-protocol
Depends-On: `lab-docs/lang/lab-igniter-compiler-effect-summary-readiness-p5-v0.md`

## Goal

Implement the first interprocedural effect-summary slice so a `pure` contract
cannot launder IO/effects through a helper `def`.

This closes audit-control-board row A20. The target is compiler diagnostics,
not runtime IO or a new effect system surface.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-effect-summary-readiness-p5-v0.md`
- `lang/igniter-compiler/src/typechecker.rs`
- any call-graph/SCC/Tarjan code in the compiler
- existing effect/purity tests such as
  `lang/igniter-compiler/tests/effect_name_parity_tests.rs`

Known live facts to re-verify:

- current purity checks are local/inline enough to miss transitive helper
  effects;
- the compiler already has some call-graph or SCC machinery that should be
  reused rather than reinvented;
- diagnostics must distinguish direct forbidden effect from transitive helper
  effect if possible.

## Scope

Allowed:

- Add an internal per-definition/contract effect summary.
- Compute a fixpoint over the existing call graph/SCC machinery.
- Make `pure` checks consult transitive summaries.
- Add fixtures where a pure contract calls a helper that performs the forbidden
  effect.
- Update proof docs and implemented surface if current truth changes.

Closed:

- No new public `.ig` syntax.
- No VM/runtime effect execution changes.
- No web/machine host IO wiring changes.
- No broad capability authority redesign.
- No canon `igniter-lang` edits from this lab card.

## Questions To Answer

1. What exact effect categories exist in the current compiler?
2. Does the first slice need one boolean (`has_effect`) or a small enum/set?
3. How are cycles handled: SCC summary or conservative fail-closed?
4. Which diagnostic code is used for transitive effect in a pure contract?
5. What existing tests prove direct effects still behave the same?

## Acceptance

- [ ] Live purity/effect implementation is characterized before editing.
- [ ] A helper/`def` with a forbidden effect called from a `pure contract`
      fails compilation.
- [ ] Direct effect diagnostics still work.
- [ ] Cyclic helper graphs are handled deterministically.
- [ ] Existing compiler tests remain green for unaffected surfaces.
- [ ] Proof packet names the summary model and remaining limitations.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test effect_name_parity_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
git diff --check
```

Adjust exact tests after live source discovery.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-effect-summary-p6-v0.md
```

Packet must include:

- effect categories modeled;
- graph/fixpoint handling;
- direct vs transitive diagnostic examples;
- what remains outside this first slice.

## Closing Report (2026-06-28)

Outcome: **first slice implemented and closed.** A `pure` contract that reaches
`stdlib.IO.*` through an app-local `def` now fails compilation with `OOF-M1`.

What changed (lab only, compiler diagnostics — no canon, VM, or host IO edits):

- `lang/igniter-compiler/src/typechecker.rs`
  - New `compute_ambient_io_summary(functions)` — transitive per-`def` `ambient_io`
    summary. Seeds direct `stdlib.IO.*` (`block_has_io_call` / `expr_has_io_call`,
    mirroring the classifier predicate with full AST coverage incl. `match` / `?`),
    then propagates over the **existing** `collect_fn_calls` graph + `tarjan_sccs`
    (reverse-topological single pass; cycles share one value → deterministic).
  - New enforcement block after the OOF-L4 gate: each `pure` contract's reached defs
    are checked; effectful ones emit `OOF-M1` (sorted/deduped, message names the
    transitive helper path to distinguish it from the direct case).
  - Cross-cutting fix: added the missing `Expr::Try` arm to `expr_collect_calls` so
    `helper(x)?` is a real call edge for both the effect summary and OOF-L4.
- `lang/igniter-compiler/tests/effect_summary_interprocedural_tests.rs` — 7 tests
  (laundering, clean-negative, two-hop transitive, `?`-edge, deterministic cycle,
  observed-scope-guard, direct-IO regression guard).
- `lab-docs/lang/lab-igniter-compiler-effect-summary-p6-v0.md` — proof packet.
- `lab-docs/lang/lab-audit-control-board-v1.md` — A20 → CLOSED (first slice).

Acceptance:

- [x] Live purity/effect implementation characterized before editing (see packet "The Gap").
- [x] A helper `def` with a forbidden effect called from a `pure contract` fails compilation.
- [x] Direct effect diagnostics still work (`direct_io_in_pure_contract_still_flagged`,
      `effect_name_parity_tests`).
- [x] Cyclic helper graphs handled deterministically (twice-run equality test).
- [x] Existing compiler tests green (full suite: 34 binaries, 0 failed).
- [x] Proof packet names the summary model + remaining limitations.
- [x] `git diff --check` passes.
- [x] Card closed with this report.

Verification:

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test effect_summary_interprocedural_tests
  7 passed; 0 failed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
  34 test binaries; 0 failed
cargo test ... --test effect_name_parity_tests --test igweb_lowering_tests
  4 passed / 11 passed
git diff --check  → PASS
```

Deferred (next slice, named in packet): `call_contract("Name")` callee propagation;
richer P5 flag set + `effect_summary` SIR metadata; conservative `unknown_dynamic`
fail-closed rule once a dynamic callee exists.

Note: the working tree contained unrelated in-progress changes from other cards
(`type_ir.rs`, `igniter-web/*`, `LAB-…-TYPE-IR-ENUM-P5`); left untouched.

