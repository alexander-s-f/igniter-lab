# Lab Doc: Scheduler Substrate Readiness and Minimal Runtime Contract
**Track:** lab-scheduler-substrate-readiness-and-minimal-runtime-contract-v0  
**Card:** LAB-CONCURRENCY-P4 (Category: lang)  
**Status:** CLOSED / DESIGN-LOCKED  
**Date:** 2026-06-09  
**Route:** DESIGN / LAB-ONLY — no proof runner; no code written; design artifact only  
**Authority:** Lab-only. No canon claim. No implementation authority opened.  
This document names a contract; it does not authorize implementation of any substrate.

---

## Purpose

P1 proved the wave model and parity invariant.  
P2 proved the capability-aware policy gate for effectful nodes.  
P3 proved the replay/audit boundary for tamper-evident receipts.

This card answers the next question: **what must any future scheduler substrate satisfy to execute P1/P2 wave plans and produce P3-replayable receipts?**

The answer is a minimal runtime contract — a set of invariants and a five-phase execution model that any substrate must respect, regardless of its internal threading or concurrency model. The contract can be stated without implementing real threads, async runtime, or any production scheduler.

---

## Depends On

| Card | Description |
|------|-------------|
| LAB-CONCURRENCY-P1 | Wave model; read-isolation invariant; parity proved (57/57) |
| LAB-CONCURRENCY-P2 | PolicyEvaluator 6-gate sequence; EffectSpec; CapabilityAwareScheduler (59/59) |
| LAB-CONCURRENCY-P3 | ReplayableReceipt; DigestableMixin; ReceiptReplayerP3 10-gate verify (60/60) |

---

## Core Invariants from P1/P2/P3

These invariants are already proved. The substrate contract formalizes them as requirements:

**From P1 — Wave Model:**
- **W1 (Read-isolation):** All nodes in the same wave have no mutual dependencies. Each node's inputs come exclusively from prior waves. Intra-wave execution order cannot change any node's inputs or outputs.
- **W2 (Topological order):** `wave(n) = max(deps_waves) + 1`. No node executes before any node it depends on.
- **W3 (Parity):** `SequentialScheduler.result_values == ParallelSchedulerSimulation.result_values` for all graphs and all intra-wave orderings of pure nodes.

**From P2 — Policy Gate:**
- **P1 (Effect serialization default):** Effectful nodes are not concurrent-eligible without an explicit `SchedulingPolicy`.
- **P2 (Capability denial is pre-eminent):** Gate 1 of `PolicyEvaluator.check_pair` fires before all other gates. A denied `capability_id` cannot be rescued by resource disjointness or category allowance.
- **P3 (All pairs must be eligible):** A wave is `concurrent_eligible` only if ALL effectful pairs in the wave return `:eligible`. One non-eligible pair makes the wave ineligible.

**From P3 — Receipt Integrity:**
- **R1 (Digest fixation):** `graph_digest` and `policy_digest` are computed once at build time and must match the current graph/policy at replay time.
- **R2 (Spec-digest):** Each effectful node's `spec_digest` encodes `effect_category + resource_keys + capability_id`. Drift in any field is detectable at replay.
- **R3 (Result backstop):** Even if `result_values` and `result_digest` are tampered consistently, Gate 10 re-execution catches the mismatch.

---

## Five-Phase Execution Model

Any scheduler substrate must implement these five phases in order. Names are illustrative — not public API:

