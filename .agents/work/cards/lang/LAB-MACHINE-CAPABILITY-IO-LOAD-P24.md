# Card: LAB-MACHINE-CAPABILITY-IO-LOAD-P24 — load / correctness evidence

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> meta focus [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md) (blocker #6 — the LAST in-lab blocker).

**Status: CLOSED 2026-06-16 — evidence-only load/correctness proof.** 3 machine tests
(`tests/capability_io_load_tests.rs`); default suite green (256). Design doc:
`lab-docs/lang/lab-machine-capability-io-load-p24-v0.md`. **No code tuning** (none needed).

## Goal (met)

Evidence that exactly-one + the hardening invariants hold under real concurrency at/above 2–5k
rpm. Multi-thread tokio (4 workers) → genuine OS-thread stress on the P18 gate + sharded backend.
Correctness asserted FIRST; measurements secondary.

## Correctness under load

- same-key storm (2000 concurrent) → executor applied **exactly once**; all observe committed;
  one committed receipt for the key.
- distinct keys (3000) → all committed, applied 3000×, P23 snapshot = 3000 committed, NO duplicates.
- all-timeout (800) → all unknown, **0 committed**.

## Measurements (one run, illustrative)

storm ≈39k/s p50≈24ms (serialized — correct, the cost of exactly-one falls only on same-key
contention); distinct ≈51k/s p50=54µs/p99=422µs (microseconds — distinct keys don't contend).
Throughput ~500× the 2–5k rpm target. No silent double-commit/lost-update/duplicate at scale.

## Closed

Local only, no external network. Evidence-only (no optimization). Numbers illustrative, not an SLA.

## All in-lab hardening CLOSED (#1–#6)

P18 atomic gate / P19 durable recovery / P20 orchestrator / P21+P22 security / P23 observability /
P24 load — all closed. The only remaining step is **#7 human-gated live** (real endpoint + vaulted
credential + human approval), a separate operational/security gate, NOT a wave continuation.
