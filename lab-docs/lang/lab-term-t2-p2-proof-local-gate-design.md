# Lab Gate Design: PROP-041-P2 — T2 Structural-Size Relation Proof-Local Gate

Status: gate-design-complete
Date: 2026-06-08
Card: PROP-041-P2
Depends on: PROP-041-P1 design lock
Route: EXPERIMENTAL / LAB-ONLY / PROOF-LOCAL

---

## Wording Standard

Throughout this document and all PROP-041+ artifacts:

> T2 adds **structural-size relation evidence with explicit trust metadata**.
> It is not a proof of termination. `stdlib_certified` means the compiler
> trusts the relation for its own stdlib types. `user_assumed` means the
> programmer declared the relation; the compiler records it without verification.
> Both are useful evidence. They are different classes of truth.

Do not write "full termination proof" for T2. Do not write "proven to terminate"
for `user_assumed` relations. The correct framing: "T2 termination evidence
accepted" or "structural-size relation evidence present."

---

## 1. Gate Structure

This gate is an experiment proof — a standalone Ruby verify script with
fixtures, extending the canon pipeline in a new experiment directory. It does
NOT modify production `classifier.rb`, `typechecker.rb`, or
`semanticir_emitter.rb`. The extension lives in the experiment and graduates
to production via PROP-041 authorization + separate gate.

**Experiment directory (proposed):**
```
igniter-lang/experiments/prop041_structural_size_relation_proof/
  fixtures/         ← .ig fixture files
  verify_prop041_t2.rb
```

**Verify script structure:** Same shape as `verify_oof_r3.rb`. Runs the full
canon pipeline; checks type_errors, oof codes, and semantic_ir fields.

---

## 2. Pipeline Extension Design

### 2.1 Classifier Extension

New recognized top-level declaration form (parser must handle):
```
size_relation TypeName accessor1[, accessor2, ...]
```

Examples:
```igniter
size_relation ItemList tail
size_relation TreeNode left, right
size_relation WordList head, rest
```

**Classifier action:**
1. Parse each `size_relation` declaration in the module.
2. For each `(TypeName, accessor)` pair, create a registry entry:
   ```ruby
   { subject_type: "ItemList", accessor: "tail",
     trust: "user_assumed", source: "module:#{module_name}" }
   ```
3. Pre-load stdlib-certified entries (hardcoded in the classifier):
   ```ruby
   STDLIB_SIZE_RELATIONS = [
     { subject_type: "Collection", accessor: "tail",
       trust: "stdlib_certified", source: "stdlib" },
     { subject_type: "Collection", accessor: "rest",
       trust: "stdlib_certified", source: "stdlib" },
   ]
   ```
4. Pass the merged registry as `size_relation_registry` in the classified
   contract context.

**No cross-module lookup.** Registry is built per compilation unit.
A `size_relation` declared in module A is not visible in module B.

### 2.2 Typechecker Extension

The T2 extension modifies the `decreases_variant` check. Two entry points:

**Entry point 1: `decreases items` (simple identifier, custom type)**

After the existing T1 whitelist check in the `infer_recur_call` method:
- If `syntactic_decrease?(variant_arg, dv)` is false (T1 miss):
  - Check if `variant_arg` is a field-access: `{ kind: "field_access", object: { name: dv }, field: accessor }`
  - If yes: look up `(type_of_input(dv), accessor)` in the registry
  - Found → T2 pass: no OOF-R3; record evidence for SemanticIR
  - Not found → OOF-R8 (or OOF-R3 if OOF-R8 not yet promoted)

**Entry point 2: `decreases items.accessor` (dotted-path)**

Currently fires OOF-R3 at contract level (dotted-path fail-closed).
T2 extension: before firing, attempt registry lookup:
- Parse the dotted-path: root = `items`, accessor = `accessor`
- Look up `(type_of_input(items), accessor)` in registry
- Found → T2 pass: no OOF-R3 at contract level; validate call sites
  - Each call site: arg at `items` position must be `items.<same_accessor>`
  - Violation → OOF-R9
- Not found → OOF-R3 fires (unchanged behavior)

**Numeric dotted-path blocked:**
- If the accessor's return type is a numeric scalar (Integer, Float, Decimal):
  NOT T2 structural — this is T3 territory. Fire OOF-R3 with a message
  pointing at T3 (deferred). Do not register as T2 evidence.
- Check: infer the type of `items.accessor`; if it is a numeric type, reject.

### 2.3 SemanticIR Emitter Extension

When a contract has T2 evidence, emit `termination` as:

