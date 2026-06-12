# LAB-STDLIB-STRINGLY-CALL-CONTRACT-P1 — Stringly Stdlib call_contract Classification

**Track:** lab / stdlib / call_contract / routing
**Route:** RESEARCH / CLASSIFICATION PROOF
**Status:** CLOSED / PROVED — 37/37 PASS
**Date:** 2026-06-12
**Grounding:** LAB-RUBY-CALL-CONTRACT-PARITY-P1 (56/56), APP-RECHECK-WAVE-P2

---

## Verdict: PROVED — 37/37 PASS

**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_p1.rb`
**Classification doc:** `igniter-lab/lab-docs/governance/lab-stdlib-stringly-call-contract-classification-p1-v0.md`

---

## Scope

Enumerate, classify, and route the 34 `call_contract("append"/"empty"/...)` calls in the
app corpus. No implementation. No source rewrites. No stdlib changes. No VM changes.

---

## Census (Confirmed 37/37)

| Callee | Count | Shape(s) |
|--------|-------|----------|
| `"append"` | 31 | BOOTSTRAP (6) + ACCUMULATING (25) |
| `"empty"` | 3 | EMPTY_CONSTRUCTOR (3) |
| **Total** | **34** | — |

No other stdlib-form callees. Apps use direct stdlib for `is_empty`, `concat`, `map`, etc.

---

## Shape Taxonomy

| Shape | Count | First arg | Second arg | Root cause |
|-------|-------|-----------|------------|------------|
| **ACCUMULATING** | 25 | `Collection[T]` field/var | element `T` | Should be `append(coll, elem)` |
| **BOOTSTRAP** | 6 | bare element `T` | bare element `T` | No `empty()` → can't seed collection |
| **EMPTY_CONSTRUCTOR** | 3 | (none) | (none) | No `empty()` stdlib function |

---

## Why NOT to Special-Case Stdlib Names in `call_contract` (5 invariants)

1. **Registry contract** — `call_contract` registry is built from module contracts only; stdlib names never appear there. "Not found in this module" is semantically correct.
2. **Bootstrap arity mismatch** — `call_contract("append", T, T)` would need bootstrap detection (T×T → Collection[T]); canonical `stdlib.collection.append` is `Collection[T]×T → Collection[T]`. Different signatures.
3. **Double dispatch** — `append(...)` is already handled at `when "append"` in `infer_call`. Routing from `call_contract` would create a second path for the same operation.
4. **SIR structural mismatch** — `call_contract(...)` SIR node has `fn: "call_contract"`; stdlib route needs `fn: "stdlib.collection.append"`. Rewriting the fn key in TC violates the emitter boundary.
5. **Callee invariant** — the invariant "callee is a verified, pure, in-scope contract" must hold. Allowlisting stdlib names silently widens this without authority.

---

## Route Decision

| Shape | Count | Route | Blocker |
|-------|-------|-------|---------|
| ACCUMULATING | 25 | `call_contract("append", c, e)` → `append(c, e)` | **None — works today** |
| BOOTSTRAP | 6 | `call_contract("append", t1, t2)` → `append(append(empty(), t1), t2)` | **LANG-STDLIB-COLLECTION-EMPTY-P1** |
| EMPTY_CONSTRUCTOR | 3 | `call_contract("empty")` → `empty()` | **LANG-STDLIB-COLLECTION-EMPTY-P1** |

---

## Proof Matrix (37/37)

| Section | Checks | Topic |
|---------|--------|-------|
| A | 5 | Census — callee names, counts, files, apps |
| B | 6 | Shape classification — BOOTSTRAP / ACCUMULATING / EMPTY_CONSTRUCTOR |
| C | 6 | Blocking — OOF-TY0 in Ruby + Rust for all 3 shapes |
| D | 5 | Direct stdlib alternative — `append()` works; `empty()` absent; bootstrap blocked |
| E | 5 | Why not special-case — 5 invariants proved via TC source + runtime |
| F | 6 | Route decision — migration counts, blocker gates |
| G | 4 | Inventory — `append` present; `empty` absent; next track clean |

---

## Next Routes

| Card | Scope |
|------|-------|
| **LANG-STDLIB-COLLECTION-EMPTY-P1** | Proposal: `empty(): → Collection[T]` stdlib function; unblocks 9 calls |
| **LANG-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1** | Source rewrite: all 34 calls; gates on LANG-STDLIB-COLLECTION-EMPTY-P1 for bootstrap/empty shapes |
