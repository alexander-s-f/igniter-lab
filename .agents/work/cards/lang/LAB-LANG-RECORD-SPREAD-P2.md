# LAB-LANG-RECORD-SPREAD-P2 - Pure record spread/update syntax

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: implementation-proof
Delegation code: OPUS-LANG-RECORD-SPREAD-P2
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-LANG-RECORD-ERGONOMICS-READINESS-P1` split record pain into two different problems:

- default-field noise wants optional fields / defaults, but that is canon-gated by the optional-field PROP;
- context accumulation wants pure record spread/update, which is a clean lab slice and does not decide
  absence/default semantics.

Live pressure:

- app context accumulation currently repeats boilerplate `CtxWith*` contracts;
- relational and IgWeb contexts want "copy this record and add/override one field";
- ViewArtifact flat-record verbosity should **not** be solved here; helper contracts remain the v0 path until
  optional fields are designed.

This card should implement record spread as deterministic sugar over existing record construction.

## Goal

Support a minimal record spread/update expression:

```ig
compute enriched : Ctx = { ...ctx, todo_id: todo_id }
compute bumped : Counter = { ...counter, count: counter.count + 1 }
```

Semantics:

- spread copies fields from a known record value;
- explicit fields override copied fields;
- all required fields of the expected output record must be present after expansion;
- extra fields remain rejected;
- result is an ordinary record value with the same VM serialization as an explicit literal.

## Verify First

Read live code before editing:

- `lang/igniter-compiler/src/lexer.rs` token handling for `...` / dots;
- `lang/igniter-compiler/src/parser.rs` record literal parsing;
- `lang/igniter-compiler/src/typechecker.rs`
  - record literal typing;
  - field lookup;
  - missing/extra-field diagnostics;
- `lang/igniter-compiler/src/emitter.rs` record literal emission;
- `lang/igniter-vm` record serialization behavior if needed;
- fixtures that construct records, nested records, and collections of records;
- lead/router or context fixtures with `CtxWith*` boilerplate;
- `lab-docs/lang/lab-lang-record-ergonomics-readiness-p1-v0.md`.

Confirm or correct:

- whether tokenizing `...` already exists or must be added;
- whether record literal AST can carry spread entries without disturbing existing literals;
- whether the expected output type is available during record-literal checking;
- whether source spread type can be inferred from the spread expression;
- whether the right implementation point is typecheck-time expansion or emitter-time expansion.

Live code wins over this card.

## Recommended Implementation Shape

Prefer **one spread entry v0** unless multiple spread entries are already trivial:

```ig
{ ...base, field: value }
```

Validation rules:

- spread expression must typecheck to a record type;
- target/expected type must be a record type;
- copied fields are those present in both source and target records;
- explicit fields override spread-copied values;
- explicit duplicate fields remain an error;
- after expansion, existing record shape checker enforces missing/extra fields;
- if the target type is not known, emit a clear diagnostic instead of guessing.

Implementation preference:

- desugar to an explicit field-by-field record construction once types are known;
- reuse existing record-literal emission and VM serialization;
- do not introduce runtime reflection or dynamic maps.

If live code makes "source fields present in target" unsafe, narrow the slice to same-type update only:

```ig
Counter -> Counter: { ...counter, count: next }
```

and document what blocks widening to source-subset / target-superset.

## Required Acceptance

- [x] Same-type update works: `{ ...counter, count: counter.count + 1 }`.
- [x] Accumulation works: source record fields plus one explicit target field produce a larger target record (source ⊂ target).
- [x] Explicit field override wins over spread-copied field.
- [x] Explicit duplicate fields are rejected (`duplicate field`).
- [x] Unknown/non-record spread source is rejected with a clear diagnostic.
- [x] Missing required target field after spread+explicit fields is rejected by existing record shape logic.
- [x] Extra explicit field is rejected by existing record shape logic.
- [x] Emitted value serializes exactly like an explicit record literal (byte-identical SIR record node).
- [x] Existing record literal tests remain green (full suite 152/0).
- [x] No optional fields or default values are introduced.
- [x] No ViewArtifact schema changes.
- [x] `lang/igniter-compiler cargo test` green (152/0).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Outcome:** record spread/update `{ ...base, field: value }` works as **pure sugar**. Proof doc:
`lab-docs/lang/lab-lang-record-spread-p2-v0.md`.

**Model:** the typechecker expands a top-level spread (where the declared compute/output record type `T` is
known) into an explicit field-by-field `record_literal` — explicit fields override, and every field `T`
declares that the source type `S` also has is copied via a synthesized `field_access(src, g)`; copied-field
types are checked source-vs-target. The expanded literal is stashed as the decl's `annotated_expr`; the
emitter lowers it via the established `annotated_expr → record_literal` path (one new line). **No new SIR node
kind** — `record_spread` never reaches the SIR. Missing/extra fields fall to the existing
`check_record_literal_shape`.

**Files:** `lexer.rs` (`...` token) · `parser.rs` (`Expr::RecordSpread` + leading-`...` parse + duplicate-key
rejection) · `typechecker.rs` (decl-level expansion + nested guard + walk/exhaustiveness mirrors) ·
`classifier.rs` (refs/effect walks + `expr_kind`) · `emitter.rs` (`lower_annotated_expr` record-literal case)
· `form_resolver.rs` (exhaustiveness) + 1 new test file.

**Narrowing (documented):** v0 is **top-level, typed** spread. Nested/untyped spread is **rejected** with a
clear diagnostic (the emitter has no type defs and `annotated_expr` is read only at decl level, so a nested
spread has no target type). Widening needs a general expected-type-threading pass through `infer_expr` —
carded as the next step, not this slice.

**Parity proof:** the spread `{ ...counter, count: counter.count + 1 }` produces a **byte-identical
`record_literal` node** to the hand-written explicit literal, with **no `record_spread`** in the SIR.

**Proof — all green:** record_spread_tests **9**; igniter-compiler **152/0**; string_escapes 10;
loop_conformance 14; igweb 11; match_arm 6; igniter-web 17. `git diff --check` clean.

**Next:** retire a live `CtxWith*` helper with spread; if nested spread becomes load-bearing, card the
`infer_expr` expected-type-threading pass. Optional fields stay on the canon PROP track (not via spread).

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-record-spread-p2-v0.md
```

It must include:

- exact syntax accepted;
- exact narrowing if v0 supports only same-type update;
- parser/typechecker/emitter changes;
- desugaring model;
- diagnostics examples;
- serialization parity proof;
- whether a lead_router / context-accumulation fixture was simplified or only mirrored in tests;
- exact test commands and counts.

Update this card with a closing report.

## Closed Scope

- No optional fields.
- No default values.
- No partial record omission semantics.
- No map/dynamic object spread.
- No variant spread.
- No renderer changes.
- No relational schema changes.
- No canon claim.

## Suggested Next

If record spread lands cleanly, use it in one context-accumulation fixture or Todo/IgWeb context proof. Keep
optional fields on the canon PROP track and do not smuggle them through spread.
