# Card: LAB-RESULT-ENVELOPE-P1
**Category:** governance  
**Track:** lab-contract-result-envelope-taxonomy-and-promotion-boundary-v0  
**Status:** CLOSED — analysis complete; no promotions authorized  
**Date closed:** 2026-06-09  
**Route:** DESIGN / GOVERNANCE / LAB-ONLY

---

## Goal

Compare the repeated result-envelope patterns proven across NET P8/P9, Rack P14, and
Sidekiq P5. Classify which pieces are reusable language/stdlib pressure, which are
domain-local application shapes, and which must remain lab-only until further proof.
No envelope promoted to canon, public API, or stable runtime surface.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-STDLIB-NET-P8 | ✅ DONE (50/50) — HttpResult, RetryEnvelope (HTTP-level) |
| LAB-STDLIB-NET-P9 | ✅ DONE (55/55) — ContractResult, DomainResponseMapper |
| LAB-RACK-P14 | ✅ DONE (60/60) — ContractResult → FullRackResponse; 6-kind mapping |
| LAB-SIDEKIQ-P5 | ✅ DONE (48/48) — JobInput/JobReceipt/RetryEnvelope (job-level) with Map metadata |
| LAB-RECORD-VM-P1/P2/P3 | ✅ DONE (43+42+49) — VM record construction + field access |
| PROP-043-P5 | ✅ DONE (55/55) — Map[String,String] production surface; C1 fix |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Governance taxonomy doc | `lab-docs/governance/lab-contract-result-envelope-taxonomy-and-promotion-boundary-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-RESULT-ENVELOPE-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Key Findings (Summary)

### Five confirmed reusable patterns (Category A)

| Pattern | Confidence | Notes |
|---------|-----------|-------|
| **Denial-as-data invariant** | Highest | 6 independent proofs; every consumer handles denial as a data branch; no exceptions raised anywhere in the corpus |
| **`kind: String` discriminant envelopes** | High | Used in HttpResult (3 values) and ContractResult (6 values); de facto lab convention for typed unions |
| **`attempt + max_attempts` budget** | High | PROP-039 BudgetedLocalLoop confirmed; appears in P8+P5 RetryEnvelope and P5 JobReceipt |
| **`Map[String,String]` for key/value fields** | High | PROP-043-P5 already production; both `headers` (transport) and `metadata` (job) use same shape |
| **Three-layer composition boundary** | Medium | HttpResult → ContractResult → consumer; appeared independently in both P14 and P5 |

### Shape classifications

| Shape | Classification | Promote now? |
|-------|---------------|-------------|
| `HttpResult` | Network-local | ❌ — 3-variant; `denied` is HTTP-specific |
| `ContractResult` | HTTP-domain-local | ❌ — name too generic; 6-kind HTTP-bound |
| `FullRackResponse` | Rack-specific | ❌ — HTTP integer status; Rack-only consumer |
| `JobReceipt` | Sidekiq-local | ❌ — job_class/job_id Sidekiq-specific |
| `RetryEnvelope` (P8 vs P5) | Incompatible shapes | ❌ — P8 embeds HttpResult; P5 is re-enqueue instruction |
| `attempt + max_attempts` pattern | Reusable pressure | PROP-039 is the right home; no new gate needed |
| `Map[String,String]` shape | Production (PROP-043-P5) | ✅ already production |
| Denial-as-data invariant | Design law | Future capability system gate |

---

## Explicit Decision Record

| Question | Answer |
|----------|--------|
| `kind`-tagged result envelopes a repeated pattern? | **YES** — de facto lab convention; not yet syntax-supported |
| `HttpResult` → generic `Result`? | **NO** — HTTP-specific; `denied` variant has no non-network analog |
| `ContractResult` name good for reuse? | **NO** — too generic; shape is HTTP-domain-specific |
| `RackResponse` remain domain-local? | **YES** — Rack-specific (HTTP integer status) |
| `JobReceipt` remain domain-local? | **YES** — Sidekiq-specific (job_class/job_id) |
| `RetryEnvelope` reusable? | **SPLIT** — budget pattern reusable; shapes incompatible |
| Capability denial as data? | **YES** — design law; 6-proof corpus; strongest finding |
| `Map[String,String]` the right v0 shape? | **YES** — PROP-043-P5 production; stable in both roles |
| Propose anything to canon now? | **NO** — blockers exist (see below) |
| More application pressure needed? | **YES** — only HTTP/job domains so far |
| `ContractResult` better name? | `UpstreamCallOutcome` or `HttpDomainResult` — not renamed here |

---

## Blockers for Canon Promotion

1. **No sum type support in grammar** — `kind`-discriminant pattern can't be exhaustively enforced
2. **VM `map_get` bytecode is open** — Map-typed fields are type-level only (no runtime proof)
3. **Only two application domains** — HTTP + job; a third domain would strengthen generalization
4. **Two incompatible `RetryEnvelope` shapes** — no unified abstraction yet
5. **`ContractResult` name is misleading** — would need renaming for any stdlib proposal

---

## Next Route Recommendations

| Route | Priority | Gate required? |
|-------|---------|----------------|
| **LAB-VM-MAP-P1** — VM `map_get` bytecode | Highest / immediate | No — lab extension |
| **LAB-RESULT-ENVELOPE-P2** — Third-domain pressure (non-HTTP upstream) | Short-term | No — lab extension |
| **PROP-044** (tentative) — Kind-discriminant convention or sum type pressure | Medium-term | Yes — PROP gate required |
| **PROP-039 follow-on** — Retry loop in full VM execution | Medium-term | PROP-039 existing gate |

---

## Authority

- Analysis only — no code changes, no production compiler changes
- No canon proposal authorized
- No public API claim
- No Rack compatibility claim, no Sidekiq compatibility claim
- All envelopes remain lab-only
- `ContractResult` naming issue noted; lab name preserved for continuity

---

## Gap Packet

```
analysis:   lab-contract-result-envelope-taxonomy-and-promotion-boundary / v0
status:     CLOSED — analysis complete
authority:  governance / lab_only
date:       2026-06-09

strongest_finding:    denial-as-data invariant (6-proof corpus; design law candidate)
reusable_patterns:    kind_discriminant, budget_loop, Map[String,String], three-layer composition
stay_local:           HttpResult, ContractResult, FullRackResponse, JobReceipt, RetryEnvelope (shapes)
canon_proposal_now:   NO
primary_blocker:      VM map_get bytecode

next_authorized_route:
  immediate: LAB-VM-MAP-P1 (VM map_get bytecode — closes runtime gap for Map-typed envelopes)
  short_term: LAB-RESULT-ENVELOPE-P2 (non-HTTP domain proof — needed for generalization claim)
```
