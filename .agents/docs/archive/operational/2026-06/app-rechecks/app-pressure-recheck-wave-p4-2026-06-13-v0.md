# APP-RECHECK-WAVE-P4 Rollup — 2026-06-13

**Governance card:** `APP-RECHECK-WAVE-P4`
**Trigger:** LANG-TYPED-COMPUTE-BINDING-P2 CLOSED (48/48 PASS)
**Scope:** Fresh compile recheck for all 10 igniter-apps; evidence and registry updates only; no app source edits, no compiler/typechecker/parser implementation.

---

## Compile Results

| App | Rust | Ruby | Δ from Wave P3 |
|---|---|---|---|
| dsa | ok / 0 | oof / 4 | UNCHANGED |
| vector_editor | oof / 1 | oof / 4 | UNCHANGED |
| decision_tree | oof / 4 | oof / 7 | UNCHANGED |
| arch_patterns | oof / 8 | oof / 14 | UNCHANGED |
| dataframes | ok / 0 | oof / 2 | UNCHANGED |
| rule_engine | oof / 2 | oof / 3 | UNCHANGED |
| neural_net | ok / 0 | oof / 2 | UNCHANGED |
| vector_math | ok / 0 | oof / 41 | UNCHANGED |
| advanced_logistics | ok / 0 | ok / 0 | STILL CLEAN |
| sim_framework | ok / 0 | oof / 4 | NEW FIRST RUBY CHECK |

---

## Dominant Finding: LANG-TYPED-COMPUTE-BINDING-P2 Had Zero Impact

LANG-TYPED-COMPUTE-BINDING-P2 added annotation-authoritative bind-type resolution for `compute name : Type = expr` bindings where the inferred RHS is Unknown-bearing. **No app in the corpus uses this form.** All apps use unannotated computes or stringly call_contract returns:

- `compute e0 = { index: 0, value: 10 }` — unannotated record literal
- `compute new_objects = call_contract("append", layer.objects, obj)` — stringly call_contract return

P2 only applies when a type annotation is present on the compute binding. Zero apps had such a form, so zero resolutions resulted.

---

## Root Cause Re-Classification

Wave P3 attributed all "compute binding" pressures to `LANG-TYPED-COMPUTE-BINDING-P1`. This was incorrect. The actual root causes are:

### Gap A: Unannotated record literal → Unknown (8+ apps)

Ruby TC `infer_record_literal` (typechecker.rb line ~2927) returns `type_ir("Unknown")` for all unannotated intermediate compute nodes that have no corresponding output declaration. Affected symbols:

- **dsa:** `e0`, `s`, `edge1`, `c_h` — DSA-P10
- **neural_net:** `w1`, `x1` — NN-P09
- **dataframes:** `c00`, `p1` — DF-P10
- **vector_editor:** `default_style`, `new_pos` — VE-P08 (partial)
- **arch_patterns:** `genesis` — AP-P12 (partial)
- **rule_engine:** `tx1` — RE-P07 (partial)
- **vector_math:** `gravity`, `point`, `b`, `a_min`, `min_pt` — VM-P09
- **sim_framework:** `pop_constraint`, `wolves` — SIM-P12, SIM-P13

Route: **`LANG-RUBY-RECORD-LITERAL-INFERENCE-P1`** (highest-priority new card)

### Gap B: Stringly call_contract("append", ...) → unresolved callee (4 apps)

Both toolchains fail to dispatch stdlib functions when called via `call_contract("stdlib_fn_name", ...)` form. Affected:

- **vector_editor:** `new_objects` — VE-P08 (partial); Rust oof/1 + Ruby oof/1
- **decision_tree:** `new_nodes`, `nodes_0`, `features_good` cascade — DT-P09; Rust oof/4 + Ruby oof/4
- **arch_patterns:** `new_trail` ×3 cascade — AP-P12 (partial); Rust oof/7 + Ruby oof/9

Route: **`LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`** (second-priority)

### Gap C: String/Text alias (sim_framework only)

Ruby TC `concat(...)` returns type `"Text"` but `sim_framework/types.ig` declares `rule_name : String`. These names are treated as distinct types, causing OOF-TY0 and cascade OOF-TY1.

