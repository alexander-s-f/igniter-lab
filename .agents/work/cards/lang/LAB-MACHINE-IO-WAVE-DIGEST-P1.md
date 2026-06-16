# Card: LAB-MACHINE-IO-WAVE-DIGEST-P1 — IO wave front-door digest

**Lane:** governance / anti-drift / digest · **Skill:** idd-agent-protocol
**Status: CLOSED 2026-06-16.** Coordination/navigation artifact — **no code, no new authority.**

> **Front door deliverable:** [`lab-docs/lang/lab-machine-io-wave-digest-p1-v0.md`](../../../../lab-docs/lang/lab-machine-io-wave-digest-p1-v0.md)
> One compact digest for the full igniter-machine IO wave, so future agents stop rediscovering
> ~25 scattered cards and do not confuse in-lab proof with live readiness.

## Goal

Single navigation front door covering the capability-IO substrate (P1–P15), the HTTP/TLS/SparkCRM
executor, the coordination/service runtime, the bridge/wire contour, and hardening (P18–P25) —
compact enough to read before coding, routing to (not duplicating) the per-phase cards.

## Authority boundary

- **Source of truth:** live code + `igniter-machine/IMPLEMENTED_SURFACE.md` + `…-HARDENING-CAPSTONE-P25`.
- **Cards / proofs:** evidence only.
- **Digest authority:** navigation / front-door — **not** new feature authority.
- **Closed surfaces (held):** no code changes, no new IO behaviour, no live/staging work, no
  movement of historical cards, no rewriting old evidence docs (except an optional front-door pointer).

## Verify-first evidence (2026-06-16)

- 30 source modules present in `igniter-machine/src/`; 36 test files in `tests/`.
- `cargo test --no-default-features` → **256 passing**.
- `cargo test --no-default-features --features tls` → **271 passing** (adds real-TLS + SparkCRM).
- Confirmed on disk: `LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`, `…-PRODUCTION-HARDENING-P17`,
  `…-HARDENING-CAPSTONE-P25`, `LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1`,
  `LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE`.
- ⚠ Out-of-scope finding (NOT fixed here): plain `cargo test` (default features incl. `ffi`)
  fails to compile on a stale async `.await` in `src/ffi.rs` — unrelated to the IO wave; the
  canonical command is `--no-default-features`. Flagged for a separate task.

## Deliverables

- ✅ `lab-docs/lang/lab-machine-io-wave-digest-p1-v0.md` — the digest (7 sections: exec summary,
  timeline map, proven table, NOT-proven gate, next routes, agent search protocol, noise note).
- ✅ `.agents/work/cards/lang/LAB-MACHINE-IO-WAVE-DIGEST-P1.md` — this card.
- ✅ `igniter-machine/IMPLEMENTED_SURFACE.md` — one-line pointer to the digest added at the top.
- ⊘ MAP/status pointer — **not added**: `MAP.md` is navigation-only ~1 screen and already routes to
  per-crate `IMPLEMENTED_SURFACE.md`; no clear slot without adding noise. Surface pointer is enough.

## Acceptance (all met)

- Compact enough to read before coding (one-screen exec summary + tables).
- Pointers repo-stable, point to current artifacts.
- Cleanly separates "in-lab closed" from "live gated" (§4 NOT-proven table).
- Routes to cards, does not duplicate their details.
- Anti-drift warning included (stale docs lose to live code + surface).
- No new feature proposal hidden inside.

## Next route

Navigation only; no follow-on required. Future P-slices in this wave should add a row to the
digest's §3 table and the surface, not a new front door.
