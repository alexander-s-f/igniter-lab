# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2

**Card:** `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2`  
**Date:** 2026-06-13  
**Status:** CLOSED  
**Proof:** 62/62 PASS — `verify_lab_stdlib_stringly_call_contract_migration_p2.rb`  
**Gate:** LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 CLOSED

---

## Summary

This phase executed the source-level migration planned in P1. 24 of 29 unblocked stringly stdlib `call_contract("append",…)` sites were rewritten to canonical form. 5 sites in `arch_patterns/example.ig` (c0-c4 BOOTSTRAP → direct `Collection[Transition]` output) were deferred pending Rust TC parity for typed-compute binding propagation.

**bloom_filter** and **decision_tree** are now dual-toolchain CLEAN.  
**vector_editor** is Rust CLEAN; Ruby retains one pre-existing issue unrelated to this migration.  
**arch_patterns** retains 6 diagnostics from the deferred c0-c4 chain.

---

## Migration Table

### bloom_filter/example.ig

| Site | Line | Shape | Before | After | Deferred? |
|---|---|---|---|---|---|
| BF-S01 | 35 | BOOTSTRAP | `call_contract("append", s0, s1)` | `compute b0 : Collection[BitSlot] = [s0, s1]` | No |
| BF-S02 | 36 | ACCUMULATING | `call_contract("append", b0, s2)` | `append(b0, s2)` | No |
| BF-S03 | 37 | ACCUMULATING | `call_contract("append", b1, s3)` | `append(b1, s3)` | No |
| BF-S04 | 38 | ACCUMULATING | `call_contract("append", b2, s4)` | `append(b2, s4)` | No |
| BF-S05 | 39 | ACCUMULATING | `call_contract("append", b3, s5)` | `append(b3, s5)` | No |
| BF-S06 | 40 | ACCUMULATING | `call_contract("append", b4, s6)` | `append(b4, s6)` | No |
| BF-S07 | 41 | ACCUMULATING | `call_contract("append", b5, s7)` | `append(b5, s7)` | No |
| BF-S08 | 42 | ACCUMULATING | `call_contract("append", b6, s8)` | `append(b6, s8)` | No |
| BF-S09 | 43 | ACCUMULATING | `call_contract("append", b7, s9)` | `append(b7, s9)` | No |
| BF-S10 | 44 | ACCUMULATING | `call_contract("append", b8, s10)` | `append(b8, s10)` | No |
| BF-S11 | 45 | ACCUMULATING | `call_contract("append", b9, s11)` | `append(b9, s11)` | No |
| BF-S12 | 46 | ACCUMULATING | `call_contract("append", b10, s12)` | `append(b10, s12)` | No |
| BF-S13 | 47 | ACCUMULATING | `call_contract("append", b11, s13)` | `append(b11, s13)` | No |
| BF-S14 | 48 | ACCUMULATING | `call_contract("append", b12, s14)` | `append(b12, s14)` | No |
| BF-S15 | 49 | ACCUMULATING | `call_contract("append", b13, s15)` | `append(b13, s15)` | No |

**15 sites migrated.** Output is `output bf : BloomFilter` (record), not direct `Collection[T]` — Rust typed-[] propagation gap does not apply here.

### arch_patterns/pipeline.ig

| Site | Line | Shape | Before | After | Deferred? |
|---|---|---|---|---|---|
| AP-S01 | 39 | ACCUMULATING | `call_contract("append", ctx.audit_trail, "mw:validate_amount")` | `append(ctx.audit_trail, "mw:validate_amount")` | No |
| AP-S02 | 69 | ACCUMULATING | `call_contract("append", ctx.audit_trail, "mw:check_frozen")` | `append(ctx.audit_trail, "mw:check_frozen")` | No |
| AP-S03 | 105 | ACCUMULATING | `call_contract("append", ctx.audit_trail, "mw:check_balance")` | `append(ctx.audit_trail, "mw:check_balance")` | No |

