# Lab: IO.StorageCapability — Query Execution Boundary Design

**Track:** lab-storage-capability-query-execution-boundary-design-v0  
**Card:** LAB-STORAGE-CAPABILITY-P1  
**Status:** DESIGN COMPLETE — no proof runner; design-locked  
**Date:** 2026-06-09  
**Route:** DESIGN / LAB-ONLY

---

## Purpose

Define the `IO.StorageCapability` boundary for future mocked query execution.
This document specifies:

- The `IO.StorageCapability` JSON schema (parallel to `IO.NetworkCapability`)
- The denial-as-data gate sequence (6 ordered gates)
- The `QueryExecutionReceipt` shape (telemetry-only; no authority)
- The future `ExecuteQuery` effect contract form (PROP-035 grammar)
- The fragment classification for execution contracts
- The OOF-STORE diagnostic candidates
- What remains permanently closed

This is a **design document only.** No fixture is written. No proof runner is written.
No `IO.StorageCapability` is injected into production grammar. No DB connection is opened.

---

## Dependency Map

| Dependency | Status | What it provides |
|-----------|--------|-----------------|
| PROP-035 (effect surface + IO.NetworkCapability grammar) | ✅ AUTHORED | `capability name: Type` + `effect name using cap_ref` grammar productions; `IO.*` opaque sentinel pattern |
| LAB-QUERY-P1 (data-access boundary research) | ✅ DONE | QueryPlan v0 types; `IO.StorageCapability` boundary designed conceptually; denial-as-data 5-kind vocab |
| LAB-QUERY-P2 (QueryPlan fixture + proof) | ✅ DONE (42/42) | `QueryPlan`, `QueryResult`, `StorageDenied` proved as named Records; CORE fragment class for plan-building |
| LAB-CONCURRENCY-P4 (PolicySchedulingReceipt pattern) | ✅ DONE | Receipt-as-telemetry-only pattern; 6-gate policy check sequence |

---

## Relationship to PROP-035 and IO.NetworkCapability

`IO.StorageCapability` follows the exact same grammar pattern as `IO.NetworkCapability`
defined in PROP-035.

### Grammar form (from PROP-035)

```igniter
-- Capability declaration in a module header:
capability storage: IO.StorageCapability

-- Effect binding in a contract body:
effect read_from_storage using storage
```

Productions:

```
capability-decl      ::= "capability" ident ":" type-ref
effect-binding-decl  ::= "effect" ident "using" ident
```

### Structural parallel

| NetworkCapability field | StorageCapability analog | Mapping rationale |
|------------------------|------------------------|------------------|
| `capability_id` | `capability_id` | Direct |
| `resource_type: "network"` | `resource_type: "storage"` | Domain discriminant |
| `allowed_hosts: [String]` | `allowed_sources: [String]` | Table names; fail-closed if empty |
| `allowed_port_ranges: [{min,max}]` | `allowed_ops: [String]` | Op allowlist (["read"] in v0) |
| `loopback_only: Bool` | — | No storage analog in v0 |
| `connect_allowed: Bool` | `read_allowed: Bool` | Read authority |
| `listen_allowed: Bool` | `write_allowed: Bool` | Write authority (deferred) |
| `send_allowed: Bool` | — | No storage analog in v0 |
| `receive_allowed: Bool` | — | No storage analog in v0 |
| `tls_required: Bool` | — | No storage analog in v0 |
| — | `row_limit: Integer` | Storage-specific: safety cap |
| — | `allow_include_all: Bool` | Storage-specific: SELECT * gate |
| — | `deny_reason: String` | Human-readable denial context |

The `IO.*` opaque sentinel pattern is preserved: the Igniter typechecker treats
`IO.StorageCapability` as an opaque sentinel type at Stage 1. No grammar changes
are needed to name the capability; grammar changes (from PROP-035) are needed to
inject and bind it in effect contracts.

---

## IO.StorageCapability Schema

### JSON schema (v0)

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

### Field definitions

