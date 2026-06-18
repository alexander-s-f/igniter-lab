# Card: LAB-MACHINE-IGNITER-SERVER-WAVE-CHECKPOINT-P14 — server wave digest/checkpoint

**Lane:** standard / checkpoint-digest
**Skill:** idd-agent-protocol
**Status:** CLOSED (checkpoint digest)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
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

---

## Closing report — 2026-06-18

**Outcome:** One compact, source-backed front-door digest written for the `igniter-server` wave. All 8
required sections present (exec summary, P1–P14 timeline, surface map, fresh command block, boundary/
not-proven, DX, next routes, agent navigation). Grounded in live source + fresh `cargo` runs, not card
lore. No code, no new behavior, no live/deploy.

**Deliverable:** `lab-docs/lang/lab-machine-igniter-server-wave-checkpoint-p14-v0.md` + a one-line
front-door pointer added to `igniter-server/README.md` (no rewrite).

**Command results (fresh, this session):**
```text
cargo build --examples              → Finished, 0 warnings
cargo test                          → 49 passed; 0 failed
cargo test --features machine       → 62 passed; 0 failed
```
Per-file (default): lib-unit 7 · loopback 5 · reload 4 · serving_loop 5 · middleware 8 · sparkcrm_app 5
· example_app 8 · app_runner_example 7 (effect_machine 0 + sparkcrm_shadow 0 feature-gated off);
machine adds effect_machine 8 + sparkcrm_shadow 5.

**Inventory verified:** all P1–P13 server cards + both SPARKCRM-SERVER-APP cards are CLOSED (read from
each card's `Status:` line); src module map matches `lib.rs`; two examples + nine test files present.

**Key next route:** `LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-REPORT-P3` (offline product work). Substrate
work is trigger-only (raw response / separate app crate / live gate by human).

**Caveats found:**
- README "Current contents" line ("`src/lib.rs` — exports the protocol module") is **stale shorthand**;
  the real module map is `protocol`/`host`/`reload`/`serving_loop`/`middleware`/`fixture` (+ `effect_host`
  under feature `machine`). Flagged in the digest §8 (stale-claim guards) rather than rewriting README.
- Several non-`Pn` design docs exist (`…-app-stack-composition`, `…-middleware-shape`,
  `…-gemini-wave-a-synthesis`, review checklists) — folded into the timeline/surface map context.

**Acceptance:** all boxes met — 8 sections; source-grounded; fresh commands included; explicit
boundary list; bounded non-live next routes; no code/behavior/live change.
