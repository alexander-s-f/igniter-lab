# Lab: Static Route Dispatch (v0)

> Status: experiment-pass · lab-only · 27/27 checks PASS
> Card: LAB-RACK-P4
> Date: 2026-06-08
> Category: lang / web
> Track: lab-rack-static-route-dispatch-v0
> Precedes: LAB-RACK-P3 (ContractRef VM dispatch preflight)
> Authority: lab-only evidence — no canon claim, no stable-API surface, no production commitment

---

## Pre-v1 Language Note

All Igniter constructs in this document are drawn from accepted spec chapters
and PROPs and reflect the current spec vocabulary. They are not stable APIs.
This document is lab-only research evidence. It does not constitute canon
specification, a PROP, or a production commitment.

---

## 1. Purpose

LAB-RACK-P4 proves that a Rack-like route dispatch table is expressible as a
**single `pure contract` using data-plane logic only** — no ContractRef runtime
dispatch, no VM call-frame dispatch, no accept-loop, no network I/O.

The proof establishes correctness at two layers:
1. **Algebra level** — the dispatch logic produces the right status code for all
   5 route cases, verified by a Ruby module that mirrors the Igniter contract's
   exact logic (`starts_with`, `byte_length > 1`).
2. **Compiler/IR level** — the contracts compile clean through all 5 pipeline
   stages, and SemanticIR confirms the correct node types (`if_expr`,
   `stdlib.text.starts_with`, `stdlib.text.split`, `last`).

The proof also precisely characterises two new gaps found during P4:

| Gap | Detail |
|-----|--------|
| VM `stdlib.text.*` namespace mismatch | Compiler emits `fn:"stdlib.text.starts_with"` but VM OP_CALL only handles bare `"starts_with"` — blocks execution |
| TypeChecker `==` and `<` | OOF-TY0 on `==` and `<` for all types; workaround uses `starts_with` for method/route detection and `byte_length(path) > 1` for root detection |

**What this proof establishes:**

1. `RouteDispatch` pure contract compiles clean through parse → classify →
   typecheck → emit → assemble (5 stages, status: ok).
2. Correct dispatch for all 5 route cases: `GET /` → 200, `GET /articles/42`
   → 200, `POST /articles` → 201, `GET /missing` → 404, `POST /articles/42`
   → 405.
3. Path param extraction via `split(path, "/")` + `last(segments)` correctly
   isolates `:id` from `/articles/42` → `"42"`.
4. SemanticIR shape confirmed: `status_code` node is `if_expr`; condition uses
   `stdlib.text.starts_with`; segments uses `stdlib.text.split`; param_id uses
   bare `last`.
5. VM execution gap characterised precisely: `OP_CALL: Unknown/unimplemented
   function 'stdlib.text.starts_with'` — same OP_CALL layer as P3, different
   root cause (stdlib namespace mismatch, not ContractRef dispatch).

**What this proof does NOT establish:**

- End-to-end VM execution of route dispatch (blocked by stdlib.text.* gap)
- TypeChecker support for string equality (`==`) or `<` comparison
- ContractRef runtime dispatch (gap from P3 still open)
- Middleware execution in the route handler chain
- Query param parsing, prefix/glob matching
- Any production HTTP server or rack-compatible server claim

---

## 2. Proof Structure

**Proof file:** `igniter-view-engine/proofs/verify_p4_route_dispatch.rb`
**Fixtures:** `igniter-view-engine/fixtures/rack_core/route_dispatch.ig`,
             `igniter-view-engine/fixtures/rack_core/path_param_extract.ig`
**Result:** 27/27 PASS

### 2.1 Sections and Check Count

| Section | Checks | Coverage |
|---------|--------|----------|
| P4-COMPILE | 4 | Both contracts compile clean |
| P4-ROUTES | 5 | All 5 route cases correct |
| P4-PARAM | 3 | Split+last param extraction |
| P4-IR | 6 | SemanticIR node shape |
| P4-VM-GAP | 3 | VM stdlib.text.* gap characterised |
| P4-SURFACE | 4 | Closed-surface scan |
| P4-GAP-PACKET | 2 | Gap packet completeness |
| **Total** | **27** | |

---

## 3. Contract Design

### 3.1 RouteDispatch

```igniter
pure contract RouteDispatch {
  input method : String
  input path   : String

  compute status_code =
    if starts_with(path, "/articles/") {
      if starts_with(method, "GET") { 200 } else { 405 }
    } else {
      if starts_with(path, "/articles") {
        if starts_with(method, "POST") { 201 } else { 405 }
      } else {
        if byte_length(path) > 1 { 404 } else { 200 }
      }
    }

  output status_code : Integer
}
```

**Design notes:**
- TypeChecker gap: `==` and `<` emit OOF-TY0. Route detection uses `starts_with`
  instead. Root path detection uses `byte_length(path) > 1` (length of `"/"` is 1).
- Method detection: `starts_with(method, "GET")` and `starts_with(method, "POST")`
  correctly discriminate for the 5 test cases (no other HTTP methods tested).
