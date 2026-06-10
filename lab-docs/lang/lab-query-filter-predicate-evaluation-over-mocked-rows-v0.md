# LAB-FILTER-EVAL-P1: Filter Predicate Evaluation Over Mocked Rows

**Track:** `lab-query-filter-predicate-evaluation-over-mocked-rows-v0`
**Status:** CLOSED — PROOF COMPLETE (50/50)
**Route:** LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB
**Authority:** No canon claim. No framework compat. No public API. No stable surface.

---

## What was proved

`QueryPlan.filters` is no longer just a shape — it has a v0 semantic meaning over mocked in-memory rows. A `Collection[FilterPredicate]` can be applied to mocked rows and produce deterministic `QueryResult` data without SQL, database access, ORM, or storage runtime authority.

Specifically proved:
- Four `FilterPredicate` shapes (eq, neq, contains, prefix) accepted at Layer A (Ruby TypeChecker) and Layer B (Rust compiler). Contracts CORE fragment — no capability, no IO, no effect contracts required.
- `BuildQueryPlanWithFilters` inline filter array types as `Collection[FilterPredicate]` in the Rust SIR (record-field-context mechanism from LAB-TC-ARRAY-P2, confirmed again in this fixture).
- Empty filter array (`compute filters = []`) also types as `Collection[FilterPredicate]` from record-field context (inline fixture confirms).
- Layer C `FilterEvalSim` evaluates all four operators correctly over a 5-row deterministic dataset:
  - `eq`: 4 of 5 rows match `status == "active"`
  - `neq`: 4 of 5 rows match `role != "guest"`
  - `contains`: 2 of 5 rows match `name.include?("alex")` — "alex" and "alexia"
  - `prefix`: 2 of 5 rows match `email.start_with?("admin")` — "admin@…" and "admin2@…"
- AND composition narrows correctly: `AND(status=active, role!=guest)` → 3 matches (< 4 each individually).
- Empty filter list → all 5 rows (vacuous conjunction = true). Not an error.
- Unknown field in row → 0 matches, `kind:"empty"` — field absence is NOT a `query_error`.
- Unknown operator → `kind:"query_error"` (NOT `kind:"denied"`) — malformed predicate, fix before retry.
- `count == matched_rows.length` holds as an invariant across all evaluations.
- VM executes all 6 tested contracts correctly: BuildFilterEq, BuildFilterContains, BuildQueryPlanWithFilters, FilterResultRows, FilterResultEmpty, FilterResultQueryError.
- `FilterResultMetadataReader` — `map_get + or_else` on `QueryResult.metadata` works on filter outputs.

---

## Core formula

```
FilterEval v0  =  Collection[FilterPredicate]  +  mocked rows  →  QueryResult
FilterEval v0  ≠  SQL execution  ≠  DB runtime  ≠  ORM  ≠  StorageCapability live execution
FilterEvalSim  =  PROOF-LOCAL ONLY  ≠  production filter engine
```

---

## Files

| File | Purpose |
|------|---------|
| `igniter-view-engine/fixtures/query_execution/filter_eval.ig` | 9 pure contracts (all CORE; no effect; no capability) |
| `igniter-view-engine/proofs/verify_lab_filter_eval_p1.rb` | Proof runner — 50 checks, 8 sections |
| `lab-docs/lang/lab-query-filter-predicate-evaluation-over-mocked-rows-v0.md` | This document |
| `.agents/work/cards/lang/LAB-FILTER-EVAL-P1.md` | Agent card |

---

## Type shapes

### FilterPredicate (3 fields)

```igniter
type FilterPredicate {
  field: String,
  op:    String,
  value: String
}
```

### QueryResult (4 fields — same as LAB-EXECUTE-QUERY-P1; no rows field in v0)

```igniter
type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}
```

**Note:** Rows themselves are not stored in `QueryResult` in the Igniter fixture — the Igniter VM has no iteration/loop opcodes. Row data is carried by the Layer C `FilterEvalSim` (Ruby). `count` in `QueryResult` reflects the number of matched rows. If a `rows` field is needed in future, that requires a separate card.

---

## Contracts (9)

