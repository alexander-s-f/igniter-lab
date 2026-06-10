# LAB-QUERY-PROJECTION-P1

**Card:** LAB-QUERY-PROJECTION-P1
**Track:** lab-query-projection-and-include-all-over-mocked-rows-v0
**Status:** CLOSED — PROOF COMPLETE (62/62)
**Route:** LAB PROOF / QUERY SEMANTICS / NO DB
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Define and prove proof-local projection semantics for `QueryPlan.projection` over mocked rows. Given a filtered/ordered/limited row set, what does `Projection` do to each row?

Core formula:
```
Projection v0  =  mocked rows  +  Projection{fields,include_all}
               →  shaped rows (field-subset or full row) + QueryResult
Projection v0  ≠  SQL SELECT column list  ≠  DB schema introspection
ProjectionSim  =  PROOF-LOCAL ONLY  ≠  production projection evaluation runtime
```

---

## Explicit answers (from card requirements)

1. **include_all true**: Return all row fields unchanged (full passthrough — identity projection)
2. **include_all false**: Use `fields` as comma-separated explicit field list
3. **fields parsing v0**: `split(",").map(&:strip).reject(&:empty?)`
4. **empty fields**: `query_error` (accidental empty projection = malformed plan)
5. **missing field in row**: `query_error` (fail-closed)
6. **duplicate field**: de-duplicate preserving first occurrence (not `query_error`)
7. **projection after filter/order/limit**: YES — final pipeline step
8. **projection changes row count**: NO
9. **include_all policy**: `allow_include_all=false` → `query_error` (NOT `denied`)
10. **opens SQL/DB/ORM/runtime**: NO

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-EXECUTE-QUERY-P2 | Integrated mocked pipeline (73/73); G5 include_all policy gate |
| LAB-QUERY-MULTI-ORDER-P1 | Collection[OrderBy] semantics (64/64); MultiOrderQuerySim pipeline base |
| LAB-FILTER-EVAL-P1 | Filter predicate evaluation (50/50) |
| LAB-QUERY-ORDER-LIMIT-P1 | Order/limit semantics (54/54) |
| LAB-TC-ARRAY-P2 | `Collection[T]` from record-field context (19/19); 7th confirmation in this proof |
| LAB-TC-ARRAY-P1 | Empty array in Collection context (27/27) |
| PROP-043-P5 | `Map[String,String]` production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM `map_get`/`or_else` (48/48) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/query_execution/projection_query.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_query_projection_p1.rb` | DONE (62/62) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-query-projection-and-include-all-over-mocked-rows-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-QUERY-PROJECTION-P1.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (62/62)

| Section | n | Checks |
|---------|---|--------|
| PROJ-COMPILE | 5 | Fixture compiles; 7 contracts; Ruby TC all accepted; zero type_errors |
| PROJ-SHAPE | 7 | Projection fields/include_all; QueryPlanProjection.projection:Projection; filters/order Collection types; Rust SIR type_tag (7th P2) |
| PROJ-INCLUDE-ALL | 5 | include_all true: all fields, row count unchanged, identity projection |
| PROJ-FIELDS | 8 | Single/multi/three field; excludes non-requested; whitespace; duplicate dedup; row count |
| PROJ-PIPELINE | 6 | Integrated pipeline rows; field shaping; filter/order before; empty input; include_all |
| PROJ-POLICY | 5 | include_all+allow_false→query_error; not denied; G5 before projection; G1 short-circuits |
| PROJ-ERROR | 6 | Empty fields; missing field; integrated missing; query_error≠denied; informative messages |
| PROJ-VM | 7 | All 7 contracts VM-executed |
| PROJ-CLOSED | 8 | No SQL/DB/ORM/optimizer/joins/writes/capability/persistence |
| PROJ-GAP | 5 | Proof-local only; fields:String+nested-record boundary; typed Row[T] deferred; 7th P2 |

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

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | `include_all=true` → full row passthrough (identity projection) |
| B2 | `fields` parsed as comma-split+strip in v0 |
| B3 | Empty field list after parsing → `query_error` (malformed plan) |
| B4 | Field absent in row → `query_error` (fail-closed) |
| B5 | Duplicate fields → de-duplicate preserving first occurrence |
| B6 | Projection does not change row count |
| B7 | Projection applied AFTER filter → multi-order → limit |
| B8 | G5 include_all policy → `query_error` (NOT `denied`) |
| B9 | TypeChecker boundary: nested record literals inside outer record literals do not get inner-field type context (`projection: { fields: "...", include_all: false }` fails OOF-TY0). Workaround: pass `projection` as `input`. Documents a gap for future TC improvement. |
| B10 | `Collection[OrderBy]` from record-field context (LAB-TC-ARRAY-P2 — 7th confirmation) |

---

## Next authorized

- TypeChecker nested-record-literal context propagation: separate card required (B9)
- Typed Row[T] / schema-aware projection: separate card required
- Collection[String] field list grammar: requires grammar change, separate card required
- LAB-EXECUTE-QUERY-P3: integrate projection + multi-order into unified receipt — separate card
- Production projection runtime: ProjectionSim is PROOF-LOCAL ONLY; separate card required