- Dispatch order: `/articles/` prefix first (item), `/articles` exact second
  (collection, matched in else-branch of first), then root vs 404.
- `byte_length` is the canonical Text stdlib op (not legacy `length`). The
  `byte_length` of `"/"` is 1; any longer path has `byte_length > 1`.

### 3.2 PathParamExtract

```igniter
pure contract PathParamExtract {
  input path : String

  compute segments = split(path, "/")
  compute param_id = last(segments)

  output param_id : Option[String]
}
```

**Design notes:**
- `split("/articles/42", "/")` → `["", "articles", "42"]`
- `last(["", "articles", "42"])` → `"42"` (as `Option[String]`)
- `last` compiles to bare `fn: "last"` (collection stdlib, not text stdlib) —
  already supported by VM OP_CALL handler. Only `split` is namespaced.
- `split` compiles to `fn: "stdlib.text.split"` — needs P5 VM alignment.

---

## 4. TypeChecker Gap Note

The following operators are OOF-TY0 in the current lab compiler:
- `==` (equality) — for all types (String, Integer, Bool)
- `<` (less-than) — for all types

Available operators (confirmed working):
- `>` — Integer greater-than ✓
- `&&` — Bool and ✓
- `||` — Bool or (untested, likely ✓)
- `starts_with(str, prefix)` → Bool ✓
- `contains(str, substr)` → Bool ✓
- `byte_length(str)` → Integer ✓

This is a TypeChecker gap, not a parser or VM gap. The VM has OP_EQ and OP_LT
opcodes that CAN handle these comparisons — the TypeChecker rejects them before
they reach the bytecode compiler. A separate card can address TypeChecker
operator coverage.

---

## 5. VM Gap: stdlib.text.* Namespace Mismatch

The compiler (after the Text/String Core track update) emits namespaced function
names for text stdlib operations:

| Igniter source | Compiler emits | VM knows |
|----------------|----------------|----------|
| `starts_with(s, p)` | `fn: "stdlib.text.starts_with"` | `"starts_with"` (bare) |
| `split(s, d)` | `fn: "stdlib.text.split"` | `"split"` (bare) |
| `byte_length(s)` | `fn: "stdlib.text.byte_length"` | `"length"` (bare, different name) |
| `last(arr)` | `fn: "last"` | `"last"` ✓ |

**Fix for LAB-RACK-P5:** Add three cases to `vm.rs` OP_CALL handler:
```rust
"stdlib.text.starts_with" => { /* same as "starts_with" */ }
"stdlib.text.split"       => { /* same as "split" */ }
"stdlib.text.byte_length" => { /* same as "length" (byte count) */ }
```
No other VM changes required to unblock P4 route dispatch execution.

---

## 6. Route Table Design

| Route | Method | Pattern | Status | Dispatch Logic |
|-------|--------|---------|--------|----------------|
| Root | GET | `/` | 200 | `byte_length(path) > 1` is false |
| Articles item | GET | `/articles/:id` | 200 | `starts_with(path, "/articles/")` |
| Articles collection | POST | `/articles` | 201 | `starts_with(path, "/articles")` in else-branch |
| No route | ANY | `/missing` | 404 | `byte_length(path) > 1` is true |
| Wrong method | POST | `/articles/:id` | 405 | `starts_with(path, "/articles/")` + `!starts_with(method, "GET")` |

**Param extraction for `:id` routes:**
- `split("/articles/42", "/")` → `["", "articles", "42"]` → `last` → `"42"`
- Works for any positive integer id at the tail segment

---

## 7. Relationship to P1–P3

| Proof | What it proved |
|-------|----------------|
| LAB-LANG-HTTP-TYPES-P1 (~41/41) | HTTP type schema + ContractRef at Ruby proof level |
| LAB-RACK-P2 (46/46) | Static middleware pipeline shape + adapters |
| LAB-RACK-P3 (25/25) | Precise gap map at each compiler/VM layer for ContractRef dispatch |
| **LAB-RACK-P4 (27/27)** | **5-route data-plane table; path param extraction; two new VM gaps found** |

P4 adds new evidence: the route dispatch algebra IS expressible in Igniter
`pure contract` syntax. The compiler accepts it fully. The gap is precisely at
the VM stdlib.text.* namespace layer — not a language design gap, but an
implementation alignment gap.

---

## 8. Next Route

**LAB-RACK-P5: VM stdlib.text.* Alignment**

Add `stdlib.text.starts_with`, `stdlib.text.split`, and `stdlib.text.byte_length`
to the VM OP_CALL handler in `igniter-vm/src/vm.rs`. This converts the P4
algebra proof into a full end-to-end VM execution proof across all 5 routes.

Scope: 3 targeted additions to one match block in vm.rs. No TypeChecker changes.
No ContractRef dispatch. No VM entrypoint selector. No canon grammar changes.

The P5 proof would reuse P4's fixture contracts verbatim (route_dispatch.ig,
path_param_extract.ig) and replace the P4-VM-GAP section with P5-VM-EXEC checks
showing VM result = expected status code for each route.
