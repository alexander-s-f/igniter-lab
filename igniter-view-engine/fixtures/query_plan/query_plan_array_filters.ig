module Lab.Query.ArrayFilterBuilderV1

-- LAB-TC-ARRAY-P1: Array literal in typed Collection[T] context proof.
-- Track: lab-rust-typechecker-array-literal-collection-context-v0
--
-- Closes the LAB-QUERY-P3 boundary finding B1: the Rust TypeChecker rejected
-- direct array literal construction ([f1, f2]) with OOF-TY0
-- "Unsupported expression kind: array_literal", forcing the workaround of
-- passing `filters: Collection[FilterPredicate]` as an external input.
--
-- This fixture proves the target ergonomic path now compiles in the Rust
-- pipeline (compiler + VM):
--
--   compute filters = [
--     { field: "status", op: "eq", value: "active" },
--     { field: "role",   op: "eq", value: "admin"  }
--   ]
--   output filters : Collection[FilterPredicate]
--
-- Behavior is CONTEXTUAL: an array literal is typed against the declared
-- Collection[T] output annotation (analogous to the RecordLiteral nominal
-- upgrade, LAB-RACK-P13). A free-standing array literal with no Collection
-- output hint resolves to Unknown (no fabricated type, no OOF-TY0).
--
-- Positive contracts only — all must compile clean. Negative cases
-- (missing/extra/wrong-typed fields, mixed element shapes) are exercised as
-- inline fail-closed sources in the proof runner, since they must NOT compile.
--
-- Core formula:
--   [RecordLiteral, ...] : Collection[T]  (contextual, T = named record element)
--   array literal != list library, != generic collection design, != runtime IO.
--   All contracts pure -> CORE. No IO. No StorageCapability.
--
-- Depends: LAB-QUERY-P3 (Collection[FilterPredicate] as input; array gap B1),
--          PROP-043-P5 (Map[String,String] surface),
--          LAB-MAP-RUST-P1 (Rust Map type IR), LAB-RECORD-VM-P3 (nested records),
--          LAB-STORAGE-CAPABILITY-P2 (query domain boundary).
--
-- Authority: LAB-ONLY. No canon claim. No SQL. No DB. No ORM. No framework
-- compat. No stable surface. No public API. No StorageCapability execution.

-- ── Types (carried from LAB-QUERY-P3 query_plan_nested.ig) ───────────────────────

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

type OrderBy {
  field:     String,
  direction: String
}

type QueryPlan {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      OrderBy,
  limit:      Integer,
  metadata:   Map[String, String]
}

-- ── Contract 1: InlineFilterCollection ───────────────────────────────────────
-- Proves the headline path: an array of inline RecordLiteral elements is typed
-- as Collection[FilterPredicate] against the declared output annotation.
-- The compute node AND the output port carry Collection[FilterPredicate] in the
-- SIR type metadata. Fragment: CORE (pure; no capability; no IO).

pure contract InlineFilterCollection {
  compute filters = [
    { field: "status", op: "eq", value: "active" },
    { field: "role",   op: "eq", value: "admin"  }
  ]
  output filters : Collection[FilterPredicate]
}

-- ── Contract 2: InlineFilterRefs ─────────────────────────────────────────────
-- Proves array literal of Ref elements (already-typed FilterPredicate inputs)
-- types as Collection[FilterPredicate]. This is the QPLAN3-ARRAY Layer A case,
-- now also accepted by the Rust TypeChecker (Layer B). Fragment: CORE.

pure contract InlineFilterRefs {
  input  f1 : FilterPredicate
  input  f2 : FilterPredicate
  compute filters = [f1, f2]
  output filters : Collection[FilterPredicate]
}

-- ── Contract 3: EmptyFilterCollection ────────────────────────────────────────
-- Empty array decision: an empty literal is accepted ONLY with a contextual
-- Collection[T] type. Zero elements -> zero element checks -> upgrade to
-- Collection[FilterPredicate]. Without contextual type an array literal stays
-- Unknown (proved by the free-standing case in the runner). Fragment: CORE.

pure contract EmptyFilterCollection {
  compute filters = []
  output filters : Collection[FilterPredicate]
}

-- ── Contract 4: BuildInlineSelectPlan ────────────────────────────────────────
-- Proves a full QueryPlan can be constructed with inline filters instead of the
-- LAB-QUERY-P3 input workaround. `filters` is computed as an inline array
-- literal, then embedded as the QueryPlan.filters field. The plan RecordLiteral
-- upgrades to QueryPlan (LAB-RACK-P13). Compiles clean; VM round-trips the
-- nested filter collection. Fragment: CORE (pure; no capability; no IO).
--
-- Note: the intermediate `filters` node feeds a record FIELD position (not a
-- Collection output), so its static type metadata is Unknown — contextual
-- typing fires at Collection[T] OUTPUT positions in v0. The collection data is
-- preserved through compile + VM regardless; record-field-position contextual
-- typing is a documented follow-up (broader collection typing), not required to
-- close the P3 workaround.

pure contract BuildInlineSelectPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  order      : OrderBy
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute filters = [
    { field: "status", op: "eq", value: "active" },
    { field: "age",    op: "gt", value: "18"     }
  ]
  compute plan = {
    kind:       "select",
    source:     source,
    projection: projection,
    filters:    filters,
    order:      order,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlan
}
