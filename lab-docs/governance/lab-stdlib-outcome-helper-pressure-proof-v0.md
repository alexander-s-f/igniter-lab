# Lab Doc: Stdlib Outcome Helper Pressure Proof

**Track:** stdlib-outcome-helper-pressure-and-stringly-kind-reduction-v0
**Card:** LAB-STDLIB-OUTCOME-P1
**Status:** CLOSED — PASS 66/66
**Date:** 2026-06-11
**Route:** LAB PROOF / DESIGN + FIXTURE / NO CANON IMPLEMENTATION

---

## 1. Research Question

Can stdlib outcome helpers reduce stringly `kind` handling across domains without
collapsing domain-specific outcomes or granting runtime authority?

The `LAB-STDLIB-FOUNDATION-P1` surface inventory identified the outcome category as the
biggest blind spot: Canon Ch12 + Covenant P15 define the unknown-state model; lab proofs
flatten it to ad-hoc `kind: String` comparisons; stdlib offers zero combinators.

---

## 2. Evidence Base

This proof draws on the full prior lineage:

| Prior work | Contribution |
|------------|--------------|
| PROP-047-P2 | Six stable cross-domain terms; 10 recovery axes; 10 forbidden-collapse rules |
| LAB-FAILURE-TAXONOMY-P4 | `partial_success` independently proved (54/54) in batch domain |
| LAB-EPISTEMIC-OUTCOME-P2 | KDR convention (kind: String, idempotency_key, metadata) (54/54) |
| LAB-EPISTEMIC-OUTCOME-P4 | ReconciliationReceipt KDR 11-field shape proven in VM (46/46) |
| LAB-OUTCOME-VARIANT-P1..P3 | Variant/match form; KDR is separate from variant arms |
| LANG-STDLIB-ENTRY-CONTRACT-P1 | Entry contract schema; authority/stability axes; demand criteria |
| LAB-STDLIB-FOUNDATION-P1 | Outcome category = OPEN-as-convention; helpers as proof-local demand evidence |

---

## 3. Fixture Inventory (3 domains)

**Fixtures:** `igniter-lab/igniter-view-engine/fixtures/stdlib_outcome/`

| File | Domain | Stable terms | Domain-local kinds |
|------|--------|--------------|--------------------|
| `http_client_outcome.ig` | Network / HTTP | denied, timed_out, unknown_external_state, system_error, query_error | ok, redirect, rate_limited |
| `storage_query_outcome.ig` | Storage / Query | denied, system_error, query_error, unknown_external_state, partial_success | rows, empty, found, created, conflict |
| `epistemic_reconciliation_outcome.ig` | Epistemic / Reconciliation | denied, timed_out, unknown_external_state, system_error, partial_success | confirmed_succeeded, confirmed_failed, still_unknown, reconciliation_denied, reconciliation_error |

All six PROP-047 stable terms appear in at least 2 of the 3 domains (A-04 PASS).
Domain-local outcome kinds appear in exactly their own domain (A-05 PASS).

---

## 4. Proof-Local Helper Model

Helpers defined as Ruby module methods in `OutcomeH` — not implemented in the
igniter compiler, parser, TypeChecker, VM, or any stdlib surface.

| Helper | Type | Verdict |
|--------|------|---------|
| `stdlib.outcome.is_denied(o)` | `(Map[String,String]) -> Bool` | ACCEPT |
| `stdlib.outcome.is_unknown_external_state(o)` | `(Map[String,String]) -> Bool` | ACCEPT |
| `stdlib.outcome.is_timed_out(o)` | `(Map[String,String]) -> Bool` | ACCEPT |
| `stdlib.outcome.is_system_error(o)` | `(Map[String,String]) -> Bool` | ACCEPT |
| `stdlib.outcome.is_query_error(o)` | `(Map[String,String]) -> Bool` | ACCEPT |
| `stdlib.outcome.is_partial_success(o)` | `(Map[String,String]) -> Bool` | ACCEPT |
| `stdlib.outcome.kind(o)` | `(Map[String,String]) -> String` | ACCEPT |
| `stdlib.outcome.is_retryable(o)` | `(Map[String,String]) -> Bool` | CONDITIONAL ACCEPT |
| `stdlib.outcome.route(o, policy)` | — | REJECT |

