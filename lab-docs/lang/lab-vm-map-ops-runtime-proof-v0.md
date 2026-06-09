# LAB-VM-MAP-P1: Lab VM Map Runtime Operations Proof (v0)

**Track:** lab-vm-map-ops-runtime-proof-v0  
**Date:** 2026-06-09  
**Status:** CLOSED / PROVED — 48/48 PASS  
**Proof file:** `igniter-view-engine/proofs/verify_lab_vm_map_p1.rb`  
**Fixture:** `igniter-view-engine/fixtures/vm_map/map_vm_ops.ig`

---

## Goal

Implement and prove proof-local VM runtime support for `map_get`, `map_has_key`, and
`or_else` over `Map[String,String]` runtime values. Close the Rack P14
`HeadersAwareHandler` VM gap identified as the highest-priority blocker in
LAB-RESULT-ENVELOPE-P1.

**Scope:** Read-only map access. String keys only. No mutation, no literals, no
non-String keys, no broad map API (keys/values/size/to_pairs). Lab-only. No canon
claim. No stable runtime API claim.

---

## What Was Proved

### VM Representation Decisions

| Question | Answer |
|----------|--------|
| Map runtime representation | `Value::Record(Arc<BTreeMap<String, Value>>)` — no separate Map variant |
| Option None representation | `Value::Nil` |
| Option Some(v) representation | Raw `v` (no wrapper — same as pre-existing `some`/`stdlib.option.wrap`) |
| `or_else` handler status | Pre-existing — not added in this card; already correct for map_get |

The VM has no separate `Map` value variant. `Map[String,String]` runtime values
arrive as `Value::Record(BTreeMap<String, Value>)` via `Value::from_json`. This
is consistent with how `Record` types work — the semantic difference is only
at the type-checker level.

### Handlers Added (LAB-VM-MAP-P1)

Two handlers added to `vm.rs` in the `OP_CALL` dispatch block, before the
`Unknown/unimplemented` default case:

```rust
// map_get(map, key) → Option[V]: Nil if absent, raw value if present
"map_get" | "stdlib.map.get" => { ... }

// map_has_key(map, key) → Bool: true iff key exists
"map_has_key" | "stdlib.map.has_key" => { ... }
```

Both handlers accept `Value::Record` (the runtime map representation) and
`Value::Nil` as first argument (for absent/nil-map robustness). Bare names
(`map_get`, `map_has_key`) match what the Rust emitter produces; qualified
names (`stdlib.map.get`, `stdlib.map.has_key`) match the TypeChecker's
alternate forms.

### or_else Correctness

`or_else` was already implemented (pre-existing handler at vm.rs line ~1119):
- `Value::Nil` → returns fallback (None path) ✓
- Any other non-Record-with-ok/err value → returns identity (Some path) ✓
- `Value::String("...")` falls to `_ => val.clone()` — returns the string ✓

This means `or_else(map_get(m, key), default)` works correctly:
- Key present: `map_get` → `Value::String(v)` → `or_else` → `v` ✓
- Key absent:  `map_get` → `Value::Nil` → `or_else` → `default` ✓

### Rack P14 HeadersAwareHandler Gap — Closed

The `HeadersAwareHandler` contract in `http_result_rack_composition.ig` was
TypeChecker-complete but VM-deferred since LAB-RACK-P14. The gap was:

```
VM raises: Unknown/unimplemented function 'map_get'
```

After this card: `HeadersAwareHandler` executes end-to-end. Rack P14 is now
**10/10 VM-executable** (was 9/10).

### Sidekiq P5 MetadataReader Gap — Closed

`MetadataReader` in `upstream_http_result_composition.ig` was TypeChecker-complete
but VM-deferred. After this card: executes end-to-end including the `or_else`
fallback to `"default"` when `queue` key is absent.

---

## Fixture Design

`map_vm_ops.ig` — 7 pure contracts:

| Contract | Tests |
|----------|-------|
| `MapGetHit` | `map_get` present key → raw string |
| `MapGetMiss` | `map_get` absent key → nil |
| `OrElseHit` | `or_else(Some(v), default)` → v |
| `OrElseMiss` | `or_else(None, default)` → default |
| `HasKeyHit` | `map_has_key` present key → true |
| `HasKeyMiss` | `map_has_key` absent key → false |
| `HeaderChain` | `map_get + or_else` chain (mirrors Rack P14 gap) |

All contracts use `Map[String,String]` inputs. No type declarations. No mutation.

---

## Proof Sections (48 checks)

