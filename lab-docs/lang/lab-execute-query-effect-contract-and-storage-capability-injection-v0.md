# LAB-EXECUTE-QUERY-P1: ExecuteQuery Effect Contract and StorageCapability Injection

**Track:** `lab-execute-query-effect-contract-and-storage-capability-injection-v0`
**Status:** CLOSED — PROOF COMPLETE (57/57)
**Route:** LAB PROOF / STAGE 2+ / MOCKED STORAGE EXECUTION / NO REAL DB
**Authority:** No canon claim. No framework compat. No public API. No stable surface.

---

## What was proved

An `ExecuteQuery` effect contract can receive a `QueryPlan` plus an `IO.StorageCapability`-shaped authority object, apply the LAB-STORAGE-CAPABILITY-P2 6-gate sequence, and return a typed `QueryResult` + `QueryExecutionReceipt` — using mocked storage data only, with no real database connection, SQL execution, ORM, or persistence runtime at any layer.

Specifically proved:
- `ExecuteQuery` effect contract (with `capability storage : IO.StorageCapability`) is accepted by Layer A (Ruby TypeChecker) and compiles clean in Layer B (Rust compiler). The effect contract passport gap (ESCAPE class) is the correct enforcement boundary: VM execution requires capability injection.
- 17 pure contracts across two fixtures accept at both Layer A and Layer B; all 12 pure contracts in the receipts fixture are VM-executable.
- The 6-gate `StorageCapability` sequence (G1–G6) is proved via Layer C `ExecuteQuerySim` with full `QueryPlan`-shaped + `StorageCapability`-shaped hashes.
- G4 (row-limit clamp) is NOT a denial — `cap_granted` stays `true` after clamp; `row_limit_clamped:true` with `effective_limit == row_limit_cap`.
- G5 (include_all restricted) produces `query_error` NOT `denied` — different consumer action (fix plan before retry vs. do not retry).
- `QueryExecutionReceipt` 15-field invariants hold: `cap_granted:false` iff `result_kind` ∈ {denied, query_error}; `rows_returned:0` whenever `cap_granted:false`.
- The `BuildQueryPlanInline` inline filter array types as `Collection[FilterPredicate]` in the Rust SIR (LAB-TC-ARRAY-P2 record-field-context pattern confirmed in this fixture).
- `TBackend` and `TEMPORAL` types are orthogonal — absent from both fixtures; write ops are closed in v0.

---

## Core formula

```
ExecuteQuery v0  =  QueryPlan  +  IO.StorageCapability authority  →  QueryResult + QueryExecutionReceipt
ExecuteQuery v0  ≠  SQL execution  ≠  ORM  ≠  database runtime  ≠  TBackend
IO.StorageCapability (ESCAPE class)  requires capability injection for VM execution
Stage 2+ STORAGE class fragment required for live storage execution
StorageCapability ≠ database connection; it is a policy-gate authority object
```

---

## Files

| File | Purpose |
|------|---------|
| `igniter-view-engine/fixtures/query_execution/execute_query_capability.ig` | Capability boundary fixture (effect + 4 pure; Module `Lab.ExecuteQuery.CapabilityBoundary`; Layer A + Layer B compile) |
| `igniter-view-engine/fixtures/query_execution/execute_query_receipts.ig` | VM-executable fixture (12 pure contracts; Module `Lab.ExecuteQuery.MockedExecution`; Layer A + Layer B + VM) |
| `igniter-view-engine/proofs/verify_lab_execute_query_p1.rb` | Proof runner — 57 checks, 10 sections |
| `lab-docs/lang/lab-execute-query-effect-contract-and-storage-capability-injection-v0.md` | This document |
| `.agents/work/cards/lang/LAB-EXECUTE-QUERY-P1.md` | Agent card |

---

## Two-fixture architecture

The same two-fixture pattern established in LAB-STORAGE-CAPABILITY-P2:

### Fixture 1: `execute_query_capability.ig` (Layer A + Layer B compile only)

Contains the `ExecuteQuery` effect contract (ESCAPE class — compile proof only; VM requires capability injection) plus 4 pure contracts that prove input/output shapes and the denial-as-data form.

**Contracts (5):**

| Contract | Proves |
|----------|--------|
| `ExecuteQuery` | Effect contract form: capability injection, QueryPlan input, QueryResult output (compile-only) |
| `ReadPlanSource` | Nested field access: `plan.source.table` (two-hop OP_GET_FIELD) |
| `ReadPlanProjection` | Nested field access: `plan.projection.include_all` (G5 gate input, Bool) |
| `BuildDeniedResult` | Denial-as-data: `QueryResult{kind:"denied"}` — G1/G2/G3 form |
| `ReadPlanMeta` | `map_get(plan.metadata, key)` + `or_else` chain on QueryPlan |

### Fixture 2: `execute_query_receipts.ig` (Layer A + Layer B + VM)

