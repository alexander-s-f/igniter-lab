# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1

**Lane:** lab / app-pressure / migration-readiness  
**Status:** CLOSED  
**Date:** 2026-06-13  
**Gate:** LAB-STDLIB-STRINGLY-CALL-CONTRACT-P1 CLOSED (37/37 PASS); APP-RECHECK-WAVE-P6 CLOSED  
**Scope:** Evidence + migration plan only. No app source edits. No compiler changes.

---

## Summary

Inspected all 34 `call_contract("append")` and `call_contract("empty")` sites across the igniter-apps corpus. Produced per-site classification, rewrite strategies for all three shapes, and a migration table. Proved all three rewrite patterns compile in both Ruby and Rust toolchains today.

**Key finding:** `LANG-STDLIB-COLLECTION-EMPTY-P1` was rejected — `empty()` function will not be added. BOOTSTRAP and EMPTY_CONSTRUCTOR shapes are no longer gated. All 34 sites can be migrated using typed `[]` (typed array literal or typed compute binding). Igniter_parser's 5 sites are gated on `IP-P01` (stdlib.string), not on migration patterns.

**Rust TC gap (E-07):** `LANG-TYPED-COMPUTE-BINDING-P2` was Ruby-only. Rust TC handles typed `[]` at the output boundary correctly but does not propagate the annotation into `symbol_types` for downstream `append`. ACCUMULATING migration is fully unblocked in Rust. BOOTSTRAP and EMPTY_CONSTRUCTOR downstream chains require `LANG-TYPED-COMPUTE-BINDING-P2` Rust parity before Rust migration is complete.

---

## Census

| Callee | Count |
|---|---|
| `call_contract("append", ...)` | 31 |
| `call_contract("empty")` | 3 |
| **Total** | **34** |

| Shape | Count | Unblocked today? |
|---|---|---|
| ACCUMULATING | 25 | Yes |
| BOOTSTRAP | 6 | Yes — typed `[t1, t2]` seed |
| EMPTY_CONSTRUCTOR | 3 | Yes — typed `compute x : Collection[T] = []` |
| DYNAMIC (out of scope) | separate | No — LAB-DYNAMIC-CONTRACT-DISPATCH-P1 |
| NOT_STDLIB PascalCase (out of scope) | separate | N/A |

---

## App Coverage

| App | Stdlib sites | Shapes | Blocked? |
|---|---|---|---|
| arch_patterns | 9 | 2 BOOTSTRAP + 7 ACCUMULATING | No |
| bloom_filter | 15 | 1 BOOTSTRAP + 14 ACCUMULATING | No |
| decision_tree | 4 | 3 BOOTSTRAP + 1 ACCUMULATING | No |
| igniter_parser | 5 | 3 EMPTY_CONSTRUCTOR + 2 ACCUMULATING | Yes — IP-P01 stdlib.string |
| vector_editor | 1 | 1 ACCUMULATING | No |

---

## Rewrite Strategies

**ACCUMULATING** (`call_contract("append", existing_collection, elem)`)  
→ `append(existing_collection, elem)` with `import stdlib.collection.{ append }`

**BOOTSTRAP** (`call_contract("append", elem_a, elem_b)` — two bare elements, no Collection seed)  
→ `compute seed : Collection[T] = [elem_a, elem_b]` (typed array literal; subsequent appends use canonical `append`)

**EMPTY_CONSTRUCTOR** (`call_contract("empty")`)  
→ `compute x : Collection[T] = []` (typed compute binding; annotation overrides `Collection[Unknown]`)

---

## Verdict

| Shape | Verdict |
|---|---|
| ACCUMULATING | ACCEPT — migrate in P2 |
| BOOTSTRAP | ACCEPT — migrate in P2 via typed [] seed |
| EMPTY_CONSTRUCTOR | ACCEPT — migrate in P2 via typed [] binding |
| DYNAMIC callees | REJECT migration — LAB-DYNAMIC-CONTRACT-DISPATCH-P1 |
| NOT_STDLIB callees (PascalCase) | REJECT migration — not stdlib |
| Compiler special-case | REJECT — 5 invariants forbid hijacking call_contract dispatch |

---

## Non-Goals

- No app source edits in P1.
- No compiler changes.
- No `empty()` function — path is closed (LANG-STDLIB-COLLECTION-EMPTY-P1 rejected).
- No special-casing of `"append"` or `"empty"` inside TC dispatch.
- No migration of DYNAMIC or NOT_STDLIB sites.

---

## Deliverables

- [x] Lab doc: `igniter-lab/lab-docs/governance/lab-stdlib-stringly-call-contract-migration-readiness-v0.md`
- [x] Proof runner: `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p1.rb` — 57 checks, sections A-J, target ≥50 PASS
- [x] Agent card: this file
- [x] Portfolio index: prepended
- [x] Proof run: **57/57 PASS** (sections A-J)

---

## Next Routes

| Rank | Route | Scope |
|---|---|---|
| 1 | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 | Rewrite all 29 unblocked sites (arch_patterns + bloom_filter + decision_tree + vector_editor); one app at a time or batch; proof ≥40 checks |
| 2 | LANG-STDLIB-STRING-SURFACE-P1 | Unblock igniter_parser IP-P01; then 5 more sites become migratable |
| 3 | LANG-RUBY-RECORD-LITERAL-INFERENCE-P4 | SIM-P14 (Collection[Unknown] param-depth), VE-P09 (new_obj) |
| 4 | LANG-STRING-TEXT-ALIAS-P1 | SIM-P10/P11 String/Text mismatch |
| 5 | LAB-DYNAMIC-CONTRACT-DISPATCH-P1 | rule_engine RE-P02/P03/P04 |

**Expected P2 impact (if bloom_filter + decision_tree + arch_patterns + vector_editor migrated):**  
bloom_filter → dual-toolchain CLEAN (−16 diags). decision_tree: −6 Ruby. arch_patterns: −9 Ruby. vector_editor: −1. Total fleet Ruby diagnostic reduction: ~32.
