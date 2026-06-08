# Lab Design Lock: T2 Structural-Size Relation Proof Boundary

Status: design-lock-complete
Date: 2026-06-08
Card: PROP-041-P1
Depends on: TERM-PROOF-P1
Route: EXPERIMENTAL / DESIGN-ONLY / PRE-PROPOSAL
Authority: design lock — no compiler edits, no canon grammar, no runtime

---

## 1. The Central Question

**Who may declare a size relation, and how do we distinguish
stdlib-certified truth from user assertion?**

This question is the design lock's load-bearing beam. Get it wrong and the
proof system either over-trusts user declarations (unsound) or refuses to
let programmers extend it (useless). The answer below is intentional.

---

## 2. Declaration Authority and Trust Model

Three authorities may contribute entries to the size-relation registry.
Each has a different trust level and different compiler treatment.

### 2.1 Stdlib Authority — `stdlib_certified`

**Who:** The Igniter stdlib, as represented by compiler-internal registry
entries. Users do not write these.

**What they certify:** The structural size relations for all stdlib collection
types. These are mathematical truths about the data structures — not
assertions, not assumptions.

**Hardcoded at T2 v0:**

| Type | Accessor | Relation | Certified by |
|------|----------|----------|--------------|
| `Collection[T]` | `tail` | `count(x.tail) < count(x)` | stdlib (T1 whitelist, now explicit) |
| `Collection[T]` | `rest` | `count(x.rest) < count(x)` | stdlib (T1 whitelist, now explicit) |

These entries already exist implicitly in the T1 whitelist. T2 names them
formally as `stdlib_certified` registry entries. T1 programs are unaffected —
the whitelist check is a lookup in the registry, and the result is the same.

**SemanticIR trust field:** `"stdlib_certified"`

**OOF implication:** None. Stdlib-certified relations do not require any user
annotation. Their presence is guaranteed by the compiler version.

**Programmer action required:** None. Using `Collection[T]` with
`decreases items` + `recur(items.tail, ...)` is valid at T1 and remains
valid at T2 with no source changes.

### 2.2 Module Authority — `user_assumed`

**Who:** The programmer, writing at module scope.

**What they declare:** That a named accessor on a named type produces a
structurally smaller value. The compiler does not verify this claim.
It is an assertion — explicit, named, and auditable.

**Declaration syntax (candidate — NOT canon):**

```igniter
-- Single accessor
size_relation ItemList tail

-- Multiple accessors for one type
size_relation ItemList tail, rest, prev

-- Block form (if multiple types in one module)
size_relations {
  ItemList: tail, rest
  TreeNode: left, right
}
```

The declaration names the type and the accessor(s). The compiler registers
each `(type_name, accessor)` pair as `user_assumed` for the declaring module.

**SemanticIR trust field:** `"user_assumed"`

**OOF implication at T2:** No error fires for the declaration itself. The
declaration is accepted. The trust level is recorded. Future tooling (proof
obligation pass, audit flag) may act on `user_assumed` entries — that is
post-T2 work.

**Programmer action required:** Explicit `size_relation` declaration at module
scope before any `recursive` contract in the same module may use the declared
type's accessor as a decrease witness.

### 2.3 Contract-Inline Authority — deferred to v1

Contract-inline declarations (`size_relation items: tail` inside a contract
body) are a v1 shorthand only. They create a module-scoped `user_assumed`
entry implicitly. Not in scope for T2 v0.

### 2.4 Trust Ladder Summary

| Source | Trust level | Compiler verification | Programmer action |
|--------|-------------|----------------------|------------------|
| Stdlib | `stdlib_certified` | n/a — compiler guarantees it | None |
| Module declaration | `user_assumed` | None — asserted, not proved | Write `size_relation` declaration |
| Future: proof receipt | `proof_backed` | Receipt verification | Provide receipt — T5 territory |

The trust ladder is explicit and non-ambient. There is no implicit trust of
arbitrary programmer types. A programmer using a custom type without a
`size_relation` declaration gets OOF-R8 — not a silent pass.

---

## 3. Registry Shape

The size-relation registry is a table keyed by `(type_name, accessor)`.
Each entry records the trust level and the declaring source.

### 3.1 Entry Structure

