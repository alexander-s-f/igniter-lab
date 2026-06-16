# lab-machine-capability-io-load-p24-v0 — load / correctness evidence

**Card:** `LAB-MACHINE-CAPABILITY-IO-LOAD-P24` (production-hardening blocker #6, meta
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`)
**Status:** CLOSED — evidence-only load/correctness proof. 3 machine tests
(`tests/capability_io_load_tests.rs`); default suite green (256).
**Boundary held:** local, no external network; **no code tuning** (none needed — no correctness
bug surfaced).

## Purpose

Not a benchmark/optimization. Evidence that the hardening invariants — above all **exactly-one
effect** — hold under real concurrency at (and far beyond) the 2–5k rpm target. Real OS-thread
parallelism via a multi-thread tokio runtime (4 workers) → genuine stress on the P18 atomic gate
and the sharded backend. Correctness is asserted FIRST; measurements are secondary.

## Correctness under load (asserted)

| scenario | n (concurrent) | result |
|---|---|---|
| same idempotency key storm | 2000 | **executor applied EXACTLY ONCE**; all 2000 observe `committed` (one executed, the rest replay); exactly one `committed` receipt fact for the key |
| distinct keys | 3000 | all `committed`; executor applied 3000×; the P23 snapshot reports exactly 3000 `committed` — **no duplicates** |
| all-timeout (unknown) | 800 | every outcome `unknown_external_state`; **0 committed** (nothing silently commits); P23 snapshot reports 800 unknown |

The central production invariant — *exactly-one effect under a concurrent same-key storm* — holds
at 2000-way concurrency, not just the 2-key P18 unit proof.

## Measurements (one run, dev machine — illustrative, not an SLA)

```
[load:same_key_storm] n=2000  throughput≈39k/s  p50≈24ms  p95≈37ms  p99≈38ms
[load:distinct_keys]  n=3000  throughput≈51k/s  p50≈54us  p95≈97us  p99≈422us
[load:mixed]          n=800   all unknown, 0 committed
```

Findings:
- **Throughput** (~40–50k effects/s) is ~500× the 2–5k **rpm** target (~83 rps). Capacity is not
  the constraint at this scale.
- **Distinct-key latency** is microseconds (p50 54µs, p99 422µs) — distinct keys do not contend;
  the per-key lock is genuinely per-key.
- **Same-key-storm latency** is tens of ms (p50 ≈ 24ms) — and that is CORRECT, not a regression.
  A same-key storm is serialized by the single-flight gate (that IS exactly-one); the median
  request waits behind roughly half the queue. The cost of exactly-one falls ONLY on duplicate
  contention for one key — precisely the retry-storm case where serialization is wanted. Distinct
  traffic is unaffected.

## Interpretation

- The atomic gate (P18) does what it must under heavy concurrency and nothing it shouldn't: it
  serializes same-key duplicates and lets distinct keys run free.
- No silent double-commit, no lost-update, no duplicate receipt at scale.
- Observability (P23) reports the load truthfully (committed / unknown counts match the driver).
- No code change was required — the proof is evidence, per the card's "no tuning unless a
  correctness bug appears."

## Closed

Local only, no external network. Evidence-only (no optimization). Numbers are illustrative of a
single run, not a guaranteed throughput SLA.

## All in-lab hardening CLOSED

```
#1 atomic gate (P18)     ✅   #4 security (P21+P22)   ✅
#2 durable recovery (P19)✅   #5 observability (P23)  ✅
#3 orchestrator (P20)    ✅   #6 load (P24)           ✅
```

The only remaining step is **#7 human-gated live** — a separate operational/security gate (real
endpoint + vaulted credential + human approval), NOT a continuation of this engineering wave.

```
In-lab production hardening: CLOSED.
Live: human-gated only.
```
