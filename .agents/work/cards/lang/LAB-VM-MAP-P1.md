# Card: LAB-VM-MAP-P1
**Category:** lang / vm  
**Track:** lab-vm-map-ops-runtime-proof-v0  
**Status:** CLOSED — PROVED  
**Gate result:** 48/48 PASS  
**Date closed:** 2026-06-09  
**Route:** LAB / VM / IMPLEMENTATION

---

## Goal

Implement and prove proof-local VM runtime support for `map_get`, `map_has_key`, and
`or_else` over `Map[String,String]` runtime values. Close the Rack P14
`HeadersAwareHandler` VM gap identified as the highest-priority blocker by
LAB-RESULT-ENVELOPE-P1.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-RESULT-ENVELOPE-P1 | ✅ DONE — identified VM map_get gap as highest-priority blocker |
| LAB-RACK-P14 (60/60) | ✅ DONE — HeadersAwareHandler TypeChecker complete; VM gap identified |
| LAB-SIDEKIQ-P5 (48/48) | ✅ DONE — MetadataReader TypeChecker complete |
| LAB-MAP-RUST-P1 (32/32) | ✅ DONE — map_get/or_else TypeChecker proofs |
| LAB-RECORD-VM-P2 (42/42) | ✅ DONE — OP_GET_FIELD base |
| PROP-043-P5 (55/55) | ✅ DONE — Map[String,String] production surface |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| VM handler edit (map_get, map_has_key) | `igniter-vm/src/vm.rs` | ✅ DONE |
| VM compiler fix (input field access) | `igniter-vm/src/compiler.rs` | ✅ DONE |
| Fixture | `igniter-view-engine/fixtures/vm_map/map_vm_ops.ig` | ✅ DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_vm_map_p1.rb` | ✅ DONE |
| Lab doc | `lab-docs/lang/lab-vm-map-ops-runtime-proof-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/lang/LAB-VM-MAP-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Changes Made

### `igniter-vm/src/vm.rs`
Added two OP_CALL handlers in the `LAB-VM-MAP-P1` section (before `Unknown/unimplemented` default):

```rust
"map_get" | "stdlib.map.get" => {
    // (map, key) → Option[V]: Nil if absent, raw value if present
}
"map_has_key" | "stdlib.map.has_key" => {
    // (map, key) → Bool
}
```

### `igniter-vm/src/compiler.rs`
Fixed field_access fallback for input records (line ~406). Previously emitted
`OP_LOAD_REF("job.metadata")` — a dotted flat lookup that fails at runtime.
Now emits `OP_LOAD_REF("job") + OP_GET_FIELD("metadata")` — resolves the base
input record first, then extracts the named field. This enables `MetadataReader`
and all contracts with nested input field access.

---

## Key Findings

| Finding | Detail |
|---------|--------|
| Map runtime = Value::Record | No separate Map type needed; BTreeMap serves both |
| Option None = Value::Nil | Pre-existing convention; or_else already correct |
| Option Some(v) = raw v | No wrapper; or_else identity path falls to `_ => val.clone()` |
| or_else was pre-existing | Already handled Nil→fallback and non-Nil→identity correctly |
| SIR emits bare "map_get" | Emitter does not qualify map names (unlike stdlib.text.*) |
| Input field access gap fixed | Compiler emitted `OP_LOAD_REF("a.b")`; now emits `OP_LOAD_REF("a") + OP_GET_FIELD("b")` |
| Rack P14 gap closed | HeadersAwareHandler: 9/10 → 10/10 VM-executable |
| Sidekiq P5 gap closed | MetadataReader now VM-executable (queue present → value, absent → "default") |

---

## Proof Sections (48/48)

```
VMAP-COMPILE  (4/4)  — fixture compiles, 7 contracts, no type_errors, all accepted
VMAP-TYPES    (5/5)  — map_get→Option[String], or_else→String, map_has_key→Bool
VMAP-GET      (6/6)  — present/absent key behavior; no Unknown error; raw string
VMAP-HAS      (4/4)  — has_key true/false; no Unknown error; empty map → false
VMAP-OR       (6/6)  — or_else identity/fallback; nil→fallback; non-nil→identity
VMAP-BRIDGE   (4/4)  — HeaderChain chain: present→value, absent→"text/plain"
VMAP-RACK     (4/4)  — P14 HeadersAwareHandler executes; 10/10 gap closed
VMAP-SIDEKIQ  (4/4)  — MetadataReader executes; queue present/absent; String return
VMAP-CLOSED   (5/5)  — no mutation, no non-String keys, no broad API, read-only
VMAP-GAP      (6/6)  — representation decisions, pre-existing or_else, gap closed
```

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| VM new Map type needed? | **NO** — Value::Record serves as Map runtime |
| New opcodes needed? | **NO** — OP_CALL handlers + compiler fix sufficient |
| or_else pre-existing? | **YES** — already correct for map_get Option output |
| SIR function name? | `"map_get"` (bare); qualified alias `"stdlib.map.get"` also handled |
| Option[String] in VM? | None = Nil, Some(s) = Value::String(s) |
| Rack P14 gap closed? | **YES** — HeadersAwareHandler 10/10 VM-executable |
| Sidekiq P5 gap closed? | **YES** — MetadataReader executes end-to-end |
| Mutation handlers added? | **NO** — read-only only |
| Canon claim? | **NO** — lab-only |

---

## Gap Packet

```
proof:      lab-vm-map-ops-runtime-proof / v0
status:     CLOSED — 48/48 PASS
authority:  lab_only
date:       2026-06-09

handlers_added:   map_get (bare + qualified), map_has_key (bare + qualified)
compiler_fix:     input field access: OP_LOAD_REF("a.b") → OP_LOAD_REF("a")+OP_GET_FIELD("b")
gaps_closed:      VM map_get bytecode (LAB-RACK-P14), Rack P14 HeadersAwareHandler,
                  Sidekiq P5 MetadataReader, LAB-RESULT-ENVELOPE-P1 blocker #2

remaining_open:
  - VM map literal construction (map_from_pairs, map_empty)
  - VM map mutation (map_set, map_delete) — not authorized
  - Non-String-keyed maps — out of scope in v0
  - LAB-RESULT-ENVELOPE-P2 (third-domain pressure proof)
```

---

## Authority

lab-only — no canon claim, no stable surface.  
`map_get` / `map_has_key` are lab-VM handlers (not canon grammar).  
Compiler fix is internal to the lab VM toolchain.  
No production runtime claim. No mutation. String keys only (v0).
