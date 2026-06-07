# PROP-Forms-Enhanced-v0: Form System — Enhanced Specification

Date: 2026-06-04
Status: experimental · pressure document · lab-local
Layer: syntax + form compiler
Base: PROP-Forms-v0 (Agent-C archive)
Strengthens: §1 FormPattern, §2 FormKind, §4 Registry, §6 Resolution, §7 Binder, §12 Phase 2, §17 Open Questions

---

## Purpose

PROP-Forms-v0 established the authoritative Form System specification.
This document adds seven targeted enhancements identified through cross-analysis
of C0–C5 and the igniter-compiler (Rust, `igniter-lab/igniter-compiler/`):

1. **FormShape** — form declarations on `contract_shape` (trait-inherited forms)
2. **`no_form` modifier** — explicit opt-out from form syntax
3. **Structural validity rules** — six compile-time constraints not in PROP-Forms-v0
4. **`form_resolution_trace`** — resolution events in diagnostics output
5. **`MultiKeywordForm`** — seventh FormKind resolving §17 Q4
6. **BinderRef in MethodCallForm** — resolution of §17 Q1
7. **Two-phase compiler mapping** — explicit alignment with igniter-compiler pipeline

Everything else — FormPattern, FormKind 1–6, Form Registry, Trust Levels, Resolution
Algorithm, Import Control, Profile Trust, Explicit Qualification, `.ifh` format — is
unchanged from PROP-Forms-v0 and not repeated here.

---

## Axioms (inherited, unchanged)

```
Forms are not macros. Forms are typed aliases.
Macro changes meaning. Form exposes meaning.

User syntax is admitted, not trusted.
Compiler is the trust boundary.

Form resolution is static. No form is resolved at runtime.
```

---

## §E1. FormShape — Form Declarations on `contract_shape`

### Problem

PROP-Forms-v0 allows forms only on `contract`. This means every implementor
of a `contract_shape` (trait) must re-declare the same form pattern independently,
with no enforcement that they use the same syntax.

### Solution: `form` on `contract_shape`

A `contract_shape` may carry one or more `form` declarations. All contracts
`implements`-ing that shape **inherit** the declared forms automatically.

```igniter
contract_shape Mappable[T, R] {
  input  collection: Collection[T]
  output result:     Collection[R]
  form (collection) ".map" { (selector) }
  priority 10
}

-- Both contracts inherit the .map { } BlockMethodForm:
contract StringTransform implements Mappable[String, String] { ... }
contract NumberScale   implements Mappable[Decimal, Decimal]  { ... }

-- Both usable as:
names.map { it.upcase }
prices.map { it * rate }
```

### Semantics

- A `contract_shape` form is a **form template**. The compiler instantiates it
  for each implementing contract by substituting the concrete type parameters.
- The implementing contract may **override** an inherited form by redeclaring it
  explicitly with different priority or pattern.
- If an implementing contract has a type parameter mismatch that makes the
  form's type constraints unsatisfiable, the compiler emits `E-FORM-SHAPE-TYPE`.
- A contract_shape form has `trust_level: :user` by default (same as its declaring module).

### FormEntry extension for inherited forms

```igniter
type FormEntry {
  -- (existing fields from PROP-Forms-v0 §4.1)
  ...

  -- new field:
  inherited_from: Option[ContractShapeRef]
    -- present when this form was inherited via contract_shape
    -- ContractShapeRef: { module: String, name: String }
}
```

### Error codes (new)

| Code | Phase | Description |
|------|-------|-------------|
| `E-FORM-SHAPE-TYPE` | Phase 2 | Inherited form type constraints unsatisfiable for implementing contract |
| `E-FORM-SHAPE-CONFLICT` | Phase 2 | Implementing contract re-declares a form with incompatible pattern |

---

## §E2. `no_form` Modifier

### Problem

Some contracts — particularly `privileged`, `irreversible`, or `effect` contracts —
should not be callable through form syntax. There is no mechanism in PROP-Forms-v0
to enforce this.

### Solution

A new contract-level modifier: `no_form`.

