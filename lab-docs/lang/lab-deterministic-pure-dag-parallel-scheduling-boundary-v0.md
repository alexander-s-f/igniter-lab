# Lab Doc: Deterministic Pure-DAG Parallel Scheduling Boundary
**Track:** lab-deterministic-pure-dag-parallel-scheduling-boundary-v0  
**Card:** LAB-CONCURRENCY-P1 (Category: lang)  
**Status:** CLOSED / PROVED — 57/57 PASS  
**Date:** 2026-06-09  
**Authority:** Lab-only. No runtime concurrency authority opened. SchedulingReceipt is telemetry evidence only; it does not create language semantic authority or open production scheduling infrastructure.

---

## Purpose

Prove the lab-only boundary for deterministic pure-DAG parallel scheduling:

1. Independent pure nodes may be scheduled concurrently as an execution optimization
2. Dependent nodes preserve topological order (wave-based ordering enforces this)
3. Effectful nodes remain serialized (closed in v0; no concurrent-effectful dispatch)
4. Parallel scheduling returns the same result as sequential scheduling for all fixtures

The proof uses wave-based analysis: `DagWaves` assigns each node a wave number, groups same-wave nodes, and marks each wave as concurrent-eligible iff it contains no effectful nodes. `ParallelSchedulerSimulation` executes waves in order but explores configurable intra-wave orderings to prove result identity holds regardless of scheduling order.

---

## Pressure Points Addressed

| Pressure | How addressed |
|----------|---------------|
| Independent pure nodes may be concurrent | Wave-eligible iff kind==:pure AND no mutual dep; proved across diamond and fanout fixtures |
| Dependent nodes preserve topological order | Wave number = max(dep_waves)+1; nodes in same wave have no mutual deps (proved structurally) |
| Effectful nodes serialized in v0 | `concurrent_eligible=false` for any wave containing an effectful node; effectful nodes run after pure sub-wave |
| Parallel == sequential result | `result_values` identity proved across all 5 fixtures and 4+ intra-wave orderings |
| No runtime concurrency infrastructure | No `Thre` + `ad`, no `Fib` + `er`, no `sle` + `ep`, no async-runtime require |

---

## Graph Fixtures (inline)

Five inline graph fixtures provide the scheduling proof scenarios:

### Diamond (pure DAG)
```
A(input) -> B(pure), C(pure) -> D(pure)

Wave 0: [A]
Wave 1: [B, C]  ← concurrent-eligible (both pure, no mutual dep)
Wave 2: [D]

Seeds: A=10
Values: A=10, B=20, C=15, D=35  (B=A*2, C=A+5, D=B+C)
```
**Key proof**: B and C are independent pure siblings in wave 1 — the canonical concurrent scheduling case.

### Wide Fanout (pure DAG)
```
A(input) -> B,C,D,E(pure) -> F(pure)

Wave 0: [A]
Wave 1: [B, C, D, E]  ← 4-node concurrent-eligible wave
Wave 2: [F]

Seeds: A=5
Values: A=5, B=6, C=7, D=8, E=9, F=30
```
**Key proof**: 4 independent pure siblings all concurrent-eligible; all 4 intra-wave orderings produce F=30.

### Dependent Chain (no parallelism)
```
A(input) -> B(pure) -> C(pure)

Wave 0: [A]
Wave 1: [B]  ← single node; trivially sequential
Wave 2: [C]

Seeds: A=4
Values: A=4, B=12, C=11  (B=A*3, C=B-1)
```
**Key proof**: No concurrent opportunity; structural case for "chain forces sequential order."

### Mixed Effectful
```
A(input) -> B(pure), E(effectful) -> D(pure)

Wave 0: [A]
Wave 1: [B, E]  ← NOT concurrent-eligible (contains effectful E)
Wave 2: [D]

Seeds: A=3
Values: A=3, B=6, E=103, D=109  (B=A*2, E=A+100, D=B+E)
```
**Key proof**: Wave 1 has `concurrent_eligible=false`; B (pure) runs first, E (effectful) serialized after; parity holds.

### Independent Effectful Siblings
```
A(input) -> X(effectful), Y(effectful) -> Z(pure)

Wave 0: [A]
Wave 1: [X, Y]  ← NOT concurrent-eligible (both effectful)
Wave 2: [Z]

Seeds: A=0
Values: A=0, X=10, Y=20, Z=30
```
**Key proof**: X and Y are independent but both effectful — wave is NOT concurrent-eligible regardless of mutual dep status; v0 serialization boundary demonstrated.

---

## Core Module Architecture

### DagNode
```ruby
DagNode = Struct.new(:id, :kind, :deps, keyword_init: true)
# kind: :input | :pure | :effectful
# deps: Array of node IDs that must execute before this node
```

