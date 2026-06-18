# Card: LAB-MACHINE-IGNITER-SERVER-APP-BOUNDARY-P6 — keep domain apps out of server core

**Lane:** standard / architecture hygiene + narrow refactor
**Skill:** idd-agent-protocol
**Status:** CLOSED (architecture hygiene + narrow refactor)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Authority:** Lab-only refactor. No behavior expansion. No live SparkCRM. No public listener.

## Why this card exists

`LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2` proved a useful offline SparkCRM-shaped `ServerApp`, but it
placed `SparkCrmApp` and `sparkcrm_payloads` under `igniter-server/src/`. That sends the wrong
architectural signal: `igniter-server` must remain server substrate (protocol, wire/transport,
concurrency/lifecycle, reload, middleware, optional machine bridge) and must NOT own SparkCRM or any
product domain. The domain belongs to app packages/examples/tests that implement `ServerApp`.

This is not "delete the SparkCRM proof" — it is "move it to the right place" so the proof is not an
architectural lie.

## Required shape

1. Remove domain modules from core exports (`pub mod sparkcrm;` / `pub mod sparkcrm_payloads;`).
2. Keep the shadow proof — move `SparkCrmApp` + sanitized payloads into test fixture scope.
3. Tests still prove the same behavior (machine-free + machine), keeping the canonical duplicate-key
   correction.
4. Core server modules contain no SparkCRM vocabulary; README clarifies domain apps live outside core.
5. No behavior expansion (no middleware, plugin, assets, live SparkCRM, DB/network).

## Acceptance

- [x] `cargo test` + `cargo test --features machine` pass.
- [x] `rg` finds no core-domain hits in `igniter-server/src` (only justified negation comments).
- [x] `igniter_server::sparkcrm` / `igniter_server::sparkcrm_payloads` no longer exist.
- [x] SparkCRM shadow tests still prove target mapping, canonical duplicate key, keyless 400 zero
      effects, bounded_fresh attempts, dedup_last replay.
- [x] Proof doc + P2 supersession note + closing report.

## Closed surfaces

No new app/plugin framework · no middleware · no assets protocol · no SparkCRM live/staging ·
no DB/network · no public listener · no canon claim · no new effect semantics.

## Next route

`LAB-MACHINE-IGNITER-SERVER-EXTENSIONS-READINESS-P7` — how third-party/domain apps extend/specialize
`igniter-server` without hard-wiring into the base crate (app packages, examples, static vs dynamic
composition, middleware wrappers, assets, optional feature crates, versioned `ServerApp` protocol, what
stays forbidden in core).

---

## Closing report — 2026-06-18

**Outcome:** Boundary hygiene done. The SparkCRM-shaped app was relocated from the core
`igniter-server` public surface into a test fixture, with identical behavior and pass counts — the
SHADOW-P2 proof is preserved, not deleted. Core now exports only generic server substrate.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-app-boundary-p6-v0.md` (+ P2 doc
supersession note).

**Changes (narrow, behavior-preserving):**
- Deleted `src/sparkcrm.rs` + `src/sparkcrm_payloads.rs`; removed their `pub mod` exports from
  `src/lib.rs`. `igniter_server::sparkcrm*` no longer exist.
- Moved `SparkCrmApp` + sanitized payloads to `tests/fixtures/sparkcrm_app.rs` (`#![allow(dead_code)]`,
  in-memory, sanitized), included by both SparkCRM test files via `#[path]`.
- Rewired `tests/sparkcrm_app_tests.rs` + `tests/sparkcrm_shadow_tests.rs` to the fixture; same
  assertions. Canonical duplicate-key correction preserved (app extracts vendor key →
  `ServerDecision.idempotency_key`; recipe `key_header = "idempotency-key"` generic).
- De-vocabularized core: `src/protocol.rs` sample target `"lead-intake"` → neutral `"demo-target"`.
- README: added "Domain apps live OUTSIDE the core" section pointing to P7.

**Exact commands + pass counts:**

```text
$ cd igniter-server && cargo test                    → 26 passed; 0 failed   (unchanged vs P2)
$ cd igniter-server && cargo test --features machine → 39 passed; 0 failed   (unchanged vs P2)
$ rg -n "SparkCRM|SparkCrm|sparkcrm|auction|lead-bid|lead-intake|lead-status" igniter-server/src
    → only 2 justified negation comments (fixture.rs, bin/igniter-server.rs: "…no SparkCRM…")
```
`igniter-server` warning-clean in both builds. `igniter-machine` untouched.

**Acceptance:** all boxes met. Next = `LAB-MACHINE-IGNITER-SERVER-EXTENSIONS-READINESS-P7`.
