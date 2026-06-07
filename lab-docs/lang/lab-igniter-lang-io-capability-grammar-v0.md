# Lab: igniter-lang IO.Capability Grammar — PROP-035 v0

**Status:** experiment-pass
**Date:** 2026-06-07
**Tracks:** stdlib/IO.NetworkCapability, lang/grammar
**PROP:** PROP-035-effect-surface-io-capability-v0 (igniter-lang)
**Evidence:** `<igniter-lang>/experiments/io_capability_proof/` — 64/64 PASS
**Lab predecessor:** LAB-STDLIB-NET-P2..P6 (200/200), LAB-STDLIB-IO-P2..P10

---

## 1. What landed in the compiler

PROP-035 closes the deferral from PROP-031 §1 ("No Effect Surface validation, deferred
to PROP-035"). Two new grammar productions were added to the igniter-lang Ruby compiler
at the contract body level:

### `capability <name>: <CapType>`

Declares a named IO capability inside a contract body.

```igniter
effect contract ConnectToService {
  capability net_conn: IO.NetworkCapability
  effect connect_to_service using net_conn
}
```

### `effect <name> using <cap_ref>`

Binds an effect surface to a declared capability. `cap_ref` must resolve to a
`capability` declaration in the same contract body.

---

## 2. Pipeline changes

| Stage | File | What was added |
|---|---|---|
| Parser | `lib/igniter_lang/parser.rb` | `parse_capability_decl`, `parse_effect_binding_decl`; dispatch in `parse_body_decl` |
| Classifier | `lib/igniter_lang/classifier.rb` | `when "capability"`, `when "effect_binding"` handlers; OOF-M2/M4/M5 post-loop checks |
| TypeChecker | `lib/igniter_lang/typechecker.rb` | IO.* → `"IO.Capability"` opaque sentinel; effect_binding → `"Unit"` |
| Source fixtures | `source/io_capability_basic.ig` | Valid `effect` contract with capability + binding |
| Source fixtures | `source/io_capability_oof_blocked.ig` | OOF-M2/M4/M5 diagnostic scenarios |

---

## 3. New OOF diagnostic codes

| Code | Stage | Trigger |
|---|---|---|
| OOF-M2 | Classifier | `pure` contract with a `capability` body declaration |
| OOF-M4 | Classifier | `effect_binding` references an undeclared capability name |
| OOF-M5 | Classifier | `capability` declared but not referenced by any `effect` binding |

---

## 4. Relationship to lab proofs

The compiler enforces grammar structure only (capability declaration, effect binding,
three OOF codes). Everything about the IO.NetworkCapability **schema, delegation algebra,
and safety policies** is lab-only territory, proved in the following cards:

| Card | Checks | Scope |
|---|---|---|
| LAB-STDLIB-NET-P2 | 53/53 | JSON schema, delegation algebra (8 conditions), NET-1..NET-6 policies |
| LAB-STDLIB-NET-P3 | 61/61 | FFI surface, stub mode, operation sequence |
| LAB-STDLIB-NET-P4 | 42/42 | Compiler escape classification, all 10 E-NET-* diagnostic codes |
| LAB-STDLIB-NET-P5 | 44/44 | Glob semantics, direction:both compose, multi-hop chains, bind-address, wildcard+loopback |
| LAB-STDLIB-NET-P6 | ~36/36 | Dead grant detection, compose bind_address options A/B/C |
| PROP-035 grammar proof | 64/64 | Parsing → classification → type-checking |
| **Total** | **~300+** | |

---

## 5. What the compiler does not do (by design)

- Does not validate IO.NetworkCapability JSON field values (runtime concern)
- Does not resolve capability delegation chains at compile time (proved in NET-P2/P5)
- Does not perform runtime capability injection (Phase 2)
- OOF-M3 (authority resolution for `privileged` contracts) — deferred to PROP-034

---

## 6. IO.Capability type in the TypeChecker

All `IO.*` types normalise to the `"IO.Capability"` opaque sentinel (not `"Unknown"`).
The compiler does not validate the shape of the capability value at compile time.

```
capability net_conn: IO.NetworkCapability
→ typed output: { "type": { "name": "IO.Capability", "params": [] }, "resolved": true }
```

The `resolved: true` flag confirms the type is recognized (not `Unknown`), which prevents
false type-mismatch diagnostics.

---

## 7. Non-claims

- `IO.Capability` is not a Published Runtime Type
- The NET-P2..P6 algebra is not a canonical grammar specification
- PROP-035 is experiment-pass only; it is not a production-ready surface
- This document does not claim portability guarantees or public runtime support