```igniter
privileged no_form contract DeleteTenant(tenant_id: TenantId) -> Unit {
  ...
}
```

Effect: the compiler **refuses to register any form** for this contract, and **refuses
to match** this contract during form resolution. It is callable only by explicit name:

```igniter
-- Compile error — no_form enforced:
tenants.delete { it.id == target_id }

-- Always valid — explicit call:
DeleteTenant(tenant_id: target)
```

### Semantics

- `no_form` is checked in Phase 1 (Header Scan). If a `no_form` contract has a
  `form` declaration in its body, the compiler emits `E-FORM-NOFM-DECL` (error).
- `no_form` is recorded in the `.ifh`. Downstream modules that attempt to `import M`
  where `M` contains a `no_form` contract will never receive form entries for it.
- `no_form` does not affect explicit qualification: `Contract(args)` always works.
- Combining `no_form` with `contract_shape` that has a form declaration:
  the implementing contract's `no_form` **suppresses** the inherited form.

### Error codes (new)

| Code | Phase | Description |
|------|-------|-------------|
| `E-FORM-NOFM-DECL` | Phase 1 | `no_form` contract has a `form` declaration |
| `E-FORM-NOFM-MATCH` | Phase 3 | Form resolution would match a `no_form` contract |

---

## §E3. Structural Validity Rules

PROP-Forms-v0 defines FormPattern invariants (§1) and error codes (§15) but does
not enumerate all compile-time structural rules that the Form Compiler enforces
in Phase 2. The following six rules complete the picture.

### Rule F-01: Block argument requires at least one positional prefix

A `BlockRef` in a form pattern must be preceded by at least one `ArgRef` or `Literal`.
A form that starts directly with a block is not a valid FormKind.

```igniter
-- INVALID — block before any anchor:
form { (body) } ".do"

-- VALID — receiver first:
form (collection) ".do" { (body) }
```

Error: `E-FORM-STRUCT` — "BlockRef must be preceded by at least one ArgRef or Literal"

### Rule F-02: At most one BinderRef per form pattern tree

A single form pattern may contain at most one `BinderRef`. Multiple binders
in one form create ambiguous scope.

```igniter
-- INVALID:
form "zip" [a] "with" [b] "in" (coll) { (body) }

-- Resolution: use a single binder, pass the pair:
form "zip" [pair] "in" (coll) { (body) }
```

Error: `E-FORM-BINDER` (already in PROP-Forms-v0) — extended to cover this case.

### Rule F-03: Keyword form token must not be an existing identifier in scope

A `KeywordBlockForm` literal that shares a name with an `ArgRef` parameter of the
**same** contract causes ambiguity in form parsing. The compiler rejects this.

```igniter
-- Contract has parameter named "guard":
contract Check(guard: Boolean, ...) -> Unit
  form "guard" (guard) "else" (errors)   -- ERROR: "guard" is both literal and param name
```

Error: `E-FORM-KW-SHADOW` — "keyword literal '{token}' conflicts with parameter name '{token}'"

### Rule F-04: PostfixMethodForm priority must be ≥ 8

A postfix method form with priority < 8 will always lose precedence to infix forms,
making it unreachable without explicit parentheses. The compiler warns.

```igniter
-- WARNING:
form (collection) ".count"
  priority 3    -- lower than comparison ops
```

Warning: `W-FORM-PRIO` — "PostfixMethodForm with priority < 8 may be unreachable; recommended: ≥ 8"

### Rule F-05: InfixForm token must be a symbolic token

An `InfixForm` pattern token must be a symbolic operator, not an alphabetic identifier.
Alphabetic infix forms create ambiguous grammar with value references.

```igniter
-- INVALID — alphabetic token in infix position:
form (a) "is_a" (b)

-- VALID:
form (a) "=~" (b)     -- symbolic
form (a) "@" (b)      -- symbolic
```

Error: `E-FORM-KIND` — extended: "InfixForm token must be a symbolic operator, not an identifier"

### Rule F-06: Multi-form contracts must have consistent type constraints

All forms declared on a single contract must resolve to the same type signature.
A contract with inconsistent type constraints across its forms is rejected.

