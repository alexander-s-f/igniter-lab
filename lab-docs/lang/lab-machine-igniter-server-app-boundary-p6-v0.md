# lab-machine-igniter-server-app-boundary-p6-v0 — keep domain apps out of server core

**Card:** `LAB-MACHINE-IGNITER-SERVER-APP-BOUNDARY-P6`
**Status:** CLOSED (architecture hygiene + narrow refactor) — the SparkCRM-shaped app was relocated
from the core `igniter-server` public surface into a test fixture. **No behavior change, no expansion,
no new app/plugin framework, no middleware, no live SparkCRM, no DB/network, no `igniter-machine`
change.**
**Authority:** Lab-only refactor. No canon claim.

## Why

SHADOW-P2 proved a useful offline SparkCRM `ServerApp`, but placed `SparkCrmApp` +
`sparkcrm_payloads` under `igniter-server/src/` and exported them as `igniter_server::sparkcrm*`. That
made the proof an architectural lie: `igniter-server` is server **substrate** (protocol, wire,
concurrency/lifecycle, reload, serving loop, optional machine bridge) — like Rack/Puma — and must own
**no** product domain. P6 moves the domain app to where a domain app belongs (a consumer that
implements `ServerApp`) without losing the proof.

```text
igniter-server core exports generic server substrate only.
SparkCRM shadow app is a test fixture implementing ServerApp, not server API.
```

## What changed (narrow, behavior-preserving)

| Action | Detail |
|---|---|
| **Removed from core** | deleted `src/sparkcrm.rs` + `src/sparkcrm_payloads.rs`; removed `pub mod sparkcrm;` / `pub mod sparkcrm_payloads;` from `src/lib.rs`. `igniter_server::sparkcrm*` no longer exist. |
| **Moved to fixture** | `SparkCrmApp` + sanitized payloads now live in `tests/fixtures/sparkcrm_app.rs` (in-memory, sanitized, `#![allow(dead_code)]` since shared across two test binaries). Both SparkCRM test files include it via `#[path = "fixtures/sparkcrm_app.rs"] mod sparkcrm_fixture;`. |
| **Tests rewired** | `tests/sparkcrm_app_tests.rs` + `tests/sparkcrm_shadow_tests.rs` now `use sparkcrm_fixture::{payloads as fx, SparkCrmApp};` — same assertions, same behavior. |
| **Core de-vocabularized** | `src/protocol.rs` unit tests used the domain string `"lead-intake"` as a sample target; changed to the neutral `"demo-target"`. Core now contains no product vocabulary. |
| **README** | added a "Domain apps live OUTSIDE the core" section: core exports substrate only; a domain app is a `ServerApp` consumer; points to the P7 extensions readiness. |
| **Canonical-key correction preserved** | the fixture `SparkCrmApp` still extracts the vendor key → `ServerDecision.idempotency_key`; the machine recipe still uses generic `duplicate_policy.key_header = "idempotency-key"` (the adapter force-inserts the canonical key, unchanged from P2). |

No new crate was created (explicitly deferred). No middleware, plugin system, or assets protocol was
added.

## Acceptance — met

- [x] `igniter-server cargo test`: **26 passed; 0 failed** (unchanged vs P2).
- [x] `igniter-server cargo test --features machine`: **39 passed; 0 failed** (unchanged vs P2).
- [x] `rg -n "SparkCRM|SparkCrm|sparkcrm|auction|lead-bid|lead-intake|lead-status" igniter-server/src`
      returns **no core-domain hits** — only two *negation* comments remain (`fixture.rs`,
      `bin/igniter-server.rs`: "…no SparkCRM…"), which document the boundary and are explicitly
      justified.
- [x] `igniter_server::sparkcrm` and `igniter_server::sparkcrm_payloads` no longer exist.
- [x] SparkCRM shadow tests still prove: target mapping; canonical duplicate key; keyless 400 zero
      effects; bounded_fresh attempts 0..4; `dedup_last` replay.
- [x] Core server (`protocol.rs`, `host.rs`, `reload.rs`, `serving_loop.rs`, `effect_host.rs`) contains
      no SparkCRM product vocabulary.
- [x] Proof doc (this file) + P2 supersession note + closing report in the card.
- [x] No behavior expansion (no middleware / plugin / assets / live SparkCRM / DB / network).

## Exact commands + pass counts

```text
$ cd igniter-server && cargo test                    → 26 passed; 0 failed
$ cd igniter-server && cargo test --features machine → 39 passed; 0 failed
$ rg -n "SparkCRM|SparkCrm|sparkcrm|auction|lead-bid|lead-intake|lead-status" igniter-server/src
    src/fixture.rs:8:            … no SparkCRM paths, tables, or business terms.   (negation comment)
    src/bin/igniter-server.rs:4: … no SparkCRM, no DB/live.                        (negation comment)
```
(`igniter-server` compiles warning-clean in both builds.)

## Closed surfaces (held)

No new app/plugin framework · no middleware · no assets protocol · no SparkCRM live/staging · no
DB/network · no public listener · no canon claim · no new effect semantics.

## Next

- `LAB-MACHINE-IGNITER-SERVER-EXTENSIONS-READINESS-P7` — research/readiness: how third-party/domain
  apps should extend or specialize `igniter-server` without hard-wiring into the base crate (app
  packages, examples, static vs dynamic composition, middleware wrappers, assets, optional feature
  crates, versioned `ServerApp` protocol, and what stays forbidden in core).
