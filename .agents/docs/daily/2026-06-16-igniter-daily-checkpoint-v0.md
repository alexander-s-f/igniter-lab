# Igniter Daily Checkpoint — 2026-06-16

## Daily Summary

2026-06-16 was a consolidation and hardening day. The main arc was:

```text
machine IO model -> production-shaped in-lab hardening -> human-gated live stop
serving/coordination -> wire-to-effect proof -> deployment/readiness docs
frame/ui -> projection runtime -> UI-kit/workbench -> DX authoring model
language -> effect/capability parity + dynamic dispatch policy
```

The day ended in a good state: the machine IO wave is not merely feature-complete
in-lab, it is explicitly stopped before live; frame/ui now has a clear authoring
question and first answer; language pressure cards are routed without reopening
closed VM/runtime work.

## Checkpoints Closed

### Machine IO / Production Hardening

- Capability IO correctness and hardening were consolidated into two capstones:
  - P15 correctness capstone: domain executor composition over receipts,
    idempotency, authority, clock, reconciliation, retry, compensation, HTTP/TLS.
  - P25 hardening capstone: in-lab production hardening closed; live remains
    human-gated only.
- The hardening line closed the critical in-lab blockers:
  - P18 atomic idempotency gate: same-key concurrent requests serialize, distinct
    keys remain parallel.
  - P19 durable recovery: dangling `prepared`/`unknown` receipts are reconciled,
    not retried blindly.
  - P20 host-driven orchestrator: explicit `boot`/`tick`/`report`, no daemon.
  - P21/P22 security: signed passports + env/file/layered secret providers.
  - P23 observability: metrics/dead-letter inbox as projection from facts.
  - P24 load/correctness: same-key storm and distinct-key pressure held in lab.
- P25 intentionally stopped the wave:

```text
Correctness model: DONE
In-lab production hardening: DONE
Live external runtime: NOT DONE / human-gated only
```

### Serving / Coordination / Production Shape

- Coordination/serving line closed from agent pools through wire-to-effect:
  - pools/ACL/audit, messenger, capsule transfer, ServiceRecipe, HTTP ingress,
    duplicate policy, homogeneous pool fanout, replica selection, bridge effect,
    and loopback HTTP wire-to-effect proof.
- Deployment topology P1 clarified the actual production-shaped process:
  - one effect process;
  - N tokio workers;
  - one durable fact store;
  - one listener;
  - `orchestrator.boot()` before serving;
  - host-driven `tick()`;
  - facts are source of truth for report/observe.
- Important topology constraint surfaced:

```text
exactly-one effect is currently in-process single-flight.
Therefore v0 production topology is one effect process per fact store / key-space.
Multi-process effects require distributed lock or backend CAS, not just more replicas.
```

### Storage Durability

- RocksDB durability assumption audit found a naming/semantics gap: the previous
  so-called RocksDB backend was an `.mpk` file backend shape, and durability
  assumptions needed to be made explicit.
- Factstore durability hardening fixed the local file backend surface:
  - atomic temp-write + rename;
  - best-effort file/parent sync;
  - corruption visible as `EngineError::Corruption`;
  - no silent `unwrap_or_default` reads.
- Remaining non-claim: no full power-loss guarantee or distributed storage claim.

### SparkCRM / Live Gate / Operator Readiness

- SparkCRM live-gate packet P1 was prepared, not executed:
  - no live network;
  - no credentials;
  - no production mutation;
  - Alex-only approval block remains required.
- Recommended first live step remains read-only / shadow-like, not write:

```text
prod-shadow read-only / status check first
write/create/cancel smoke only after a separate human approval
```

- Operator console P1 closed as design/readiness:
  - facts are the console;
  - views are read-only projections;
  - `boot`/`tick` safe host actions;
  - compensate/reissue/live/credentials remain gated.

### SparkCRM Webhook Auction Policy

- Auction duplicate-policy P1 clarified the business lever:

```text
idempotency       = safety envelope, always on
duplicate_policy  = business strategy, configurable per ServiceRecipe/vendor
```

- The repeated vendor webhook strategy is now explicit/readiness-level, not a
  hidden hack:
  - `dedup_strict` for payment/irreversible cases;
  - `bounded_fresh(n)` for vendor auction resend leverage;
  - attempt index can seed distinct UPI/offer codes;
  - win-rate uplift remains a hypothesis to measure per vendor.

### Federation Readiness

- Federation readiness P1 separated two planes:
  - replication plane: capsules, recipes, transfer envelopes, messages, audit facts
    can be mirrored/signed/imported without consensus;
  - effect plane: exactly-one execution remains single-owner.
- Minimal v0 route:

