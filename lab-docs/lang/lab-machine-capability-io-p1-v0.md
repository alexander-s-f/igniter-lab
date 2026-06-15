# lab-machine-capability-io-p1-v0 — production capability IO boundary

**Card:** `LAB-MACHINE-CAPABILITY-IO-P1`
**Status:** CLOSED — readiness/design + fake-executor proof. 13 machine tests
(`tests/capability_io_tests.rs`), full suite green (`cargo test --no-default-features`).
**Boundary held:** no real DB/HTTP/queue/clock; no language syntax change; no MCP hot path;
no canon claim about D-001.

## Thesis

The correct production IO shape for Igniter is **not** "the MCP agent pokes the world." It is
a data-plane host:

```text
contract declares effect/capability          ← language already has the vocabulary
ServiceLoop validates authority + idempotency ← the host boundary (run_effect)
CapabilityExecutor performs the external IO   ← typed external port (TBackend is one)
EffectReceipt is written as a bitemporal fact ← receipt = fact (same substrate)
pure graph continues from the typed outcome   ← outcome is a typed taxonomy, not a bool
```

Guardrail (verbatim, locked in the card):

> **External world may be contract-shaped, but never carries pure-contract authority.
> It always carries receipt, failure, authority, and idempotency.**

The key reframe from verify-first: **we are not adding an IO layer from scratch — we are
generalizing one that already exists.** Igniter contracts already *declare* their effect
surface; the VM already has escape/emit opcodes; `TBackend` is already an executor-shaped
port. P1 connects declaration → execution → receipt, and proves it with fake executors.

## Must-answer questions

**1. What exists today for `capability` / `effect` / `escape_set` / `service_loop`?**
The language already *declares* effect surface per contract in the IR: `modifier`
(`pure` / `observed` / `privileged` / `irreversible`), `effects[]`, `escape_set[]`,
`capabilities[]`, `escape_boundaries`. The VM has effect opcodes `OP_LOAD_AS_OF` (0x0D,
temporal read) and `OP_EMIT_OBS` (0x0E, observation emit). The compiler carries a
`service_loop_node`. So declaration + escape points + a proto-loop already exist; what was
missing is the runtime that *honors* the declared surface and records its effects.

**2. Is `TBackend` a `CapabilityExecutor` instance or a backing store?**
Both, precisely: `TBackend` is the **first proven capability family** — a typed
external/temporal port (`read_as_of` / `write_fact` / `facts_for`) with three impls
(in-memory / RocksDB / remote-TCP). `CapabilityExecutor` is the same shape generalized to
HTTP/DB/queue. We **lift its form, not replace it.** The receipt store is itself a `TBackend`
namespace (`__receipts__`), so the executor pattern and the audit log share one substrate.

**3. Minimal `CapabilityExecutor` trait for P1.**
```rust
trait CapabilityExecutor {
    fn capability_id(&self) -> &str;
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome;
}
```
`EffectRequest { capability_id, idempotency_key, authority_ref, args }`,
`EffectOutcome { kind: OutcomeKind, result, failure_kind }`.

**4. `EffectReceipt` fields (v0).** A fact in store `__receipts__`, key
`capability_id:idempotency_key`, value `{capability_id, idempotency_key, authority_ref,
outcome_kind, result, failure_kind}`, plus the fact's own `transaction_time` (audit axis).
A real ServiceLoop stamps `tt = now`; the proof uses a fixed `tt` (single receipt per key,
no time-travel needed for v0 receipts).

**5. Idempotency key scope.** `(capability_id, idempotency_key)`, caller-provided. Lookup is
`read_as_of(__receipts__, "cap:key", MAX)` before any external call.

**6. Replay mode.** Executor bypass: always resolve from the receipt store; reconstruct the
typed outcome from the receipt fact; never call the executor. A replay request for a key with
no receipt is **`unknown_external_state`** (we cannot reconstruct what we never recorded) —
still no executor call.

**7. `unknown_external_state` vs `failed`.** A timeout / no-answer is an **epistemic**
outcome: we don't know the external truth, so collapsing it to "failed" would be a lie. It is
distinct from `permanent_failure` (a definite negative, e.g. "key not found"). The proof's
`KvReadExecutor` returns `unknown_external_state` for `__timeout__` and `permanent_failure`
for an absent key — two different facts. (Proof-local vocabulary that *aligns with* the canon
epistemic-outcome model / ledger D-001 — **not** a claim D-001 is implemented in canon.)

