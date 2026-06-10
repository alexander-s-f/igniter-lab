# lab-outcome-variant-rich-payload-routing-proof-v0

**Track:** lab-outcome-variant-rich-payloads-and-routing-v0  
**Route:** LAB PROOF / DOMAIN VARIANT PRESSURE / NO TAXONOMY AUTHORITY  
**Authority:** lab_only — not canon, not production  
**Proof result:** 56/56 PASS  
**Date:** 2026-06-10  
**Predecessor:** LAB-OUTCOME-VARIANT-P1  

---

## Goal

Extend LAB-OUTCOME-VARIANT-P1 beyond arm-label routing to prove that **payload bindings
flow correctly from match arm fields to contract outputs** through the full Rust lab path.

Three new payload types are exercised that P1 did not bind at runtime:
- `String` field bindings from specific arms (`evidence_kind`, `observed_at`, `request_id`)
- `Integer` field bindings (`attempt`, `budget_remaining`)
- `Map[String,String]` field binding with `map_get` / `or_else` in the arm body

The domain is a focused 5-arm `ReconciliationOutcomeRich` variant designed to maximise
payload variety while keeping the fixture surface small.

---

## Domain: ReconciliationOutcomeRich

```igniter
variant ReconciliationOutcomeRich {
  ConfirmedSucceededReal    { request_id: String, resource: String, evidence_kind: String, observed_at: String }
  ConfirmedSucceededModel   { request_id: String, resource: String, evidence_kind: String, observed_at: String }
  ConfirmedFailed           { request_id: String, idempotency_key: String, attempt: Integer }
  StillUnknown              { request_id: String, attempt: Integer, budget_remaining: Integer }
  ReconciliationError       { request_id: String, detail: String, metadata: Map[String,String] }
}
```

**Real vs Model distinction.** Both `ConfirmedSucceededReal` and `ConfirmedSucceededModel`
carry identical field sets (including `evidence_kind`). No-Upward-Coercion is enforced
at the arm-name layer: `Real` routes to `"accept"`, `Model` routes to `"needs_human_review"`,
regardless of what `evidence_kind` value is passed. A `ConfirmedSucceededModel` record
with `evidence_kind:"real"` still routes to `"needs_human_review"` — the arm name is
the discriminant, not the payload.

---

## Contracts (12 total)

### Build contracts (5, flat inputs → variant record)
| Contract | Output arm | Key payload |
|----------|-----------|-------------|
| `BuildSucceededReal` | `ConfirmedSucceededReal` | evidence_kind + observed_at |
| `BuildSucceededModel` | `ConfirmedSucceededModel` | evidence_kind + observed_at |
| `BuildFailed` | `ConfirmedFailed` | idempotency_key + attempt: Integer |
| `BuildUnknown` | `StillUnknown` | budget_remaining: Integer |
| `BuildError` | `ReconciliationError` | metadata: Map[String,String] |

### Routing and extraction contracts (7)
| Contract | Returns | Binding used |
|----------|---------|-------------|
| `RouteRich` | action: String | arm label (no payload binding) |
| `ExtractEvidenceKind` | evidence: String | `evidence_kind` (Real + Model arms) |
| `ExtractObservedAt` | ts: String | `observed_at` (Real + Model arms) |
| `ExtractRequestId` | rid: String | `request_id` (all 5 arms) |
| `ExtractAttempt` | n_attempt: Integer | `attempt` (Failed + Unknown arms) |
| `ExtractBudget` | budget: Integer | `budget_remaining` (Unknown arm only) |
| `ExtractTraceId` | trace_id: String | `metadata` (Error arm; calls `map_get`) |

**Note on compute node naming.** The VM compiler inserts match arm bindings temporarily
into `compute_node_registers` and removes them after the arm body compiles. If the
compute node name equals a binding name, the cleanup removes the compute node's
register, causing a panic at allocation time (compiler.rs:145). Affected contracts
use distinct compute node names:

| Contract | Binding name | Compute node name |
|----------|-------------|-------------------|
| `ExtractObservedAt` | `observed_at` | `ts` |
| `ExtractRequestId` | `request_id` | `rid` |
| `ExtractAttempt` | `attempt` | `n_attempt` |

This is a VM compiler constraint, not a language design constraint.

---

## Proof Sections (56 checks)

