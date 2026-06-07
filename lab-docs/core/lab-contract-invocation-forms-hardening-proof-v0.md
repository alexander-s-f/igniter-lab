# Track: lab-contract-invocation-forms-hardening-proof-v0

Date:    2026-06-04
Card:    LAB-FORMS-P2
Depends: LAB-FORMS-P1
Status:  complete
Result:  pass (H1–H7 all addressed)
Route:   conditional_accept_with_remaining_blockers

---

## D — Done

Hardened LAB-FORMS-P1 proof so frontier evidence is protocol-honest.

### Code changes

| File | Change |
|------|--------|
| `src/form_resolver.rs` | H1: `W-FORM-AMBIG` (warning, winner) → `E-FORM-AMBIG` (error, no winner, `resolved_to=null`) |
| `src/form_resolver.rs` | H2: `miss` → `primitive_pass_through` (LANGUAGE_PRIMITIVES set) or `unresolved_trigger` |
| `src/main.rs` | Always write form_table + form_resolution_trace sidecar files even on oof |

### Fixtures created

| Fixture | Purpose |
|---------|---------|
| `fixtures/forms/hardening/positive.ig` | H4-A + H6 + H3 positive proof |
| `fixtures/forms/hardening/ambiguity.ig` | H1: E-FORM-AMBIG, status=oof, no winner |
| `fixtures/forms/hardening/unresolved.ig` | H2: primitive_pass_through classification |
| `fixtures/forms/hardening/no_form.ig` | H5: no_form still fail-closed after H1/H2 |
| `fixtures/forms/hardening/plus_policy.ig` | H4-B/C: + vs ++ independent, String+ rejected |

---

## S — Succeeded

All 7 hardening requirements addressed:

| # | Requirement | Result |
|---|-------------|--------|
| H1 | Ambiguity must fail closed: E-FORM-AMBIG, oof, no winner | ✓ pass |
| H2 | Miss classified honestly: primitive_pass_through vs unresolved_trigger | ✓ pass |
| H3 | SemanticIR sidecar_resolution_only: no ContractInvocation nodes | ✓ pass |
| H4 | + policy: Integer ok, String+ rejected, ++ independent | ✓ pass |
| H5 | no_form unchanged after H1/H2 | ✓ pass |
| H6 | Explicit call trace-visible | ✓ pass |
| H7 | P4/P8/P9 downgraded/corrected | ✓ pass |

### Command matrix

```
cargo test                                         → ok (0 tests)
cargo run -- compile positive.ig                   → status: ok
cargo run -- compile ambiguity.ig                  → status: oof   (E-FORM-AMBIG ×3, resolved_forms=0)
cargo run -- compile unresolved.ig                 → status: ok    (primitive_pass_through ×4)
cargo run -- compile no_form.ig                    → status: oof   (E-FORM-NOFM-MATCH ×2, DECL ×1)
cargo run -- compile plus_policy.ig                → status: oof   (OOF-TY0 ×2 — String+ rejected)
```

---

## T — Trace / Evidence

### H1: E-FORM-AMBIG, no winner

```json
ambiguity.form_resolution_trace.json:
  resolved_forms: []            ← 0 entries (H1: no winner selected)
  trace[0]: {
    "kind": "ambiguity_error",
    "trigger": "+",
    "resolved_to": null,        ← null (H1: no winner)
    "candidates": ["Add1", "Add2"]
  }
```

### H2: primitive_pass_through

```json
unresolved.igapp/form_resolution_trace.json:
  trace_kinds: { "primitive_pass_through": 4 }
  sample: { "kind": "primitive_pass_through", "trigger": "+", "resolved_to": null }
```

`primitive_pass_through` = trigger in LANGUAGE_PRIMITIVES, not in form registry. Correct behavior. Not a security fail-closed claim.

`unresolved_trigger` = trigger NOT in LANGUAGE_PRIMITIVES, not in registry. Honest unknown classification.