```
Phase 1: PREPARE
  Input:  DAG (graph snapshot), SchedulingPolicy (policy snapshot or nil)
  Action: - Validate graph structure (DagValidator equivalent)
          - Compute graph_digest = DigestableMixin.graph_digest(dag)
          - Compute policy_digest = DigestableMixin.policy_digest(policy)
          - FREEZE: graph and policy are immutable for the remainder of the run
  Output: Frozen graph + policy digests; validated wave plan

Phase 2: PLAN
  Input:  Frozen graph
  Action: - Compute wave assignments (DagWaves.compute_waves equivalent)
          - Group nodes by wave (DagWaves.wave_groups equivalent)
          - For each wave, classify nodes into :input / :pure / :effectful
          - For effectful waves: evaluate all pairs via PolicyEvaluator
          - Record eligibility and reasons for each wave
  Output: Ordered list of wave plans (wave_number, node_ids, concurrent_eligible,
          policy_decisions, policy_id)

Phase 3: EXECUTE_WAVE (repeated per wave, in wave-number order)
  Input:  Wave plan, current values map (seed + prior wave results)
  Action: - :input nodes: bind from seed_values
          - :pure nodes: execute compute_table[id].call(values)
          - :effectful nodes: execute compute_table[id].call(values)
          - IF concurrent_eligible == true: substrate MAY execute nodes
            in any intra-wave order (W1 guarantees result equivalence)
          - IF concurrent_eligible == false: substrate MUST execute nodes
            in a deterministic serial order
          - Each node result is written ONCE; subsequent reads are immutable
  Output: Updated values map with this wave's results

Phase 4: RECORD
  Input:  Completed wave execution data
  Action: - For each wave: write wave_details entry with:
            - wave number
            - node_ids (all nodes in this wave)
            - concurrent_eligible flag
            - policy_decisions (PolicyDecision records for all effectful pairs)
            - policy_id (nil if no policy)
            - effect_categories and resource_keys per effectful node
          - For each effectful node: write effect_metadata entry with spec_digest
  Output: Populated wave_details + effect_metadata

Phase 5: FINALIZE_RECEIPT
  Input:  Frozen digests, wave_details, effect_metadata, result_values
  Action: - Compute result_digest = DigestableMixin.result_digest(result_values)
          - Assemble ReplayableReceipt with all digest + structural fields
          - Set schema_version = 'replay-v0'
  Output: ReplayableReceipt (P3-compatible; ready for ReceiptReplayerP3.verify)
```

---

## Required Substrate Invariants

The nine invariants a substrate must satisfy:

| # | Invariant | Source | Enforcement point |
|---|-----------|--------|-------------------|
| SI-1 | Graph digest fixed at run start | R1 | Phase 1: PREPARE — no graph mutation after digest computed |
| SI-2 | Policy digest fixed at run start | R1 | Phase 1: PREPARE — no policy mutation after digest computed |
| SI-3 | Node inputs immutable within a wave | W1 | Phase 3: only prior-wave values readable; never current-wave partial results |
| SI-4 | Node result written exactly once | W3 | Phase 3: compute_table[id] called exactly once per node per run |
| SI-5 | No dependent node starts before its dependencies finish | W2 | Phase 3: wave order enforced; no cross-wave out-of-order execution |
| SI-6 | No effectful wave executes concurrently unless P2 policy allows | P1+P3 | Phase 2: eligibility gate; Phase 3: serial if not eligible |
| SI-7 | Every eligibility decision is recorded | R2 | Phase 4: all PolicyDecision records written; no silent decisions |
| SI-8 | Every denied/serialized reason is recorded | R2 | Phase 4: reason field populated for every non-eligible wave |
| SI-9 | Result digest produced from canonical result values | R3 | Phase 5: `DigestableMixin.result_digest` called after all waves complete |

**Invariant dependencies:**  
SI-3 depends on SI-1 (graph frozen) and SI-5 (wave order enforced).  
SI-9 depends on SI-4 (result written once) and SI-5 (all waves complete before finalize).

---

## Runtime Interface Shape (Illustrative)

These names illustrate the five-phase contract. They are NOT a public API — they describe what must exist, not what it must be called:

```ruby
# Phase 1
substrate.prepare(graph, policy)
# → freezes digests; validates structure; raises SubstrateError on invalid graph

# Phase 2  
wave_plan = substrate.plan_waves()
# → [{ wave:, node_ids:, concurrent_eligible:, policy_decisions:, ... }, ...]

# Phase 3 (called per wave)
substrate.execute_wave(wave_plan[i], values_map)
# → updated values_map with this wave's results appended

# Phase 4 (called per wave, or post-execute)
substrate.record_decision(wave_number, wave_result)
# → writes wave_details entry; populates effect_metadata

# Phase 5
receipt = substrate.finalize_receipt()
# → ReplayableReceipt with schema_version, digests, waves, effect_metadata,
#    result_digest, result_values
```

**Why five phases, not one method?**  
Each phase has a distinct failure mode and a distinct invariant class. Merging them into one call hides which invariant was violated when a failure occurs. The five-phase model also maps naturally to how a future proof card would verify each phase independently.

