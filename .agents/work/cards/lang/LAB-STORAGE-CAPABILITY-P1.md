# Card: LAB-STORAGE-CAPABILITY-P1

**Category:** lang  
**Track:** lab-storage-capability-query-execution-boundary-design-v0  
**Status:** CLOSED — DESIGN COMPLETE  
**Gate result:** design-locked; no proof runner  
**Date closed:** 2026-06-09  
**Route:** DESIGN / LAB-ONLY

---

## Goal

Design the `IO.StorageCapability` boundary for future mocked query execution:
allowed sources, allowed ops, row limit/budget, read/write split, denial-as-data,
and receipt shape.

Still closed: real DB connection; SQL execution; ORM; migrations; transactions;
persistence runtime; public data API.

---

## Depends On

| Card | Status |
|------|--------|
| PROP-035 (effect surface + IO.NetworkCapability grammar) | ✅ AUTHORED |
| LAB-QUERY-P1 (data-access boundary research) | ✅ DONE |
| LAB-QUERY-P2 (QueryPlan fixture + proof — 42/42) | ✅ DONE |
| LAB-CONCURRENCY-P4 (receipt pattern; 6-gate policy sequence) | ✅ DONE |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Design doc | `lab-docs/lang/lab-storage-capability-query-execution-boundary-design-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## IO.StorageCapability Schema (v0)

```json
{
  "capability_id":     "storage-read-users-v0",
  "resource_type":     "storage",
  "allowed_sources":   ["users", "posts", "sessions"],
  "allowed_ops":       ["read"],
  "row_limit":         1000,
  "allow_include_all": false,
  "read_allowed":      true,
  "write_allowed":     false,
  "deny_reason":       ""
}
```

---

## Structural Parallel to IO.NetworkCapability

| NetworkCapability | StorageCapability | Mapping |
|------------------|-----------------|--------|
| `allowed_hosts: [String]` | `allowed_sources: [String]` | Table names; empty = deny all (fail-closed) |
| `allowed_port_ranges: [{min,max}]` | `allowed_ops: [String]` | ["read"] in v0; "write" deferred |
| `connect_allowed: Bool` | `read_allowed: Bool` | Master read gate |
| `listen_allowed: Bool` | `write_allowed: Bool` | Master write gate (always false in v0) |
| *(n/a)* | `row_limit: Integer` | Safety clamp; 0 = deny all rows |
| *(n/a)* | `allow_include_all: Bool` | SELECT * gate |
| *(n/a)* | `deny_reason: String` | Surfaced in QueryResult.message |

---

## Denial-as-Data Gate Sequence (6 Gates)

| Gate | Check | Fail outcome |
|------|-------|-------------|
| G1 | `plan.source_table` in `allowed_sources`? (empty = deny all) | `QueryResult{kind:"denied"}` |
| G2 | `"read"` in `allowed_ops`? | `QueryResult{kind:"denied"}` |
| G3 | `cap.read_allowed == true`? | `QueryResult{kind:"denied"}` |
| G4 | `plan.limit > cap.row_limit`? | Clamp to `row_limit` *(no denial)* |
| G5 | `include_all` plan + `!allow_include_all`? | `QueryResult{kind:"query_error"}` |
| G6 | Execute (mocked in v0) | `QueryResult{kind:"rows"\|"empty"\|"system_error"}` |

**Denial invariant:** All `IO.StorageCapability` denials flow as `QueryResult{kind:"denied"}`.
No exception is raised. No `raise`. Consumer branches on `result.kind`.

**G4 note:** Row limit is a clamp, not a denial. `effective_limit = min(plan.limit, cap.row_limit)`.
Receipt records `row_limit_clamped: true` if clamping occurred.

**G5 note:** `include_all` on a restricted capability is a plan-formation error → `"query_error"`,
not `"denied"`. Consumer must fix the plan.

---

## QueryExecutionReceipt Shape

```
QueryExecutionReceipt {
  cap_id:            String,              -- from capability.capability_id
  plan_kind:         String,              -- from QueryPlan.kind
  source_table:      String,              -- from QueryPlan.source_table
  op_requested:      String,              -- "read" in v0
  cap_checked:       Bool,
  cap_granted:       Bool,               -- false = denied at some gate
  denial_gate:       String,              -- "G1"..."G5" or "" if granted
  deny_reason:       String,
  plan_limit:        Integer,
  row_limit_cap:     Integer,             -- from capability.row_limit
  effective_limit:   Integer,             -- min(plan_limit, row_limit_cap)
  row_limit_clamped: Bool,
  rows_returned:     Integer,
  result_kind:       String,              -- from QueryResult.kind
  metadata:          Map[String, String]
}
```

**Receipt is evidence only.** Does not re-authorize subsequent executions.
Same invariant as `PolicySchedulingReceipt` (LAB-CONCURRENCY-P4) and `AppendReceipt` (PROP-008).

---

## Future ExecuteQuery Effect Contract Form

*Not implemented today. Design target only.*

```igniter
-- Requires PROP-035 effect grammar; Stage 2+
effect contract ExecuteQuery {
  capability storage: IO.StorageCapability
  effect read_from_storage using storage
  input  plan   : QueryPlan
  output result : QueryResult
}
```

---

## Fragment Classification

| Contract | Fragment | Status |
|----------|---------|--------|
| BuildSelectQuery, BuildFilteredQuery, QueryResultDenied, etc. | CORE | Proved in LAB-QUERY-P2; pure; no capability |
| `ExecuteQuery` (future) | ESCAPE → STORAGE | ESCAPE is the coarse label; refines to STORAGE when ch4 extended (Stage 2+) |

---

## OOF-STORE Candidates

| Code | Trigger | Priority | Status |
|------|---------|---------|--------|
| OOF-STORE1 | Dynamic source name construction | High | Candidate — not active |
| OOF-STORE2 | Write op on read-only capability | High | Candidate — not active |
| OOF-STORE3 | Source not in `allowed_sources` (static) | Medium | Candidate — not active |
| OOF-STORE4 | `include_all` plan on cap with `allow_include_all: false` | Medium | Candidate — not active |
| OOF-STORE5 | `row_limit: 0` misconfig (always clamps to 0 = deny all rows) | Low | Candidate — not active |

---

## Closed Surfaces

### Permanently closed

| Surface | Status |
|---------|--------|
| Real DB connection | CLOSED — no auth path |
| SQL execution | CLOSED — no auth path |
| ORM / ActiveRecord | PERMANENTLY CLOSED |
| Schema migrations | CLOSED — no auth path |
| Transactions | CLOSED — no auth path |
| Persistence runtime | CLOSED — no auth path |
| Public data API | CLOSED — explicit auth needed |

### Deferred

| Surface | Version |
|---------|--------|
| Write operations | v1 |
| Collection[FilterPredicate] in QueryPlan | v1 |
| JOINs, aggregates | v1 |
| StorageCapability delegation algebra | v1 |
| STORAGE fragment class (ch4 extension) | Stage 2+ |
| PROP-035 grammar implementation | Stage 2+ |

---

## Design Decisions (10)

| # | Decision | Status |
|---|----------|--------|
| D1 | `allowed_sources` fail-closed (empty = deny all) | ✅ LOCKED |
| D2 | `allowed_ops: ["read"]` only; write deferred | ✅ LOCKED |
| D3 | Row limit clamps, does not deny | ✅ LOCKED |
| D4 | `include_all` violation → `"query_error"` (not `"denied"`) | ✅ LOCKED |
| D5 | `read_allowed/write_allowed` are master gates (evaluated after source/op) | ✅ LOCKED |
| D6 | `deny_reason` surfaced in `QueryResult.message` | ✅ LOCKED |
| D7 | Receipt is evidence-only; does not re-authorize | ✅ LOCKED |
| D8 | ExecuteQuery is ESCAPE (not STORAGE) in v0 | ✅ LOCKED |
| D9 | No delegation algebra in v0 (single flat capability) | ✅ LOCKED |
| D10 | No grammar changes today; PROP-035 required first | ✅ LOCKED |

---

## Gap Packet

```
design:    lab-storage-capability-query-execution-boundary / v0
status:    CLOSED — design-locked; no proof runner
authority: lab_only
date:      2026-06-09