```igniter
-- INVALID — different type constraints:
contract Add[T: Numeric](left: T, right: T) -> result: T
  form (left) "+" (right)
  form "add_str" "(" (left: String) "," (right: String) ")"  -- different types

-- VALID — same types, different syntax:
contract Add[T: Numeric](left: T, right: T) -> result: T
  form (left) "+" (right)
  form "add" "(" (left) "," (right) ")"
```

Error: `E-FORM-PARAM` (already in PROP-Forms-v0) — extended to cover multi-form type consistency.

---

## §E4. `form_resolution_trace` in Diagnostics

### Problem

PROP-Forms-v0 §15 defines error codes for failed resolution. There is no artifact
capturing successful resolutions. When type-directed dispatch is involved, it is
not obvious which contract was chosen and why — a debugging blind spot.

### Solution

The Phase 3 compiler emits a `form_resolution_trace` section in `diagnostics.json`
(alongside existing `parse_errors`).

### Format

```json
{
  "form_resolution_trace": [
    {
      "kind":         "resolved",
      "expr":         "items + more_items",
      "trigger":      "+",
      "location":     { "line": 42, "col": 15 },
      "candidates":   [
        "stdlib.Collection.CollectionConcat",
        "stdlib.Numeric.Add",
        "stdlib.String.Concat"
      ],
      "type_filtered":  ["stdlib.Collection.CollectionConcat"],
      "profile_filtered": ["stdlib.Collection.CollectionConcat"],
      "resolved_to":  "stdlib.Collection.CollectionConcat",
      "priority":     5,
      "trust_level":  "stdlib"
    },
    {
      "kind":         "ambiguity_warning",
      "expr":         "v1 + v2",
      "trigger":      "+",
      "location":     { "line": 55, "col": 8 },
      "candidates":   ["stdlib.Numeric.Add", "MyVectors.VecAdd"],
      "reason":       "types (Vector3, Vector3) match both; equal trust_level",
      "suggestion":   "use import MyVectors overriding + or explicit call"
    }
  ]
}
```

### Emission rules

- Trace is emitted only when the compiler flag `--form-trace` is set, or when
  a diagnostics verbosity level ≥ 2 is configured.
- In normal compilation, only `kind: "ambiguity_warning"` and `kind: "error"` events
  are emitted (resolution successes are suppressed for performance).
- The trace is written to the `.igapp/diagnostics.json` artifact alongside existing fields.

### Trace event kinds

| Kind | When emitted |
|------|-------------|
| `resolved` | Successful resolution (verbose mode only) |
| `ambiguity_warning` | Multiple candidates survived all filters |
| `type_error` | No candidates after TYPE FILTER |
| `profile_error` | No candidates after PROFILE FILTER |
| `trigger_miss` | Trigger token not in Form Registry |
| `deprecated_used` | Form matched but marked deprecated |

---

## §E5. MultiKeywordForm — Seventh FormKind

### Problem (PROP-Forms-v0 §17 Q4)

`match value { arm => expr; ... }` does not fit any of the six FormKind variants.
`KeywordBlockForm` handles `keyword [binder] "in" (expr) { body }` but not
structured arm-based dispatch.

Leaving `match` as a compiler primitive creates a two-tier language where users
cannot define match-like syntax. This violates the core principle.

### Solution: `MultiKeywordForm` — the seventh FormKind

```
MultiKeywordForm
  Declaration:  form "keyword" (scrutinee) "{" [arm-pattern]* "}"
  Pattern:      keyword  expr  {  arm  =>  expr  ;  ...  }
  Arity:        1 scrutinee + 1 structured Arms argument
  Arm type:     MatchArm[T, R] = { pattern: T -> Boolean, value: T -> R }
  Example:
    match risk { > 0.8 => :blocked; _ => :ok }
    match status { :active => proceed(); :paused => wait(); _ => error("unknown") }
```

### FormKind → FormPattern mapping (extension)

| FormKind | FormPattern |
|----------|-------------|
| `MultiKeywordForm` | `Sequence([Literal(keyword), ArgRef(scrutinee), Literal("{"), Repeat(ArmRef, ";"), Literal("}")])` |

