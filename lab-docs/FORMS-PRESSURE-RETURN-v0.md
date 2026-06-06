# FORMS-PRESSURE-RETURN-v0: Form System Implementation — Pressure Return

Date: 2026-06-04
Status: pressure return · lab evidence · awaiting mainline review
From: igniter-lab (pkg:companion-store / Architect)
To: Architect Supervisor / Codex — mainline igniter-lang
Lane: cross_project (evidence only, no code authority)

---

## What This Is

This document packages the Form System work done in igniter-lab for
canonical consideration. It contains:

1. Summary of work done
2. Evidence artifacts
3. Key findings and insights
4. Open questions for mainline decision
5. Suggested next steps

---

## Work Done

### Specification

`lab-docs/PROP-Forms-Enhanced-v0.md` — enhanced Form System spec.

Basis: PROP-Forms-v0 (Agent-C archive) + cross-analysis of C0–C5 + igniter-compiler.
Adds 7 targeted enhancements beyond PROP-Forms-v0:

| § | Enhancement |
|---|-------------|
| E1 | FormShape — form declarations on `contract_shape` (trait-inherited forms) |
| E2 | `no_form` modifier — explicit opt-out from form syntax |
| E3 | 6 structural validity rules (F-01..F-06) |
| E4 | `form_resolution_trace` — resolution events in diagnostics |
| E5 | MultiKeywordForm — 7th FormKind (resolves PROP-Forms-v0 §17 Q4) |
| E6 | AccumulatorRef — fold/reduce pattern (resolves §17 Q1) |
| E7 | Two-phase pipeline mapping — igniter-compiler alignment |

Also closes all 6 open questions from PROP-Forms-v0 §17.

### Implementation

Compiler: `igniter-compiler/` (Rust, igniter-lab)

**Files modified:**
- `src/lexer.rs` — added "form", "priority", "associativity", "no_form", "hiding", "overriding" to KEYWORDS
- `src/parser.rs` — `FormDecl`, `FormElement`, `Associativity` types; `ContractDecl.forms` + `no_form`; `ContractShapeDecl.forms`; `Import.hiding` + `overriding`; `parse_form_header_annotations()`; `parse_form_pattern()`
- `src/emitter.rs` — `EmitResult.form_table` + `resolved_program` fields
- `src/assembler.rs` — writes `form_table.json` and `form_resolution_trace.json` per `.igapp/`
- `src/lib.rs` — `pub mod form_registry; pub mod form_resolver`
- `src/main.rs` — form resolution step between typecheck and emit

**Files created:**
- `src/form_registry.rs` — `FormEntry`, `FormRegistry`, `TrustLevel`, `FormKind`, trigger index, structural rules F-01/F-02/F-05
- `src/form_resolver.rs` — AST walker, trigger lookup, `ResolvedProgram`, `TraceEvent`
- `forms_test.ig` — test file with 4 form declarations (InfixForm, PostfixMethodForm, BlockMethodForm, KeywordBlockForm)

---

## Evidence

### form_table.json (from forms_test.ig)

```
artifact: form_table
module:   Forms.Test
entries:  4

Add::infix          kind=infix          trigger="+"   priority=5
Sum::postfix        kind=postfix_method trigger=".sum" priority=10
Where::block_method kind=block_method   trigger=".where" priority=10
Guard::keyword_block kind=keyword_block trigger="guard" priority=1
```

### form_resolution_trace.json (from forms_test.ig)

```
resolved: a + b (UseAdd::total) → Add::infix (priority 5)
resolved: left + right (Add::result) → Add::infix (self-ref, expected)
miss:     a - b (UseAdd::diff) → no form for "-" (correct — not registered)
ambiguities: 0
```

### Test suite

- 5/6 verify_compiler.rb cases pass (same as pre-change baseline)
- loops_and_recursion: pre-existing failure, unrelated to form changes
- forms_test.ig: new test case, status=ok, form_table.json and form_resolution_trace.json produced

