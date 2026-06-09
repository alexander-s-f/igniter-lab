# Lab Doc: Capability-Aware Effect Scheduling Policy Boundary
**Track:** lab-capability-aware-effect-scheduling-policy-boundary-v0  
**Card:** LAB-CONCURRENCY-P2 (Category: lang)  
**Status:** CLOSED / PROVED — 59/59 PASS  
**Date:** 2026-06-09  
**Authority:** Lab-only. No canon claim. No finalized API surface.  
`CapabilityAwareScheduler` and `PolicyEvaluator` are proof-local only.  
`PolicySchedulingReceipt` is telemetry evidence; it does not open runtime concurrency authority.

---

## Purpose

Prove the lab-only boundary for capability-aware scheduling of effectful DAG nodes:

1. Effectful nodes are **not** concurrent-eligible by default (v0 baseline from P1 preserved)
2. Concurrent effectful dispatch requires an **explicit scheduling policy** object
3. Policy eligibility further requires: disjoint resource keys, compatible effect categories, and no denied capabilities
4. Scheduling decisions are recorded in a deterministic `PolicySchedulingReceipt` but do NOT open runtime authority
5. P1 pure-DAG behavior is unchanged: pure nodes remain concurrent-eligible without any policy

---

## Depends On

| Card | Description |
|------|-------------|
| LAB-CONCURRENCY-P1 | Wave-based DAG scheduling; SchedulingReceipt; pure-wave eligibility |
| LAB-STDLIB-NET-P8 | HttpResult capability denial as typed data; capability_id pattern |
| LAB-STDLIB-NET-P9 | Capability policy gate before transport; ContractResult denial branch |

---

## Core Abstractions

### EffectSpec
```ruby
EffectSpec = Struct.new(:node_id, :effect_category, :resource_keys, :capability_id,
                        keyword_init: true)
# effect_category: :read_file | :write_file | :network_call | :unknown_effect
# resource_keys:   ["file:/data/a.txt"] | ["net:api.example.com"] | [] (unknown → rejected)
# capability_id:   String — checked against policy.denied_capability_ids
```

### SchedulingPolicy
```ruby
SchedulingPolicy = Struct.new(:id, :allowed_concurrent_pairs, :denied_capability_ids,
                               keyword_init: true)
# allowed_concurrent_pairs: [[:read_file, :read_file], [:network_call, :network_call], ...]
# denied_capability_ids:    Set[String]
```

### PolicyDecision
```ruby
PolicyDecision = Struct.new(:outcome, :reason, :resource_keys_a, :resource_keys_b,
                             :policy_id, keyword_init: true)
# outcome: :eligible | :no_policy | :capability_denied | :unknown_resource |
#          :resource_conflict | :category_closed
```

---

## PolicyEvaluator Gate Sequence

```
check_pair(spec_a, spec_b, policy)
    │
    ├─ Gate 1: capability denial?
    │           policy.denied_capability_ids.include?(spec.capability_id)
    │           → :capability_denied  (short-circuit; no further gates evaluated)
    │
    ├─ Gate 2: no policy provided?
    │           policy == nil
    │           → :no_policy  (serialized by default v0 rule)
    │
    ├─ Gate 3: unknown resource key?
    │           spec.resource_keys.empty?
    │           → :unknown_resource  (cannot prove disjoint; rejected)
    │
    ├─ Gate 4: resource conflict?
    │           overlapping keys AND any write category involved
    │           → :resource_conflict  (rejected; both writes AND read/write)
    │
    ├─ Gate 5: category pair closed?
    │           [cat_a, cat_b].sort not in policy.allowed_concurrent_pairs
    │           → :category_closed  (serialized; pair not listed)
    │
    └─ Gate 6: all gates passed
                → :eligible
```

**Key property:** Gate 1 (capability denial) fires even when a policy is present. Denial is pre-eminent — a denied capability_id cannot be rescued by resource disjointness or category allowance.

---

## Fixtures and Results

| Fixture | Effect specs | Policy | PolicyEvaluator outcome | Wave eligible |
|---------|-------------|--------|------------------------|---------------|
| `default_effect_serialized` | read/read disjoint | nil | :no_policy | false |
| `read_read_disjoint_policy` | read/read disjoint | read-read policy | :eligible | true |
| `write_write_same_resource` | write/write same key | write-write policy | :resource_conflict | false |
| `read_write_same_resource` | read/write same key | read-write policy | :resource_conflict | false |
| `net_disjoint_hosts` | network/network disjoint | net policy | :eligible | true |
| `net_same_host_policy_closed` | network/network same host | empty-pairs policy | :category_closed | false |
| `unknown_resource_key` | read/read, one empty | read-read policy | :unknown_resource | false |
| `denied_capability` | read/read disjoint | denied cap policy | :capability_denied | false |

---

## CapabilityAwareScheduler Wave Eligibility

