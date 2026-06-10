# LAB-EXECUTE-QUERY-P2: Integrated Mocked Query Execution

**Track:** `lab-execute-query-integrated-gates-filter-order-limit-receipt-v0`
**Status:** CLOSED — PROOF COMPLETE (73/73)
**Route:** LAB PROOF / INTEGRATED MOCKED QUERY EXECUTION / NO DB
**Authority:** No canon claim. No framework compat. No public API. No stable surface.

---

## What was proved

The first complete mocked `ExecuteQuery` pipeline. The three previously separate proof-local layers — StorageCapability gate sequence (LAB-EXECUTE-QUERY-P1), filter evaluation (LAB-FILTER-EVAL-P1), and order/limit semantics (LAB-QUERY-ORDER-LIMIT-P1) — are now integrated into a single `IntegratedQuerySim` execution path that produces both a `QueryResult` and a `QueryExecutionReceipt`.

Specifically proved:
- The 6-gate pipeline (G1–G6) correctly sequences source-allowlist, op-allowlist, read-master, row-limit clamp, include-all policy, and query evaluation.
- G1/G2/G3 gate failures short-circuit before filter/order/limit evaluation: no rows evaluated, receipt records `cap_granted:false`, `rows_returned:0`.
- G4 row-limit clamp: `effective_limit = min(plan.limit, cap.row_limit)`. Cap clamp is NOT a denial — `cap_granted` remains true after clamp; `row_limit_clamped` records whether the clamp reduced the plan limit.
- G5 `include_all` violation → `kind:"query_error"` (NOT `kind:"denied"`): malformed plan field, not access denial.
- G6 filter/order/limit failures → `kind:"query_error"` (NOT `kind:"denied"`): malformed plan field.
- `query_error ≠ denied` throughout the integrated pipeline — the distinction holds in all 73 checks.
- Filter semantics: `eq`/`neq`/`contains`/`prefix`; AND-only composition; unknown op → `query_error`; missing field in row → `empty` (row silently fails filter, vacuous false); empty filter list → all rows pass.
- Order semantics: `asc`/`desc` lexicographic; stable sort (equal keys preserve input order); empty direction → preserve input order; unknown direction → `query_error`.
- Limit semantics: applied AFTER filter and order (order-then-limit invariant); `limit > 0` → at most `limit` rows; `limit == 0` → `empty`; `limit < 0` → `query_error`.
- `QueryExecutionReceipt` (15 fields): records `cap_checked`, `cap_granted`, `denial_gate`, `deny_reason`, `plan_limit`, `row_limit_cap`, `effective_limit`, `row_limit_clamped`, `rows_returned`, `result_kind` — every receipt field verified against known Layer C outcomes.
- `BuildIntegratedPlan.filters` types as `Collection[FilterPredicate]` in the Rust SIR (record-field-context mechanism — 5th confirmation across fixtures).
- All 8 contracts VM-executed at Layer B.
- KDR 5-kind routing: `rows` → process; `empty` → show empty state; `denied` → deny; `query_error` → fix plan before retry; `system_error` → retry later.

---

## Core formula

```
ExecuteQueryMock v0 = QueryPlan + StorageCapability-shaped policy + mocked rows
                    → gated / filtered / ordered / limited QueryResult + QueryExecutionReceipt
ExecuteQueryMock v0 ≠ sql execution ≠ DB runtime ≠ ORM ≠ production StorageCapability execution
ExecuteQueryMock v0 ≠ query optimizer ≠ index-backed sorting
IntegratedQuerySim  = PROOF-LOCAL ONLY ≠ production integrated query runtime
```

---

## Files

| File | Purpose |
|------|---------|
| `igniter-view-engine/fixtures/query_execution/execute_query_integrated.ig` | 8 pure contracts (all CORE; no effect; no capability authority) |
| `igniter-view-engine/proofs/verify_lab_execute_query_p2.rb` | Proof runner — 73 checks, 10 sections |
| `lab-docs/lang/lab-execute-query-integrated-gates-filter-order-limit-receipt-v0.md` | This document |
| `.agents/work/cards/lang/LAB-EXECUTE-QUERY-P2.md` | Agent card |

---

## Type shapes

### QueryPlan (7 fields)

```igniter
type QueryPlan {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      OrderBy,
  limit:      Integer,
  metadata:   Map[String, String]
}
```

### StorageCapability (plain Record — 8 fields)

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

**Note:** `StorageCapability` is a plain named Record here — it models gate parameters only. It is NOT the `IO.StorageCapability` capability authority reference.

### QueryResult (4 fields — same as LAB-FILTER-EVAL-P1 / LAB-QUERY-ORDER-LIMIT-P1)

```igniter
type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}
```

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

---