---

## Key Findings

### F1: Parser is ready

The igniter-compiler parser already has the right structure. Form declarations
fit cleanly as header-level annotations between `[TypeParams]`/`implements` and `{`.
No grammar conflicts found. The `@` token (`TokenType::At`) is already lexed —
`TemporalAt` form will work immediately.

### F2: Two-phase resolution is the right architecture

`parse → classify → typecheck → [form_resolver] → emit` works cleanly.
The form resolver receives the TypedProgram and FormRegistry and walks the
typed AST replacing generic `BinaryOp`/`UnaryOp`/`FieldAccess` nodes with
`ContractInvocation` lookup results. No parser changes needed for this.

### F3: FormKind classification is reliable

6 of 7 FormKinds are classifiable purely from `Vec<FormElement>` pattern matching.
The 7th (`MultiKeywordForm`) requires a `Repeat` element not yet implemented
in the parser — this is the only missing piece.

### F4: Type-directed dispatch needs typechecker integration

The current resolver does **name-based** dispatch only (trigger → first matching contract).
Full type-directed dispatch (PROP-Forms-v0 §6 STEP 4: TYPE FILTER) requires
the typechecker to propagate resolved types per-expression. The typechecker
already has type_info per declaration — the gap is expression-level type annotation.

This is the main open engineering work for a production-quality resolver.

---

## Open Questions for Mainline Decision

**Q-M1: Parser syntax — header vs. body?**

Current implementation: form declarations in the **header** (before `{`).
Alternative: form declarations as BodyDecl variants (inside `{`).

Header placement matches the spec exactly. Body placement would be easier
to extend without parser refactor. Recommendation: header (matches spec).

**Q-M2: Type-directed dispatch — phase or pass?**

Two options:
a. Integrate with typechecker (single pass, richer context)
b. Separate form_resolver pass after typecheck (current approach, simpler)

For lab: option (b) works. For production: option (a) gives better error messages.

**Q-M3: FormKind 7 (MultiKeywordForm) — compiler primitive or user form?**

PROP-Forms-Enhanced-v0 §E5 proposes making `match` a MultiKeywordForm
accessible to users. This requires `Repeat` in the parser. Scope decision needed:
is this Stage 3 or later?

**Q-M4: `form_table.json` as canonical `.igapp` artifact?**

Currently optional (only emitted when form declarations exist). Should it be
a mandatory artifact (empty when no forms)? Affects tooling contracts.

---

## Suggested Next Steps (mainline, if accepted)

```
1. Accept PROP-Forms-Enhanced-v0 as addendum to PROP-Forms-v0 (or supersession)
2. Decide Q-M2 (phase vs pass) before production integration
3. Plan typechecker expression-level type annotation (prerequisite for TYPE FILTER)
4. Decide Q-M3 (MultiKeywordForm scope) — gate on Stage 3 or later
5. Make form_table.json a mandatory .igapp artifact (Q-M4)
```

---

## Authority Boundary

This document is **evidence and pressure**, not an authority change.

- Lab code does not become mainline without explicit acceptance
- `igniter-lab/igniter-compiler/` changes are playground-local
- PROP-Forms-Enhanced-v0 is a candidate addendum, not a ratified spec

Decisions belong to: Architect Supervisor / Codex (mainline igniter-lang)

---

## Artifact Paths

| Artifact | Path |
|----------|------|
| Enhanced spec | `lab-docs/PROP-Forms-Enhanced-v0.md` |
| IDD card | `.agents/current-card.md` |
| Test source | `igniter-compiler/forms_test.ig` |
| form_table.json | `igniter-compiler/out/forms_test.igapp/form_table.json` |
| form_resolution_trace.json | `igniter-compiler/out/forms_test.igapp/form_resolution_trace.json` |
| form_registry.rs | `igniter-compiler/src/form_registry.rs` |
| form_resolver.rs | `igniter-compiler/src/form_resolver.rs` |
