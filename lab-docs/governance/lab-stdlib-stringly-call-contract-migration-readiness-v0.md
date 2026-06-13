# Lab — Stringly stdlib call_contract Migration Readiness

**Card:** LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1  
**Date:** 2026-06-13  
**Gate:** LAB-STDLIB-STRINGLY-CALL-CONTRACT-P1 CLOSED (37/37 PASS — census + classification confirmed)  
**Trigger:** APP-RECHECK-WAVE-P6 CLOSED — P3 resolved all ACTIVE_TRUE_INTERMEDIATE symbols, exposing stringly append as the dominant cross-app blocker  
**Scope:** Evidence + migration plan only. No app source edits. No compiler changes.

---

## Background

LAB-STDLIB-STRINGLY-CALL-CONTRACT-P1 (2026-06-13) classified all 34 `call_contract("append"/"empty")` sites into three shapes and recommended:

- ACCUMULATING (25 sites): migrate today → `append(coll, elem)`
- BOOTSTRAP (6 sites): gated on `LANG-STDLIB-COLLECTION-EMPTY-P1` to produce typed seed
- EMPTY_CONSTRUCTOR (3 sites): gated on `LANG-STDLIB-COLLECTION-EMPTY-P1`

**Key update:** `LANG-STDLIB-COLLECTION-EMPTY-P1` was rejected — `empty()` function will not be added. The route for BOOTSTRAP and EMPTY_CONSTRUCTOR is instead:

- **BOOTSTRAP:** typed array literal seed — `compute c0 : Collection[T] = [elem1, elem2]`
- **EMPTY_CONSTRUCTOR:** typed empty compute — `compute x : Collection[T] = []`

Both are already supported today via `LANG-TYPED-COMPUTE-BINDING-P2` and `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3`. All 34 sites are unblocked.

---

## Census Summary

| Callee | Sites | Apps |
|---|---|---|
| `"append"` | 31 | arch_patterns, bloom_filter, decision_tree, igniter_parser, vector_editor |
| `"empty"` | 3 | igniter_parser |
| **Total** | **34** | **5 apps, 9 source files** |

| Shape | Sites | Blocked today? |
|---|---|---|
| ACCUMULATING | 25 | No — `append(coll, elem)` compiles today (both TCs) |
| BOOTSTRAP | 6 | No — typed `[elem1, elem2]` seed compiles today (both TCs) |
| EMPTY_CONSTRUCTOR | 3 | No — `compute x : Collection[T] = []` compiles today (both TCs) |

igniter_parser's 5 sites (3 EMPTY_CONSTRUCTOR + 2 ACCUMULATING) are behind IP-P01 (`OOF-IMP2 stdlib.string`). Migration patterns are correct; execution is gated on `LANG-STDLIB-STRING-SURFACE-P1`.

---

## Migration Table

