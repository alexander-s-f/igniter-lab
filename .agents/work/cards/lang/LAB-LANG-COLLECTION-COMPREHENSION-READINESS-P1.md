# LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1 - Readable map/filter surface for app lists

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: readiness / design
Delegation code: OPUS-LANG-COLLECTION-COMPREHENSION-P1
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

ViewArtifact authoring and Todo list rendering now hit the common app pattern:

```ig
map(filter(todos, t -> t.done == false), t -> TodoLabel(t))
```

The stdlib route is explicit and good as a substrate, but it reads inside-out. A comprehension-like surface
could make list rendering and relational rows easier to author while lowering to existing `map` / `filter`.

Candidate:

```ig
body : Collection[HtmlNode] = [ TodoLabel(t) for t in todos if t.done == false ]
```

This card is readiness only. Do not mix it into signature-bound surface or fallible `?` work.

## Goal

Decide whether Igniter should support a collection comprehension surface, and define the smallest v0 shape
that desugars to existing collection functions without new runtime semantics.

## Verify First

Read live surfaces:

- `lang/igniter-compiler/src/parser.rs`
  - collection literals;
  - lambdas;
  - `for` / `if` token usage if any;
- `lang/igniter-compiler/src/typechecker.rs`
  - `Collection[T]`;
  - lambda typing;
  - `map`, `filter`, or compiler-builtins for collection stdlib;
- `lang/igniter-compiler/src/emitter.rs` for collection/lambda lowering;
- stdlib docs/tests:
  - collection append/concat/map/filter proposals or cards;
  - live tests for `map` and `filter`;
- ViewArtifact/Todo app files that build `Collection[HtmlNode]`;
- `LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-READINESS-P1.md`.

Confirm or correct:

- whether `map`/`filter` are fully implemented or only proposal/local proof;
- whether lambdas capture local names correctly;
- whether collection literals with call_contract/helper calls already typecheck;
- whether `for` is a free keyword or conflicts with loop syntax;
- whether comprehension should support one generator only in v0.

## Candidate v0

One generator, optional filter:

```ig
[ Expr for item in collection ]
[ Expr for item in collection if predicate ]
```

Desugar:

```ig
map(collection, item -> Expr)
map(filter(collection, item -> predicate), item -> Expr)
```

Out of v0:

- multiple generators;
- local `let` inside comprehension;
- grouping/flatMap;
- async/effectful iteration;
- SQL/DB pushdown;
- mutation/accumulation.

## Required Questions

Answer directly:

1. Is comprehension useful enough beyond `map` / `filter` helpers?
2. Is `map` / `filter` implemented strongly enough to be the substrate?
3. What exact grammar is proposed?
4. Does v0 support filters?
5. Does v0 support multiple generators? Default answer should be no unless live code makes it trivial.
6. How are element variable scopes handled?
7. How does capture of outer graph nodes work?
8. How does type inference determine output `Collection[T]`?
9. Does source order imply sequencing? It must not.
10. What diagnostics are needed for non-collection input or non-bool filter?
11. What implementation slice follows readiness?

## Required Deliverable

Create:

```text
lab-docs/lang/lab-lang-collection-comprehension-readiness-p1-v0.md
```

It must include:

- live stdlib/compiler support findings;
- grammar proposal;
- desugar to `map` / `filter`;
- scope and type rules;
- examples for ViewArtifact/Todo list rendering;
- alternative comparison against helper contracts and explicit `map/filter`;
- implementation test matrix;
- non-goals.

Update this card with a closing report.

## Closed Scope

- No implementation.
- No signature-bound contract changes.
- No fallible `?` propagation.
- No DB/SQL pushdown.
- No effectful loops.
- No canon claim.

## Suggested Next

If readiness lands cleanly, open `LAB-LANG-COLLECTION-COMPREHENSION-P2` with one pure collection fixture and
one Todo ViewArtifact list fixture.

---

## Closing Report (2026-06-20)

**Outcome: PROCEED.** Deliverable: `lab-docs/lang/lab-lang-collection-comprehension-readiness-p1-v0.md`
(all 11 required questions answered against live code).

**Headline findings (verified):**
- `map`/`filter` are a **strong, proven substrate** — collection-producing builtins with real element-type
  inference (`collection_elem_hints`, LAB-TC-ARRAY-P1/P2, lambda param ← element type), used live across
  `todo_view_app_tests`, `relational_todo_tests`, `render_html_app_tests`, and the ViewArtifact proofs
  (list-authoring-p21, conditional-lists-p22, select-options-p23).
- **No `for` conflict:** `for Name item in source { … }` is a body-decl FiniteLoop (G3b, `parser.rs:1955`);
  a comprehension `for` lives **inside `[ … ]`** (expression position). `for`/`in`/`if` are matched
  contextually by value → **no lexer change**.
- `parse_array_literal` (`parser.rs:3683`) is the single isolated interception point.

**Design decisions:**
- Grammar `[ Expr for Ident in Expr ( if Expr )? ]` — **single generator + optional filter**.
- **Pure parse-time desugar:** `[E for x in C]` → `map(C, x->E)`; `[E for x in C if P]` →
  `map(filter(C, x->P), x->E)`. **No new SIR node kind**, no new typecheck/emit code (rides the proven
  map/filter/lambda path); the two diagnostics (`OOF-C1` non-collection source, `OOF-C2` non-bool filter)
  largely fall out of existing map/filter checks.
- Item var = lambda param (block-local, no leak); capture of outer nodes = existing lambda capture; output
  `Collection[typeof E]` via existing map inference; **source order implies NO sequencing** (graph data
  dependencies only).
- v0 non-goals honored: no multiple generators, no local `let`, no flat_map/grouping, no effectful
  iteration, no SQL pushdown.

**No code changed** (readiness). **Next:** `LAB-LANG-COLLECTION-COMPREHENSION-P2` — parse-time desugar +
2 diagnostics + test matrix, with one pure collection fixture and one Todo ViewArtifact
`Collection[HtmlNode]` fixture (+ serialization parity vs explicit map/filter).