Where `ArmRef` is a new `FormPattern` variant:

```igniter
meta type FormPattern =
  -- (all existing variants from PROP-Forms-v0 §1)
  ...
  | ArmRef(scrutinee_param: String)
      -- Structured match arm: pattern => expr
      -- Only valid inside MultiKeywordForm
      -- Compile-time desugared to: MatchArm[T, R] collection
```

### Arm syntax

```igniter
-- Arms are parsed as: pattern => expr
-- Pattern may be:
--   literal value:       42 => ...
--   comparison op:       > 0.8 => ...
--   symbol:              :active => ...
--   wildcard:            _ => ...
--   binder with guard:   [x] where x.valid? => ...

match value {
  :ok      => handle_ok(value)
  :error   => handle_error(value)
  _        => fallback()
}
```

### `match` as MultiKeywordForm in stdlib.Control

```igniter
contract MatchExpr[T, R](scrutinee: T, arms: Collection[MatchArm[T, R]]) -> result: R
  form "match" (scrutinee) "{" [arm]* "}"
  priority 1
{
  let matched = arms.find { it.matches(scrutinee) }
  guard matched.present? else :match => "no matching arm"
  result = matched.value.execute(scrutinee)
}
```

### Access rule

`MultiKeywordForm` is available to users (trust_level: :user allowed).
The arm syntax `[arm]*` uses the `Repeat` FormPattern variant —
but only **within** a `MultiKeywordForm` declaration. Users cannot use bare `Repeat`
outside this context. The compiler enforces this via the FormKind structural check.

### Error codes (new)

| Code | Phase | Description |
|------|-------|-------------|
| `E-FORM-ARM-EMPTY` | Phase 2 | MultiKeywordForm declared with zero arms |
| `E-FORM-ARM-NO-WILD` | Phase 3 | match expression has no wildcard arm and exhaustiveness cannot be proved |

---

## §E6. BinderRef in MethodCallForm

### Problem (PROP-Forms-v0 §17 Q1)

PROP-Forms-v0 §7 restricts `BinderRef` to `BlockMethodForm` and `KeywordBlockForm`.
This means there is no way to write `items.reduce([acc] start: 0)` as a form.
The common `reduce/fold` pattern requires carrying a running value across iterations —
a BinderRef-like concept applied to a non-block argument.

### Solution: `AccumulatorRef` — a new FormPattern variant

Rather than allowing arbitrary `BinderRef` in `MethodCallForm` (which would make
the two forms nearly identical), we introduce a dedicated variant:

```igniter
meta type FormPattern =
  -- (existing variants)
  ...
  | AccumulatorRef(name: String, init_param: String)
      -- Introduces an accumulator variable with an initial value
      -- Declared as: [acc from (init)]
      -- The accumulator is threaded through the block automatically
      -- Only valid in MethodCallForm or BlockMethodForm
```

### Syntax

```igniter
contract Reduce[T, R](
  collection:   Collection[T],
  init:         R,
  accumulator:  (R, T) -> R
) -> result: R
  form (collection) ".reduce" "[" acc "from" (init) "]" { (accumulator) }
  priority 10
{ result = collection.__fold(init, accumulator) }
```

Usage:

```igniter
total = items.reduce [sum from 0] { sum + it.amount }
merged = parts.reduce [acc from ""] { acc + it.text }
```

### Semantics

- `[acc from (init)]` is syntactic sugar. The compiler desugars it to:
  a `MethodCallForm` with an extra `ArgRef("init")` and a `BlockRef` where
  the block receives `(acc, it)` as parameters.
- `acc` is visible only inside the `{ }` block — same scoping as `BinderRef`.
- `it` remains the implicit second parameter of the block.
- The desugared lambda has signature `(R, T) -> R` where `R` is inferred from `init`.

### Access rule

`AccumulatorRef` is available to users (trust_level: :user allowed).
It is a `MethodCallForm` extension, not a new FormKind.

---

## §E7. Two-Phase Compiler Mapping

### Context

The igniter-compiler (`igniter-lab/igniter-compiler/src/`) implements:
```
parse → classify → typecheck → emit
```

