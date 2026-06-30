# LAB-STDLIB-DECIMAL-MONEY-SAFE-P2 - implement the chosen Decimal v0 contract

Status: DONE
Lane: igniter-lab / stdlib+VM / foundation-hardening
Type: implementation / Decimal correctness
Date: 2026-06-27
Skill: idd-agent-protocol
Depends-On: `LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1`

## Agent Onboarding Header

Do **not** start this card until
`LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1` is closed and its proof packet
names this implementation slice.

This card exists so the next agent has a prepared landing zone, but the
readiness decision owns the exact contract. If this card disagrees with the
readiness packet, the readiness packet wins.

## Goal

Implement the chosen Decimal v0 contract from:

```text
lab-docs/lang/lab-stdlib-decimal-money-contract-readiness-p1.md
```

Expected direction from audit, pending readiness confirmation:

- checked Decimal arithmetic;
- scale-normalized `Eq`/`Ord`;
- no silent wrap/truncate;
- deterministic VM Decimal compare/equality with no `to_f64()`;
- old tests updated away from wrong behavior.

## Context

Read first:

```text
.agents/work/cards/lang/LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1.md
lab-docs/lang/lab-stdlib-decimal-money-contract-readiness-p1.md
lang/igniter-stdlib/src/decimal.rs
lang/igniter-stdlib/src/lib.rs
lang/igniter-vm/src/value.rs
lang/igniter-vm/src/vm.rs
lang/igniter-vm/tests/vm_tests.rs
lang/igniter-vm/tests/stdlib_to_text_tests.rs
```

## Current Authority

- The closed P1 readiness packet decides contract details.
- Live source/tests decide behavior.

## Closed Surfaces

- Do not edit frame-ui/render-html.
- Do not edit compiler/parser/package/server/machine/home-lab/SparkCRM.
- Do not change Float formatting or `to_text(Float)`.
- Do not introduce arbitrary precision unless P1 explicitly chose it.
- Do not change canon `igniter-lang`.

## Implementation Boundaries

Expected first slice, unless P1 says otherwise:

1. Make Decimal arithmetic checked.
2. Replace raw derived equality/ordering with numeric scale-normalized behavior.
3. Replace VM Decimal comparison/equality paths that use `to_f64()`.
4. Update tests that currently encode truncating division / old compare behavior.

If P1 chooses to split stdlib and VM into two cards, implement only the portion
assigned to this card and update this card's closing report accordingly.

## Acceptance

- [x] Tests prove checked `add/sub/mul` do not wrap.
- [x] Tests prove `Decimal(15,1) == Decimal(150,2)`.
- [x] Tests prove `Decimal(10,1) < Decimal(5,0)`.
- [x] Tests prove large integer Decimal comparison does not route through f64
      precision loss (`9007199254740993 > 9007199254740992` if supported by the
      chosen representation).
- [x] Division behavior matches P1 contract and old wrong tests are updated.
- [x] Existing Decimal construction / `to_text(Decimal)` tests remain green or
      are intentionally updated per P1.
- [x] Focused tests plus relevant full crate tests:

```text
cargo test -p igniter-stdlib
cargo test -p igniter-vm
```

  If workspace packaging requires narrower commands, record the exact commands.

- [x] `git diff --check`
- [x] Only stdlib/vm Decimal files/tests, proof doc, and this card changed.

## Proof Doc

Write if the implementation crosses both crates or changes old behavior:

```text
lab-docs/lang/lab-stdlib-decimal-money-safe-p2.md
```

## Closing Report

Close with:

- chosen contract reference from P1;
- exact representation and error behavior implemented;
- tests changed from old behavior;
- exact commands/results;
- confirmation no frame-ui/compiler/server/machine/home-lab files changed.

Closed 2026-06-27:

- Contract reference:
  `lab-docs/lang/lab-stdlib-decimal-money-contract-readiness-p1.md`.
- Proof doc:
  `lab-docs/lang/lab-stdlib-decimal-money-safe-p2.md`.
- Implemented: checked `i128` Decimal intermediates with public
  `{ value: i64, scale: u32 }` compatibility; `MAX_DECIMAL_SCALE = 18`;
  checked add/sub/mul; exact-only lhs-scale-preserving div; normalized
  Decimal equality/order in VM bytecode and eval_ast; VM `decimal(value, scale)`
  scale-bound validation.
- Old behavior changed: VM division no longer subtracts scales/truncates;
  `2625@2 / 25@1` now returns `1050@2`; inexact division returns `OOF-DM3`.
- Tests:
  `cd lang/igniter-stdlib && cargo test` passed;
  `cd lang/igniter-vm && cargo test --test vm_tests decimal_ -- --nocapture`
  passed; `cd lang/igniter-vm && cargo test` passed.
- `git diff --check` passed.
- No frame-ui/compiler/server/machine/home-lab/SparkCRM/canon files were edited.