**3 sites migrated.** Input `ctx.audit_trail : Collection[String]` is typed via `PipelineContext` field — safe ACCUMULATING in both TCs.

### arch_patterns/example.ig

| Site | Line | Shape | Before | After | Deferred? |
|---|---|---|---|---|---|
| AP-S04 | 65 | BOOTSTRAP | `call_contract("append", "pipeline:start", "pipeline:init")` | `compute empty_trail : Collection[String] = ["pipeline:start", "pipeline:init"]` | No |
| AP-S05 | 23 | BOOTSTRAP | `compute c0 = call_contract("append", t_start, t_init)` | — | **Yes — Rust gap** |
| AP-S06 | 24 | ACCUMULATING | `compute c1 = call_contract("append", c0, t_e1)` | — | **Yes — Rust gap** |
| AP-S07 | 25 | ACCUMULATING | `compute c2 = call_contract("append", c1, t_e2)` | — | **Yes — Rust gap** |
| AP-S08 | 26 | ACCUMULATING | `compute c3 = call_contract("append", c2, t_e3)` | — | **Yes — Rust gap** |
| AP-S09 | 27 | ACCUMULATING | `compute c4 = call_contract("append", c3, t_e4)` | — | **Yes — Rust gap** |

**1 site migrated (empty_trail). 5 sites deferred (c0-c4).** See deferred site analysis below.

### decision_tree/example.ig

| Site | Line | Shape | Before | After | Deferred? |
|---|---|---|---|---|---|
| DT-S01 | 32 | BOOTSTRAP | `call_contract("append", decision_income, decision_credit)` | `compute nodes_0 : Collection[TreeNode] = [decision_income, decision_credit]` | No |
| DT-S02 | 56 | BOOTSTRAP | `call_contract("append", feat_income_high, feat_credit_good)` | `compute features_good : Collection[FeatureEntry] = [feat_income_high, feat_credit_good]` | No |
| DT-S03 | 57 | BOOTSTRAP | `call_contract("append", feat_income_low, feat_credit_bad)` | `compute features_bad : Collection[FeatureEntry] = [feat_income_low, feat_credit_bad]` | No |

**3 sites migrated.** Elements are from `call_contract` registry results (`TreeNode`) or P3-inferred records used inside record literals — output is `output tree_3 : DecisionTree` (record), not direct Collection. Safe in both TCs.

### decision_tree/builder.ig

| Site | Line | Shape | Before | After | Deferred? |
|---|---|---|---|---|---|
| DT-S04 | 53 | ACCUMULATING | `call_contract("append", tree.nodes, node)` | `append(tree.nodes, node)` | No |

**1 site migrated.** Input `tree.nodes : Collection[TreeNode]` typed via `DecisionTree` field.

### vector_editor/document.ig

| Site | Line | Shape | Before | After | Deferred? |
|---|---|---|---|---|---|
| VE-S01 | 9 | ACCUMULATING | `call_contract("append", layer.objects, obj)` | `append(layer.objects, obj)` | No |

**1 site migrated.** Input `layer.objects : Collection[GraphicObject]` typed via `Layer` field.

---

## Deferred Sites: arch_patterns c0-c4

### Root Cause — Rust Typed-Compute Binding Propagation Gap

The c0-c4 chain in `arch_patterns/example.ig` follows this pattern:

```
compute t_start = { ... }     -- Transition literal
compute t_init  = { ... }     -- Transition literal
compute c0 : Collection[Transition] = [t_start, t_init]   -- BOOTSTRAP typed []
compute c1 = append(c0, t_e1)                              -- ACCUMULATING from typed []
...
compute c4 = append(c3, t_e4)
output c4 : Collection[Transition]                         -- DIRECT Collection output
```

