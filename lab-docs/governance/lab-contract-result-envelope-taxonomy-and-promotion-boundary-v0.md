# Lab Governance Doc: Contract Result Envelope Taxonomy and Promotion Boundary

**Track:** lab-contract-result-envelope-taxonomy-and-promotion-boundary-v0  
**Card:** LAB-RESULT-ENVELOPE-P1  
**Category:** governance  
**Date:** 2026-06-09  
**Route:** DESIGN / GOVERNANCE / LAB-ONLY  
**Status:** CLOSED — analysis complete; promotion candidates identified; no promotion authorized

---

## Purpose

Compare the repeated result-envelope patterns proven across the NET (P8, P9), Rack (P14),
and Sidekiq (P5) lab tracks. Classify which pieces are reusable language/stdlib pressure,
which are domain-local application shapes, and which must remain lab-only until further
proof. No envelope is promoted to canon, public API, or stable runtime surface in this doc.
This doc informs future gate decisions; it does not make them.

---

## Source Material

| Card | Track | Checks | Envelopes Introduced |
|------|-------|--------|---------------------|
| LAB-STDLIB-NET-P8 | HTTP error result + retry | 50/50 | `HttpResult`, `RetryEnvelope` (HTTP-level) |
| LAB-STDLIB-NET-P9 | Upstream call contract composition | 55/55 | `ContractResult`, `DomainResponseMapperP9` |
| LAB-RACK-P14 | Rack upstream HTTP result composition | 60/60 | `FullRackResponse` ↔ `ContractResult` mapping |
| LAB-SIDEKIQ-P5 | Sidekiq upstream composition + Map metadata | 48/48 | `JobInput`, `JobReceipt` (P5), `RetryEnvelope` (job-level) |
| LAB-RECORD-VM-P1/P2/P3 | VM record construction + field access + nested | 43+42+49 | Proved runtime execution of above |
| PROP-043-P5 | Map[K,V] production surface (C1 fix) | 55/55 | `Map[String,String]` as stable field type |

---

## Envelope Shapes Catalogue

### HttpResult (transport layer)

**Introduced:** LAB-STDLIB-NET-P8  
**Used by:** P9 (via DomainResponseMapper), P14 (Rack reads ContractResult; HttpResult is upstream)

```
HttpResult {
  kind:          String             — "ok" | "denied" | "error"
  status:        Integer            — HTTP status (0/nil for denied)
  headers:       Map[String,String] — {} for denied
  body:          String             — "" for denied
  error_code:    String             — E-HTTP-* code (nil/empty for ok)
  error_detail:  String             — human-readable (nil/empty for ok)
  capability_id: String
  policy_source: String
}
```

The `kind` field is the primary discriminant. Transport internals (`capability_id`,
`policy_source`, `headers`) are NOT propagated past DomainResponseMapper.

### ContractResult (domain layer)

**Introduced:** LAB-STDLIB-NET-P9  
**Used by:** P14 (Rack maps to FullRackResponse), P5/Sidekiq (job paths branch on kind)

```
ContractResult {
  kind:       String — "found" | "created" | "not_found" | "upstream_error"
                      | "capability_denied" | "upstream_unavailable"
  data:       String — domain payload for found/created; "" otherwise
  error_code: String — E-HTTP-* code; "" for found/created/not_found
  message:    String — human-readable message
}
```

`ContractResult` is the clearest composition boundary in the lab stack: all downstream
consumers (Rack and Sidekiq) branch only on `kind`; no transport internals propagate.

### RetryEnvelope — HTTP-level (P8) vs job-level (P5)

Two incompatible shapes proved under the same name:

**P8 HTTP-level envelope** (wraps the raw HttpResult):
```
RetryEnvelope {
  attempt:      Integer
  max_attempts: Integer
  last_result:  HttpResult   — full transport envelope (embedded)
  should_retry: Bool
  exhausted:    Bool
  retry_reason: String|nil
}
```