For each wave:
- **Pure-only wave**: `concurrent_eligible: true` (no policy needed; same as P1)
- **Single effectful node**: `concurrent_eligible: false` (nothing to parallelize; no basis for eligibility claim)
- **2+ effectful nodes**: check all pairs via `PolicyEvaluator.check_pair`
  - `concurrent_eligible: true` iff ALL pairs return `:eligible`
  - `concurrent_eligible: false` if ANY pair returns non-eligible

**Critical distinction**: `concurrent_eligible: true` is a **scheduling decision record**. The scheduler does not actually dispatch nodes to concurrent workers. It records evidence that concurrent dispatch would be permitted by policy if a runtime scheduling mechanism were present.

This is the lab-only boundary claim: the proof models the *policy decision*, not the *execution mechanism*.

---

## Parity Property (P2-COMPOSE-03)

**Scheduling decisions do not affect computed values.**

```
eligible path:   CapabilityAwareScheduler(policy: READ_READ_POLICY).result_values
                 == { 'A'=>0, 'X'=>10, 'Y'=>20, 'Z'=>30 }

serialized path: CapabilityAwareScheduler(policy: nil).result_values
                 == { 'A'=>0, 'X'=>10, 'Y'=>20, 'Z'=>30 }
```

Concurrent eligibility changes the scheduling receipt but never changes the computed output. This is structurally guaranteed by the read-isolation invariant from P1: effectful nodes in the same wave have no mutual dependencies, so their execution order cannot change their inputs.

---

## PolicySchedulingReceipt

```
PolicySchedulingReceipt {
  strategy:             :capability_aware
  execution_order:      [node_id, ...]
  wave_assignments:     { node_id => wave_number }
  wave_details:         [{ wave, pure_nodes, effectful_nodes, concurrent_eligible,
                           policy_decisions: [PolicyDecision], policy_id,
                           effect_categories, resource_keys }]
  dependency_edges:     [[from_id, to_id], ...]
  node_classifications: { node_id => :input | :pure | :effectful }
  result_values:        { node_id => computed_value }
  effect_metadata:      { node_id => { effect_category, resource_keys, capability_id } }
  policy_id:            String | nil
}
```

The receipt is deterministic: given the same DAG, EffectSpecs, and SchedulingPolicy, two runs produce identical result_values, effect_metadata, and policy_id.

---

## Self-Matching Antipattern Avoidance

New class for P2: `performance improvement` as a contiguous phrase.

| Banned phrase | Replacement in prose | Check pattern |
|---------------|---------------------|---------------|
| `performance improvement` | `no-perf-claims-closed` | `'perf' + 'ormance improvement'` |
| `Thread` | "concurrent-task class" | `'Thre' + 'ad'` |
| `Fiber` | "coroutine class" | `'Fib' + 'er'` |
| `sleep` | "blocking-wait" | `'sle' + 'ep'` |
| `stable API` | "finalized API surface" | `'stab' + 'le API'` |
| `DNS` | "name-resolution" | `'DN' + 'S'` |

The positive marker `'no-perf-claims-closed'` appears in the file header so the P2-GAP-09 check can scan for it without the check body containing the banned phrase.

---

## Proof Results (59/59 PASS)

| Section | Checks | Coverage |
|---------|--------|----------|
| P2-DEFAULT | 6 | Default v0 serialization; no-policy pair decision; P1 regression: pure diamond + correct values; single effectful node |
| P2-POLICY | 7 | Struct shape; gate order (denial before no_policy); no_policy gate; eligible gate; category_closed gate; policy_id in decision; reason string |
| P2-RESOURCE | 8 | read/read disjoint eligible; write/write same rejected; read/write same rejected; unknown_resource; disjoint? helper; conflict reason string |
| P2-NETWORK | 6 | net_disjoint eligible; wave eligible; same_host_closed; host-key "net:" prefix; no real I/O; mixed IO+net category_closed |
| P2-DENY | 5 | capability_denied outcome; Gate 1 before Gate 5; wave not eligible; reason includes cap_id; empty denied set passes |
| P2-COMPOSE | 6 | Eligible correct values; serialized correct values; parity; mixed-DAG pure+effectful; strategy field; denied still computes values |
| P2-RECEIPT | 6 | policy_id nil/present; effect_category in metadata; resource_keys in metadata; policy_decisions in wave_details; reason string; deterministic |
| P2-CLOSED | 5 | No concurrent-task class; no coroutine; no async-runtime/process-fork; no finalized-API/canon-claim; no perf-claim/production-claim |
| P2-GAP | 10 | All 10 card questions answered |

---

## Gap Packet Answers

