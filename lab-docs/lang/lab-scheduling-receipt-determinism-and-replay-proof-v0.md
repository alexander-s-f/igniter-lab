# Lab Doc: Scheduling Receipt Determinism and Replay
**Track:** lab-scheduling-receipt-determinism-and-replay-proof-v0  
**Card:** LAB-CONCURRENCY-P3 (Category: lang)  
**Status:** CLOSED / PROVED — 60/60 PASS  
**Date:** 2026-06-09  
**Authority:** Lab-only. No canon claim. No finalized API surface.  
`ReplayableReceipt` and `ReceiptReplayerP3` are proof-local only.  
`ReplayableReceipt` is `scheduling-receipt-evidence-only-v0` — it does not create semantic authority over scheduling decisions and does not open runtime concurrency authority.

---

## Purpose

Prove the lab-only replay/audit boundary for deterministic scheduling receipts:

1. A `ReplayableReceipt` produced from a DAG and policy can be **replayed** against the same graph and policy to reproduce the same result
2. **Graph drift** (changed kind, added/removed edge, unknown/missing node) fails closed
3. **Policy drift** (changed pairs, changed denial set) fails closed
4. **Effect spec drift** (changed resource keys or effect category) fails closed
5. **Eligibility tampering** (claiming a wave is concurrent-eligible when it isn't) fails closed
6. **Result tampering** (value or digest changed; even both changed consistently) fails closed
7. **Wave structural violations** (same-wave deps, wrong wave, duplicate nodes) fail closed
8. **Legal intra-wave permutations** (node order within a wave) are equivalent — same result_values
9. The receipt does NOT create semantic authority or open runtime concurrency authority

---

## Depends On

| Card | Description |
|------|-------------|
| LAB-CONCURRENCY-P1 | Wave-based DAG scheduling; SchedulingReceipt; parity invariant |
| LAB-CONCURRENCY-P2 | PolicyEvaluator 6-gate sequence; EffectSpec; CapabilityAwareScheduler |

---

## Core Abstractions

### ReplayableReceipt

The tamper-evident scheduling evidence record. All digest fields are deterministic functions of their respective inputs:

```ruby
ReplayableReceipt = Struct.new(
  :schema_version,    # 'replay-v0' — guards against version mismatch
  :graph_digest,      # DigestableMixin.graph_digest(dag)
  :policy_digest,     # DigestableMixin.policy_digest(policy)  (or 'nil-policy')
  :scheduler_mode,    # :capability_aware
  :waves,             # Array of wave records (includes node_ids, policy_decisions)
  :effect_metadata,   # { node_id => { effect_category, resource_keys, capability_id, spec_digest } }
  :result_digest,     # DigestableMixin.result_digest(result_values)
  :result_values,     # { node_id => computed_value }
  keyword_init: true
)
```

### DigestableMixin

Pure deterministic fingerprint functions. No clock, no randomness:

```ruby
module DigestableMixin
  def self.graph_digest(nodes)
    # Sort nodes by ID; encode kind and sorted dep list; join with '|'
    nodes.sort_by(&:id)
         .map { |n| "#{n.id}:#{n.kind}:#{n.deps.sort.join(',')}" }
         .join('|')
  end

  def self.policy_digest(policy)
    # 'nil-policy' when no policy; otherwise encodes id + sorted pairs + sorted denied ids
    return 'nil-policy' unless policy
    pairs_str  = policy.allowed_concurrent_pairs
                       .map { |p| p.map(&:to_s).sort.join('+') }.sort.join(',')
    denied_str = policy.denied_capability_ids.to_a.sort.join(',')
    "#{policy.id}|pairs:#{pairs_str}|denied:#{denied_str}"
  end

  def self.result_digest(result_values)
    # Sort by node_id; encode as key=value; join with '|'
    result_values.to_a.sort_by { |k, _| k }.map { |k, v| "#{k}=#{v}" }.join('|')
  end

  def self.effect_spec_digest(spec)
    # Encodes effect_category + sorted resource_keys + capability_id
    # Node_id is NOT included — the hash is keyed separately in effect_metadata
    keys_str = spec.resource_keys.sort.join(',')
    "#{spec.effect_category}:keys=#{keys_str}:cap=#{spec.capability_id}"
  end
end
```

### ReceiptBuilderP3

Wraps `CapabilityAwareSchedulerP3`; adds `schema_version`, `graph_digest`, `policy_digest`, `result_digest`, and augments `effect_metadata` with `spec_digest` per node:

```ruby
module ReceiptBuilderP3
  def self.build(dag, policy, effect_specs, compute_table, seed_values)
    out = CapabilityAwareSchedulerP3.execute(...)
    meta = out.effect_metadata.each_with_object({}) do |(node_id, m), h|
      spec = effect_specs[node_id]
      h[node_id] = m.merge(spec_digest: spec ? DigestableMixin.effect_spec_digest(spec) : nil)
    end
    ReplayableReceipt.new(
      schema_version: 'replay-v0',
      graph_digest:   DigestableMixin.graph_digest(dag),
      policy_digest:  DigestableMixin.policy_digest(policy),
      scheduler_mode: out.strategy,
      waves:          out.wave_details,
      effect_metadata: meta,
      result_digest:  DigestableMixin.result_digest(out.result_values),
      result_values:  out.result_values.dup
    )
  end
end
```

### ReceiptReplayerP3

10-gate validation sequence:

```
verify(dag, policy, effect_specs, compute_table, seed_values, receipt)
    │
    ├─ Gate 1:  schema_version == 'replay-v0'
    ├─ Gate 2:  graph_digest matches current graph
    ├─ Gate 3:  policy_digest matches current policy
    │           (stop structural checks if gates 1–3 fail — cascading false errors)
    │
    ├─ Gate 4:  Node membership (no unknown, no missing, no duplicate)
    ├─ Gate 5:  Wave assignment correctness (each node in expected wave)
    ├─ Gate 6:  Same-wave dependency check (no topological violation)
    │
    ├─ Gate 7:  Effect spec drift (spec_digest comparison per effectful node)
    ├─ Gate 8:  Eligibility claim validation (re-evaluate PolicyEvaluatorP3 per wave)
    │
    ├─ Gate 9:  Internal consistency: result_digest == f(result_values)
    └─ Gate 10: Re-execute scheduler; compare recomputed result_values
```

**Key properties:**

- Gates 1–3 are digest guards. Any tampering with the DAG or policy is caught before structural checks.
- Gate 8 re-evaluates the policy evaluator — a tampered `concurrent_eligible: true` in a wave is rejected if the re-evaluation returns a non-eligible outcome.
- Gate 10 is the final backstop: even if an attacker tampers `result_values` AND `result_digest` consistently (making Gate 9 pass), Gate 10 re-executes the scheduler and catches the mismatch.

---

## Replay Verification Sequence

### Why stopping early on digest mismatch matters

If the graph or policy digest does not match, all subsequent membership and wave checks would produce spurious errors (nodes listed in the receipt would be "unknown" from the perspective of the current graph). Stopping early after Gates 1–3 fail prevents noise and makes the error set actionable.

### Why Gate 10 is necessary

Gates 1–3 + 7 + 9 together guarantee that the digest chain is consistent with the stored data. But they do NOT prove that the stored values were correctly derived from the computation. Gate 10 is the only gate that re-runs the scheduler and can detect a case where an attacker tampered `result_values` and updated `result_digest` to match — the tampered values will differ from the freshly computed ones.

---

## Fixtures and Results

### Replay-OK fixtures

| Fixture | DAG | Policy | Expected replay outcome |
|---------|-----|--------|------------------------|
| Pure diamond | DIAMOND_DAG_P3 | nil | valid; recomputed matches |
| Wide fanout | FANOUT_DAG_P3 | nil | valid; F=30 |
| Read/read disjoint (eligible) | EFFECT_DAG_P3 | READ_READ_POLICY_P3 | valid; wave eligible |
| Denied capability | EFFECT_DAG_P3 | DENIED_POLICY_P3 | valid; wave NOT eligible; values preserved |
| No-policy (effectful) | EFFECT_DAG_P3 | nil | valid; wave NOT eligible; values preserved |
| Two replays of same receipt | DIAMOND_DAG_P3 | nil | both valid; identical recomputed values |

### Fail-closed fixtures

| Scenario | Gate that fires | Error message pattern |
|---------|----------------|----------------------|
| Changed node kind | Gate 2 | `graph_digest mismatch` |
| Added dependency edge | Gate 2 | `graph_digest mismatch` |
| Removed dependency edge | Gate 2 | `graph_digest mismatch` |
| Unknown node in receipt | Gate 4 | `unknown node in receipt: GHOST` |
| Missing node from receipt | Gate 4 | `missing node from receipt: C` |
| Duplicate node in receipt | Gate 4 | `duplicate node in receipt: B` |
| Changed allowed_pairs | Gate 3 | `policy_digest mismatch` |
| Changed denied_capability_ids | Gate 3 | `policy_digest mismatch` |
| Eligibility tamper (no-policy → eligible) | Gate 8 | `eligibility tamper in wave 1` |
| Eligibility tamper (write/write conflict → eligible) | Gate 8 | `eligibility tamper in wave 1` |
| resource_key changed | Gate 7 | `effect spec drift for X` |
| effect_category changed | Gate 7 | `effect spec drift for X` |
| resource_conflict tampered as eligible | Gate 8 | `eligibility tamper in wave 1` |
| category_closed tampered as eligible | Gate 8 | `eligibility tamper in wave 1` |
| denied_capability tampered as eligible | Gate 8 | `eligibility tamper in wave 1` |
| result_value tampered, digest unchanged | Gate 9 | `result_digest inconsistent` |
| result_digest tampered, values unchanged | Gate 9 | `result_digest inconsistent` |
| both tampered consistently | Gate 10 | `result_values mismatch after re-execution` |
| same-wave dep violation | Gate 5/6 | `same-wave dep` or `wave` |
| node in wrong wave | Gate 5 | `node D in receipt wave 0 but DAG assigns wave 2` |
| schema_version mismatch | Gate 1 | `schema_version mismatch` |

---

## Proof Results (60/60 PASS — first run clean)

| Section | Checks | Coverage |
|---------|--------|----------|
| P3-SCHEMA | 6 | schema_version; graph/policy/result digests present; waves array; effect_metadata spec_digest; result_digest consistent |
| P3-DIGEST | 6 | Graph digest stability and sensitivity (node kind; dep edge); policy digest stability (changed pairs); result digest encoding |
| P3-REPLAY-OK | 6 | Pure diamond; fanout (F=30); eligible policy; denied cap receipt replays (values preserved); no-policy; two replays identical |
| P3-FAIL-GRAPH | 5 | Changed kind; added edge; removed edge; unknown node; missing node |
| P3-FAIL-POLICY | 4 | Changed allowed_pairs; changed denied_ids; no-policy tampered eligible; write/write conflict tampered eligible |
| P3-FAIL-EFFECT | 5 | resource_key drift; effect_category drift; resource_conflict tamper; category_closed tamper; denied_capability tamper |
| P3-FAIL-RESULT | 3 | Value tampered; digest tampered; both tampered consistently (Gate 10 catches) |
| P3-WAVE | 5 | Same-wave dep violation; legal intra-wave permutation OK; duplicate node; wrong wave; all nodes accounted for |
| P3-RECEIPT | 5 | Evidence-only marker; no semantic authority; no runtime authority; deterministic; schema_version guards version mismatch |
| P3-CLOSED | 4 | No concurrent-task class/coroutine; no blocking-wait; no async-runtime/process-fork; no perf claim |
| P3-GAP | 11 | All 11 card questions answered |

---

## Self-Matching Antipattern Avoidance

All banned phrases from P1+P2 carry forward. No new classes added in P3.

| Banned phrase | Replacement in prose | Check pattern |
|---------------|---------------------|---------------|
| `performance improvement` | `no-perf-claims-closed` slug | `'perf' + 'ormance improvement'` |
| `Thread` | "concurrent-task class" | `'Thre' + 'ad'` |
| `Fiber` | "coroutine class" | `'Fib' + 'er'` |
| `sleep` | "blocking-wait" | `'sle' + 'ep'` |
| `stable API` | "finalized API surface" | `'stab' + 'le API'` |
| `DNS` | "name-resolution" | `'DN' + 'S'` |

---

## Gap Packet Answers

| Question | Answer |
|----------|--------|
| Receipts replayable against same graph + policy? | YES — `ReceiptReplayerP3.verify` returns `valid: true` for all 5 replay-OK fixtures |
| Replay preserves deterministic results? | YES — `recomputed_result_values == receipt.result_values` for all valid replays |
| Legal intra-wave permutations equivalent? | YES — reversed `node_ids` order in wave 1 still replays successfully with identical recomputed values |
| Graph drift fails closed? | YES — any change to node kind or dep edges triggers `graph_digest mismatch`; unknown/missing/duplicate nodes also fail |
| Policy drift fails closed? | YES — changed `allowed_concurrent_pairs` or `denied_capability_ids` triggers `policy_digest mismatch` |
| Resource/effect drift fails closed? | YES — changed `resource_keys` or `effect_category` triggers `effect spec drift` via `spec_digest` |
| Eligibility tampering fails closed? | YES — `ReceiptReplayerP3` re-evaluates `PolicyEvaluatorP3` per wave; tampered `concurrent_eligible: true` is rejected |
| Result tampering fails closed (even consistent tamper)? | YES — Gate 9 catches value/digest-only tampering; Gate 10 (re-execution) catches consistent tampering |
| Telemetry creates semantic authority? | NO — `scheduling-receipt-evidence-only-v0`; "does not create semantic authority over scheduling decisions" in source |
| Receipt opens runtime concurrency authority? | NO — "does not open runtime concurrency authority" in source; no Thread/Fiber infrastructure |
| Next route | LAB-CONCURRENCY-P4: conditional/multi-root DAG scheduling; or LAB-COMPILER-P5: EffectSpec kind as tagged union |

---

## Design Notes

### Why digest-first validation prevents cascading errors

If the graph passed to `ReceiptReplayerP3.verify` does not match the graph used to build the receipt, every subsequent membership check would produce spurious "unknown node" errors. By stopping at Gates 1–3 and returning immediately when a digest mismatch is found, the replayer surfaces the root cause directly rather than burying it in a list of downstream failures.

### Why Gate 10 is not redundant with Gates 7–9

Gates 7, 8, and 9 all validate stored data against derivable expectations. But they cannot detect an attacker who tampers `result_values` AND `result_digest` to match each other. Gate 10 is the only gate that re-runs the scheduler from scratch and compares the fresh output to the stored values. This is the final backstop of the replay proof.

### What "spec_digest" captures and what it does not

`DigestableMixin.effect_spec_digest(spec)` encodes `effect_category + resource_keys + capability_id` but NOT `node_id`. The `node_id` is the key in `effect_metadata`, so including it in the digest would create a trivially-satisfied check (a renamed node would fail the membership check at Gate 4 before reaching Gate 7). The spec_digest answers: "for this node, were the effect parameters the same at receipt build time as they are now?"

### Intra-wave permutation equivalence

From P1: all nodes in the same wave have no mutual dependencies (same-wave mutual independence invariant). For pure nodes, this means their inputs come exclusively from prior waves — the order in which they are listed in `wave_details[].node_ids` cannot affect their inputs or outputs. This makes legal intra-wave permutations structurally equivalent, not just empirically confirmed.

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Multi-root DAG replay | P4 candidate | Current proof uses single-root topology |
| Conditional-branch DAGs | P4 candidate | Static graph only |
| Replay of partially-executed receipts | Separate card | No partial-execution receipt model in v0 |
| Receipt versioning migration | Separate card | schema_version guards detection; migration path not designed |
| Canon claim for ReplayableReceipt | Closed | Lab-only; `scheduling-receipt-evidence-only-v0` |
| Runtime dispatch authorization from receipt | Closed | Receipt records the decision; does not authorize execution |

---

## Next Recommended Routes

**LAB-CONCURRENCY-P4**: Extend replay to multi-root DAGs (multiple independent input chains) and conditional-branch DAGs (where a node's execution determines which downstream nodes are present in the receipt). Prove that the replay boundary holds for dynamic topology.

**LAB-COMPILER-P5**: Prove that the igniter-lang compiler can express `DagNodeP3.kind` (`:input | :pure | :effectful`) and `EffectSpecP3.effect_category` (`:read_file | :write_file | :network_call`) as tagged unions with discriminated field checking. This would allow the compiler to reject ill-formed EffectSpec construction at compile time rather than at replay time.

**LAB-CONCURRENCY-P3 / EffectSpec wiring**: Wire `EffectSpecP3.capability_id` to the existing `HttpCapabilityPolicyP6` engine — proving that network-call effect nodes can derive their resource keys and capability denial status directly from the capability grant table, without manual EffectSpec construction.