Pure contracts only. Contains the `StorageCapability` record (schema-shaped; not `IO.StorageCapability` authority reference), all QueryExecutionReceipt builders, and the metadata chain.

**Contracts (12):**

| Contract | Proves |
|----------|--------|
| `BuildStorageCapability` | StorageCapability 8-field record shape |
| `BuildQueryPlanInline` | Full QueryPlan with inline filter array (LAB-TC-ARRAY-P2 pattern) |
| `ExecuteQueryRows` | `QueryResult{kind:"rows"}` — G6 mocked rows |
| `ExecuteQueryEmpty` | `QueryResult{kind:"empty"}` — G6 zero rows |
| `ExecuteQueryDeniedSource` | `QueryResult{kind:"denied"}` — G1 denial-as-data (10th proof) |
| `ExecuteQueryQueryError` | `QueryResult{kind:"query_error"}` — G5 (≠ denied) |
| `ExecuteQuerySystemError` | `QueryResult{kind:"system_error"}` — G6 infrastructure failure |
| `BuildAllowedReceipt` | Receipt when `cap_granted:true`; no clamp |
| `BuildDeniedGateReceipt` | Receipt when `cap_granted:false` + `denial_gate` set |
| `BuildClampedReceipt` | Receipt when `row_limit_clamped:true` (G4 clamp; `cap_granted:true`) |
| `QueryReceiptReader` | 15-field `QueryExecutionReceipt` field access (all compute nodes) |
| `QueryMetadataChain` | `map_get(result.metadata, key)` + `or_else` on QueryResult |

---

## Type shapes

### QueryExecutionReceipt (15 fields)

```igniter
type QueryExecutionReceipt {
  cap_id:            String,
  plan_kind:         String,
  source_table:      String,
  op_requested:      String,
  cap_checked:       Bool,
  cap_granted:       Bool,
  denial_gate:       String,
  deny_reason:       String,
  plan_limit:        Integer,
  row_limit_cap:     Integer,
  effective_limit:   Integer,
  row_limit_clamped: Bool,
  rows_returned:     Integer,
  result_kind:       String,
  metadata:          Map[String, String]
}
```

### StorageCapability (schema-shaped record, 8 fields)

```igniter
type StorageCapability {
  cap_id:            String,
  allowed_sources:   Collection[String],
  allowed_ops:       Collection[String],
  row_limit:         Integer,
  allow_include_all: Bool,
  read_allowed:      Bool,
  write_allowed:     Bool,
  deny_reason:       String
}
```

---

## 6-gate denial sequence (Layer C)

| Gate | Input | Outcome if fails |
|------|-------|-----------------|
| G1 | `plan.source.table ∈ cap.allowed_sources` | `kind:"denied"`, `denial_gate:"G1"` |
| G2 | `"read" ∈ cap.allowed_ops` | `kind:"denied"`, `denial_gate:"G2"` |
| G3 | `cap.read_allowed == true` | `kind:"denied"`, `denial_gate:"G3"` |
| G4 | `plan.limit ≤ cap.row_limit` | **Clamp only** — `effective_limit = min(plan_limit, row_limit)`; `cap_granted:true`; NOT denied |
| G5 | `plan.projection.include_all == false ∥ cap.allow_include_all == true` | `kind:"query_error"`, `denial_gate:"G5"` (≠ denied) |
| G6 | Mocked execute | `kind:"rows"/"empty"/"system_error"` |

**Denial-as-data invariant:** all gate failures return typed results; no exceptions raised.

**G4 clamp ≠ denial:** `row_limit_clamped:true` with `cap_granted:true`. Consumer receives rows under `effective_limit`.

**G5 query_error ≠ denied:** malformed plan (fix before retry), not access denial. Consumer action: fix plan first; do not retry same plan.

---

## Proof results (57/57)

| Section | Checks | What was proved |
|---------|--------|-----------------|
| EXECQ-COMPILE | 5 | Rust compiler accepts both fixtures; 5+12 contracts; Ruby TC 5/5 accepted |
| EXECQ-SHAPE | 8 | QueryExecutionReceipt (6 fields); QueryPlan.filters; StorageCapability.allowed_sources |
| EXECQ-GATES | 6 | Layer C G1–G6 gate simulation; G4 clamp ≠ denial; G5 query_error ≠ denied |
| EXECQ-RECEIPT | 7 | VM receipt builders; cap_granted/rows_returned invariants; G4 clamp ≠ denial |
| EXECQ-VM | 8 | All 5 KDR result kinds; BuildStorageCapability; BuildQueryPlanInline; clamped receipt |
| EXECQ-MAP | 4 | QueryMetadataChain hit + miss; ReadPlanMeta Layer A accepted; meta_str: String |
| EXECQ-ARRAY | 4 | Rust SIR: filters=Collection[FilterPredicate]; plan=QueryPlan; output port; VM 2-elem array |
| EXECQ-COMPOSE | 5 | plan fields drive gates (source→G1, include_all→G5, limit→G4); source_table preserved |
| EXECQ-CLOSED | 5 | No SQL/DB/ORM; ExecuteQuery compile-only; no persistence in runner |
| EXECQ-GAP | 5 | ESCAPE gap; TBackend absent; KDR routing; write ops CLOSED in v0 |

