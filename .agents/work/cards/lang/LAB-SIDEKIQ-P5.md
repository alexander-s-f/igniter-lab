# Card: LAB-SIDEKIQ-P5
**Category:** lang  
**Track:** lab-sidekiq-upstream-http-result-retry-composition-proof-v0  
**Status:** CLOSED / PROVED — 48/48 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Prove a Sidekiq-shaped job composition that consumes typed upstream
`HttpResult` / `ContractResult` envelopes, applies retry policy as explicit data
(BudgetedLocalLoop analog), and returns a typed `JobReceipt` / retry envelope
with `Map[String,String]` metadata.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-SIDEKIQ-P4 | ✅ DONE (5-field JobReceipt baseline) |
| LAB-RECORD-VM-P3 | ✅ DONE (structural reference) |
| LAB-RECORD-MAP-P1 | ✅ DONE (C1 fix gap identified) |
| PROP-043-P5 | ✅ DONE (C1 fix + Map[String,V] production surface) |
| LAB-MAP-RUST-P1 | ✅ DONE (Rust symmetry reference) |
| LAB-STDLIB-NET-P8 | ✅ DONE (HttpResult / RetryEnvelope shapes) |
| LAB-STDLIB-NET-P9 | ✅ DONE (ContractResult 6-kind discriminant) |

---

## Gate Result

```
SJOB5-TYPES:    5/ 5 PASS
SJOB5-MAP:      6/ 6 PASS
SJOB5-SUCCESS:  4/ 4 PASS
SJOB5-DENIED:   3/ 3 PASS
SJOB5-RETRY:    4/ 4 PASS
SJOB5-EXHAUSTED:3/ 3 PASS
SJOB5-SIM:      8/ 8 PASS
SJOB5-REG:      4/ 4 PASS
SJOB5-CLOSED:   5/ 5 PASS
SJOB5-GAP:      6/ 6 PASS

Total: 48/48 PASS
```

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/sidekiq_core/upstream_http_result_composition.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_sidekiq_p5_upstream_http_result_composition.rb` | DONE — 48/48 PASS |
| Lab doc | `lab-docs/lang/lab-sidekiq-upstream-http-result-retry-composition-proof-v0.md` | DONE |
| Card | `.agents/work/cards/lang/LAB-SIDEKIQ-P5.md` | DONE (this file) |

**Not touched:** igniter-lang canon, igniter-compiler, VM/runtime, any production files.

---

## Proof Sections (48 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| SJOB5-TYPES | 5 | All 5 declared types in type_env; Map field params on JobInput/JobReceipt/RetryEnvelope |
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

## Key Findings

**Map[String,String] metadata flows end-to-end through all 4 job paths:**
- `@type_shapes["JobInput"]["metadata"] = Map[String,String]` (C1 fix)
- `job.metadata` field access → `Map[String,String]` (not `Map` without params)
- `map_get(job.metadata, key) → Option[String]` (not `Option[Unknown]`)
- `or_else(Option[String], default) → String`
- Record literals `{ ..., metadata: job.metadata, ... }` → `JobReceipt` or `RetryEnvelope` typed correctly

**Record literal resolution to named types:**
- `@output_type_hints["receipt"] = type_ir("JobReceipt")` (from output annotation)
- `infer_record_literal` validates all fields against `@type_shapes["JobReceipt"]`
- Map field compatibility: `type_name("Map") == type_name("Map")` ✅

**Field arithmetic for next_attempt:**
- `next_attempt = job.attempt + 1`
- `infer_binary`: field_access(Integer) + literal(Integer) → Integer via stdlib.integer.add
- `RetryEnvelope.next_attempt: Integer` field validated in record literal ✅

**Retry policy as explicit data (BudgetedLocalLoop analog):**
- success (found/created): `JobReceipt(ok)` — immediate
- denial (capability_denied/not_found): `JobReceipt(non_retryable)` — never retried
- retriable (upstream_error), `attempt < max_attempts`: `RetryEnvelope`
- retriable (upstream_error), `attempt >= max_attempts`: `JobReceipt(upstream_unavailable)`

**Two-layer proof architecture:**
- Layer A (TypeChecker): type shapes, Map inference, record resolution, arithmetic
- Layer B (simulation): behavioral branching, attempt counter, metadata passthrough

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Typed JobReceipt carries Map-shaped metadata end-to-end? | YES — SJOB5-TYPES-3 + SJOB5-GAP-1 |
| Metadata Map preserved through all 4 paths? | YES — all 4 contracts accepted; SJOB5-GAP-2 |
| Retry budget applies to upstream_error but NOT capability_denied? | YES — SJOB5-SIM-2/4 + SJOB5-GAP-3 |
| `next_attempt = attempt + 1` typed as Integer? | YES — SJOB5-RETRY-2 + SJOB5-GAP-4 |
| Proof-local simulation only (no scheduler)? | YES — SJOB5-CLOSED + SJOB5-GAP-5 |
| Authority boundary? | LAB-ONLY — SJOB5-GAP-6 |
| `upstream_unavailable` correct for budget exhaustion? | YES — consistent with P9 finding |
| Map params preserved through named Record field access? | YES — SJOB5-MAP-3/6: params[0]="String" |

---

## Authority Constraints (preserved)

- Closed: igniter-lang canon, real network/sockets, job queue runtime, background-process
- Forbidden: socket primitives, scheduling primitives, http-lib requires
- No Sidekiq compatibility claim
- No canon claim
- No public or finalized API claim
- Lab-only: all modules are proof-local (`UpstreamCompositionP5`)
- No production file changes (TypeChecker, classifier, VM untouched)

---

## Gap Packet

```
proof:      lab-sidekiq-upstream-http-result-retry-composition-proof / v0
status:     CLOSED / PROVED — 48/48 PASS
authority:  lab_only
date:       2026-06-09

map_metadata:
  JobInput.metadata:      PROVED Map[String,String] (C1 fix, SJOB5-TYPES-2)
  JobReceipt.metadata:    PROVED Map[String,String] (P5 extension, SJOB5-TYPES-3)
  RetryEnvelope.metadata: PROVED Map[String,String] (SJOB5-TYPES-4)
  map_get chain:          PROVED Option[String] via named Record (SJOB5-MAP-2/3)
  or_else chain:          PROVED String (SJOB5-MAP-4)

paths:
  success:   PROVED (SuccessPath accepted, JobReceipt ok)
  denied:    PROVED (DeniedPath accepted, JobReceipt non_retryable)
  retry:     PROVED (RetryablePath accepted, RetryEnvelope, next_attempt Integer)
  exhausted: PROVED (ExhaustedPath accepted, JobReceipt upstream_unavailable)

simulation:
  budgeted_loop:        PROVED ([error,error,found] → attempt 3)
  denial_non_retry:     PROVED (capability_denied → non_retryable immediately)
  attempt_counter:      PROVED (next_attempt = attempt + 1)
  metadata_passthrough: PROVED (object identity preserved)

next_authorized_route: none
  (Production Sidekiq integration is a separate gate decision beyond lab scope.)
```

---

## Next Recommended Routes

**LAB-SIDEKIQ-P6** (tentative): Wire `JobReceipt` through the Rust lab compiler pipeline —
prove `OP_PUSH_RECORD` for the P5 7-field `JobReceipt` (with Map metadata) at the VM layer.

**LAB-STDLIB-NET-P10** (orthogonal): Wire `ContractResult` through the igniter-lang compiler
pipeline — nominal Record type with discriminated field checking.
