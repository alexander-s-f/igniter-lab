# IO Runtime P2 — Storage Read Mocked Executor Plan v0

**Card:** LAB-IGNITER-LANG-IO-RUNTIME-P2  
**Track:** lab-igniter-lang-io-runtime-storage-read-mocked-executor-v0  
**Status:** OPEN — planning doc authored  
**Authority:** mocked executable proof only; no real DB/SQL/ORM  
**Date:** 2026-06-13

---

## Scope

This document answers the six questions posed in LAB-IGNITER-LANG-IO-RUNTIME-P2 and
defines the mocked runtime path for the Storage read executor slice. It builds
directly on:

- LAB-IGNITER-LANG-IO-RUNTIME-P1 (CLOSED 85/85) — route confirmed
- LAB-STORAGE-CAPABILITY-P2 (CLOSED 51/51) — 6-gate sequence + QueryExecutionReceipt
- LAB-EXECUTE-QUERY-P1/P2/P3 (CLOSED 57+73+68) — full mocked query pipeline
- LANG-IO-CAPABILITY-EXECUTOR-P1 (OPEN) — executor interface under definition

**No real DB, SQL, ORM, transactions, or persistence runtime is opened here.**

---

## The Route (Confirmed by P1)

```text
effect contract with IO.StorageCapability
  -> compiled/assembled evidence (fixture compiles in Rust; Ruby TC accepts)
  -> RuntimeMachine-like evaluator sees ESCAPE boundary (effect class)
  -> CapabilityExecutor registry looked up by capability_name
  -> MockCapabilityExecutor.execute(effect_name, capability, inputs)
  -> 6-gate evaluation (G1–G6) → QueryResult
  -> QueryExecutionReceipt returned as typed evidence
```

The mocked executor replaces real substrate access. Real DB execution is never
called. The executor is looked up from a registry keyed by capability class name
(`IO.StorageCapability`).

---

## Q1 — Minimal Fixture Expressing Storage Read as Effect Contract

The minimal fixture structure is already proved in `execute_query_capability.ig`
(LAB-EXECUTE-QUERY-P1). The executor-ready form adds no new grammar — it reuses
the existing `capability`/`effect_binding` experiment-pass surface:

```igniter
effect contract ExecuteQuery {
  capability storage : IO.StorageCapability
  effect read_file using storage
  input  plan : QueryPlan
  compute result = { kind: "denied", count: 0, message: "execution-not-v0", metadata: plan.metadata }
  output result : QueryResult
}
```

Key points:

- `capability storage : IO.StorageCapability` — declares the authority gate.
  The executor registry uses `IO.StorageCapability` as the lookup key.
- `effect read_file using storage` — declares the effect binding. The executor
  receives `effect_name: "read_file"` and the resolved capability object.
- `input plan : QueryPlan` — the full plan is passed through; executor applies
  G1-G6 gates against it.
- The `compute result` stub returns `"denied"` conservatively (no execution in v0).
  The executor's mocked G6 layer produces the real result.
- **Fragment:** ESCAPE (effect contract; capability binding present).
  Stage 2+ STORAGE class required for live VM execution.

The fixture requires NO grammar changes. PROP-035 full Effect Surface (`affects`,
`authority`, `reversibility`, `idempotency`, `receipt`, `failure`, `compensation`)
remains pending. The `capability`/`effect_binding` subset is experiment-pass.

---

## Q2 — Can Existing `QueryExecutionReceipt` Be Reused Unchanged?

**YES.** The 15-field `QueryExecutionReceipt` shape proven in LAB-STORAGE-CAPABILITY-P2
and confirmed across LAB-EXECUTE-QUERY-P1/P2/P3 is unchanged.

```
QueryExecutionReceipt {
  cap_id:            String,   -- capability.capability_id
  plan_kind:         String,   -- plan.kind
  source_table:      String,   -- plan.source.table (G1 input)
  op_requested:      String,   -- "read" (G2 input)
  cap_checked:       Bool,     -- always true when executor runs
  cap_granted:       Bool,     -- false iff denied or query_error
  denial_gate:       String,   -- "G1".."G5" or "" if granted
  deny_reason:       String,   -- from capability.deny_reason or error msg
  plan_limit:        Integer,  -- plan.limit (G4 input)
  row_limit_cap:     Integer,  -- capability.row_limit
  effective_limit:   Integer,  -- min(plan.limit, cap.row_limit)
  row_limit_clamped: Bool,     -- true when G4 clamped
  rows_returned:     Integer,  -- 0 when denied; actual count after G6
  result_kind:       String,   -- "rows" | "empty" | "denied" | "query_error" | "system_error"
  metadata:          Map[String, String]
}
```