## Contracts (8)

| Contract | Proves |
|----------|--------|
| `BuildIntegratedPlan` | `QueryPlan` with inline filter array (LAB-TC-ARRAY-P2 mechanism — 5th confirmation) |
| `BuildIntegratedCapability` | `StorageCapability` plain Record shape (8 fields) |
| `BuildIntegratedRowsResult` | `QueryResult{kind:"rows", count:N}` — rows returned after pipeline |
| `BuildIntegratedEmptyResult` | `QueryResult{kind:"empty", count:0}` — zero rows |
| `BuildIntegratedDeniedResult` | `QueryResult{kind:"denied", count:0}` — G1/G2/G3 gate denial |
| `BuildIntegratedQueryErrorResult` | `QueryResult{kind:"query_error", count:0}` — malformed plan field |
| `BuildIntegratedReceipt` | `QueryExecutionReceipt` (15 fields) — allowed execution receipt |
| `IntegratedMetadataReader` | `map_get(result.metadata, key)` + `or_else` on integrated `QueryResult` |

**Note on input naming:** `BuildIntegratedDeniedResult` uses `input deny_reason : String` and `BuildIntegratedQueryErrorResult` uses `input reason : String`. The name `message` cannot be used as an Igniter input name — it is a Ruby parser keyword (boundary finding B4/B5 from prior proofs).

---

## Gate pipeline (G1–G6)

### Gate sequence and routing

| Gate | Condition | Result kind | Denial? |
|------|-----------|-------------|---------|
| G1 | `source.table` not in `cap.allowed_sources` | `denied` | Yes — cap_granted:false |
| G2 | `"read"` not in `cap.allowed_ops` | `denied` | Yes — cap_granted:false |
| G3 | `cap.read_allowed == false` | `denied` | Yes — cap_granted:false |
| G4 | `plan.limit > cap.row_limit` | clamp only | No — cap_granted:true; effective_limit reduced |
| G5 | `projection.include_all && !cap.allow_include_all` | `query_error` | No — malformed plan |
| G6 | evaluate filter → order → limit | `rows`/`empty`/`query_error` | No |

### G4 clamp semantics

G4 is a **clamp**, not a denial. `effective_limit = min(plan.limit, cap.row_limit)`. The capability grants the read but reduces the row count ceiling. `row_limit_clamped = true` records that the cap reduced the plan's requested limit. `cap_granted` stays `true` after G4.

### G5 vs G1/G2/G3 distinction

G5 produces `kind:"query_error"` (not `kind:"denied"`) because `include_all` is a plan policy field — a malformed plan choice. The consumer must fix the plan before retry, not present different credentials.

### Gate short-circuit invariant

G1/G2/G3 failures return immediately with `rows:[]`, `rows_returned:0`. Filter, order, and limit evaluation is never invoked after a denial gate fires. The receipt records `denial_gate` identifying which gate fired.

---

## Layer C: IntegratedQuerySim

### What it is

`IntegratedQuerySim` is the proof-local Ruby module that executes the full integrated pipeline over in-memory Hash rows. It is **PROOF-LOCAL ONLY** — not a production integrated query runtime.

### Pipeline execution order

```
G1 source allowlist         → denied if not in allowed_sources
G2 op allowlist             → denied if "read" not in allowed_ops
G3 read_allowed             → denied if false
G4 row-limit clamp          → effective_limit = min(plan.limit, cap.row_limit); NOT denial
G5 include_all policy       → query_error if projection.include_all && !cap.allow_include_all
G6a apply_filters           → query_error (bad op) or matched rows
G6b apply_order             → query_error (bad direction) or sorted rows
G6c apply effective_limit   → empty (limit==0) / query_error (limit<0) / limited rows
build receipt               → QueryExecutionReceipt (15 fields)
```

### Filter semantics (G6a)

| Operator | Semantics | Unknown op result |
|----------|-----------|-------------------|
| `eq` | row value equals filter value | — |
| `neq` | row value does not equal filter value | — |
| `contains` | row value contains filter value as substring | — |
| `prefix` | row value starts with filter value | — |
| any other | `kind:"query_error"` (NOT `"denied"`) | — |

- AND-only composition: all predicates must match.
- Missing field in row: row silently fails the filter (returns `false`) → effectively `empty` if no rows match. NOT a `query_error`.
- Empty filter list → all rows pass (vacuous conjunction).

### Order semantics (G6b)

| Direction | Semantics |
|-----------|-----------|
| `"asc"` | Ascending lexicographic order |
| `"desc"` | Descending lexicographic order |
| `""` (empty) | No ordering; preserve input order |
| other | `kind:"query_error"` (NOT `"denied"`) |

