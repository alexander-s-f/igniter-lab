# LAB-RACK-P14: Rack-Shaped Upstream HTTP Result Composition Proof (v0)

**Track:** lab-rack-upstream-http-result-composition-proof-v0  
**Date:** 2026-06-09  
**Status:** CLOSED / PROVED — 60/60 PASS  
**Proof file:** `igniter-view-engine/proofs/verify_p14_http_result_rack_composition.rb`  
**Fixture:** `igniter-view-engine/fixtures/rack_core/http_result_rack_composition.ig`

---

## Goal

Prove that Rack-shaped handler contracts can map a typed upstream ContractResult envelope
into a typed `FullRackResponse` across all 6 branch outcomes, using `map_get`/`or_else`
for header extraction, without opening real network I/O, Rack compatibility, or
production server runtime.

---

## What Was Proved

### ContractResult Branch Taxonomy (6 kinds)

| Kind | Status | Body |
|---|---|---|
| `found` | 200 | caller-supplied `data_body` |
| `created` | 201 | caller-supplied `data_body` |
| `not_found` | 404 | `"Not Found"` |
| `capability_denied` | 403 | `"Forbidden"` |
| `upstream_error` | 502 | `"Bad Gateway"` |
| `upstream_unavailable` | 503 | `"Service Unavailable"` |

The `upstream_unavailable → 503` branch doubles as the catch-all for unknown kinds
(any string that matches none of the 5 explicit conditions falls to the else-branch).

### TypeChecker (primary deliverable)

All types proved at compile time via Rust TypeChecker:

| Node | Contract | Resolved Type |
|---|---|---|
| `is_found`, `is_created`, `is_nf`, `is_denied`, `is_error` | `ContractResultBranchMapper` | `Bool` |
| `resp_status` | `ContractResultBranchMapper` | `Integer` |
| `resp_body` | `ContractResultBranchMapper` | `String` |
| `response` | `ContractResultBranchMapper` | `FullRackResponse` (P13 upgrade) |
| `content_type_opt` | `HeadersAwareHandler` | `Option[String]` |
| `content_type` | `HeadersAwareHandler` | `String` |
| `response` | `HeadersAwareHandler` | `FullRackResponse` (P13 upgrade) |
| `response` | `Tier1BranchDispatcher` | `FullRackResponse` (P11 Tier 1) |
| `response` | `Tier2BranchDispatcher` | `Unknown` (P11 Tier 2) |
| `response` | all 6 per-branch builders | `FullRackResponse` (P13 upgrade each) |

### map_get / or_else

- `map_get(Map[String,String], key) → Option[String]` — TypeChecker-proved (LAB-MAP-RUST-P1 basis)
- `or_else(Option[String], default) → String` — TypeChecker-proved
- Map field `headers: Map[String,String]` preserved through all 6 builders (SIR params intact)
- VM gap: `map_get` bytecode opcode not yet implemented; VM raises `Unknown/unimplemented function 'map_get'`

### VM Execution (secondary deliverable)

9 of 10 contracts execute end-to-end through the VM:

| Contract | VM Result |
|---|---|
| `FoundResponseBuilder` | `{status: 200, body: "hello", headers: {}}` ✓ |
| `CreatedResponseBuilder` | `{status: 201}` ✓ |
| `NotFoundResponseBuilder` | `{status: 404, body: "Not Found"}` ✓ |
| `DeniedResponseBuilder` | `{status: 403, body: "Forbidden"}` ✓ |
| `UpstreamErrorBuilder` | `{status: 502, body: "Bad Gateway"}` ✓ |
| `UnavailableBuilder` | `{status: 503, body: "Service Unavailable"}` ✓ |
| `ContractResultBranchMapper` | All 6 kinds correct ✓ |
| `Tier1BranchDispatcher(found)` | `{status: 200}` ✓ |
| `Tier1BranchDispatcher(capability_denied)` | `{status: 403}` ✓ |
| `HeadersAwareHandler` | VM error — `map_get` gap ✗ (expected) |

Map pass-through confirmed: `resp_headers` survives VM execution as a JSON object
with all key/value pairs intact.

---

## Design

### Branch Mapping Pattern

```ig
compute is_found   = kind == "found"
compute is_created = kind == "created"
-- ...

compute resp_status =
  if is_found { 200 } else {
    if is_created { 201 } else {
      if is_nf { 404 } else {
        if is_denied { 403 } else {
          if is_error { 502 } else { 503 }
        }
      }
    }
  }
```

**TypeChecker behavior:** `kind == "found"` (String==String) → `Bool`. Nested `IfExpr` with
`Integer` leaves → TypeChecker infers `Integer`. P13 upgrades the output `RecordLiteral` to
`FullRackResponse` when all field types match.