**P5 Sidekiq job-level envelope** (typed instruction to re-enqueue):
```
RetryEnvelope {
  attempt:      Integer
  job_class:    String
  job_id:       String
  max_attempts: Integer
  metadata:     Map[String,String]
  next_attempt: Integer            — attempt + 1 (explicit arithmetic)
  reason:       String             — error_code from ContractResult
}
```

The two shapes share the `attempt + max_attempts` budget pattern but diverge significantly.
P8's envelope embeds the transport result; P5's envelope is a pure re-enqueue instruction
with job identity. They should NOT be unified without additional proof.

### JobReceipt — P4 baseline and P5 extension

**P4 baseline (5-field):**
```
JobReceipt {
  job_class:        String
  job_id:           String
  attempt:          Integer
  budget_remaining: Integer
  status:           String
}
```

**P5 extension (7-field, replaces budget_remaining with max_attempts, adds message + metadata):**
```
JobReceipt {
  attempt:      Integer
  job_class:    String
  job_id:       String
  max_attempts: Integer
  message:      String
  metadata:     Map[String,String]
  status:       String   — "ok" | "non_retryable" | "upstream_unavailable"
}
```

Note: P4 used `budget_remaining: Integer` (tracking how much budget is left); P5 uses
`max_attempts: Integer` (the original budget). These carry different semantics. No
normalization was forced — the divergence is intentional domain evolution.

### FullRackResponse (Rack-specific)

**Introduced:** LAB-RACK-P12 (2-field) → P13/P14 (3-field)

```
FullRackResponse {
  status:  Integer          — HTTP status code
  body:    String
  headers: Map[String,String]
}
```

Maps directly from `ContractResult` via the P14 branch taxonomy:
`found→200`, `created→201`, `not_found→404`, `capability_denied→403`,
`upstream_error→502`, `upstream_unavailable→503`.

### Capability Denial Record (policy layer)

**From P8 `HttpCapabilityPolicyP8`:**
```
CapabilityDecision {
  allowed:       Bool
  reason_code:   String   — E-HTTP-* policy code
  reason_detail: String
  capability_id: String
  policy_source: String
  request_id:    String
}
```

Not a consumer-facing envelope — produced by the policy gate and immediately consumed
by `HttpResultBuilder.from_denied` to produce an `HttpResult { kind: "denied" }`.

---

## Repeated Field Analysis

| Field | HttpResult | ContractResult | P8 RetryEnv | P5 RetryEnv | JobReceipt | FullRackResp |
|-------|-----------|----------------|-------------|-------------|------------|--------------|
| `kind` (String discriminant) | ✅ 3 values | ✅ 6 values | — | — | — | — |
| `status` (varies by context) | Integer (HTTP) | — | — | — | String | Integer (HTTP) |
| `error_code` (E-HTTP-*) | ✅ | ✅ | — | `reason` | — | — |
| `data`/`body`/`message` (payload) | `body` | `data` | — | — | `message` | `body` |
| `headers: Map[String,String]` | ✅ | — | — | — | — | ✅ |
| `metadata: Map[String,String]` | — | — | — | ✅ | ✅ | — |
| `attempt: Integer` | — | — | ✅ | ✅ | ✅ | — |
| `max_attempts: Integer` | — | — | ✅ | ✅ | ✅ | — |
| `exhausted: Bool` | — | — | ✅ | — | — | — |
| `next_attempt: Integer` | — | — | — | ✅ | — | — |
| `job_class`/`job_id` | — | — | — | ✅ | ✅ | — |

**Observations:**
- `kind` as a String discriminant is used only in HttpResult and ContractResult — but it's the most impactful pattern
- `error_code` is consistent: always an E-HTTP-* String; always absent on success
- The payload field has three different names across four consumers: `body` (HttpResult, Rack), `data` (ContractResult), `message` (JobReceipt) — same shape, domain-renamed
- `headers` and `metadata` are parallel Map patterns at different boundary layers (transport vs job)
- The `attempt + max_attempts` budget appears in 4 shapes, proving BudgetedLocalLoop is the right PROP-039 analog

