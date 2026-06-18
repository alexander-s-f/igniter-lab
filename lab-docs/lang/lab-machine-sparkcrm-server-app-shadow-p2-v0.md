# lab-machine-sparkcrm-server-app-shadow-p2-v0 — SparkCRM ServerApp shadow harness

**Card:** `LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2`
**Status:** CLOSED (implementation proof) — an offline, deterministic SparkCRM-shaped `ServerApp` +
sanitized in-memory fixtures, executed against local fake executors through the proven P3 machine
contour. **No live SparkCRM, no public listener, no daemon, no real Postgres/DB, no credentials, no
network IO, no `igniter-machine` semantic change.**
**Authority:** Lab-only shadow proof. No canon claim. Product meaning = SparkCRM/Alex. Builds on the
P1 readiness packet + the auction-policy readiness.

## What this card proves

```text
sanitized webhook fixture (in-memory)
  → SparkCrmApp::call            (path→target, raw fields→clean input, canonical key extraction)
  → ServerDecision::InvokeEffect { target, input, idempotency_key }   (NO capability_id/operation/scope)
  → MachineEffectHost (P3)        (target→route infra binding; forces the canonical idempotency-key)
  → IngressRouter::handle_effect  (bounded_fresh(5) → attempt 0..4 → one effect each; dedup_last)
  → local FakeWriteExecutor + receipts   (no DB, no network)
```

### The canonical-key correction (applied)

Vendor normalization lives entirely in the app; the machine duplicate policy stays **generic**. The
recipe's `duplicate_policy.key_header = "idempotency-key"` (not a vendor header). `SparkCrmApp` extracts
the duplicate key by precedence and puts the result into `ServerDecision.idempotency_key`. The P3
adapter (`MachineEffectHost::run_invoke_effect`) was changed to **force-insert** that canonical key as
the `idempotency-key` header of the `IngressRequest`, overriding any raw vendor header — so the machine
gates duplicates on exactly what the app decided. (This is the only `effect_host.rs` change; it is
inert for P3/P4/P5 because their decisions carry `idempotency_key = None`, and their 8/… tests still
pass.)

## Implementation surface (all lab-only, `igniter-server`)

| File | Role |
|---|---|
| `src/sparkcrm.rs` (**new, machine-free**) | `SparkCrmApp: ServerApp` — `/webhook/leads→lead-intake`, `/webhook/bids→lead-bid`, `/webhook/status→lead-status`; `normalize_input` (clean local shape, always supplies integer `base`); `extract_key` precedence; deterministic `composite_key` (std `DefaultHasher`, opaque `comp-<hex>`, no PII echoed, no host clock) |
| `src/sparkcrm_payloads.rs` (**new, machine-free**) | sanitized in-memory fixtures (lead / bid / status / composite-only / keyless) |
| `src/effect_host.rs` | `run_invoke_effect` now force-inserts the decision's canonical `idempotency-key` (override) |
| `tests/sparkcrm_app_tests.rs` (**new, machine-free**) | 5 normalization / precedence / 400 / no-identity tests |
| `tests/sparkcrm_shadow_tests.rs` (**new, `#![cfg(feature = "machine")]`**) | 5 harness tests over the machine contour |

### Key extraction precedence (as specified)

1. `x-auction-id` header → 2. body `auction_id` → 3. deterministic composite from non-secret stable
fields (`phone`,`email`,`campaign`,`event_bucket`) → 4. `idempotency-key` header fallback. **No key →
`Respond 400`, zero effects** (never silently fresh, never randomized).

### Authority boundary (held)

`SparkCrmApp` emits only a logical inbound `target` + normalized `input` + canonical `idempotency_key`.
It NEVER emits `capability_id` / `operation` / `scope` — asserted structurally in
`test_decisions_carry_no_privileged_effect_identity` (serialized decision has no such keys). The host
owns the outbound effect identity via the signed recipe + `EffectBridgeConfig`.

### Duplicate / auction policy (recommended profile)

