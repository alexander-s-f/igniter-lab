# LAB-LANG-RECORD-ERGONOMICS-READINESS-P1 - Optional fields, spread, and partial record pressure

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: readiness / design
Delegation code: OPUS-LANG-RECORD-ERGONOMICS-P1
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

Typed records worked well for relational intents and ViewArtifact authoring, but app code became verbose
when a record type had many fields and each node used only a subset. P20 helper contracts reduced the pain,
but repeated helper boilerplate across apps would be a sign that the language surface needs better record
ergonomics.

Examples of live pressure:

- `HtmlNode` flat record needs default-like fields for kinds that do not use them;
- `ViewArtifact` / form authoring benefits from small partial values;
- relational `QueryPlan` / `WriteIntent` can become noisy when optional policy fields are added;
- record spread could express "copy this context and add one field" for accumulation.

This card should decide what belongs in language sugar vs app-local helpers.

## Goal

Design the smallest record-ergonomics direction that improves application authoring while preserving
deterministic record values and graph lowering.

Candidates:

- optional fields with defaults;
- partial record literals checked against expected type;
- record spread / update syntax;
- helper contracts as the blessed v0 instead of syntax.

## Verify First

Read live surfaces:

- `lang/igniter-compiler/src/parser.rs` record literal parsing
- `lang/igniter-compiler/src/typechecker.rs` record typing / missing-field diagnostics
- `lang/igniter-compiler/tests/fixtures` with record literals, nested records, collection of records
- `server/igniter-web/examples/todo_view_app/todo_views.ig`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- relational proof docs:
  - `lab-docs/lang/lab-igniter-relational-contracts-todo-p2-v0.md`
  - `lab-docs/lang/lab-igniter-relational-queryplan-bridge-p3-v0.md`
- ViewArtifact proof docs P18-P23 if present.
- proposal files for optional fields, partial records, record spread, schema evolution.

Confirm or correct:

- whether every record field is currently required;
- whether field order matters in parser/typechecker/VM serialization;
- whether missing-field diagnostics are useful enough;
- whether extra fields are rejected or ignored;
- whether record values serialize without variant tags;
- whether app-local helper contracts already solve most pressure.

## Alternatives To Compare

### A. Optional fields with type-level defaults

```ig
type HtmlNode {
  kind : String
  text? : String = ""
  options? : Collection[String] = []
}
```

Powerful but touches type declarations and defaults.

### B. Partial record literals under expected type

```ig
compute n : HtmlNode = { kind: "label", text: "Hello" }
```

Typechecker fills known defaults. Requires a default story.

### C. Record spread / update

```ig
compute enriched : Ctx = { ...ctx, todo_id: todo_id }
```

Excellent for accumulation/context, but not enough for missing defaults by itself.

### D. App-local helper contracts only

Current proven path. Keep as baseline; promote syntax only if two apps repeat the same helpers.

### E. Separate specialized view node variants

Avoids optional fields but may reintroduce `__arm`/variant serialization mismatch with current renderer.

## Required Questions

Answer directly:

1. Which record pain is actually blocking vs merely verbose?
2. Which proposal(s) already cover the desired shape?
3. Do optional fields need defaults, `Option[T]`, or both?
4. How does record spread interact with immutability and graph lowering?
5. How are diagnostics kept clear for missing/extra fields?
6. Does this help ViewArtifact only, or also relational/context accumulation?
7. Is the first implementation slice optional fields, spread, or no syntax yet?
8. What tests prove VM serialization remains stable?
9. What should stay app-local until repeated by a second app?
10. What is the smallest follow-up implementation card?

## Required Deliverable

Create:

```text
lab-docs/lang/lab-lang-record-ergonomics-readiness-p1-v0.md
```

It must include:

- live record behavior summary;
- proposal crosswalk;
- alternative comparison;
- recommended first slice;
- test matrix;
- non-goals.

Update this card with a closing report.

## Closed Scope

- No implementation.
- No renderer changes.
- No ViewArtifact schema changes unless only used as pressure evidence.
- No relational schema/migration work.
- No user-generic type design unless needed for the comparison.
- No canon claim.

## Suggested Next

If readiness finds repeated pressure, open one narrow implementation card:

- `LAB-LANG-RECORD-SPREAD-P2`, or
- `LAB-LANG-OPTIONAL-FIELDS-P2`, or
- keep helper contracts as the v0 and wait for a second app.

---

## Closing Report (2026-06-20)

**Deliverable:** `lab-docs/lang/lab-lang-record-ergonomics-readiness-p1-v0.md` — readiness/design, **no
code**. Answers Q1–Q10 with live behavior, proposal crosswalk, alternative comparison, the spread design,
a test matrix, and non-goals.

**Two pains, split by where they belong:**
1. **Default-field noise** (P19/P23 flat `HtmlNode`; `OOF-TY0: required field 'options' is missing`) → wants
   optional fields with defaults. **CANON-GATED:** `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1` *explicitly
   defers* implementation pending a full PROP, because omission semantics (absent-field meaning at
   construction/access/serialization) is **semantic authority**, not surface sugar. The lab lane must not
   jump that gate; v0 stays **helper contracts** (canon's own "safe app pattern"). Lab role = feed P19/P23
   evidence to that PROP.
2. **Context accumulation** (`{ ...ctx, f: v }`) → **record spread** — semantically clean (pure
   copy+override, no omission question), **untracked** by canon, with **strong real-app evidence**:
   lead_router hand-writes **six** `CtxWith*` contracts that ARE spreads. → the recommended lab slice.

**Recommended slice: `LAB-LANG-RECORD-SPREAD-P2`** — `{ ...base, f: v }` **desugars to an explicit
field-by-field record literal** (`{ a: ctx.a, …, f: v }`) when the source type is known → lowers to the
**same SIR node kind**, byte-identical, pure/immutable, no new authority (fits P0 exactly). Overrides
validated via the existing `check_record_literal_shape` (`OOF-TY0`). Rewrites the lead_router `CtxWith*`
boilerplate.

**Deferred / app-local:** optional & partial-record fields (canon PROP); helper contracts remain v0 for the
default-field pain.

**Verified live:** all record fields required (P23); fields are keyed not positional; records serialize
tagless; `?` parses but is erased before validation (canon proof); lead_router 6× `CtxWith*` accumulation.

**Next:** `LAB-LANG-RECORD-SPREAD-P2` (implementation) + a non-code action to attach P19/P23 evidence to the
canon `LANG-OPTIONAL-FIELD-PARTIAL-RECORD` PROP. This concludes the P0 lane's first readiness trio
(escapes ✅ shipped, match-arm bindings → P2, record spread → P2).