---

## Repeated Transition Analysis

### Transition 1: Network outcome → domain result
**Chain:** `HttpResult` → `ContractResult` (via `DomainResponseMapperP9`)  
**Proved in:** P9, consumed by P14 and P5  
**Pattern:** A mapper contract strips transport internals and projects into 6 domain kinds.  
**Stability:** High. DomainResponseMapper is the clearest "transport boundary" proven.

### Transition 2: Domain result → Rack response
**Chain:** `ContractResult` → `FullRackResponse` (via P14 branch taxonomy)  
**Proved in:** P14  
**Pattern:** 6-kind discriminant mapped to HTTP status + body via nested if-else.  
**Stability:** Medium. The status code mapping (403/502/503) is Rack-specific policy.

### Transition 3: Domain result → job receipt or retry envelope
**Chain:** `ContractResult` → `JobReceipt` or `RetryEnvelope` (via P5 branch paths)  
**Proved in:** P5  
**Pattern:** found/created → ok receipt; denied/not_found → non_retryable receipt; upstream_error → retry (budget) or upstream_unavailable receipt.  
**Stability:** Medium. The retry/non-retry branching logic is proven stable; the job identity fields are Sidekiq-specific.

### Transition 4: Capability denial → non-exception branch
**Chain:** Policy decision → `HttpResult { kind: "denied" }` → `ContractResult { kind: "capability_denied" }` → `JobReceipt { status: "non_retryable" }` (or Rack 403)  
**Proved in:** P6/P7/P8 (denial data), P9 (capability_denied ContractResult), P14 (403), P5 (non_retryable)  
**Pattern:** Capability denial flows as explicit data through ALL four consumer layers without exception/raise.  
**Stability:** **Highest of all patterns.** This invariant held across 6 proofs spanning 3 years of lab progression.

### Transition 5: Upstream 5xx → retryable (job) vs immediate 502 (Rack)
**Chain:** `upstream_error` ContractResult → RetryEnvelope (Sidekiq, budget available) OR 502 response (Rack, immediate)  
**Proved in:** P14 (Rack: immediate 502), P5 (Sidekiq: RetryEnvelope or upstream_unavailable)  
**Pattern:** The routing depends on execution model, not on the envelope itself. The same `ContractResult { kind: "upstream_error" }` produces different outcomes depending on whether the caller is synchronous (Rack) or budget-retry (Sidekiq).  
**Stability:** Medium. The pattern is stable; the routing rule (retry only in async contexts) needs more application pressure before promoting.

---

## Classification

### Category A: Reusable Language/Stdlib Pressure

These patterns appear consistently across multiple tracks and are strong candidates for
eventual stdlib surface — but require more application pressure before a proposal.

**A1. `kind`-tagged discriminant envelopes are now a proven pattern.**  
`kind: String` as the primary discriminant appears in both HttpResult (3 values) and
ContractResult (6 values). This is the closest approximation of an algebraic sum type
available in Igniter's current type system. Pressure for: a discriminated-kind convention
in contract design, or a future `Result[T, E]` / `Outcome` type once the type system
supports it. Not ready for syntax promotion — the current shape requires String comparison
and compiler doesn't enforce exhaustive matching.

**A2. Capability denial as data (never exception) — strongest cross-cutting invariant.**  
Proved in P6, P7, P8, P9, P14, P5 — six independent proofs. Every consumer handles denial
as a data branch. No consumer raises an exception for denial. This is not accidental:
it is a deliberate design law emerging from the lab corpus. This is the highest-confidence
candidate for a language-level guarantee in a future capability system.

**A3. `attempt + max_attempts` budget pattern — proven BudgetedLocalLoop analog.**  
Appears in: P8 RetryEnvelope, P5 RetryEnvelope, P5 JobReceipt, P8 RetrySimulator.
All instances follow PROP-039's BudgetedLocalLoop contract: attempt counter, budget, 
exhaustion state. This confirms PROP-039's loop grammar is the right abstraction for
retry — no new loop class is needed. The budget arithmetic (`next_attempt = attempt + 1`)
is typed correctly by the production TypeChecker.

