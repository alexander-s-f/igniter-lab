# Lab: PROP-041 T2 Structural-Size Relation — Rust Symmetry Proof

Status: closed  
Date: 2026-06-08  
Card: LAB-TERM-T2-P1  
Route: EXPERIMENTAL / LAB-ONLY / RUST-SYMMETRY  
Authority: lab symmetry proof — confirms Rust compiler mirrors Ruby canon; no canon authority, no runtime authorization

---

## 1. Situation

PROP-041-P7 graduated T2 structural-size relation to the Ruby production pipeline
(`igniter-lang`). T2 is the second level in the termination proof hierarchy:

| Level | Name | Mechanism |
|-------|------|-----------|
| T1 | syntactic_v0 | Whitelist: `variant-N`, `variant.tail`, `variant.rest` |
| T2 | structural_size_v1 | Dotted-path `decreases X.accessor` allowed iff a named size relation covers (Type, accessor) |

Ruby gate result: `verify_prop041_t2_production.rb` 48/48 PASS.

This document covers the Rust lab compiler symmetry implementation (LAB-TERM-T2-P1): proof that
the Rust compiler in `igniter-lab/igniter-compiler` mirrors the accepted Ruby canon behavior for
all T2 surface forms.

---

## 2. What T2 Is (and Is Not)

**T2 is:**
- Structural evidence with trust metadata
- A named relation `(Type, accessor)` that the compiler records in SemanticIR
- A two-trust model: `stdlib_certified` (hardcoded compiler built-ins) vs. `user_assumed` (module-level declarations)
- A call-site enforcement: `recur()` variant-position argument must be `subject.accessor` exactly

**T2 is NOT:**
- A full termination proof
- Proof of well-foundedness beyond syntactic structural descent
- A runtime guarantee
- Canon authority from lab behavior

**Trust model:**

| Trust level | Source | Registration |
|-------------|--------|--------------|
| `stdlib_certified` | Compiler built-in | `Collection.tail`, `Collection.rest` hardcoded |
| `user_assumed` | Module-level declaration | `size_relation TypeName accessor` in source file |

---

## 3. Rust Implementation Surface

### 3.1 Files Modified

| File | Change |
|------|--------|
| `src/parser.rs` | `SizeRelationDecl` struct; `size_relations` field on `SourceFile`; `parse_size_relation_decl()`; `"size_relation"` arm in `parse_top_decl` |
| `src/classifier.rs` | `SizeRelationDecl` import; `size_relations: Vec<SizeRelationDecl>` on `ClassifiedProgram` (serde: skip_if empty) |
| `src/typechecker.rs` | `T2RegistryEntry`, `T2Context`, `T2Kind` types; `stdlib_size_registry()` fn; `NUMERIC_ACCESSORS` const; `decreases_variant_t2` + `size_relation_evidence` on `TypedContract`; T2 dispatch replacing pre-T2 OOF-R3 dotted-path block; four private methods: `build_size_registry`, `handle_t2_variant`, `check_t2_callsite_in_expr`, `t2_structural_arg` |
| `src/emitter.rs` | `structural_size_v1` termination path: `decreases`, `variant_check`, `size_relation.{accessor,trust,source}` |

### 3.2 Key Design: Stateless TypeChecker

The Ruby TypeChecker uses instance variables (`@t2_context`, `@size_registry`) for T2 state.
The Rust TypeChecker is stateless (`struct TypeChecker { version: String }`).

Solution:
- `size_registry: HashMap<(String,String), T2RegistryEntry>` built once before the contracts loop, passed by reference
- `t2_context: Option<T2Context>` is a local variable inside `typecheck_contract`
- `check_t2_callsite_in_expr` is a separate method from `check_recur_in_expr`, called after the recur check. This avoids touching all 14 `check_recur_in_expr` call sites.

### 3.3 T2 Dispatch Logic (symmetric with Ruby canon)

```
decreases_variant contains "."?
  YES →
    accessor ∈ NUMERIC_ACCESSORS? → OOF-R3 (blocked, numeric excluded from T2)
    (type, accessor) in size_registry? → T2 pass (structural_size_v1)
    else → OOF-R8 (missing structural size relation)
  NO → T1 dispatch (syntactic_v0 rules unchanged)

T2 pass: for each recur() call site
  variant-position arg is subject.accessor (exact field_access)? → OK
  else → OOF-R9 (call-site mismatch)
```

### 3.4 STDLIB_SIZE_REGISTRY (hardcoded)

```
("Collection", "tail") → { trust: "stdlib_certified", source: "compiler_builtin" }
("Collection", "rest") → { trust: "stdlib_certified", source: "compiler_builtin" }
```

### 3.5 NUMERIC_ACCESSORS (closed list)

```
["count", "length", "size", "total_count", "num_items", "num_elements"]
```

These route to OOF-R3 (syntactic_v0 block), not OOF-R8. Exactly symmetric with Ruby canon.

### 3.6 SemanticIR Shape (structural_size_v1)

```json
{
  "termination": {
    "decreases": "items.remaining",
    "variant_check": "structural_size_v1",
    "size_relation": {
      "accessor": "remaining",
      "trust": "user_assumed",
      "source": "MyModule"
    }
  }
}
```

