# Lab Doc: lab-sidekiq-upstream-http-result-retry-composition-proof-v0

**Card:** LAB-SIDEKIQ-P5  
**Date:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY  
**Status:** PROVED — 48/48 PASS

---

## Goal

Prove a Sidekiq-shaped job composition that:
- Consumes typed `HttpResult` / `ContractResult` envelopes
- Applies retry policy as explicit data (BudgetedLocalLoop analog)
- Returns a typed `JobReceipt` or `RetryEnvelope` with `Map[String,String]` metadata

---

## Architecture

Two-layer proof (same pattern as PROP-043-P5):

**Layer A — Production Ruby TypeChecker** (`IgniterLang::TypeChecker`):
- Proves type shapes and Map[String,String] inference end-to-end
- Proves record literal resolution to named types via `@output_type_hints`
- Proves field arithmetic (`next_attempt = job.attempt + 1 → Integer`)
- Proves `map_get(job.metadata, key) → Option[String]` via named Record field access (C1 fix)
- Proves `or_else(Option[String], default) → String`

**Layer B — Proof-local simulation** (`UpstreamCompositionP5`):
- Behavioral branching: success / denial / retry / exhaustion
- BudgetedLocalLoop analog: attempt counter, budget check, retry dispatch
- Metadata passthrough and `map_get` + `or_else` behavioral semantics
- No scheduler, no blocking-wait, no background-process, no socket-primitive

---

## Fixture

**Path:** `igniter-view-engine/fixtures/sidekiq_core/upstream_http_result_composition.ig`

### Types declared

| Type | Key fields | Notes |
|------|-----------|-------|
| `HttpResult` | `body, error_code, kind, status` | From LAB-STDLIB-NET-P8 |
| `ContractResult` | `data, error_code, kind, message` | From LAB-STDLIB-NET-P9 (6-kind discriminant) |
| `JobInput` | `attempt, job_class, job_id, max_attempts, metadata: Map[String,String], payload` | P5 structured input |
| `JobReceipt` | `attempt, job_class, job_id, max_attempts, message, metadata: Map[String,String], status` | P5 extension of P4 |
| `RetryEnvelope` | `attempt, job_class, job_id, max_attempts, metadata: Map[String,String], next_attempt, reason` | New in P5 |

### Contracts proved

| Contract | Branch | Output type |
|----------|--------|-------------|
| `MetadataReader` | map_get + or_else chain | `queue: String` |
| `SuccessPath` | found/created | `JobReceipt` (status="ok") |
| `DeniedPath` | capability_denied | `JobReceipt` (status="non_retryable") |
| `RetryablePath` | upstream_error, budget not exhausted | `RetryEnvelope` (next_attempt=attempt+1) |
| `ExhaustedPath` | upstream_error, budget exhausted | `JobReceipt` (status="upstream_unavailable") |

---

## Key Findings

### Map[String,String] metadata end-to-end

The PROP-043-P5 C1 fix (`classifier.rb` + `typechecker.rb`) preserves `Map[String,String]` params
in `@type_shapes` for user-declared Record fields. This enables the full chain:

```
@type_shapes["JobInput"]["metadata"] = Map[String,String]   (C1 fix)
job.metadata                          → Map[String,String]  (field access)
map_get(job.metadata, "worker")       → Option[String]      (infer_map_get, not Option[Unknown])
or_else(Option[String], "default")    → String              (infer_or_else extracts V from params[0])
```

Without C1: `map_get(job.metadata, key) → Option[Unknown]` (params stripped).
After C1: `map_get(job.metadata, key) → Option[String]` (params preserved). ✅

### Record literal resolution to named types

`infer_record_literal` uses `@output_type_hints` (pre-scanned from output declarations)
to resolve `{ field: value, ... }` literals to named Record types:

```igniter
compute receipt = { attempt: job.attempt, ..., metadata: job.metadata, status: "ok" }
output receipt: JobReceipt
```

`@output_type_hints["receipt"] = type_ir("JobReceipt")` → literal resolves to `JobReceipt`.
All fields validated: type_name compatibility checked per field (Map == Map ✅, Integer == Integer ✅, String == String ✅).

### Field arithmetic: `next_attempt = job.attempt + 1`

`infer_binary` handles `job.attempt` (field_access → Integer) `+` `1` (literal → Integer):
```ruby
when "+" => ["stdlib.integer.add", type_ir("Integer")]
```
Result: `next_attempt` resolved type = `Integer`. ✅
`RetryEnvelope.next_attempt` field expectation = `Integer`. ✅

### Retry policy as explicit data

The BudgetedLocalLoop analog applies:
- `SUCCESS_KINDS` (found, created): immediate `JobReceipt(ok)`
- `DENIED_KINDS` (capability_denied, not_found): immediate `JobReceipt(non_retryable)` — deterministic, never retried
- `RETRY_KINDS` (upstream_error): `RetryEnvelope` if `attempt < max_attempts`, else `JobReceipt(upstream_unavailable)`

Capability denial flows through as data. Transport is never called for denied requests (P8/P9 pattern).