| Contract | Proves |
|----------|--------|
| `BuildFilterEq` | eq FilterPredicate shape — `op:"eq"` |
| `BuildFilterNeq` | neq FilterPredicate shape — `op:"neq"` |
| `BuildFilterContains` | contains FilterPredicate shape — `op:"contains"` |
| `BuildFilterPrefix` | prefix FilterPredicate shape — `op:"prefix"` |
| `BuildQueryPlanWithFilters` | QueryPlan with inline 2-filter array (LAB-TC-ARRAY-P2 mechanism) |
| `FilterResultRows` | `QueryResult{kind:"rows", count:N}` — matched rows exist |
| `FilterResultEmpty` | `QueryResult{kind:"empty", count:0}` — zero rows matched |
| `FilterResultQueryError` | `QueryResult{kind:"query_error"}` — unknown operator (≠ "denied") |
| `FilterResultMetadataReader` | `map_get(result.metadata, key)` + `or_else` on filter output |

---

## v0 filter semantics (Layer C)

### Operators

| Operator | Semantics | Row match condition |
|----------|-----------|---------------------|
| `eq` | String equality | `row[field] == value` |
| `neq` | String inequality | `row[field] != value` |
| `contains` | Substring match | `row[field].include?(value)` |
| `prefix` | Prefix match | `row[field].start_with?(value)` |

### Composition

- **AND only in v0.** All predicates must pass for a row to match.
- **Empty list = all rows.** Vacuous conjunction. Not an error.

### Special cases

| Case | Behaviour | Kind |
|------|-----------|------|
| Unknown field in row | Row fails predicate; not an error | `empty` (if all rows fail) |
| Unknown operator | `kind:"query_error"` (NOT `"denied"`) | `query_error` |
| Zero matches | `kind:"empty"`, `count:0` | `empty` |
| One or more matches | `kind:"rows"`, `count:N` | `rows` |

### Unknown field vs unknown operator