`unresolved_form_error` (type mismatch with registered form) = **DEFERRED** — requires type-directed dispatch.

### H3: SemanticIR sidecar

```
positive.igapp/semantic_ir_program.json:
  binary_op nodes:        2  ← SemanticIR unchanged
  contract_invocation:    0  ← no IR lowering
  → sidecar_resolution_only
```

form_table.json and form_resolution_trace.json are evidence sidecars, not IR facts.

### H4: + policy

```
positive.igapp form_resolution_trace:
  trigger='+' → Add @ UseAdd::total        ← Integer + Integer: sidecar resolves to Add

plus_policy.form_table.json (sidecar):
  '+' → Add    (priority 5, infix)         ← + is numeric only
  '++' → Concat (priority 4, infix)        ← ++ is independent trigger

plus_policy.igapp compilation:
  status: oof
  OOF-TY0: "Type mismatch: expected Integer, got String+String"
  → String + String: no form path AND typechecker gate rejects it
```

Sidecar caveat: form resolver does NOT type-direct. If String+String bypassed typechecker, sidecar would incorrectly show "Add". H3 sidecar_resolution_only applies.

### H7: Corrected P1–P12 posture

| P | Old claim | Corrected claim |
|---|-----------|-----------------|
| P4 | pass — resolved to ContractInvocation | **sidecar_pass** — trace shows intent, SemanticIR unchanged |
| P8 | fail-closed | **primitive_pass_through** — language ops pass through correctly; not a security claim |
| P9 | pass (warning) | **pass** — E-FORM-AMBIG error, status=oof, no winner (H1 applied) |

P1, P2, P3, P5, P6, P7, P10, P11, P12: unchanged from LAB-FORMS-P1.

---

## R — Recommendation

**conditional_accept_with_remaining_blockers**

### Hardened claims (accept as frontier evidence)

- Form declaration parsing + Form Registry
- `form_table.json` + `form_resolution_trace.json` as sidecar artifacts
- E-FORM-AMBIG: ambiguity refuses compilation (H1)
- `primitive_pass_through` honest classification (H2)
- `sidecar_resolution_only` honest posture for SemanticIR (H3)
- `+`/`++` policy: registry-level evidence (H4-A/B) + typechecker gate (H4-C)
- `no_form` fail-closed: E-FORM-NOFM-MATCH + DECL (H5)
- `explicit_call` bypass trace-visible (H6)
- `E-FORM-NOFM-MATCH`, `E-FORM-AMBIG` error codes

### Remaining blockers before mainline intake

1. **Type-directed dispatch (TYPE FILTER)** — primary gap.
   Sidecar resolver does name-based lookup only. Without this:
   - P4 remains `sidecar_pass` (not real IR lowering)
   - `unresolved_form_error` (H2 third category) is unrepresentable
   - H4-C relies on typechecker gate, not form gate

2. **FormKind Unknown → E-FORM-KIND error**
   Currently unknown form patterns are silently registered. Should be a Phase 2 error.

3. **Ambiguity: deferred within same contract**
   `E-FORM-AMBIG` fires at USE site (per declaration). Ambiguity within a single contract body fires multiple times. Policy: should fire once per use site with full candidate list.

4. **import hiding/overriding enforcement**
   Parsing is done; registry-time filtering not wired.

5. **sidecar artifacts on oof**
   Form sidecar files are now written on oof via flat-file path. They live outside the `.igapp/` directory structure, breaking the `.igapp/` layout contract. Needs design decision: always-emit igapp directory (with partial artifacts), or separate sidecar dir.

### Deferred (out of scope)

- MultiKeywordForm (7th FormKind)
- AccumulatorRef / reduce syntax
- contract_shape FormShape
- trust_level assignment
- Compiler passport emission

---

*Lab-local frontier evidence. Authority: Architect Supervisor / Codex.*
