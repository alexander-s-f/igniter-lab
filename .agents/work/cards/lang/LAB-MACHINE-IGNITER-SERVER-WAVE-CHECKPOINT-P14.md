# Card: LAB-MACHINE-IGNITER-SERVER-WAVE-CHECKPOINT-P14 — server wave digest/checkpoint

**Lane:** standard / checkpoint-digest
**Skill:** idd-agent-protocol
**Status:** OPEN
**Date opened:** 2026-06-18
**Authority:** Lab documentation/checkpoint only. No implementation. No live/deploy authority.

## Why this card exists

The `igniter-server` wave now spans protocol, loopback serving, machine bridge, hot reload, serving
loop, domain boundary, extension readiness, middleware, examples, assets, and packaging. Without a
front-door digest, future agents will become archaeologists and may re-open settled questions.

This card creates one compact source-backed checkpoint for the current server wave.

## Read first

Verify against live code and cards, not memory:

- `igniter-server/README.md`
- `igniter-server/Cargo.toml`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/effect_host.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/examples/server_app_basic.rs`
- `igniter-server/examples/server_app_runner.rs`
- `lab-docs/lang/lab-machine-igniter-server-*.md`
- `.agents/work/cards/lang/LAB-MACHINE-IGNITER-SERVER-*.md`
- `.agents/work/cards/lang/LAB-MACHINE-SPARKCRM-SERVER-APP-*.md`

## Goal

Write a compact checkpoint digest answering:

- what exists today;
- what is proven by tests/examples;
- what commands are green;
- what remains explicitly not proven / not live;
- what next routes are legitimate;
- how a future agent should search/navigate this wave.

This is a navigation artifact, not new authority.

## Required sections

1. **Executive summary (one screen).**
   - What `igniter-server` is now.
   - The core invariant: server owns wire/concurrency/lifecycle; app owns routing/product meaning;
     host owns machine/effect authority.

2. **Timeline table P1-P14.**
   Include at least:
   - P1 protocol readiness
   - P2 loopback binary
   - P3 machine/effect bridge
   - P4 hot reload
   - P5 serving loop
   - SparkCRM readiness/shadow
   - P6 app boundary
   - P7 extensions readiness
   - P8 middleware
   - P9/P10 external app example
   - P11 assets readiness
   - P12 packaging readiness
   - P13 runner example
   - P14 checkpoint

3. **Implemented surface map.**
   - `protocol`, `host`, `effect_host`, `reload`, `serving_loop`, `middleware`, examples.
   - For each: source file, role, key proof/tests.

4. **Command/evidence block.**
   Run or cite fresh commands:
   ```bash
   cd igniter-server && cargo build --examples
   cd igniter-server && cargo test
   cd igniter-server && cargo test --features machine
   ```
   Prefer fresh execution if feasible; otherwise state why not.

5. **Boundary / not proven.**
   Explicitly name:
   - no public listener/live deploy;
   - no live SparkCRM/vendor API;
   - no DB/credentials;
   - no dynamic plugin system;
   - no raw HTML/SVG/binary response protocol yet;
   - no framework/route config in core;
   - no release/canon claim.

6. **Developer DX today.**
   - How to write a minimal `ServerApp`.
   - How to package with `build_app(config)`.
   - How middleware/reload/serving loop compose.
   - Keep concise; point to examples instead of duplicating code.

7. **Next legitimate routes.**
   - SparkCRM shadow report P3.
   - Raw response only if real in-tree app needs verbatim bytes.
   - Separate app crate only if a real second consumer appears.
   - Live gate only by human decision.

8. **Agent navigation protocol.**
   - What to grep first.
   - Which docs/cards are front doors.
   - Which stale paths/claims to ignore if code disagrees.

## Deliverable

Checkpoint digest:

`lab-docs/lang/lab-machine-igniter-server-wave-checkpoint-p14-v0.md`

Closing report in this card with:

- command results;
- key next route;
- any caveats found.

Optional small README pointer is allowed if it helps discovery; do not rewrite README.

## Acceptance

- [ ] Digest answers all 8 required sections.
- [ ] Digest is grounded in live source, not just card lore.
- [ ] Fresh command results included or explicitly explained.
- [ ] Boundaries / not-proven list is explicit.
- [ ] Next routes are bounded and non-live by default.
- [ ] No code changes.
- [ ] No new behavior.
- [ ] No live/network/DB/credentials.
- [ ] Closing report in this card.

## Closed surfaces

- No implementation.
- No new server feature.
- No route framework.
- No raw-response implementation.
- No SparkCRM live/staging.
- No public listener.
- No DB/credentials/vendor API.
- No release/canon claim.

## Suggested conclusion shape

```text
igniter-server in-lab wave: CLOSED ENOUGH as substrate + DX proof
  -> next product work = SparkCRM shadow report / app-specific gates
  -> next substrate work only by trigger: raw response, separate app crate, live gate
```

Verify before writing; do not trust this suggested conclusion blindly.