`LANG-TYPED-COMPUTE-BINDING-P2` (Ruby-only) propagates the `Collection[Transition]` annotation from the `c0` binding into `symbol_types`. Rust TC does not implement this propagation: `c0`'s entry in `symbol_types` is `Collection[Unknown]`, so `append(c0, …)` returns `Collection[Unknown]`, and the output boundary check `Collection[Unknown]` vs `Collection[Transition]` fires `OOF-TY1`.

This gap does NOT affect:
- ACCUMULATING sites where the collection comes from an input-typed field (e.g., `ctx.audit_trail : Collection[String]`)
- BOOTSTRAP sites where the typed-[] result feeds a record literal output (e.g., bloom_filter `output bf : BloomFilter`)

It ONLY affects BOOTSTRAP → ACCUMULATING chains where the final value is directly output as `Collection[T]`.

### Deferral Decision

Migrating c0-c4 now would produce Ruby ok / Rust oof — a regression relative to the current state (both oof/6 for the same pre-existing reasons). Deferral preserves the status quo while the Rust gap is addressed.

**Route:** `LANG-RUST-TYPED-COMPUTE-BINDING-P1` — Rust parity for typed-compute binding propagation.

---

## App Compile Matrix

| App | Before Ruby | After Ruby | Before Rust | After Rust | Result |
|---|---|---|---|---|---|
| bloom_filter | oof/16 | **ok/0** | oof/15 | **ok/0** | **DUAL-CLEAN** |
| decision_tree | oof/7 | **ok/0** | oof/4 | **ok/0** | **DUAL-CLEAN** |
| vector_editor | oof/3 | oof/1 | oof/1 | **ok/0** | Rust CLEAN; Ruby VE-P09 |
| arch_patterns | oof/14 | oof/6 | oof/8 | oof/6 | Partial (c0-c4 deferred) |

### vector_editor Ruby residual

`oof/1` — `OOF-P1 Unresolved symbol: new_obj` in `tools.ig`. This is `VE-P09`, first surfaced in Wave P6 after LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved `default_style`. Unrelated to stringly stdlib migration. Route: `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` or candidate re-pass.

### arch_patterns residual

`oof/6` — 5× OOF-TY0 (`call_contract: unknown callee 'append'` for c0-c4) + 1× OOF-TY1 (`Output type mismatch: expected Collection[Transition], got Unknown` — cascade from c4 returning Unknown). Both TCs identical. Clears when LANG-RUST-TYPED-COMPUTE-BINDING-P1 enables c0-c4 migration.

---

## Counts

| Category | Count |
|---|---|
| Sites scanned at P1 census | 34 (append=31, empty=3) |
| Sites out of scope (igniter_parser, blocked by IP-P01) | 5 |
| Sites targeted in P2 (unblocked) | 29 |
| Sites migrated | 24 |
| Sites deferred (c0-c4, Rust gap) | 5 |
| Sites remaining stdlib-form total | 10 (5 arch_patterns c0-c4 + 5 igniter_parser) |

---

## Invariants Preserved

- No compiler source files changed (Ruby TC: `@call_contract_registry` unchanged; Rust TC: `contract_registry.get(callee_name)` unchanged)
- User PascalCase `call_contract` sites untouched (MakeLeaf, MakeDecision, AddNode, AppendObjectToLayer, ExecuteRules, Insert, Query, etc.)
- Dynamic variable callee in rule_engine untouched
- igniter_parser stdlib sites untouched (blocked by IP-P01)
- No new OOF codes introduced; only pre-existing OOF-TY0, OOF-TY1, OOF-P1

---

## Routes

| Track | Next step |
|---|---|
| `LANG-RUST-TYPED-COMPUTE-BINDING-P1` | Rust parity for typed [] annotation propagation into symbol_types — enables c0-c4 arch_patterns migration |
| `LANG-STDLIB-STRING-SURFACE-P1` | igniter_parser 5 sites can migrate once string stdlib is available |
| `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` | VE-P09 new_obj resolution (Ruby only) |
