# Card: LAB-RESULT-ENVELOPE-P2
**Category:** governance  
**Track:** lab-result-envelope-third-domain-kind-discriminant-pressure-v0  
**Status:** CLOSED — PROVED  
**Gate result:** 50/50 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / GOVERNANCE / LAB-ONLY

---

## Goal

Test whether the `kind`-discriminant result-envelope pattern generalises beyond
HTTP/Rack and Sidekiq by proving a third non-HTTP domain pressure fixture. Reclassify
P1 findings and decide whether PROP-044 should open.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-RESULT-ENVELOPE-P1 | ✅ DONE — taxonomy baseline |
| LAB-VM-MAP-P1 (48/48) | ✅ DONE — map_get VM runtime unblocked |
| LAB-RACK-P14 (60/60) | ✅ DONE — ContractResult 6-kind reference |
| LAB-SIDEKIQ-P5 (48/48) | ✅ DONE — JobReceipt + RetryEnvelope reference |
| LAB-STDLIB-NET-P9 (55/55) | ✅ DONE — HttpResult + DomainResponseMapper reference |
| PROP-043-P5 (55/55) | ✅ DONE — Map[String,String] production surface |

---

## Domain Choice: Form Validation

Selected over: file import, payment authorization, ETL row result.

**Reason:** Smallest domain clearly orthogonal to both HTTP and job semantics.
No HTTP status codes. No retry budget. No job identity. Natural 4-kind space.
Natural denial-as-data path (capability denied = `"unauthorized"` in form context).

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture (7 contracts) | `fixtures/validation_envelope/validation_envelope.ig` | ✅ DONE |
| Proof runner | `proofs/verify_lab_result_envelope_p2.rb` | ✅ DONE |
| Governance doc | `lab-docs/governance/lab-result-envelope-third-domain-kind-discriminant-pressure-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-RESULT-ENVELOPE-P2.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Third-Domain Envelope: `ValidationResult`

```
ValidationResult {
  field:    String               — which field failed; "" if not applicable
  kind:     String               — "valid" | "invalid" | "unauthorized" | "system_error"
  message:  String               — human-readable outcome
  metadata: Map[String, String]  — rule, expected, field_name, etc.
}
```

**No HTTP status codes. No retry budget. No job fields.**

---

## Proof Sections (50/50)

```
VENV-COMPILE  (4/4)  — fixture compiles, 7 contracts, SIR, no type_errors
VENV-TYPES    (5/5)  — type env: ValidationResult fields, Option[String] map chain
VENV-KINDS    (6/6)  — all 4 kind values (valid/invalid/unauthorized/system_error)
VENV-DENIED   (4/4)  — denial-as-data in non-HTTP form domain
VENV-MAP      (5/5)  — Map[String,String] metadata type + VM execution
VENV-VM       (6/6)  — VM record construction + map chain execution
VENV-ROUTE    (5/5)  — routing simulation: 4 kind paths + fail-closed
VENV-COMPARE  (5/5)  — comparison vs HttpResult/ContractResult/JobReceipt
VENV-PROMOTE  (5/5)  — promotion readiness: which patterns generalise
VENV-CLOSED   (5/5)  — closed surface: no HTTP status, no job fields, lab-only
```

---

## P1 Reclassifications

| Pattern | P1 finding | P2 update |
|---------|-----------|-----------|
| `kind`-discriminant | Lab convention (2 domains) | ✅ **Generalises** — 3 domains |
| Denial-as-data | Strongest invariant (6 proofs) | ✅ **Cross-domain** — 7 proofs |
| `Map[String,String]` | Production (PROP-043-P5) | ✅ **Cross-domain** — 3 contexts |
| Three-layer composition | Needs more proof | ✅ **Confirmed** — ValidationMapper |
| `attempt+max_attempts` | PROP-039 aligned | ⚠️ **Domain-local** — not universal |
| `ContractResult` name | Too generic | ✅ **Confirmed** — HTTP-domain-bound |

---

## Key Findings

| Finding | Detail |
|---------|--------|
| Third domain confirmed | ValidationResult: 4-kind, no HTTP/job fields, VM-executed |
| Denial-as-data 7th proof | `unauthorized` routes deterministically to `deny`; no raise |
| Map[String,String] 3rd context | vr.metadata field access → Option[String] (C1 chain) |
| budget-loop is domain-local | Validation has no retry; pattern applies to retry-capable domains only |
| kind-discriminant is general | Same architectural role in 3 independent domains |
| ContractResult confirmed HTTP-domain | 6-kind space does not generalise; name misleads |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| kind-discriminant generalises? | **YES** — 3 independent domains proved |
| denial-as-data cross-domain? | **YES** — 7 proofs; strongest invariant |
| Map[String,String] reusable? | **YES** — 3 contexts; same C1 chain pattern |
| ContractResult rename needed? | **YES** — use `UpstreamCallOutcome` or `HttpDomainResult` |
| Minimal Outcome proposal now? | **NO** — no sum type grammar; convention doc first |
| PROP-044 open now? | **PROPOSAL-AUTHORING ONLY** — 3-domain bar met; grammar gap remains |
| More domain pressure needed? | For PROP-044 authoring: NO. For canon land: optional P3 |
| Runtime/stable authority open? | **NO** — lab-only boundary maintained |

---

## Gap Packet

```
proof:      lab-result-envelope-third-domain-kind-discriminant-pressure / v0
status:     CLOSED — 50/50 PASS
authority:  governance / lab_only
date:       2026-06-09

third_domain:
  ValidationResult 4-kind (valid/invalid/unauthorized/system_error)
  no_http_fields: YES | no_job_fields: YES
  denial_as_data: CONFIRMED (7th proof)
  map_metadata:   CONFIRMED (C1 chain; vm executed)

prop044:
  before: deferred (2 domains; VM gap)
  after:  PROPOSAL-AUTHORING ONLY authorized
  blocker: no sum type grammar

next_authorized:
  immediate:    PROP-044 proposal-authoring only
  optional:     LAB-RESULT-ENVELOPE-P3 (4th domain)
  medium_term:  PROP-044 grammar proposal (sum types)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat.  
No production files changed. No PROP-044 created.  
Proof-local + production TypeChecker read-only + Lab VM read-only.
