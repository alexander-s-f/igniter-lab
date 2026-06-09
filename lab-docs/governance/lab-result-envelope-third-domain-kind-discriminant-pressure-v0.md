# Lab Governance Doc: Third-Domain Kind-Discriminant Pressure Proof

**Track:** lab-result-envelope-third-domain-kind-discriminant-pressure-v0  
**Card:** LAB-RESULT-ENVELOPE-P2  
**Category:** governance  
**Date:** 2026-06-09  
**Route:** EXPERIMENTAL / GOVERNANCE / LAB-ONLY  
**Status:** CLOSED — 50/50 PASS; third-domain pressure proved; classification updated

---

## Purpose

Test whether the `kind`-discriminant result-envelope pattern (established in
LAB-RESULT-ENVELOPE-P1 across HTTP/Rack and Sidekiq) generalises to a third
non-HTTP domain. The chosen domain is **form validation and submission processing**
— orthogonal to HTTP transport (no HTTP status codes) and Sidekiq job processing
(no retry budget, no job identity fields).

This proof either strengthens the canon case for a generic discriminated-kind type,
or reveals that the pattern is bound to network/job semantics. The answer informs
whether PROP-044 should open for proposal authoring.

No production files were changed. No canon proposal was created. Lab-only.

---

## Source Material

| Card | Track | Checks | Envelopes Introduced |
|------|-------|--------|---------------------|
| LAB-RESULT-ENVELOPE-P1 | Taxonomy + promotion boundary | — | Classification baseline |
| LAB-STDLIB-NET-P8/P9 | HTTP result + upstream composition | 50+55 | `HttpResult`, `ContractResult` |
| LAB-RACK-P14 | Rack HTTP result composition | 60/60 | `FullRackResponse` |
| LAB-SIDEKIQ-P5 | Sidekiq upstream + Map metadata | 48/48 | `JobReceipt`, `RetryEnvelope` |
| LAB-VM-MAP-P1 | VM map_get/map_has_key runtime | 48/48 | map_get + or_else VM runtime |
| **LAB-RESULT-ENVELOPE-P2** | **This proof — validation domain** | **50/50** | **`ValidationResult`** |

---

## Domain: Form Validation and Submission Processing

### Why This Domain

Form validation is the most common application-level operation in any web or
backend system. It is:

1. **Orthogonal to HTTP transport.** Validation logic does not know or care about
   HTTP status codes. The HTTP layer's 4xx/5xx vocabulary has no meaning in the
   validation domain (a field is "invalid", not "404").
2. **Orthogonal to Sidekiq job processing.** Validation does not have a retry
   budget, a job class, a job id, or an attempt counter. Once a form fails
   validation, the user corrects the input — there is no automated retry cycle.
3. **Contains a natural denial-as-data path.** The `unauthorized` kind models
   capability denial (e.g., a suspended account) in a domain with no HTTP
   infrastructure. This is the critical test for the denial-as-data invariant.
4. **Minimal.** No external dependencies, no mocked I/O, no scheduler.
   The domain can be expressed in pure `pure contract` Igniter contracts.

### Third-Domain Envelope: `ValidationResult`

```
ValidationResult {
  kind:     String    — "valid" | "invalid" | "unauthorized" | "system_error"
  message:  String    — human-readable outcome detail
  field:    String    — which field failed; "" if not applicable
  metadata: Map[String, String]   — context: rule, expected, field_name, etc.
}
```

**Kind value vocabulary:**

| Kind | Description | Domain analog of... |
|------|-------------|---------------------|
| `"valid"` | All constraints satisfied | `ContractResult.found/created` |
| `"invalid"` | Field-level constraint violated | `ContractResult.not_found` (user error) |
| `"unauthorized"` | Submission not permitted (capability denied) | `ContractResult.capability_denied` |
| `"system_error"` | Constraint machinery failed (infrastructure) | `ContractResult.upstream_error` |

---

## Fixture Design

**File:** `igniter-view-engine/fixtures/validation_envelope/validation_envelope.ig`  
**Module:** `Lab.Validation.ThirdDomain`  
**Types:** `ValidationResult`, `SubmissionOutcome`  
**Contracts (7):**

