# Card: LAB-MACHINE-CAPABILITY-IO-COMPENSATION-P12 — effect compensation / `aborted`

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first; P12 is a milestone tail item.

**Status: CLOSED 2026-06-15 — readiness/design + fake-executor proof.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 7 machine tests
(`igniter-machine/tests/capability_io_compensation_tests.rs`); full suite green
(`cargo test --no-default-features`: 119 capability+machine / 128 incl. coordination). Design
doc: `lab-docs/lang/lab-machine-capability-io-compensation-p12-v0.md`.

## Goal (met)

Formalize `aborted` / compensation for host effects: **REVERSE a committed effect** by running a
new opposite action. Distinct from retry (re-attempt failed) and reconcile (read-back unknown).
No external HTTP / SparkCRM / saga engine.

## Must-decide (answered)

1. `aborted` appears only when a `committed` effect is successfully compensated.
2. Only the original authority may compensate (compensator digest must match the receipt's).
3. Terminal update of the original receipt (append `aborted`; committed fact preserved →
   auditable). Separate compensation-action receipt = richer future option.
4. Linked by `correlation_id` (original) + `compensation_correlation_id` (reversal).
5. Compensation `unknown` → does NOT abort; original stays committed; host reconciles. No blind
   reversal/retry.
6. Compensation reverses a SUCCESS (needs `committed`, produces `aborted`); retry re-runs a
   FAILED action; reconcile only READS. Different preconditions, different terminals.
7. Executor declares `is_compensatable()`; `false` models the language `irreversible` modifier →
   refused, compensator never runs.

## Implementation

`compensation.rs`: `CompensatableExecutor { capability_id, is_compensatable, async compensate }`,
`run_compensation(...) -> CompensationResult { Aborted | Unknown | Failed | NotCompensatable |
NotCommitted(state) | AlreadyAborted | AuthorityMismatch | NoReceipt }`, `FakeCompensatableExecutor`.

## Proof (7 tests)

`committed_effect_compensated_to_aborted` (committed fact preserved + corr recorded),
`compensation_unknown_keeps_committed`, `compensation_failure_keeps_committed`,
`irreversible_effect_refuses_compensation` (compensator never runs),
`replay_compensation_does_not_run_twice` (AlreadyAborted), `non_committed_is_not_compensated`
(NotCommitted/NoReceipt), `authority_mismatch_refused`.

## Closed

No external HTTP. No SparkCRM. No background saga scheduler. No automatic compensation policy
(host decides when). No contract-body compensation. Fake executor only.

## Next

- **P13** allowlisted external host + TLS; **P14** SparkCRM executor (forward + compensating
  actions); reconcile-by-`correlation_id`; richer compensation (separate action receipt,
  compensation-scope authority).