---

## Failure Mode Matrix

| Failure | Phase | Substrate response | Receipt state | Replayer response |
|---------|-------|-------------------|---------------|-------------------|
| **Node failure** (compute_table raises) | Phase 3 | Catch; mark node as `failed`; record in wave_details | Partial receipt with `failed_nodes` list; result_values missing failed node | Gate 10 re-execution: result_values mismatch → `valid: false` |
| **Policy mismatch** (policy changed after prepare) | Phase 2/3 | Detect via policy_digest comparison; abort; raise SubstrateError | No receipt emitted | N/A (substrate aborts before receipt) |
| **Graph drift** (node added/removed after prepare) | Phase 2/3 | Detect via graph_digest comparison; abort; raise SubstrateError | No receipt emitted | N/A |
| **Effect denial** (capability_id denied) | Phase 2 | Gate 1 fires in PolicyEvaluator; wave marked not eligible; reason recorded | Receipt emitted with `concurrent_eligible: false`; reason in policy_decisions | Replay valid — denied wave is correctly non-eligible |
| **Receipt write failure** (finalize raises) | Phase 5 | Abort; no partial receipt emitted | No receipt | N/A |
| **Partial execution** (substrate aborted mid-run) | Phase 3 | Record completed waves; set `partial_execution: true` on receipt | Partial receipt — some waves present, some absent | Replayer extended: detect missing waves; report `partial_execution` error |
| **Cancellation / abort** | Phase 3 | Same as partial execution | Same as partial execution | Same as partial execution |
| **Unknown effect category** | Phase 2 | `:unknown_resource` gate fires (empty resource_keys); wave not eligible | Receipt with `outcome: :unknown_resource` in policy_decisions | Replay valid — unknown category correctly rejected |

**Key design rule:** A substrate MUST NOT emit a receipt it cannot make internally consistent. A failed receipt is worse than no receipt — it would pass Gate 9 (consistent digest) but fail Gate 10 (re-execution), misleading auditors.

---

## Substrate Options Comparison

| Substrate | Auth status | Proof requirements met | Notes |
|-----------|-------------|----------------------|-------|
| **Deterministic single-thread wave interpreter** | ✅ OPEN (proved by P1/P2/P3) | P1+P2+P3 sufficient | This is exactly what `SequentialScheduler` and `CapabilityAwareScheduler` demonstrate. No additional proof needed. |
| **Simulated parallel executor** (intra-wave reordering) | ✅ OPEN (lab only) | P1 ParallelSchedulerSimulation proved parity | W1 read-isolation guarantees any intra-wave order of PURE nodes is equivalent. Lab only — no real thread infrastructure. |
| **Real thread pool** | 🔒 HOLD — requires P5 | P5 thread-safety proof required (see below) | W1 is necessary but not sufficient; must also prove: (a) compute_table functions are pure/thread-safe; (b) result collection is race-free; (c) P3-compatible receipt from concurrent execution. |
| **Real async executor** | 🔒 HOLD — separate card | Async runtime selection + async effect model required | Requires: executor selection proof; async EffectSpec model (futures, structured concurrency); cancellation/partial-receipt model. Separate authorization required. |
| **Distributed scheduler** | 🔒 HOLD — far future | Network topology, node serialization, distributed receipts all unproved | Not a near-term route. |

### What P5 (thread pool) must prove

Before real threading can open, a dedicated proof card (LAB-CONCURRENCY-P5 or equivalent) must demonstrate:

| Requirement | Test |
|---|---|
| **compute_table purity** | Each function reads only `values` (prior-wave map); no shared mutable state |
| **Result collection race-freedom** | Concurrent writes to separate keys of `values` produce same result as serial writes |
| **Receipt production from concurrent execution** | graph_digest, policy_digest, result_digest all match the single-thread path for same inputs |
| **Error isolation** | One node failure does not corrupt results of other nodes in the same wave |
| **P1 parity preserved** | `result_values` identical for all fixtures when thread pool is used vs. single-thread |
| **P3 replay succeeds** | Receipt produced by thread pool substrate passes ReceiptReplayerP3.verify |

All existing proof runners (P1 57/57, P2 59/59, P3 60/60) must stay green as regression guards.

