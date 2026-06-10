# LAB-STORAGE-CAPABILITY-P2: IO.StorageCapability Policy Gates and QueryExecutionReceipt

**Card:** LAB-STORAGE-CAPABILITY-P2
**Track:** lab-storage-capability-policy-gates-and-query-execution-receipt-v0
**Status:** CLOSED — PROOF COMPLETE (51/51)
**Date:** 2026-06-10
**Route:** LAB PROOF / NO REAL DB / NO RUNTIME STORAGE
**Depends on:** LAB-QUERY-P3 (44/44), LAB-STORAGE-CAPABILITY-P1 (design), PROP-035 (capability grammar), PROP-046-P1 (boundary proposal)

---

## Core formula

```
QueryPlan         = pure typed intent data     (CORE fragment class; no capability needed)
StorageCapability = execution authority gate   (ESCAPE/STORAGE; not a DB connection)
QueryResult       = typed outcome/denial data  (5-kind KDR vocabulary)
QueryExecutionReceipt = evidence-only          (does not confer authority)

StorageCapability != database connection
StorageCapability != ORM / ActiveRecord
StorageCapability != SQL runtime
StorageCapability != TBackend (orthogonal — TEMPORAL track)
```

---

## Proof architecture

Three layers, two fixtures:

| Layer | Role | Fixture |
|-------|------|---------|
| Layer A | Ruby TypeChecker | `storage_capability_exec.ig` |
| Layer B | Rust compiler + VM | `storage_capability_exec.ig` (compile); `storage_capability_receipts.ig` (VM) |
| Layer C | Proof-local Ruby simulation | `StorageCapabilityGates` module in runner |

**Fixture split:** `storage_capability_exec.ig` contains the `ExecuteQuery` effect contract (compile-only Layer A + Layer B) alongside all 8 contracts. `storage_capability_receipts.ig` contains the 7 pure contracts only. Reason: Layer B passport requires capability injection for effect contracts; pure contracts must live in a capability-free igapp for VM execution.

---

## Proof results (51/51)

| Section | n | Result |
|---------|---|--------|
| SCAP2-COMPILE  | 4  | PASS |
| SCAP2-SCHEMA   | 6  | PASS |
| SCAP2-G1       | 4  | PASS |
| SCAP2-G2       | 3  | PASS |
| SCAP2-G3       | 3  | PASS |
| SCAP2-G4       | 4  | PASS |
| SCAP2-G5       | 3  | PASS |
| SCAP2-G6       | 4  | PASS |
| SCAP2-RECEIPT  | 6  | PASS |
| SCAP2-KDR      | 4  | PASS |
| SCAP2-COMPOSE  | 5  | PASS |
| SCAP2-CLOSED   | 5  | PASS |
| **Total**      | **51** | **PASS** |

---

## Contracts proved

### Fixture: storage_capability_exec.ig (Layer A + Layer B compile)

| Contract | Kind | Proves |
|----------|------|--------|
| `ExecuteQuery` | effect (compile-only) | `capability storage: IO.StorageCapability` + `effect read_file using storage`; Layer A + Layer B accept; ESCAPE class |
| `BuildGrantedReceipt` | pure | Receipt shape when cap granted (no clamp): `cap_granted:true`, `effective_limit = plan_limit` |
| `BuildDeniedReceipt` | pure | Receipt shape for G1/G2/G3 denials: `cap_granted:false`, `effective_limit:0`, `rows_returned:0` |
| `BuildClampedReceipt` | pure | Receipt shape when G4 clamps: `effective_limit = row_limit_cap`, `row_limit_clamped:true` |
| `ReadReceiptFields` | pure | Field access on 15-field `QueryExecutionReceipt`: `receipt.cap_granted` → Bool |
| `DeniedResult` | pure | `QueryResult{kind:"denied"}` — denial-as-data from G1/G2/G3 |
| `QueryErrorResult` | pure | `QueryResult{kind:"query_error"}` — G5 result (not "denied") |
| `RowsResult` | pure | `QueryResult{kind:"rows"}` — G6 mocked execution |

### Fixture: storage_capability_receipts.ig (Layer B VM execution)

All 7 pure contracts above — VM-executable without capability injection.

---

## Types proved

### QueryExecutionReceipt (15 fields)

| Field | Type | Invariant |
|-------|------|-----------|
| `cap_id` | String | identity of the capability checked |
| `plan_kind` | String | from input QueryPlan.kind |
| `source_table` | String | from input QueryPlan.source.table |
| `op_requested` | String | "read" in v0 |
| `cap_checked` | Bool | always true when receipt exists |
| `cap_granted` | Bool | false iff result_kind ∈ {denied, query_error} |
| `denial_gate` | String | "G1".."G5" or "" when granted |
| `deny_reason` | String | human-readable denial message |
| `plan_limit` | Integer | from input QueryPlan.limit |
| `row_limit_cap` | Integer | from IO.StorageCapability.row_limit |
| `effective_limit` | Integer | min(plan_limit, row_limit_cap) |
| `row_limit_clamped` | Bool | true iff effective_limit < plan_limit |
| `rows_returned` | Integer | 0 whenever cap_granted:false |
| `result_kind` | String | 5-kind KDR vocabulary |
| `metadata` | Map[String, String] | from input QueryPlan.metadata |

---

## 6-gate sequence (proved by Layer C)

| Gate | Input condition | Outcome kind | cap_granted | Notes |
|------|----------------|--------------|-------------|-------|
| G1 | source not in `allowed_sources` | `"denied"` | false | fail-closed; empty list = deny all |
| G2 | `"read"` not in `allowed_ops` | `"denied"` | false | op allowlist checked after source |
| G3 | `read_allowed == false` | `"denied"` | false | master kill-switch |
| G4 | `plan.limit > row_limit` | *(no denial)* | true | clamp: `effective_limit = min(...)` |
| G5 | `include_all && !allow_include_all` | `"query_error"` | false | malformed plan, not access denial |
| G6 | mocked execution | `"rows"`/`"empty"`/`"system_error"` | true/true/false | G6 cap_granted:false only on system_error |

