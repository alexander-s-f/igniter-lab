# LAB-TBACKEND-SPARK-SHADOW-CANARY-READINESS-P5 — first bounded SparkCRM shadow boundary

Status: CLOSED
Lane: tbackend / SparkCRM shadow evidence / business pressure
Type: readiness + architecture decision + canary plan
Delegation code: OPUS-TBACKEND-SPARK-SHADOW-CANARY-READINESS-P5
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P3 proved a real Spark-shaped **batch** slice:

- sanitized Spark dev `lead_signals` samples ingest through `acts-as-tbackend`;
- TBackend aggregate/query parity matches the Spark/Ruby baseline for two metrics;
- safe manual compaction + reboot works on real-shaped facts;
- `outbox_events` was empty in the chosen dev DB, so no real outbox-row proof yet.

P4 proved a synthetic Rails **lifecycle** slice:

- real ActiveRecord model + `acts_as_tbackend` macro + live loopback daemon;
- create/update history, latest, aggregate parity, idempotent replay;
- daemon-down is soft/non-fatal and does not break the AR write path.

The next decision is **not** "wire this into Spark now". The next decision is the first bounded,
observe-only SparkCRM shadow boundary that can be reviewed safely.

## Current Authority

- SparkCRM/Postgres remains source of truth.
- TBackend remains side-evidence / shadow ledger only.
- A canary must be disabled by default and guarded by operator config / feature flag.
- Mirror failure must never block a Spark write or user-facing flow.
- No production mutation, no automatic deployment, no remote daemon requirement in this readiness card.
- SparkCRM code may be read and reasoned about; do not edit SparkCRM in this card unless the card is explicitly re-scoped.

## Verify First

Read current proof trail:

- `runtime/acts-as-tbackend/docs/spark-outbox-leadsignal-proof.md`
- `runtime/acts-as-tbackend/docs/spark-synthetic-rails-mirror-proof.md`
- `runtime/acts-as-tbackend/scripts/spark_outbox_leadsignal_probe.rb`
- `runtime/acts-as-tbackend/scripts/synthetic_rails_mirror_proof.rb`
- `.agents/work/cards/lang/LAB-TBACKEND-SPARK-OUTBOX-LEADSIGNAL-ANALYTICS-P3.md`
- `.agents/work/cards/lang/LAB-TBACKEND-SPARK-SYNTHETIC-RAILS-MIRROR-P4.md`

Read live `acts-as-tbackend` surfaces:

- `runtime/acts-as-tbackend/lib/acts_as_tbackend/extension.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/mirror.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/fact.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/client.rb`
- `runtime/acts-as-tbackend/lib/acts_as_tbackend/config.rb`

Read SparkCRM shape read-only:

- `/Users/alex/dev/projects/sparkcrm/app/models/lead_signal.rb`
- `/Users/alex/dev/projects/sparkcrm/app/models/outbox_event.rb`
- `/Users/alex/dev/projects/sparkcrm/app/services/analytics/bulk_lead_signal_ingestor.rb`
- `/Users/alex/dev/projects/sparkcrm/app/services/analytics/lead_signals_hourly_load.rb`
- `/Users/alex/dev/projects/sparkcrm/app/services/mcp/tools/outbox_health_tool.rb`
- relevant feature-flag/config surfaces, if any, for a disabled-by-default canary.

Before recommending implementation, confirm:

1. whether the first real canary target should be `LeadSignal`, `OutboxEvent`, or neither;
2. where the Spark write/lifecycle event actually happens;
3. how to guard the mirror path (`enabled?`, env var, feature flag, initializer, or all of them);
4. where failures will be logged/observed without raising into app flow;
5. how to avoid raw PII/payload fields in the mirrored value;
6. how to run and stop a local/staging TBackend daemon for the canary.

## Goal

Write a readiness packet that defines the first SparkCRM shadow-canary slice:

```text
one Spark-owned lifecycle surface
  -> allowlisted, sanitized mirror value
  -> acts-as-tbackend side write
  -> local/staging TBackend store
  -> parity/health/readback report
  -> explicit stop/rollback switch
```

The packet must answer:

1. Which single model/event should be first, and why?
2. What is the exact authority split?
3. What data is mirrored and what is never mirrored?
4. What configuration/feature flag must exist before any code lands?
5. What proof would convince us to turn the canary on in a dev/staging environment?
6. What must still be true before any production shadow canary?

## Candidate Targets To Compare

Compare at least these candidates:

### A. `LeadSignal` mirror

Pros:

- P3 has real row shape and large dev volume.
- P4 synthetic lifecycle is already shaped around lead signals.
- Useful analytics/parity metrics exist.

Risks:

- May live in analytics DB / bulk ingest paths rather than ordinary Rails model callbacks.
- Need confirm where `updated_at` and lifecycle events are stable.
- Contains lead-adjacent sensitive fields, so allowlist must be strict.

### B. `OutboxEvent` mirror

Pros:

- Naturally event-shaped.
- Interesting for audit/dispatch health.

Risks:

- Chosen dev DB had 0 rows in P3.
- Payload can be sensitive; must not blindly mirror raw payload.
- Could duplicate an existing outbox responsibility rather than add useful side evidence.

### C. Availability / scheduling side model

Pros:

- Directly aligned with business-ledger direction.
- Strong explanatory/audit value.

Risks:

- Larger domain decision; risks widening beyond the first canary.
- May belong in home-lab Spark-shaped availability first, not SparkCRM.

### D. No SparkCRM code yet: canary-readiness only

Pros:

- Preserves safety if live write path is ambiguous.
- Lets us design config, rollback, observability and PII guard first.

