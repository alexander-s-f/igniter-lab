# LAB-QUERY-PROJECTION-P1
## Projection and include_all row-shaping semantics over mocked rows — v0

**Track:** lab-query-projection-and-include-all-over-mocked-rows-v0
**Status:** CLOSED — PROOF COMPLETE (62/62)
**Route:** LAB PROOF / QUERY SEMANTICS / NO DB
**Date:** 2026-06-10

---

## Core formula

```
Projection v0  =  mocked rows  +  Projection{fields,include_all}
               →  shaped rows (field-subset or full row) + QueryResult
Projection v0  ≠  SQL SELECT column list  ≠  DB schema introspection
Projection v0  ≠  typed Row[T]  ≠  Collection[String] field list (deferred)
ProjectionSim  =  PROOF-LOCAL ONLY  ≠  production projection evaluation runtime
```

---

## Files

| Layer | Path | Purpose |
|-------|------|---------|
| Fixture | `igniter-view-engine/fixtures/query_execution/projection_query.ig` | 6 types, 7 pure CORE contracts |
| Proof runner | `igniter-view-engine/proofs/verify_lab_query_projection_p1.rb` | 62 checks, 10 sections |
| Lab doc | `igniter-lab/lab-docs/lang/lab-query-projection-and-include-all-over-mocked-rows-v0.md` | This file |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-QUERY-PROJECTION-P1.md` | Agent card |
| Portfolio | `igniter-lab/.agents/portfolio-index.md` | Entry #56 |

---

## Types (6)

```igniter
type Projection {
  fields:      String,
  include_all: Bool
}

type QuerySource {
  table:  String,
  schema: String
}

type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

type OrderBy {
  field:     String,
  direction: String
}

-- QueryPlanProjection: QueryPlan variant with explicit Projection input.
-- Does not mutate existing QueryPlan or QueryPlanMultiOrder from prior fixtures.
type QueryPlanProjection {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      Collection[OrderBy],
  limit:      Integer,
  metadata:   Map[String, String]
}

type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}
```

---

## Contracts (7 — all pure CORE)

| Contract | Purpose |
|---------|---------|
| `BuildIncludeAllPlan` | QueryPlanProjection with projection input; proves Projection field typed |
| `BuildFieldsProjectionPlan` | QueryPlanProjection with 2-key order; proves Collection[OrderBy] context (7th P2 confirmation) |
| `BuildSingleFieldPlan` | QueryPlanProjection with empty order; proves Collection[OrderBy] empty context |
| `BuildProjectionRowsResult` | QueryResult{kind:"rows"} for projected rows |
| `BuildProjectionEmptyResult` | QueryResult{kind:"empty"} for zero rows |
| `BuildProjectionQueryErrorResult` | QueryResult{kind:"query_error"} for malformed projection or policy violation |
| `ProjectionMetadataReader` | map_get(result.metadata, key) + or_else |

---

## v0 Projection semantics (Layer C)

### include_all

```
include_all == true   → return all row fields unchanged (full passthrough)
  subject to G5 gate: allow_include_all==false → query_error before projection
