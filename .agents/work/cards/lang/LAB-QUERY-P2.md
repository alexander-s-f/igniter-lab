# Card: LAB-QUERY-P2

**Category:** lang  
**Track:** lab-query-plan-record-fixture-and-pure-builder-proof-v0  
**Status:** CLOSED — PROVED  
**Gate result:** 42/42 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Prove that QueryPlan / QueryResult / QuerySource / Projection / FilterPredicate /
OrderBy can be represented and composed today as pure typed Records with
Map[String,String] metadata — no DB, no ORM, no execution authority.

Core formula locked:  
Query v0 = typed intent AST + denial-as-data + Map metadata.  
Query v0 ≠ ORM ≠ database connection ≠ persistence runtime.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-QUERY-P1 (research + design boundary) | ✅ DONE |
| PROP-043-P5 (Map[String,String] production surface + C1 fix) | ✅ DONE — 55/55 |
| LAB-VM-MAP-P1 (map_get/or_else VM runtime) | ✅ DONE — 48/48 |
| LAB-RESULT-ENVELOPE-P2 (KDR + denial-as-data cross-domain baseline) | ✅ DONE — 50/50 |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture (6 contracts, 7 types) | `fixtures/query_plan/query_plan.ig` | ✅ DONE |
| Proof runner | `proofs/verify_lab_query_p2.rb` | ✅ DONE |
| This card | `.agents/work/cards/lang/LAB-QUERY-P2.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Types Proved (7)

| Type | Key fields | Notes |
|------|-----------|-------|
| `QuerySource` | table:String, schema:String | Source identity; capability-checked at exec (v1+) |
| `Projection` | fields:String, include_all:Bool | v0 simplified: String description; Collection[String] deferred |
| `FilterPredicate` | field:String, op:String, value:String | op: eq/neq/gt/gte/lt/lte/is_null |
| `OrderBy` | field:String, direction:String | direction: asc/desc |
| `QueryPlan` | kind:String, source_table, filter_field, filter_op, filter_value, order_field, order_dir, limit:Integer, metadata:Map[String,String] | Flat for v0; Collection[FilterPredicate] deferred |
| `QueryResult` | kind:String, count:Integer, message:String, metadata:Map[String,String] | KDR convention |
| `StorageDenied` | table:String, op:String, reason:String, kind:String | Denial typed record |

**All 7 types expressible as named Records in Stage 1 today. No new grammar.**

---

## Contracts Proved (6)

| Contract | Role | Fragment |
|----------|------|---------|
| `BuildQuerySource` | QuerySource record construction | CORE |
| `BuildSelectQuery` | Full flat QueryPlan construction | CORE |
| `BuildFilteredQuery` | Simplified eq-filter plan | CORE |
| `QueryResultDenied` | Denial-as-data (QueryResult{kind:"denied"}) | CORE |
| `QueryMetadataReader` | map_get(result.metadata, key) + or_else (C1 chain) | CORE |
| `QueryMapper` | Three-layer mapper (raw context → QueryResult) | CORE |

---

## Proof Sections (42/42)

```
QPLAN-COMPILE  (4/4)  — fixture compiles; 6 contracts; SIR; no type_errors
QPLAN-TYPES    (5/5)  — type env: QueryPlan fields; Map[String,String] metadata; FilterPredicate; C1 chain
QPLAN-BUILD    (6/6)  — plan construction; QuerySource; QueryPlan; eq-filter; QueryResult
QPLAN-DENIED   (4/4)  — denial-as-data in query domain; no HTTP status field
QPLAN-MAP      (4/4)  — Map[String,String] metadata chain (Layer A + B); direct Map + field access forms
QPLAN-VM       (5/5)  — VM: QuerySource, BuildSelectQuery(kind="select"), BuildFilteredQuery(filter_op="eq"),
                         MetadataReader map_get hit "web" + or_else fallback "unknown_source"
QPLAN-ROUTE    (5/5)  — Layer C sim: rows/empty/denied/system_error/unknown-fail-closed
QPLAN-COMPARE  (4/4)  — metadata shape matches ValidationResult; no Sidekiq fields; "empty" domain-specific; KDR holds
QPLAN-CLOSED   (5/5)  — no SQL, no DB, no ORM, no stable-API claim, all-pure CORE fragment
```

---

## Key Findings

| Finding | Detail |
|---------|--------|
| Query types expressible today | All 7 types are named Records; no grammar changes needed |
| C1 chain in 4th domain | `result.metadata` → `Map[String,String]` → `map_get` → `Option[String]` → `or_else` → `String` (QueryResult input, same as vr.metadata in validation) |
| KDR convention 4th domain | QueryResult follows kind+message+metadata shape; denial-as-data holds |
| "empty" kind domain-specific | Zero rows is a distinct non-error outcome in the query domain — not present in ValidationResult/ContractResult/JobReceipt |
| All contracts CORE | All 6 contracts are `pure` → CORE fragment; no capability, no IO |
| Flat QueryPlan safe for v0 | Collection[FilterPredicate] deferred; flat embedding of filter/order sufficient for v0 proof |
| Map metadata 4th context | QueryResult.metadata joins HttpResult, JobReceipt, ValidationResult metadata chain |

---

## Two Failure Fixes (40/42 → 42/42)

| Failure | Root cause | Fix |
|---------|-----------|-----|
| QPLAN-CLOSED-01 | `SOURCE.include?('execute_sql')` — the string literal appeared in the check itself | Split: `'execut' + 'e_sql'`, `'run_qu' + 'ery('` |
| QPLAN-CLOSED-05 | `!src.include?('persistence runtime')` — fixture comment `-- != persistence runtime` triggered false positive | Changed check to: `src.include?('pure contract') && !src.include?('effect contract')` (better test: proves CORE fragment) |

**Pattern confirmed:** All SOURCE/src string checks must be split or use declaration-form checks.

---

## Gap Packet

```
proof:      lab-query-plan-record-fixture-and-pure-builder-proof / v0
status:     CLOSED — 42/42 PASS
authority:  lab_only
date:       2026-06-09

types_proved:
  QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/StorageDenied
  all expressible as named Records in Stage 1 today; no grammar changes

kdr_convention:
  domain:        query (data access)
  kind_vocab:    rows | empty | denied | query_error | system_error
  denial_kind:   denied (8th denial-as-data proof opportunity)
  metadata:      Map[String,String] — 4th context
  c1_chain:      result.metadata → Map[String,String] → map_get → Option[String] ✓

vm_executed:
  BuildQuerySource   → table="users"
  BuildSelectQuery   → kind="select"
  BuildFilteredQuery → filter_op="eq"
  QueryMetadataReader → "web" (hit) / "unknown_source" (or_else fallback)
  QueryMapper        → message="3 records found" (map_get hit)

deferred:
  Collection[FilterPredicate]: deferred to v1
  Nested named records in QueryPlan: deferred to v1
  IO.StorageCapability design: follows PROP-035 model; explicit auth needed
  JOINs: v1
  Aggregates: v1
  Write operations: v1

next_authorized:
  immediate:    IO.StorageCapability design (follows PROP-035; explicit auth needed)
  optional:     LAB-QUERY-P3 (Collection[FilterPredicate] + nested records)
  future:       PROP-045 or similar (query grammar; joins; aggregates)
```

---

## Authority

Lab-only — no canon claim, no stable surface, no framework compat.  
No production files changed. No grammar added. No VM modified.  
No SQL connection established. No database runtime.