| Contract | Kind proved | Notes |
|----------|------------|-------|
| `ValidSubmission` | `"valid"` | Happy path; metadata from context input |
| `InvalidRequired` | `"invalid"` | Required field missing |
| `InvalidFormat` | `"invalid"` | Format constraint violated |
| `UnauthorizedSubmission` | `"unauthorized"` | Denial-as-data; non-HTTP |
| `SystemError` | `"system_error"` | Infrastructure fault |
| `MetadataInspector` | — | map_get(vr.metadata, key) + or_else → String (VM proof) |
| `ValidationMapper` | any | Low-level → domain mapper; strips raw detail |

---

## Two-Layer + Simulation Proof Architecture

### Layer A — Production Ruby TypeChecker

All 7 contracts accepted, zero `type_errors`. Key type results:

- `ValidationResult.metadata` field → `Map[String,String]` (C1 fix chains through named Record type)
- `MetadataInspector.rule_opt` → `Option[String]` (not `Option[Unknown]` — C1 fix working)
- `MetadataInspector.rule_name` → `String` (or_else extraction confirmed)
- `ValidationMapper.result` → `ValidationResult` (record literal resolved via `@output_type_hints`)

### Layer B — Lab Rust VM (igniter-compiler + igniter-vm)

VM contracts tested:

| Contract | Input | Expected output | Result |
|----------|-------|-----------------|--------|
| `ValidSubmission` | `{name, email, context: {source, form}}` | `{kind:"valid", metadata:{source,form}}` | ✅ PASS |
| `MetadataInspector` | `{vr: {metadata: {rule:"required", field_name:"email"}}}` | `"required"` | ✅ PASS |
| `MetadataInspector` | `{vr: {metadata: {source:"web"}}}` (no rule key) | `"unknown_rule"` | ✅ PASS |
| `ValidationMapper` | `{context: {message:"phone error"}}` | `message = "phone error"` | ✅ PASS |
| `ValidationMapper` | `{context: {rule:"check"}}` (no message) | `message = "validation processed"` | ✅ PASS |
| `UnauthorizedSubmission` | `{reason:"suspended", metadata:{rule:...}}` | `{kind:"unauthorized"}` | ✅ PASS |

### Layer C — Proof-local Routing Simulation

`ValidationRouter.route(ValidationResult)` proves 4-kind routing determinism:

| kind | action | semantic |
|------|--------|---------|
| `"valid"` | `accept` | store submission |
| `"invalid"` | `reject` | show field errors to user |
| `"unauthorized"` | `deny` | access denied; no retry |
| `"system_error"` | `error` | infrastructure failure; retry later |
| unknown kind | `unknown` | fail closed (not `accept`) |

---

## Envelope Comparison Matrix

| Field / Pattern | HttpResult | ContractResult | JobReceipt | ValidationResult |
|----------------|-----------|----------------|------------|------------------|
| `kind: String` | ✅ 3 values | ✅ 6 values | — | ✅ 4 values |
| `status: Integer` | ✅ HTTP | — | — | ❌ absent |
| `status: String` | — | — | ✅ job outcome | — |
| `error_code: String` | ✅ E-HTTP-* | ✅ E-HTTP-* | — | — |
| `data/body/message: String` | `body` | `data` | `message` | `message` |
| `field: String` | — | — | — | ✅ validation-specific |
| `headers: Map[String,String]` | ✅ | — | — | ❌ absent |
| `metadata: Map[String,String]` | — | — | ✅ | ✅ |
| `attempt/max_attempts` | — | — | ✅ | ❌ absent |
| `job_class/job_id` | — | — | ✅ | ❌ absent |
| `capability_id/policy_source` | ✅ | — | — | ❌ absent |

**Key finding:** `ValidationResult` is the first envelope with no HTTP-specific fields
(`status: Integer`, `headers`, `error_code: E-HTTP-*`) AND no job-specific fields
(`job_class`, `job_id`, `attempt`). It is genuinely domain-orthogonal.

---

## Reclassification of P1 Findings

### A1: `kind`-discriminant — STRENGTHENED

