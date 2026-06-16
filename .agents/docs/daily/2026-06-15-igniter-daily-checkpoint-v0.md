# Igniter Daily Checkpoint — 2026-06-15

## Daily Summary

2026-06-15 was a transition day from language/runtime pressure into a real
machine-host IO architecture. The biggest outcome was not a single feature: it was the
separation of three execution planes that must not be collapsed:

```text
VM              = deterministic execution core
igniter-machine = host boundary / ServiceLoop / capability data-plane
MCP             = agent control/debug plane
```

By the end of the day, runtime fleet evidence reached **RUN-OK 24/25**. The remaining
non-green app is `rule_engine`, which is intentionally governance-gated by dynamic
dispatch / epistemic unknown-state policy rather than a VM/runtime bug.

The second major result was the `igniter-machine` capability IO track. The system moved
from fake executor proof to a real local read/write substrate, while preserving the
boundary: contracts declare effects, the host executes them, receipts are bitemporal
facts, and VM/contract bodies do not perform IO.

## Checkpoints Closed

### Hygiene / Anti-Drift / Protocol

- Doc-navigation protocol was tightened around living docs:
  - `MAP.md` as project entry point.
  - `DELTA-LEDGER.md` in `igniter-gov` as the single canon/lab delta ledger.
  - doc segmentation standard: active crest vs archive.
  - `idd-agent-protocol` source moved to `igniter-gov/agent-protocol`, with runtime
    copies/pointers separated from authority.
- `ledger-reconcile` pass retired stale delta claims, including old compiler/lowering
  gaps that live code had already closed.
- The core anti-drift rule was crystallized: stale docs that say "not implemented" are
  claims, not authority; check `IMPLEMENTED_SURFACE.md` and live code first.

### Fleet / App / Runtime Rechecks

- `APP-RECHECK-WAVE-P12` and follow-up baseline work expanded/confirmed the active fleet.
- New app baselines were closed for:
  - `audit_ledger`
  - `batch_importer`
  - `job_runner`
  - `web_router`
- Runtime rechecks advanced:
  - `LAB-VM-RUN-OK-RECHECK-P1`: **23/25 RUN-OK**.
  - `LAB-VM-RUN-OK-RECHECK-P2`: **23/25 RUN-OK**, no count change.
  - `LAB-VM-RUN-OK-RECHECK-P3`: **24/25 RUN-OK**, `spreadsheet` now green via
    `RunWorkbookDemo`; only `rule_engine` remains non-green and governance-gated.

### VM / Runtime Surface

- `LAB-STDLIB-STRING-CHAR-AT-VM-P1` — CLOSED, **96/96 PASS**. VM now executes
  `stdlib.string.char_at` / `substring` in bytecode and eval_ast paths.
- `LAB-APP-DEMO-ENTRY-WAVE-P1` — CLOSED, **122/122 PASS**. Demo entries added for
  app-side runtime evidence without changing production handlers.
- `LAB-FUNCTION-SIR-RUNTIME-P1` — CLOSED, **105/105 PASS**. App-local `def` functions
  are materialized in SIR and callable from VM eval_ast via a function registry;
  `spreadsheet` unblocked.
- `LAB-VM-EVALAST-COVERAGE-P1` — CLOSED, **174/174 PASS**. eval_ast/bytecode parity
  coverage was guarded.
- `LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1` — CLOSED, **90/90 PASS**. VM dispatch table
  construction now fails closed with structured diagnostics rather than partial runtime.

Known runtime frontier after the day:

- `rule_engine` remains blocked intentionally by dynamic dispatch / Unknown policy.
- Function SIR has a known hardening follow-up: block branch `let` evaluation inside
  eval_ast `if_expr`.

### Numeric / Sum / Decimal

- `LANG-RUBY-NUMERIC-OPS-PARITY-P1` — CLOSED, **124/124 PASS**. Ruby numeric ops now
  match Rust homogeneous numeric relaxation, including Decimal scale behavior.
- `LAB-RUST-DECIMAL-INPUT-SCALE-P1` — CLOSED, **78/78 PASS**. Rust Decimal input scale
  inference no longer collapses to scale 0.
- `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` — CLOSED. Explicit `decimal(value, scale)`
  constructor landed across lab/canon surfaces needed by bookkeeping migration.
- `LANG-STDLIB-COLLECTION-SUM-SCALAR-P1/P2` — CLOSED. Scalar
  `sum(Collection[T]) -> T` implemented dual-toolchain + VM, with `OOF-COL8` for
  non-numeric scalar sum and Decimal scale preserved for non-empty collections.
- `LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1` — CLOSED as app migration evidence; remaining
  pressure was routed to numeric/sum work and subsequently closed.

### Sumtype / Option / Result / Collection Extraction

- Sumtype and Result planning/implementation pressure continued around sealed built-ins
  (`Option`, `Result`) rather than generic FP abstractions.
- `LANG-SUMTYPE-COLLECT-P1/P2/P3` and related Result/collect work established the
  collection extraction route for apps like `batch_importer`.
- Guardrail remained unchanged: no HKT, no typeclasses, no generic Monad, no do-notation.

### Rust Compiler / Typechecker / Loop Tightening

- `LAB-RUST-TYPECHECKER-DECOMP-P1/P2` had already separated the stdlib dispatch
  hot-spot; follow-up cards benefited from the smaller Rust TC surface.
- `LAB-RUST-LOOP-BODY-ASSIGNMENT-P1` / budgeted loop work tightened the Rust/Ruby
  divergence around loop-body assignment and selected the fold-to-struct route for
  accumulators instead of widening local mutation.

