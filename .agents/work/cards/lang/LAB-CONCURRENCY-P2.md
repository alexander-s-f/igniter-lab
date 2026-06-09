# Card: LAB-CONCURRENCY-P2
**Category:** lang  
**Track:** lab-capability-aware-effect-scheduling-policy-boundary-v0  
**Status:** CLOSED / PROVED — 59/59 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Prove the lab-only boundary for capability-aware scheduling of effectful DAG nodes:
- Effectful nodes remain serialized or rejected by default (v0)
- Concurrent dispatch requires an explicit `SchedulingPolicy` with allowed category pairs
- Policy eligibility also requires disjoint resource keys and no denied capabilities
- Scheduling decisions are deterministic receipts — not runtime authority
- P1 pure-DAG behavior is preserved: pure nodes remain eligible without policy

---

## Depends On

| Card | Status |
|------|--------|
| LAB-CONCURRENCY-P1 | ✅ DONE (57/57) |
| LAB-STDLIB-NET-P8 | ✅ DONE (50/50) |
| LAB-STDLIB-NET-P9 | ✅ DONE (55/55) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-view-engine/proofs/capability_aware_effect_scheduling_proof.rb` | DONE — 59/59 PASS |
| Lab doc | `lab-docs/lang/lab-capability-aware-effect-scheduling-policy-boundary-v0.md` | DONE |

---

## Proof Sections (59 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| P2-DEFAULT | 6 | Default v0 serialization; :no_policy decision; P1 regression; single-node case |
| P2-POLICY | 7 | Struct shape; gate order; no_policy; eligible; category_closed; policy_id; reason strings |
| P2-RESOURCE | 8 | read/read disjoint; write/write conflict; read/write conflict; unknown key; disjoint? helper; conflict reason |
| P2-NETWORK | 6 | net_disjoint eligible; wave eligible; same_host_closed; "net:" prefix; no real I/O; mixed category_closed |
| P2-DENY | 5 | capability_denied outcome; Gate 1 fires first; wave not eligible; reason includes cap_id; empty set passes |
| P2-COMPOSE | 6 | Eligible correct values; serialized correct values; parity; mixed-DAG; strategy field; denied still computes |
| P2-RECEIPT | 6 | policy_id nil/present; effect_category; resource_keys; policy_decisions; reason string; deterministic |
| P2-CLOSED | 5 | No concurrent-task class; no coroutine; no async/fork; no finalized-API/canon; no perf-claim |
| P2-GAP | 10 | All 10 card questions answered |

---

## Key Findings

**PolicyEvaluator gate sequence proved:**
- Gate 1: Capability denial (pre-eminent; fires before all other gates)
- Gate 2: No policy → `:no_policy` (serialized by default)
- Gate 3: Empty resource_keys → `:unknown_resource` (fail-closed)
- Gate 4: Overlapping keys with write → `:resource_conflict` (rejected)
- Gate 5: Category pair not in allowed list → `:category_closed`
- Gate 6: All gates passed → `:eligible`

**Parity property:**
`result_values` is identical regardless of `concurrent_eligible` flag. Scheduling decisions never change computed values. This is structurally guaranteed by P1's read-isolation invariant.

**EffectSpec resource key scheme:**
- `"file:/path/to/resource"` — file system
- `"net:hostname"` — network host target
- Empty `resource_keys` → automatically rejected (unknown_resource gate)

**Concrete fixture outcomes (8 fixtures):**
- `default_effect_serialized`: `:no_policy` → not eligible
- `read_read_disjoint_policy`: `:eligible` → wave eligible
- `write_write_same_resource`: `:resource_conflict` → not eligible (policy category allowed but resource conflict wins)
- `read_write_same_resource`: `:resource_conflict` → not eligible
- `net_disjoint_hosts`: `:eligible` → wave eligible
- `net_same_host_policy_closed`: `:category_closed` → not eligible
- `unknown_resource_key`: `:unknown_resource` → not eligible
- `denied_capability`: `:capability_denied` → not eligible

---

## Self-Matching Antipattern Fixes

New class for P2: `performance improvement` as a contiguous phrase.

- **`performance improvement`** appeared in the file header comment AND in the P2-GAP-09 check label. Fix: changed comment to `no-perf-claims-closed` (a tagged slug); changed GAP-09 positive marker to `'no-perf-claims-closed'`; changed label to avoid the full phrase.

Ongoing (same as P1):
- `Thread` → `'Thre' + 'ad'`
- `Fiber` → `'Fib' + 'er'`
- `sleep` → `blocking-wait` in prose; `'sle' + 'ep'` in check
- `stable API` → `'stab' + 'le API'`

---

## Gap Packet

| Question | Answer |
|----------|--------|
| Effectful concurrent by default? | NO — `:no_policy` → not eligible |
| Explicit policy required? | YES — nil policy gates all pairs as `:no_policy` |
| Disjoint reads can be eligible? | YES — with matching category pair and non-empty disjoint keys |
| Overlapping writes closed? | YES — `:resource_conflict` regardless of policy category allowance |
| Unknown resource keys fail closed? | YES — `:unknown_resource` gate |
| Denied capability prevents scheduling? | YES — Gate 1; fires before any other check |
| Deterministic receipts represent decisions? | YES — `PolicySchedulingReceipt.wave_details[*].policy_decisions` |
| Real threading opened? | NO — no Thread/Fiber; receipt-only |
| Perf claims made? | NO — `no-perf-claims-closed`; parity is correctness, not speed |
| Lab behavior creates canon authority? | NO — proof-local only; no canon claim |
| Next route | LAB-CONCURRENCY-P3 (multi-root/conditional DAGs) OR LAB-COMPILER-P5 (type system) |

---

## Authority Constraints (preserved)

- Closed: real concurrent execution, real I/O, real network, runtime, production scheduling
- Forbidden: `Thread`, `Fiber`, `sleep`, async-runtime require
- No canon claim; no finalized API surface
- Lab-only; all modules proof-local
- `PolicySchedulingReceipt` is telemetry evidence only; no semantic or runtime authority

---

## Next Recommended Routes

**LAB-CONCURRENCY-P3**: Multi-root DAGs, conditional-branch scheduling, dynamic topology.

**LAB-COMPILER-P5**: Express DagNodeP2 kind and EffectSpec.effect_category as tagged unions in igniter-lang type system.

**LAB-CONCURRENCY-P2 / EffectSpec wiring**: Wire `EffectSpec.capability_id` to `HttpCapabilityPolicyP6` so network-call effect nodes derive resource keys and denial status from the existing capability grant table.
