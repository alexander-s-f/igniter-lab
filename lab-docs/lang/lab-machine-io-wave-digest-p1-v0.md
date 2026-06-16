# igniter-machine IO wave — front-door digest (v0)

**Card:** `LAB-MACHINE-IO-WAVE-DIGEST-P1` · **Lane:** governance / anti-drift / digest
**Role:** navigation front door for the whole capability-IO + service-runtime wave.
This document is **navigation only — it creates no authority and proposes no feature.**

> **Authority & verify-first.** Source of truth = **live code** + the crate's
> [`IMPLEMENTED_SURFACE.md`](../../igniter-machine/IMPLEMENTED_SURFACE.md) + the wave-stop
> checkpoint `…-HARDENING-CAPSTONE-P25`. Cards and `lab-docs/*` proofs (including this digest)
> are **evidence, not authority**. If any doc says a slice is "missing / not implemented / only a
> PROP-042 sketch", it is **stale** — `cargo test --no-default-features` and `grep src/**` win.
> Full rule: [`SEARCH.md`](../../SEARCH.md).

---

## 1. Executive summary (one screen)

`igniter-machine` is a working, tested **production data-plane substrate**: a fused
compiler+VM+fact-store kernel with a capability-IO boundary that performs real read/write
effects behind receipts, plus a coordination/service runtime that activates capsules and a
front door that drives the full **wire → effect** contour over a real socket.

The wave moved from *"how do we do IO?"* to a substrate that holds **exactly-one-effect** under
concurrency, crashes, retries, and load — observably — and stops, deliberately, **before any live
external network call.**

```
Correctness model (P1–P15):        DONE — receipts, idempotency, authority, reconcile, retry,
                                   HTTP/TLS, SparkCRM domain executor.
Service / coordination (P2–P11):   DONE — pools/ACL, recipes, agentless serving, HTTP ingress,
                                   replica fanout, service↔effect bridge, wire-to-effect contour.
In-lab production hardening (P18–P24): DONE — atomic gate, durable recovery, orchestrator,
                                   signed passport, secret providers, observability, load.
Live external runtime:             NOT DONE, NOT AUTHORIZED — human-gated only.
```

**Test ground truth (verified 2026-06-16):**
- `cargo test --no-default-features` → **256 passing**
- `cargo test --no-default-features --features tls` → **271 passing** (adds real-TLS + SparkCRM)
- ⚠ Plain `cargo test` (default features incl. `ffi`) currently **fails to compile** on a stale
  async `.await` in `src/ffi.rs` — **unrelated to the IO wave**; the canonical command is
  `--no-default-features`. Flagged separately; not part of this digest's scope.

---

## 2. Timeline map (5 bands)

| Band | Phases | One-line |
|---|---|---|
| **A · Capability-IO substrate** | P1–P9, P12, P13 | receipt-as-fact boundary → real read → clock → passport → receipt-gated write → reconcile → bounded retry → durable retry queue; compensation (`aborted`); correlation reconcile |
| **B · HTTP / TLS / SparkCRM executor** | P10, P11, P14, P14-impl, P15 | HTTP policy taxonomy → real loopback → external-host profile → **real rustls TLS** → **SparkCRM domain executor** (one struct = forward + lookup + compensate) |
| **C · Coordination / service runtime** | P2–P9 (coord) | pools + ACL + content-addressed refs → messenger → transfer envelopes → **ServiceRecipe + agentless serving** → HTTP ingress front door → duplicate policy → homogeneous replica fanout → replica-in-ingress |
| **D · Bridge / wire contour** | P16, P10(bridge), P11(wire) | service↔effect bridge (two authorities) → bridge×replica glass box → **wire-to-effect milestone** (real `127.0.0.1` POST drives the full contour to one effect + receipt) |
| **E · Hardening** | P18–P25 | atomic idempotency gate → durable crash recovery → host orchestrator → signed passport → secret providers → observability → load/correctness → **capstone stop** |

> Note on numbering: two parallel P-series share the wave — the **capability-IO** series
> (P1…P24) and the **coordination/service** series (P2…P11). They are distinct lanes that the
> bridge (P16) and wire contour (P11-wire) join. Don't read them as one linear sequence.

---

## 3. What is PROVEN (code + test + doc pointers)

All paths relative to `igniter-lab/`. Modules are in `igniter-machine/src/`, tests in
`igniter-machine/tests/`, phase docs in `lab-docs/lang/`.

