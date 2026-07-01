# LAB-TBACKEND-SPARK-OUTBOX-LEADSIGNAL-ANALYTICS-P3 — real Spark-shaped analytics + compaction proof

Status: CLOSED
Lane: tbackend / Spark-shaped evidence / business pressure
Type: implementation + measurement + report
Delegation code: OPUS-TBACKEND-SPARK-OUTBOX-LEADSIGNAL-ANALYTICS-P3
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P2 proved raw local throughput for `acts-as-tbackend` + local `tbackend`:

- accepted writes: ~2M rpm local loopback;
- durable sample: ~52k rpm;
- deterministic replay: `idempotent_replay`;
- hostile backpressure: soft/classified, no hard Ruby exceptions.

That is necessary but still synthetic. The next useful pressure is a real
Spark-shaped domain slice:

- main DB: `spark_dev_db_2026_06_25` → `outbox_events` (`OutboxEvent`);
- analytics DB: `spark_dev_analytics_db_15_05_2026_v2` → `lead_signals` (`LeadSignal`).

Goal: ingest sanitized real samples into TBackend, measure storage growth, use
TBackend analytics/query functions on those facts, and run safe manual
compaction/rollup on a warm/cold split.

## Current Authority

- SparkCRM/Postgres remains source of truth.
- TBackend is side-evidence only.
- This card is local/dev read-only extraction and local loopback TBackend.
- No SparkCRM writes, no production DB, no remote host, no Tailscale, no Docker/AWS.

## Verify First

Read live Spark shape:

- `/Users/alex/dev/projects/sparkcrm/app/models/outbox_event.rb`
- `/Users/alex/dev/projects/sparkcrm/app/models/lead_signal.rb`
- `/Users/alex/dev/projects/sparkcrm/db/schema.rb` (`outbox_events`)
- `/Users/alex/dev/projects/sparkcrm/db/analytics_db_schema.rb` (`lead_signals`)
- `/Users/alex/dev/projects/sparkcrm/app/services/analytics/bulk_lead_signal_ingestor.rb`
- `/Users/alex/dev/projects/sparkcrm/app/services/analytics/lead_signals_hourly_load.rb`
- `/Users/alex/dev/projects/sparkcrm/app/services/mcp/tools/outbox_health_tool.rb`

Read live TBackend analytics/compaction surfaces:

- `igniter-tbackend/scripts/verify/verify_analytics.rb`
- `igniter-tbackend/scripts/verify/verify_snapshot.rb`
- `igniter-tbackend/src/packs/query.rs`
- `igniter-tbackend/src/packs/analytics.rs`
- `igniter-tbackend/src/packs/snapshot.rs`
- `igniter-tbackend/src/main.rs`

Live facts already confirmed by curator:

- `OutboxEvent`: `event_type`, `event_at`, `processed_at`, `payload`, timestamps;
  scopes `pending`, `processed`, `processed_before`, `for_processing`.
- `LeadSignal`: `channel`, `vendor_name`, `zip_code`, `state`, `accepted`, `bid`,
  `signal_at`, `converted`, `order_status`, `eligibility_*`, `data`, timestamps.
- TBackend supports `query_slice`, `analytics_aggregate`, `analytics_calculate`,
  `analytics_metrics`, `snapshot_policy_create`, `snapshot_trigger`, `size`, and
  safe manual compaction via `--enable-compaction true`.

## Goal

Produce a bounded real-data proof:

```text
Spark dev DB read-only sample
  -> sanitized TBackend facts
  -> analytics/query measurements
  -> file-size/storage growth measurements
  -> safe manual compaction/rollup proof
```

The proof should answer:

1. What does `outbox_events` / `lead_signals` look like as TBackend fact streams?
2. How fast does WAL size grow for real-shaped payloads?
3. Which TBackend analytics functions are already useful for Spark indicators?
4. Does safe manual compaction/rollup work on real-shaped lead-signal facts?
5. What should improve next: schema projection, analytics API, compaction policy,
   storage format, or connector ergonomics?

## Data Safety / Redaction

Do **not** dump raw payloads blindly.

Use a strict allowlist and redact or omit potentially sensitive fields.

Recommended fact values:

### `outbox_events` store

Allowed:

- `event_type`
- `event_at`
- `processed_at`
- extracted payload fields only if present and safe:
  - `channel`
  - `trade_name`
  - `vendor_name`
  - `zip_code` (5 digits only)
  - `state`
  - `accepted`
  - `bid`
  - `operator_id` as numeric/id evidence only
  - `has_did` boolean, not raw DID
  - `has_upi` boolean, not raw UPI
  - `payload_keys` array

Omit raw `did`, `upi`, phone/email/name/address, raw request bodies, and any
unknown nested payload values.

### `lead_signals` store

Allowed:

- `channel`, `trade_name`, `vendor_name`
- `zip_code`, `city`, `county`, `state`, `timezone`
- `accepted`, `bid`, `converted`, `order_status`
- `eligibility_mode`, `eligibility_slots`, `eligibility_threshold`
- `signal_at`, `created_at`, `updated_at`
- `external_operator_id`, `external_trade_id`, `external_vendor_id`
- `linkage_source`, `linkage_confidence`
- `has_did`, `has_upi`, `has_request_id`, `has_trace_id`

Omit raw `did`, `upi`, `request_id`, `trace_id`, and full `data` JSON. If data
shape matters, record only `data_keys`.

## Scope

Allowed:

- Add a local script under `runtime/acts-as-tbackend/scripts/`, for example:
  `spark_outbox_leadsignal_probe.rb`.
- Add a proof packet under `runtime/acts-as-tbackend/docs/`.
- Read Spark dev DBs through Rails runner or read-only SQL.
- Start local loopback `tbackend` with temp data-dir and `--enable-compaction true`.
- Ingest bounded samples and optionally synthetic-scale them by repeating the real
  distribution with new deterministic ids.

Closed:

- No SparkCRM writes.
- No production DBs.
- No remote hosts/Tailscale/Docker/AWS.
- No secrets in docs/output.
- No raw PII/lead payload dumps.
- No TBackend daemon source changes unless a hard blocker is found; if found,
  stop and write the exact blocker.

## Suggested Plan

### 1. Read-only Spark sampling

From `/Users/alex/dev/projects/sparkcrm`, verify DB access:

```text
bundle exec rails runner 'puts({ outbox: OutboxEvent.count, lead_signals: LeadSignal.count }.inspect)'
```

If DB is unavailable, stop with the exact error. Do not generate fake claims.

Collect bounded samples:

- `outbox_events`: latest N processed + pending, default N=5_000;
- `lead_signals`: latest N by `signal_at`, default N=5_000;
- counts by day/hour/status before export;
- a small shape report: payload keys, null rates, top channels/vendors/states,
  accepted/converted rates.

### 2. Sanitized transform to TBackend facts

Use deterministic ids:

```text
spark_outbox:<outbox_id>:<updated_at_us>
spark_lead_signal:<lead_signal_id>:<updated_at_us>
```

Stores:

- `spark.outbox_events`
- `spark.lead_signals`

Keys:

- `outbox:<id>`
- `lead_signal:<id>`

Set:

- `valid_time` = `event_at` for outbox, `signal_at` for lead signals;
- `transaction_time` may remain server-stamped unless explicit historical TX is
  needed for compaction tests. For cold/warm compaction, use a derived cold/warm
  dataset with explicit transaction time if TBackend API allows it, or document
  the limitation.

### 3. Storage growth measurement

Measure after each ingest batch:

- fact count by store (`size`);
- WAL file bytes per store;
- total data-dir bytes;
- avg bytes/fact;
- write elapsed / rpm;
- memory-ish metric if available from `analytics_metrics` / diagnostics.

Run at least:

- small real sample: 1k + 1k;
- normal sample: 5k + 5k;
- synthetic-scale sample: 50k+ if local runtime is reasonable, generated from
  sampled distribution, not raw duplicated ids.

### 4. TBackend analytics proof

Use TBackend operations against `spark.lead_signals`:

- `query_slice`:
  - accepted leads by vendor/state/channel;
  - bid > threshold;
  - converted true;
  - eligibility mode filters if present.