```
VMAP-COMPILE  (4)  — fixture compiles, 7 contracts, no type_errors, all accepted
VMAP-TYPES    (5)  — map_get→Option[String], or_else→String, map_has_key→Bool, HeaderChain
VMAP-GET      (6)  — map_get present/absent; no Unknown error; raw string (not wrapped)
VMAP-HAS      (4)  — map_has_key true/false; no Unknown error; empty map → false
VMAP-OR       (6)  — or_else identity/fallback; nil→fallback; non-nil→identity
VMAP-BRIDGE   (4)  — HeaderChain with/without content-type; chain completes; fallback correct
VMAP-RACK     (4)  — P14 HeadersAwareHandler executes; 10/10 VM-executable
VMAP-SIDEKIQ  (4)  — P5 MetadataReader executes; queue present/absent; String return
VMAP-CLOSED   (5)  — no mutation, no non-String keys, no broad API, read-only handlers
VMAP-GAP      (6)  — representation decisions; pre-existing or_else; new handlers; gap closed
```

---

## Key Design Decisions

### Why no new Value variant for Map?

The VM already uses `Value::Record(BTreeMap)` for all key/value containers. Adding
a separate `Value::Map` variant would:
- Break existing JSON deserialization (all objects become Record)
- Require changes to `from_json`, `to_json`, `OP_GET_FIELD`, `OP_PUSH_RECORD`
- Provide no behavioral benefit for read-only access

**Decision:** `Map[String,String]` at runtime IS `Value::Record`. The semantic
distinction between Record and Map lives at the TypeChecker level only.

### Why no new opcode?

The compiler already emits `OP_CALL("map_get", 2)` for `map_get(m, key)` calls —
the `apply/call` compiler case falls through to `OP_CALL` with the function name
unchanged. Adding new opcodes (OP_MAP_GET etc.) would require compiler changes
and offer no advantage for the `CALL fn_name, argc` dispatch already in place.

**Decision:** OP_CALL handlers only. Compiler unchanged.

### Why both bare and qualified names?

The TypeChecker accepts `"map_get" | "stdlib.map.get"`. The Rust emitter does not
qualify map function names (unlike text stdlib which qualifies as `stdlib.text.*`).
So the SIR contains `"map_get"` (bare). The qualified alias `"stdlib.map.get"` is
provided for forward compatibility and symmetry with the text stdlib pattern.

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Does VM need a new Map value type? | **NO** — Value::Record serves as Map runtime |
| Does VM need new opcodes? | **NO** — OP_CALL dispatch sufficient |
| Was or_else already correct? | **YES** — pre-existing; Value::Nil = None path works |
| What function names does SIR emit? | `"map_get"` (bare, not qualified) |
| What is Option[String] in the VM? | None = Value::Nil, Some(s) = Value::String(s) |
| Is the Rack P14 gap now closed? | **YES** — HeadersAwareHandler 10/10 VM-executable |
| Is the Sidekiq P5 gap now closed? | **YES** — MetadataReader executes end-to-end |
| Are there mutation handlers? | **NO** — read-only only |
| Canon claim? | **NO** — lab-only |
| Stable runtime API claim? | **NO** — lab-only |

---

## Gaps Closed

| Gap (from prior cards) | Status |
|------------------------|--------|
| VM `map_get` bytecode (LAB-RACK-P14) | ✅ **CLOSED** |
| VM `map_get` bytecode (LAB-RESULT-ENVELOPE-P1 blocker #2) | ✅ **CLOSED** |
| Rack P14 HeadersAwareHandler VM execution | ✅ **CLOSED** |
| Sidekiq P5 MetadataReader VM execution | ✅ **CLOSED** |

## Remaining Open Gaps

| Gap | Status |
|-----|--------|
| VM map literal (`{}`) construction | Open — not in scope |
| VM map mutation (`map_set`, `map_delete`) | Open — not in scope; requires authorization |
| VM non-String-keyed maps | Open — lab-only String keys in v0 |
| Three-level chained field access | Open (from P14) |
| Multi-output callee | Open (from P14) |

---

## Prerequisites

| Prerequisite | Status |
|---|---|
| LAB-MAP-RUST-P1 (32/32) | ✅ TypeChecker map_get/or_else proofs |
| LAB-RACK-P14 (60/60) | ✅ HeadersAwareHandler TypeChecker complete; VM gap identified |
| LAB-SIDEKIQ-P5 (48/48) | ✅ MetadataReader TypeChecker complete |
| LAB-RESULT-ENVELOPE-P1 | ✅ Identified VM map_get as highest-priority blocker |
| LAB-RECORD-VM-P2 (42/42) | ✅ OP_GET_FIELD base |
| PROP-043-P5 (55/55) | ✅ Map[String,String] production surface |

---

## Authority

lab-only — no canon claim, no stable surface.  
`map_get` / `map_has_key` are lab-VM handlers (not canon grammar).  
`Value::Record` as Map runtime representation is an internal implementation detail.  
No production runtime claim. No mutation. No broad map API.  
String keys only (v0).