include_all == false  → parse fields as comma-separated field list
```

### fields parsing (include_all == false)

```
"name,status"        → ["name", "status"]
" name , status "    → ["name", "status"]  (whitespace stripped)
"name"               → ["name"]            (single field)
""                   → query_error         (empty field list = malformed plan)
"name,status,name"   → ["name", "status"]  (de-duplicated, first occurrence wins)
```

### Row shaping

```
field absent in row  → query_error (fail-closed; NOT denied)
duplicate fields     → de-duplicate preserving first occurrence (not query_error)
projection result    → row with exactly the de-duplicated requested fields
field order          → follows de-duplicated request order (Ruby Hash preserves insertion order ≥ 1.9)
```

### Row count invariant

Projection **does not change row count** — it shapes the fields of each row, not the set of rows.

### Pipeline position

```
G1/G2/G3 denial  →  G4 clamp  →  G5 include_all policy  →  G6 filter+order+limit  →  projection
```

Projection is the **final step** before QueryResult is constructed.

### query_error ≠ denied

Throughout the pipeline:
- Denial (kind:"denied") = G1/G2/G3 gate failures only
- query_error = malformed plan (fix before retry): empty fields, missing field, unknown direction, negative limit, bad filter op, G5 include_all policy

---

## Three-layer proof structure

### Layer A — Ruby TypeChecker

- All 7 contracts: `status: "accepted"`
- Zero `type_errors`
- `Projection.fields` type: `String`
- `Projection.include_all` type: `Bool`
- `QueryPlanProjection.projection` type: `Projection`
- `QueryPlanProjection.filters` type: `Collection[FilterPredicate]`
- `QueryPlanProjection.order` type: `Collection[OrderBy]`

**TypeChecker boundary (B9):** Nested record literals inside outer record literals do not propagate inner field type context. `{ fields: "...", include_all: false }` embedded directly in the plan record literal fails OOF-TY0 ("missing required field: kind" applied to the wrong type). Workaround: pass `projection` as an `input` to plan-building contracts. Specific projection shapes are verified at Layer B (VM inputs) and Layer C (ProjectionSim). This is the same pattern established in `execute_query_integrated.ig`.

### Layer B — Rust compiler + VM

**Compiler:** fixture compiles; SIR emitted for all contracts.

**Type tag (LAB-TC-ARRAY-P2 — 7th confirmation):**

```
BuildFieldsProjectionPlan.order_list  →  type_tag: Collection[OrderBy]
```

**VM execution — all 7 contracts:**

| Contract | Key assertion |
|---------|---------------|
| `BuildIncludeAllPlan` | kind:"select"; projection.include_all=true; projection.fields="" |
| `BuildFieldsProjectionPlan` | projection.fields="name,status"; include_all=false; order 2-key |
| `BuildSingleFieldPlan` | projection.fields="name"; include_all=false; empty order |
| `BuildProjectionRowsResult` | kind:"rows"; count:3 |
| `BuildProjectionEmptyResult` | kind:"empty"; count:0 |
| `BuildProjectionQueryErrorResult` | kind:"query_error"; count:0 |
| `ProjectionMetadataReader` | map_get hit:"eng"; miss:"not-found" |

### Layer C — Proof-local ProjectionSim

Test dataset (5 rows):

```ruby
PROJ_ROWS = [
  { 'name' => 'alice', 'status' => 'active',   'dept' => 'eng', 'score' => '10', 'role' => 'admin' },
  { 'name' => 'bob',   'status' => 'active',   'dept' => 'eng', 'score' => '20', 'role' => 'user'  },
  { 'name' => 'carol', 'status' => 'inactive', 'dept' => 'mkt', 'score' => '30', 'role' => 'user'  },
  { 'name' => 'dave',  'status' => 'active',   'dept' => 'mkt', 'score' => '40', 'role' => 'admin' },
  { 'name' => 'eve',   'status' => 'inactive', 'dept' => 'eng', 'score' => '50', 'role' => 'user'  },
]
```

Key projection results:

| Projection | Result |
|-----------|--------|
| `include_all=true` | All 5 rows, all 5 fields unchanged (identity) |
| `fields="name,status"` | All 5 rows, each with exactly `{name, status}` |
| `fields="name"` | All 5 rows, each with exactly `{name}` |
| `fields=" name , status "` | Whitespace stripped → same as `"name,status"` |
| `fields="name,status,name"` | De-duplicated → same as `"name,status"` |
| `fields=""` | `query_error` |
| `fields="name,missing_col"` | `query_error` (missing_col absent) |

Integrated pipeline (filter active + name asc + name/status projection, limit 100):
- Filtered: alice, bob, dave (active only)
- Ordered: alice, bob, dave (name asc)
- Limited: alice, bob, dave (limit 100 ≥ 3)
- Projected: `{name,status}` for each → 3 rows, 2 fields each

---

## Proof results (62/62)

| Section | n | Checks |
|---------|---|--------|
| PROJ-COMPILE | 5 | Fixture compiles; 7 contracts; Ruby TC all accepted; zero type_errors |
| PROJ-SHAPE | 7 | Projection fields/include_all typed; QueryPlanProjection.projection:Projection; filters/order Collection types; Rust SIR type_tag (7th P2) |
| PROJ-INCLUDE-ALL | 5 | include_all true returns all fields; all 5 fields per row; row count unchanged; values preserved; identity projection |
| PROJ-FIELDS | 8 | Single field; two fields; three fields; excludes non-requested; whitespace stripped; duplicate de-duplicated; row count preserved |
| PROJ-PIPELINE | 6 | Integrated pipeline rows; projected fields only; filter before projection; order before projection; empty input; include_all in pipeline |
| PROJ-POLICY | 5 | include_all+allow_false→query_error; not denied; G5 fires before projection; G1 short-circuits; query_error≠denied |
| PROJ-ERROR | 6 | Empty fields→query_error; missing field→query_error; integrated missing→query_error; query_error≠denied invariant; informative messages |
| PROJ-VM | 7 | All 7 contracts VM-executed |
| PROJ-CLOSED | 8 | No SQL/DB/ORM/optimizer/joins/writes/capability-authority/persistence |
| PROJ-GAP | 5 | Proof-local only; fields:String v0+nested-record boundary; typed Row[T] deferred; 7th P2 confirmation; no production runtime |

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | `include_all=true` → full row passthrough (identity projection); all fields returned unchanged |
| B2 | `fields` parsed as comma-split+strip in v0; whitespace in field names stripped |
| B3 | Empty field list after parsing → `query_error` (malformed plan, not a silent empty result) |
| B4 | Field absent in row → `query_error` (fail-closed); projection does not silently omit missing fields |
| B5 | Duplicate fields → de-duplicate preserving first occurrence; not an error |
| B6 | Projection does not change row count — it is a column selector, not a row filter |
| B7 | Projection applied AFTER filter → multi-order → limit (final pipeline step) |
| B8 | `include_all` policy (G5): allow_include_all=false → `query_error` (NOT `denied`); fires before projection is evaluated |
| B9 | TypeChecker boundary: nested record literals inside outer record literals do not get inner-field type context. `projection: { fields: "...", include_all: false }` fails OOF-TY0 in Ruby TC. Workaround: pass `projection` as `input`. Documented as a gap for a future TC improvement card. |
| B10 | `Collection[OrderBy]` from record-field context (LAB-TC-ARRAY-P2 — 7th confirmation): `BuildFieldsProjectionPlan.order_list` type_tag: `Collection[OrderBy]` |

---

## Closed surfaces

- SQL SELECT generation / DB column introspection: CLOSED
- ORM / ActiveRecord / Arel: CLOSED
- StorageCapability live execution (IO authority): CLOSED
- Index hints / query optimizer: CLOSED
- Joins / aggregates: CLOSED (v0 single-source)
- Write operations: CLOSED
- Typed Row[T] / schema-aware projection: DEFERRED
- Collection[String] field list grammar: DEFERRED
- Production projection runtime: CLOSED (ProjectionSim is PROOF-LOCAL ONLY)
- Public / stable API: CLOSED

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-EXECUTE-QUERY-P2 | Integrated mocked pipeline (73/73); gate pipeline; G5 include_all policy gate |
| LAB-QUERY-MULTI-ORDER-P1 | Collection[OrderBy] semantics (64/64); MultiOrderQuerySim as pipeline base |
| LAB-FILTER-EVAL-P1 | Filter predicate evaluation (50/50); Layer C mocked row evaluation pattern |
| LAB-QUERY-ORDER-LIMIT-P1 | Order/limit semantics (54/54); order-then-limit invariant |
| LAB-TC-ARRAY-P2 | `Collection[T]` from record-field context (19/19); 7th confirmation in this proof |
| LAB-TC-ARRAY-P1 | Empty array in Collection context (27/27) |
| PROP-043-P5 | `Map[String,String]` production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM `map_get`/`or_else` (48/48) |

---

## Next authorized routes

- TypeChecker nested-record-literal context propagation: separate card required (B9 boundary)
- Typed Row[T] / schema-aware projection: separate card required
- Collection[String] field list grammar: requires grammar change, separate card required
- LAB-EXECUTE-QUERY-P3: integrate projection + multi-order into unified receipt — separate card
- Production projection runtime: ProjectionSim is PROOF-LOCAL ONLY; separate card required
