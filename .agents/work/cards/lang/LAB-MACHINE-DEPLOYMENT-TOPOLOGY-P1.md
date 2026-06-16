# Card: LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1 — production-shaped (non-live) topology

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> hardening capstone [`…-HARDENING-CAPSTONE-P25`](LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25.md).

**Status: CLOSED 2026-06-16 — readiness/design.** How igniter-machine lives as a process, after
the hardening capstone. **No code, no live, no deploy, no staging.** Doc:
`lab-docs/lang/lab-machine-deployment-topology-p1-v0.md`.

## What it answers

process model · storage layout · boot/recovery/tick order · ingress serving · capsule pool
topology · backup/restore · clock/secrets/passport placement · operator commands · risks.

## The load-bearing conclusions

- **ONE effect-process / N tokio workers / ONE RocksDB / one listener.** Exactly-one (P18) is an
  IN-PROCESS lock → one effect-process per RocksDB; scale vertically (workers) for distinct keys;
  capsule activation may fan out across pool replicas, but a served EFFECT funnels through ONE
  `run_write_effect_atomic`. Multi-process effects need a distributed lock / backend CAS (later).
- **Storage** = bitemporal facts in one RocksDB, partitioned by store namespace (`__receipts__`,
  `__retry_queue__`, `__dead_letter__`, `__orchestrator_audit__`, `__ingress_dedup__`, coordination
  stores, domain stores). Receipt store is the spine.
- **Boot order**: open RocksDB → build host context (clock/verifier/secrets/registry/single-flight/
  hub) → `orchestrator.boot()` (idempotent recovery sweep) → ingress serve loop → host-driven
  `tick()` cadence → `report()`/`observe()` anytime. No daemon.
- **Backup** = the RocksDB dir (+ optional `.igm` checkpoint); **restore** = reopen + `boot()`
  (recovery reconciles dangling prepared at restore time).
- **Clock/secrets/passport** = host-boundary injected (SystemClock; Env/File SecretProvider;
  PassportVerifier trusted keys); never in a contract or a fact.
- **Operator commands** (conceptual): boot / serve / tick / report / observe / deadletters /
  checkpoint / recipe-sign+pool-promote.

## Risks carried

in-process single-flight ⇒ one effect-process per RocksDB (design constraint); unbounded lock map
(evict idle); RocksDB durability semantics to validate; clock skew (audit-only); pre-executor
refusals unobserved (P23 finding); single process = SPOF (HA gated on distributed lock).

> **Durability validated → `LAB-MACHINE-ROCKSDB-DURABILITY-P2`** (`lab-docs/lang/lab-machine-rocksdb-durability-p2-v0.md`),
> **then hardened → `LAB-MACHINE-FACTSTORE-DURABILITY-HARDENING-P3`** (`lab-docs/lang/lab-machine-factstore-durability-hardening-p3-v0.md`).
> "RocksDB" here is a **pure-Rust `.mpk` file store** (no `rocksdb` crate), now renamed
> **`MpkFileBackend`**. P3 made writes **atomic** (temp→fsync→rename), made corruption
> **observable+refused** (no more silent loss), and put the **receipt spine on the hardened path**.
> Graceful-restart + crash/torn-write durability now proven; **full power-loss durability stays
> platform-gated** (macOS `F_FULLFSYNC`, cloud-volume fsync honoring) under the P25 human-gate. Backup
> = **quiesced** dir copy (live copy is still a point-in-time snapshot) or `.igm` checkpoint.

## Closed

No live / deploy / staging / code. Design only. Hard constraint: exactly-one is in-process — one
effect-process per RocksDB until a distributed gate exists.

## Next

live-gate packet (human) · distributed-lock/backend-CAS slice IF horizontal effect scale is
needed · otherwise switch track (substrate done enough).