**A4. `Map[String,String]` as the v0 shape for typed key/value collections.**  
`headers: Map[String,String]` (transport layer) and `metadata: Map[String,String]` (job layer)
use the same type with different semantic roles. The PROP-043-P5 C1 fix and the
map_get/or_else chain are proven stable in both contexts. No alternative shape has been 
proposed. `Map[String,String]` is already production surface (PROP-043-P5) and its 
fitness is confirmed by all downstream consumers.

**A5. Three-layer composition boundary.**  
The pattern transport-layer → domain-layer → consumer-layer (HttpResult → ContractResult →
Rack/Sidekiq) appeared independently in both P14 and P5 and was not designed as a
shared pattern. The DomainResponseMapper role (stripping transport internals, projecting
to domain kinds) is a strong generic pattern. More application pressure is needed before
proposing a canonical "mapper contract" shape.

---

### Category B: Domain-Local Lab Patterns

These shapes are well-proved but carry domain-specific fields that should NOT migrate
to a generic stdlib without significant redesign.

**B1. `FullRackResponse` — Rack-specific, should remain so.**  
`status: Integer` (HTTP status code), `body: String`, `headers: Map[String,String]` directly
mirrors the Rack tuple `[status, headers, body]`. The specific field names and the
integer status code space are Rack-specific. The 6-kind → HTTP status mapping is an
application policy (403 for denied, 502/503 for upstream errors). No other consumer uses
integer HTTP status codes. Should stay Rack-local.

**B2. `JobReceipt` — Sidekiq-specific, should remain so.**  
`job_class: String`, `job_id: String` are job identity fields with no analog in HTTP or
Rack contexts. `budget_remaining: Integer` (P4) and `max_attempts: Integer` (P5) are
job retry budget fields. The P5 extension's `metadata: Map[String,String]` and `message: String`
are more generic, but the overall shape is clearly job-system-specific. Should stay
Sidekiq-local until a generic "async task receipt" pattern emerges from more application proof.

**B3. `ContractResult` name — too generic for the shape.**  
The shape is good; the name is misleading. `ContractResult` in the lab refers specifically
to the domain-layer output after mapping from an HTTP upstream call. The 6 kind values
(`found`, `created`, `not_found`, `upstream_error`, `capability_denied`, `upstream_unavailable`)
are all derived from HTTP semantics. A generic `Result` or `Outcome` type would have a
different structure. The current name creates false impressions of being the result of any
Igniter contract — it is more accurately `HttpDomainOutcome` or `UpstreamCallResult`.
Recommend: keep the current name for lab continuity, but treat it as HTTP-domain-local.

**B4. E-HTTP-* error codes — HTTP-specific vocabulary.**  
`E-HTTP-SERVER-ERROR`, `E-HTTP-CLIENT-ERROR`, `E-HTTP-CAP-DENY`, etc. are all HTTP-specific.
The pattern (String error codes in a taxonomy with a prefix) is generic and sound — but the
vocabulary itself should not become the generic error code system. A future stdlib might
define a different prefix for non-HTTP errors.

---

### Category C: Framework-Specific Shapes (never promote)

**C1. `FullRackResponse` HTTP status integer range.**  
The specific integer meanings (200, 201, 404, 403, 502, 503) are RFC 7231 HTTP status codes.
They are correct for Rack but should not appear as literals in a generic contract stdlib.