```
SizeRelationEntry {
  subject_type:  String,   -- "Collection", "ItemList", "TreeNode"
  accessor:      String,   -- "tail", "rest", "prev", "left", "right"
  trust:         Trust,    -- stdlib_certified | user_assumed
  source:        String,   -- "stdlib" | "module:<name>"
}

Trust = stdlib_certified | user_assumed
```

### 3.2 Registry Lifecycle

At classify time, the classifier:

1. Scans the module's top-level declarations for `size_relation` entries.
2. For each declared `(type, accessor)` pair, inserts a `user_assumed` entry.
3. The stdlib-certified entries are pre-loaded — they are always present
   regardless of source content.
4. The populated registry is passed to the typechecker as a read-only context
   for that compilation unit.

No cross-module sharing at T2 v0. A `size_relation` declared in module A is
not visible in module B. (Cross-module sharing is post-T2 design work.)

### 3.3 Lookup

`registry.get(type_name, accessor) → Option<SizeRelationEntry>`

If the type_name is a parameterized type (e.g., `Collection[Integer]`), the
lookup uses the base type name (`Collection`) to match stdlib-certified entries.
User-declared entries use the exact type name as written.

---

## 4. Decrease Variants and Call-Site Rules

T2 defines two cases: simple-identifier `decreases` and dotted-path `decreases`.
Both are T2 — the difference is in the subject of the registry lookup and the
call-site structural constraint.

### 4.1 Case A — Simple Identifier: `decreases items` (Custom Type)

**Context:** `items: ItemList`, `decreases items`.

T1 rule: at each `recur()` call site, the argument at the `items` position must
syntactically match a T1 whitelist pattern for `items` (`items - N`,
`items.tail`, `items.rest`). Since `ItemList` is not `Collection[T]`, `.tail`
and `.rest` on `ItemList` are not in the T1 whitelist → OOF-R3.

T2 rule: the same syntactic constraint, but the whitelist is now the registry
lookup. At each call site, the argument at the `items` position must be
`items.<accessor>` where `registry.get(ItemList, accessor)` is present.

**Lookup:** `(ItemList, accessor_used_at_call_site)`

**Call-site constraint:**
```
arg at variant_pos must match: items.<accessor>
where registry.get(type_of(items), accessor) = Some(_)
```

If no registered accessor is used → OOF-R8.
If the registered accessor exists but the call site passes a different form
(e.g., a raw literal) → OOF-R9.

### 4.2 Case B — Dotted-Path: `decreases items.accessor`

**Context:** `items: ItemList`, `decreases items.remaining`.

T1 rule: dotted-path variant fails closed at the contract declaration level
(OOF-R3). No call-site check is performed.

T2 rule: allowed iff `registry.get(ItemList, remaining)` is present.

**Lookup:** `(ItemList, accessor_in_decreases_path)` — the type of the root
input `items` and the accessor named in the dotted-path.

**Call-site constraint:**
The argument at the `items` position must syntactically be
`items.<same_accessor>`:
```
arg at variant_pos must match: items.remaining
```
This is a strict structural step-along requirement — the program recurses by
peeling the same accessor off the same input. Any other form fires OOF-R9.

**Why this is conservative and correct:** The registry entry asserts
`size(x.remaining) < size(x)`. The call site passes `items.remaining` as the
new `items`. If the type of `items.remaining` is the same as the type of
`items` (a structural subtype), and the relation holds, the recursion decreases
the variant on every call. If the types don't match (e.g., `.remaining` returns
an Integer, not an `ItemList`), the existing type-checker catches the mismatch
as OOF-TY0 before OOF-R3/R8 is reached. T2 does not need to solve this — the
type system handles it.

**Note on numeric dotted-path:** `decreases items.count` where `.count` returns
an Integer is NOT T2 structural — it is T3 numeric measure territory. The T2
registry only covers structural accessors (same-type or subtype return). The
compiler distinguishes at classify time by checking the return type of the
accessor: if the return type is a numeric scalar, T2 does not apply; the
program gets OOF-R3 with a message pointing at T3 (deferred). If the return
type is the same structural type (or a parametric variant), T2 applies.

---

## 5. OOF-R8 and OOF-R9 — Candidate Diagnostics

These are candidates only — they require a gate proof before becoming canon
experiment-pass codes. Until then, implementations may fire OOF-R3 for all
T2 violations without breaking conformance.