---

## 4. Verification

### 4.1 Fixtures

28 fixtures copied from `igniter-lang/experiments/prop041_structural_size_relation_proof/fixtures/`
to `igniter-lab/igniter-compiler/fixtures/prop041_t2_structural_size_relation/`.

Fixture set covers T2A–T2H scenarios (see §5).

### 4.2 Verify Script

`igniter-lab/igniter-compiler/verify_t2_structural_size_relation.rb`

52 checks across sections T2A–T2I. Uses `BoundedCommand` (LAB-PROOF-HYGIENE-P1) for bounded
execution with hard timeouts and process-group cleanup.

### 4.3 Results

```
verify_t2_structural_size_relation.rb: 52/52 PASS
verify_oof_r3.rb:                     34/34 PASS  (OOF-R3 scope unweakened — no regression)
verify_g5_recur.rb:                   18/18 PASS  (G5 recur() — no regression)
```

---

## 5. Check Coverage

| Section | Description | Checks |
|---------|-------------|--------|
| T2A | Stdlib-certified: `Collection.tail` / `Collection.rest` → `stdlib_certified`, `structural_size_v1`, accessor/source in SIR | 7 |
| T2B | User-assumed: module-level `size_relation` → `user_assumed`, source = module name, multi-relation + different-type variants | 7 |
| T2C | Dotted-path rehabilitation: registered relation → no OOF-R3/R8/R9, compiles, order-independent, stdlib+user coexist | 8 |
| T2D | OOF-R8: non-numeric dotted-path with no registered relation → OOF-R8 fires, OOF-R3 does NOT | 6 |
| T2E | OOF-R9: registered relation but wrong recur() arg (wrong accessor, plain ref, wrong variable) | 6 |
| T2F | OOF-R3: numeric accessors (`count`, `length`) → OOF-R3 fires, OOF-R8 does NOT | 4 |
| T2G | T1 regression: simple-identifier decreases → `syntactic_v0`; fuel_bounded → no termination IR; OOF-R3 still fires for T1 forms | 9 |
| T2H | OOF-R3 scope unweakened: arithmetic increase, wrong variant arg, non-whitelisted field | 3 |
| T2I | Closed-surface scan: stdlib_certified ≠ user_assumed, user_assumed ≠ stdlib_certified, T1 never emits structural_size_v1, SIR node has required fields | 4 |
| **Total** | | **52** |

---

## 6. Canon Boundary

The following surfaces remain closed and are NOT affected by this lab work:

| Surface | Status |
|---------|--------|
| Runtime execution / `igc run` / `.igbin` | Closed |
| VM stack / TCO / execution traces | Closed |
| Full termination proof authority | T2 is structural evidence only |
| igniter-lang canon grammar / parser.rb | Unchanged by lab |
| `size_relation` in canon grammar | PROP-041-P7 owns canon; lab is conformance consumer |
| Real TCP sockets / network I/O | Closed (lab constraint) |
| Public/stable/production/release claims | Closed |

**Lab behavior does not create canon authority.**
**T2 is structural evidence with trust metadata — NOT a verified termination proof.**

---

## 7. Behavioral Symmetry Summary

| Behavior | Ruby canon (PROP-041-P7) | Rust lab (LAB-TERM-T2-P1) | Symmetric? |
|----------|--------------------------|---------------------------|-----------|
| `size_relation TypeName accessor` parsed at module level | ✅ | ✅ | ✅ |
| Order-independent (relation after contract body) | ✅ | ✅ | ✅ |
| `Collection.tail` → `stdlib_certified` | ✅ | ✅ | ✅ |
| `Collection.rest` → `stdlib_certified` | ✅ | ✅ | ✅ |
| Module-level decl → `user_assumed`, source = module name | ✅ | ✅ | ✅ |
| Registered relation → `structural_size_v1` in SIR | ✅ | ✅ | ✅ |
| OOF-R8: missing relation | ✅ | ✅ | ✅ |
| OOF-R9: call-site accessor mismatch | ✅ | ✅ | ✅ |
| Numeric dotted-path → OOF-R3 (not OOF-R8) | ✅ | ✅ | ✅ |
| T1 `syntactic_v0` unchanged | ✅ | ✅ | ✅ |
| OOF-R3 scope unweakened | ✅ 33/33 | ✅ 34/34 | ✅ |

**Verdict: Full Rust-Ruby symmetry. No behavioral divergence found.**

---

## 8. Next Route

**LAB-TERM-T2** track is now closed.

Recommended next steps (in priority order):

1. **LAB-TERM-T2-P2 (optional):** Additional OOF-R9 edge cases — nested recur(), multi-branch contracts where one branch has correct accessor and another does not
2. **PROP-041 T3 research (open):** Numeric measure expressions — `decreases size(items)` where `size` is a declared pure function; see `lab-managed-recursion-full-termination-proof-beyond-syntactic-v0.md` §2.3
3. **Canon grammar stability:** T2 surface (`size_relation` declaration) is now proven at both Ruby and Rust layers; no further lab work required to confirm canon stability

**The LAB-TERM-T2-P1 card is closed.**
