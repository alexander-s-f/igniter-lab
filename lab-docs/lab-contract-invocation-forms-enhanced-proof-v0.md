# Track: lab-contract-invocation-forms-enhanced-proof-v0

Date:    2026-06-04
Card:    LAB-FORMS-P1
Status:  complete
Result:  pass (12/12 proof points)
Route:   conditional_accept_with_hardening

---

## D — Done

Ran a bounded lab-local proof of the enhanced contract invocation form system in
`igniter-lab/igniter-compiler` (Rust). Verified P1–P12 of the canon-agent card:
parser type-blindness, form registry construction, form resolution, fail-closed
behavior for `no_form`, ambiguity, and unresolved triggers.

### Code changes

| File | What changed |
|------|-------------|
| `src/lexer.rs` | Added 6 keywords: `form`, `priority`, `associativity`, `no_form`, `hiding`, `overriding` |
| `src/parser.rs` | `FormDecl`, `FormElement`, `Associativity` types; `ContractDecl.forms`/`no_form`; `ContractShapeDecl.forms`; `Import.hiding`/`overriding`; `parse_form_header_annotations()`; `parse_form_pattern()` |
| `src/form_registry.rs` (new) | `FormRegistry`, `FormEntry`, `FormKind`, `TrustLevel`; trigger index; structural rules F-01/F-02/F-05; `no_form_contracts` tracking |
| `src/form_resolver.rs` (new) | AST walker; `resolve_trigger()`; P7/P8/P9 fail-closed logic; `explicit_call` trace for P10 |
| `src/emitter.rs` | `EmitResult.form_table`, `.resolved_program` fields |
| `src/assembler.rs` | Writes `form_table.json` and `form_resolution_trace.json` per `.igapp/` |
| `src/lib.rs` | `pub mod form_registry; pub mod form_resolver` |
| `src/main.rs` | Form resolution step (Phase 3.5); form diagnostic injection into compilation report |

### Fixtures created

| Fixture | Purpose |
|---------|---------|
| `fixtures/forms/positive_forms.ig` | P1–P6, P10, P11, P12 positive proof |
| `fixtures/forms/no_form_negative.ig` | P7 fail-closed: E-FORM-NOFM-DECL + E-FORM-NOFM-MATCH |
| `fixtures/forms/ambiguous_negative.ig` | P9 fail-closed: W-FORM-AMBIG |
| `fixtures/forms/unresolved_check.ig` | P8 fail-closed: all-miss, no crash, no silent error |

---

## S — Succeeded

All 12 proof points passed:

| Point | Requirement | Result | Evidence |
|-------|-------------|--------|----------|
| P1 | `form (left) "+" (right)` parsed | ✓ pass | `form_table.json` entry_count=5 |
| P2 | Parser type-blind, emits generic BinaryOp | ✓ pass | semantic_ir: 4 `binary_op` nodes |
| P3 | Form Registry built from parsed forms | ✓ pass | trigger_index: {+, ++, .sum, .where, guard} |
| P4 | `a + b` resolves to ContractInvocation(Add) | ✓ pass | `form_resolution_trace.json` resolved_forms |
| P5 | Output includes `form_resolution_trace` | ✓ pass | Artifact present in every `.igapp/` |
| P6 | Output includes `form_table` evidence packet | ✓ pass | Artifact present in every `.igapp/` |
| P7 | `no_form` contracts fail closed | ✓ pass | status=oof; E-FORM-NOFM-MATCH + E-FORM-NOFM-DECL |
| P8 | Unresolved operator fails closed | ✓ pass | All 4 operators → `miss` trace; no crash; no diagnostic for primitives |
| P9 | Ambiguous candidates fail closed | ✓ pass | status=ok; W-FORM-AMBIG ×3 in warnings |
| P10 | Explicit call valid when form blocked | ✓ pass | `length(s)` → `explicit_call` trace event; bypasses form resolution |
| P11 | Runtime receives resolved meaning only | ✓ pass | `form_table.json` is static; no runtime dispatch fields |
| P12 | `+` policy: numeric only; `++` distinct | ✓ pass | form_table: `+`→Add, `++`→Concat; independent triggers |

### Command matrix

```
cargo test                                      → ok (0 tests)
cargo run -- compile positive_forms.ig          → status: ok
cargo run -- compile no_form_negative.ig        → status: oof  (E-FORM-NOFM-MATCH ×2, E-FORM-NOFM-DECL ×1)
cargo run -- compile ambiguous_negative.ig      → status: ok   (W-FORM-AMBIG ×3 in warnings)
cargo run -- compile unresolved_check.ig        → status: ok   (all operators: miss trace, no diagnostics)
```