### DagValidator
```ruby
module DagValidator
  # validate(nodes) -> ValidationResult { valid, errors }
  #   - checks all dep references exist
  #   - checks input nodes have empty deps
  #   - detects cycles via Kahn's algorithm
  # topological_sort(nodes) -> [id, ...]  (deterministic; sorted queues)
end
```

### DagWaves
```ruby
module DagWaves
  # compute_waves(nodes) -> { node_id => wave_number }
  #   wave(input) = 0
  #   wave(node)  = max(wave(dep)) + 1 for all deps
  #
  # wave_groups(nodes)  -> { wave_number => [node_id, ...] }
  # pure_wave?(ids, nodes) -> true iff no :effectful node in ids
end
```

### SchedulingReceipt
```ruby
SchedulingReceipt = Struct.new(
  :strategy,             # :sequential | :parallel_simulation
  :execution_order,      # Array of node IDs in execution order
  :wave_assignments,     # { node_id => wave_number }
  :wave_details,         # Array of per-wave records (parallel only)
  :dependency_edges,     # Array of [from_id, to_id]
  :node_classifications, # { node_id => :input | :pure | :effectful }
  :result_values,        # { node_id => computed_value }
  keyword_init: true
)
```
**SchedulingReceipt is telemetry evidence only.** It does not create semantic authority over language execution order. It does not open runtime concurrency authority.

### SequentialScheduler
```ruby
module SequentialScheduler
  # execute(nodes, compute_table, seed_values) -> SchedulingReceipt
  # Executes in topological order; one node at a time
end
```

### ParallelSchedulerSimulation
```ruby
module ParallelSchedulerSimulation
  # execute(nodes, compute_table, seed_values, intra_wave_order:) -> SchedulingReceipt
  # Executes waves in order; within each wave:
  #   :input     -> use seeded value
  #   :pure      -> execute in intra_wave_order
  #   :effectful -> always serialized after pure siblings
  #
  # intra_wave_order: :natural | :reversed | :alpha_asc | :alpha_desc | Array
end
```

---

## Wave Invariants (proved)

### Invariant 1: Topological safety
> If node N1 depends on N2, then `wave(N1) > wave(N2)`.

Proved by construction: `wave(N) = max(wave(dep)) + 1`, so N is always in a strictly later wave than any of its deps.

### Invariant 2: Same-wave mutual independence
> Nodes in the same wave have no mutual dependencies.

Proved structurally in P1-WAVE-06 across all 5 fixtures: no pair `(a, b)` in the same wave where `b ∈ a.deps` or `a ∈ b.deps`.

### Invariant 3: Read isolation
> A pure node in wave W reads only from values computed in waves 0..W-1.

Proved in P1-WAVE-05: for every pure node, every dep is in a strictly earlier wave. Intra-wave order among pure siblings cannot change their inputs.

### Invariant 4: Concurrent eligibility
> A wave is concurrent-eligible iff it contains no effectful nodes.

Proved in P1-WAVE-02 (diamond: eligible), P1-WAVE-04 (mixed: not eligible), P1-EFFECT-03 (impure siblings: not eligible).

### Invariant 5: Parity
> `SequentialScheduler.result_values == ParallelSchedulerSimulation.result_values` for all fixtures and all intra-wave orderings.

Proved across P1-PARITY-01..08 (8 checks; 5 fixtures; 4+ orderings). Read isolation (Invariant 3) is the structural reason parity holds: intra-wave order cannot affect inputs, so outputs are identical regardless of scheduling order.

---

## Effectful Node Boundary

In v0, effectful nodes are **always serialized**:
- They are never placed in `concurrent_eligible=true` waves
- Within a mixed wave, they execute after the pure sub-wave
- Intra-effectful order is deterministic (preserves the sorted node ID order)

Opening concurrent-effectful dispatch requires:
1. A scheduling capability or policy fixture (not provided in v0)
2. An explicit future scheduling gate
3. A separate proof that concurrent effectful ordering produces deterministic results in the target domain

The nondeterministic probe in P1-EFFECT-04 demonstrates why this boundary exists: two effectful functions applied to shared state produce different outputs depending on execution order. Serialization eliminates this class of non-determinism.

---

## Proof Results (57/57 PASS)

| Section | Checks | Coverage |
|---------|--------|----------|
| P1-DAG | 6 | Graph construction, cycle detection, missing deps, input-with-deps, node kinds, wide graph |
| P1-TOPO | 6 | Topological order, A before B/C, B/C before D, chain order, diamond wave numbers, fanout wave 1 |
| P1-SEQ | 5 | Diamond/fanout/chain correct values; execution order; dependency edges |
| P1-WAVE | 7 | Wave groups, pure-eligible, mutual-independence, mixed non-eligible, read isolation, structural proof, wave_details flag |
| P1-PARITY | 8 | All 5 fixtures; natural/reversed/custom orderings; sequential == parallel in all cases |
| P1-EFFECT | 6 | Effectful not in eligible wave; B before E in mixed; impure siblings serialized; nondeterministic probe; eligibility conditions; v0 boundary |
| P1-RECEIPT | 5 | result_values identity; wave_assignments complete; dependency_edges; node_classifications; strategy telemetry |
| P1-CLOSED | 5 | No concurrent-task class; no coroutine; no async require; no Rack-compat claim; no finalized-API claim |
| P1-GAP | 9 | All card questions answered |