---

## Boundary findings

### Finding B1: Effect contract passport gap (ESCAPE class — correct enforcement)

`ExecuteQuery` is an effect contract (`capability storage : IO.StorageCapability`). The Lab Rust VM requires a capability passport for any contract in the same igapp directory that declares an effect. Pure-only contracts cannot be VM-executed when an effect contract is present in the same fixture.

**Resolution:** The two-fixture architecture (established in LAB-STORAGE-CAPABILITY-P2) isolates the effect contract in `execute_query_capability.ig` (compile-only Layer A + Layer B) from the pure VM-executable contracts in `execute_query_receipts.ig`. This is the correct ESCAPE boundary — Stage 2+ STORAGE class fragment required for live execution.

### Finding B2: Rust SIR type_tag for inline filter arrays

`BuildQueryPlanInline.filters` (intermediate array-literal compute) types as `Collection[FilterPredicate]` in the Rust SIR (`compute_nodes[].type_tag`). The record-field-context mechanism from LAB-TC-ARRAY-P2 works correctly in this fixture: `QueryPlan.filters : Collection[FilterPredicate]` supplies the element hint, the intermediate `filters` node is upgraded in place.

### Finding B3: `deny_reason` vs `message` (Ruby parser keyword)

The `message` field name is a Ruby parser keyword. The input name `deny_reason` is used in the effect contract and pure contracts where `message` would conflict. This is the same B4 finding from LAB-STORAGE-CAPABILITY-P2; carried forward here.

### Finding B4: `read_file` vs `read` (Ruby parser keyword)

The effect binding uses `read_file` not `read`. `read` is a Ruby parser keyword (`parse_effect_binding_decl: ident-only`). Carried forward from LAB-STORAGE-CAPABILITY-P2 B3.

### Finding B5: TBackend / TEMPORAL orthogonality confirmed

Neither fixture references `TBackend`, `TEMPORAL`, temporal types, or scheduled execution. StorageCapability and temporal execution are orthogonal tracks; no type/grammar/runtime overlap.

---

## Closed surfaces

| Surface | Status |
|---------|--------|
| SQL execution | Closed — no `execute_sql`, `run_query`, `raw_sql` |
| Real database connection | Closed — no `establish_connection`, `database_url`, `ActiveRecord` |
| ORM / ActiveRecord | Closed |
| StorageCapability live execution | Closed — ESCAPE class; Stage 2+ STORAGE fragment required |
| Transactions | Closed |
| Joins / aggregates | Closed |
| Persistence runtime | Closed |
| Write ops | Closed in v0 — `write_allowed` field declared; no write effect contract |
| TBackend / TEMPORAL | Not touched — orthogonal tracks |
| Public / stable API | Closed — LAB-ONLY |

---

## Depends on

| Card | What this proof relied on |
|------|--------------------------|
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44); plan.source.table chained access |
| LAB-STORAGE-CAPABILITY-P1 | IO.StorageCapability schema + 6-gate design |
| LAB-STORAGE-CAPABILITY-P2 | Gate receipts proof (51/51); two-fixture architecture; denial-as-data 9th proof |
| LAB-TC-ARRAY-P2 | Collection[FilterPredicate] from record-field context — BuildQueryPlanInline.filters |
| PROP-035 | `capability`/`effect_binding` grammar (experiment-pass) |
| PROP-046-P1 | IO.StorageCapability boundary proposal (14 sections, 15 decisions locked) |

---

## KDR 5-kind routing (StorageCapability domain)

| Kind | Consumer action | Gate |
|------|----------------|------|
| `rows` | Process rows; iterate and transform | G6 |
| `empty` | Show empty state; no rows matched filters | G6 |
| `denied` | Access denied; do not retry same plan | G1/G2/G3 |
| `query_error` | Malformed plan; fix before retry | G5 |
| `system_error` | Infrastructure failure; retry later | G6 |

---

## Next authorized routes

**For Stage 2+ live execution (STORAGE class):**
- Requires PROP-035 Stage 2+ authorization + ch4 amendment for `ExecuteQuery` ESCAPE→STORAGE promotion
- Not authorized in v0; this proof closes the mocked execution boundary

**For write operations:**
- `write_allowed` field is declared in `StorageCapability`; write ops are CLOSED in v0
- Requires explicit write-execution card + PROP authorization

**For filter evaluation:**
- Card: `LAB-FILTER-EVAL-P1` — in-memory predicate evaluation over `Collection[FilterPredicate]`; no DB; pure

---

*LAB-ONLY. No canon claim. No framework compat. No public API.*