| Capability | Module | Test | Phase doc |
|---|---|---|---|
| Capability-IO boundary (receipt-as-fact, idempotency, replay) | `capability.rs` | `capability_io_tests.rs` (13) | `lab-machine-capability-io-p1-v0.md` |
| Declared-effect host entrypoint | `service_loop.rs` | `capability_io_host_tests.rs` (9) | `lab-machine-capability-io-p2-host-entrypoint-v0.md` |
| First real substrate (read-only RocksDB / remote-TCP) | `executors.rs` | `capability_io_real_tests.rs` (5) | `lab-machine-capability-io-p3-real-substrate-v0.md` |
| Host clock | `clock.rs` | `capability_io_clock_tests.rs` (5) | `lab-machine-capability-io-clock-p4-v0.md` |
| Typed capability passport | `capability.rs` | `capability_io_authority_tests.rs` (9) | `lab-machine-capability-io-authority-p5-v0.md` |
| Receipt-gated write (+ real local write) | `write.rs` | `capability_io_write_tests.rs` (9) / `…_write_real_tests.rs` (8) | `…-write-p6a-v0.md` / `…-write-p6b-v0.md` |
| Unknown-write reconciliation | `reconcile.rs` | `capability_io_reconcile_tests.rs` (6) | `…-reconciliation-p7-v0.md` |
| Bounded reconcile-gated retry | `retry.rs` | `capability_io_retry_tests.rs` (7) | `…-retry-p8-v0.md` |
| Durable retry queue | `retry_queue.rs` | `capability_io_retry_queue_tests.rs` (8) | `…-retry-queue-p9-v0.md` |
| HTTP executor (policy + real loopback) | `http.rs` | `capability_io_http_tests.rs` (12) / `…_http_loopback_tests.rs` (9) | `lab-machine-capability-http-p10-v0.md` / `…-p11-v0.md` |
| Correlation reconciliation | `correlation.rs` | `capability_io_correlation_tests.rs` (8) | `…-correlation-reconcile-p13-v0.md` |
| External HTTP profile + **real TLS** | `http.rs` | `capability_io_http_external_tests.rs` (10) / `…_http_tls_tests.rs` (7, `tls`) | `…-http-external-p14-v0.md` / `…-http-tls-p14-impl-v0.md` |
| **SparkCRM domain executor** (capstone) | `sparkcrm.rs` | `capability_io_sparkcrm_tests.rs` (8, `tls`) | `lab-machine-capability-sparkcrm-executor-p15-v0.md` |
| Effect compensation (`aborted`) | `compensation.rs` | `capability_io_compensation_tests.rs` (7) | `…-compensation-p12-v0.md` |
| Agent/pool coordination | `coordination.rs` | `coordination_pools_tests.rs` (9) | *(card)* `LAB-MACHINE-AGENT-POOLS-P2` |
| Messenger bus | `coordination.rs` | `coordination_messenger_tests.rs` (9) | *(card)* `LAB-MACHINE-AGENT-MESSENGER-P3` |
| Transfer envelopes | `coordination.rs` | `coordination_transfer_tests.rs` (9) | *(card)* `LAB-MACHINE-AGENT-TRANSFER-P4` |
| ServiceRecipe + agentless serving | `coordination.rs` | `coordination_recipe_tests.rs` (7) | *(card)* `LAB-MACHINE-SERVICE-RECIPE-P5` |
| HTTP ingress front door | `ingress.rs` | `service_http_ingress_tests.rs` (9) | *(card)* `LAB-MACHINE-SERVICE-HTTP-INGRESS-P6` |
| Ingress duplicate policy | `coordination.rs` + `ingress.rs` | `service_ingress_duplicate_policy_tests.rs` (8) | *(card)* `LAB-MACHINE-SERVICE-INGRESS-DUPLICATE-POLICY-P7` |
| Homogeneous pool fanout | `coordination.rs` | `service_pool_fanout_tests.rs` (8) | *(card)* `LAB-MACHINE-SERVICE-POOL-FANOUT-P8` |
| Replica selection in ingress | `ingress.rs` | `service_ingress_replica_tests.rs` (7) | *(card)* `LAB-MACHINE-SERVICE-INGRESS-REPLICA-P9` |
| Service↔effect bridge | `bridge_effect.rs` | `capability_io_bridge_tests.rs` (6) | *(card)* `LAB-MACHINE-SERVICE-EFFECT-BRIDGE-P16` |
| Bridge × replica (glass box) | `ingress.rs` | `service_bridge_replica_tests.rs` (6) | *(card)* `LAB-MACHINE-SERVICE-BRIDGE-REPLICA-P10` |
| **Wire-to-effect** (real socket MILESTONE) | `ingress.rs` (`serve_once_effect`) | `service_wire_effect_tests.rs` (5) | *(card)* `LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE` |
| Atomic idempotency gate (concurrency) | `single_flight.rs` | `capability_io_atomic_tests.rs` (4) | `…-atomic-gate-p18-v0.md` |
| Durable recovery (crash) | `recovery.rs` | `capability_io_recovery_tests.rs` (7) | `…-durable-recovery-p19-v0.md` |
| Effect orchestrator (host loop) | `orchestrator.rs` | `capability_io_orchestrator_tests.rs` (6) | `…-orchestrator-p20-v0.md` |
| Signed passport (security) | `capability.rs` | `capability_io_signed_passport_tests.rs` (5) | `…-signed-passport-p21-v0.md` |
| Secret providers (security) | `secrets.rs` | `capability_io_secrets_tests.rs` (5) | `…-secret-provider-p22-v0.md` |
| Observability (projection) | `observability.rs` | `capability_io_observability_tests.rs` (6) | `…-observability-p23-v0.md` |
| Load / correctness (multi-thread) | `tests/…` | `capability_io_load_tests.rs` (3) | `…-load-p24-v0.md` |

