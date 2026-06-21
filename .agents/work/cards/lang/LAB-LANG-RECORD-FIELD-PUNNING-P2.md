# LAB-LANG-RECORD-FIELD-PUNNING-P2 - `{ field }` sugar for record literals

Status: CLOSED
Lane: parallel / language-surface / app-pressure
Type: implementation-proof
Delegation code: OPUS-LANG-RECORD-FIELD-PUNNING-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4` found that after signature-bound contracts,
comprehensions, fallible binding, `RenderView`, and helper contracts, one high-frequency friction remains:

```ig
{ account_id: account_id, todo_id: todo_id, title: title }
```

The same pattern appears in:

- relational `QueryFilter` / `QueryPlan` construction;
- `WriteIntent` / `WriteValues` construction;
- context accumulation records;
- ViewArtifact helper contracts;
- route-param plumbing in IgWeb handlers.

Record spread already exists:

```ig
{ ...ctx, account: account }
```

This card adds the smaller neighboring sugar:

```ig
{ account_id, todo_id, title }
```

desugars to:

```ig
{ account_id: account_id, todo_id: todo_id, title: title }
```

This is ergonomics only. It must not change authority, evaluation order, record typechecking, or runtime
representation.

## Goal

Implement and prove record field punning in the Rust lab compiler:

```ig
compute filter : QueryFilter = { field: "account_id", op: "eq", value: account_id }
compute values : WriteValues = { account_id, title, done }
compute ctx    : Ctx = { req, user, account_id }
compute next   : Ctx = { ...ctx, todo_id }
```

The parser may desugar immediately to the existing `Expr::RecordLiteral { fields }` /
`Expr::RecordSpread { fields }` shapes, or it may keep a small AST marker if diagnostics need it. Prefer
immediate desugar unless live parser constraints say otherwise.

## Verify First

Read live code before editing:

- `lang/igniter-compiler/src/lexer.rs`
- `lang/igniter-compiler/src/parser.rs`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/emitter.rs`
- `lang/igniter-compiler/tests/record_spread_tests.rs`
- `lang/igniter-compiler/tests/app_pressure_scorecard_tests.rs`
- `lab-docs/lang/lab-lang-record-ergonomics-readiness-p1-v0.md`
- `lab-docs/lang/lab-lang-app-pressure-ergonomics-scorecard-p4-v0.md`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_view_app/todo_views.ig`

Confirm or correct:

- how `parse_record_or_block` currently distinguishes `{ key: value }`, `{ ...base, f: v }`, and invalid
  forms;
- whether identifiers alone are currently valid inside record literals or rejected;
- whether duplicate fields are already rejected or last-write-wins;
- whether record spread permits punned override fields naturally;
- whether punning should support only plain identifiers or also dotted paths.

Live code wins over this card.

## Design Bias

Recommended v0:

```text
{ name }              => { name: name }
{ name, other: expr } => { name: name, other: expr }
{ ...base, name }     => { ...base, name: name }
```

Closed for v0:

```text
{ account.id }        # no dotted punning; field name would be ambiguous
{ "name" }            # no string-key punning
{ name? }             # no pattern/optional sugar
{ name = expr }       # no alternate separator
```

Duplicate-field behavior should match existing record literals / spreads. If existing behavior is weak, do
not silently broaden it; add a diagnostic only if it is small and local.

## Required Acceptance

- [x] `{ name }` parses and compiles as `{ name: name }`.
- [x] Mixed explicit + punned fields compile.
- [x] Punned fields work in typed `compute` / `output` contexts.
- [x] Punned fields work inside record literals (collection-element form is the same record path).
- [x] Punned fields work with record spread update: `{ ...ctx, todo_id }`.
- [x] Missing symbol fails through the normal unknown-symbol path (`OOF-P1: Unresolved symbol`).
- [x] Unexpected punned field fails through normal record-shape validation (`OOF-TY0: unexpected field`).
- [x] Dotted punning rejected (parse error `Expected name, got Dot`).
- [x] Existing record spread tests remain green (9/0).
- [x] App-pressure Todo-shaped `WriteValues` fixture with punning compiles.
- [x] No VM/runtime change (parser-only; byte-identical SIR).
- [x] No product example rewrite (fixtures only).
- [x] No canon claim.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Outcome:** record field punning `{ name }` ⇒ `{ name: name }` implemented as **parser-only** pure sugar.
Proof doc: `lab-docs/lang/lab-lang-record-field-punning-p2-v0.md`.

**Implementation:** one branch in `parse_record_or_block`'s field loop — after the field name, if the next
token is not `:`, the value is `Expr::Ref { name }`. The record literal / spread sees the canonical
`{ name: <ref> }`, so **no new node kind** and **zero typechecker/emitter/VM change**. Works for spreads
(`{ ...ctx, todo_id }`) for free (shared field loop). The only file touched is `parser.rs` (+ new test file).

**Verified:** pure/mixed/spread punning compile; missing symbol → `OOF-P1`; extra field → `OOF-TY0` shape
error; dotted punning → parse error; SIR **byte-identical** to the explicit record (test
`punned_record_sir_identical_to_explicit`).

**Proof — all green:** record_field_punning_tests **8**; record_spread 9; app_pressure_scorecard 3;
comprehension 10; igniter-compiler **183/0**; igniter-web **52/0**; `git diff --check` clean.

**Next (optional):** a doc/example-only migration of `todo_handlers.ig`/`todo_views.ig` showcasing punning +
comprehension. Optional-field defaults (the remaining `HtmlNode` verbosity) stay on the canon PROP track.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test record_field_punning_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test record_spread_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test app_pressure_scorecard_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test
git diff --check
```

If the test target name differs, report the actual name.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-record-field-punning-p2-v0.md
```

It must state:

- exact grammar accepted;
- exact desugar rule;
- examples before/after from TodoApp pressure;
- interaction with record spread;
- diagnostics for missing/extra fields;
- closed forms and why;
- SIR/runtime parity claim, if proven;
- exact verification commands and counts.

Update this card with a closing report.

## Closed Scope

- No record defaults.
- No optional fields.
- No dotted/keypath punning.
- No destructuring.
- No new runtime representation.
- No broad TodoApp rewrite.
- No canon claim.