```json
{
  "termination": {
    "decreases": "items",
    "variant_check": "structural_size_v1",
    "size_relation": {
      "accessor": "tail",
      "trust": "stdlib_certified",
      "source": "stdlib"
    }
  }
}
```

For `user_assumed`:
```json
{
  "termination": {
    "decreases": "items",
    "variant_check": "structural_size_v1",
    "size_relation": {
      "accessor": "tail",
      "trust": "user_assumed",
      "source": "module:M1"
    }
  }
}
```

For dotted-path rehabilitation:
```json
{
  "termination": {
    "decreases": "items.remaining",
    "variant_check": "structural_size_v1",
    "size_relation": {
      "accessor": "remaining",
      "trust": "user_assumed",
      "source": "module:M1"
    }
  }
}
```

**T1 contracts are unaffected:** programs using `Collection.tail` or
`Collection.rest` may be re-emitted as `structural_size_v1 + stdlib_certified`,
or left as `syntactic_v0`. The gate should test both representations. For the
gate itself: T1 programs are tested for the absence of regression, not for
upgrade.

---

## 3. Fixture Coverage Matrix

~28 fixtures, ~35 checks. Organized by gate section.

### T2a — Stdlib-Certified Upgrade (3 fixtures, 6 checks)

These prove that `Collection.tail` and `Collection.rest` are correctly
classified as `stdlib_certified` T2 evidence, and that the SemanticIR
upgrades from `syntactic_v0`.

**T2a-1: `collection_tail_upgrade`**
```igniter
module M1
recursive contract SumDown {
  input items: Collection[Integer]
  input acc: Integer
  output total: Integer
  decreases items
  max_steps 1000
  compute total = recur(items.tail, acc + 1)
}
```
Checks:
- No type errors
- `termination.variant_check = "structural_size_v1"`
- `termination.size_relation.trust = "stdlib_certified"`

**T2a-2: `collection_rest_upgrade`**
Same as T2a-1 but `items.rest`. Checks same fields.

**T2a-3: `collection_tail_stdlib_source`**
Checks `termination.size_relation.source = "stdlib"`.

---

### T2b — User-Assumed Custom Type (4 fixtures, 8 checks)

These prove module-level `size_relation` declarations are parsed,
registered as `user_assumed`, and emitted correctly.

**T2b-1: `custom_type_tail_assumed`**
```igniter
size_relation ItemList tail

module M1
recursive contract ProcessItems {
  input items: ItemList
  input acc: Integer
  output total: Integer
  decreases items
  max_steps 1000
  compute total = recur(items.tail, acc + 1)
}
```
Checks:
- No type errors
- `termination.variant_check = "structural_size_v1"`
- `termination.size_relation.trust = "user_assumed"`
- `termination.size_relation.source = "module:M1"`

**T2b-2: `custom_type_multiple_accessors`**
`size_relation WordList head, rest` — two accessors declared.
Call site uses `items.rest`. Checks: no error, correct accessor emitted.

**T2b-3: `custom_type_multi_input`**
`decreases items` where `items` is not position 0 (second input).
Confirms variant position tracking is correct.

**T2b-4: `custom_type_user_assumed_no_verification`**
```igniter
-- Deliberately declares a relation that could be wrong.
-- Compiler accepts it — user_assumed is assertion, not verification.
size_relation BrokenList tail   -- user asserts; compiler does not verify soundness

module M1
recursive contract Bad {
  input items: BrokenList
  output result: Integer
  decreases items
  max_steps 100
  compute result = recur(items.tail)
}
```
Checks: No OOF errors; `trust = "user_assumed"` in SemanticIR.
Proof point: T2 records the assumption, does not verify mathematical truth.

---

### T2c — Dotted-Path Rehabilitation (4 fixtures, 8 checks)

These prove that `decreases items.accessor` is accepted when the relation
exists, and that call sites are correctly constrained.

**T2c-1: `dotted_path_basic_rehabilitation`**
```igniter
size_relation ItemList remaining

module M1
recursive contract Drain {
  input items: ItemList
  output count: Integer
  decreases items.remaining
  max_steps 1000
  compute count = recur(items.remaining)
}
```
Checks:
- No OOF-R3 at contract declaration level
- `termination.decreases = "items.remaining"`
- `termination.variant_check = "structural_size_v1"`

**T2c-2: `dotted_path_correct_call_site`**
Call site passes `items.remaining` — the same accessor as declared.
Checks: no OOF-R9.

**T2c-3: `dotted_path_wrong_call_site`**
Call site passes `items.tail` instead of `items.remaining`.
`size_relation ItemList remaining` declared but call site uses `tail` (registered
separately or not at all). Checks: OOF-R9 fires.

