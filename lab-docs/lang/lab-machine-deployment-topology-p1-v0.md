# lab-machine-deployment-topology-p1-v0 — production-shaped (non-live) deployment topology

**Card:** `LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1`
**Status:** READINESS / DESIGN — how igniter-machine lives as a process. After the hardening
capstone (P25). **No code, no live, no deploy, no staging** — this is the operational shape on
paper, grounded in the existing surface.

Grounded in live modules: `machine::IgniterMachine`, `backend::RocksDBBackend`,
`single_flight::{SingleFlight, run_write_effect_atomic}`, `recovery::recover_dangling_writes`,
`orchestrator::EffectOrchestrator{boot,tick,report}`, `ingress::{IngressRouter, serve_once}`,
`coordination::{CoordinationHub, ServiceRecipe, pools}`, `bridge_effect::ServiceEffectBridge`,
`clock::SystemClock`, `secrets::{Env,File,Layered}SecretProvider`, `capability::PassportVerifier`,
`observability::observe`.

## 1. Process model — ONE process, N worker threads, ONE RocksDB

The exactly-one-effect invariant (P18) is enforced by an **in-process** per-key `SingleFlight`
lock. Therefore the unit of deployment is:

```
ONE effect-process  ─owns→  ONE SingleFlight  +  ONE RocksDB data dir  +  the listening socket
                    ─runs→  a multi-thread tokio runtime (N worker threads)
```

- **Scale UP (vertical):** N tokio worker threads inside the one process. Distinct idempotency
  keys run in parallel across workers (P24 showed microsecond latency); same-key duplicates
  serialize on the per-key lock. This is the supported scaling axis for EFFECTS.
- **Capsule ACTIVATION can fan out** across the coordination homogeneous pool replicas (pure
  dispatch, content-addressed image). But the GUARDRAIL from the coordination track holds: a
  served effect funnels through ONE replica → ONE `run_write_effect_atomic`. Activation scales;
  effects do not multiply.
- **Multi-PROCESS is NOT supported by P18** — two processes each have their own `SingleFlight`
  and could double-execute the same key. A horizontal multi-process effect tier needs a
  distributed lock or a backend compare-and-set on the `prepared` write (an explicit later slice,
  noted in P18). Until then: **one effect-process per RocksDB; partition by capability/tenant if
  more processes are needed (each its own RocksDB + key space).**

Ports: one inbound listener (ingress, currently loopback HTTP/1.1). Outbound effect transports
(HTTP/TLS) dial out from the same process via the host allowlist (P14).

## 2. Storage layout — fact-store namespaces in ONE RocksDB

All durable state is bitemporal facts in the single RocksDB, partitioned by store namespace
(each persisted as `data_dir/<store>/<key>.mpk`):

| store | owner | holds |
|---|---|---|
| `__receipts__` | capability/write | effect + two-phase write receipts (source of truth for idempotency/replay) |
| `__retry_queue__` | retry_queue | durable retry intents (`due_at`, state) |
| `__dead_letter__` | orchestrator | stuck items (exhausted/blocked/unresolved) |
| `__orchestrator_audit__` | orchestrator | boot/tick audit |
| `__ingress_dedup__` | coordination | ingress duplicate-policy state |
| `__recipes__` / `__coord_audit__` / `__transfers__` / `__messenger__` | coordination | serving line (pools, ServiceRecipes, ownership, audit) |
| domain stores (e.g. `orders`) | the write executor's substrate | the actual mutated data |

The receipt store is the spine: idempotency, reconciliation, recovery, and observability all read
it. Keep it on the durable backend (never in-memory) in production. Capsule images are
content-addressed (one stored image, N pool refs — no copy).

## 3. Boot / recovery / tick order (host-driven, explicit)

```text
1. open RocksDB(data_dir)                         # durable facts reload (.mpk)
2. construct host context:
     SystemClock, PassportVerifier(trusted keys), SecretProvider(env/file),
     CapabilityExecutorRegistry(real executors), SingleFlight, CoordinationHub
3. EffectOrchestrator.boot()                       # P19 recovery sweep: reconcile dangling
       │                                           #   `prepared` receipts (read-back/correlation),
       │                                           #   never re-execute; dead-letter the unresolved
       └─ idempotent: safe to run on every boot
4. ingress: bind the listener; begin the serve loop  (serve_once per connection)
5. tick cadence: the host calls EffectOrchestrator.tick() on an interval
       │   (drains DUE retry intents under the SAME reconcile-gating; dead-letters exhausted/blocked)
       └─ NO background daemon / hidden timer — the host owns the cadence
6. report()/observe() available at any time for an operator snapshot
```

Crash-safe by construction: boot's recovery sweep resolves any effect interrupted mid-flight
before serving resumes; `tick()` is the only thing that re-issues, and it is reconcile-gated.

## 4. Ingress serving topology

```text
inbound socket
  → ingress::serve_once (one connection)         # loopback HTTP/1.1 today
  → IngressRouter.handle: passport verify → route(path→pool) → ServiceRecipe
  → duplicate policy (business strategy on the recipe)
  → CoordinationHub.invoke = capsule activation (resume + dispatch, PURE)  ── may pick ONE replica
  → ServiceEffectBridge: capsule output = intent → run_write_effect_atomic = ONE effect + receipt
  → HTTP response (200 committed / 202 unknown / 403 / 502 / 503) + audit fact
```