### 5.1 OOF-R8 — Size Relation Not Found

**Condition:** `decreases items` or `decreases items.accessor` where the type
of `items` has no registered size relation for the accessor used (or implied)
at a `recur()` call site.

**Message shape:**
```
contract 'Foo' — no size relation declared for 'items.tail' on type 'ItemList';
declare 'size_relation ItemList tail' at module scope
or use a stdlib collection type (Collection[T] is pre-certified)
```

**Fires at:** Contract declaration level (for dotted-path missing relation) or
call-site level (for simple-identifier missing relation for the accessor used).

**Distinct from OOF-R3:** OOF-R3 fires for syntactic whitelist failure
(`variant - 0`, `variant.something` not in whitelist). OOF-R8 fires for a
missing T2 relation declaration. The distinction helps the programmer know
whether to fix the call site or add a declaration.

### 5.2 OOF-R9 — Call Site Violates Declared Relation

**Condition:** A size relation exists for `(type, accessor)`, but the call-site
argument at the variant position does not syntactically match `variant.<accessor>`
(e.g., the relation declares `tail` but the call site passes a raw integer
or a different accessor).

**Message shape:**
```
recur() in 'Foo' — variant 'items' (position 1) has size_relation for 'tail',
but call site passes 'items.prev' which is not covered by the declared relation;
add 'size_relation ItemList prev' or adjust the call site
```

**Fires at:** Call-site level only. The declaration is fine; the call site
diverges from the declared relation.

### 5.3 OOF Code Scope Table

| Code | Level | Condition | Fires at | Candidate until |
|------|-------|-----------|----------|-----------------|
| OOF-R3 | T1 | Syntactic whitelist miss; dotted-path in T1 | Call site / contract | Closed (experiment-pass) |
| OOF-R8 | T2 | No registry entry for (type, accessor) | Contract / call site | PROP-041 gate proof |
| OOF-R9 | T2 | Registry entry exists but call site violates it | Call site | PROP-041 gate proof |

---

## 6. SemanticIR Shape — `structural_size_v1`

### 6.1 T1 shape (unchanged, for reference)

```json
{
  "termination": {
    "decreases": "n",
    "variant_check": "syntactic_v0"
  }
}
```

### 6.2 T2 shape — custom type, stdlib-certified relation

Program: `decreases items` where `items: Collection[Integer]`, call site
passes `items.tail`. This is T1-compatible but T2-classified.

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

Note: T1 programs using `Collection.tail` may be re-emitted as `structural_size_v1`
in a T2-capable compiler, or left as `syntactic_v0`. Both are valid representations
of the same fact. The canonical T2 compiler upgrades them. Alternate
implementations may retain `syntactic_v0` for T1-compatible programs without
conformance failure.

### 6.3 T2 shape — custom type, user-assumed relation

Program: `size_relation ItemList tail` declared in module; `decreases items`
where `items: ItemList`; call site passes `items.tail`.

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

### 6.4 T2 shape — dotted-path variant (rehabilitated)

Program: `size_relation ItemList remaining` declared; `decreases items.remaining`
where `items: ItemList`; call site passes `items.remaining` at items position.

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

### 6.5 SemanticIR field specification (T2)

```
contract_ir.termination = {
  "decreases":    String,   -- input name (T1/T2) or dotted-path (T2 only)
  "variant_check": "structural_size_v1",
  "size_relation": {
    "accessor":  String,    -- the structural accessor covered by the relation
    "trust":     "stdlib_certified" | "user_assumed",
    "source":    String     -- "stdlib" | "module:<name>"
  }
}
```

The `size_relation` sub-object is present only when `variant_check =
"structural_size_v1"`. It is absent for `syntactic_v0` (T1).

---

## 7. T1 Compatibility

T2 is a strict superset of T1. The following invariants hold:

1. All programs that compile clean at T1 compile clean at T2 with identical
   semantics. No source changes required.

2. The T1 whitelist (`Collection.tail`, `Collection.rest`) is fully subsumed
   by the stdlib-certified entries in the T2 registry. The whitelist check in
   the typechecker becomes a registry lookup — the result is identical.

3. Programs emitted with `variant_check = "syntactic_v0"` by T1 compilers
   remain valid SemanticIR at T2. The T2 compiler may upgrade them to
   `structural_size_v1` or leave them as-is.