| Field | Type | Default | Semantics |
|-------|------|---------|----------|
| `capability_id` | String | — | Unique identifier; surfaced in `QueryExecutionReceipt.cap_id`; used for audit trail |
| `resource_type` | String | `"storage"` | Domain discriminant; always `"storage"` for this capability class |
| `allowed_sources` | `[String]` | `[]` | Table names eligible for query; **empty = deny all** (fail-closed); exact-match only in v0; glob/pattern deferred to v1 |
| `allowed_ops` | `[String]` | `[]` | Operations permitted; closed set in v0: `"read"` only; `"write"` deferred; empty = deny all (fail-closed) |
| `row_limit` | Integer | `0` | Maximum rows returned per execution; `0 = deny all rows`; executor applies `min(plan.limit, row_limit)` — clamps, does not deny |
| `allow_include_all` | Bool | `false` | Whether `Projection{include_all: true}` (SELECT *) is permitted; `false` = `QueryResult{kind:"query_error"}` if plan requests it |
| `read_allowed` | Bool | `false` | Master read gate; `false` = deny all read operations regardless of `allowed_sources` or `allowed_ops` |
| `write_allowed` | Bool | `false` | Master write gate; always `false` in v0 (write path not designed) |
| `deny_reason` | String | `""` | Human-readable denial context surfaced in `QueryResult.message` when denied |

### Fail-closed defaults

All fields default to the most restrictive value. A `StorageCapability` with no
explicit configuration denies all access. This mirrors `IO.NetworkCapability`:
an empty `allowed_hosts` blocks all network access.

---

## Denial-as-Data Gate Sequence

Query execution performs six ordered gate checks. The first failing gate short-circuits:
no subsequent gates are evaluated. All denial outcomes are `QueryResult` typed data —
never exceptions, never `raise`.

This mirrors the 6-gate policy evaluation sequence in `LAB-CONCURRENCY-P4`.

### Gate table

| Gate | Check | Fail outcome | Denial kind |
|------|-------|-------------|------------|
| G1 | Is `plan.source_table` in `allowed_sources`? (fail-closed: empty list = deny all) | `QueryResult{kind:"denied", message: cap.deny_reason}` | `"denied"` |
| G2 | Is `"read"` in `allowed_ops`? | `QueryResult{kind:"denied"}` | `"denied"` |
| G3 | Is `cap.read_allowed == true`? | `QueryResult{kind:"denied"}` | `"denied"` |
| G4 | Row limit enforcement: if `plan.limit > cap.row_limit`, clamp to `cap.row_limit` | *(clamp; no denial)* | — |
| G5 | If plan requests `include_all` and `cap.allow_include_all == false` | `QueryResult{kind:"query_error", message:"include_all not permitted by capability"}` | `"query_error"` |
| G6 | Execute plan (mocked in v0) | `QueryResult{kind:"rows"\|"empty"\|"system_error"}` | result-dependent |

**Gate G4 note:** Row limit is a safety clamp, not a denial. Exceeding the limit is
not an authorization failure — it is a budget enforcement. The executor silently
applies `effective_limit = min(plan.limit, cap.row_limit)`. The receipt records
both values and sets `row_limit_clamped: true` if clamping occurred.

**Gate G5 note:** `include_all` violation is a plan-formation error, not a capability
denial. The plan was formed incorrectly given the capability's constraints. Consumer
must fix the plan and resubmit. Hence `"query_error"` not `"denied"`.

**Gate G6 note:** In v0, execution is always mocked (Layer C simulation). No DB
connection is opened. The mock returns a `QueryResult` with kind `"rows"`, `"empty"`,
or `"system_error"` based on deterministic test inputs.

### Denial-as-data invariant

> All `IO.StorageCapability` denials flow as `QueryResult{kind:"denied"}`.
> No exception is raised. No `raise` keyword appears in execution logic.
> The consumer branches on `result.kind` to detect denial.

This is the same invariant as denial-as-data in `ContractResult` (LAB-STDLIB-NET-P6),
`ValidationResult` (LAB-RESULT-ENVELOPE-P2), and `QueryResult` (LAB-QUERY-P2).

---

## QueryExecutionReceipt

The receipt is **telemetry evidence only.** It records what the executor decided and
why. It does not confer authority. It does not authorize further execution. It does
not change the computed output.

This mirrors `PolicySchedulingReceipt` (LAB-CONCURRENCY-P4) and `AppendReceipt`
(PROP-008/TBackend).

### Shape