capability_schema:
  allowed_sources:   [String]   -- table names; fail-closed
  allowed_ops:       [String]   -- ["read"] in v0
  row_limit:         Integer    -- clamp safety cap
  allow_include_all: Bool
  read_allowed:      Bool
  write_allowed:     Bool (always false in v0)
  deny_reason:       String

gate_sequence: G1 source / G2 op / G3 read_allowed / G4 clamp / G5 include_all / G6 execute

receipt: cap_id + plan_kind + source_table + op_requested + cap_checked + cap_granted +
         denial_gate + deny_reason + plan_limit + row_limit_cap + effective_limit +
         row_limit_clamped + rows_returned + result_kind + metadata

fragment: plan-building=CORE; ExecuteQuery=ESCAPE->STORAGE (Stage 2+)

oof_candidates: OOF-STORE1..5 (not active)

next_authorized:
  immediate:   LAB-QUERY-P3 (Collection[FilterPredicate] if Collection[NamedRecord] proved)
  design_only: PROP-046 (IO.StorageCapability grammar proposal)
  deferred:    LAB-STORAGE-CAPABILITY-P2 (PROP-035 grammar impl required)
```

---

## Authority

Lab-only — no canon claim, no stable surface, no framework compat.  
No production files changed. No grammar added. No VM modified.  
No SQL connection established. No database runtime.  
No `ExecuteQuery` contract written. No `IO.StorageCapability` grammar introduced.