Risks:

- Slower path to live business signal.

The packet must pick one recommendation and name the next implementation card.

## Required Design Constraints

- Disabled by default.
- Single model / single store / single environment first.
- Store names use underscores, not dots.
- Mirror values are allowlisted and sanitized.
- Mirror write is post-commit and soft-fail.
- TBackend downtime cannot break Spark writes.
- Side-evidence never becomes source of truth.
- No raw DID/UPI/request_id/trace_id/phone/email/name/address/full payload.
- Logs/receipts must make mirror failures observable without leaking payloads.
- Canary must have a one-command or one-flag rollback.

## Acceptance

- [ ] Readiness packet created under `runtime/acts-as-tbackend/docs/` or `lab-docs/lang/`.
- [ ] Packet cites P3/P4 evidence and distinguishes batch proof vs lifecycle proof.
- [ ] At least 3 candidate targets compared, with one recommended.
- [ ] Exact first canary boundary named:
  - model/event;
  - store name;
  - key/id scheme;
  - valid_time/transaction_time stance;
  - mirrored field allowlist;
  - failure behavior;
  - config/feature flag;
  - observability/readback.
- [ ] Explicit "not production authority" boundary included.
- [ ] Explicit PII/payload exclusion included.
- [ ] Exact next implementation card named.
- [ ] No SparkCRM code changes.
- [ ] No daemon / connector source changes unless a hard blocker is found; if found, stop and document.
- [ ] `git diff --check` clean.

## Deliverables

- Readiness packet, suggested path:
  - `runtime/acts-as-tbackend/docs/spark-shadow-canary-readiness.md`
- Closing report in this card with:
  - recommendation;
  - rejected candidates;
  - next implementation card ID;
  - exact remaining blockers, if any.

## Closing Report

**CLOSED 2026-07-01.** Readiness packet: `runtime/acts-as-tbackend/docs/spark-shadow-canary-readiness.md`.

```text
Recommendation: A — a bounded, explicit, sampled LeadSignal shadow mirror in the ingestor, dev-first,
disabled by default, observe-only.

Load-bearing finding (drove the recommendation): LeadSignal is written via LeadSignal.insert_all
(BulkLeadSignalIngestor) — insert_all BYPASSES ActiveRecord callbacks, so the P4 after_commit macro would
silently miss every real lead signal. The canary must use an EXPLICIT Mirror.mirror! on the ingestor's
inserted_rows (the extension already supports app-owned explicit mirroring), not the macro.

First canary boundary (full spec in the packet):
- model/event: LeadSignal, on ingest (inserted_rows post-insert_all)
- trigger: explicit Mirror.mirror! per row (NOT the macro) + a sample gate (id % SAMPLE_MOD) — bounded slice
- store: spark_lead_signals (underscore); key spark_lead_signals:<id>; id ...:ingest:<updated_at_us>
- valid_time = signal_at; transaction_time = server-stamped
- version stamp: P6 must provide updated_at_us explicitly. Current Spark insert_all returning does not include
  updated_at; either add it to returning or build a DTO from inserted payload/result using the same now value.
- allowlist = P3 sanitized set; NEVER did/upi/request_id/trace_id/full data/PII
- failure: post-commit soft-fail (connector soft status); never blocks the Spark write; daemon-down = no-op
- config: disabled by default — ActsAsTbackend.enabled? (ENV TBACKEND_ENABLED off) + canary flag
  (TBACKEND_CANARY_LEADSIGNAL / System::AppSetting) + sample-mod; one-flag rollback
- observability: health reporter (get_outbox_health style) + parity readback (TBackend agg vs LeadSignal AR)

Rejected candidates:
- OutboxEvent — 0 rows in the dev DB (unprovable in dev today); per-row create IS macro-compatible → revisit
  on a populated staging.
- Availability/scheduling — already covered by the home-lab spark-availability-ledger-lab shadow reference;
  widens scope.
- "no code" — this card is that readiness step; the packet + next card are its output.

Explicit boundaries in the packet: SparkCRM stays source of truth; TBackend side-evidence only; NOT
production authority; structural PII/payload exclusion.

Next implementation card: LAB-TBACKEND-SPARK-LEADSIGNAL-SHADOW-CANARY-P6 (smallest slice — sampled
inserted_rows via explicit soft hook behind the triple guard + health/parity readback + one-flag rollback;
SparkCRM code changes begin there).

Remaining blockers before a PRODUCTION shadow canary (out of scope here): staging soak on real traffic;
connector token/auth wired to a real (non-open-loopback) daemon; durable/recoverable daemon + backup-restore
runbook; network/loopback security gate.

Verified: git diff --check clean; no SparkCRM code changes; no daemon/connector source changes.
Curator addendum: live Spark `insert_all returning:` currently omits `updated_at`, so P6 must carry an explicit
version stamp instead of letting Mirror fall back to wall-clock.
```

## Non-Goals

- Implement SparkCRM integration.
- Modify SparkCRM models/services.
- Deploy or run a remote TBackend daemon.
- Turn on a production canary.
- Add background jobs or async outbox workers.
- Add new TBackend analytics APIs.

## Expected Next Cards

Depending on the readiness decision:

- `LAB-TBACKEND-SPARK-LEADSIGNAL-SHADOW-CANARY-P6`
- `LAB-TBACKEND-SPARK-OUTBOX-SHADOW-CANARY-P6`
- `LAB-TBACKEND-SPARK-SHADOW-CONFIG-AND-OBSERVABILITY-P6`

Prefer the smallest implementation card that can prove one real Spark path in dev/staging without making TBackend authoritative.