Front-door cards: substrate = `LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`; hardening order =
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`; wave stop =
`LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25`. (All under
`.agents/work/cards/lang/`.)

---

## 4. What is explicitly NOT proven (the live gate)

In-lab "done" is **not** live readiness. None of the following exist or have been reviewed; an
agent must **not** treat any of them as "the next step":

| NOT proven | Status today |
|---|---|
| **Live SparkCRM (or any third-party) endpoint** | only a **local fake** HTTPS upstream touched — no real host, no internet |
| **Real vaulted credential** | `SecretProvider` is **env / file** in the glass box; the vault adapter point exists but is **not** wired to any real vault |
| **Deployment topology (operational, live)** | **design done** in-lab (`LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1`: process/storage/boot/backup/clock) — but **no deployed/failover/backup-tested live shape** |
| **Public-ingress threat review** | no auth-surface / rate-&-cost-abuse / DoS / input-validation-at-scale review |
| **Operational runbook** | no on-call, dead-letter triage, or rollback runbook |
| **Human approval** | none. `P16-live` / any live smoke is a **separate operational + security decision**, **not** a continuation of this engineering wave |

Hard constraint surfaced by the topology design: **exactly-one-effect is in-process** →
**one effect-process per RocksDB** (multi-process horizontal effect scale needs a distributed
lock / backend-CAS slice that does not yet exist).

---

## 5. Current next routes (the wave is intentionally stopped)

- **Live-gate packet** — one document gathering the §4 deltas for a *human* gate decision
  (authored for review; **not executed** by an agent).
- **Deployment-topology readiness** — extend `LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1` (still in-lab/design).
- **Operator console** — UI over the read-only `observability.rs` projection (`to_json` export).
  Design done: [`lab-machine-operator-console-p1-v0.md`](lab-machine-operator-console-p1-v0.md)
  (`LAB-MACHINE-OPERATOR-CONSOLE-P1`) — views/actions/CLI surface, design-only.
- **SparkCRM auction policy** — exercise the `treat_as_fresh` / `bounded_fresh` duplicate policy
  as a business lever (same input → distinct generated codes, audited). Design done:
  [`lab-sparkcrm-webhook-auction-policy-p1-v0.md`](lab-sparkcrm-webhook-auction-policy-p1-v0.md)
  (`LAB-SPARKCRM-WEBHOOK-AUCTION-POLICY-P1`) — 3 profiles + measurement plan, policy-only.
- **Switch track** — the substrate is done enough; frame/GUI, coordination federation, or the
  canon language may be the higher-value move.

These are routes, not commitments. Pick by value, not by sequence number.

---

## 6. Agent search protocol

1. **Check `igniter-machine/IMPLEMENTED_SURFACE.md` first** — it is the live, code-anchored index.
2. **Use this digest as the front door** for the IO/service wave — it routes to the per-phase
   cards and docs; it does not replace them.
3. **Old cards are evidence, not a backlog.** A closed P-card describes what was proven, not work
   to redo. Read the milestone front door + the P25 capstone **before** pulling any single P-slice
   out of context.
4. Canonical verify commands: `cargo test --no-default-features` (256) and
   `--no-default-features --features tls` (271). Grep `igniter-machine/src/**` to confirm a module.

---

## 7. Superseded / noise note

- Do **not** chase any "igniter-machine IO is missing / unimplemented / only PROP-042" claim
  without verify-first. Those are **stale** — every band in §2 has a module + a green test.
- Do **not** conflate this wave with the separate **`LAB-IGNITER-LANG-IO-RUNTIME-*`** track
  (language-level storage executor in the compiler/VM lineage). Different crate, different lineage.
- This digest adds **no** new feature, primitive, or authority. Hardening was composition of the
  existing substrate; no new effect primitives were introduced anywhere in the wave.

---

*Front door, not authority. Stale docs cannot override live code + `IMPLEMENTED_SURFACE.md`.*
*Compiled 2026-06-16 against verified test counts. Update via `LAB-MACHINE-IO-WAVE-DIGEST-P1`.*