- All comparisons are lexicographic String comparisons in v0.
- Stable sort: equal order-field values preserve input order.
- Missing order field in any row → `kind:"query_error"` (fail-closed).

### Limit semantics (G6c)

| Limit value | Result |
|-------------|--------|
| `> 0` | First `effective_limit` rows after filter + order |
| `== 0` | `kind:"empty"`, count:0 |
| `< 0` | `kind:"query_error"` (NOT `"denied"`) |

- **Order-then-limit invariant**: limit is always applied AFTER ordering.
- `QueryPlan.limit` and `StorageCapability.row_limit` are orthogonal. G4 computes `effective_limit = min(plan.limit, cap.row_limit)` before filter/order/limit evaluation.

---

## Three-layer proof structure

### Layer A — Ruby TypeChecker

All 8 contracts accepted; zero type_errors. `QueryPlan`, `StorageCapability`, `QueryResult`, `QueryExecutionReceipt`, `OrderBy`, `FilterPredicate`, `QuerySource`, `Projection` all in `type_env` with correct field types. `QueryPlan.filters: Collection[FilterPredicate]`, `QueryPlan.order: OrderBy`, `QueryPlan.limit: Integer`.

### Layer B — Lab Rust compiler + VM

- Fixture compiles; 8 contracts; zero diagnostics.
- Rust SIR: `BuildIntegratedPlan.filters` compute_type_tag = `Collection[FilterPredicate]` — record-field-context mechanism confirmed for the 5th time across fixtures (LAB-TC-ARRAY-P2).
- VM: all 8 contracts VM-executed; all return `status:"success"` with correct shapes. `BuildIntegratedReceipt` returns all 15 fields; `IntegratedMetadataReader` returns `"api"` on hit and `"not-found"` on miss.

### Layer C — Proof-local IntegratedQuerySim (Ruby)

Pure Ruby; in-memory Hash rows only. Deterministic 5-row dataset (alice/bob/carol/dave/eve) and 4-row DUPE_ROWS dataset for stable sort. Proves all gate paths, filter operators, order/limit semantics, and receipt field invariants. `IntegratedQuerySim` is PROOF-LOCAL — not a production integrated query runtime.

---

## Proof results (73/73)

| Section | Checks | What was proved |
|---------|--------|-----------------|
| EXECQ2-COMPILE | 5 | Fixture compiles; 8 contracts; Ruby TC all accepted; zero type_errors |
| EXECQ2-SHAPE | 8 | Collection[FilterPredicate]; OrderBy; QueryResult 4 fields; StorageCapability field types; receipt 15 fields; Rust SIR type tag |
| EXECQ2-GATES | 6 | G1/G2/G3→denied; G4 clamp ≠ denial; G5→query_error; system_error distinct |
| EXECQ2-FILTER | 8 | eq/neq/contains/prefix; AND; empty list; missing field → empty; bad op → query_error |
| EXECQ2-ORDER-LIMIT | 8 | asc/desc; stable sort; empty direction; bad direction → query_error; limit 0/negative/order-then-limit |
| EXECQ2-INTEGRATED | 7 | Full pipeline rows/empty/bad-op/bad-dir/denied/clamped; query_error ≠ denied invariant |
| EXECQ2-RECEIPT | 7 | cap_checked; cap_granted invariant; denial_gate:G1; effective_limit = min; row_limit_clamped; rows_returned; result_kind mirrors kind |
| EXECQ2-VM | 8 | All 8 contracts VM-executed; plan filters array; cap shape; rows/empty/denied/query_error/receipt/metadata |
| EXECQ2-CLOSED | 9 | No SQL/DB/ORM/index-usage/joins/writes/transactions/capability-authority/persistence in any layer |
| EXECQ2-GAP | 7 | Complete pipeline story; not production; no sql; Layer C proof-local; row_limit orthogonal; joins deferred; gate short-circuit confirmed |

---

## Boundary findings

### B1: Gate short-circuit before filter/order/limit is the correct execution model

When G1, G2, or G3 fires, the pipeline returns immediately. Filter evaluation, order sorting, and limit slicing are never invoked. The receipt records `rows_returned:0` and `cap_granted:false`. This is the correct boundary — not a shortcut. A production path must not invoke query evaluation logic after a capability denial.

### B2: G4 clamp ≠ denial — effective_limit, cap_granted:true, row_limit_clamped:true

G4 reduces `effective_limit` to `min(plan.limit, cap.row_limit)` but does NOT deny. `cap_granted` stays `true`. `row_limit_clamped` records the clamp. This distinction matters for consumers: a clamped result should not be retried as a denial.

### B3: G5 → query_error (NOT denied) — include_all is a plan field

`include_all` is a plan field that the consumer controls. Violating the capability's `allow_include_all` policy means the consumer sent a malformed plan — fix the plan before retry. It is not an access denial.