- **sim_framework:** `rule_name` mismatch → SIM-P10; cascade OOF-TY1 → SIM-P11

Route: **`LANG-STRING-TEXT-ALIAS-P1`**

### Gap D: Tier 2 dynamic dispatch → Unknown (rule_engine only)

`call_contract(variable_callee, tx)` returns Unknown in both toolchains. Output variable `d` and field access `Unknown.action` remain unresolved. This was correctly classified in Wave P3 as RE-P02/RE-P07 and is unchanged.

Route: **`LAB-DYNAMIC-CONTRACT-DISPATCH-P1`** (safety-gated; pre-existing)

---

## New Pressures Added

| ID | App | Description | Status |
|---|---|---|---|
| SIM-P10 | sim_framework | String/Text naming mismatch on `rule_name` field | ACTIVE |
| SIM-P11 | sim_framework | OOF-TY1 cascade from SIM-P10 | ACTIVE |
| SIM-P12 | sim_framework | Unannotated record literal — `pop_constraint` | ACTIVE |
| SIM-P13 | sim_framework | Unannotated record literal — `wolves` | ACTIVE |

---

## Pressure Re-Routings

| App | Pressure | Old Route | New Route |
|---|---|---|---|
| dsa | DSA-P10 | `LANG-TYPED-COMPUTE-BINDING-P1` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |
| neural_net | NN-P09 | `LANG-TYPED-COMPUTE-BINDING-P1` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |
| dataframes | DF-P10 | `LANG-TYPED-COMPUTE-BINDING-P1` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |
| vector_editor | VE-P08 (partial) | `LANG-TYPED-COMPUTE-BINDING-P1` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` (default_style/new_pos) |
| arch_patterns | AP-P12 (partial) | `LANG-TYPED-COMPUTE-BINDING-P1` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` (genesis) |
| rule_engine | RE-P07 (partial) | `LANG-TYPED-COMPUTE-BINDING-P1` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` (tx1) |
| vector_math | VM-P09 | `LANG-TYPED-COMPUTE-BINDING-P1` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |
| decision_tree | DT-P09 | `LANG-TYPED-COMPUTE-BINDING-P1` | stringly stdlib migration (cascade from append) |

---

## Recommended Next Cards (Priority Order)

### 1. `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` — HIGHEST IMPACT

**Scope:** Modify `infer_record_literal` in `igniter-lang/lib/igniter_lang/typechecker.rb` (line ~2883) to infer field types from `@type_shapes` even when no `output_type_hint` is set for the node. The method currently returns `type_ir("Unknown")` unconditionally when `@output_type_hints[node_name]` is absent.

**Impact:** Resolves or unblocks pressures in 8 apps (DSA-P10, NN-P09, DF-P10, VE-P08-partial, AP-P12-partial, RE-P07-partial, VM-P09, SIM-P12, SIM-P13). Highest single-card leverage in the corpus.

### 2. `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`

**Scope:** Define migration path from `call_contract("stdlib_fn", ...)` form to direct bare call form (`stdlib_fn(...)`) or a typed stdlib dispatch mechanism. Resolves stringly blockers in VE/DT/AP.

**Prerequisite:** `LANG-STDLIB-COLLECTION-EMPTY-P1` family (already closed); `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` should land first to isolate the remaining signal.

### 3. `LANG-STRING-TEXT-ALIAS-P1`

**Scope:** Investigate whether `String` and `Text` should be treated as aliases or the same type in the Ruby TC. The `concat(...)` built-in returns `"Text"`; apps that declare `field_name : String` are blocked. Bounded: either unify under one name or add a structural alias equivalence in `structurally_assignable?`.

**Impact:** Resolves SIM-P10 and unblocks SIM-P11.

---

## Standing Invariants (Unchanged)

- advanced_logistics retains dual-toolchain CLEAN status (Wave P3 → P4: no regression).
- Rust CLEAN apps: dsa, dataframes, neural_net, vector_math, advanced_logistics, sim_framework — all unchanged.
- LANG-OUTPUT-TYPE-ASSIGNABILITY-P3/P4 safety-positive signals (RE-P04, AP-P11) confirmed unchanged.
- No app source edits were made in this wave.