### P13 Nominal Record Type Upgrade

All 8 contracts that output a `RecordLiteral` declared as `FullRackResponse` are upgraded
from `Unknown` to `FullRackResponse` by the P13 post-infer check in `typecheck_contract`.
The upgrade is contingent on all fields passing `check_record_literal_shape`.

### Per-Branch Builder Pattern

Each ContractResult outcome also has a standalone pure contract:

```ig
pure contract FoundResponseBuilder {
  input  data_body    : String
  input  resp_headers : Map[String, String]
  compute body     = data_body
  compute hdrs     = resp_headers
  compute code     = 200
  compute response = { body: body, headers: hdrs, status: code }
  output response : FullRackResponse
}
```

These are Tier 1 `call_contract` targets. The `Tier1BranchDispatcher` calls
`ContractResultBranchMapper` directly; the per-branch builders serve as simpler
alternatives for single-kind callers.

---

## Fail-Closed Invariants

| Violation | Diagnostic |
|---|---|
| Missing required field (e.g. `status`) | OOF-TY0: field named, type named |
| Extra field not in `FullRackResponse` | OOF-TY0: extra field named |
| Wrong status type (String instead of Integer) | OOF-TY0: type mismatch named |
| Wrong body type (Integer instead of String) | OOF-TY0: type mismatch named |
| Uncontextualized RecordLiteral (no output type) | No error; stays `Unknown` |

---

## Gaps and Open Items

| Gap | Status |
|---|---|
| VM `map_get` bytecode | **Open** — TypeChecker-proved; VM execution deferred |
| Tier 2 dynamic callee type | **Open** — Unknown; inherent to dynamic dispatch |
| Three-level chained field access | Open |
| Multi-output callee | Open |
| Real Rack env / accept-loop | Closed — out of scope |

**VM map_get bytecode** is the highest-priority VM gap for follow-on work.
`HeadersAwareHandler` is TypeChecker-complete and will execute end-to-end once
the opcode is implemented.

---

## Proof Sections (60 checks)

```
P14-COMPILE  (5)  — fixture compiles; 10 contracts; all stages ok; no diagnostics
P14-TYPES   (12)  — BranchMapper: 5 Bool flags, Integer status, String body, FullRackResponse;
                    all 6 builders → FullRackResponse; HeadersAwareHandler: Option[String]/String/FullRackResponse;
                    Tier1 → FullRackResponse; Tier2 → Unknown; builder code/hdrs types
P14-BRANCH  (10)  — 6 kinds via VM (found/created/not_found/capability_denied/upstream_error/unavail);
                    simulation: found/created data_body pass-through; error body strings; unknown→503;
                    headers unmodified
P14-MAP      (5)  — map_get → Option[String]; or_else → String; Map field in all builders;
                    VM gap confirmed; headers pass-through in VM
P14-VM       (8)  — 6 builders correct; Tier1(found)→200; Tier1(denied)→403
P14-FC       (6)  — missing status, extra field, wrong status type, wrong body type,
                    uncontextualized→Unknown, missing body
P14-COMPAT   (4)  — P13/P12 regression green; P14 no diagnostics; FullRackResponse shape consistent
P14-CLOSED   (5)  — no socket imports; no net/http; no Rack-compat/prod-runtime claim;
                    no ServiceLoop; fixture labeled lab-only
P14-GAP      (5)  — TypeChecker 6-kind taxonomy; map_get VM gap; 9/10 VM-executable;
                    upstream_unavailable 503; Tier2 Unknown preserved
```

---

## Prerequisites

| Prerequisite | Status |
|---|---|
| LAB-RACK-P13 (47/47) | ✅ P13 nominal record type checking |
| LAB-RACK-P12 (45/45) | ✅ typed response dispatch |
| LAB-RACK-P11 (47/47) | ✅ two-tier call_contract policy |
| LAB-RECORD-VM-P3 (49/49) | ✅ nested record field values |
| LAB-RECORD-MAP-P1 (51/51) | ✅ Map[String,V] record field bridge |
| LAB-MAP-RUST-P1 (32/32) | ✅ map_get/or_else TypeChecker proofs |
| LAB-STDLIB-NET-P9 (55/55) | ✅ ContractResult domain envelope |

---

## Authority

lab-only — no canon claim, no stable surface.  
`call_contract` is lab-only. No Rack-compatibility claim. No production runtime claim.  
`map_get` / `or_else` are lab-stdlib (not canon grammar).  
Record checking and branch inference are in the lab Rust compiler; not in igniter-lang canon grammar.