PROP-Forms-v0 describes a three-phase model:
```
Phase 1: Header Scan → .ifh
Phase 2: Form Compiler → Form Registry + .ifc
Phase 3: Contract Compiler → .iri + .ilk
```

### Alignment

| igniter-compiler stage | PROP-Forms-v0 phase | What happens |
|------------------------|---------------------|--------------|
| `lexer.rs` + `parser.rs` | Phase 1 (partial) | Tokenize, produce generic AST with `BinaryOp`, `UnaryOp`, `FieldAccess` — **type-blind** |
| `classifier.rs` | Phase 1 (remainder) | Extract contract declarations, type params, form declarations into `.ifh`-equivalent |
| `typechecker.rs` | Phase 2 | Build Form Registry from all known form declarations; type-check expressions |
| **NEW: form_resolver.rs** | Phase 2 + 3 boundary | Walk typed AST, replace `BinaryOp`/`UnaryOp`/`FieldAccess` with `ContractInvocation` nodes |
| `emitter.rs` | Phase 3 | Emit `.igapp/` artifacts including `form_table.json` (see §E7.2) |

### Key invariant

The parser **must not** attempt to resolve forms. It produces generic operator nodes:

```rust
// parser.rs — CORRECT: type-blind
Expr::BinaryOp { op: "+", left: ..., right: ... }

// form_resolver.rs — CORRECT: type-informed
Expr::ContractInvocation { contract: "stdlib.Numeric.Add", args: [...] }
```

This is already the case in igniter-compiler. The `binary_prec` table in `parser.rs`
provides priority ordering for the parser pass. After form resolution, priorities
come from the Form Registry instead.

### New artifact: `form_table.json`

The emitter should produce `form_table.json` inside each `.igapp/` output:

```json
{
  "artifact": "form_table",
  "module":   "MyApp",
  "resolved": [
    {
      "trigger":    "+",
      "left_type":  "Integer",
      "right_type": "Integer",
      "contract":   "stdlib.Numeric.Add",
      "priority":   5
    },
    {
      "trigger":    "@",
      "left_type":  "Store[Booking]",
      "right_type": "Timestamp",
      "contract":   "stdlib.Temporal.TemporalAt",
      "priority":   10
    }
  ],
  "ambiguities": [],
  "unused_forms": []
}
```

This artifact enables:
- IDE autocomplete without re-running the compiler
- CI compatibility checks between module versions
- `form_resolution_trace` population (§E4)

### `@` token — already ready

`TokenType::At` is already lexed in `lexer.rs`. The `TemporalAt` pattern
`(store) "@" (at)` will work immediately once form resolution is wired.
No lexer change required.

---

## §E8. Answers to PROP-Forms-v0 §17 Open Questions

### Q1: BinderRef in MethodCallForm?

**Resolved in §E6.** Solution: `AccumulatorRef` — a dedicated variant for
fold/reduce patterns, not a general BinderRef extension. This avoids conflating
`BlockMethodForm` and `MethodCallForm`.

### Q2: Priority InfixForm with identifiers

**Decision: disallow.** Rule F-05 (§E3) forbids alphabetic tokens in `InfixForm`.
If `x is_a T` becomes necessary in the future, it should be a `KeywordBlockForm`
without a block: `form "is_a" (value) (type)` — which is a degenerate
KeywordBlockForm with zero block components. Until then: symbolic operators only
for infix forms.

### Q3: Multi-form order at same priority

**Decision: declaration order.** When a contract has two forms of the same kind at
the same priority, the compiler tries them in declaration order. First match wins.
This is deterministic and matches the user's expectation ("I listed this one first").
The compiler emits `W-FORM-ORDER` when this situation occurs, to make it visible.

### Q4: FormKind for multi-keyword (match)

**Resolved in §E5.** `MultiKeywordForm` — the seventh FormKind.

### Q5: Explicit form qualification and IDE

**Decision: `::form_kind` syntax is correct.** The syntax `Add::infix(a, b)` uses the
existing `::` qualifier pattern. For IDE support, the Form Registry (§4 of
PROP-Forms-v0) already contains all necessary information. IDEs should read the
`form_table.json` artifact for autocomplete, not re-run resolution.