The serve loop is host-driven (one connection per `serve_once`; the host loops). A real multi-
connection accept loop is a thin wrapper — still one process. Ingress validates authority BEFORE
activation; the effect is single-flight-gated; replay never re-sends.

## 5. Capsule pool topology

- A **production pool** is a stateless replica set over ONE immutable content-addressed capsule
  image (a signed `ServiceRecipe` pins the `capsule_digest`).
- Activation (resume + dispatch) is pure and replica-parallel; deployment can size the pool for
  activation throughput.
- The **effect** an activation declares is performed ONCE by the host effect tier (one
  `SingleFlight`), regardless of pool size — pool scaling never multiplies downstream effects.
- Dev→prod handoff is the existing flow: agent builds capsule → developer signs the
  `ServiceRecipe` → pool becomes Production → vendor passport invokes. Updating the service =
  sign a new recipe pinning a new digest (immutable image swap).

## 6. Backup / restore

- **Backup**: the durable RocksDB `data_dir` IS the state (all fact stores). Snapshot the dir
  (filesystem-consistent copy / volume snapshot). Additionally, `machine.checkpoint(.igm)`
  produces a deterministic, byte-identical capsule image (contracts + facts + observations) for a
  portable point-in-time snapshot.
- **Restore**: reopen RocksDB on the restored dir (facts reload), then `boot()` — the recovery
  sweep reconciles any dangling `prepared` against the restored substrate before serving. A `.igm`
  restores via `IgniterMachine::resume`.
- **Caveat**: a restore to a point BEFORE some external effects landed leaves dangling `prepared`
  receipts whose targets already exist externally → boot's reconcile resolves them to `committed`
  (read-back) — exactly the write-succeeded-but-receipt-failed handling, now at restore time.

## 7. Clock / secrets / passport placement

- **Clock**: `SystemClock` injected at the host boundary ONLY (P4). The single real-time source;
  contracts never read it. Operational note: receipt `transaction_time` is wall-clock — keep the
  host clock monotonic-ish (NTP); a large backward jump doesn't corrupt idempotency (keyed by
  identity, not time) but muddies audit windows.
- **Secrets**: a host `SecretProvider` (env allowlist / traversal-safe file / layered) — P22.
  Secrets are references (`{{secret:name}}`) in requests, resolved at the boundary, redacted from
  every fact. Provisioned by the operator (env vars / a mounted secret dir); a real vault plugs in
  as another layer.
- **Passport**: a `PassportVerifier` holds the trusted issuer keys; effects require a signed
  passport (P21). Issuer keys are operator-provisioned host config, never in a contract or a fact.

## 8. Operator commands (conceptual surface — no CLI built)

A host wrapper would expose these over the existing API (each is one method call, no daemon):

- `boot` — open RocksDB + run the recovery sweep (idempotent).
- `serve` — start the ingress accept loop.
- `tick` — drain due retries once (run on a cron/interval by the operator).
- `report` / `observe` — emit the `ObservabilitySnapshot` JSON (effects by state, retries,
  dead-letters by reason, unknowns) for a dashboard / health check.
- `deadletters` — list the dead-letter inbox grouped by reason/key/correlation for triage.
- `checkpoint <path.igm>` — portable point-in-time snapshot.
- `recipe sign / pool promote` — deploy a new capsule image (serving line).

## 9. Risks (carried, with mitigations)

| risk | status / mitigation |
|---|---|
| in-process single-flight ⇒ single effect-process per RocksDB | DESIGN CONSTRAINT — partition by tenant; multi-process needs distributed lock / backend CAS (later) |
| lock map grows unbounded (one entry/key seen) | mitigate: evict idle locks (sharded/weak map) before high-cardinality production |
| write-succeeded-but-receipt-failed | CLOSED by boot recovery (P19) — resolved on boot/restore, never blind-retried |
| RocksDB durability = our pure-Rust file log (`.mpk`), not the rocksdb crate | validate fsync/consistency semantics + backup cadence before real data |
| clock skew / backward jump | identity-keyed idempotency is unaffected; audit windows muddied — keep NTP |
| pre-executor refusals write no receipt | observability gap (P23 finding) — emit host audit events for bad-passport / missing-secret if those must be counted |
| single process = single point of failure | acceptable at this stage; HA is a multi-process story gated on the distributed-lock slice |
| secrets / issuer keys provisioning | operator responsibility — outside the glass box; part of the live-gate packet |

## Closed

No live network, no real deployment, no staging, no code. Design only. The single hard constraint
to carry forward: **exactly-one is in-process — one effect-process per RocksDB until a distributed
gate exists.**

## Next

- a live-gate packet (gathers this + the P25 deltas for a human decision — NOT agent-executed).
  **PREPARED: `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1` → `lab-docs/lang/lab-machine-sparkcrm-live-gate-p1-v0.md`.**
- if/when horizontal scale is needed: a distributed-lock / backend-CAS slice for the prepare gate
  (the one thing that unblocks multi-process effects);
- otherwise the substrate is done enough — switch track.