| Section | Checks | What is proved |
|---------|--------|---------------|
| OUTVAR2-COMPILE | 6 | Fixture compiles; 5-arm variant declared; 12 contracts; no OOF diags |
| OUTVAR2-SHAPE | 8 | SIR arm field types: String, Integer, Map; exhaustive/has_wildcard |
| OUTVAR2-BIND | 8 | String + Integer payload bindings flow from match arm to output |
| OUTVAR2-ROUTE | 6 | Arm-label routing correct for all 5 arms; 5 distinct actions |
| OUTVAR2-MAP | 5 | Map[String,String] binding + map_get + or_else default |
| OUTVAR2-BUDGET | 5 | Integer budget_remaining / attempt round-trip (including zero) |
| OUTVAR2-NOUC | 5 | No-Upward-Coercion: Real ≠ Model routing; payload-neutral arm enforcement |
| OUTVAR2-REG | 6 | P1 (11-arm), PROP-044-P9 (reserved fields), variant_match regressions green |
| OUTVAR2-CLOSED | 7 | No OP_MATCH, no Value::Variant, no Outcome[T,E], no taxonomy in code |

---

## Key Findings

### Finding 1: Payload bindings are sufficient for routing-quality extraction

String and Integer fields bound in match arms flow transparently to contract outputs.
The pattern `compute ts: String = match outcome { ArmName { observed_at } => observed_at }` 
works end-to-end: the binding name `observed_at` is a scoped temporary register, the
arm body returns its value, and the compute node output carries the resolved type.

### Finding 2: Map[String,String] binds normally in a match arm

`ReconciliationError { metadata } => or_else(map_get(metadata, "trace_id"), "absent")`
executes correctly. The `metadata` Map field is injected as a scoped register; `map_get`
is called on that register in the arm body; `or_else` handles the missing-key case.
The Map payload survives the full path: `variant_construct` → `OP_PUSH_RECORD` →
match arm binding → function call on the bound value → output.

### Finding 3: No-Upward-Coercion holds with identical field sets

`ConfirmedSucceededReal` and `ConfirmedSucceededModel` carry identical payload fields.
The routing boundary is the `__arm` discriminant, not the payload content.
A `ConfirmedSucceededModel` value with `evidence_kind: "real"` still routes to
`"needs_human_review"` — the payload has no authority over the arm-level routing decision.

### Finding 4: Integer zero is preserved

`budget_remaining: 0` is extracted correctly by `ExtractBudget`, returning `0`.
Path B treats Integer `0` as a valid non-sentinel value — it is not coerced to `nil`
or conflated with a missing field.

---

## Path B Mechanics (unchanged from P1)

```
variant_construct ArmName { f1: v1, ... }
  → OP_PUSH_RECORD { __arm: "ArmName", __variant: "RecordVariantType", f1: v1, ... }

match outcome {
  ArmName { binding1 } => body
  ...
}
  → OP_GET_FIELD("__arm") + OP_EQ("ArmName") + OP_JMP_UNLESS(next)
     scoped_reg = OP_GET_FIELD("binding1")  -- payload extraction
     [compile body using scoped_reg]
  → OP_JMP(end)
  → [next arm chain...]
```

No new opcodes. No `Value::Variant`. `instructions.rs`, `vm.rs`, `value.rs` closed.

---

## Constraints Respected

- No `Value::Variant` added  
- No `OP_MATCH` or `OP_PUSH_VARIANT` added  
- No Ruby canon changes  
- No failure taxonomy authored  
- No sealed `Outcome[T,E]` introduced  
- No production runtime authority claimed  
- No public/stable API claimed  
- `__arm`/`__variant` not promoted to user-visible API  
- No external serialization policy  
- No generic Outcome type  
- No KDR convention fields altered  

---

## What This Proves

- String, Integer, and Map[String,String] payload fields bind in match arms and flow to outputs
- `map_get` / `or_else` compose correctly with a bound Map field from a match arm
- No-Upward-Coercion holds even when arm field sets are identical across arms
- Integer zero is a valid payload value (not a missing-field sentinel)
- Path B is sufficient for richer extraction contracts beyond simple arm-label routing
- P1 (11-arm routing), PROP-044-P9 (reserved fields), variant_match fixtures: all green

## What This Does NOT Prove

- Generic sealed `Outcome[T,E]`
- Failure taxonomy authority
- Production runtime support
- External serialization stability
- Ruby canon parity for payload bindings
- Real reconciliation execution
