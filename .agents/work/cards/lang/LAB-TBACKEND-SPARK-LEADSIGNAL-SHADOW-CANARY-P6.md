# LAB-TBACKEND-SPARK-LEADSIGNAL-SHADOW-CANARY-P6 — sampled explicit LeadSignal shadow canary

Status: OPEN
Lane: tbackend / SparkCRM shadow evidence / business pressure
Type: implementation + dev/staging proof + report
Delegation code: OPUS-TBACKEND-SPARK-LEADSIGNAL-SHADOW-CANARY-P6
Date: 2026-07-01
Skill: idd-agent-protocol

## Dependency decision — PAUSED pending public repo + gem publish (2026-07-01)

Verify-first resolved everything except **how SparkCRM loads `acts-as-tbackend`** (verify-first item 5).
A sibling-path Gemfile dep is **prod-unsafe** (breaks any checkout/CI without the `igniter-workspace`
sibling; SparkCRM's `path:` convention is in-repo `vendor/*` only). The dependency decision is now:
**public GitHub repo is canonical, RubyGems carries the versioned gem, Forgejo is at most a read-only
internal mirror.**

**Prepared (this card):** gemspec made GitHub/RubyGems-ready (`allowed_push_host` = rubygems.org,
homepage/source = GitHub), `gem build` green, unit suite 12/0, and a publish runbook
`runtime/acts-as-tbackend/RELEASE.md`.

**Blocked on:** creating/pushing the standalone public GitHub repo and publishing `acts-as-tbackend 0.2.0`
to RubyGems. Once SparkCRM can `bundle install` it as a normal versioned gem, P6 resumes: the guarded,
sampled, explicit hook in `BulkLeadSignalIngestor` (verify-first below already confirmed the hook point,
the `now`-based version stamp, and the allowlist).

## Context

P3 proved Spark-shaped **batch** evidence:

- sanitized Spark dev `lead_signals` samples ingest through `acts-as-tbackend`;
- TBackend aggregates match Spark/Ruby baselines for vendor/state counts;
- safe manual compaction + reboot works;
- chosen dev DB had `outbox_events = 0`, so `LeadSignal` is the only real-data target proven so far.

P4 proved synthetic Rails **lifecycle** evidence:

- real ActiveRecord model + live loopback TBackend daemon;
- create/update history, latest, aggregate parity, idempotent replay;
- daemon-down is soft/non-fatal.

P5 chose the first real Spark shadow boundary:

- **recommended target:** `LeadSignal`;
- **important correction:** Spark writes `LeadSignal` through `insert_all`, so `after_commit` callbacks do not fire;
- therefore P6 must use an **explicit mirror hook in `Analytics::BulkLeadSignalIngestor`** on the returned `inserted_rows`, not the `acts_as_tbackend` macro.

## Current Authority

- SparkCRM/Postgres remains source of truth.
- TBackend is side-evidence / shadow ledger only.
- This card may modify SparkCRM code, but only for a disabled-by-default, observe-only canary.
- No production enablement.
- No remote daemon requirement.
- No raw PII/payload mirroring.
- Mirror failure must never fail Spark ingest or mark an `OutboxEvent` unprocessed.

## Target Repos

Primary implementation target:

- `/Users/alex/dev/projects/sparkcrm`

Read-only evidence/reference:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/acts-as-tbackend`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-tbackend`

## Verify First

In SparkCRM, read live implementation surfaces:

- `app/services/analytics/bulk_lead_signal_ingestor.rb`
- `app/models/lead_signal.rb`
- `app/models/outbox_event.rb`
- `Gemfile` / local gem dependency convention
- feature flag / app setting surfaces, if any:
  - `System::AppSetting`
  - env-based feature gates
  - existing config/initializer patterns
- logging/health tooling:
  - `app/services/mcp/tools/outbox_health_tool.rb`
  - any existing analytics health/report tool

In acts-as-tbackend, read:

- `lib/acts_as_tbackend/mirror.rb`
- `lib/acts_as_tbackend/fact.rb`
- `lib/acts_as_tbackend/client.rb`
- `lib/acts_as_tbackend/config.rb`
- `docs/spark-shadow-canary-readiness.md`

Confirm before editing:

1. `LeadSignal.insert_all(...)` still bypasses callbacks and returns `inserted_rows`.
2. `returning:` still omits `updated_at` unless already changed.
3. `inserted_rows` has enough columns to build a sanitized mirror DTO, or can be joined to the inserted payload by `idempotency_key`.
4. There is a safe flag/config place for `TBACKEND_ENABLED`, `TBACKEND_CANARY_LEADSIGNAL`, and sample-mod.
5. SparkCRM can load `acts-as-tbackend` locally in dev/test without requiring a published gem.

If any item is false, stop and write the exact blocker.

## Goal

Implement the smallest SparkCRM dev/staging canary:

```text
BulkLeadSignalIngestor insert_all
  -> inserted_rows
  -> triple guard + sample gate
  -> explicit ActsAsTbackend::Mirror.mirror!(record-like DTO, store: spark_lead_signals, event_type: ingest)
  -> soft result counted/logged
  -> Spark ingest continues regardless
```

The canary must prove:

1. a sampled `LeadSignal` ingest can mirror to TBackend;
2. the mirror is retry-stable and bounded;
3. daemon-down does not change Spark ingest behavior;
4. parity/readback can compare TBackend against Spark AR for the mirrored slice;
5. one flag disables the canary immediately.

## Required Design

### Guarding

All of these must be true before a mirror write is attempted:

1. `ActsAsTbackend.enabled?`
2. lead-signal canary flag on:
   - env var `TBACKEND_CANARY_LEADSIGNAL=1`, or
   - an existing Spark settings surface if clearly better
3. sample gate passes:
   - `TBACKEND_CANARY_LEADSIGNAL_SAMPLE_MOD`
   - default must be sparse and safe, e.g. `1000` or stricter

If disabled, the code path should no-op cheaply.

### Data Shape

Store:

```text
spark_lead_signals
```

Event type:

```text
ingest
```

Allowed fields:

- `channel`
- `trade_name`
- `vendor_name`
- `zip_code`
- `city`
- `county`
- `state`
- `timezone`
- `accepted`
- `bid`
- `converted`
- `order_status`
- `eligibility_mode`
- `eligibility_slots`
- `eligibility_threshold`
- `external_operator_id`
- `external_trade_id`
- `external_vendor_id`
- `linkage_source`
- `linkage_confidence`
- `has_did`
- `has_upi`
- `has_request_id`
- `has_trace_id`
- `data_keys`

Never mirror:

- raw `did`
- raw `upi`
- raw `request_id`
- raw `trace_id`
- raw phone/email/name/address
- full `data` JSON
- raw outbox payloads

### Version Stamp

P5 found that current Spark `insert_all returning:` omits `updated_at`. P6 must provide a stable version stamp:

- Preferred: include `updated_at` in `returning:` if supported and harmless.
- Alternative: build a record-like DTO from the original payload plus returned row, using the same `now` value already assigned in `build_payloads`.
- Do **not** allow `ActsAsTbackend::Mirror.source_version` to fall back to wall-clock for this canary.

### Record-like DTO

If `LeadSignal` ActiveRecord instances are not available after `insert_all`, use a minimal object responding to:

- `id`
- `updated_at`
- `valid_time` or equivalent
- `attributes`

It should be local/private to the ingestor or a tiny named helper. Keep it boring.

### Failure Semantics

- Mirror errors are caught and classified.
- Mirror failures are logged as status counts, never raw values.
- The ingestor must still process and mark `OutboxEvent` rows as it would without TBackend.
- Daemon down = soft no-op / `unavailable`, not exception propagation.

### Observability

Add the smallest useful observability:

- mirror attempts
- committed/replay counts
- soft-fail counts
- disabled/skipped counts
- sample-mod value

Prefer an internal service result or log line. If there is an obvious health endpoint/tool pattern, add a read-only health reporter. Do not build a dashboard.

### Parity / Readback

Add a dev/test proof that compares:

- Spark AR count by `vendor_name` or `state` for the mirrored sample/window
- TBackend `analytics_aggregate` over `spark_lead_signals` for the same sample/window

It may be a script or test harness. Keep it bounded and local.

## Implementation Scope

Allowed:

- SparkCRM code changes in `Analytics::BulkLeadSignalIngestor` and a small helper/service if needed.
- SparkCRM tests or proof script.
- SparkCRM docs/notes for dev-only canary use.
- Local path dependency/config for `acts-as-tbackend` only if that is the existing SparkCRM convention for local experiments.

Closed:

- No production config enablement.
- No automatic daemon provisioning.
- No remote/Tailscale/AWS.
- No full background job/outbox retry framework.
- No TBackend daemon changes.
- No broad analytics API work.
- No availability/scheduling domain work.

## Acceptance

- [ ] Verify-first notes confirm live `insert_all` behavior and the chosen version-stamp solution.
- [ ] Canary is disabled by default.
- [ ] Triple guard implemented.
- [ ] Sample gate implemented with safe default.
- [ ] Explicit mirror hook runs after `insert_all` for sampled `inserted_rows`.
- [ ] Raw PII/payload fields are structurally excluded.
- [ ] Stable retry-safe fact id proven; no wall-clock fallback for mirrored LeadSignal facts.
- [ ] Daemon-down proof: Spark ingest still succeeds and outbox rows are handled as before.
- [ ] TBackend-on proof: sampled facts appear in `spark_lead_signals`.
- [ ] Parity/readback proof: at least one aggregate matches Spark AR for the mirrored slice.
- [ ] Observability/status counts recorded without payload leakage.
- [ ] SparkCRM tests/proof command documented and green.
- [ ] `acts-as-tbackend` existing tests remain green if touched or if the local gem path is changed.
- [ ] No production flags enabled.
- [ ] `git diff --check` clean.

## Deliverables

- SparkCRM implementation diff.
- SparkCRM test/proof command output.
- Proof packet or implementation note, suggested:
  - `runtime/acts-as-tbackend/docs/spark-leadsignal-shadow-canary-p6.md`, or
  - SparkCRM-local agent/proof doc if the team convention prefers that.
- Closing report in this card with:
  - exact files changed;
  - exact flags/config;
  - commands run;
  - daemon-up result;
  - daemon-down result;
  - parity result;
  - rollback instruction.

## Rollback

At minimum:

```text
TBACKEND_ENABLED=0
```

or disable the canary-specific flag. The rollback must not require code deploy if the flag exists.

## Non-Goals

- Production canary.
- Remote daemon hardening.
- Durable daemon deployment.
- Full SparkCRM ledger rewrite.
- OutboxEvent mirror.
- Availability/scheduler mirror.

## Expected Next Cards

If P6 succeeds:

- `LAB-TBACKEND-SPARK-LEADSIGNAL-SHADOW-CANARY-P7` — dev/staging soak + operational runbook, or
- `LAB-TBACKEND-SPARK-SHADOW-HEALTH-P7` — health/parity reporter hardening, or
- `LAB-TBACKEND-STORE-NAME-VALIDATION-P*` — daemon-side dotted-store validation/error cleanup.