---

## Promotion / Readiness Checklist

### For v0 deterministic substrate (single-thread wave interpreter)

- [x] **P1** Wave model and parity invariant proved (57/57)
- [x] **P2** Policy gate and effect serialization proved (59/59)
- [x] **P3** Replay/audit boundary proved (60/60)
- [x] **P4** Minimal runtime contract named (this document)
- [ ] Real implementation authorized (separate gate decision required)
- [ ] Integration with igniter-lang VM (separate card; VM runtime gate closed)

### For v1 thread-pool substrate

- [x] P1+P2+P3+P4 complete
- [ ] LAB-CONCURRENCY-P5: compute_table purity proof
- [ ] LAB-CONCURRENCY-P5: race-free result collection proof
- [ ] LAB-CONCURRENCY-P5: P3-compatible receipt from concurrent execution
- [ ] LAB-CONCURRENCY-P5: error isolation proof
- [ ] Explicit authorization to open real-threading infrastructure
- [ ] P1+P2+P3 regression proofs pass with thread-pool execution

### For async executor substrate

- [ ] LAB-CONCURRENCY-P5 complete
- [ ] Async runtime selection + lock (separate card)
- [ ] Async EffectSpec model (futures/structured concurrency)
- [ ] Cancellation and partial-receipt model
- [ ] Separate authorization card

### What must remain closed before v1 (any substrate)

| Surface | Status | Reason |
|---------|--------|--------|
| Public concurrency API | Closed | No stable API surface; no canon claim |
| Performance claims | Closed | `no-perf-claims-closed`; parity is correctness, not speed |
| Production scheduler deployment | Closed | VM runtime gate closed separately |
| Real I/O in concurrent waves | Closed | Requires effect proof + resource isolation beyond P2 |
| Canon promotion of SchedulingReceipt | Closed | Lab-only; `scheduling-receipt-evidence-only-v0` |
| `Thread`/`Fiber`/async-runtime infrastructure | Closed | Requires P5 + explicit authorization |

---

## Explicit Answers to Card Questions

| Question | Answer |
|----------|--------|
| Can a future substrate be specified without implementation? | **YES.** This document is the specification. It names invariants, a five-phase model, and a failure matrix without implementing any of them. |
| Are P1/P2/P3 sufficient to define the minimal runtime contract? | **YES for v0 (deterministic single-thread).** P1 defines the wave model and parity invariant. P2 defines the policy gate. P3 defines the receipt integrity contract. Together they fully specify the v0 substrate. Real threading requires P5. |
| Is single-thread wave execution a valid first substrate? | **YES.** It is the ONLY currently authorized substrate. P1 `SequentialScheduler` and P2 `CapabilityAwareScheduler` already demonstrate it. |
| May a real thread pool open next? | **NO — must wait.** Thread-safety proof (P5) required. W1 read-isolation is necessary but not sufficient — it does not prove compute_table purity or race-free result collection. |
| May an async runtime open next? | **NO — must wait and requires separate card.** Async runtime infrastructure is closed. Opening it requires executor selection, async EffectSpec model, and cancellation semantics — all unproved. |
| Does effect concurrency remain policy-gated? | **YES, always.** Any substrate must pass P2 `PolicyEvaluator.check_pair` before scheduling effectful waves concurrently. Gate 1 (capability denial) remains pre-eminent. |
| Is the P3 replay receipt mandatory for any future substrate? | **YES, as the minimum.** Any substrate must emit a receipt that passes `ReceiptReplayerP3.verify`. A substrate may emit a superset of P3 fields, but may not omit any. |
| Do performance claims remain closed? | **YES.** Concurrent execution may be faster in practice; this is not a claim this track makes. Performance claims require a separate, authorized benchmarking card. |
| Does public concurrency API remain closed? | **YES.** No stable API surface. The five-phase interface names are illustrative. No method names are public or stable. |
| What is the exact next route? | **LAB-CONCURRENCY-P5** — thread-safety proof (compute_table purity + race-free result collection + P3-compatible concurrent receipt). Requires explicit authorization to open real-threading infrastructure. Alternatively: **LAB-COMPILER-P5** — express `DagNode.kind` and `EffectSpec.effect_category` as tagged unions in the igniter-lang type system. |