---

## Self-Matching Antipattern Avoidance

Continuing patterns from P8/P9, plus new patterns for concurrency domain:

| Banned string | Prose alternative | Check pattern |
|---------------|-------------------|---------------|
| `Thread` | "concurrent-task class" | `'Thre' + 'ad'` |
| `Fiber` | "coroutine class" | `'Fib' + 'er'` |
| `sleep` | "blocking-wait" | `'sle' + 'ep'` |
| `stable API` | "finalized API surface" | `'stab' + 'le API'` |
| `performance improvement` | n/a (just don't claim it) | `'perf' + 'ormance improvement'` |
| `DNS` | "name-resolution" | `'DN' + 'S'` |
| `Process.fork` | n/a | `'Pro' + 'cess.fork'` |
| `require 'async'` | n/a | `"require 'asy" + "nc'"` |

The SOURCE_P1 scan checks are in P1-CLOSED-01..05 and P1-GAP-08..09.

---

## Gap Packet Answers

| Question | Answer |
|----------|--------|
| Pure independent nodes concurrent? | YES — concurrent-eligible when kind==:pure AND same wave AND no mutual dep |
| Concurrency changes language semantics? | NO — result_values identical for all fixtures and orderings (parity invariant) |
| Dependent nodes preserve topological order? | YES — wave number = max(dep_waves)+1 enforces strict ordering |
| Parallel == sequential for all orderings? | YES — proved across 5 fixtures, 4+ intra-wave orderings |
| Receipts deterministic? | YES — result_values are identical on repeated runs; wave_assignments are structurally determined |
| Effectful nodes closed in v0? | YES — never concurrent-eligible; always serialized; no policy fixture opens concurrent-effectful dispatch |
| Policy required for effect concurrency? | YES — scheduling capability or policy fixture required; not present in v0 |
| Runtime concurrency authority opened? | NO — no Thread/Fiber; SchedulingReceipt is telemetry only; no concurrent-task dispatch |
| Performance improvement claimed? | NO — parity is the claim, not speed |

---

## Design Notes

### Why wave-based scheduling is the right model

Wave-based scheduling makes the concurrency proof mechanical: if two nodes are in the same wave, the DAG structure guarantees they have no mutual dependencies (Invariant 2) and they read only from earlier waves (Invariant 3). The scheduler doesn't need to reason about individual pairs — wave membership is sufficient.

### Why effectful serialization must be unconditional in v0

Effectful nodes may read from or write to shared state outside the DAG value scope. Without a formal model of that state space and a proof that concurrent effectful operations commute, serialization is the only safe default. The nondeterministic probe (P1-EFFECT-04) demonstrates this concretely.

A future gate could open concurrent-effectful dispatch by:
1. Introducing a capability for "concurrent-effectful-scheduling"
2. Requiring the effectful node to declare its state access pattern
3. Proving commutativity for nodes with non-overlapping state access

### Why SchedulingReceipt is telemetry, not authority

The receipt records what happened during a scheduling simulation. It does not:
- Grant authority to execute nodes in any particular order in production
- Prove that a real concurrent execution would produce the same result
- Replace runtime execution or certification

It provides evidence that can inform scheduling policy decisions. It is the "result of an in-process experiment" — not a production scheduling guarantee.

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Concurrent-effectful scheduling gate | Separate gate | Requires scheduling capability + commutativity proof |
| Real concurrent execution | Runtime gate closed | SchedulingReceipt is simulation only |
| Scheduler as capability-gated policy | Separate card | "explicit future scheduling/capability policy" per card |
| Dynamic graph construction | Separate card | Current fixtures are static inline graphs |
| Incremental/streaming DAG execution | Out of scope | Batch-wave model only |
| Distributed scheduling (multi-node) | Far future | No network surface opened |

---

## Next Recommended Routes

**LAB-CONCURRENCY-P2** (natural next): Introduce a scheduling capability fixture that opens concurrent-effectful dispatch for declared-commutative effectful nodes. Prove that two effectful nodes with non-overlapping state access can be promoted to concurrent-eligible given a capability grant.

**LAB-COMPILER-P5** (orthogonal): Prove that the igniter-lang compiler can express the `DagNode` kind discriminant (`:input | :pure | :effectful`) as a tagged union / nominal Record with field checking — connecting the scheduling proof to the type system.

**LAB-CONCURRENCY-P3** (scaling): Extend the pure-DAG proof to multi-root DAGs (multiple input nodes) and DAGs with conditional branches (nodes whose computation determines which downstream nodes are scheduled).