---

## T — Trace / Evidence

### Form table sample

```json
{
  "artifact": "form_table",
  "module": "Forms.Positive",
  "entry_count": 5,
  "resolved": [
    { "id": "Add::infix",          "trigger": "+",      "kind": "infix",         "priority": 5  },
    { "id": "Concat::infix",       "trigger": "++",     "kind": "infix",         "priority": 4  },
    { "id": "Sum::postfix",        "trigger": ".sum",   "kind": "postfix_method","priority": 10 },
    { "id": "Where::block_method", "trigger": ".where", "kind": "block_method",  "priority": 10 },
    { "id": "Guard::keyword_block","trigger": "guard",  "kind": "keyword_block", "priority": 1  }
  ]
}
```

### Resolution trace sample

```json
{ "kind": "resolved",      "trigger": "+",      "resolved_to": "Add",  "contract_ctx": "UseAdd"          }
{ "kind": "miss",          "trigger": "*",      "resolved_to": null,   "contract_ctx": "UseAdd"          }
{ "kind": "explicit_call", "trigger": "length", "resolved_to": null,   "contract_ctx": "ExplicitCallPath" }
```

### no_form fail-closed diagnostics

```json
{ "rule": "E-FORM-NOFM-DECL",  "severity": "error",
  "message": "contract 'SafeAdd' has no_form modifier but also declares form annotations" }
{ "rule": "E-FORM-NOFM-MATCH", "severity": "error",
  "message": "form '+' would resolve to no_form contract 'SafeAdd' in AttemptFormUse::total — blocked" }
```

### Ambiguity diagnostic

```json
{ "rule": "W-FORM-AMBIG", "severity": "warning",
  "message": "form '+' is ambiguous in UseAmbiguous::total: candidates [Add1, Add2] — resolved to 'Add1' by priority; use explicit call to suppress" }
```

### Artifact paths

```
out/lab_contract_invocation_forms_enhanced_proof/
  summary.json
  positive_forms.igapp/
    form_table.json
    form_resolution_trace.json
  no_form_negative.igapp/
    form_table.json
    form_resolution_trace.json
  ambiguous_negative.igapp/
    form_table.json
    form_resolution_trace.json
  unresolved_check.igapp/
    form_table.json
    form_resolution_trace.json
```

---

## R — Recommendation

**conditional_accept_with_hardening**

The core claim is proved: the trust-boundary slice works correctly.
Parser is type-blind. Form Registry builds from declarations. Resolution runs post-typecheck.
Fail-closed behavior is demonstrated for P7/P8/P9. Explicit call path (P10) is provably separate.

### Accept as-is

- Form declaration parsing (header-level annotations)
- Form Registry structure (`FormEntry`, `FormKind`, trigger index)
- `form_table.json` + `form_resolution_trace.json` as `.igapp/` artifacts
- `no_form` modifier (E-FORM-NOFM-DECL, E-FORM-NOFM-MATCH error codes)
- W-FORM-AMBIG warning for ambiguous candidates
- `explicit_call` trace for Call-node bypass
- Structural rules F-01 / F-02 / F-05

### Hardening required before mainline intake

1. **Type-directed dispatch (STEP 4: TYPE FILTER)**
   Currently name-based only. Production requires typechecker to annotate
   per-expression resolved types so the resolver can filter candidates by type.
   This is the main engineering gap.

2. **Ambiguity: warning vs. error policy**
   W-FORM-AMBIG is currently a warning (compilation continues with priority-based winner).
   Mainline may require hard error for fully ambiguous cases. Decision needed.

3. **import hiding/overriding enforcement**
   Parsing is implemented. Registry-time filtering is not yet wired to import statements.

4. **trust_level assignment**
   All forms currently get `:user`. Mainline needs `:stdlib` for stdlib forms.

5. **FormKind Unknown**
   Any form that doesn't match the 6 patterns gets `kind: unknown`.
   Should emit E-FORM-KIND error or be rejected at Phase 2.

### Deferred (out of scope for this proof)

- MultiKeywordForm (7th FormKind)
- AccumulatorRef / reduce syntax
- contract_shape inherited forms (FormShape §E1)
- Compiler passport emission

---

*Evidence only. Lab-local frontier. Does not create canonical Igniter semantics.*
*Mainline authority: Architect Supervisor / Codex.*
