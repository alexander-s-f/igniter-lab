module Lab.TypeChecker.NestedRecordContext

-- LAB-TC-NESTED-RECORD-CONTEXT-P1: Nested record literal context propagation
-- Track: lab-typechecker-nested-record-literal-context-propagation-v0
-- Route: LAB FIX + PROOF / RUST TYPECHECKER HARDENING / NO QUERY SEMANTICS CHANGE
--
-- Closes the TypeChecker gap discovered in LAB-QUERY-PROJECTION-P1 (B9):
-- inline nested record literals inside outer record literals do not receive
-- the expected field type context.
--
-- The fix: when check_record_literal_shape encounters a field value that is a
-- RecordLiteral and the expected field type is a named record in type_shapes,
-- recurse to validate the inner shape. Bounded: one level per call depth, no
-- global inference, no unification, no retroactive symbol mutation.
--
-- Contracts (6 — all pure CORE):
--   BuildPlanInlineProjection   — inline Projection literal inside QueryPlanProjection
--   BuildPlanInlineSource       — inline QuerySource literal inside QueryPlanProjection
--   BuildPlanBothInline         — both Projection + QuerySource inline
--   BuildPlanTwoLevel           — two-level nested: inner record inside middle record
--   BuildPlanMixedRefAndInline  — outer record: some fields inline, some as refs
--   BuildNaturalInlineQuery     — full QueryPlanProjection with all records inline
--                                  (the natural projection syntax from B9 now compiles)
--
-- Closed surfaces:
--   No query semantics change; no SQL/DB/ORM; no parser change; no VM change;
--   no grammar change; no global type inference; no production runtime.
--
-- Authority: LAB-ONLY. No canon claim. No public API. No stable surface.

-- ── Types ──────────────────────────────────────────────────────────────────────

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

type QueryPlanProjection {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      Collection[OrderBy],
  limit:      Integer,
  metadata:   Map[String, String]
}

-- Two-level nesting: inner record inside a middle record inside the outer plan.
type Address {
  street: String,
  city:   String
}

type Contact {
  name:    String,
  address: Address
}

type ContactRecord {
  kind:    String,
  contact: Contact,
  active:  Bool
}

-- ── Contract 1: BuildPlanInlineProjection ─────────────────────────────────────
-- Proves the B9 gap is closed: inline Projection literal inside QueryPlanProjection.
-- Before the fix this pattern required passing projection as an input.
-- After the fix: { fields: "name,status", include_all: false } compiles inline.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildPlanInlineProjection {
  input  source   : QuerySource
  input  filters  : Collection[FilterPredicate]
  input  limit    : Integer
  input  metadata : Map[String, String]
  compute order_list = []
  compute plan = {
    kind:       "select",
    source:     source,
    projection: { fields: "name,status", include_all: false },
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanProjection
}

-- ── Contract 2: BuildPlanInlineSource ────────────────────────────────────────
-- Proves inline QuerySource literal inside QueryPlanProjection compiles.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildPlanInlineSource {
  input  projection : Projection
  input  filters    : Collection[FilterPredicate]
  input  limit      : Integer
  input  metadata   : Map[String, String]
  compute order_list = []
  compute plan = {
    kind:       "select",
    source:     { table: "users", schema: "public" },
    projection: projection,
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanProjection
}

-- ── Contract 3: BuildPlanBothInline ──────────────────────────────────────────
-- Proves both Projection and QuerySource can be inline simultaneously.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildPlanBothInline {
  input  filters  : Collection[FilterPredicate]
  input  limit    : Integer
  input  metadata : Map[String, String]
  compute order_list = []
  compute plan = {
    kind:       "select",
    source:     { table: "orders", schema: "app" },
    projection: { fields: "id,status", include_all: false },
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanProjection
}

-- ── Contract 4: BuildPlanTwoLevel ─────────────────────────────────────────────
-- Proves two-level nesting: Address inline inside Contact inline inside ContactRecord.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildPlanTwoLevel {
  input active : Bool
  compute record = {
    kind:    "contact",
    contact: {
      name:    "alice",
      address: { street: "1 Main St", city: "Westville" }
    },
    active: active
  }
  output record : ContactRecord
}

-- ── Contract 5: BuildPlanMixedRefAndInline ────────────────────────────────────
-- Proves outer record mixes inline literals and refs correctly.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildPlanMixedRefAndInline {
  input  source   : QuerySource
  input  filters  : Collection[FilterPredicate]
  input  limit    : Integer
  input  metadata : Map[String, String]
  compute order_list = []
  compute plan = {
    kind:       "select",
    source:     source,
    projection: { fields: "name", include_all: false },
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanProjection
}

-- ── Contract 6: BuildNaturalInlineQuery ───────────────────────────────────────
-- The exact "natural" source pattern from B9 that failed before the fix.
-- All nested records inline; no inputs for Projection or QuerySource.
-- Fragment: CORE (pure; no capability; no IO).

pure contract BuildNaturalInlineQuery {
  input  filters  : Collection[FilterPredicate]
  input  limit    : Integer
  input  metadata : Map[String, String]
  compute order_list = [
    { field: "name", direction: "asc" }
  ]
  compute plan = {
    kind:       "select",
    source:     { table: "users", schema: "public" },
    projection: { fields: "name,status,dept", include_all: false },
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanProjection
}