```
QueryExecutionReceipt {
  cap_id:            String,              -- from capability.capability_id
  plan_kind:         String,              -- from QueryPlan.kind (always "select" in v0)
  source_table:      String,              -- from QueryPlan.source_table
  op_requested:      String,              -- "read" in v0
  cap_checked:       Bool,               -- was capability checked before execution?
  cap_granted:       Bool,               -- false = denied at some gate
  denial_gate:       String,              -- "G1"..."G5" or "" if granted
  deny_reason:       String,              -- non-empty if denied
  plan_limit:        Integer,             -- from QueryPlan.limit
  row_limit_cap:     Integer,             -- from capability.row_limit
  effective_limit:   Integer,             -- min(plan_limit, row_limit_cap)
  row_limit_clamped: Bool,               -- true if effective_limit < plan_limit
  rows_returned:     Integer,             -- actual row count from execution
  result_kind:       String,              -- from QueryResult.kind
  metadata:          Map[String, String]  -- trace_id, requester, etc.
}
```

### Receipt invariants

- `cap_granted == false` iff `result_kind == "denied"` or `result_kind == "query_error"` (for G5)
- `denial_gate` is non-empty iff `cap_granted == false`
- `rows_returned == 0` when `cap_granted == false`
- `effective_limit <= row_limit_cap` always
- `row_limit_clamped == (effective_limit < plan_limit)`

The receipt is deterministic: given the same `QueryPlan` and `IO.StorageCapability`,
two runs produce identical receipts (modulo mocked execution output in Layer C).

### Receipt is evidence, not authority

A `QueryExecutionReceipt` with `cap_granted: true` does not re-authorize subsequent
executions. Each execution re-evaluates the full gate sequence. The receipt is for
audit, observability, and test assertion — not runtime re-use.

---

## Future ExecuteQuery Effect Contract Form

This is the grammar form that `ExecuteQuery` would take when PROP-035 effect grammar
is implemented. It is **not implemented today.** It is recorded here as the design
target so future work has a concrete reference.

```igniter
-- Future: requires PROP-035 effect grammar
-- Fragment: ESCAPE (v0) -> STORAGE (when STORAGE fragment class is defined)
-- NOT implemented in Stage 1. No grammar exists yet.

effect contract ExecuteQuery {
  capability storage: IO.StorageCapability
  effect read_from_storage using storage
  input  plan   : QueryPlan
  output result : QueryResult
}
```

Grammar productions used (from PROP-035):

```
capability-decl      ::= "capability" ident ":" type-ref
effect-binding-decl  ::= "effect" ident "using" ident
```

No `ExecuteQuery` contract is written in any fixture today. No effect binding is
introduced in the lab. Plan-building contracts (`BuildSelectQuery`,
`BuildFilteredQuery`) remain `pure` → CORE. Only the future execution path is
`effect` → requires `IO.StorageCapability`.

---

## Fragment Classification

### Plan-building contracts: CORE

All six contracts proved in LAB-QUERY-P2 are `pure` → CORE. They build typed
`QueryPlan` and `QueryResult` records without any capability, IO, or effect surface.

| Contract | Fragment class | Reason |
|----------|---------------|--------|
| `BuildQuerySource` | CORE | Pure; no capability; no IO |
| `BuildSelectQuery` | CORE | Pure; no capability; no IO |
| `BuildFilteredQuery` | CORE | Pure; no capability; no IO |
| `QueryResultDenied` | CORE | Pure; denial-as-data construction; no IO |
| `QueryMetadataReader` | CORE | Pure; map_get chain; no IO |
| `QueryMapper` | CORE | Pure; three-layer composition; no IO |

### Future ExecuteQuery: ESCAPE → STORAGE

When the effect grammar (PROP-035) is implemented, `ExecuteQuery` would be
classified as ESCAPE (the coarse external-surface label) until a dedicated STORAGE
fragment class is defined in ch4.

A **STORAGE fragment class** would be analogous to TEMPORAL (TBackend reads).
It would be the named class for contracts that execute queries against a storage
subsystem via `IO.StorageCapability`. This is a Stage 2+ concern.

| Contract | Fragment class | Route |
|----------|---------------|-------|
| `ExecuteQuery` (future) | ESCAPE (v0) | Refines to STORAGE when ch4 extended |

---

## Closed Surfaces Matrix

### Permanently closed (not deferred)