4. OOF-R3 continues to fire for all cases where T1 currently fires it, until
   the programmer opts into T2 by adding a `size_relation` declaration.

---

## 8. What Is Closed

| Surface | Status |
|---------|--------|
| T1 whitelist weakened or bypassed | Closed — T2 is strictly additive |
| Dotted-path without declared size relation | Closed — OOF-R3 / OOF-R8 fires |
| Numeric dotted-path as T2 structural | Closed — T3 territory; deferred |
| Cross-module size relation visibility | Closed at T2 v0 |
| Contract-inline `size_relation` shorthand | Closed at T2 v0; v1 candidate |
| Compiler verification of user-assumed relations | Closed — post-T2 |
| Proof receipts for user-assumed relations | Closed — T5 territory |
| SMT-backed relation verification | Closed pre-v1 |
| T3 numeric measure expressions | Closed — post-T2 |
| T4 lexicographic multi-variant | Closed — post-v1 |
| Recursive execution, VM, TCO, igc run | Closed — PROP-039 Part IV |
| Any compiler source edits from this design lock | Closed — design only |
| OOF-R8/R9 as canon experiment-pass codes | Closed — require PROP-041 gate |

---

## 9. Fixture Sketch for PROP-041 Gate Experiment

This is not a proof — it is an illustrative sketch of what the gate fixtures
should cover. Actual fixtures are produced in the PROP-041 gate experiment.

**Happy path — custom type with stdlib analog (T2 core):**
```igniter
-- Module declares size_relation for custom list type
size_relation ItemList tail

module M1

recursive contract ProcessItems {
  input items: ItemList
  input acc: Integer
  output total: Integer
  decreases items
  max_steps 10000
  compute total = recur(items.tail, acc + 1)
}
```
Expected: clean compile; `variant_check = "structural_size_v1"`,
`trust = "user_assumed"`, `accessor = "tail"`.

**Happy path — dotted-path rehabilitation:**
```igniter
size_relation ItemList remaining

module M1

recursive contract CountItems {
  input items: ItemList
  output count: Integer
  decreases items.remaining
  max_steps 10000
  compute count = recur(items.remaining)
}
```
Expected: clean compile; `decreases = "items.remaining"`,
`variant_check = "structural_size_v1"`.

**OOF-R8 — no relation declared for custom type:**
```igniter
module M1

recursive contract Bad {
  input items: ItemList
  output count: Integer
  decreases items
  max_steps 10000
  compute count = recur(items.tail)
}
```
Expected: OOF-R8 — "no size relation declared for 'items.tail' on type
'ItemList'".

**OOF-R9 — relation declared but call site uses different accessor:**
```igniter
size_relation ItemList tail

module M1

recursive contract Mismatch {
  input items: ItemList
  output count: Integer
  decreases items
  max_steps 10000
  compute count = recur(items.prev)  -- prev not in registry
}
```
Expected: OOF-R9 — call site violates declared relation.

**Regression — T1 program unaffected:**
```igniter
module M1

recursive contract SumDown {
  input n: Integer
  output total: Integer
  decreases n
  max_steps 100
  compute total = recur(n - 1)
}
```
Expected: clean compile; `variant_check = "syntactic_v0"` (unchanged).

**Regression — Collection.tail still works (stdlib-certified unchanged):**
```igniter
module M1

recursive contract SumList {
  input items: Collection[Integer]
  input acc: Integer
  output total: Integer
  decreases items
  max_steps 10000
  compute total = recur(items.tail, acc + 1)
}
```
Expected: clean compile; `variant_check = "structural_size_v1"`,
`trust = "stdlib_certified"`.

---

## 10. References

- Research base: `igniter-lab/lab-docs/lang/lab-managed-recursion-full-termination-proof-beyond-syntactic-v0.md`
- Card: `igniter-lang/.agents/work/cards/lang/PROP-041-P1.md`
- OOF-R3 gate: `igniter-lang/experiments/oof_r3_syntactic_variant_decrease_proof/verify_oof_r3.rb`
- Canon spec: `igniter-lang/docs/spec/ch13-managed-recursion.md`
- Conformance: `igniter-lang/.agents/work/conformance/PROP-039-managed-repetition-conformance-package-v0.md`
