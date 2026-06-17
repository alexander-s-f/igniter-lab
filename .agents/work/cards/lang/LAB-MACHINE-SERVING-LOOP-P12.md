# Card: LAB-MACHINE-SERVING-LOOP-P12 — host-owned serving loop over wire-to-effect

**Lane:** standard / implementation-readiness · **Skill:** idd-agent-protocol  
**Status: CLOSED (2026-06-17) — implemented + proven (283 machine tests green, +4).** See the
closing report at the bottom. Non-live, loopback/local only. This card must not open public ingress,
external SparkCRM, deployment, credentials, or a daemon manager.

## Front door

Read first:

- `LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE.md`
- `LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25.md`
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Live surfaces to verify before writing:

- `ingress::serve_once_effect` — real 127.0.0.1 HTTP/1.1 request → duplicate policy →
  one replica → capsule intent → one effect → receipt → HTTP response.
- `orchestrator::EffectOrchestrator::{boot,tick,report}` — host-driven recovery/drain/report,
  no daemon.
- `observability::observe` — read-only projection from facts.

## Goal

Define and minimally prove the **host serving shape** around the already-proven wire-to-effect
entrypoint:

```text
open local listener
  → boot recovery once
  → accept/process requests by repeatedly calling serve_once_effect
  → host-owned tick cadence drains due retries
  → report/observe remains queryable
  → graceful stop after bounded condition in tests
```

This is not "production deployment"; it is the missing in-lab host shell that shows how the
machine lives as a process without inventing a background daemon.

## Required decisions

1. **Loop ownership:** host owns the loop and cadence; the machine exposes functions, not a daemon.
2. **Scope:** loopback/local only (`127.0.0.1`); no public listener, no TLS ingress, no live vendor.
3. **Concurrency:** allow bounded concurrent request handling only if it keeps P18 atomic-gate
   semantics. Same idempotency key must still execute at most one effect.
4. **Tick policy:** explicit cadence or manual tick hook; no hidden background scheduler.
5. **Shutdown:** tests must have a deterministic stop condition (N requests, cancellation token, or
   bounded duration). Do not create an unkillable loop.
6. **Observability:** boot/tick/request counts must be visible through existing facts/projections
   or a tiny host report. Do not create a side-log as truth.

## Acceptance

- [ ] Verify-first section names the exact current APIs and confirms no public server loop already
      exists.
- [ ] A minimal `ServingLoop`/host helper (name agent may choose) composes:
      `EffectOrchestrator::boot`, repeated `serve_once_effect`, optional `tick`, and `report/observe`.
- [ ] Tests use real loopback TCP and a fake/local executor only.
- [ ] Test proves at least two requests can be processed by one loop instance.
- [ ] Test proves duplicate same-key requests still produce exactly one effect/receipt.
- [ ] Test proves tick can drain a due retry intent while the loop shape remains host-owned.
- [ ] Test proves deterministic shutdown; no leaked task/session at the end of the test.
- [ ] No live network, no SparkCRM staging/prod, no credentials, no public bind address.
- [ ] `IMPLEMENTED_SURFACE.md` is updated only if a new public surface is actually added.
- [ ] Proof doc explains the boundary between "serving loop in lab" and "deployment topology/live".

## Closed surfaces

- Do not change capability-IO semantics.
- Do not add public ingress/TLS exposure.
- Do not create a daemon, supervisor, systemd unit, Dockerfile, or deployment topology.
- Do not call real SparkCRM or any external host.
- Do not widen duplicate policy or effect idempotency semantics.

## Deliverables

- Implementation and tests if the minimal helper is needed.
- `lab-docs/lang/lab-machine-serving-loop-p12-v0.md`
- Closing report in this card.
- Optional pointer from `LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE.md` if the proof closes.

## Next routes

- Deployment topology implementation packet (separate).
- Public ingress threat model (separate, human-gated).
- SparkCRM live/staging smoke remains behind `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`.

---

## Closing report — CLOSED (2026-06-17)

**Outcome:** the in-lab host serving shell now exists and is proven. The host owns a bounded loop;
the machine still exposes only functions. No daemon, no public ingress, no live vendor, no credentials.

**Verify-first (confirmed live, before writing):**
- `ingress::serve_once_effect(listener, router, hub, cfg) -> io::Result<()>` — serves exactly ONE
  connection through the full P11 contour; "No background worker".
- `orchestrator::EffectOrchestrator{receipts,substrate,registry,clock,passport,base_delay}` with
  `boot()`/`tick()`/`report()`; `tick` "Does NOT loop — the host calls `tick` on its own cadence."
- `observability::observe(facts)` — pure read-only projection.
- **No host serving loop existed.** `service_loop.rs` is the capability single-call entrypoint
  (`run_service_*`), not a TCP loop. Gap confirmed real.

**Added (one new module, zero changes to existing effect/coordination/orchestrator surfaces):**
- `igniter-machine/src/serving_loop.rs` — `ServingLoop` + `ServingPolicy` + `ServingReport`.
  `run(orch, policy)` = `boot()` once → repeat `serve_once_effect` until `max_requests` → optional
  host-owned `tick` cadence (`tick_every`/`tick_on_stop`) → derived report. Sequential (no new
  concurrency → P18 gate intact). No `tokio::spawn`, no hidden scheduler, loopback-only.
- `lib.rs` exports `pub mod serving_loop;`.

**Tests:** `tests/serving_loop_tests.rs` (4, real `127.0.0.1`, fake executor):
two-requests-one-loop (+ observe/report queryable) · duplicate same-key → exactly one effect ·
host-owned tick drains a due retry · deterministic bounded shutdown (re-entrant, no leaked acceptor).

**Verification:** `cargo test --no-default-features` → **283 passed / 0 failed** (was 279; +4). No
existing test changed; no warnings from the new files.

**Acceptance:** all boxes met.
- ✅ Verify-first names exact APIs + confirms no pre-existing server loop.
- ✅ `ServingLoop` composes `boot` + repeated `serve_once_effect` + optional `tick` + `report/observe`.
- ✅ Real loopback TCP + fake/local executor only.
- ✅ ≥ two requests through one loop instance.
- ✅ Duplicate same-key → exactly one effect/receipt.
- ✅ Tick drains a due retry while the loop stays host-owned.
- ✅ Deterministic shutdown; bounded; re-entrant; no leaked task/session.
- ✅ No live network / SparkCRM / credentials / public bind.
- ✅ `IMPLEMENTED_SURFACE.md` updated (a new public surface WAS added).
- ✅ Proof doc explains the lab-loop vs deployment/live boundary.

**Deliverables:** `src/serving_loop.rs`, `tests/serving_loop_tests.rs`,
`lab-docs/lang/lab-machine-serving-loop-p12-v0.md`, `IMPLEMENTED_SURFACE.md` update, milestone pointer.

**Boundary held:** no capability-IO/duplicate/idempotency change; no public ingress/TLS; no
daemon/supervisor/systemd/Dockerfile/deployment topology; no real SparkCRM/external host. Live remains
behind `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`.