---

## 5. Section Results

| Section | Label | Checks | Result |
|---------|-------|--------|--------|
| A | Inventory | 6 | PASS 6/6 |
| B | Helper model | 6 | PASS 6/6 |
| C | Positive stable terms | 8 | PASS 8/8 |
| D | Domain-local preservation | 8 | PASS 8/8 |
| E | Retry/routing safety | 7 | PASS 7/7 |
| F | Stringly reduction | 5 | PASS 5/5 |
| G | KDR/variant boundary | 5 | PASS 5/5 |
| H | Authority closed | 8 | PASS 8/8 |
| I | Stdlib entry pressure | 7 | PASS 7/7 |
| J | Decision | 6 | PASS 6/6 |
| **Total** | | **66** | **PASS 66/66** |

---

## 6. Key Findings

### F-1: Helpers reduce stringly duplication without requiring a sealed type

The six `is_<term>` helpers each centralize one string literal at a single
definition site. Callers using `o["kind"] == "system_error"` scattered across
files all become `OutcomeH.is_system_error(o)`. Typos (e.g. `"sytem_error"`) are
caught immediately at definition time rather than silently returning `false`.
(F-01..F-03 PASS)

### F-2: Domain-local kinds are NOT absorbed by generic helpers

Helpers return `false` for any kind string not in their exact stable term.
`found`, `rows`, `empty`, `created`, `redirect`, `still_unknown`,
`confirmed_succeeded` — all return `false` from every `is_*` helper (D-01..D-07 PASS).
`kind()` passes any string through unchanged (D-08 PASS). There is no "fallback unknown"
behavior (F-05 PASS).

### F-3: is_retryable boundary is axis-9 only

`is_retryable` correctly handles the PROP-047 FC-rules:
- `denied` → false (deterministic; FC-1)
- `unknown_external_state` → false (reconcile not retry; Covenant P15)
- `system_error` → true
- `timed_out` + `dispatch_started=false` → true (pre-dispatch)
- `timed_out` + `dispatch_started=true` → false (post-dispatch = unknown state path)
- `query_error` → false (malformed input; FC-1)
- domain-local kinds → false (open-world; generic helper cannot know domain semantics)

This helper MUST document its axis-9-only boundary in the entry contract totality field.
Callers with domain-specific retry logic MUST use direct kind comparison. (E-01..E-07 PASS)

### F-4: route() encodes policy — rejected

A `route(outcome, policy)` helper would allow callers to encode a routing policy
as a data parameter — effectively granting the helper runtime scheduling authority.
The helper must not decide what to do with the outcome; only the caller can.
`route()` is rejected: NotImplementedError with authority-policy rationale. (H-05 PASS, B-06 PASS)

### F-5: KDR and variant are separate and coexist

Helpers operate on KDR hashes (`{ "kind" => String, ... }`). Variant arm names
(e.g. `ConfirmedSucceededReal` from LAB-OUTCOME-VARIANT-P1) are NOT stable terms
and never match any `is_*` helper. The two forms serve different purposes:
KDR for boundary interop and proof-local work; variant/match for exhaustiveness
enforcement and typed payloads. (G-01..G-05 PASS)

### F-6: No authority opened

Every helper is a pure total function (or honest-partial for `is_retryable`):
- No side effects (H-01, H-03, H-08)
- No execution of recovery (H-01, H-02)
- No scheduling authority (H-02)
- No capability grant (H-03, H-07)
- No modification of the outcome record (H-04)
- Returns Bool or String — never a new outcome record (H-06)

---

## 7. Entry Contract Sketches

Three representative sketches using LANG-STDLIB-ENTRY-CONTRACT-P1 schema (v0):

### stdlib.outcome.is_denied

```json
{
  "canonical_name":    "stdlib.outcome.is_denied",
  "category":          "outcome",
  "status":            "proof-local",
  "stability": {
    "semantic":        "convention",
    "lowering":        "none",
    "compatibility":   "pre-v1-none"
  },
  "fragment_class":    "core",
  "purity":            "pure",
  "deterministic":     true,
  "totality":          "total",
  "input_signature":   ["Map[String, String]"],
  "output_signature":  "Bool",
  "authority_surface": "none",
  "failure_behavior":  "absent 'kind' key → KeyError raised",
  "proof_lineage":     ["LAB-STDLIB-OUTCOME-P1"]
}
```