| Surface | Reason | Status |
|---------|--------|--------|
| Real DB connection | Architectural incompatibility with pure-contract model | CLOSED — no auth path |
| SQL string execution | Same as DB connection; also self-modifying query risk | CLOSED — no auth path |
| ORM / ActiveRecord | Global connection state, callbacks, `save!`, implicit transactions — incompatible | PERMANENTLY CLOSED |
| Schema migrations | DDL authority; completely separate from query path | CLOSED — no auth path |
| Transactions | Cross-statement atomicity; requires connection runtime | CLOSED — no auth path |
| Persistence runtime | No persistent state machine outside of TBackend (PROP-008) | CLOSED — no auth path |
| Public data API | No stable API surface; lab-only | CLOSED — explicit auth needed |

### Deferred (v1+)

| Surface | Reason | Deferral |
|---------|--------|---------|
| Write operations | Write path design not complete; mutation capability not designed | v1 |
| `Collection[FilterPredicate]` composition | Nested named Records in QueryPlan deferred in v0 for type-safety | v1 |
| JOINs | Cross-source type complexity; N+1 risk unresolved | v1 |
| Aggregates | New projection node kind needed | v1 |
| OR/NOT predicate composition | Requires variant grammar | v1 |
| Row projection `Row[T]` | Requires variant grammar | v1 |
| StorageCapability delegation algebra | Sub-delegation of table access; v0 is flat capability only | v1 |
| Glob/pattern in `allowed_sources` | Wildcard source matching (like `allowed_hosts: ["*"]`) | v1 |
| STORAGE fragment class in ch4 | Requires PROP-035 effect grammar implementation first | Stage 2+ |

---

## OOF-STORE Diagnostic Candidates

These are candidate diagnostics for the STORAGE capability surface. They are **not
active**. No grammar implements them. They are candidates for future activation when
PROP-035 effect grammar and IO.StorageCapability grammar are implemented.

| Code | Trigger condition | Example | Priority |
|------|-----------------|---------|---------|
| OOF-STORE1 | Dynamic source name construction (not a string literal) | `source_table: build_table_name(user_id)` | High — OOF-MAP2 analog |
| OOF-STORE2 | Write operation requested on a read-only capability (`write_allowed: false`) | `ExecuteQuery` with a `"write"` op on read-only cap | High |
| OOF-STORE3 | Source name not in `allowed_sources` at static analysis time | `source_table: "audit_log"` when only `["users"]` allowed | Medium |
| OOF-STORE4 | `include_all` plan on cap with `allow_include_all: false` | `Projection{include_all: true}` on restricted cap | Medium |
| OOF-STORE5 | `row_limit: 0` capability (deny-all rows; always clamps to 0) | `row_limit: 0` in capability JSON | Low — misconfig detection |

---

## Design Decision Table

