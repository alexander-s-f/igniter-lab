# lab-machine-capability-io-compensation-p12-v0 — effect compensation / `aborted`

**Card:** `LAB-MACHINE-CAPABILITY-IO-COMPENSATION-P12` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail)
**Status:** CLOSED — readiness/design + fake-executor proof. 7 machine tests
(`tests/capability_io_compensation_tests.rs`); full machine suite green
(`cargo test --no-default-features`: 119 capability+machine / 128 incl. coordination).
**Boundary held:** no external HTTP, no SparkCRM, no background saga scheduler, no automatic
compensation policy, no contract-body compensation.

## The three operations, finally distinct

```text
retry        (P8/P9): re-attempt a FAILED action so it succeeds
reconcile    (P7):    DETERMINE the truth of an `unknown` (read-back; never acts)
compensation (P12):   REVERSE a SUCCEEDED action by running a new, opposite action
```

Compensation is the only one that acts on a `committed` effect.

## Must-decide answers

**1. When does `aborted` appear?** Only when a `committed` effect is successfully compensated
(reversed). `aborted` was reserved in P6a; P12 is what produces it. (A pre-commit host abort
could also reach `aborted`, but P12's path is compensation of a commit.)

**2. Who may launch compensation?** The original authority. The compensator's
`passport.authority_digest()` must match the original receipt's `authority_digest` (same
continuity rule as replay/drain) → else `AuthorityMismatch`, nothing run. (Richer
"compensation-scope" authority is future.)

**3. Compensation receipt — separate or terminal update?** **Terminal update of the original
receipt**: an `aborted` fact is appended at the original key; the original `committed` fact is
preserved (append-only) so the history stays auditable. The aborted fact records
`compensated=true` + `compensation_correlation_id`. (A separate compensation-action receipt is a
richer future option; the minimal form keeps one auditable timeline per effect.)

**4. Linked via `correlation_id`.** The aborted fact carries the original receipt's
`correlation_id` (preserved by copy) plus a `compensation_correlation_id` for the reversal — so
forward effect ↔ reversal is traceable.

**5. What if compensation is itself unknown?** It does **NOT** abort. The original stays
`committed`; `run_compensation` returns `Unknown`. No blind reversal/retry — the host must
reconcile whether the reversal actually happened (same epistemic discipline as writes).

**6. How does compensation differ from retry/reconcile?** Compensation runs a NEW opposite
action against a SUCCEEDED effect; retry re-runs the SAME action against a FAILED one; reconcile
only READS to resolve an unknown. Compensation requires `committed`; the others require
failed/unknown. Compensation produces `aborted`; reconcile produces committed/permanent_failure;
retry produces committed/exhausted.

**7. Compensatable vs irreversible?** The executor declares `is_compensatable()`. `false` models
the language `irreversible` modifier — compensation is refused (`NotCompensatable`) and the
compensator never runs. (A contract whose effect is `irreversible` exposes a non-compensatable
executor.)

## Implementation

`igniter-machine/src/compensation.rs`:
- `CompensatableExecutor { capability_id, is_compensatable, async compensate(original_receipt,
  corr) -> EffectOutcome }` — separate from `CapabilityExecutor` (forward path untouched).
- `run_compensation(receipts, clock, passport, compensator, capability_id, idempotency_key,
  comp_corr) -> CompensationResult` — loads the original receipt, checks authority + state, runs
  the compensator iff compensatable, and on success appends an `aborted` fact.
- `CompensationResult ∈ { Aborted | Unknown | Failed | NotCompensatable | NotCommitted(state) |
  AlreadyAborted | AuthorityMismatch | NoReceipt }`.
- `FakeCompensatableExecutor` (Reverse/Deny/Timeout; `irreversible()` variant).

## Proof (7 tests, `tests/capability_io_compensation_tests.rs`)

| claim | test |
|---|---|
| committed effect → compensation → aborted; committed fact preserved (auditable); corr recorded | `committed_effect_compensated_to_aborted` |
| compensation unknown → original stays committed | `compensation_unknown_keeps_committed` |
| compensation denied/failed → original stays committed | `compensation_failure_keeps_committed` |
| irreversible effect refuses compensation (compensator never runs) | `irreversible_effect_refuses_compensation` |
| replay compensation runs exactly once (2nd = AlreadyAborted) | `replay_compensation_does_not_run_twice` |
| only a committed effect is compensatable (unknown → NotCommitted; absent → NoReceipt) | `non_committed_is_not_compensated` |
| only the original authority may compensate | `authority_mismatch_refused` |

## Closed (held)

No external HTTP. No SparkCRM. No background saga scheduler. No automatic compensation policy
(the host decides when to compensate). No contract-body compensation. Fake executor only.

## Next route

- **P13** allowlisted external host + TLS (the `with_allowed_hosts` mechanism already exists);
- **P14** SparkCRM API executor (forward + compensating actions per its API);
- reconciliation by `correlation_id` (now first-class) — close the P7 same-value caveat;
- richer compensation: a separate compensation-action receipt; compensation-scope authority;
  a (still host-driven, non-automatic) compensation-on-unknown reconcile loop.