Recipe `duplicate_policy = bounded_fresh(max_fresh=5, after_limit=dedup_last, key_header="idempotency-
key", seed_field="attempt", variant_payload=false, require_key=true)`. The host injects `attempt_index`
0..4 into `attempt`; the capsule (`contract LeadOffer { code = base + attempt }`) mints a deterministic
code per attempt. Effect idempotency key = `<canonical-key>:<attempt>` → exactly one effect per
accepted attempt; past the bound, `dedup_last` replays the last response with no new effect.

## Acceptance — met

- [x] `igniter-server cargo test` (default, machine-free): **26 tests, 0 failed**.
- [x] `igniter-server cargo test --features machine`: **39 tests, 0 failed**.
- [x] Fixture lead/bid/status normalize to correct targets (`test_sparkcrm_lead_intake_normalization`,
      `test_target_mapping_bids_and_status`) and execute through the machine with zero network
      (`test_sparkcrm_targets_execute_through_machine`: three targets → three committed effects).
- [x] Keyless request returns 400 and performs zero effects (machine-free
      `test_keyless_webhook_refusal_is_400` + end-to-end `test_keyless_webhook_is_400_zero_effects_
      over_socket`: `applied_count == 0`).
- [x] Duplicate attempts 0..4 produce distinct deterministic codes
      (`test_bounded_fresh_auction_attempts_up_to_limit`: `applied_count == 5`, receipts
      `IO.LeadStore:AUC-DUP:0..4` with pairwise-distinct `payload_digest`) +
      (`test_deterministic_code_is_reproducible_across_runs`: attempt-0 digest identical across two
      fresh fixtures).
- [x] 6th duplicate replays the 5th result, no new effect
      (`test_after_limit_dedup_last_replays_fifth_attempt`: 6th body == 5th body, `applied_count`
      stays 5, no `:5` receipt).
- [x] Decisions structurally carry no `capability_id`/`operation`/`scope`.
- [x] Duplicate-key extraction precedence proven (`test_duplicate_key_extraction_precedence`: header >
      body > composite > idempotency-key).
- [x] No live SparkCRM, no public listener, no daemon, no real DB, no credentials.
- [x] Proof doc (this file) + closing report in the card.

## Exact commands + pass counts

```text
$ cd igniter-server && cargo test
  unittests src/lib.rs                 7 passed; 0 failed
  tests/effect_machine_tests.rs        0 passed (feature-gated off)
  tests/loopback_tests.rs              5 passed; 0 failed
  tests/reload_tests.rs                4 passed; 0 failed
  tests/serving_loop_tests.rs          5 passed; 0 failed
  tests/sparkcrm_app_tests.rs          5 passed; 0 failed
  tests/sparkcrm_shadow_tests.rs       0 passed (feature-gated off)
  TOTAL                               26 passed; 0 failed

$ cd igniter-server && cargo test --features machine
  unittests src/lib.rs                 7 passed; 0 failed
  tests/effect_machine_tests.rs        8 passed; 0 failed
  tests/loopback_tests.rs              5 passed; 0 failed
  tests/reload_tests.rs                4 passed; 0 failed
  tests/serving_loop_tests.rs          5 passed; 0 failed
  tests/sparkcrm_app_tests.rs          5 passed; 0 failed
  tests/sparkcrm_shadow_tests.rs       5 passed; 0 failed
  TOTAL                               39 passed; 0 failed
```

(`igniter-server` compiles warning-clean in both builds; transitive warnings are pre-existing in
`igniter_compiler`/`igniter_machine`.)

## Closed surfaces (held)

No live SparkCRM endpoint · no live DB (Postgres/RocksDB) · no credentials · no public listener · no
daemon · no canon claim. Local fake executor + in-memory backend only; every payload is fabricated.

## Next

- `LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-REPORT-P3` — summarize shadow results and decide whether the
  human live-gate packet should be revisited.
- `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1` remains the separate human gate — live execution must NOT be
  inferred from this shadow harness.