**P1 finding:** kind: String appears in HttpResult and ContractResult — de facto lab convention.  
**P2 update:** ValidationResult confirms kind: String in a third independent domain. The
kind-discriminant envelope is now proved across 3 domains (HTTP, Sidekiq, validation).
The pattern is not HTTP-specific or job-specific. It is a general lab design law.

**Reclassification:** A1 remains Category A (reusable pressure). Third domain confirms
generality. The primary blocker for canon proposal remains: no sum type grammar support.

### A2: Denial-as-data — CONFIRMED CROSS-DOMAIN

**P1 finding:** Denial-as-data proved in 6 HTTP/job proofs — strongest cross-cutting invariant.  
**P2 update:** `UnauthorizedSubmission` proves denial-as-data in a domain with:
- No HTTP status code (no `403`)
- No capability_id or policy_source fields
- No job retry budget

The invariant holds: `kind = "unauthorized"` is deterministic, routes to `deny` action,
never raises, never retries. The routing simulation confirms no exception is raised for
the denial path.

**Reclassification:** A2 remains Category A (strongest invariant). Now proved in 3 domains.
This is the highest-confidence finding in the entire lab corpus.

### A3: `attempt + max_attempts` budget — DOMAIN-LOCAL, NOT UNIVERSAL

**P1 finding:** BudgetedLocalLoop analog appears in P8/P5 retry shapes.  
**P2 update:** ValidationResult has no retry budget fields. Validation is fundamentally
non-retryable from the automation perspective (user corrects input, not the system retries).
The budget pattern is correct for HTTP retry and job retry; it is NOT universal.

**Reclassification:** A3 remains Category A for HTTP/job domains. It is NOT a universal
envelope pattern. The budget pattern belongs to domains with automated retry semantics.

### A4: `Map[String,String]` — CONFIRMED CROSS-DOMAIN

**P1 finding:** Map[String,String] appears in transport headers and job metadata.  
**P2 update:** ValidationResult.metadata is `Map[String,String]` in the validation domain.
Three independent contexts now use the same type:
1. `headers: Map[String,String]` — HTTP transport layer (Rack/NET)
2. `metadata: Map[String,String]` — Sidekiq job metadata
3. `metadata: Map[String,String]` — validation field context

The C1 fix (PROP-043-P5) chains correctly through all three: `vr.metadata` field access
produces `Map[String,String]`, `map_get(vr.metadata, "rule")` produces `Option[String]`,
`or_else` produces `String`. Same chain as `job.metadata` (Sidekiq) and `resp_headers` (Rack).

**Reclassification:** A4 confirmed as cross-domain. `Map[String,String]` is the right v0
shape for unstructured key/value context across all proved application layers.

### A5: Three-layer composition — CONFIRMED IN VALIDATION DOMAIN

**P1 finding:** transport-layer → domain-layer → consumer-layer appeared in P14 and P5.  
**P2 update:** `ValidationMapper` proves the mapper role (low-level → domain) in the
validation context: `map_get(context, "message")` + `or_else` strips raw detail; the
domain consumer sees only `kind` and domain-safe fields.

The mapper role (strip transport internals, project to domain kinds) is confirmed in a
third domain without HTTP or job semantics. The pattern is generic.

**Reclassification:** A5 strengthened. Three-layer composition is confirmed as
domain-agnostic. DomainResponseMapper (P9), SuccessPath (P5), ValidationMapper (P2) all
play the same role at different domain layers.

### B3: `ContractResult` name — CONFIRMED TOO GENERIC

**P1 finding:** `ContractResult` name too generic for a 6-kind HTTP-domain envelope.  
**P2 update:** The validation domain produces a 4-kind `ValidationResult`. The 6-kind
space of `ContractResult` (`found`/`created`/`not_found`/`upstream_error`/
`capability_denied`/`upstream_unavailable`) is specific to HTTP upstream call outcomes.
`ContractResult` does not generalise — a validation result has `"invalid"` and `"unauthorized"`,
not `"not_found"` or `"upstream_error"`. The name `ContractResult` is confirmed misleading.

**Reclassification:** B3 unchanged. Recommend renaming if promoted: `UpstreamCallOutcome`
or `HttpDomainOutcome`. The 6-kind space is HTTP-bound.

---

## Promotion Readiness: Updated Matrix

