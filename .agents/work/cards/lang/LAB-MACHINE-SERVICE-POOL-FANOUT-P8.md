# Card: LAB-MACHINE-SERVICE-POOL-FANOUT-P8 — homogeneous production pool serving

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. P8 proves the server-architecture hypothesis: a production pool = a homogeneous stateless replica set over an immutable content-addressed service image.

**Status: CLOSED 2026-06-16 — implemented + proven.** 8 machine tests
(`igniter-machine/tests/service_pool_fanout_tests.rs`); full suite green. Code added to
`igniter-machine/src/coordination.rs`. Design doc:
`lab-docs/lang/lab-machine-service-pool-fanout-p8-v0.md`.

## Goal (met)

Prove homogeneous production-pool serving across N identical capsule refs: `pool_sizing`,
deterministic single-replica selection, `invoke_fanout` (activate all → identical output),
duplicate policy + audit preserved. Local in-process only; no LB / federation / daemon /
autoscaling / distributed state.

## Implementation (`coordination.rs`)

`select_replica(strategy, n, seed)` (pure; round_robin | hash-by-key, no random) ·
`replica_count`/`replica_refs` (replica set = refs matching the recipe digest; others excluded)
· `invoke_replica` (serving: pick one, activate, audit `replica:i/N`) · `invoke_fanout`
(diagnostic: all replicas → `Vec<(i, Ok|Err)>`, `"disabled"`/failing replica isolated+reported,
audit `fanout:N`). Shared `authorize_invoke` + `activate_digest`; `invoke` (P5) unchanged.

## Proof (8 tests = 10 acceptance)

`n_homogeneous_replicas_one_image` (1,9), `different_digest_excluded` (2),
`deterministic_selection` (3), `invoke_replica_output_invariant` (3,5,6),
`fanout_identical_output` (4), `audit_records_replica_and_fanout` (7),
`non_production_cannot_fanout` (8), `failure_isolation_in_fanout` (10).

## Decisions

- content-addressed homogeneity (one stored image regardless of N; replicas identical by
  construction);
- exclude (not refuse) a non-matching digest;
- deterministic selection only (round-robin / hash-by-key); no random;
- fanout isolates per-replica failures.

## Closed

Local in-process only. No network LB / multi-machine federation / worker daemon / autoscaling /
distributed state. No language/VM change. Single fact log.

## Next

- wire `invoke_replica` into the ingress hot path (hash duplicate key → replica) — thin
  integration;
- multi-machine federation (replicas across instances);
- fanout × the neighbour's `bridge_effect.rs` (service↔effect) = fanned-out effectful service.
