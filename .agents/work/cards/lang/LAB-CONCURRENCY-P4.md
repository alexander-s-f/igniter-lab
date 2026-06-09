# Card: LAB-CONCURRENCY-P4
**Category:** lang  
**Track:** lab-scheduler-substrate-readiness-and-minimal-runtime-contract-v0  
**Status:** CLOSED / DESIGN-LOCKED  
**Date closed:** 2026-06-09  
**Route:** DESIGN / LAB-ONLY — no proof runner; no code written

---

## Goal

Define the minimal runtime contract that any future scheduler substrate must satisfy to:
- Execute deterministic wave plans from P1/P2
- Produce P3-replayable receipts
- Without implementing real threads, async runtime, production scheduler, or public concurrency API

---

## Depends On

| Card | Status |
|------|--------|
| LAB-CONCURRENCY-P1 | ✅ DONE (57/57) |
| LAB-CONCURRENCY-P2 | ✅ DONE (59/59) |
| LAB-CONCURRENCY-P3 | ✅ DONE (60/60) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Design/readiness doc | `lab-docs/lang/lab-scheduler-substrate-readiness-and-minimal-runtime-contract-v0.md` | DONE |
| Card | `.agents/work/cards/lang/LAB-CONCURRENCY-P4.md` | DONE (this file) |
| Portfolio update | `.agents/portfolio-index.md` | DONE |

---

## Five-Phase Execution Model

Any substrate must implement in order:

1. **PREPARE** — Accept graph + policy; compute and freeze `graph_digest` + `policy_digest`; validate structure
2. **PLAN** — Compute wave assignments; evaluate P2 eligibility per wave (PolicyEvaluator); record decisions
3. **EXECUTE_WAVE** (per wave) — Run nodes in wave-number order; write each result exactly once; may use any intra-wave order when `concurrent_eligible == true`
4. **RECORD** — Write `wave_details` (node_ids, concurrent_eligible, policy_decisions, policy_id, effect_metadata)
5. **FINALIZE_RECEIPT** — Compute `result_digest`; assemble `ReplayableReceipt` with all digest + structural fields

---

## Nine Required Substrate Invariants

| # | Invariant | Source proof |
|---|-----------|-------------|
| SI-1 | Graph digest fixed at run start | P3 R1 |
| SI-2 | Policy digest fixed at run start | P3 R1 |
| SI-3 | Node inputs immutable within a wave | P1 W1 (read-isolation) |
| SI-4 | Node result written exactly once | P1 W3 (parity) |
| SI-5 | No dependent node starts before dependencies finish | P1 W2 (topological order) |
| SI-6 | No effectful wave executes concurrently unless P2 policy allows | P2 P1+P3 |
| SI-7 | Every eligibility decision is recorded | P3 R2 |
| SI-8 | Every denied/serialized reason is recorded | P3 R2 |
| SI-9 | Result digest produced from canonical result values | P3 R3 |

---

## Substrate Options

| Substrate | Auth status | Gate |
|-----------|-------------|------|
| Deterministic single-thread wave interpreter | ✅ OPEN (proved by P1/P2/P3) | None — already demonstrated |
| Simulated parallel executor (intra-wave reorder) | ✅ OPEN (lab only) | None — P1 ParallelSchedulerSimulation proved parity |
| Real thread pool | 🔒 HOLD | LAB-CONCURRENCY-P5 required (thread-safety + race-free result collection) |
| Real async executor | 🔒 HOLD | Separate card + async infrastructure opening required |
| Distributed scheduler | 🔒 HOLD | Far future — network topology unproved |

---

## Failure Mode Matrix

| Failure | Phase | Receipt state | Replayer response |
|---------|-------|---------------|-------------------|
| Node failure | Phase 3 | Partial receipt, `failed_nodes` list | Gate 10: result mismatch → `valid: false` |
| Policy mismatch after prepare | Phase 2/3 | Abort — no receipt | N/A |
| Graph drift after prepare | Phase 2/3 | Abort — no receipt | N/A |
| Effect denial (capability_id) | Phase 2 | Receipt emitted, wave not eligible | Replay valid — denial correctly recorded |
| Receipt write failure | Phase 5 | No receipt emitted | N/A |
| Partial execution / abort | Phase 3 | Partial receipt, `partial_execution: true` | Replayer extended to detect missing waves |

**Design rule:** A substrate MUST NOT emit an internally inconsistent receipt. A failed receipt is worse than no receipt.

---

## Gap Packet

| Question | Answer |
|----------|--------|
| Substrate specifiable without implementation? | **YES** — this card demonstrates it |
| P1/P2/P3 sufficient for minimal contract? | **YES for v0 single-thread.** Real threading requires P5. |
| Single-thread valid first substrate? | **YES** — only currently authorized substrate |
| Real thread pool may open next? | **NO** — P5 thread-safety proof required |
| Async runtime may open next? | **NO** — separate card + infrastructure authorization required |
| Effect concurrency remains policy-gated? | **YES** — P2 PolicyEvaluator fires for any effectful wave |
| P3 replay receipt mandatory? | **YES** — any substrate must pass `ReceiptReplayerP3.verify` |
| Performance claims remain closed? | **YES** — `no-perf-claims-closed` |
| Public concurrency API remains closed? | **YES** — no stable names; no canon claim |
| Exact next route | **LAB-CONCURRENCY-P5** (thread-safety proof) or **LAB-COMPILER-P5** (tagged union types) |

---

## Why W1 Is Necessary But Not Sufficient for Threading

W1 (read-isolation) proves intra-wave execution order cannot change any node's inputs or outputs. This is a **correctness property about values**.

It does NOT prove that the data structures holding those values are safe for concurrent reads/writes in a real memory model. P5 must separately prove:
- compute_table functions are pure (no shared mutable state)
- Result collection mechanism is race-free
- P3-compatible receipt can be produced from concurrent execution

---

## Authority Constraints

- Closed: real concurrent execution, real I/O, real network, production scheduler, public API
- Forbidden: `Thread`, `Fiber`, `sleep`, async-runtime require, performance claims
- No canon claim; no finalized API surface; no implementation authority
- Lab-only; no production file edits

---

## Next Routes

**LAB-CONCURRENCY-P5 (unlocks real thread pool):**  
Prove compute_table purity + race-free result collection + P3-compatible concurrent receipt + error isolation. Requires explicit authorization to open real-threading infrastructure before starting.

**LAB-COMPILER-P5 (does not require threading):**  
Express `DagNode.kind` and `EffectSpec.effect_category` as tagged unions in igniter-lang. Ill-formed EffectSpec becomes a compile-time error.

**EffectSpec wiring:**  
Wire `EffectSpec.capability_id` to `HttpCapabilityPolicyP6` so network-call effect nodes derive resource keys and denial status from the capability grant table automatically.