```text
read-only mirror + signed capsule sync
NO active-active effects
NO automatic split-brain failover
```

### Frame / UI

- Frame/UI line advanced from mechanics to DX:
  - `igniter-frame` is the projection/input runtime;
  - `igniter-3d`, `igniter-gui`, and `igniter-ui-kit` are consumers over the same
    runtime;
  - `igniter-machine` remains the boring state/effect kernel.
- UI-kit workbench composition P10 proved a Rust-authored multi-panel screen:
  sidebar/list + main/form + inspector, stable ids, scoped validation, focus,
  deterministic replay, browser/WASM.
- DX authoring model P11 closed the key question:

```text
Today: developer writes Rust.
Next portable artifact: ViewArtifact JSON.
Later ergonomic sugar: .igv.
.ig remains business logic / state / effects authority, not UI markup.
```

- Next frame route named but not started:

```text
LAB-FRAME-VIEWARTIFACT-P12
```

### Language / Canon Pressure

- Effect/capability surface was clarified:
  - Ruby accepted broader effect labels;
  - Rust effect-name parity was closed by `LANG-EFFECT-NAME-PARITY-P2`.
- Dynamic dispatch unknown policy closed as HOLD:
  - literal string callee can be static dispatch;
  - non-literal/dynamic callee remains `Unknown`;
  - `Unknown.field` fails closed;
  - `rule_engine` remains governance-gated, not a VM bug.
- Sumtype/canon drift around `Option`/`Result` matchability remains a canon
  decision surface:
  - live compilers accept match over `Option`/`Result`;
  - stale tutorial/canon wording should route through a canon reconciliation
    gate, not silent lab edits.

## Current State At End Of Day

### Repos / Worktree

- `igniter-lang`: clean after today's proposal/canon-adjacent commits.
- `igniter-gov`: clean.
- `igniter-lab`: contains the latest frame DX P11 card/doc from Opus and should
  be reviewed/committed as the next small slice if desired.

### Machine / IO

- In-lab IO correctness and production hardening are closed.
- Live/staging is explicitly not authorized.
- Next live-related work must be a human-gated operational decision, not an agent
  continuation.

### Frame / UI

- Mechanics are proven.
- Rust authoring is proven.
- Portable app-authoring is not implemented yet.
- Next safest implementation step is ViewArtifact JSON -> UI-kit -> frame runtime.

### Language

- VM runtime common layer is no longer today's main pressure.
- Dynamic dispatch remains intentionally fail-closed.
- Canon tutorial/doc drift should be handled through canon gate cards.

## Rebalanced Backlog For Tomorrow

### P0 — Morning Review / Commit Hygiene

1. Review and commit the P11 frame DX authoring model slice if it looks good:
   - `LAB-FRAME-DX-AUTHORING-MODEL-P11.md`
   - `lab-frame-dx-authoring-model-p11-v0.md`
2. Check whether any background frame/gui/ui changes remain uncommitted.
3. Do not mix frame/ui commits with language or machine-hardening commits.

### P0 — Frame/UI Next Crest

4. `LAB-FRAME-VIEWARTIFACT-P12`
   - proof-local ViewArtifact JSON;
   - lower to `igniter-ui-kit` component tree;
   - run over `igniter-frame`;
   - compare behavior to hand-written `Workbench::lead_review`;
   - no `.igv` parser yet.

### P1 — Operator / Console App Route

5. After P12, choose one app consumer:
   - operator console over P23 observability;
   - or small IDE-shell with replay strip / frame viewer / lineage inspector.
6. Keep it as a consumer of the kit, not a place to invent new primitives.

### P1 — Machine Topology / Storage Follow-Ups

7. If continuing machine ops:
   - distributed-lock/backend-CAS readiness only, not implementation;
   - file backend power-loss/fsync validation only if it becomes production-relevant;
   - no live SparkCRM until human gate.

### P1 — Language Canon Follow-Ups

8. Canon reconciliation cards only:
   - Option/Result matchability doc stance;
   - dynamic dispatch sealed registry readiness if `rule_engine` becomes active again.
9. Do not silently edit canon tutorial behavior claims without a canon authority decision.

## Do Not Start First Tomorrow

- Do not start live SparkCRM traffic.
- Do not build `.igv` parser before ViewArtifact JSON.
- Do not push UI concerns into `igniter-machine`.
- Do not turn `.ig` into UI markup by implication.
- Do not reopen machine IO hardening unless a concrete gap appears.

## Suggested Morning Entry Points

```text
1. Commit/review frame DX P11.
2. Open LAB-FRAME-VIEWARTIFACT-P12.
3. If energy is lower: do a small repo hygiene/status pass and stop.
```
