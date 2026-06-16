# lab-machine-service-pool-fanout-p8-v0 — homogeneous production pool serving (replica fanout)

**Card:** `LAB-MACHINE-SERVICE-POOL-FANOUT-P8` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — implemented + proven. 8 machine tests
(`tests/service_pool_fanout_tests.rs`); full machine suite green. Builds on P5 (recipe/invoke) +
P7 (duplicate policy). **Local in-process only; no network LB, no multi-machine federation, no
worker daemon, no autoscaling, no distributed state.**

## The hypothesis, now proven

> A production capsule pool = a **homogeneous stateless replica set over an immutable service
> image**, with state/receipts in the fact log.

The replicas are **content-addressed** — N capsule refs sharing one `content_digest` are
provably identical (one stored byte image, no copy). So "selecting a replica" is for load
distribution + audit, never correctness; fanout across all replicas yields identical output by
construction. P7 already protected duplicate semantics, so scaling here cannot multiply the
repeat-handling error.

## Implementation (`coordination.rs`)

- `select_replica(strategy, n, seed)` — pure deterministic selection (NO random):
  `"round_robin"` (seed = sequence number) or hash-by-key (default; hash the duplicate key).
- `replica_count(pool)` / `replica_refs` — the replica set = refs whose digest matches the
  signed recipe (others **excluded**).
- `invoke_replica(passport, pool, inputs, replica_index)` — normal serving: authorize → pick one
  replica → activate → audit `replica:i/N`.
- `invoke_fanout(passport, pool, inputs)` — diagnostic: activate ALL replicas, return
  `Vec<(index, Ok(output) | Err(reason))>`; a `"disabled"`-labelled or failing replica is
  isolated + reported, not fatal; audit `fanout:N`.
- Shared `authorize_invoke` (passport + accepted-recipe + production + scopes + grant) reused by
  the replica/fanout paths; `activate_digest` (resume + dispatch). `invoke` (P5) unchanged.

## Selection decision (as recommended)

- **Normal serving**: deterministic — round-robin (sequence) or hash-by-duplicate-key. No random.
- **Diagnostic**: `invoke_fanout` runs all replicas and compares output.

## Proof (8 tests — 10 acceptance criteria)

| # | acceptance | test |
|---|---|---|
| 1,9 | pool_sizing=N accepts N homogeneous refs; ONE stored image (no byte copy) | `n_homogeneous_replicas_one_image` |
| 2 | a different-digest ref is excluded from the replica set | `different_digest_excluded` |
| 3 | deterministic selection (hash-by-key stable; round-robin wraps) | `deterministic_selection` |
| 3,5,6 | invoking a different replica never changes the output (homogeneous) | `invoke_replica_output_invariant` |
| 4 | fanout across all replicas → identical output | `fanout_identical_output` |
| 7 | audit records the selected replica / fanout set | `audit_records_replica_and_fanout` |
| 8 | a non-production pool cannot fanout | `non_production_cannot_fanout` |
| 10 | one disabled replica is isolated + reported; others succeed | `failure_isolation_in_fanout` |

(#5/#6 — the duplicate policy + `attempt_index` are applied by the ingress (P7) *before* replica
selection, and selection is output-invariant, so the same attempt is honored identically across
replicas; proven by `invoke_replica_output_invariant`.)

## Decisions

- **Content-addressed homogeneity**: replicas share one digest/image → identical by
  construction; one stored byte array regardless of N (no copy).
- **Exclude, don't refuse**, on a non-matching digest: a pool may hold other refs, but only the
  recipe-digest refs form the replica set.
- **Deterministic selection only** (round-robin / hash-by-key); random is out of scope.
- **Fanout isolates failures** per replica (a `"disabled"` label or a failing activation reports
  in its slot; the others still run).

## Closed (held)

Local in-process only. No network load balancer. No multi-machine federation. No worker-pool
daemon / autoscaling. No distributed state. No language/VM change (serving is the existing pure
`dispatch`). Single fact log (the dedup/audit substrate).

## Next route

- wire `invoke_replica` into the ingress hot path (P6) with a selection strategy (hash the
  duplicate key) so HTTP serving spreads across replicas — a thin integration.
- multi-machine federation (replicas across instances) — the deferred distribution axis.
- the neighbour's **service↔effect bridge** (`bridge_effect.rs`) + this fanout = a fanned-out
  service that performs declared effects with receipts; a natural convergence point.