| App | File | Line | Callee | Shape | Rewrite | Blockers | Next card |
|---|---|---|---|---|---|---|---|
| arch_patterns | example.ig | 23 | append | BOOTSTRAP | `compute c0 : Collection[Transition] = [t0, t1]` | None | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 |
| arch_patterns | example.ig | 24 | append | ACCUMULATING | `compute c1 = append(c0, t2)` | None | same |
| arch_patterns | example.ig | 25 | append | ACCUMULATING | `compute c2 = append(c1, t3)` | None | same |
| arch_patterns | example.ig | 26 | append | ACCUMULATING | `compute c3 = append(c2, t4)` | None | same |
| arch_patterns | example.ig | 27 | append | ACCUMULATING | `compute c4 = append(c3, t5)` | None | same |
| arch_patterns | example.ig | 65 | append | BOOTSTRAP | `compute empty_trail : Collection[String] = ["pipeline:start", "pipeline:init"]` | None | same |
| arch_patterns | pipeline.ig | 39 | append | ACCUMULATING | `compute new_trail = append(ctx.audit_trail, "mw:validate_amount")` | None | same |
| arch_patterns | pipeline.ig | 69 | append | ACCUMULATING | `compute new_trail = append(ctx.audit_trail, "mw:check_frozen")` | None | same |
| arch_patterns | pipeline.ig | 105 | append | ACCUMULATING | `compute new_trail = append(ctx.audit_trail, "mw:check_balance")` | None | same |
| bloom_filter | example.ig | 35 | append | BOOTSTRAP | `compute b0 : Collection[BitSlot] = [s0, s1]` | None | same |
| bloom_filter | example.ig | 36 | append | ACCUMULATING | `compute b1 = append(b0, s2)` | None | same |
| bloom_filter | example.ig | 37 | append | ACCUMULATING | `compute b2 = append(b1, s3)` | None | same |
| bloom_filter | example.ig | 38 | append | ACCUMULATING | `compute b3 = append(b2, s4)` | None | same |
| bloom_filter | example.ig | 39 | append | ACCUMULATING | `compute b4 = append(b3, s5)` | None | same |
| bloom_filter | example.ig | 40 | append | ACCUMULATING | `compute b5 = append(b4, s6)` | None | same |
| bloom_filter | example.ig | 41 | append | ACCUMULATING | `compute b6 = append(b5, s7)` | None | same |
| bloom_filter | example.ig | 42 | append | ACCUMULATING | `compute b7 = append(b6, s8)` | None | same |
| bloom_filter | example.ig | 43 | append | ACCUMULATING | `compute b8 = append(b7, s9)` | None | same |
| bloom_filter | example.ig | 44 | append | ACCUMULATING | `compute b9 = append(b8, s10)` | None | same |
| bloom_filter | example.ig | 45 | append | ACCUMULATING | `compute b10 = append(b9, s11)` | None | same |
| bloom_filter | example.ig | 46 | append | ACCUMULATING | `compute b11 = append(b10, s12)` | None | same |
| bloom_filter | example.ig | 47 | append | ACCUMULATING | `compute b12 = append(b11, s13)` | None | same |
| bloom_filter | example.ig | 48 | append | ACCUMULATING | `compute b13 = append(b12, s14)` | None | same |
| bloom_filter | example.ig | 49 | append | ACCUMULATING | `compute b14 = append(b13, s15)` | None | same |
| decision_tree | builder.ig | 53 | append | ACCUMULATING | `compute new_nodes = append(tree.nodes, node)` | None | same |
| decision_tree | example.ig | 32 | append | BOOTSTRAP | `compute nodes_0 : Collection[TreeNode] = [decision_income, decision_credit]` | None | same |
| decision_tree | example.ig | 56 | append | BOOTSTRAP | `compute features_good : Collection[FeatureEntry] = [feat_income_high, feat_credit_good]` | None | same |
| decision_tree | example.ig | 57 | append | BOOTSTRAP | `compute features_bad : Collection[FeatureEntry] = [feat_income_low, feat_credit_bad]` | None | same |
| igniter_parser | api.ig | 9 | empty | EMPTY_CONSTRUCTOR | `compute initial_tokens : Collection[Token] = []` | IP-P01 stdlib.string | LANG-STDLIB-STRING-SURFACE-P1 first |
| igniter_parser | api.ig | 21 | empty | EMPTY_CONSTRUCTOR | `compute initial_nodes : Collection[AstNode] = []` | IP-P01 stdlib.string | same |
| igniter_parser | lexer.ig | 26 | append | ACCUMULATING | `compute new_tokens = append(state.tokens, new_token)` | IP-P01 stdlib.string | same |
| igniter_parser | parser.ig | 10 | empty | EMPTY_CONSTRUCTOR | `compute empty_children : Collection[String] = []` | IP-P01 stdlib.string | same |
| igniter_parser | parser.ig | 19 | append | ACCUMULATING | `compute new_nodes = append(state.nodes, module_node)` | IP-P01 stdlib.string | same |
| vector_editor | document.ig | 9 | append | ACCUMULATING | `compute new_objects = append(layer.objects, obj)` | None | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 |

---

## Rewrite Shapes

### ACCUMULATING

**Pattern:** `call_contract("append", existing_collection, new_element)` where the first argument is an existing `Collection[T]` (field access like `ctx.audit_trail` or a chained intermediate like `b0`).

**Rewrite:**
```
-- Before
compute new_items = call_contract("append", items, new_item)

-- After
import stdlib.collection.{ append }
compute new_items = append(items, new_item)
```

Both toolchains already support canonical `append`. No type annotation needed when the input Collection type is already known.

### BOOTSTRAP

**Pattern:** `call_contract("append", elem_a, elem_b)` where both arguments are bare same-typed elements (not a Collection). Prior routing said this needed `empty()` for a typed seed — that function was rejected. The correct route is a typed array literal.

**Rewrite:**
```
-- Before
compute c0 = call_contract("append", t0, t1)

-- After (no import needed for typed [] seed)
compute c0 : Collection[T] = [t0, t1]
```

The typed annotation `Collection[T]` activates `LANG-TYPED-COMPUTE-BINDING-P2`. Subsequent `append(c0, t2)` then receives a proper `Collection[T]` first argument. The `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` ensures `t0`/`t1` are already typed for P3 cases (non-string elements).

### EMPTY_CONSTRUCTOR

**Pattern:** `call_contract("empty")` — zero-argument empty collection constructor. Prior routing said this was the direct use case for `empty()` — that function was rejected. The route is a typed empty compute binding.

**Rewrite:**
```
-- Before
compute initial_tokens = call_contract("empty")

-- After
compute initial_tokens : Collection[Token] = []
```