- `analytics_aggregate`:
  - count by `value.channel`;
  - count + avg/sum bid by `value.vendor_name`;
  - accepted/converted count by `value.state`;
  - count by `value.eligibility_mode`.
- `analytics_calculate`:
  - if useful on time-series per key or vendor, test SMA/stddev over `value.bid`;
  - otherwise report that current API is timeline-per-key oriented and not ideal
    for Spark hourly rollups.
- Compare at least two aggregate results with ActiveRecord/SQL from Spark for the
  same sanitized sample window.

Use Spark's existing `Analytics::LeadSignalsHourlyLoad` as conceptual reference,
but do not mutate its code.

### 5. Compaction / rollup proof

Run local TBackend with:

```text
--enable-compaction true
```

Create a rollup policy for `spark.lead_signals`:

- retention period: choose a cutoff that splits sample into cold/warm;
- target store: `spark.lead_signals_summary`;
- group by: `value.vendor_name`, `value.zip_code` or `value.state`, `value.accepted`;
- aggregates:
  - `count`;
  - `sum value.bid`;
  - optionally avg if supported.

Trigger:

```text
snapshot_policy_create
snapshot_trigger
```

Measure:

- source store size before/after;
- summary store size;
- WAL bytes before/after;
- compaction stats (`__compaction_stats`) if available;
- reboot correctness: restart daemon from compacted data-dir and verify warm facts
  + summary facts load.

## Required Evidence

Proof packet must include:

- DB names used:
  - `spark_dev_db_2026_06_25`;
  - `spark_dev_analytics_db_15_05_2026_v2`.
- exact sample window and row counts;
- redaction/allowlist used;
- ingest counts and status mix;
- file-size growth table;
- analytics operations attempted and which were useful;
- SQL/AR comparison for at least two metrics;
- compaction/rollup before/after table;
- limitations and next-card recommendation.

## Required Commands

At minimum:

```text
cd /Users/alex/dev/projects/sparkcrm
bundle exec rails runner '<read-only counts/sample-shape command>'

cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-tbackend
cargo build --release --bin tbackend

cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/acts-as-tbackend
ruby -Ilib:test -e 'ARGV.each { |f| require File.expand_path(f) }' test/*_test.rb
ruby -Ilib scripts/spark_outbox_leadsignal_probe.rb --sample 5000 --json
```

Also:

```text
git diff --check -- runtime/acts-as-tbackend .agents/work/cards/lang/LAB-TBACKEND-SPARK-OUTBOX-LEADSIGNAL-ANALYTICS-P3.md
```

## Acceptance

- [ ] Spark DB access verified read-only or exact blocker reported.
- [ ] Sample transform uses allowlist/redaction; no raw PII in docs.
- [ ] Local TBackend ingest works for both stores.
- [ ] File growth measured at multiple sample sizes.
- [ ] At least three TBackend analytics/query operations are exercised on
      Spark-shaped facts.
- [ ] At least two TBackend metrics are compared with Spark SQL/AR baseline.
- [ ] Safe manual compaction/rollup is exercised, or exact API blocker reported.
- [ ] Reboot-after-compaction correctness is checked if compaction runs.
- [ ] No SparkCRM writes, no production/remote host access.
- [ ] Existing `acts-as-tbackend` unit suite still passes.
- [ ] `git diff --check` clean.

## Stop Conditions

Stop and report instead of widening scope if:

- Spark DB is unavailable or points somewhere unexpected;
- sampling would require exposing raw sensitive payload fields;
- TBackend analytics API cannot express a needed metric without raw client-side
  full-scan; report the exact missing operation;
- compaction cannot be run safely on local temp data;
- ingest creates duplicate conflicts for deterministic ids;
- daemon leaves temp data/processes behind.

## Non-goals

- No SparkCRM feature change.
- No production/preview deployment.
- No long soak or maximum-ceiling benchmark.
- No replacing Spark analytics rollups.
- No new TBackend daemon optimization unless a correctness blocker appears.

## Closing Report

**CLOSED 2026-07-01.** Full evidence in `docs/spark-outbox-leadsignal-proof.md`.