**C2. `JobInput.job_class` / `job_id` fields.**  
These are Sidekiq job identity fields (`jid`, `class` in Sidekiq's JSON representation).
They must remain Sidekiq-local.

**C3. `DomainResponseMapperP9` specific mapping rules.**  
The specific mapping `200→found`, `201→created`, `404→not_found`, `503→upstream_unavailable`
is an application policy that can vary by domain. The mapper pattern is generic; the
specific mapping is not.

---

### Category D: Closed / Not Ready for Promotion

**D1. `HttpResult` as generic `Result[T, E]`.**  
The three-variant design (`ok`/`denied`/`error`) is HTTP-specific — `denied` has no analog in
non-network contexts. A generic stdlib `Result[T, E]` would be two-variant (success, failure).
Promoting `HttpResult` would conflate network-specific semantics with generic language design.
The right route: let the type system evolve to support sum types first.

**D2. `ContractResult` as reusable library name.**  
Addressed in B3. The 6-kind discriminant is HTTP-domain-specific. Cannot be a generic library
type without becoming `UpstreamHttpDomainResult` — a much narrower name.

**D3. The two `RetryEnvelope` shapes unified into one.**  
P8's HTTP-level `RetryEnvelope` (embeds `last_result: HttpResult`) and P5's job-level
`RetryEnvelope` (is a re-enqueue instruction with `next_attempt`) are incompatible. Unifying
them would require a common abstraction that does not yet exist. Both are useful; neither
should be promoted over the other.

**D4. VM `map_get` bytecode.**  
The most urgent open gap for runtime execution. `HeadersAwareHandler` in P14 is TypeChecker-
complete but VM-blocked. Until `map_get` is proved at the bytecode level, `Map[String,String]`
metadata/headers are only type-level proof, not runtime-complete. This is a prerequisite
for any runtime promotion of map-typed envelope fields.

**D5. Any production runtime authority for these envelopes.**  
All envelopes are proof-local or lab-local modules. None have been run through the production
compiler or production runtime. The VM record construction proofs (P1/P2/P3) used the lab Rust
compiler. This must be explicitly maintained — no runtime authority exists.

---

## Promotion Readiness Matrix

| Shape / Pattern | Category | Canon-ready? | Blocker(s) |
|----------------|----------|-------------|-----------|
| Denial-as-data invariant | A2 | Closest to ready | No syntax support; needs capability type system |
| `kind` discriminant pattern | A1 | Language pressure only | No sum types; String comparison only |
| `attempt + max_attempts` pattern | A3 | PROP-039 aligned; need no new gate | VM retry execution not proved end-to-end |
| `Map[String,String]` shape | A4 | PROP-043-P5 already production | VM map_get bytecode open |
| Three-layer composition | A5 | Design pressure | Needs more domain application proof |
| `ContractResult` (6-kind) | B3 / D2 | No — HTTP-domain-specific | Name + shape both HTTP-bound |
| `HttpResult` | D1 | No — transport-specific | 3-variant; HTTP-specific `denied` |
| `FullRackResponse` | C1 / B1 | No — Rack-specific | HTTP integer status; Rack-only consumer |
| `JobReceipt` | B2 | No — job-system-specific | job_class/job_id Sidekiq-specific |
| `RetryEnvelope` (unified) | D3 | No — two incompatible shapes | P8 vs P5 diverge; no common abstraction |
| VM `map_get` bytecode | D4 | No — open gap | Not yet implemented |

---

## Explicit Answers to Card Questions

**Q: Are `kind`-tagged result envelopes now a repeated pattern?**  
YES. `kind: String` as a discriminant appears in both `HttpResult` and `ContractResult`, and
the pattern of branching on `kind` is repeated identically in P9, P14, and P5 without
coordination between proofs. This is now an established lab convention for discriminated
envelopes. It does not yet have syntax support in the language — but it is the de facto
pattern for "typed union" in the current Igniter lab corpus.

**Q: Should `HttpResult` remain network-local or become generic `Result` pressure?**  
REMAIN NETWORK-LOCAL. The `denied` variant is specific to capability-gated network calls.
A generic stdlib `Result[T, E]` would be two-variant (success/error) and would not map cleanly
to `HttpResult`'s three variants. `HttpResult` carries transport internals (`capability_id`,
`headers`) that have no meaning outside the HTTP context. Keep it HTTP-network-local; design
a separate `Result[T, E]` if/when sum types arrive in the grammar.