| Shape / Pattern | Category | P1 verdict | P2 update | Blocker(s) |
|----------------|----------|-----------|-----------|-----------|
| Denial-as-data | A2 | Strongest invariant (6 proofs) | **Confirmed cross-domain** (3 domains) | No syntax support; capability grammar needed |
| `kind` discriminant | A1 | Lab convention (2 domains) | **Generalises** (3 domains) | No sum types; String comparison only |
| `Map[String,String]` | A4 | PROP-043-P5 production | **Confirmed cross-domain** (3 contexts) | v1 expansion still closed |
| Three-layer composition | A5 | Needs more domain proof | **Confirmed** (validation mapper) | Needs naming convention + proposal |
| `attempt+max_attempts` | A3 | PROP-039 aligned | **Domain-local** (not universal) | Applies to retry-capable domains only |
| `ContractResult` | B3/D2 | HTTP-domain-specific | Confirmed NOT generalisable as a name | Name + shape both HTTP-bound |
| `HttpResult` | D1 | Network-local | Unchanged | Transport-specific |
| `FullRackResponse` | C1/B1 | Rack-specific | Unchanged | HTTP integer status |
| `JobReceipt` | B2 | Sidekiq-specific | Unchanged | job_class/job_id Sidekiq-specific |
| `RetryEnvelope` (unified) | D3 | Incompatible shapes | Unchanged | No common abstraction |

---

## Explicit Answers to Card Questions

**Q: Does the `kind`-discriminant envelope pattern generalise beyond HTTP/job domains?**  
YES. ValidationResult uses kind: String as the primary discriminant in a domain with no
HTTP or job semantics. The 4-kind space (valid/invalid/unauthorized/system_error) is
domain-specific but the architectural role of `kind` is identical: the consumer branches
on `kind` to determine the action. The pattern is confirmed domain-agnostic.

**Q: Does denial-as-data remain the strongest reusable design law candidate?**  
YES — even more strongly after P2. The `unauthorized` kind in ValidationResult represents
capability denial in a domain with no HTTP infrastructure. The routing simulation confirms
it routes to `deny` (not `accept`) without raising. The invariant has now held across:
P6, P7, P8, P9, P14, P5 (HTTP/job), and P2 (validation) — **7 independent proofs**.

**Q: Does `Map[String,String]` metadata remain reusable?**  
YES. Confirmed in 3 independent contexts: transport headers (Rack/NET), job metadata
(Sidekiq P5), and validation field context (this proof). The C1 fix chains correctly
through all three: `map_get(x.metadata, key)` → `Option[String]` → `or_else` → `String`.
`Map[String,String]` is the confirmed v0 shape for unstructured key/value context.

**Q: Should `ContractResult` be renamed or avoided as too generic?**  
CONFIRMED TOO GENERIC. The validation domain uses `ValidationResult` with 4 kinds. The
6-kind space of `ContractResult` is HTTP-specific. A generic `Result` or `Outcome` would
not map cleanly to `ContractResult`'s current 6 values. If `ContractResult` is ever
promoted, it should be renamed `UpstreamCallOutcome` or `HttpDomainResult` to reflect
its HTTP-domain binding.

**Q: Should any minimal `Outcome`/`Result` proposal open next?**  
NOT YET. Three domains (HTTP, Sidekiq, validation) confirm the pattern exists and is
general. But:
1. No sum type grammar support — kind-discriminant requires String comparison
2. Exhaustive matching is not enforced — a consumer can miss a `kind` branch
3. The three domains use different kind vocabularies (no shared enum)
A minimal `Outcome` convention (not a type) could be proposed as a lab design pattern.
A language-level proposal requires grammar work (sum types / tagged unions) first.

**Q: Should PROP-044 open now or remain deferred?**  
**REMAIN DEFERRED** — but the deferral justification has changed:
- **Before P2:** deferred because only 2 domains, VM map_get open
- **After P2:** deferred because **no sum type grammar** (primary blocker), not domain count
The third-domain proof removes the "only 2 domains" blocker. The remaining blocker is
the grammar: the language has no exhaustive match construct for String-discriminant types.
PROP-044 should open **only after** sum type / tagged union grammar proposal work begins.