Key design invariants (all proved):
- **G4 is a clamp, not a denial** — `result_kind` never `"denied"` after G4 passes
- **G5 → "query_error", not "denied"** — different consumer action: fix plan, not retry same plan
- **denial-as-data** — all gate failures return typed result; no exceptions/raise

---

## KDR vocabulary (5 kinds)

| Kind | Consumer action | Gate source |
|------|----------------|-------------|
| `"rows"` | process/iterate | G6 (rows > 0) |
| `"empty"` | show empty state | G6 (rows == 0) |
| `"denied"` | deny; do not retry same plan | G1, G2, G3 |
| `"query_error"` | fix plan before retry | G5 |
| `"system_error"` | retry later (infra failure) | G6 (inject_error) |

---

## Boundary findings

### B1 — Effect contract passport gap (Layer B VM)

**Finding:** `ExecuteQuery` (effect contract with `capability storage: IO.StorageCapability`) compiles cleanly through both Layer A (Ruby TypeChecker) and Layer B (Rust compiler) — zero diagnostics. However, the compiled igapp's passport requires capability injection (`storage` binding) at runtime. VM execution of any contract in the same igapp fails with `PassportError: missing capability binding for parameter 'storage'`.

**Resolution:** Split into two fixtures. Effect contracts are correctly classified as ESCAPE class. VM execution of effect contracts requires capability injection infrastructure — Stage 2+ STORAGE class work. This is the correct boundary.

**Evidence type:** Lab boundary finding. Not a language gap. ESCAPE class enforcement working as designed.

### B2 — Rust classifier effect name vocabulary

**Finding:** The Rust classifier enforces a closed vocabulary of effect names: `{read_file, read_json, read, write_file, write_json, write}`. `read_from_storage` (the PROP-046 design name) is rejected with `E-IO-EFFECT-UNKNOWN`. The Ruby TypeChecker has no such vocabulary check.

**Resolution:** Used `read_file` as the effect name in the fixture (accepted by both Rust and Ruby parsers). The actual runtime effect name for StorageCapability is a Stage 2+ detail.

**Evidence type:** Lab boundary finding. Rust classifier vocabulary is narrower than the design intent. Future PROP or card required to add `read_storage`/`write_storage` to the recognized effect vocabulary.

### B3 — `read` is a Ruby parser keyword

**Finding:** `read` is in the Ruby parser's `KEYWORDS` list. `parse_input_decl` and `parse_effect_binding_decl` call `name_token!(%i[ident])` (ident-only). Using `effect read using storage` fails Layer A parsing with `Expected name, got keyword(read)`. Used `read_file` as the effect binding name.

**Evidence type:** Lab surface constraint. Parser keyword list excludes `read` from use as an identifier in input/effect binding positions.

### B4 — `message` is a Ruby parser keyword

**Finding:** `message` is also in the `KEYWORDS` list. `input message: String` fails Layer A parsing. Renamed all `message` inputs to `reason` in contracts.

**Evidence type:** Lab surface constraint. Affects any contract that uses `message` as an input name.

---

## Receipt invariants (all proved)

| # | Invariant |
|---|-----------|
| I1 | `cap_checked` is always `true` when a receipt exists |
| I2 | `cap_granted == false` iff `result_kind ∈ {"denied", "query_error"}` |
| I3 | `rows_returned == 0` whenever `cap_granted == false` |
| I4 | `effective_limit == min(plan_limit, row_limit_cap)` |
| I5 | `row_limit_clamped == true` iff `effective_limit < plan_limit` |
| I6 | `source_table == plan.source.table` (preserved from plan) |

---

## TBackend ⊥ StorageCapability

These are orthogonal tracks. No types, grammar, or runtime overlap:

| Dimension | TBackend / TEMPORAL | IO.StorageCapability |
|-----------|---------------------|---------------------|
| Domain | Temporal state / event history | Relational-like query execution |
| Types | `History[T]`, `BiHistory[T]` | `QueryPlan`, `QueryResult`, `QueryExecutionReceipt` |
| Fragment class | TEMPORAL | ESCAPE (v0) → STORAGE (Stage 2+) |
| Authorization | — | capability gate (6 gates) |
| Row model | event log | tabular rows |

---

## Closed surfaces (confirmed by this proof)

| Surface | Status |
|---------|--------|
| Real database connection | NOT OPENED — no `establish_connection`, no DB URL |
| SQL execution | NOT OPENED — no SELECT/INSERT/UPDATE/DELETE |
| ORM / ActiveRecord | NOT OPENED — no ActiveRecord calls |
| Migrations / transactions | NOT OPENED |
| Persistence runtime | NOT OPENED |
| Stable public API | NOT OPENED |
| Write ops | NOT OPENED — closed in v0; deferred |
| TBackend / TEMPORAL | NOT TOUCHED — orthogonal track |

---

## Authorized next routes

From PROP-046:
- `LAB-EXECUTE-QUERY-P1` — Stage 2+ execution proof with capability injection (requires STORAGE class amendment)
- `LAB-TC-ARRAY-P1` — Rust typechecker array_literal gap (from LAB-QUERY-P3 B1)
- `OOF-STORE1..5` activation (require explicit card)
- Effect name vocabulary expansion in Rust classifier (B2 above — requires explicit card)

---

*LAB-ONLY. No canon claim. No stable surface. No public API.*
*All evidence: layer-A/B/C lab proof only.*
