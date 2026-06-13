# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2

**Status:** CLOSED  
**Date closed:** 2026-06-13  
**Gate:** LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 CLOSED  
**Proof:** 62/62 PASS — `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p2.rb`  
**Lab doc:** `igniter-lab/lab-docs/governance/lab-stdlib-stringly-call-contract-migration-p2-v0.md`

---

## Scope

Migrate all unblocked stringly stdlib `call_contract("append",…)` sites in app source files to canonical form. No compiler changes. Source edits app-local only.

Apps in scope: `arch_patterns`, `bloom_filter`, `decision_tree`, `vector_editor`  
Shapes: ACCUMULATING (`append(coll, elem)`), BOOTSTRAP (typed `[elem_a, elem_b]` seed)  
Out of scope: `igniter_parser` (IP-P01), dynamic callees (rule_engine), user PascalCase contracts

---

## Results

### Sites Migrated: 24

| App | File | Shape | Sites |
|---|---|---|---|
| bloom_filter | example.ig | BOOTSTRAP ×1 + ACCUMULATING ×14 | 15 |
| arch_patterns | pipeline.ig | ACCUMULATING ×3 | 3 |
| arch_patterns | example.ig | BOOTSTRAP ×1 (empty_trail) | 1 |
| decision_tree | example.ig | BOOTSTRAP ×3 | 3 |
| decision_tree | builder.ig | ACCUMULATING ×1 | 1 |
| vector_editor | document.ig | ACCUMULATING ×1 | 1 |

### Sites Deferred: 5

`arch_patterns/example.ig` lines 23-27 (c0-c4):  
BOOTSTRAP `Collection[Transition]` annotation → ACCUMULATING chain → `output c4 : Collection[Transition]` (direct Collection). Rust TC gap: `LANG-TYPED-COMPUTE-BINDING-P2` is Ruby-only; Rust does not propagate typed-[] annotation into `symbol_types`, causing OOF-TY1 on direct Collection output from append chain rooted in typed [].  
**Route:** `LANG-RUST-TYPED-COMPUTE-BINDING-P1`

---

## Compile Matrix

| App | Ruby before | Ruby after | Rust before | Rust after |
|---|---|---|---|---|
| bloom_filter | oof/16 | **ok/0** | oof/15 | **ok/0** |
| decision_tree | oof/7 | **ok/0** | oof/4 | **ok/0** |
| vector_editor | oof/3 | oof/1 | oof/1 | **ok/0** |
| arch_patterns | oof/14 | oof/6 | oof/8 | oof/6 |

New dual-CLEAN apps: **bloom_filter**, **decision_tree**  
Rust CLEAN apps: bloom_filter, decision_tree, vector_editor  
arch_patterns residual: 5×OOF-TY0 (c0-c4) + 1×OOF-TY1 (c4 cascade)  
vector_editor Ruby residual: VE-P09 (`new_obj` unresolved — unrelated to migration)

---

## Invariants

- No compiler source changes
- PascalCase user contracts preserved
- Dynamic callees in rule_engine preserved
- igniter_parser stdlib sites preserved
- No new OOF codes; existing OOF-TY0/TY1/P1 only
- No absolute paths in any artifact

---

## Routes Out

| Track | Priority |
|---|---|
| `LANG-RUST-TYPED-COMPUTE-BINDING-P1` | Unblocks arch_patterns c0-c4 (5 deferred sites) |
| `LANG-STDLIB-STRING-SURFACE-P1` | Unblocks igniter_parser 5 sites |
| `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` | Resolves VE-P09 (Ruby-only) |