### B4: query_error ≠ denied invariant holds throughout integrated pipeline

G1/G2/G3 → `denied`. G5/G6-filter/G6-order/negative-limit → `query_error`. These two failure kinds must never be conflated. A consumer routing on `denied` must not match `query_error`, and vice versa. All 73 checks confirmed this invariant.

### B5: QueryPlan.limit and StorageCapability row_limit are orthogonal — do not conflate

`QueryPlan.limit` is user query intent. `StorageCapability.row_limit` is the capability clamp applied at G4. The integrated pipeline computes `effective_limit = min(plan.limit, cap.row_limit)` and passes it to limit evaluation. These are separate concerns.

### B6: Collection[FilterPredicate] from record-field context — 5th confirmation

`BuildIntegratedPlan.filters` inline array `[{ field: "status", op: "eq", value: "active" }, ...]` types as `Collection[FilterPredicate]` in the Rust SIR because the array is assigned to `QueryPlan.filters` (a `Collection[FilterPredicate]` field). This is the LAB-TC-ARRAY-P2 mechanism. Fifth confirmation across fixtures.

### B7: `message` is a Ruby parser keyword — use `reason` or `deny_reason`

Confirmed again: `input message : String` fails the Ruby TypeChecker. `BuildIntegratedDeniedResult` uses `input deny_reason : String`; `BuildIntegratedQueryErrorResult` uses `input reason : String`. These names work correctly and map to `message` in the computed record literal.

---

## Closed surfaces

| Surface | Status |
|---------|--------|
| SQL query execution | Closed — no sql, no ORDER\s+BY, no SELECT FROM |
| Real database connection | Closed — no establish_connection, no database_url |
| ORM / ActiveRecord / Arel | Closed |
| Index hints / query optimizer usage | Closed |
| Joins / aggregates | Deferred — v0 is single-source only |
| Write operations / transactions | Closed |
| StorageCapability live execution (IO authority) | Closed — StorageCapability is plain Record only |
| Persistence runtime | Closed |
| Numeric / date / locale-aware ordering | Deferred — v0 is lexicographic String only |
| Multi-column ordering | Deferred — v0 supports single OrderBy field |
| Production integrated query runtime | Closed — IntegratedQuerySim is PROOF-LOCAL ONLY |
| Public / stable API | Closed — LAB-ONLY |

---

## Depends on

| Card | What this proof relied on |
|------|--------------------------|
| LAB-EXECUTE-QUERY-P1 | StorageCapability gate sequence (57/57); G1–G6 gate pipeline design |
| LAB-FILTER-EVAL-P1 | Filter evaluation semantics (50/50); Layer C mocked row evaluation pattern |
| LAB-QUERY-ORDER-LIMIT-P1 | Order/limit semantics (54/54); stable sort; order-then-limit invariant |
| LAB-STORAGE-CAPABILITY-P2 | Gate receipt fields (51/51); cap_checked/cap_granted invariants |
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44); field access patterns |
| LAB-TC-ARRAY-P2 | `Collection[FilterPredicate]` from record-field context (19/19) |
| PROP-043-P5 | `Map[String,String]` production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM `map_get`/`or_else` (48/48) |
| LAB-RECORD-VM-P3 | Nested record field access (49/49) |

---

## KDR 5-kind routing (integrated pipeline)

| Kind | Consumer action | Condition |
|------|----------------|-----------|
| `rows` | Process returned rows; count > 0 | Gates passed; filter + order + limit produced rows |
| `empty` | Show empty state; no rows | Gates passed; zero rows after filter/order/limit or limit==0 |
| `denied` | Do not retry same plan+cap; check credentials/source | G1/G2/G3 gate denial |
| `query_error` | Fix plan field before retry | G5/G6-filter op/G6-order direction/negative limit |
| `system_error` | Retry later; infrastructure failure | Not produced by IntegratedQuerySim; modeled for completeness |

---

## Next authorized routes

**Production integrated query execution:**
- IntegratedQuerySim is PROOF-LOCAL only.
- A production path requires StorageCapability live execution (IO authority), real row storage, VM sort/iteration opcodes or compiled-to-host evaluation.
- Separate card required.

**Multi-column ordering:**
- `order: Collection[OrderBy]` — requires typed collection field and multi-column sort semantics.
- Separate card required.

**Numeric/date/locale-aware ordering:**
- Requires type promotion in row values (string → Integer/Date coercion) or a typed Row record.
- Deferred — not in scope for v0.

**Joins / aggregates:**
- Single-source only in v0.
- Separate card required.

**Write execution:**
- Closed for this track; separate card required.

---

*LAB-ONLY. No canon claim. No framework compat. No public API.*