The typed annotation activates `LANG-TYPED-COMPUTE-BINDING-P2`. `[]` produces `Collection[Unknown]`; the annotation overrides to `Collection[Token]`. No function call needed.

---

## Out of Scope

| Shape | Classification | Reason | Route |
|---|---|---|---|
| `call_contract(variable_name, ...)` in rule_engine | DYNAMIC | Variable callee — cannot be statically classified | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| `call_contract("MakeLeaf", ...)`, `call_contract("MakeCell", ...)`, etc. | NOT_STDLIB | PascalCase callee — user module contract, not stdlib | No migration needed |
| `call_contract("ReplayEvents5", ...)` | NOT_STDLIB | User module contract | No migration needed |

---

## Rust TC Gap (E-07)

**Finding:** `LANG-TYPED-COMPUTE-BINDING-P2` was implemented in Ruby only. Rust TC handles the output-boundary check for `compute x : Collection[T] = []` correctly (output type matches), but does NOT propagate the annotation into `symbol_types` for downstream use. When `append(x, elem)` is called and `x` came from a typed empty array binding, Rust resolves `x` from `symbol_types` as `Collection[Unknown]` (the raw inference from `[]`), not `Collection[T]`.

**Consequence:**
- ACCUMULATING migration: fully works in both TCs (first arg is input-typed or field-access Collection)
- BOOTSTRAP typed `[t1, t2]` seed: array literal output only works in both TCs; downstream `append` after typed `[]` seed fails in Rust → OOF-TY1
- EMPTY_CONSTRUCTOR direct output: works in both TCs
- EMPTY_CONSTRUCTOR with downstream append: fails in Rust

**Route for Rust gap:** `LANG-TYPED-COMPUTE-BINDING-P2` Rust parity. Until then, BOOTSTRAP and EMPTY_CONSTRUCTOR rewrites in Rust source are blocked at the downstream-append step. ACCUMULATING rewrites are unblocked today.

---

## Verdict

**ACCEPT** all three shapes as migration targets for `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` (source rewrite).

| Shape | Ruby verdict | Rust verdict | Reason |
|---|---|---|---|
| ACCUMULATING (25 sites) | ACCEPT | ACCEPT | canonical `append(coll, elem)` compiles today in both TCs |
| BOOTSTRAP (6 sites) | ACCEPT | CONDITIONAL | typed `[elem1, elem2]` seed output works in Rust; downstream append after typed seed needs LANG-TYPED-COMPUTE-BINDING-P2 Rust parity |
| EMPTY_CONSTRUCTOR (3 sites) | ACCEPT | CONDITIONAL | typed `[]` output works in Rust; downstream append needs Rust P2 parity |
| DYNAMIC (rule_engine) | REJECT | REJECT | variable callee; separate design required |
| NOT_STDLIB (PascalCase) | REJECT | REJECT | user contract calls; migration would break contract dispatch |
| COMPILER SPECIAL-CASE | REJECT | REJECT | 5 invariants forbid `call_contract("append")` hijacking inside TC (established in P1) |

**igniter_parser** (5 sites, all three shapes): ACCEPT patterns, CONDITIONAL execution. Migration is blocked by `IP-P01` (`OOF-IMP2 stdlib.string`). Patterns are correct. Execute after `LANG-STDLIB-STRING-SURFACE-P1`.

---

## App Impact Projection

| App | Current Ruby diags | After migration | Net |
|---|---|---|---|
| arch_patterns | 14 | ~5 (remaining stringly cascade + OOF-TY1) | −9 |
| bloom_filter | 16 | 0 (BF-P01 is the only blocker; Ruby cascade `b14` clears automatically) | −16 |
| decision_tree | 7 | ~1 (OOF-TY1 output cascade may remain) | −6 |
| vector_editor | 3 | 2 (VE-P09 remains; only the document.ig append site migrates) | −1 |
| igniter_parser | 1 (OOF-IMP2) | 1 (unchanged — gated on IP-P01) | 0 |

Bloom_filter would go dual-toolchain CLEAN after migration — the 15-site append chain in `InitFilter16` is the only blocker.

---

## Non-Goals

- Do not special-case `call_contract("append"/"empty")` inside the compiler. The 5 invariants from P1 still hold.
- Do not implement `empty()` as a function. Typed `[]` is the route.
- Do not migrate `DYNAMIC` or `NOT_STDLIB` callees in this card.
- Do not rewrite igniter_parser source until `LANG-STDLIB-STRING-SURFACE-P1` unblocks it.
- Do not change any compiler files (typechecker.rb, typechecker.rs, emitter, parser).

---

## Proof

Proof runner: `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p1.rb`

Target: ≥50/57 PASS across sections A–J.