**T2c-4: `dotted_path_no_relation`**
`decreases items.remaining` with NO `size_relation` declaration.
Checks: OOF-R3 fires (dotted-path fail-closed, no T2 rehabilitation).

---

### T2d — OOF-R8 Missing Relation (4 fixtures, 4 checks)

These prove that custom types without a `size_relation` declaration fire the
correct diagnostic.

**T2d-1: `custom_type_no_declaration`**
`decreases items` where `items: ItemList`, no `size_relation` declared.
Call site passes `items.tail`. Checks: OOF-R8 fires.

**T2d-2: `custom_type_wrong_accessor`**
`size_relation ItemList tail` declared. Call site passes `items.prev` (not
registered). Checks: OOF-R8 or OOF-R9 fires for the unregistered accessor.

**T2d-3: `custom_type_declaration_after_use`**
`size_relation` declared AFTER the contract. If order matters, OOF-R8 fires.
If the classifier does a full-module scan before typechecking, no error.
Gate should specify which behavior is correct. Recommendation: full-module scan
(like how `assumptions` work) — declare anywhere in the module.

**T2d-4: `custom_type_different_module`**
`size_relation` declared in module A, contract in module B (separate compilation
units). OOF-R8 fires in B — cross-module not supported at T2 v0.

---

### T2e — OOF-R9 Relation/Call-Site Mismatch (3 fixtures, 3 checks)

**T2e-1: `relation_declared_wrong_accessor_used`**
`size_relation ItemList tail` declared. Call site passes `items.rest` (not
`tail`). Checks: OOF-R9 fires — relation declared but wrong accessor at call
site.

**T2e-2: `relation_declared_literal_passed`**
`size_relation ItemList tail` declared. Call site passes literal `42` at
variant position. Checks: OOF-R9 fires.

**T2e-3: `relation_declared_subtraction_used`**
`size_relation ItemList tail` declared. `items: ItemList`, call site passes
`items - 1` (T1 arithmetic form). `ItemList` is not Integer so this is already
a type error, but OOF-R9 should fire for the relation mismatch specifically.

---

### T2f — Numeric Dotted-Path Blocked (2 fixtures, 2 checks)

These prove that dotted-path variants whose accessor returns a numeric type
are NOT classified as T2 structural evidence — they are T3 territory and must
fire OOF-R3 with a "T3 deferred" message, not silently pass.

**T2f-1: `numeric_dotted_path_count`**
```igniter
size_relation ItemList count   -- declared, but accessor returns Integer

module M1
recursive contract WrongLevel {
  input items: ItemList
  output result: Integer
  decreases items.count         -- count: Integer → not structural T2
  max_steps 100
  compute result = recur(items.count)
}
```
Checks: OOF-R3 fires (not T2; numeric measure is T3 territory).

Note: this fixture requires the typechecker to infer the type of `items.count`.
If the type system cannot resolve `ItemList.count` type, OOF-P1 fires first.
Either outcome is acceptable for the gate; the key is that this does NOT
silently pass as T2.

**T2f-2: `numeric_field_not_structural`**
`items.length: Integer` — same class of rejection.

---

### T2g — T1 Regression (5 fixtures, 5 checks)

These prove that all T1 programs compile identically under the T2 extension.
T1 behavior is not changed. OOF-R3 whitelist still fires for T1 violations.
`syntactic_v0` is still emitted for pure T1 programs.

**T2g-1: `t1_subtract_unchanged`**
`decreases n` + `recur(n - 1)`. Checks: `variant_check = "syntactic_v0"` (not
upgraded to `structural_size_v1`).

**T2g-2: `t1_collection_tail_unchanged`**
`decreases items` + `recur(items.tail)` where `items: Collection[Integer]`.
Checks: compiles clean; `variant_check` is either `syntactic_v0` OR
`structural_size_v1 + stdlib_certified` (both acceptable; gate documents
which the implementation emits). Regression: no OOF-R3 fires.

**T2g-3: `t1_oof_r3_same_still_fires`**
`decreases n` + `recur(n)` (same value). Checks: OOF-R3 fires exactly once
(unchanged from T1 behavior).

**T2g-4: `t1_oof_r3_dotted_no_relation_still_fires`**
`decreases items.remaining` with NO `size_relation`. Checks: OOF-R3 fires
(fail-closed rule unchanged).

**T2g-5: `t1_fuel_exempt_unchanged`**
`fuel_bounded` or `recursive + decreases fuel`. Checks: no OOF-R3, no OOF-R8,
unaffected by T2 extension.