**Invariants (all previously proved):**
- `cap_checked: true` in all executor paths
- `cap_granted: false` iff `result_kind` is `"denied"` or `"query_error"`
- `rows_returned: 0` when denied
- `effective_limit = min(plan_limit, row_limit_cap)`

Receipt is **evidence-only**. It does not re-authorize subsequent executions.

---

## Q3 — Which Six Gates Become Executor Gates?

The 6-gate sequence from LAB-STORAGE-CAPABILITY-P1/P2 maps directly to executor
evaluation steps. The executor runs them in order; each gate can short-circuit.

| Gate | Executor Check | Fail Output |
|------|---------------|-------------|
| G1 | `cap.allowed_sources.include?(plan.source.table)` (fail-closed: empty = deny all) | `QueryResult{kind:"denied"}`, `denial_gate:"G1"` |
| G2 | `cap.allowed_ops.include?("read")` | `QueryResult{kind:"denied"}`, `denial_gate:"G2"` |
| G3 | `cap.read_allowed == true` | `QueryResult{kind:"denied"}`, `denial_gate:"G3"` |
| G4 | `plan.limit > cap.row_limit` → clamp | NOT denial; `effective_limit = min(plan.limit, cap.row_limit)`; `row_limit_clamped: true` |
| G5 | `plan.projection.include_all && !cap.allow_include_all` | `QueryResult{kind:"query_error"}`, `denial_gate:"G5"` (NOT "denied") |
| G6 | Mocked execution with effective_limit | `QueryResult{kind:"rows"\|"empty"\|"system_error"}` |

G1/G2/G3 short-circuit: subsequent gates not evaluated on denial.  
G4 is a clamp, not a denial: `cap_granted:true` after clamp.  
G5 is a plan error (`"query_error"`), not a capability denial (`"denied"`).  
G6 is the mocked executor result; no real DB call.

---

## Q4 — Runtime Refusal vs Denial-as-Data

These are two distinct outcomes and must never be conflated.

### Runtime Refusal

A **runtime refusal** occurs before the executor can run. The RuntimeMachine
raises a structured `EvaluateRefusal` (Ch7 §7.3). No `QueryResult` or receipt
is produced. Causes:

| Refusal Code | Trigger |
|---|---|
| `runtime.capability_missing` | Capability passport not injected; effect requires it |
| `runtime.capability_unknown` | Capability class not in executor registry |
| `runtime.effect_name_unknown` | Effect binding name not recognized by executor |
| `runtime.no_idempotency_key` | Effect requires idempotency key; none provided |
| `runtime.authority_missing` | `authority` clause present; no authority token in context |
| `runtime.no_receipt_type` | Effect requires receipt; none configured (Stage 2+) |
| `runtime.unknown_external_state` | Request sent; no confirmation received (Covenant P15) |

Runtime refusals are **fail-closed**. The executor must not execute partial work
before producing a refusal.

### Denial-as-Data

A **denial-as-data** occurs inside the executor after it is found and the
capability is evaluated. The executor runs the gate sequence (G1–G6) and returns
a `QueryResult{kind:"denied"}` as a first-class typed output. A receipt is
produced and records `cap_granted:false` + `denial_gate`.

**Rule:** The consumer branches on `result.kind`. No exception is raised. No
`raise`. This is the 9th proof domain for denial-as-data in the igniter-lang lab.

### Boundary

```text
before executor found    → EvaluateRefusal   (no receipt, no result)
executor found + gates   → QueryResult{kind} (receipt always produced)
```

---

## Q5 — Evidence Required for Replay

The replay/determinism model requires that every mocked IO execution produce
evidence sufficient to reconstruct the outcome without re-executing. The minimum
evidence set:

| Field | Source | Purpose |
|---|---|---|
| `effect_name` | effect binding name (`"read_file"`) | Identifies the operation kind |
| `capability_id` | `capability.capability_id` | Identifies the authority gate used |
| `inputs_hash` | `sha256(canonical(plan))` | Deterministic input identity |
| `idempotency_key` | From effect contract declaration (Stage 2+) | Safe retry detection |
| `denial_gate` | Receipt field | Which gate fired |
| `deny_reason` | Receipt field | Why denied |
| `result_kind` | Receipt field | Final outcome |
| `rows_returned` | Receipt field | Row count (0 for denials) |
| `effective_limit` | Receipt field | Clamp recorded |
| `row_limit_clamped` | Receipt field | Clamp flag |
| `cap_granted` | Receipt field | Authorization outcome |
| `timestamp` | External (not a contract field) | Correlation only; not replay material |

