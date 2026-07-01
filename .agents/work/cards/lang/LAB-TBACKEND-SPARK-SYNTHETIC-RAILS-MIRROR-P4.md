# LAB-TBACKEND-SPARK-SYNTHETIC-RAILS-MIRROR-P4 — synthetic Rails mirror for Spark-shaped facts

Status: CLOSED
Lane: tbackend / acts-as-tbackend / Spark-shaped business pressure
Type: implementation + measurement + report
Delegation code: OPUS-TBACKEND-SPARK-SYNTHETIC-RAILS-MIRROR-P4
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P3 proved a real Spark-shaped read-only data slice:

- `lead_signals` dev DB has 3,858,208 rows; `outbox_events` is empty in the chosen dev DB.
- Sanitized `lead_signals` samples ingest through `acts-as-tbackend` `write_fact_once`.
- TBackend aggregate/query results match the Spark/Ruby baseline for two metrics.
- Safe manual compaction + reboot works on real-shaped facts.

That still proves **batch export -> side ledger**, not Rails lifecycle mirroring. The next safe step is a
synthetic Rails mirror that behaves like the Spark path without touching SparkCRM production or dev rows.

## Current Authority

- ActiveRecord/Postgres remains the source of truth.
- TBackend is side-evidence / shadow ledger only.
- This card must use synthetic data only.
- No SparkCRM writes, no production DBs, no remote hosts, no Docker/AWS, no secrets.
- Real SparkCRM code may be read for shape, but must not be modified.

## Verify First

Read current P3 artifacts:

- `runtime/acts-as-tbackend/docs/spark-outbox-leadsignal-proof.md`
- `runtime/acts-as-tbackend/scripts/spark_export_sample.rb`
- `runtime/acts-as-tbackend/scripts/spark_outbox_leadsignal_probe.rb`

Read current `acts-as-tbackend` surfaces:

- `runtime/acts-as-tbackend/lib/acts_as_tbackend.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/client.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/fact.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/mirror.rb` or equivalent callback surface
- `runtime/acts-as-tbackend/test/*`

Read Spark shape only if needed:

- `/Users/alex/dev/projects/sparkcrm/app/models/lead_signal.rb`
- `/Users/alex/dev/projects/sparkcrm/app/models/outbox_event.rb`
- `/Users/alex/dev/projects/sparkcrm/app/services/analytics/lead_signals_hourly_load.rb`

Before implementation, confirm:

1. where the current callback/mirror API lives;
2. whether it can derive a stable fact id from `model.id + updated_at` or equivalent version field;
3. whether daemon-unavailable failures are soft/classified and do not fail the AR write path;
4. whether store names must be underscore-only (`spark_lead_signals`, not `spark.lead_signals`).

If any of these are false, stop and write the exact blocker.

## Goal

Build a synthetic Rails lifecycle proof:

```text
Synthetic Rails model write/update/delete-ish event
  -> normal ActiveRecord commit succeeds
  -> acts-as-tbackend after_commit mirror emits sanitized fact
  -> local loopback TBackend stores side evidence
  -> read latest/history/aggregate from TBackend
  -> compare with ActiveRecord baseline
  -> prove retry/idempotency and daemon-down behavior
```

This is the bridge from P3 batch evidence to a future SparkCRM shadow mirror. It should answer:

1. Can the Rails callback path mirror Spark-shaped domain rows without app-write fragility?
2. Are fact ids stable and retry-safe across repeated callbacks?
3. Can TBackend answer latest/history/aggregate queries for mirrored Rails rows?
4. Does AR remain authoritative when TBackend is down?
5. What is the minimal next step toward a real Spark shadow canary?

## Scope

Allowed:

- Add a bounded synthetic Rails fixture/app or test harness under `runtime/acts-as-tbackend/`.
- Use SQLite or temporary Postgres if the existing test stack already supports it; choose the smallest reliable path.
- Start a local loopback `tbackend` daemon with a temp data-dir.
- Add tests and a proof packet under `runtime/acts-as-tbackend/docs/`.
- Reuse P3's sanitized `lead_signals` value shape.
- Use underscore store names:
  - `spark_lead_signals`
  - `spark_outbox_events` only if synthetic rows are created

Closed:

- No SparkCRM writes.
- No production DBs.
- No raw PII.
- No remote services.
- No daemon source changes unless a hard blocker is found; if found, stop and document.
- Do not claim production readiness.

## Suggested Shape

Create one synthetic model shape first:

```text
SyntheticLeadSignal
  id
  channel
  vendor_name
  state
  accepted
  bid
  converted
  order_status
  eligibility_mode
  signal_at
  updated_at
```

Mirror value should stay P3-compatible and sanitized:

```json
{
  "channel": "...",
  "vendor_name": "...",
  "state": "...",
  "accepted": true,
  "bid": 12.34,
  "converted": false,
  "order_status": "...",
  "eligibility_mode": "...",
  "has_did": false,
  "has_upi": false,
  "has_request_id": false,
  "has_trace_id": false,
  "data_keys": []
}
```

Fact identity must be retry-safe:

```text
id    = synthetic_lead_signal:<record_id>:<updated_at_us>
store = spark_lead_signals
key   = lead_signal:<record_id>
valid_time = signal_at
```

If `updated_at_us` is not stable enough in the chosen harness, use a persisted version column and document why.

## Acceptance

- [ ] Verify-first notes identify the exact callback/mirror surface used.
- [ ] Synthetic AR create mirrors one fact through `write_fact_once` and returns committed/acked status.
- [ ] Synthetic AR update mirrors a second version under the same key; TBackend history shows both versions.
- [ ] Re-running the same mirror operation is idempotent (no duplicate logical fact; classified as replay/already committed if exposed).
- [ ] TBackend daemon-down path does not fail the AR write transaction; the failure is classified/observable.
- [ ] Aggregate parity: TBackend count by `vendor_name` or `state` matches AR baseline on the synthetic fixture.
- [ ] Latest/history query: TBackend latest for a key matches the newest AR-derived value.
- [ ] No raw PII fields or raw payloads appear in docs, fixtures, or proof output.
- [ ] Temp daemon and temp DB/data-dir are cleaned unless an explicit keep-env var is set.
- [ ] Existing `acts-as-tbackend` tests remain green.
- [ ] `git diff --check` clean.

## Deliverables

- Synthetic Rails mirror proof code or tests.
- Proof packet:
  - `runtime/acts-as-tbackend/docs/spark-synthetic-rails-mirror-proof.md`
- Closing report in this card with:
  - exact commands run;
  - result counts;
  - daemon-down behavior;
  - idempotency behavior;
  - any remaining blockers before a real Spark shadow canary.

## Closing Report

**CLOSED 2026-07-01.** Full evidence in `docs/spark-synthetic-rails-mirror-proof.md`. First live exercise of
the P1 extension callback path against real ActiveRecord + a live daemon.

```text
Verify-first: callback surface = extension.rb (acts_as_tbackend macro -> after_commit -> Mirror.mirror! ->
  write_fact_once_safe); id = store:record_id:event_type:updated_at_us (stable, retry-safe); daemon-down soft
  (after_commit post-commit + soft result); underscore store name (spark_lead_signals). All 4 confirmed — no blocker.

Harness: SQLite :memory: ActiveRecord (AR 8.1.3, sqlite3 2.9.4) + SyntheticLeadSignal model with
  acts_as_tbackend store: spark_lead_signals, only: [8 safe columns]; live loopback tbackend (temp data-dir).

Result — ALL 8 checks pass (60 records, exit 0):
- create -> 60 facts (one per record); create status committed/idempotent_replay
- aggregate parity: TBackend count-by-vendor == AR baseline (20/20/20)
- update -> 2 versions under same key (facts_for = 2); latest_for bid 999.99 == AR bid 999.99
- idempotent re-mirror -> idempotent_replay, fact count 2->2 (no dup)
- daemon-down: AR create still persists (true); mirror returns soft "unavailable", no exception into AR path

Commands: ruby -Ilib scripts/synthetic_rails_mirror_proof.rb --records 60 (exit 0, ALL CHECKS PASSED);
  unit suite 12 runs/37 assertions/0 fail (green); ruby -c OK; gem build 0.2.0 OK (removed);
  daemon: ./target/release/tbackend --host 127.0.0.1 --port <auto> --data-dir <tmp> --durability accepted.
Cleanup: proof auto-removes temp; final check NO daemons, NO temp dirs. git diff --check clean.

daemon-down behavior: AR write survives, mirror soft-classified (unavailable) — non-fatal, observable.
idempotency: same (record,event,updated_at) -> idempotent_replay, no duplicate fact.

Remaining blockers before a real Spark shadow canary: NONE hard. Notes: (1) Mirror key = "store:record_id"
(not "lead_signal:<id>" as the card suggested) — works; make key builder configurable if a store-free key is
wanted (small follow-up). (2) fact id includes event_type (create/update distinct facts; repeat=replay).

Decision: READY. Next: LAB-TBACKEND-SPARK-SHADOW-CANARY-READINESS-P5 (design the first bounded, single-model,
observe-only SparkCRM shadow boundary — enabled? guard, soft-fail, no app-write coupling).
```

### Changed (all under `runtime/acts-as-tbackend/`)
- `scripts/synthetic_rails_mirror_proof.rb` (new) — self-asserting lifecycle proof.
- `docs/spark-synthetic-rails-mirror-proof.md` (new) — evidence packet.

Scope kept: synthetic data only, no SparkCRM writes/reads-of-rows, no daemon source changes, no production.

## Non-Goals

- Real SparkCRM integration.
- Rails engine packaging.
- Production daemon deployment.
- Async outbox worker.
- Full hourly rollup API.

## Expected Next Cards

If P4 succeeds:

- `LAB-TBACKEND-SPARK-SHADOW-CANARY-READINESS-P5` — design the first real Spark shadow canary boundary.
- `LAB-TBACKEND-STORE-NAME-VALIDATION-P*` — daemon-side validation/error message for dotted store names.
- `LAB-TBACKEND-ANALYTICS-GROUP-WINDOW-READINESS-P*` — cross-key hourly rollup API design.

