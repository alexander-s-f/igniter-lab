# Card: LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2 - SparkCRM ServerApp shadow harness and fixtures

**Lane:** standard / implementation proof  
**Status:** CLOSED (implementation proof)
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18
**Authority:** Lab-only local proof. No public listener. No daemon. No live DB. No real SparkCRM API/endpoint.  
**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-C`

## Why this card exists

`igniter-server` has a local server loop (`P5`) and a reloadable pointer (`P4`). To validate the SparkCRM integration shape safely before any live/staging smoke, we must build an offline shadow harness. The harness runs a local `ServerApp` mapped to sanitized SparkCRM-shaped webhook fixtures, producing `InvokeEffect` decisions that are executed against local fake executors (DB-free, TLS-free, network-free). This validates input normalization, duplicate key extraction, and bounded fresh policies under pure, deterministic simulation.

## Read first

- `<igniter-server>/src/protocol.rs`
- `<igniter-server>/src/effect_host.rs`
- `<igniter-lab>/lab-docs/lang/lab-machine-sparkcrm-server-app-readiness-p1-v0.md`
- `<igniter-lab>/lab-docs/lang/lab-sparkcrm-webhook-auction-policy-p1-v0.md`
- `<igniter-lab>/lab-docs/lang/lab-machine-sparkcrm-live-gate-p1-v0.md`

## Goal

Implement the SparkCRM-shaped `ServerApp` and a local shadow test harness that processes sanitized
offline sample payloads (no live network IO) and executes them against local fake executors to prove
normalization, duplicate key extraction, and bounded auction policy correctness.

## Required shape

1.  **Fixture payload collection.**
    - Include a static fixture module/file (e.g. `src/fixture/sparkcrm_payloads.rs`) holding sanitized
      local webhook-like requests (raw JSON strings or `Value` objects representing lead-intake,
      lead-bid, and lead-status updates).
    - No dynamic file loading or external network calls; keep payloads strictly in-memory.

2.  **SparkCRM ServerApp implementation.**
    - Implement a struct `SparkCrmApp` implementing `ServerApp`.
    - Normalizes raw vendor-like webhook fields to a clean local capsule input shape (e.g. `lead_id`, `bid_amount_cents`, `attempt`).
    - Maps inbound paths to logical targets:
      * `/webhook/leads` -> `lead-intake`
      * `/webhook/bids` -> `lead-bid`
      * `/webhook/status` -> `lead-status`
    - Returns `ServerDecision::InvokeEffect` containing the normalized target and input.
    - Restricts outputs: must NOT inject `capability_id`, `operation`, or `scope` into decisions.

3.  **Duplicate key extraction.**
    - `SparkCrmApp` extracts the duplicate key using precedence:
      1. Header `x-auction-id` or body field `auction_id`.
      2. Deterministic composite key from non-secret stable fields such as `phone + email + campaign`
         plus a coarse time bucket if no auction ID exists. Do not mandate a specific hash algorithm
         in the card; use the repository's existing digest helper if one is already local to the
         implementation.
      3. Header `idempotency-key` fallback.
    - Keyless request policy: missing key immediately returns `400 Bad Request` (never treat as fresh).

4.  **Bounded fresh duplicate policy.**
    - Configure a mock/local `ServiceRecipe` with `duplicate_policy = bounded_fresh(max_fresh = 5)` and `after_limit = dedup_last`.
    - The fake/local host increments `attempt_index` and injects it into the `"attempt"` seed field of the capsule input.
    - Verify that the capsule generates deterministic UPI codes based on `attempt_index`.
    - Past `max_fresh` (i.e. request 6+), verify that `dedup_last` replays the 5th attempt result without triggering a new effect.

5.  **Local fake executor.**
    - Implement a local fake capability executor / machine fixture for targets: `lead-intake`,
      `lead-bid`, and `lead-status`.
    - The fake executor performs no network IO or database mutations. It records attempts and returns mock successful responses (e.g., `{"status": "accepted", "upi": "UPI-..."}`).

## Acceptance

- [ ] `igniter-server cargo test` passes.
- [ ] Processing sanitized webhook fixtures maps to correct logical targets with zero network connection.
- [ ] A request with a duplicate key is successfully parsed, and sequential duplicate webhooks map to incremental `attempt_index` values up to `max_fresh = 5`.
- [ ] A 6th duplicate request is suppressed via `dedup_last`, returning the 5th cached result.
- [ ] Keyless webhook requests return `400 Bad Request` with zero side effects.
- [ ] Decisions carry no `capability_id`, `operation`, or `scope` (asserted structurally).
- [ ] No public listener, no daemon, no real SparkCRM API endpoints, no live database credentials.
- [ ] Proof doc written: `lab-docs/lang/lab-machine-sparkcrm-server-app-shadow-p2-v0.md`.

## Suggested tests

- `test_sparkcrm_lead_intake_normalization`
- `test_duplicate_key_extraction_precedence`
- `test_keyless_webhook_refusal_is_400`
- `test_bounded_fresh_auction_attempts_up_to_limit`
- `test_after_limit_dedup_last_replays_fifth_attempt`
- `test_decisions_carry_no_privileged_effect_identity`

## Closed surfaces

- No live SparkCRM network endpoints.
- No live database (Postgres/RocksDB active connections).
- No credential verification.
- No public listener.
- No daemon process.
- No main line/canon language status.

## Next routes

- `LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-REPORT-P3` — summarize local shadow results and decide
  whether a human live-gate packet should be revisited.
- Existing `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1` remains the separate human gate. Do not infer live
  execution from this shadow harness.

---

## Closing report — 2026-06-18

**Outcome:** Offline SparkCRM-shaped `ServerApp` + sanitized in-memory fixtures implemented and proven
through the P3 machine contour. Deterministic, DB-free, network-free, credential-free. All guardrails
held; **zero `igniter-machine` semantic changes**.

**Deliverable:** `lab-docs/lang/lab-machine-sparkcrm-server-app-shadow-p2-v0.md`.

**Canonical-key correction applied:** recipe `duplicate_policy.key_header = "idempotency-key"` (generic);
`SparkCrmApp` extracts the vendor key (precedence: `x-auction-id` > body `auction_id` > deterministic
composite > `idempotency-key`) into `ServerDecision.idempotency_key`; the P3 adapter now FORCE-inserts
that canonical key as the IngressRequest `idempotency-key` header (override). Vendor normalization stays
in the app, the machine duplicate gate stays generic. The change is inert for P3/P4/P5 (decisions there
carry `idempotency_key = None`) — those suites still pass.

**Implementation (lab-only, `igniter-server`):**
- `src/sparkcrm.rs` (new, machine-free) — `SparkCrmApp` (path→target, normalize_input with integer
  `base`, key extraction, deterministic opaque composite via std `DefaultHasher`, no host clock).
- `src/sparkcrm_payloads.rs` (new, machine-free) — sanitized in-memory lead/bid/status/composite/keyless.
- `src/effect_host.rs` — canonical `idempotency-key` force-insert.
- `tests/sparkcrm_app_tests.rs` (new) 5 + `tests/sparkcrm_shadow_tests.rs` (new, `machine`) 5.

**Exact commands + pass counts:**

```text
$ cd igniter-server && cargo test                    → 26 passed; 0 failed (shadow + effect gated off)
$ cd igniter-server && cargo test --features machine → 39 passed; 0 failed
```
`igniter-server` warning-clean both builds.

**Key tests:** targets normalize+execute (3 targets → 3 effects); keyless → 400 zero effects (unit +
over-socket); bounded_fresh attempts 0..4 → `applied_count==5` + distinct `payload_digest` per attempt;
deterministic code reproducible across fresh runs; 6th → `dedup_last` replay (body==5th, no new effect,
no `:5` receipt); precedence header>body>composite>idempotency-key; decisions carry no
`capability_id`/`operation`/`scope`.

**Acceptance:** all boxes met. No live execution inferred — `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1` remains
the separate human gate; next local route = `LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-REPORT-P3`.
