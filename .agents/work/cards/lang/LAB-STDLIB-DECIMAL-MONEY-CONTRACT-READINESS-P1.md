# LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1 - exact Decimal contract before implementation

Status: DONE
Lane: igniter-lab / stdlib+VM / foundation-hardening
Type: readiness / numeric contract
Date: 2026-06-27
Skill: idd-agent-protocol
Source: `/Users/alex/dev/projects/igniter/audit/igniter-audit-assimilation-triage-p1.md`

## Agent Onboarding Header

This is readiness/design only. Do **not** change Decimal runtime code here.

The Opus audit and triage confirm Decimal is still a live T0 correctness issue:
the stdlib helper stores `value: i64`, uses unchecked arithmetic, derives raw
`Eq/Ord`, truncates division, and the VM compares Decimal through `to_f64()`.
But Decimal touches language value shape, JSON/SIR representation, VM semantics,
stdlib FFI, old tests, and Todo/report money pressure. Do not rush a mechanical
implementation before the contract is explicit.

## Goal

Define the exact v0 money-safe Decimal contract and split it into implementation
cards.

The output should answer:

```text
what changes now,
what stays representationally compatible,
what diagnostics/errors exist,
which old tests must change,
and which implementation card runs first.
```

## Context

Read first:

```text
/Users/alex/dev/projects/igniter/audit/igniter-audit-assimilation-triage-p1.md
/Users/alex/dev/projects/igniter/audit/igniter-foundation-hardening-next-wave-p1.md
/Users/alex/dev/projects/igniter/audit/igniter-stdlib-core-foundation-audit-p1.md
/Users/alex/dev/projects/igniter/audit/igniter-vm-core-foundation-audit-p1.md
lang/igniter-stdlib/src/decimal.rs
lang/igniter-stdlib/src/lib.rs
lang/igniter-vm/src/value.rs
lang/igniter-vm/src/vm.rs
lang/igniter-vm/tests/vm_tests.rs
```

Also search current Decimal crossing pressure:

```text
rg -n "Decimal|to_text\\(|decimal\\(" lang/igniter-vm lang/igniter-compiler server
rg -n "Decimal|money|amount" lab-docs .agents/work/cards/lang
```

If files have moved, state live paths in the packet.

## Current Authority

- Live Rust code/tests decide current behavior.
- Audit packets are evidence, not authority.
- This card may write only a readiness packet and close itself.

## Closed Surfaces

- No code changes.
- No VM/stdlib implementation.
- No frame-ui/render-html edits.
- No package/server/machine/home-lab/SparkCRM edits.
- No canon `igniter-lang` claim.

## Questions To Answer

1. Should v0 change the **stored Rust representation** to `i128`, or keep the
   public VM/SIR JSON shape as `{ value, scale }` with bounded conversion?
2. What is the maximum supported `scale` and how is `10^scale` bounded?
3. What are the exact checked arithmetic rules for `add/sub/mul`?
4. What is v0 `div`?
   - preserve lhs scale?
   - require explicit rounding mode?
   - postpone division except exact divisible cases?
5. How should `Eq`/`Ord` work across scales (`1.5 == 1.50`, `1.0 < 5.0`)?
6. Should `from_f64` be removed, made fallible, or kept only as explicit helper?
7. What diagnostics/error strings should stdlib and VM surface?
8. Which existing tests encode old wrong behavior and must be changed?
9. Does VM Decimal comparison get fixed in the same card as stdlib arithmetic,
   or a follow-up card?
10. What is the smallest implementation slice that produces real safety without
    destabilizing all Decimal users?

## Alternatives To Compare

Compare at least:

- A: minimal `i64 checked_*` + scale-normalized compare, no representation change.
- B: internal `i128` Decimal with public bounded JSON/SIR compatibility.
- C: full arbitrary-precision Decimal.
- D: split: stdlib checked arithmetic first, VM compare second, div later.
- E: hold all Decimal division until explicit rounding syntax exists.

Score by correctness, compatibility, implementation risk, determinism, and app
pressure.

## Acceptance

- [x] Readiness packet written under:

```text
lab-docs/lang/lab-stdlib-decimal-money-contract-readiness-p1.md
```

- [x] Live current Decimal behavior characterized from source/tests.
- [x] At least five alternatives compared.
- [x] v0 contract states representation, scale bounds, arithmetic, comparison,
      equality, division, and from-f64 policy.
- [x] Old-test updates are named explicitly.
- [x] One or two implementation cards are named with acceptance tests.
- [x] No code changed.
- [x] `git diff --check` clean.

## Expected Next Cards

Likely:

```text
LAB-STDLIB-DECIMAL-MONEY-SAFE-P2
LAB-IGNITER-VM-DECIMAL-EXACT-P2
```

But the readiness packet may rename/split them if live evidence demands it.

## Closing Report

Close with the chosen v0 contract, implementation order, exact docs written, and
confirmation that no runtime code changed.

Closed 2026-06-27:

- Wrote
  `lab-docs/lang/lab-stdlib-decimal-money-contract-readiness-p1.md`.
- Chosen contract: keep public VM/SIR/JSON shape `{ value: i64, scale: u32 }`,
  use checked `i128` intermediates, bound v0 Decimal operations to scale 18,
  keep add/sub same-scale, make mul checked/fallible, make div exact-only and
  lhs-scale-preserving, make Eq/Ord numeric and exact, and remove Float from
  money-safe Decimal paths.
- Implementation order:
  `LAB-STDLIB-DECIMAL-MONEY-SAFE-P2` first, including VM equality/order because
  splitting that later leaves a live money correctness bug; then
  `LAB-IGNITER-COMPILER-DECIMAL-CONTRACT-TYPING-P2` for typechecker/named-call
  alignment.
- Runtime code was not changed in this readiness card.
- Verification: `git diff --check` clean.