| Situation | Result | Why |
|-----------|--------|-----|
| Field not in row | `kind:"empty"` (row just doesn't match) | Absence of data ≠ malformed predicate |
| Op not in KNOWN_OPS | `kind:"query_error"` | Predicate is malformed; must fix before retry |

---

## Three-layer proof structure

### Layer A — Ruby TypeChecker

All 9 contracts accepted; zero type_errors. `FilterPredicate`, `QueryPlan`, `QueryResult` types in type_env with correct field types. `QueryPlan.filters: Collection[FilterPredicate]`.

### Layer B — Lab Rust compiler + VM

- Fixture compiles; 9 contracts; zero diagnostics.
- Rust SIR: `BuildQueryPlanWithFilters.filters` compute_type_tag = `Collection[FilterPredicate]` (record-field-context mechanism).
- Rust SIR: `BuildQueryPlanWithFilters.plan` compute_type_tag = `QueryPlan`.
- Inline empty array: `compute filters = []` in `QueryPlan.filters` field context → `Collection[FilterPredicate]` (confirmed).
- VM: 6 of 9 contracts VM-executed; all return `status:"success"` with correct shapes.

### Layer C — Proof-local FilterEvalSim (Ruby)

Pure Ruby implementation; in-memory Hash rows only. Proves semantic correctness of all four operators and AND composition. `FilterEvalSim` is PROOF-LOCAL — not a production filter runtime.

---

## Proof results (50/50)

| Section | Checks | What was proved |
|---------|--------|-----------------|
| FEVAL-COMPILE | 5 | Fixture compiles; 9 contracts; Ruby TC all accepted; zero type_errors |
| FEVAL-SHAPE | 7 | FilterPredicate 3 fields; QueryPlan.filters; QueryResult count/kind/metadata |
| FEVAL-ARRAY | 4 | Rust SIR: filters=Collection[FilterPredicate]; plan=QueryPlan; output port; inline empty array |
| FEVAL-SEMANTICS | 7 | eq/neq/contains/prefix correct; AND narrows; empty list all rows; missing field no match |
| FEVAL-RESULT | 6 | rows/empty/query_error result kinds; count==length invariant; AND narrows count |
| FEVAL-VM | 8 | 6 VM contracts: filter shapes, plan with filters, rows/empty/query_error, metadata chain |
| FEVAL-CLOSED | 5 | No SQL/DB/ORM/StorageCapability/write at any layer |
| FEVAL-GAP | 8 | In-memory only; AND-only; OR/NOT deferred; unknown op=query_error; G1–G6 absent |

---

## Boundary findings

### Finding B1: Igniter VM has no iteration opcodes — Layer C required for row evaluation

The Igniter VM (v0) has no loop or iteration opcodes. It cannot apply a `Collection[FilterPredicate]` to a sequence of rows at runtime. The correct boundary:

- **Layer A + B**: Prove filter predicate and query plan *shapes* (types, SIR, VM construction).
- **Layer C**: Prove filter evaluation *semantics* over mocked rows (Ruby simulator).

This is not a workaround — it is the correct separation. Layer B proves the type invariants hold in the compiler; Layer C proves the evaluation model is semantically correct. The two layers are independent: the Layer C semantics will eventually need a production evaluation path (a separate card).

### Finding B2: Empty filter array → Collection[FilterPredicate] from record-field context

`compute filters = []` in the context of `QueryPlan.filters: Collection[FilterPredicate]` types as `Collection[FilterPredicate]` in the Rust SIR. This is the same mechanism as LAB-TC-ARRAY-P2 and LAB-EXECUTE-QUERY-P1. Third confirmation in three distinct fixtures.

### Finding B3: Unknown field ≠ unknown operator

Two distinct v0 behaviours intentionally separated:
- Unknown field in row → `kind:"empty"` (row fails predicate; no error; analogous to SQL `WHERE field = 'x'` on a row that doesn't have that column in a JSON store).
- Unknown operator → `kind:"query_error"` (predicate is malformed; consumer must fix before retry).

These must NOT be collapsed. Unknown field is a data-shape question; unknown operator is a predicate-validity question.

### Finding B4: StorageCapability gate sequence is orthogonal

The G1–G6 gate sequence from LAB-STORAGE-CAPABILITY-P2 and LAB-EXECUTE-QUERY-P1 is absent from this fixture. Filter evaluation and capability gating are independent concerns. A production filter evaluation would run AFTER the G1–G5 gates pass — filter semantics are gate-agnostic.

---

## Closed surfaces

| Surface | Status |
|---------|--------|
| SQL execution | Closed — no `execute_sql`, `raw_sql`, `SELECT FROM` |
| Real database connection | Closed — no `establish_connection`, `database_url`, ORM |
| StorageCapability live execution | Closed — no `IO.StorageCapability`, no effect contracts |
| Write ops / transactions | Closed — no `write_file`, `write_json`, `transaction` |
| ORM / ActiveRecord / Arel | Closed |
| OR / NOT / JOIN / aggregates | Deferred — not in KNOWN_OPS; v0 AND-only |
| Production filter runtime | Closed — `FilterEvalSim` is PROOF-LOCAL ONLY |
| Public / stable API | Closed — LAB-ONLY |

---

## Depends on

| Card | What this proof relied on |
|------|--------------------------|
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44); field access patterns |
| LAB-TC-ARRAY-P2 | `Collection[FilterPredicate]` from record-field context (19/19) |
| LAB-EXECUTE-QUERY-P1 | Inline filter array in QueryPlan (57/57); denial-as-data vocabulary |

---

## KDR 3-kind routing (filter evaluation domain)

| Kind | Consumer action | Condition |
|------|----------------|-----------|
| `rows` | Process matched rows; count > 0 | One or more rows passed all predicates |
| `empty` | Show empty state; no rows matched | Zero rows passed predicates (incl. missing field) |
| `query_error` | Fix predicate before retry | Unknown or unsupported operator |

Note: `denied` and `system_error` are not produced by filter evaluation — they belong to the StorageCapability gate sequence (LAB-EXECUTE-QUERY-P1).

---

## Next authorized routes

**For OR / NOT composition:**
- Requires explicit card extending KNOWN_OPS; semantics must be proved before use
- Boolean tree evaluation is not authorized in v0

**For numeric operators (gt_integer, lt_integer):**
- Requires type promotion in FilterPredicate (string → Integer coercion) or a typed value variant
- Deferred — not in scope for v0

**For production filter evaluation runtime:**
- FilterEvalSim is PROOF-LOCAL only; a production path requires a separate card
- Will need either: (a) Igniter VM iteration opcodes, or (b) a compiled-to-host evaluation strategy

**For rows in QueryResult:**
- Adding `rows: Collection[Map[String,String]]` or a typed Row record to `QueryResult` requires a separate card
- The `count` field in v0 proves the semantics; the row data lives in Layer C

---

*LAB-ONLY. No canon claim. No framework compat. No public API.*