**Key invariant:** `QueryExecutionReceipt` already carries all required evidence
fields for replay. No new fields are required in v0.

For full audit trail, the receipt must be returned as output alongside the
`QueryResult`. The host layer appends the receipt to the run log.

---

## Q6 — What Remains Closed Before Real DB

The following surfaces remain **permanently closed** until a separate
implementation card is authorized:

| Surface | Status |
|---|---|
| Real DB connection | PERMANENTLY CLOSED — no auth path |
| SQL query execution | PERMANENTLY CLOSED — no auth path |
| ORM / ActiveRecord | PERMANENTLY CLOSED |
| Schema migrations | PERMANENTLY CLOSED |
| Transactions | PERMANENTLY CLOSED |
| Persistence runtime | PERMANENTLY CLOSED |
| Write operations | CLOSED in v0 |
| Live VM execution of effect contracts | CLOSED — ESCAPE class; Stage 2+ required |
| Full PROP-035 Effect Surface grammar | CLOSED — PROP-035 not yet authored |
| Public runtime API | CLOSED |
| Production StorageCapability execution | CLOSED |

**Remaining before real DB (beyond P2):**

1. **LANG-IO-CAPABILITY-EXECUTOR-P1** (currently OPEN): Define the final
   `CapabilityExecutor` interface, `CapabilityPassport` shape, `EffectResult`
   envelope, and fail-closed behavior.

2. **PROP-035**: Full Effect Surface grammar (`affects`, `authority`,
   `reversibility`, `idempotency`, `receipt`, `failure`, `compensation`).

3. **Stage 2+ STORAGE fragment class**: Ch4 amendment required for live VM
   execution of effect contracts with capability injection.

4. **Implementation card** (follows P2): Bounded implementation of
   `StorageCapabilityExecutor` against the final executor interface.

---

## Mocked Runtime Path (v0)

The mocked path proved in P2 is:

```ruby
# Step 1: effect contract compiled + fixture accepted (Layer A + B)
# Effect contract declares IO.StorageCapability and read_file binding.

# Step 2: RuntimeMachine-like evaluator sees ESCAPE boundary
# Evaluator identifies effect contract; looks up executor by capability class.

# Step 3: executor lookup (fail-closed)
executor = registry["IO.StorageCapability"]
raise EvaluateRefusal.new("runtime.capability_unknown") if executor.nil?

# Step 4: capability passport resolved
cap = capability_passport["storage"]
raise EvaluateRefusal.new("runtime.capability_missing") if cap.nil?

# Step 5: mocked executor runs gate sequence
result, receipt = executor.execute("read_file", cap, plan)

# Step 6: receipt returned as typed evidence
# result.kind ∈ {"rows","empty","denied","query_error","system_error"}
# receipt.cap_granted == false iff result.kind ∈ {"denied","query_error"}
```

The mocked executor is `MockStorageCapabilityExecutor` — a proof-local Ruby class
that runs G1–G6 against the capability object and returns typed `QueryResult` +
`QueryExecutionReceipt`. No DB call, no SQL, no ORM.

---

## Next Implementation Card (Precise Scope)

After LANG-IO-CAPABILITY-EXECUTOR-P1 closes, the next implementation card must:

1. Implement `CapabilityExecutor` base interface (from P1 definition).
2. Implement `StorageCapabilityExecutor < CapabilityExecutor` with G1–G6 gates.
3. Implement `CapabilityExecutorRegistry.register("IO.StorageCapability", executor)`.
4. Wire into RuntimeMachine evaluate path for ESCAPE effect contracts.
5. Return `QueryResult` + `QueryExecutionReceipt` as paired typed outputs.
6. Keep all permanently-closed surfaces closed.

The implementation card is bounded: one executor, one capability class, one
effect family (storage read). No write ops, no transactions, no SQL.

---

## Authority

Lab-only — no canon claim, no stable surface, no framework compat.  
No production files changed. No grammar added. No VM modified.  
No SQL connection established. No database runtime.  
No `IO.StorageCapability` execution authority conferred.