---

## Readiness Decision Tree

```
New substrate card proposed?
    │
    ├─ Is it a deterministic single-thread interpreter?
    │   └─ YES → P1+P2+P3+P4 sufficient; implementation card authorized
    │
    ├─ Does it use real threads?
    │   └─ YES → Is LAB-CONCURRENCY-P5 DONE (60+/60 PASS)?
    │               ├─ YES → Is explicit authorization granted?
    │               │           └─ YES → Proceed
    │               │           └─ NO  → Open authorization gate first
    │               └─ NO  → Do P5 first
    │
    ├─ Does it use async runtime?
    │   └─ YES → Is async-runtime infrastructure gate open?
    │               └─ NO  → Open separate authorization card first
    │
    └─ Does it make performance claims?
        └─ YES → Reject; performance claims closed
```

---

## Design Notes

### Why the five-phase model over a monolithic execute()

The P1/P2/P3 proofs each touch a different phase:

- P1 proved the wave plan (Phase 2) and execution correctness (Phase 3)
- P2 proved the policy evaluation inside Phase 2
- P3 proved Phase 5 (receipt integrity) and the cross-cutting invariants R1–R3

A monolithic `execute()` would make it impossible to reason about which proof covers which invariant. The five-phase model maps each invariant to the phase that enforces it, making future proof cards mechanically composable.

### Why W1 (read-isolation) is necessary but not sufficient for threading

W1 proves that concurrent execution of pure nodes in the same wave produces the same result as serial execution — for any intra-wave order. This is a correctness property about the values.

But W1 says nothing about whether the data structures holding those values are safe for concurrent reads and writes in a real memory model. A Ruby Hash, for example, is not safe for concurrent mutation from multiple threads. P5 must prove that the result collection mechanism is race-free, independent of W1.

### Why the policy gate fires in Phase 2 (planning) not Phase 3 (execution)

The policy decision must be recorded before execution begins. If the gate fired during execution, an eligibility decision could be made after some nodes had already started, making the receipt inconsistent with the actual execution order. Planning phase evaluation ensures the receipt records the decision that governed the execution.

### What "substrate MAY execute" means vs. "substrate MUST"

When `concurrent_eligible == true`, the substrate is **permitted** (not required) to execute nodes concurrently. A substrate may choose to run them serially for any internal reason (resource pressure, debugging, etc.) — the receipt will still be valid because W3 (parity) proves serial and concurrent produce identical `result_values`. The eligibility flag records what was **allowed**, not what was **done**.

This separation is intentional: it allows a substrate to be correct (all invariants satisfied) without being optimized (not using the allowed concurrency). Optimization is a separate concern — and performance claims remain closed.

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Real-thread substrate | Closed until P5 | thread-safety + race-free collection unproved |
| Async executor | Closed until separate card | runtime infrastructure gate closed |
| Partial-execution receipt schema | Future card | Current P3 schema has no `partial_execution` field |
| Distributed scheduler | Far future | Network topology + distributed receipts unproved |
| VM integration | VM runtime gate | SchedulingReceipt not wired to `igc run` |
| Public substrate API | Closed | No stable names; no canon claim |
| Performance claims | Closed | `no-perf-claims-closed` |

---

## Next Recommended Routes

**LAB-CONCURRENCY-P5 (thread-safety proof):**  
Prove that compute_table functions are pure (no shared mutable state), that result collection is race-free, and that a P3-compatible receipt can be produced from concurrent intra-wave execution. This is the gate that unlocks real thread pool usage. Requires explicit authorization to open real-threading infrastructure before starting.

**LAB-COMPILER-P5 (tagged union types):**  
Prove that the igniter-lang compiler can express `DagNode.kind` (`:input | :pure | :effectful`) and `EffectSpec.effect_category` (`:read_file | :write_file | :network_call`) as tagged unions with discriminated field checking. Ill-formed EffectSpec construction becomes a compile-time error rather than a replay-time error. Does not require threading infrastructure.

**LAB-CONCURRENCY-P4 / EffectSpec wiring:**  
Wire `EffectSpec.capability_id` to the existing `HttpCapabilityPolicyP6` engine, so network-call effect nodes derive resource keys and capability denial status from the capability grant table automatically, without manual EffectSpec construction.