**Q: Is `ContractResult` a good reusable name or too generic?**  
TOO GENERIC. In the lab, `ContractResult` specifically means "the domain-layer output of an
HTTP upstream call after stripping transport internals." The 6 kind values are all derived
from HTTP semantics (found/created from HTTP 2xx, not_found from 404, upstream_error from
5xx, capability_denied from policy, upstream_unavailable from retry exhaustion). This name
suggests it is the result of any Igniter contract — it is not. A more accurate name would be
`UpstreamCallOutcome` or `HttpDomainResult`. Recommend: keep current name in lab for
continuity; note the naming issue for any future promotion consideration.

**Q: Does `RackResponse` remain domain-local?**  
YES, and specifically Rack-local. `FullRackResponse { status: Integer, body: String, headers: Map[String,String] }` is the Rack tuple encoded as a named Record. The integer status code space, the specific field names, and the 6-kind→status mapping are all Rack-specific. No other proven consumer uses integer HTTP status codes.

**Q: Does `JobReceipt` remain domain-local?**  
YES, and specifically job-system-local. `job_class: String`, `job_id: String` are Sidekiq
job identity fields. The P5 `status: String` values ("ok", "non_retryable", "upstream_unavailable")
are readable in other contexts, but the overall shape is bound to the job processing model.
The P5 addition of `metadata: Map[String,String]` is more generic, but not enough to promote
the whole shape.

**Q: Is `RetryEnvelope` a reusable retry pattern or Sidekiq-local?**  
SPLIT ANSWER — the name hides two different shapes:
- The `attempt + max_attempts` **budget pattern** (from both P8 and P5) IS reusable and IS already
  aligned with PROP-039's `BudgetedLocalLoop`. This is a strong stdlib pressure finding.
- The specific `RetryEnvelope` **record shapes** are NOT unified. P8's version embeds a full
  `HttpResult`; P5's version is a job re-enqueue instruction with job identity. They should not
  be merged. The budget pattern should be understood through PROP-039, not through either
  specific `RetryEnvelope` shape.

**Q: Should capability denial be modeled as data rather than exception?**  
YES — this is the clearest finding from the entire corpus. Capability denial flows as typed
data through EVERY layer: policy decision → `HttpResult { kind: "denied" }` → `ContractResult { kind: "capability_denied" }` → Rack 403 / Sidekiq `non_retryable`. Not a single consumer raises or catches. The consistency across 6 independent proofs (P6–P9, P14, P5) establishes this as a design law, not just a pattern. Any future capability system should encode this guarantee at the language level.

**Q: Is `Map[String,String]` the right v0 shape for metadata/headers?**  
YES. Used as `headers: Map[String,String]` (network layer) and `metadata: Map[String,String]`
(job layer). The C1 fix (PROP-043-P5) makes map_get/or_else through named Record fields type-safe.
Both use cases are proven stable. The `Map[K,V]` v0 surface (PROP-043-P5) is sufficient for both
roles. The only remaining gap is VM `map_get` bytecode — a runtime gap, not a type-level gap.

**Q: Should any part be proposed toward canon now?**  
NO. The patterns are well-proven at the lab level, but none meet the bar for canon proposal:
1. No sum type support in the grammar — `kind`-discriminant pattern can't be enforced
2. VM `map_get` bytecode is open — Map-typed fields are type-level-only
3. No application pressure beyond these 6 proofs — the HTTP/job domain is the only consumer
4. `ContractResult` name is already wrong for a generic type
5. The two `RetryEnvelope` shapes are unresolved

**Q: Is more application pressure needed before proposal?**  
YES. Specific gaps:
1. A third application domain (not HTTP/Rack or Sidekiq) using the same `kind`-discriminant pattern
2. An end-to-end VM execution proof including `map_get` bytecode
3. A scenario where `ContractResult`-equivalent is produced by a non-HTTP upstream (e.g., a database call or filesystem operation) — to test whether the 6-kind discriminant generalizes

**Q: What is the exact next route recommendation?**  
See next section.

---

## Next Route Recommendations

### Immediate (no gate required)