```text
Result:
- sampled rows: lead_signals (spark_dev_analytics_db_15_05_2026_v2, 3,858,208 total), latest N by
  signal_at, N=1000 & 5000. outbox_events (spark_dev_db_2026_06_25) = 0 rows (EMPTY) -> proof on
  lead_signals only.
- redaction: strict allowlist; did/upi/request_id/trace_id -> has_* booleans; data jsonb -> data_keys;
  no raw PII / payload bodies leave Spark.
- ingest/file-growth: connector write_fact_once, accepted. 1k -> 611,541 B store / 694,239 B WAL;
  5k -> 3,058,584 / 3,473,844; 55k (5k real + 50k synthetic new-id) -> 33,172,204 / 37,733,884.
  ~603 bytes/fact, linear. All committed_acked, ~2.0M rpm.
- analytics useful: analytics_aggregate (count/sum by vendor/state/channel/eligibility_mode) + query_slice
  (accepted filter, 801/5000) + analytics_calculate (SMA, ran). PARITY: TBackend count-by-vendor AND
  count-by-state EXACTLY match Spark AR GROUP BY on the same 5000 sample.
- analytics gaps: analytics_calculate is timeline-per-key, not cross-key windowed (a gap for hourly-rollup
  indicators; snapshot rollup covers cross-key group aggregates). outbox not exercised (empty DB).
- compaction result: --enable-compaction true; cold/warm split (5 cold >3d retention / 5 warm); rollup
  policy (group vendor/state/accepted, sum bid + count) -> pruned_facts=5, created_summaries=2, source
  10->5 facts, source WAL 6,778->3,390 B (shrank). Reboot: warm(5)+summary(2) preload OK, 55k main intact.

Verified:
- commands: unit suite 12 runs/37 assertions/0 fail (still green); ruby -c probe+export OK;
  gem build 0.2.0 OK (removed); daemon cmd: ./target/release/tbackend --host 127.0.0.1 --port <auto>
  --data-dir <tmp> --durability accepted [--enable-compaction true]. Spark access read-only via
  Rails runner (DATABASE/ANALYTICS_DATABASE + PGCONNECT_TIMEOUT).
- cleanup: probe auto-removes temp data-dir + sample; leftover daemons/dirs from interactive isolation
  debugging were killed + removed; final check = NO daemons, NO temp dirs/samples. git diff --check clean.

Decision:
- CONDITIONAL-READY for a Spark-shaped side-ledger experiment. Works end to end with two conditions:
  (1) store names must use underscores not dots (write_fact_once rejects dotted store names);
  (2) treat analytics_calculate as per-key (use snapshot rollups for cross-key indicators).
- next card: LAB-TBACKEND-SPARK-SYNTHETIC-RAILS-MIRROR-P4 (synthetic AR models + extension full in-request
  path); optionally LAB-TBACKEND-ANALYTICS-API-GAPS-* if hourly cross-key rollups are needed.
```

### Changed (all under `runtime/acts-as-tbackend/`)
- `scripts/spark_export_sample.rb` (new) — read-only allowlisted Rails-runner export.
- `scripts/spark_outbox_leadsignal_probe.rb` (new) — ingest via connector + raw analytics/snapshot/size
  helper + storage/analytics/compaction/reboot + baseline parity.
- `docs/spark-outbox-leadsignal-proof.md` (new) — evidence packet.

### Key daemon findings (for follow-up, no daemon changes made)
1. **Dotted store names break `write_fact_once`** — use underscores. 2. `write_fact_once` requires a
complete fact envelope (`transaction_time`+`schema_version`; `Fact.build` supplies them). 3. **No two-core
split** — connector `write_fact_once` facts are fully analytics/query/snapshot-visible (earlier confusion
was malformed test facts). 4. `analytics_calculate` is timeline-per-key. Scope kept: no SparkCRM writes,
no daemon source changes, no production/remote.

## Likely Next Cards

- `LAB-TBACKEND-SPARK-SYNTHETIC-RAILS-MIRROR-P4` — full ActiveRecord extension path
  with synthetic Spark-shaped models.
- `LAB-TBACKEND-ANALYTICS-API-GAPS-P*` — if Spark indicators expose missing
  group/window/query operations.
- `LAB-TBACKEND-CEILING-LOAD-P*` — controlled maximum/soak benchmark, separate from
  this real-shape analytics proof.
