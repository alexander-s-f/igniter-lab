# Lab: Rust Variant/Match Front-End and SIR Parity — v0

**Card:** LAB-VARIANT-RUST-P1  
**Status:** Proved (39/39 PASS)  
**Date:** 2026-06-10  
**Route:** LAB RUST PARITY / FRONT-END + SEMANTICIR / NO VM  
**Authority:** lab_only — not canon, not production

---

## Motivation

PROP-044-P7-READINESS surveyed the Rust lab toolchain and found that the Rust
compiler (`igniter-compiler`) had zero variant/match support at every layer:
lexer, parser, typechecker, and emitter. The Ruby canon pipeline had added
variant/match in PROP-044-P3 (parser), P5 (typechecker + OOF-KIND1..5), and
P6 (SIR emitter). Every lab proof that touches variant/match semantics runs on
the Rust compiler — Ruby is canon-only. This gap was the gate blocking
PROP-044-P7 (enforced `Outcome[T,E]` variant).

This doc records the design decisions and implementation shape of
LAB-VARIANT-RUST-P1: adding variant/match to the Rust front end through SIR
emission, producing structural SIR parity with PROP-044-P6.

---

## Scope

**In scope (authorized):**
- `igniter-compiler/src/lexer.rs` — `FatArrow` token, `variant`/`match` keywords
- `igniter-compiler/src/parser.rs` — `VariantDecl`, `VariantArm`, `VariantField`, `MatchArm`, `MatchPattern`, `Expr::VariantConstruct`, `Expr::MatchExpr`
- `igniter-compiler/src/classifier.rs` — pass-through of `variant_declarations`
- `igniter-compiler/src/typechecker.rs` — `VariantShapes`, OOF-KIND1..5, `annotated_expr` flow
- `igniter-compiler/src/emitter.rs` — `variant_declarations` top-level, `match_node` SIR nodes
- 10 fixtures in `igniter-view-engine/fixtures/variant_match/`
- Proof runner `igniter-view-engine/proofs/verify_lab_variant_rust_p1.rb`

**Hard out-of-scope (closed):**
- `igniter-vm/src/*` — zero VM changes
- `Value::Variant` — not added to the VM value enum
- `OP_MATCH`, `OP_PUSH_VARIANT` — no new opcodes
- Match lowering to bytecode — not implemented
- `Outcome[T,E]` sealed type — not introduced
- Failure taxonomy proposal — not in scope
- Ruby canon pipeline — unchanged

---

## Key Design Decisions

### 1. `annotated_expr` flow for enriched SIR data

The Rust pipeline's `Expr` AST and `TypedExpression` are separate types. After
typechecking, the emitter needs variant-specific information (which arm, which
variant, resolved types per arm) that isn't on the raw `Expr`. Rather than
adding a separate IR pass, we added:

```rust
pub struct TypedExpression {
    // ... existing fields ...
    pub annotated_expr: Option<serde_json::Value>,
}
pub struct TypedDecl {
    // ... existing fields ...
    pub annotated_expr: Option<serde_json::Value>,
}
```

The typechecker populates `annotated_expr` on successful inference of
`VariantConstruct` and `MatchExpr` with a JSON blob containing all SIR-ready
data. The emitter checks `annotated_expr` first and uses it when present,
falling back to the existing `semantic_expr_for_compute` path.

This avoids modifying the `Expr` enum or adding a cross-pass IR while keeping
the enriched data co-located with the typed node.

### 2. `VariantShapes` registry

```rust
type VariantShapes = HashMap<String, HashMap<String, HashMap<String, serde_json::Value>>>;
// variant_name → arm_name → field_name → type_ir
```

Built from `ClassifiedProgram.variant_declarations` at the start of
`typecheck_contract`. The match exhaustiveness check, unknown-arm check, and
arm-type checks all consult `VariantShapes`.

### 3. `match_expr` → `match_node` rename in emitter

The TypeChecker produces `kind: "match_expr"` to match the AST name.
The emitter's `lower_annotated_expr` renames it to `kind: "match_node"` to
match the SIR convention established in Ruby PROP-044-P6:

```rust
fn lower_annotated_expr(&self, val: &Value) -> Value {
    match val.get("kind").and_then(|k| k.as_str()) {
        Some("variant_construct") => val.clone(),
        Some("match_expr") => {
            let mut m = val.as_object().cloned().unwrap_or_default();
            m.insert("kind", Value::String("match_node".to_string()));
            Value::Object(m)
        }
        _ => val.clone(),
    }
}
```

### 4. OOF-KIND1..5 in the Rust TypeChecker

All five OOF-KIND diagnostics are now implemented in the Rust typechecker,
matching the behavior of the Ruby P5 implementation:

| Code | Description |
|------|-------------|
| OOF-KIND1 | Non-exhaustive match (missing arms, no wildcard) |
| OOF-KIND2 | Unknown arm (not declared in variant) |
| OOF-KIND3 | Duplicate/unreachable arm |
| OOF-KIND4 | Match subject is not a variant type |
| OOF-KIND5 | Divergent arm result types |

### 5. `variant_declarations` pass-through in classifier

The classifier passes `variant_declarations` from `SourceFile` to
`ClassifiedProgram` unchanged (following the `size_relations` pattern). The
typechecker picks them up via `classified.variant_declarations`.

---

## SIR Shape

**Top-level `semantic_ir_program.json`:**

```json
{
  "variant_declarations": [
    {
      "kind": "variant_decl",
      "name": "PaymentStatus",
      "arms": [
        { "name": "Pending",   "fields": [] },
        { "name": "Confirmed", "fields": [] },
        { "name": "Failed",    "fields": [] }
      ]
    }
  ],
  "contracts": [...]
}
```

**Compute node expr for `match`:**

```json
{
  "kind": "match_node",
  "subject": { "kind": "ref", "name": "payment_status", "resolved_type": { "name": "PaymentStatus", "params": [] } },
  "subject_type": "PaymentStatus",
  "arms": [
    {
      "pattern": { "arm": "Pending", "bindings": [], "wildcard": false },
      "body": { "kind": "literal", "value": "pending", "type_tag": "String", "resolved_type": { "name": "String", "params": [] } },
      "resolved_type": { "name": "String", "params": [] }
    }
  ],
  "exhaustive": true,
  "has_wildcard": false,
  "resolved_type": { "name": "String", "params": [] }
}
```

This is structurally identical to the Ruby PROP-044-P6 SIR output.

---

## Fixtures

| File | Purpose |
|------|---------|
| `01_basic_variant_decl.ig` | variant_construct compiles ok |
| `02_unit_arm_match.ig` | exhaustive match, 3 unit arms |
| `03_wildcard_match.ig` | wildcard `_` covers remainder |
| `04_non_exhaustive_oof_kind1.ig` | OOF-KIND1: missing arm |
| `05_unknown_arm_oof_kind2.ig` | OOF-KIND2: arm not in variant |
| `06_duplicate_arm_oof_kind3.ig` | OOF-KIND3: arm appears twice |
| `07_non_variant_subject_oof_kind4.ig` | OOF-KIND4: Integer subject |
| `08_divergent_arm_types_oof_kind5.ig` | OOF-KIND5: String vs Integer arms |
| `09_scope_isolation.ig` | Two variants in two contracts, no cross-contamination |
| `10_sir_parity.ig` | SIR parity: PaymentStatus / SirParityContract |

---

## Proof Result

**39/39 PASS** — `ruby igniter-view-engine/proofs/verify_lab_variant_rust_p1.rb`

All sections passed:
- VRUST-LEX (3 checks): FatArrow, variant/match keyword tokenisation
- VRUST-PARSE (3 checks): variant_decl, variant_construct, match_expr in AST
- VRUST-TYPE (4 checks): variant shapes, exhaustive match, scope isolation
- VRUST-OOF (6 checks): OOF-KIND1..5 all fire; error fixtures all blocked
- VRUST-SIR (9 checks): variant_declarations + match_node SIR shapes
- VRUST-PARITY (8 checks): structural key parity with Ruby PROP-044-P6
- VRUST-REG (1 check): prior conformance fixtures unaffected
- VRUST-CLOSED (5 checks): VM untouched, no Value::Variant, no OP_MATCH

---

## What This Proves

- The Rust lab compiler can lex, parse, typecheck, and emit SIR for variant/match
- OOF-KIND1..5 are enforced in the Rust typechecker at the same level as Ruby
- The SIR shape produced is structurally identical to the Ruby PROP-044-P6 output
- The VM remains untouched — this is front-end + SIR only

## What This Does NOT Prove

- VM execution of match (no `Value::Variant`, no `OP_MATCH`)
- Match lowering to bytecode (Path B — requires PROP-044-P7b)
- `Outcome[T,E]` as an enforced variant type (requires PROP-044-P7a gate)
- Any canon or production authority

---

## Next Steps

LAB-VARIANT-RUST-P1 satisfies the precursor condition for PROP-044-P7 (Rust
front-end gate open). The next step is PROP-044-P7b: lower `match_node` to
`OP_GET_FIELD`/`OP_EQ`/`OP_JMP_UNLESS`/`OP_PUSH_RECORD` in the existing VM
(Path B from the P7-READINESS survey) — no new opcode, no `Value::Variant`.