---

### T2h — OOF-R3 Scope Unweakened (3 fixtures, 3 checks)

**T2h-1: `oof_r3_increase_still_fires`**
`decreases n` + `recur(n + 1)`. OOF-R3 unchanged.

**T2h-2: `oof_r3_nonwhitelisted_still_fires`**
`decreases items` (Collection) + `recur(items.something)` where `something`
is not `tail`/`rest` and no `size_relation` declared for `Collection.something`.
OOF-R3 fires — the stdlib entry only covers `tail` and `rest`.

**T2h-3: `oof_r3_constant_still_fires`**
`recur(42)` at variant position. OOF-R3 fires.

---

## 4. Verify Script Design

```
verify_prop041_t2.rb
```

Same structure as `verify_oof_r3.rb`. Each section prints a header and runs
`check "description", bool_value`. Summary line: `N/M PASS`.

Key helper additions vs `verify_oof_r3.rb`:
- `size_relation_for(result, contract_name)` — extract
  `termination.size_relation` from SemanticIR
- `trust_for(result, contract_name)` — extract `.trust`
- `source_for(result, contract_name)` — extract `.source`

OOF-R8 and OOF-R9 are checked the same way as OOF-R3 in the existing script:
`oof_codes_for(result).include?("OOF-R8")`.

If OOF-R8/R9 are not yet distinct codes (implementation fires OOF-R3 for both),
the gate checks for OOF-R3 firing and documents which message distinguishes the
case. The gate can pass with OOF-R3 as umbrella; distinct OOF-R8/R9 codes are
a bonus.

---

## 5. Open Design Questions for the Gate Experiment

These are answered during the gate experiment, not before:

1. **Module scan order:** Does `size_relation` need to precede the contract, or
   does the classifier do a full-module pass? Recommendation: full-module scan
   (same as `assumptions` block). Gate T2d-3 proves this.

2. **T1 → T2 upgrade for `Collection.tail`:** Does the gate upgrade
   `Collection.tail` programs from `syntactic_v0` to `structural_size_v1`?
   Both are correct. The gate documents which the implementation emits.
   No conformance break either way.

3. **OOF-R8 vs OOF-R3 as distinct codes:** The gate can pass with OOF-R3 as
   the umbrella. Distinct OOF-R8/R9 codes require a separate OOF registry
   amendment. Document the gate result; promote codes separately if needed.

4. **Type inference for numeric accessor check (T2f):** If `ItemList.count`
   type is not known to the typechecker, OOF-P1 fires before the T2 check.
   The gate documents which error takes precedence. Acceptable: either OOF-P1
   or OOF-R3 fires; the key is no silent T2 pass.

---

## 6. Expected Gate Result

~28 fixtures, ~35 checks, **35/35 PASS** expected.

Evidence summary line:
```
T2 structural-size relation evidence gate:
  T2a stdlib_certified: 6/6 PASS
  T2b user_assumed: 8/8 PASS
  T2c dotted-path rehabilitation: 8/8 PASS
  T2d OOF-R8 missing relation: 4/4 PASS
  T2e OOF-R9 call-site mismatch: 3/3 PASS
  T2f numeric dotted-path blocked: 2/2 PASS
  T2g T1 regression: 5/5 PASS
  T2h OOF-R3 scope unweakened: 3/3 PASS
```

---

## 7. What This Gate Does NOT Prove

| Claim | Status |
|-------|--------|
| User-assumed relations are mathematically sound | Not proved — `user_assumed` is evidence, not verification |
| T2 programs terminate | Not proved — T2 is evidence with trust metadata |
| Cross-module relations work | Not in gate — deferred |
| Numeric dotted-path works as T2 | Not in gate — T3 territory |
| Lexicographic variants work | Not in gate — T4 territory |
| SMT-backed relations work | Not in gate — T5 territory |
| Runtime recursion is safe | Not in gate — PROP-039 Part IV |

---

## 8. References

- Design lock: `igniter-lab/lab-docs/lang/lab-term-t2-p1-design-lock.md`
- Research base: `igniter-lab/lab-docs/lang/lab-managed-recursion-full-termination-proof-beyond-syntactic-v0.md`
- Card: `igniter-lang/.agents/work/cards/lang/PROP-041-P2.md`
- OOF-R3 gate (model): `igniter-lang/experiments/oof_r3_syntactic_variant_decrease_proof/verify_oof_r3.rb`
- Canon spec: `igniter-lang/docs/spec/ch13-managed-recursion.md`