### Machine / Bitemporal / MCP Control Plane

- `LAB-MACHINE-PRESSURE-P1` found and fixed order-dependent bitemporal time-travel bugs:
  out-of-order facts no longer break `read_as_of` or history-range queries.
- `LAB-MACHINE-BITEMPORAL-AXIS-P1` fixed the axis model:
  - `read_as_of` remains transaction-time / known-at.
  - `read_bitemporal(valid_at, known_at)` makes both axes explicit.
  - `valid_time=None` is excluded under valid-axis queries.
- `LAB-MACHINE-CAPSULE-MANAGER-P1` and `LAB-MACHINE-MCP-FILMSTRIP-P1` established the
  agent control/debug plane:
  - immutable capsules / snapshots;
  - fork / activate / diff;
  - MCP-driven filmstrip.
- `LAB-MACHINE-MCP-IO-BOUNDARY-P1` recorded the guardrail: MCP can write/fork/activate
  as host/agent substrate, but this does not imply language IO.

### Machine Capability IO Data Plane

This became the main architectural result of the day.

Track closed through P6b:

```text
P1 executor + receipt model
P2 declared-effect host entrypoint
P3 real local read substrate
P4 host clock authority
P5 typed capability passport
P6a receipt-gated write lifecycle (fake)
P6b real local write substrate
```

Key invariant:

```text
contract declares effect/capability
ServiceLoop validates host authority + idempotency + executor binding
CapabilityExecutor performs external IO
EffectReceipt is written as a bitemporal fact
VM/contract body remains deterministic and IO-free
```

Important closures:

- `LAB-MACHINE-CAPABILITY-IO-P1` — executor + receipt-as-fact model.
- `LAB-MACHINE-CAPABILITY-IO-P2` — declared-effect host entrypoint through `run_effect`.
- `LAB-MACHINE-CAPABILITY-IO-P3` — real local `TBackendReadExecutor`.
- `LAB-MACHINE-CAPABILITY-IO-CLOCK-P4` — host clock provider; replay does not rewrite
  timestamps; contracts cannot read time.
- `LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5` — typed `CapabilityPassport`, authority digest,
  expiry/revocation/scope checks at host boundary.
- `LAB-MACHINE-CAPABILITY-IO-WRITE-P6` — two-phase receipt-gated write lifecycle and real
  local `TBackendWriteExecutor`.

Result:

```text
igniter-machine has real local read/write capability IO with receipts,
idempotency, authority, and host clock.
```

This is lab machine authority, not canon language authority.

## Current State At End Of Day

### Runtime Fleet

- Runtime fleet: **24/25 RUN-OK**.
- `rule_engine` remains `COMPILE-NOT-OK`, intentionally held by dynamic dispatch policy.
- VM common runtime bugs are no longer the dominant frontier.

### Machine IO

- Read/write local capability IO is proven in `igniter-machine`.
- Real network/HTTP/SparkCRM executors remain closed.
- Retry/reconciliation/compensation remain future cards.

### Authority Boundary

- Canon language authority remains in `igniter-lang`.
- Lab runtime/machine evidence remains in `igniter-lab`.
- Private governance memory remains in `igniter-gov`.
- Daily checkpoints are operational navigation only.

## Rebalanced Priorities For 2026-06-16

### P0 — Finish Yesterday's Crest

1. Write this daily checkpoint.
2. Create a machine capability IO milestone checkpoint so agents have one door for
   P1-P6b instead of rediscovering every card.
3. Keep active docs crest small; archive/supersede stale operational notes when they
   begin to outrank live `IMPLEMENTED_SURFACE.md`.

### P0 — Machine IO Next Step

4. `LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7` — design/readiness first.
   - Resolve `unknown_external_state` after write via read-back / verification.
   - No blind retry.
   - No HTTP/SparkCRM executor yet.
   - This is prerequisite for retry scheduler.

### P1 — Runtime Hardening

5. `LAB-FUNCTION-SIR-BLOCK-BRANCH-LET-P1` — harden eval_ast function body execution for
   `if_expr` branch blocks with `let` bindings.
6. Optional runtime recheck only after a meaningful runtime/machine change, not as busywork.

### P1 — Capability IO Production Invariants

7. After reconciliation, consider:
   - bounded retry taxonomy (`retryable`), but only after reconciliation;
   - compensation / `aborted` semantics;
   - write-succeeded-but-receipt-failed window;
   - executor-side idempotency handshake.

### P2 — Real External IO, Hold For Now

8. HTTP/SparkCRM API executor stays held until:
   - clock authority;
   - caller authority;
   - local read/write;
   - reconciliation;
   - retry semantics
   are all coherent.

### P2 — Canon / Language Work

9. Continue sealed sumtype / Option / Result follow-ons only when they are pulled by app
   pressure and do not reopen generic FP abstractions.
10. Do not open language-level IO. The current correct home for IO is `igniter-machine`,
    not VM and not contract bodies.

## Do Not Start First

- Do not add IO opcodes to VM.
- Do not expose `now()` to contracts.
- Do not route production request traffic through MCP.
- Do not implement HTTP/SparkCRM executor before reconciliation/retry are designed.
- Do not treat daily docs, lab cards, or proof notes as canon authority.
- Do not reopen `rule_engine` without an explicit dynamic dispatch / unknown-state
  governance decision.

## Authority Boundary

This daily checkpoint is an operational coordination artifact. It does not create canon
authority. Canon remains in `igniter-lang`; lab evidence remains in `igniter-lab`; private
governance checkpoints remain in `igniter-gov`. For implemented-state questions, check the
project `IMPLEMENTED_SURFACE.md` and live code before trusting older docs.