| # | Decision | Rationale |
|---|----------|----------|
| D1 | `allowed_sources` is fail-closed (empty = deny all) | Mirrors `allowed_hosts` in NetworkCapability; safe default |
| D2 | `allowed_ops: ["read"]` only in v0; `"write"` deferred | Write path not designed; separate mutation capability needed |
| D3 | Row limit clamps, does not deny | Over-limit is budget enforcement, not authorization failure; receipt records clamping |
| D4 | `include_all` violation → `"query_error"`, not `"denied"` | Plan formation error (consumer's responsibility); capability is not the blocker |
| D5 | `read_allowed/write_allowed` are master gates | Gate G3 (read_allowed) is evaluated after source/op checks; allows fine-grained allowlist with global kill-switch |
| D6 | `deny_reason` on capability surfaced in `QueryResult.message` | Provides actionable context to consumer without leaking capability internals |
| D7 | `QueryExecutionReceipt` is evidence-only | Following PolicySchedulingReceipt precedent; authority comes from the capability, not the receipt |
| D8 | ExecuteQuery is ESCAPE (not STORAGE) in v0 | STORAGE fragment class requires ch4 extension; ESCAPE is the correct coarse label before refinement |
| D9 | No delegation algebra in v0 | Single flat capability; sub-delegation (allowing a service to narrow table access for a sub-service) deferred to v1 |
| D10 | No `IO.StorageCapability` grammar changes today | PROP-035 effect grammar required first; design target recorded but not implemented |

---

## Query Execution Layer Model

```
Layer A (Production Ruby TypeChecker)
  ↓ type-checks plan-building contracts (BuildSelectQuery, etc.)
  ↓ [FUTURE: type-checks ExecuteQuery effect + capability binding]

Layer B (Lab Rust VM)
  ↓ executes plan-building contracts (proved in LAB-QUERY-P2)
  ↓ [FUTURE: executes ExecuteQuery with mocked StorageCapability]

Layer C (QueryExecutorSim — proof-local Ruby module)
  ↓ simulates capability gate sequence
  ↓ routes QueryResult.kind → handler action (from LAB-QUERY-P2)
  ↓ [v1+: returns QueryExecutionReceipt]
```

In v0, Layer C is the only execution layer. Layers A and B handle plan-building only.
No real storage layer is introduced at any layer in v0.

---

## Promotion Boundary

### Authorized by this card

- Design document authored (this file)
- `IO.StorageCapability` schema defined (JSON + field table)
- Denial-as-data gate sequence locked (6 gates)
- `QueryExecutionReceipt` shape locked
- Future `ExecuteQuery` grammar form recorded
- OOF-STORE1..5 candidates enumerated
- Fragment classification documented (CORE vs ESCAPE/STORAGE)

### Not authorized

- Writing a new `ExecuteQuery` effect contract in any fixture
- Adding `IO.StorageCapability` to the grammar
- Opening a DB connection at any layer
- Writing a `StorageCapability`-aware proof runner
- Implementing the STORAGE fragment class in ch4
- Modifying any production Igniter file
- Writing a stable public API for query execution

### Next authorized

| Route | Requires |
|-------|---------|
| LAB-STORAGE-CAPABILITY-P2 (write StorageCapability-aware fixture + proof runner) | Explicit auth; PROP-035 effect grammar must be implemented first |
| LAB-QUERY-P3 (Collection[FilterPredicate] + nested Records in QueryPlan) | Explicit auth; type-resolver inference for Collection[NamedRecord] must be proved |
| PROP-046 (IO.StorageCapability grammar proposal) | Explicit auth; proposal authoring only |

---

## Gap Packet

```
design:    lab-storage-capability-query-execution-boundary / v0
status:    CLOSED — design-locked
authority: lab_only
date:      2026-06-09

capability_schema:
  resource_type:     storage
  allowed_sources:   [String]   -- table names; empty = deny all
  allowed_ops:       [String]   -- ["read"] in v0; "write" deferred
  row_limit:         Integer    -- clamps, does not deny; 0 = deny all
  allow_include_all: Bool       -- false = G5 query_error on include_all plans
  read_allowed:      Bool       -- master read gate
  write_allowed:     Bool       -- master write gate (always false in v0)
  deny_reason:       String

gate_sequence:
  G1: source in allowed_sources?     NO -> denied
  G2: "read" in allowed_ops?         NO -> denied
  G3: read_allowed == true?          NO -> denied
  G4: plan.limit > row_limit?        YES -> clamp (no denial)
  G5: include_all + !allow_include_all? -> query_error
  G6: execute (mocked in v0)

receipt_fields:
  cap_id / plan_kind / source_table / op_requested
  cap_checked / cap_granted / denial_gate / deny_reason
  plan_limit / row_limit_cap / effective_limit / row_limit_clamped
  rows_returned / result_kind / metadata

fragment_classification:
  plan_building:  CORE (all LAB-QUERY-P2 contracts)
  ExecuteQuery:   ESCAPE -> STORAGE (when ch4 extended; Stage 2+)

oof_candidates:
  OOF-STORE1: dynamic source name  (high)
  OOF-STORE2: write on read-only   (high)
  OOF-STORE3: source not in list   (medium)
  OOF-STORE4: include_all on restricted cap (medium)
  OOF-STORE5: row_limit:0 misconfig (low)

deferred:
  write operations: v1
  Collection[FilterPredicate]: v1
  JOINs, aggregates: v1
  delegation algebra: v1
  STORAGE fragment class: Stage 2+
  PROP-035 grammar implementation: Stage 2+

closed:
  real DB connection: CLOSED
  SQL execution: CLOSED
  ORM / ActiveRecord: PERMANENTLY CLOSED
  migrations / transactions: CLOSED
  persistence runtime: CLOSED

next_authorized:
  immediate:   LAB-QUERY-P3 (Collection[FilterPredicate] if Collection[NamedRecord] proved)
  design_only: PROP-046 (IO.StorageCapability grammar proposal)
  deferred:    LAB-STORAGE-CAPABILITY-P2 (requires PROP-035 grammar impl)
```