**LAB-VM-MAP-P1: VM `map_get` bytecode implementation**  
Blocker: `HeadersAwareHandler` in P14 TypeChecker-complete but VM-blocked; PROP-043-P5 map types
have no runtime execution. This is the highest-priority gap for completing the lab evidence chain.
Scope: add `map_get` opcode to `igniter-vm/src/instructions.rs` + `vm.rs` + `compiler.rs`.
Expected proof: existing P14 fixture's `HeadersAwareHandler` executes end-to-end.

### Short-term (after VM map_get closed)

**LAB-RESULT-ENVELOPE-P2: Third-domain pressure (non-HTTP upstream)**  
Design a lab proof where a contract reads from a non-HTTP upstream (file, database stub, or
queue message) and produces a `kind`-tagged result envelope. Goal: test whether the 6-kind
ContractResult discriminant generalizes, or whether `not_found` / `upstream_error` are
intrinsically HTTP-specific. This would either strengthen the canon case for a generic `Outcome`
type, or confirm that `ContractResult` should remain HTTP-local.

### Medium-term (requires grammar work)

**PROP-044 (tentative): Discriminated kind convention or sum type pressure**  
If LAB-RESULT-ENVELOPE-P2 shows the `kind`-discriminant pattern generalizes, this becomes
a proposal for either: (a) a language-level exhaustive matching construct for String-discriminant
envelopes, or (b) early-stage sum type / tagged union grammar. This is NOT authorized and would
require independent research, proposal, and gate.

**PROP-039 follow-on: Retry loop in full VM execution**  
Prove that a BudgetedLocalLoop contract compiles to bytecode and executes correctly with the
attempt counter — closing the gap between the TypeChecker-proved retry pattern and VM execution.
Prerequisite: VM `map_get` bytecode (above).

### Permanently closed (no route opens these without new PROP + governance)

- `HttpResult` as generic `Result[T, E]`
- `ContractResult` as a canon standard library type
- `FullRackResponse` outside Rack-track usage
- `JobReceipt` outside Sidekiq-track usage
- Either specific `RetryEnvelope` shape as a unified stdlib type

---

## Gap Packet

```
analysis:   lab-contract-result-envelope-taxonomy-and-promotion-boundary / v0
status:     CLOSED — analysis complete; no promotions authorized
authority:  governance / lab_only
date:       2026-06-09

patterns_confirmed:
  kind_discriminant:          YES — repeated in HttpResult + ContractResult; lab convention
  denial_as_data:             YES — strongest invariant; 6 proofs; all consumers agree
  budget_loop:                YES — attempt+max_attempts proven in P8+P5; PROP-039 aligned
  map_string_string:          YES — production surface (PROP-043-P5); both network + job layer
  three_layer_composition:    YES — HttpResult→ContractResult→consumer; needs more domain proof

network_local:
  HttpResult:                 STAY NETWORK-LOCAL (3-variant; http-specific denied)
  ContractResult:             HTTP-DOMAIN-LOCAL (name too generic; 6-kind HTTP-bound)
  FullRackResponse:           RACK-LOCAL (HTTP integer status; Rack-only consumer)

job_local:
  JobReceipt:                 SIDEKIQ-LOCAL (job_class/job_id Sidekiq-specific)
  RetryEnvelope (P5 shape):   SIDEKIQ-LOCAL (re-enqueue instruction with job identity)

not_unifiable:
  RetryEnvelope (P8 vs P5):   INCOMPATIBLE (P8 embeds HttpResult; P5 is re-enqueue instruction)

canon_proposal_now:           NO (no sum types; VM map_get open; too few application domains)

blockers:
  - VM map_get bytecode (highest priority)
  - Third non-HTTP application domain proof
  - Grammar sum type support (long-term)

next_authorized_route:
  immediate: LAB-VM-MAP-P1 (VM map_get bytecode)
  short_term: LAB-RESULT-ENVELOPE-P2 (third-domain pressure)
  medium_term: PROP-044 tentative (kind-discriminant convention or sum type pressure)
```