**8. Where does ServiceLoop validation stop and executor denial begin?**
ServiceLoop does **preflight refusal** — missing idempotency key, missing authority, or
unknown capability → `Denied` **before the executor is touched**, and **no receipt is
written** (nothing happened externally). Once preflight passes, the executor may still refuse
(e.g. insufficient authority for a specific resource) → that is **denial-as-data**: the
executor ran, so the denial **is recorded as a receipt fact**.

**9. Which MCP operations stay control-plane only?**
All capsule/filmstrip MCP tools (`capsule_snapshot/list/activate/fork/diff/activate_many`)
and `igniter_*` MCP tools remain control/debug plane. MCP must not be the 2k–5k rpm hot path;
production request handling goes through the ServiceLoop data-plane (this card's path).

**10. Smallest follow-up that touches implementation code.** `LAB-MACHINE-CAPABILITY-IO-P2`
— wire the `CapabilityExecutorRegistry` + a ServiceLoop runner into a machine-local host
entrypoint (still fake executors), so a *contract that declares an effect* dispatches through
`run_effect` end-to-end. P3 binds one real substrate (likely a local RocksDB/TBackend read,
not HTTP first).

## Proof matrix (13 tests, `tests/capability_io_tests.rs`)

| § | Claim | Test |
|---|---|---|
| B/C | live effect runs executor once, writes a full-schema receipt fact | `live_effect_runs_executor_writes_receipt_fact` |
| D | idempotency: 2nd call with same `(cap,key)` replays, executor not re-invoked | `idempotency_prevents_second_executor_call` |
| D | distinct keys each invoke the executor | `distinct_idempotency_keys_each_invoke_executor` |
| E | replay reads receipt, executor untouched | `replay_returns_receipt_without_calling_executor` |
| E/F | replay with no receipt → `unknown_external_state`, no executor call | `replay_without_receipt_is_unknown_not_failure` |
| F | timeout → `unknown_external_state` (recorded as fact), not failed | `timeout_is_unknown_external_state_not_failed` |
| F | absent key → `permanent_failure`, distinct from unknown | `missing_key_is_permanent_failure_distinct_from_unknown` |
| B | known key → succeeded with typed result | `known_key_succeeds` |
| G | preflight refuses unknown capability before executor, no receipt | `preflight_refuses_unknown_capability_before_executor` |
| G | preflight refuses missing idempotency key | `preflight_refuses_missing_idempotency_key` |
| G | preflight refuses missing authority | `preflight_refuses_missing_authority` |
| G | executor-level denial is written as a receipt fact (denial-as-data) | `executor_denial_is_written_as_data` |
| H | receipt lives in the same TBackend fact store (not a hidden side-log) | `receipt_lives_in_the_same_tbackend_fact_store` |

Section **A** (verify-first of existing surfaces — modifier/effects/escape_set,
`OP_LOAD_AS_OF`/`OP_EMIT_OBS`, `TBackend`, `service_loop_node`) is grounded in this doc's
Q1/Q2 rather than as runtime checks, since those surfaces are already proven by the live
compiler/VM/machine suites.

> Note on the card's "≥70 checks": that target assumed a Ruby proof runner. This proof went
> the machine-tests route (the card's allowed alternative for proof-local Rust types) — 13
> tests / ~45 assertions covering §B–H. Honest accounting: fewer discrete "checks," same
> coverage of the model.

## Closed surfaces (held)

No real Postgres / HTTP / Redis / queue / filesystem / socket / clock / SparkCRM API. No
language syntax expansion. No contract-body IO. No dynamic-dispatch expansion. No production
retry scheduler. No MCP hot-path claim. No canon claim that D-001 / epistemic outcomes are
fully implemented. No replacement of `TBackend` — only generalization of its pattern.

## Next route

- **P2** (impl): machine-local host entrypoint that dispatches a declared-effect contract
  through `run_effect` + registry (fake executors still). Surfaces: `src/machine.rs` (a
  `run_service_effect`-style method or a thin `ServiceLoop` struct), registry wiring.
- **P3** (first real substrate): bind one real executor — local RocksDB/TBackend read is the
  safest first bind; HTTP/SparkCRM API later, behind the same trait + receipt + authority.
- **Open**: receipt `tt = now` from a real clock (currently fixed); retry/`retryable`
  scheduling (taxonomy exists, scheduler does not); authority/passport verification shape
  (currently presence-only).
