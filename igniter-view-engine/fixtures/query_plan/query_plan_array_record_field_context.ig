module Lab.Query.ArrayRecordFieldContextV1

-- LAB-TC-ARRAY-P2: Array literal typed from a nominal record-field context.
-- Track: lab-rust-typechecker-array-literal-record-field-context-v0
--
-- Closes the non-blocking gap left open by LAB-TC-ARRAY-P1: an intermediate
-- array-literal compute that feeds a typed record field receives contextual
-- Collection[T] type information from that field position.
--
-- P1 closed (output context):
--   compute filters = [...]
--   output filters : Collection[FilterPredicate]
--
-- P2 target (record-field context):
--   compute filters = [...]
--   compute plan = { ..., filters: filters, ... }
--   output plan : QueryPlan          -- QueryPlan.filters : Collection[FilterPredicate]
--
-- Mechanism: the TypeChecker pre-scans RecordLiteral computes whose declared
-- output type is a named record. For each field that is a bare Ref to another
-- compute node, if the record type declares that field as Collection[T], the
-- referenced compute node gets element hint T. Because `filters` is processed
-- before `plan` in dependency order, the array-literal node is upgraded to
-- Collection[T] in place — no retroactive symbol mutation, no global inference.
--
-- Positive contracts only — all must compile clean. Negative cases
-- (missing/extra/wrong-typed fields, mixed element shapes) are exercised as
-- inline fail-closed sources in the proof runner.
--
-- Core formula:
--   record field `f : Collection[T]` + `f: <array-literal-ref>` -> Collection[T]
--   (contextual, local, fail-closed; no global unification)
--   All contracts pure -> CORE. No IO. No StorageCapability.
--
-- Depends: LAB-TC-ARRAY-P1 (output-context array typing), LAB-QUERY-P3,
--          LAB-RACK-P13 (RecordLiteral nominal upgrade), LAB-RECORD-VM-P3,
--          LAB-MAP-RUST-P1, PROP-043-P5, LAB-STORAGE-CAPABILITY-P2.
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

-- ── Contract 1: BuildInlineSelectPlan ────────────────────────────────────────
-- The headline P2 case. `filters` is an intermediate array-literal compute,
-- then embedded into QueryPlan.filters. In P1 the `filters` node typed Unknown
-- (data preserved, type metadata lost). With P2 the QueryPlan.filters field
-- (Collection[FilterPredicate]) supplies the context, so the `filters` node
-- types as Collection[FilterPredicate] and `plan` upgrades to QueryPlan.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildInlineSelectPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  order      : OrderBy
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute filters = [
    { field: "status", op: "eq", value: "active" },
    { field: "role",   op: "eq", value: "admin"  }
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

-- ── Contract 2: BuildEmptyFilterPlan ─────────────────────────────────────────
-- Empty intermediate array typed from record-field context. The empty literal
-- is accepted because QueryPlan.filters supplies the expected element type.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildEmptyFilterPlan {
  input  source     : QuerySource
  input  projection : Projection
  input  order      : OrderBy
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute filters = []
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