### stdlib.outcome.is_retryable

```json
{
  "canonical_name":    "stdlib.outcome.is_retryable",
  "category":          "outcome",
  "status":            "proof-local",
  "stability": {
    "semantic":        "convention",
    "lowering":        "none",
    "compatibility":   "pre-v1-none"
  },
  "fragment_class":    "core",
  "purity":            "pure",
  "deterministic":     true,
  "totality":          "partial: axis-9 stable terms only; domain-local kinds always false",
  "input_signature":   ["Map[String, String]"],
  "output_signature":  "Bool",
  "authority_surface": "none",
  "failure_behavior":  "domain-local kind → false (not an error; open-world)",
  "proof_lineage":     ["LAB-STDLIB-OUTCOME-P1", "PROP-047-P2"]
}
```

### stdlib.outcome.kind

```json
{
  "canonical_name":    "stdlib.outcome.kind",
  "category":          "outcome",
  "status":            "proof-local",
  "stability": {
    "semantic":        "convention",
    "lowering":        "none",
    "compatibility":   "pre-v1-none"
  },
  "fragment_class":    "core",
  "purity":            "pure",
  "deterministic":     true,
  "totality":          "total",
  "input_signature":   ["Map[String, String]"],
  "output_signature":  "String",
  "authority_surface": "none",
  "failure_behavior":  "absent 'kind' key → KeyError raised",
  "proof_lineage":     ["LAB-STDLIB-OUTCOME-P1"]
}
```

---

## 8. Authority Closed

This proof does NOT open:

| Surface | Status |
|---------|--------|
| stdlib implementation | CLOSED |
| parser / typechecker / SemanticIR / assembler | CLOSED |
| VM / runtime | CLOSED |
| Canon outcome type | CLOSED |
| Generic `Outcome[T,E]` sealed type | CLOSED |
| Global `FailureKind` enum | CLOSED |
| Variant enforcement changes | CLOSED |
| Public API / package / distribution | CLOSED |
| OOF diagnostic codes (beyond OOF-KIND1..6) | CLOSED |

---

## 9. Open Questions for P2

1. **Implementation form**: Should the 7 accepted helpers be lowered as:
   (a) pattern-match dispatch in Ruby TC + SemanticIR inline expansion, or
   (b) first-class `stdlib.outcome.*` dispatch table entries (LANG-STDLIB-ENTRY-CONTRACT schema)?
   P2 resolves this.

2. **`is_retryable` boundary documentation**: The axis-9 boundary must appear in the
   entry contract `totality` field and a dedicated documentation section. P2 must ensure
   callers cannot mistake domain-local false-returns for "domain is not retryable."

3. **KDR input type precision**: `Map[String, String]` is the KDR convention
   (LAB-EPISTEMIC-OUTCOME-P2). The `dispatch_started` field in timed_out records is
   a boolean in the proof-local model but would be `"true"/"false"` in a strict
   `Map[String, String]`. P2 must choose: relax to `Map[String, Any]` or stringify
   the boolean and update `is_retryable` semantics accordingly.

4. **`is_partial_success` vs `partial_success` as stable term**: `partial_success` was
   promoted to stable term by PROP-047-P2 with explicit cross-domain evidence
   (LAB-FAILURE-TAXONOMY-P4). The helper should carry a `proof_lineage` reference to
   that card to anchor its promotion.

---

## 10. Next Step

**LAB-STDLIB-OUTCOME-P2** — Implementation Planning

Gates satisfied by this proof:
- 66/66 PASS ✓
- 3-domain inventory ✓
- 7 helpers ACCEPT + 1 CONDITIONAL ACCEPT + 1 REJECT ✓
- Entry contract sketches authored ✓
- Authority boundary fully documented ✓
- 4 open questions for P2 enumerated ✓

P2 scope: choose implementation form, resolve input-type precision, write final
entry contract records in `igniter-lang/docs/spec/stdlib-inventory.json`, plan
proof matrix (≥50 checks targeting compiler + TypeChecker + SIR emission).
