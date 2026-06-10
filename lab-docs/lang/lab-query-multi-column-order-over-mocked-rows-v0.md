# LAB-QUERY-MULTI-ORDER-P1
## Multi-column order semantics over mocked rows — v0

**Track:** lab-query-multi-column-order-over-mocked-rows-v0
**Status:** CLOSED — PROOF COMPLETE (64/64)
**Route:** LAB PROOF / QUERY SEMANTICS / NO DB
**Date:** 2026-06-10

---

## Core formula

```
MultiOrder v0  =  mocked rows  +  Collection[OrderBy]  +  limit
               →  deterministic stable multi-column ordered rows + QueryResult
MultiOrder v0  ≠  sql order-by clause  ≠  DB runtime  ≠  ORM  ≠  index-backed sorting
MultiOrder v0  ≠  StorageCapability row-limit gate
MultiOrderSim  =  PROOF-LOCAL ONLY  ≠  production multi-order evaluation runtime
```

---

## Files

| Layer | Path | Purpose |
|-------|------|---------|
| Fixture | `igniter-view-engine/fixtures/query_execution/multi_order_query.ig` | 6 types, 7 pure CORE contracts |
| Proof runner | `igniter-view-engine/proofs/verify_lab_query_multi_order_p1.rb` | 64 checks, 11 sections |
| Lab doc | `igniter-lab/lab-docs/lang/lab-query-multi-column-order-over-mocked-rows-v0.md` | This file |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-QUERY-MULTI-ORDER-P1.md` | Agent card |
| Portfolio | `igniter-lab/.agents/portfolio-index.md` | Entry #55 |

---

## Types (6)

```igniter
type OrderBy {
  field:     String,
  direction: String
}

type QuerySource {
  table:  String,
  schema: String
}

type Projection {
  fields:      String,
  include_all: Bool
}

type FilterPredicate {
  field: String,
  op:    String,
  value: String
}