| Question | Answer |
|----------|--------|
| Effectful nodes concurrent by default? | NO — v0 default: all effectful pairs return `:no_policy`; wave not concurrent-eligible |
| Explicit scheduling policy required? | YES — `PolicyEvaluator.check_pair` requires a non-nil `SchedulingPolicy` for eligibility |
| Disjoint read-only resources can be eligible? | YES — with `allowed_concurrent_pairs: [[:read_file, :read_file]]` and non-empty disjoint keys |
| Overlapping writes remain closed? | YES — Gate 4 catches write involvement in overlapping keys as `:resource_conflict` regardless of policy |
| Unknown resource keys fail closed? | YES — Gate 3 catches empty `resource_keys` as `:unknown_resource` |
| Denied capability prevents scheduling? | YES — Gate 1 fires first; denial short-circuits all other gates |
| Deterministic receipts represent decisions? | YES — `PolicySchedulingReceipt.wave_details[*].policy_decisions` records outcome + reason + resource_keys |
| Real threading opened? | NO — no `Thread`/`Fiber`/async-runtime in source; `concurrent_eligible` is a receipt field only |
| Perf claims made? | NO — `no-perf-claims-closed`; parity proof is about correctness, not speed |
| Lab behavior creates canon authority? | NO — proof-local only; `No canon claim` in file header |
| Next route recommendation | LAB-CONCURRENCY-P3: extend policy model to multi-root DAGs and conditional branches; OR LAB-COMPILER-P5: express `:input | :pure | :effectful` as tagged union in igniter-lang type system |

---

## Design Notes

### Why capability denial fires first (Gate 1 before Gate 2)

Capability denial is pre-eminent because it represents an active policy decision by the
capability authority — not an absence of configuration. Even when a policy object is
present and would otherwise permit concurrent dispatch, a denied capability_id means the
capability authority has explicitly withdrawn authorization. Checking this last would allow
a policy grant to appear to supersede a denial, which is the wrong authority ordering.

This matches the P8/P9 pattern where `HttpResult{ kind: "denied" }` short-circuits
domain logic: denial flows through the composition chain without being overridden by
downstream rules.

### Why the parity property is structurally guaranteed

From P1: all nodes in the same wave have no mutual dependencies (same-wave mutual
independence invariant). For effectful nodes in a wave, this means each effectful node
reads only from prior waves — the same inputs regardless of intra-wave execution order.
Therefore, changing the scheduling decision from `concurrent_eligible: false` to `true`
cannot change any computed value. `result_values` is always the parity proof.

### Resource key scheme

Resource keys are opaque strings with a category prefix:
- `"file:/path/to/resource"` — file system resources
- `"net:hostname"` — network host targets

The scheme is proof-local. A production policy engine would derive resource keys from
the capability grant's `allowed_hosts`, `allowed_paths`, or equivalent fields. The key
design requirement is that the key uniquely identifies the resource at scheduling decision
time, so that disjointness can be evaluated without executing the effect.

### What "concurrent_eligible" means and doesn't mean

`concurrent_eligible: true` means:
- The `PolicyEvaluator` determined that all effectful pairs in this wave satisfy the policy
- The scheduling receipt records this decision
- **If** a runtime scheduling mechanism were present, it would be permitted to dispatch these nodes concurrently

`concurrent_eligible: true` does NOT mean:
- The nodes were actually dispatched to concurrent workers
- Real I/O was performed concurrently
- Any runtime concurrency authority was opened
- The decision has been certified for production use

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Concurrent-effectful runtime dispatch | Runtime gate closed | `concurrent_eligible` is receipt-only in v0 |
| Multi-root DAG policy (multiple input nodes) | P3 candidate | Current proof uses single-root topology |
| Conditional-branch DAGs | P3 candidate | Static graph only; no runtime-conditional scheduling |
| Policy composition (multiple policies) | Separate card | Single policy object per scheduler call |
| Resource key derivation from capability grants | Separate card | Keys are declared manually in EffectSpec |
| Write commutativity proofs | Far future | Overlapping writes are unconditionally rejected |
| `unknown_effect` category handling | Separate card | Currently no policy allows `:unknown_effect` |

---

## Next Recommended Routes

**LAB-CONCURRENCY-P3**: Extend the capability-aware policy model to multi-root DAGs
(multiple independent input chains) and conditional-branch DAGs (where a node's
execution determines which downstream nodes are scheduled). Prove that the parity
property holds across dynamic topologies.

**LAB-COMPILER-P5**: Prove that the igniter-lang compiler can express the DagNodeP2
kind discriminant (`:input | :pure | :effectful`) and `EffectSpec.effect_category`
(`:read_file | :write_file | :network_call | :unknown_effect`) as tagged unions or
nominal Records with discriminated field checking.

**LAB-CONCURRENCY-P2 / EffectSpec production path**: Wire `EffectSpec.capability_id`
to the existing `HttpCapabilityPolicyP6` engine — proving that network-call effect
nodes can derive their resource keys and capability denial status directly from the
capability grant table, without manual EffectSpec construction.