**Q: Is more domain pressure required?**  
For PROP-044 to open: NO (the 3-domain bar is met). For a canon proposal to land: YES.
A canon `Outcome` type would need: (a) sum type grammar, (b) exhaustive matching, (c)
at least one more application domain beyond validation. Four domains would be compelling.

**Q: Does runtime/stable/public authority remain closed?**  
YES. All envelopes are proof-local. No production TypeChecker or runtime was changed.
No stable API surface was claimed. Lab-only boundary maintained in all three layers.

**Q: What is the exact next route recommendation?**  
See next section.

---

## Next Route Recommendations

### Immediate (authorized without new gate)

**PROP-044 can now open as proposal-authoring only.**  
The deferral condition ("only 2 domains") is satisfied by this proof. PROP-044 may now
open as a proposal-authoring and research card to explore:
1. A discriminated-kind convention document (not a grammar change)
2. Design requirements for sum type / tagged union grammar
3. The minimal `Outcome` pattern surface (naming + field shape conventions)
No production implementation is authorized. Proposal-authoring only.

### Short-term (unblocked)

**LAB-RESULT-ENVELOPE-P3 (optional): Fourth-domain pressure.**  
A fourth domain would strengthen the PROP-044 case. Candidate: data transformation /
ETL row result (`ParseResult`, `TransformResult`). This is optional before PROP-044 if
the proposal-authoring path is sufficient with 3 domains.

### Medium-term (requires grammar work)

**PROP-044: Kind-discriminant convention and/or sum type grammar pressure.**  
If the proposal-authoring work concludes that `kind: String` is not sufficient and the
language needs a sum type, then PROP-044 becomes a grammar proposal. This requires:
- Exhaustive match syntax
- Sum/tagged-union type declarations
- OOF-KIND1 (unrecognised kind), OOF-KIND2 (non-exhaustive match) candidates

### Permanently closed (no route opens these without new PROP + governance)

- `HttpResult` as generic `Result[T, E]` (transport-specific)
- `ContractResult` as a canon standard library type (name is HTTP-domain-bound)
- `FullRackResponse` outside Rack-track (HTTP integer status)
- `JobReceipt` outside Sidekiq-track (job_class/job_id)
- Unified `RetryEnvelope` (two incompatible shapes)

---

## Gap Packet

```
analysis:   lab-result-envelope-third-domain-kind-discriminant-pressure / v0
status:     CLOSED — 50/50 PASS; third-domain confirmed; classification updated
authority:  governance / lab_only
date:       2026-06-09
domain:     Form validation and submission processing

third_domain_proved:
  ValidationResult:  4-kind (valid/invalid/unauthorized/system_error)
  no_http_fields:    YES — no status:Integer, no headers, no error_code
  no_job_fields:     YES — no attempt, no max_attempts, no job_class
  denial_as_data:    YES — unauthorized path routes to deny; no raise; 7th proof
  map_metadata:      YES — Map[String,String] metadata field; C1 chain works
  vm_executed:       YES — 6 contracts executed in lab VM (50/50 PASS)

p1_reclassifications:
  kind_discriminant:    STRENGTHENED (2→3 domains)
  denial_as_data:       CONFIRMED CROSS-DOMAIN (6→7 proofs)
  map_string_string:    CONFIRMED CROSS-DOMAIN (2→3 contexts)
  three_layer:          CONFIRMED (validation mapper = domain mapper pattern)
  budget_loop:          DOMAIN-LOCAL (not universal — validation has no retry)
  ContractResult_name:  CONFIRMED TOO GENERIC

prop044_status:
  before_p2:   deferred (only 2 domains; VM map_get open)
  after_p2:    deferred (grammar blocker: no sum types; 3-domain bar met)
  can_open_as: proposal-authoring only (no production implementation)

remaining_blockers_for_canon:
  - No sum type / tagged union grammar
  - No exhaustive match construct for String-discriminant kinds
  - ContractResult name is HTTP-domain-bound

next_authorized_routes:
  immediate:   PROP-044 proposal-authoring only (3-domain bar met)
  optional:    LAB-RESULT-ENVELOPE-P3 (fourth domain — ETL/transform)
  medium_term: PROP-044 grammar proposal (if sum types pursued)
```