No `@form_kind` annotation is needed — it would add a second syntax for the same thing.

### Q6: Deprecation workflow configurability

**Decision: profile-configurable grace period.** Default deprecation timeline:

```
deprecated: true       → W-FORM-DEPRECATED (warning)
after grace_period     → E-FORM-DEPRECATED (error, blocks compilation)
default grace_period   = 90 days
```

Profile override:

```igniter
profile strict_upgrade {
  form_deprecation_grace: 0    -- errors immediately
}

profile legacy_compat {
  form_deprecation_grace: 365  -- one year
}
```

---

## §E9. Consolidated Error Code Table (additions only)

New codes introduced in this document, supplementing PROP-Forms-v0 §15:

| Code | Phase | Introduced in |
|------|-------|---------------|
| `E-FORM-SHAPE-TYPE` | Phase 2 | §E1 — FormShape type constraint violation |
| `E-FORM-SHAPE-CONFLICT` | Phase 2 | §E1 — Incompatible form re-declaration on implementor |
| `E-FORM-NOFM-DECL` | Phase 1 | §E2 — `form` on `no_form` contract |
| `E-FORM-NOFM-MATCH` | Phase 3 | §E2 — Resolution would select `no_form` contract |
| `E-FORM-STRUCT` | Phase 2 | §E3 F-01 — Block before positional anchor |
| `E-FORM-KW-SHADOW` | Phase 2 | §E3 F-03 — Keyword literal shadows parameter name |
| `W-FORM-PRIO` | Phase 2 | §E3 F-04 — PostfixMethodForm with priority < 8 |
| `E-FORM-ARM-EMPTY` | Phase 2 | §E5 — MultiKeywordForm with zero arms |
| `E-FORM-ARM-NO-WILD` | Phase 3 | §E5 — Non-exhaustive match |
| `W-FORM-ORDER` | Phase 2 | §E8 Q3 — Multi-form same-priority declaration order |

---

## §E10. Summary: What Changes in the Compiler

Ordered by implementation priority:

```
1. [lexer.rs]      "form", "priority", "associativity", "no_form" → KEYWORDS
                   (already: "form" missing; "no_form" missing)

2. [parser.rs]     FormDecl struct + parse_form_decl()
                   ContractDecl.forms: Vec<FormDecl>
                   ContractDecl.no_form: bool
                   Import.hiding: Vec<String>
                   Import.overriding: Vec<String>
                   ContractShapeDecl.forms: Vec<FormDecl>     [§E1]

3. [classifier.rs] Extract FormEntry from ContractDecl.forms
                   Record inherited_from for contract_shape forms [§E1]
                   Enforce no_form + form co-presence error       [§E2]
                   Apply structural rules F-01..F-06              [§E3]

4. [NEW: form_resolver.rs]
                   Walk TypedProgram AST
                   Build Form Registry from all FormEntry
                   Replace BinaryOp/UnaryOp/FieldAccess with ContractInvocation
                   Emit form_resolution_trace events              [§E4]

5. [emitter.rs]    Emit form_table.json per .igapp/              [§E7]
                   Include form_resolution_trace in diagnostics.json [§E4]

6. [typechecker.rs] Consume Form Registry for type-directed disambiguation
                   Enforce E-FORM-ARM-NO-WILD exhaustiveness       [§E5]
```

---

## Non-Goals (additions to PROP-Forms-v0 §16)

```
✗ Runtime form registration — no forms added after compilation
✗ Nested MultiKeywordForm — match inside match arm is standard nesting, not a new FormKind
✗ AccumulatorRef outside MethodCallForm/BlockMethodForm
✗ FormShape on struct/type declarations (only contract_shape)
✗ no_form inheritance — a contract_shape cannot be no_form
```

---

*Lab-local document. Does not create canonical Igniter semantics without explicit
mainline acceptance. Supersedes nothing in Agent-C archive.*

*→ Next: proof-of-concept implementation of form_resolver.rs in igniter-compiler*
