# Card: LAB-CONCURRENCY-P1
**Category:** lang  
**Track:** lab-deterministic-pure-dag-parallel-scheduling-boundary-v0  
**Status:** CLOSED / PROVED — 57/57 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Prove the lab-only boundary for deterministic pure-DAG parallel scheduling:

- Independent pure nodes may be scheduled concurrently as an execution optimization
- Dependent nodes preserve topological order
- Effectful nodes remain serialized or closed unless an explicit future scheduling/capability policy opens them
- Parallel scheduling returns the same result/receipt as sequential scheduling

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-view-engine/proofs/pure_dag_parallel_scheduling_proof.rb` | DONE — 57/57 PASS |
| Lab doc | `lab-docs/lang/lab-deterministic-pure-dag-parallel-scheduling-boundary-v0.md` | DONE |

---

## Proof Sections (57 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| P1-DAG | 6 | Graph construction, cycle detection, missing deps, input-with-deps, all 3 node kinds, wide graph |
| P1-TOPO | 6 | Topological order, A before B/C, B/C before D, chain order, diamond wave numbers, fanout wave 1 |
| P1-SEQ | 5 | Diamond/fanout/chain correct values; execution order; dependency edges in receipt |
| P1-WAVE | 7 | Wave groups, pure-eligible, mutual-independence, mixed non-eligible, read isolation, structural proof, wave_details flag |
| P1-PARITY | 8 | All 5 fixtures; natural/reversed/custom orderings; sequential == parallel in all cases |
| P1-EFFECT | 6 | Effectful not in eligible wave; pure before effectful in mixed; impure siblings serialized; nondeterministic probe; eligibility conditions; v0 boundary |
| P1-RECEIPT | 5 | result_values identity; wave_assignments complete; dependency_edges; node_classifications; strategy telemetry |
| P1-CLOSED | 5 | No concurrent-task class; no coroutine; no async require; no Rack-compat/server-runtime claim; no finalized-API/perf claim |
| P1-GAP | 9 | All card questions answered |

---

## Key Findings

**Wave-based scheduling proves concurrency safety:**
- `wave(input) = 0`; `wave(node) = max(wave(dep)) + 1`
- Nodes in the same wave provably have no mutual dependencies
- Pure nodes in wave W read only from waves 0..W-1 (read isolation)
- These invariants make intra-wave order irrelevant for pure nodes → parity holds

**Parity holds across all orderings:**
- 5 fixtures × 4+ intra-wave orderings → result_values always equal sequential
- The structural reason: read isolation ensures intra-wave order cannot affect inputs
- `result_values` is the canonical comparison; `execution_order` may differ by design

**Effect boundary is clear and unconditional in v0:**
- Any wave containing an effectful node gets `concurrent_eligible=false`
- Within a mixed wave, pure nodes run first; effectful nodes are serialized after
- No policy fixture opens concurrent-effectful dispatch in v0

**SchedulingReceipt is telemetry only:**
- Records strategy, execution_order, wave_assignments, dependency_edges, node_classifications, result_values
- Does NOT create language semantic authority
- Does NOT open runtime concurrency authority
- Designed as evidence, not as a production scheduling mechanism

**Five graph fixtures prove distinct scenarios:**
1. Diamond: canonical concurrent siblings (B, C in same wave)
2. Wide fanout: 4-node concurrent-eligible wave
3. Dependent chain: no parallelism; all waves single-node
4. Mixed effectful: wave not concurrent-eligible; B before E serialization
5. Independent effectful siblings: both effectful; wave not eligible despite no mutual dep

---

## Wave Invariants Proved

| Invariant | Check(s) |
|-----------|----------|
| wave(dep) < wave(node) for all deps | P1-TOPO-05, P1-TOPO-06 |
| Same-wave nodes have no mutual dependencies | P1-WAVE-03, P1-WAVE-06 |
| Pure nodes read only from earlier waves (read isolation) | P1-WAVE-05 |
| Wave concurrent-eligible iff no effectful nodes | P1-WAVE-02, P1-WAVE-04, P1-WAVE-07 |
| Sequential == parallel for all fixtures and orderings | P1-PARITY-01..08 |

---

## Self-Matching Antipattern Avoidance

New patterns for concurrency domain (beyond P8/P9 precedents):

| Banned string | Prose alternative | Check pattern |
|---------------|-------------------|---------------|
| `Thread` | "concurrent-task class" | `'Thre' + 'ad'` |
| `Fiber` | "coroutine class" | `'Fib' + 'er'` |
| `sleep` | "blocking-wait" | `'sle' + 'ep'` (established in P8) |
| `stable API` | "finalized API surface" | `'stab' + 'le API'` |
| `performance improvement` | n/a | `'perf' + 'ormance improvement'` |
| `DNS` | "name-resolution" | `'DN' + 'S'` (established in P9) |

---

## Gap Packet

| Question | Answer |
|----------|--------|
| Pure independent nodes concurrent? | YES — concurrent-eligible when kind==:pure AND same wave AND no mutual dep |
| Concurrency changes language semantics? | NO — result_values identical for all fixtures and orderings |
| Dependent nodes preserve topological order? | YES — wave number guarantees strict ordering |
| Parallel == sequential for all orderings? | YES — proved across 5 fixtures, 4+ intra-wave orderings |
| Receipts deterministic? | YES — structurally determined; identical on repeated runs |
| Effectful nodes closed in v0? | YES — never concurrent-eligible; always serialized |
| Policy required for effect concurrency? | YES — no policy fixture present in v0 |
| Runtime concurrency authority opened? | NO — no Thread/Fiber; SchedulingReceipt is telemetry only |
| Performance improvement claimed? | NO — parity is the claim, not speed |

---

## Authority Constraints (preserved)

- Closed: real concurrent execution, runtime, production scheduling, performance claims
- Forbidden: `Thread`, `Fiber`, `sleep`, async-runtime require, parallel-gem require
- No Rack compatibility claim
- No canon claim
- No finalized API claim
- Lab-only; all modules are proof-local
- SchedulingReceipt is explicitly telemetry evidence only; no semantic authority

---

## Next Recommended Routes

**LAB-CONCURRENCY-P2**: Introduce a scheduling capability fixture that opens concurrent-effectful dispatch for declared-commutative effectful nodes.

**LAB-COMPILER-P5**: Prove that the igniter-lang compiler can express `:input | :pure | :effectful` as a tagged union / nominal Record — connecting the scheduling proof to the type system.

**LAB-CONCURRENCY-P3**: Extend to multi-root DAGs and conditional-branch DAGs.