### `upstream_unavailable` is the correct exhausted-budget status

Proved in:
- Layer A: `ExhaustedPath` contract accepted with `status="upstream_unavailable"` in record literal
- Layer B: `single_attempt(job_at_max_attempts, upstream_error)` → `JobReceipt(upstream_unavailable)`

Consistent with P9's finding: `upstream_unavailable` is only reachable via `call_with_retry` (budget exhaustion), not via `call` (Rack path).

### Metadata passthrough (object identity)

In Layer B simulation: `job[:metadata]` is passed by reference to `receipt[:metadata]`.
`sim_success[:metadata].equal?(SIM_JOB_BASE[:metadata])` → `true` (same object). ✅
This proves metadata is not copied or transformed — it passes through unchanged.

---

## Proof Sections (48 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| SJOB5-TYPES | 5 | All 5 named types in type_env; Map field params on JobInput/JobReceipt/RetryEnvelope |
| SJOB5-MAP | 6 | map_get → Option[String]; or_else → String; two map_get calls; C1 fix both paths |
| SJOB5-SUCCESS | 4 | No errors; receipt=JobReceipt; queue=String via metadata; accepted |
| SJOB5-DENIED | 3 | No errors; receipt=JobReceipt; accepted |
| SJOB5-RETRY | 4 | No errors; next_attempt=Integer; envelope=RetryEnvelope; accepted |
| SJOB5-EXHAUSTED | 3 | No errors; receipt=JobReceipt; accepted |
| SJOB5-SIM | 8 | success/denied/not_found/retry/exhausted; attempt counter; metadata passthrough; lookup |
| SJOB5-REG | 4 | All 5 contracts accepted; zero type_errors; or_else not regressed; field arithmetic not regressed |
| SJOB5-CLOSED | 5 | No upstream-store / blocking-wait / background-process / socket / compat claim |
| SJOB5-GAP | 6 | Map metadata proved; all 4 paths; denial non-retryable; next_attempt Integer; no scheduler; lab-only |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Does typed JobReceipt carry Map-shaped metadata end-to-end? | YES — type_env + sym_type + zero type_errors all confirm Map[String,String] metadata |
| Is metadata preserved through all 4 paths? | YES — all 4 contracts accepted; SJOB5-GAP-2 confirms |
| Does retry budget apply to upstream_error but NOT capability_denied? | YES — denied → non_retryable immediately; upstream_error → RetryEnvelope (within budget) |
| Is `next_attempt = attempt + 1` correctly typed as Integer? | YES — `infer_binary`: Integer + Integer → Integer via stdlib.integer.add |
| Is the proof-local simulation the only execution model? | YES — no scheduler, no blocking-wait, no background-process; SJOB5-CLOSED confirms |
| What is the authority boundary? | LAB-ONLY — no canon claim, no public API, no Sidekiq compat claim, no finalized surface |
| Is `upstream_unavailable` correct for budget exhaustion? | YES — matches P9 finding: only reachable via retry budget path |
| Map[String,String] params preserved through @type_shapes (C1 fix)? | YES — SJOB5-MAP-3/6: params[0] = "String" (not Unknown) |

---

## Authority Boundary

**Closed surfaces (not touched):**
- `igniter-lang` canon (no changes to production compiler)
- Real network / sockets / HTTP libraries
- Sidekiq runtime, Redis, job queue scheduling
- Background-process / service-loop / blocking-wait
- Any public or finalized API surface

**Lab-only scope:**
- `UpstreamCompositionP5` is proof-local (not a production module)
- Fixture types are lab-local (not merged into production type library)
- All "call_contract" semantics are simulation only
- No Sidekiq compatibility claim

---

## Gap Packet

```
proof:      lab-sidekiq-upstream-http-result-retry-composition-proof / v0
status:     PROVED — 48/48 PASS
authority:  lab_only
date:       2026-06-09

map_metadata:
  JobInput.metadata:     PROVED Map[String,String] (C1 fix, SJOB5-TYPES-2)
  JobReceipt.metadata:   PROVED Map[String,String] (P5 extension, SJOB5-TYPES-3)
  RetryEnvelope.metadata: PROVED Map[String,String] (SJOB5-TYPES-4)
  map_get chain:         PROVED Option[String] via named Record field (SJOB5-MAP-2/3)
  or_else chain:         PROVED String (SJOB5-MAP-4)

paths:
  success:   PROVED (SuccessPath accepted, JobReceipt ok)
  denied:    PROVED (DeniedPath accepted, JobReceipt non_retryable)
  retry:     PROVED (RetryablePath accepted, RetryEnvelope, next_attempt Integer)
  exhausted: PROVED (ExhaustedPath accepted, JobReceipt upstream_unavailable)

simulation:
  budgeted_loop: PROVED ([error,error,found] → attempt 3)
  denial_non_retry: PROVED (capability_denied → non_retryable, never retried)
  attempt_counter:  PROVED (next_attempt = attempt + 1)
  metadata_passthrough: PROVED (object identity)

next_authorized_route: none (lab proof complete; production Sidekiq integration is a separate gate)
```