-- QueryPlanMultiOrder: QueryPlan variant with order: Collection[OrderBy].
-- Does not mutate the existing single-OrderBy QueryPlan from prior fixtures.
type QueryPlanMultiOrder {
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
| `BuildMultiOrderPlan` | QueryPlanMultiOrder with 2-key Collection[OrderBy]; dept+name asc |
| `BuildEmptyOrderPlan` | QueryPlanMultiOrder with empty Collection[OrderBy] |
| `BuildThreeKeyOrderPlan` | QueryPlanMultiOrder with 3-key Collection[OrderBy]; dept asc / level desc / name asc |
| `BuildMultiOrderRowsResult` | QueryResult{kind:"rows"} for non-empty ordered result |
| `BuildMultiOrderEmptyResult` | QueryResult{kind:"empty"} for zero rows |
| `BuildMultiOrderQueryErrorResult` | QueryResult{kind:"query_error"} for malformed order specification |
| `MultiOrderMetadataReader` | map_get(result.metadata, key) + or_else on QueryResult.metadata |

---

## v0 Multi-order semantics (Layer C)

### Empty list

```
order = []  →  preserve input order (no-op)
```

Empty `Collection[OrderBy]` is valid and means "no sorting" — unlike empty direction in an entry.

### Per-entry validation

```
entry.direction == ""           →  query_error
  (each entry is an explicit step; direction is required)
entry.direction not in [asc,desc]  →  query_error  (NOT denied)
entry.field absent in any row   →  query_error  (NOT denied)
```

The distinction from single-order P1: in P1 `direction: ""` meant "preserve input order" for the single key. In multi-order each entry is an explicit sort step — an empty direction is ambiguous/malformed and rejected as `query_error`.

### Priority order

Sort keys applied left to right: first entry = primary key, second = secondary key, etc.

- Primary key determines group boundaries
- Secondary key resolves primary-key ties
- Tertiary key resolves secondary-key ties
- All remaining equal keys → input order preserved (stable sort invariant)

### Stable sort

Equal values at all specified sort keys → original input order preserved.
Implementation: integer row index as final tiebreaker in `sort_by`.

```ruby
sorted = rows.each_with_index.sort_by do |row, i|
  keys = order_list.map { |ob| ... }
  keys + [i]          # i ensures deterministic input-order tie resolution
end.map(&:first)
```

### Per-column direction: ReverseComparable

`asc` columns: wrap value as plain String for lexicographic comparison.
`desc` columns: wrap value in `ReverseComparable` which reverses `<=>`.

All rows at a given sort position produce the same type (all String or all ReverseComparable), so `Array#<=>` is correct throughout the composite key.

```ruby
class ReverseComparable
  include Comparable
  attr_reader :val
  def initialize(val); @val = val.to_s; end
  def <=>(other); other.val.to_s <=> @val; end
end
```

### Limit

Limit applied AFTER all ordering (order-then-limit invariant):

```
limit > 0   →  first(effective_limit) rows of sorted result
limit == 0  →  kind:"empty"
limit < 0   →  kind:"query_error" (NOT "denied")
```

### query_error ≠ denied

Throughout the pipeline — unknown direction, missing field, empty direction, negative limit, bad filter op — all produce `kind:"query_error"`, never `kind:"denied"`.

Denial (kind:"denied") is reserved for StorageCapability gate failures (G1/G2/G3).

---

## Three-layer proof structure

### Layer A — Ruby TypeChecker

- All 7 contracts: `status: "accepted"`
- Zero `type_errors` across all contracts
- `QueryPlanMultiOrder.order` type: `Collection[OrderBy]` (confirmed via `type_env`)
- `QueryPlanMultiOrder.filters` type: `Collection[FilterPredicate]`
- `QueryPlanMultiOrder.limit` type: `Integer`
- `OrderBy` has 2 fields: `field` and `direction`

### Layer B — Rust compiler + VM

**Compiler:** fixture compiles; SIR emitted for all contracts.

**Type tag (LAB-TC-ARRAY-P2 — 6th confirmation):**

```
BuildMultiOrderPlan.order_list  →  type_tag: Collection[OrderBy]
```

`compute order_list = [{ field: "dept", direction: "asc" }, ...]` is typed `Collection[OrderBy]` from the record-field context of `QueryPlanMultiOrder.order`. This is the 6th confirmation of the LAB-TC-ARRAY-P2 mechanism (inline array typed from containing record field).

**VM execution — all 7 contracts:**

| Contract | Key assertion |
|---------|---------------|
| `BuildMultiOrderPlan` | kind:"select"; order array of 2 entries; first field:"dept" |
| `BuildEmptyOrderPlan` | kind:"select"; order is empty array |
| `BuildThreeKeyOrderPlan` | order array of 3 entries; first field:"dept"; second direction:"desc" |
| `BuildMultiOrderRowsResult` | kind:"rows"; count:3 |
| `BuildMultiOrderEmptyResult` | kind:"empty"; count:0 |
| `BuildMultiOrderQueryErrorResult` | kind:"query_error"; count:0 |
| `MultiOrderMetadataReader` | map_get hit:"eng"; miss:"not-found" |

### Layer C — Proof-local MultiOrderSim

Test dataset (5 rows):

```ruby
MULTI_ROWS = [
  { 'dept' => 'eng',  'level' => 'senior', 'name' => 'charlie', 'score' => '30', 'status' => 'active'   },
  { 'dept' => 'eng',  'level' => 'junior', 'name' => 'alice',   'score' => '10', 'status' => 'active'   },
  { 'dept' => 'mkt',  'level' => 'senior', 'name' => 'dave',    'score' => '40', 'status' => 'inactive' },
  { 'dept' => 'eng',  'level' => 'senior', 'name' => 'bob',     'score' => '20', 'status' => 'active'   },
  { 'dept' => 'mkt',  'level' => 'junior', 'name' => 'eve',     'score' => '50', 'status' => 'inactive' },
]
```

Pre-computed sort results:

| Order | Result |
|-------|--------|
| `[]` (empty) | charlie, alice, dave, bob, eve (input order) |
| `[name asc]` | alice, bob, charlie, dave, eve |
| `[name desc]` | eve, dave, charlie, bob, alice |
| `[dept asc, name asc]` | alice, bob, charlie, dave, eve |
| `[dept asc, level desc]` | charlie, bob, alice, dave, eve |
| `[dept desc, level asc]` | eve, dave, alice, charlie, bob |
| `[dept asc, level desc, name asc]` | bob, charlie, alice, dave, eve |
| `[dept asc, level asc]` | alice, charlie, bob, eve, dave |

Stable sort with `EQUAL_KEY_ROWS` (dept=eng, level=senior, name=zoe for all 3): idx=0, idx=1, idx=2 (input order preserved).

Three-key + limit 2 → bob, charlie (limit applied after sort).

---

## Proof results (64/64)

| Section | n | Checks |
|---------|---|--------|
| MORDER-COMPILE | 5 | Fixture compiles; 7 contracts; Ruby TC all accepted; zero type_errors |
| MORDER-SHAPE | 6 | Collection[OrderBy]; Collection[FilterPredicate]; limit Integer; OrderBy 2 fields; QueryResult 4 fields; Rust SIR type_tag |
| MORDER-SINGLE | 5 | Empty list preserves input order; single name asc; single name desc; P1 backward compat; empty list count |
| MORDER-MULTI | 8 | Two-key asc/asc; asc/desc; desc/asc; three-key; primary determines group; secondary resolves ties; tertiary resolves secondary ties; three-key count invariant |
| MORDER-STABLE | 5 | All-equal keys → input order; equal primary → secondary correct; equal primary+secondary → tertiary correct; equal all → input order; two-key stable ordering |
| MORDER-LIMIT | 4 | Limit 2 after three-key; limit==0 → empty; limit<0 → query_error; limit>rows → all |
| MORDER-ERROR | 5 | Unknown direction → query_error; missing field → query_error; empty direction → query_error; query_error≠denied; empty dir ≠ unknown dir messages |
| MORDER-INTEGRATED | 6 | Full pipeline rows; G1 denial short-circuits; filter before order; empty order preserves filtered order; limit after order; G4 clamp with multi-order |
| MORDER-VM | 7 | All 7 contracts VM-executed |
| MORDER-CLOSED | 8 | No SQL/DB/ORM/index-usage/joins/writes/capability-authority/persistence at any layer |
| MORDER-GAP | 5 | Proof-local only; numeric/date deferred; P1 backward compat; 6th P2 confirmation; no production runtime |

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Empty `Collection[OrderBy]` → preserve input order (no-op); valid, not an error |
| B2 | Empty direction in multi-order entry → `query_error`; differs from single-order P1 where empty direction = "no sort". Each multi-order entry is an explicit step — direction is required |
| B3 | `ReverseComparable` pattern: wrap desc values in a class whose `<=>` reverses comparison. All rows at a given position produce the same type (all String or all ReverseComparable), so `Array#<=>` is safe throughout composite key |
| B4 | Integer index tiebreaker in `sort_by` ensures input-order preservation for equal keys (stable sort invariant) |
| B5 | `query_error` ≠ `denied` invariant confirmed for all malformed-order paths: unknown direction, missing field, empty direction |
| B6 | `Collection[OrderBy]` from record-field context (LAB-TC-ARRAY-P2 — 6th confirmation); `BuildMultiOrderPlan.order_list` type_tag: `Collection[OrderBy]` |
| B7 | `QueryPlanMultiOrder` is a new type — does not mutate the existing `QueryPlan` from prior fixtures |
| B8 | Order-then-limit invariant holds for multi-column ordering: limit applied AFTER all sort keys resolved |

---

## Closed surfaces

- SQL query execution / DB runtime: CLOSED
- ORM / ActiveRecord / Arel: CLOSED
- StorageCapability live execution (IO authority): CLOSED
- Index hints / query optimizer usage: CLOSED
- Joins / aggregates: DEFERRED (v0 is single-source only)
- Write operations: CLOSED
- Numeric / date / locale-aware ordering: DEFERRED (v0 is lexicographic String only)
- Collation-aware ordering: DEFERRED
- Multi-source joins: DEFERRED
- Production multi-order runtime: CLOSED (MultiOrderSim is PROOF-LOCAL ONLY)
- Public / stable API: CLOSED

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-ORDER-LIMIT-P1 | Single-key order/limit semantics (54/54); order-then-limit invariant; stable sort |
| LAB-EXECUTE-QUERY-P2 | Integrated mocked pipeline pattern (73/73); gate pipeline; IntegratedQuerySim design |
| LAB-FILTER-EVAL-P1 | Filter predicate evaluation (50/50); Layer C mocked row evaluation pattern |
| LAB-TC-ARRAY-P2 | `Collection[T]` from record-field context (19/19); 6th confirmation in this proof |
| LAB-TC-ARRAY-P1 | Empty array in Collection context (27/27) |
| PROP-043-P5 | `Map[String,String]` production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM `map_get`/`or_else` (48/48) |

---

## Next authorized routes

- Production multi-order runtime: MultiOrderSim is PROOF-LOCAL ONLY; separate card required
- Numeric/date ordering: string → typed coercion or typed Row record — deferred v0
- Collation-aware ordering: separate card required
- Multi-source ordering: joins deferred; separate card required
- Integrated multi-order with QueryExecutionReceipt: extend LAB-EXECUTE-QUERY-P2 — separate card required
