# Card: LAB-CONCURRENCY-P3
**Category:** lang  
**Track:** lab-scheduling-receipt-determinism-and-replay-proof-v0  
**Status:** CLOSED / PROVED — 60/60 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Prove the lab-only replay/audit boundary for deterministic scheduling receipts:
- A `ReplayableReceipt` produced from a DAG + policy can be replayed against the same graph and policy to reproduce the same result
- Graph drift, policy drift, resource-key drift, effect-category drift, and receipt tampering all fail closed
- Legal intra-wave permutations are equivalent (same `result_values`)
- The receipt does NOT create semantic authority over scheduling decisions or open runtime concurrency authority

---

## Depends On

| Card | Status |
|------|--------|
| LAB-CONCURRENCY-P1 | ✅ DONE (57/57) |
| LAB-CONCURRENCY-P2 | ✅ DONE (59/59) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-view-engine/proofs/scheduling_receipt_replay_proof.rb` | DONE — 60/60 PASS |
| Lab doc | `lab-docs/lang/lab-scheduling-receipt-determinism-and-replay-proof-v0.md` | DONE |

---

## Proof Sections (60 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| P3-SCHEMA | 6 | schema_version; digests present; waves array; effect_metadata spec_digest; result_digest consistent with values |
| P3-DIGEST | 6 | Graph digest stability + sensitivity (node kind; dep edge); policy digest stability (changed pairs); result digest |
| P3-REPLAY-OK | 6 | Pure diamond; fanout (F=30); eligible policy; denied cap; no-policy; two replays identical |
| P3-FAIL-GRAPH | 5 | Changed kind; added edge; removed edge; unknown node; missing node |
| P3-FAIL-POLICY | 4 | Changed allowed_pairs; changed denied_ids; no-policy tampered eligible; write/write conflict tampered eligible |
| P3-FAIL-EFFECT | 5 | resource_key drift; effect_category drift; resource_conflict tamper; category_closed tamper; denied_capability tamper |
| P3-FAIL-RESULT | 3 | Value tampered; digest tampered; both tampered consistently (Gate 10 catches) |
| P3-WAVE | 5 | Same-wave dep violation; legal intra-wave permutation OK; duplicate node; wrong wave; all nodes accounted for |
| P3-RECEIPT | 5 | Evidence-only marker; no semantic authority; no runtime authority; deterministic; schema_version guards version |
| P3-CLOSED | 4 | No concurrent-task class/coroutine; no blocking-wait; no async-runtime/process-fork; no perf claim |
| P3-GAP | 11 | All 11 card questions answered |

---

## Key Findings

**10-gate ReceiptReplayerP3 validation sequence:**
1. `schema_version` == 'replay-v0'
2. `graph_digest` matches current graph
3. `policy_digest` matches current policy  
   _(stop structural checks on gates 1–3 failure to avoid cascading errors)_
4. Node membership: no unknown, no missing, no duplicate
5. Wave assignment correctness
6. Same-wave dependency check (topological violation → fail)
7. Effect spec drift via `spec_digest`
8. Eligibility claim validation (re-evaluate `PolicyEvaluatorP3`)
9. Internal consistency: `result_digest == f(result_values)`
10. Re-execute scheduler → compare `result_values`

**Critical: Gate 10 is the only backstop for consistent result tampering.** An attacker who modifies `result_values` AND `result_digest` consistently passes Gate 9 but fails Gate 10. This is structurally necessary — no digest-chain guard can catch it.

**Replay-OK property for denied/no-policy receipts:** Receipts where `concurrent_eligible: false` (because of a denied capability or missing policy) replay successfully. The replayer validates that the denial is consistent with the current state — it does NOT require receipts to be eligible to be valid.

**Intra-wave permutation equivalence:** Reversing `node_ids` within a wave produces a valid receipt. The read-isolation invariant from P1 guarantees same-wave nodes have no mutual dependencies, making permutations structurally equivalent.

**DigestableMixin properties:**
- `graph_digest`: any change to node kind or dep set → different digest
- `policy_digest`: any change to allowed pairs or denied capability IDs → different digest
- `result_digest`: any change to any node's computed value → different digest
- `effect_spec_digest`: any change to resource_keys, effect_category, or capability_id → different digest

---

## Gap Packet

| Question | Answer |
|----------|--------|
| Receipts replayable? | YES — `valid: true` for all 5 replay-OK fixtures |
| Replay preserves results? | YES — `recomputed_result_values == receipt.result_values` |
| Legal intra-wave permutations equivalent? | YES — reversed node_ids still replays with identical values |
| Graph drift fails closed? | YES — Gate 2 catches all kind/dep changes |
| Policy drift fails closed? | YES — Gate 3 catches all allowed_pairs/denied_ids changes |
| Resource/effect drift fails closed? | YES — Gate 7 via spec_digest |
| Eligibility tampering fails closed? | YES — Gate 8 re-evaluates PolicyEvaluatorP3 |
| Consistent result tampering fails closed? | YES — Gate 10 (re-execution) catches it |
| Telemetry creates semantic authority? | NO — `scheduling-receipt-evidence-only-v0`; declared in source |
| Receipt opens runtime authority? | NO — no Thread/Fiber; declared in source |
| Next route | LAB-CONCURRENCY-P4 (multi-root/conditional DAGs) OR LAB-COMPILER-P5 (tagged union types) |

---

## Authority Constraints (preserved)

- Closed: real concurrent execution, real I/O, real network, runtime, production scheduling, semantic authority
- Forbidden: `Thread`, `Fiber`, `sleep`, async-runtime require
- No canon claim; no finalized API surface
- Lab-only; all modules proof-local
- `ReplayableReceipt` is `scheduling-receipt-evidence-only-v0` — telemetry evidence only

---

## Next Recommended Routes

**LAB-CONCURRENCY-P4**: Multi-root DAGs (multiple independent input chains), conditional-branch scheduling, dynamic topology. Prove replay boundary holds for non-static graph shapes.

**LAB-COMPILER-P5**: Express `DagNodeP3.kind` (`:input | :pure | :effectful`) and `EffectSpecP3.effect_category` as tagged unions in the igniter-lang type system. Ill-formed EffectSpec construction becomes a compile-time error rather than a replay-time error.

**LAB-CONCURRENCY-P3 / EffectSpec wiring**: Wire `EffectSpecP3.capability_id` to `HttpCapabilityPolicyP6` engine — network-call effect nodes derive resource keys and denial status from the capability grant table automatically.
