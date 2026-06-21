# lab-lang-collection-comprehension-readiness-p1-v0 — readable map/filter surface

**Card:** `LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1` · **Delegation:** `OPUS-LANG-COLLECTION-COMPREHENSION-P1`
**Status:** CLOSED (readiness/design — **no implementation**). Recommends a single-generator comprehension
`[ E for x in C (if P)? ]` that desugars at parse time to existing `map` / `filter` + lambda nodes. No new
SIR node kind, no new runtime semantics, no lexer change, no canon claim.
**Authority:** Lab tooling design.

## Live findings (verified)

| Area | Finding |
|---|---|
| `map` / `filter` strength | **Strong, proven substrate.** Recognized collection-producing builtins (`typechecker.rs:3664-3676`: `split/range/filter/map/flat_map/zip/take/concat`). Used live across `todo_view_app_tests`, `relational_todo_tests`, `render_html_app_tests`, and the ViewArtifact proofs `list-authoring-p21`, `conditional-lists-p22`, `select-options-p23`. |
| element-type inference | Real: `collection_elem_hints` + `LAB-TC-ARRAY-P1/P2` element-type pre-scan; a lambda param binds the source's element type (`body_symbol_types["item"]`). `map(C, x->E)` infers `Collection[typeof E]`. |
| `for` keyword | **Reserved at body-decl position only** — `for Name item in source { … }` is the FiniteLoop decl (G3b, `parser.rs:1955`). A comprehension `for` sits **inside `[ … ]`** (expression position). Different productions → **no conflict**. |
| `in` keyword | Already a contextual keyword in the FiniteLoop header; the comprehension reuses `for … in …` in the same spirit. |
| lexing | Keywords/idents are matched **by value** in the parser (`Keyword`/`Ident` token carries its string). So `for`/`in`/`if` need **no lexer change** — they're recognized contextually inside the array parser. |
| array literal parser | `parse_array_literal` (`parser.rs:3683`) is a clean `while` loop of `parse_expr` items → the single, isolated interception point for a comprehension. |
| lambda capture | Lambdas already capture outer graph nodes (their ref-collection excludes the lambda param and records outer refs as dependency edges). The comprehension inherits this unchanged. |

## Grammar proposed (v0)

```
ArrayLiteral := '[' ( Comprehension | ExprList ) ']'
Comprehension := Expr 'for' Ident 'in' Expr ( 'if' Expr )?
```

- **One generator**, optional single `if` filter.
- Parsed in `parse_array_literal`: parse the first element `Expr`; if the next token's value is `for`,
  switch to comprehension mode (consume `for`, read the item `Ident`, expect `in`, parse the source `Expr`,
  optionally `if` + predicate `Expr`, expect `]`).

## Desugar (parse-time AST → AST)

```ig
[ E for x in C ]        ⇒  map(C, x -> E)
[ E for x in C if P ]   ⇒  map(filter(C, x -> P), x -> E)
```

Produces ordinary `Call(map)` / `Call(filter)` + `Lambda` AST nodes — **no new node kind**. Everything
downstream (typing, element inference, emitter lowering, VM) is the **already-proven map/filter path**.
Recommended point: desugar **at parse time** in `parse_array_literal` (cheapest — zero new typecheck/emit
code; diagnostics fall out of the existing map/filter checks).

## Answers to the 11 required questions

1. **Useful beyond map/filter?** Yes — `map(filter(todos, t -> t.done == false), t -> TodoLabel(t))` reads
   **inside-out**; the comprehension reads in declaration order (output first, source, filter). The win is
   real for `Collection[HtmlNode]` view rows and relational rows. It is **strictly optional sugar** — the
   stdlib path stays.
2. **Is map/filter a strong enough substrate?** **Yes** (see live findings — proven, not proposal).
3. **Exact grammar?** `[ Expr for Ident in Expr ( if Expr )? ]` (above).
4. **Filters in v0?** **Yes** — optional single `if`.
5. **Multiple generators in v0?** **No.** Single generator keeps the desugar 1:1 with `map`/`filter` (no
   `flat_map`/cartesian product). Live code does not make multi-generator trivial.
6. **Element variable scope?** The `Ident` is bound **only** inside the element `Expr` and the predicate —
   it becomes the lambda parameter. Block-local, does not leak; identical to writing `x -> …` today.
7. **Capture of outer graph nodes?** Unchanged from lambdas: the element/predicate may reference inputs and
   other compute nodes; those become dependency edges via the existing lambda ref-collection. No new capture
   mechanism.
8. **Output `Collection[T]` inference?** From the desugar: `map(C, x -> E)` ⇒ `Collection[typeof E]`, with
   `x` bound to `C`'s element type. Reuses existing map inference — **no new type machinery**.
9. **Does source order imply sequencing?** **No — and it must not.** The comprehension is a pure expression
   desugaring to `map`/`filter` graph nodes. Textual order is presentation only; evaluation follows the
   graph's data dependencies, element-wise and pure, exactly as `map`/`filter` already guarantee. The
   comprehension introduces **zero** iteration-order semantics.
10. **Diagnostics?**
    - source after `in` not a `Collection` → `OOF-C1: comprehension source must be a Collection` (in
      practice falls out of the existing `map`/`filter` collection check).
    - `if` predicate not `Bool` → `OOF-C2: comprehension filter must be Bool` (falls out of `filter`'s
      predicate check).
    - malformed header (missing `in`, missing source/`]`) → parse error.
11. **Implementation slice?** `LAB-LANG-COLLECTION-COMPREHENSION-P2` (below).

## Scope & type rules (concrete)

- exactly one generator; `Ident` is fresh and lambda-scoped; shadowing an outer name is allowed (lambda
  param semantics) and warned only if existing lambda rules warn.
- `C : Collection[U]` ⇒ `x : U`; predicate `P : Bool`; result `Collection[typeof E]`.
- purity: the comprehension is pure iff `E` and `P` are pure (they are lambda bodies — same rule as today).

## Examples (ViewArtifact / Todo)

```ig
-- before (inside-out)
body : Collection[HtmlNode] = map(filter(todos, t -> t.done == false), t -> TodoLabel(t))

-- after (declaration order)
body : Collection[HtmlNode] = [ TodoLabel(t) for t in todos if t.done == false ]

-- relational rows
rows : Collection[Row] = [ Row { id: c.id, name: c.name } for c in companies ]
```

## Alternatives compared

| Option | Readability | New surface | Reuse | Verdict |
|---|---|---|---|---|
| explicit `map`/`filter` | inside-out | none | full | keep as substrate |
| helper contract (`TodoLabels(todos)`) | good, but one per shape | none | full | fine for reuse, boilerplate per shape |
| **comprehension** | **best, in-order** | thin parse-sugar | **full (desugars to map/filter)** | **recommended** |

The comprehension is the cheapest readability win because it is *only* a parser rewrite — it adds no
typechecker, emitter, or VM surface.

## Implementation test matrix (for P2)

| Case | Expectation |
|---|---|
| `[ E for x in C ]` | desugars to `map(C, x->E)`; `Collection[typeof E]` |
| `[ E for x in C if P ]` | desugars to `map(filter(C, x->P), x->E)` |
| element expr references outer node | captured as dependency edge (lambda capture) |
| `x` not visible outside the comprehension | scope test (out-of-scope ref → unresolved) |
| source not a Collection | `OOF-C1` |
| `if` predicate not Bool | `OOF-C2` |
| empty / malformed header | parse error |
| ordinary array literal still parses | no regression (`[ a, b, c ]`) |
| serialization parity | comprehension SIR byte-identical to hand-written `map`/`filter` |
| Todo ViewArtifact `Collection[HtmlNode]` fixture | renders identically to the explicit form |

## Non-goals

No implementation; no multiple generators; no local `let` inside the comprehension; no grouping/`flat_map`;
no async/effectful iteration; no SQL/DB pushdown; no mutation/accumulation; no signature-bound or fallible
`?` interaction; no canon claim.

## Recommendation

**Proceed.** Clean, conflict-free, parser-only, riding entirely on the proven `map`/`filter`/lambda
substrate. Open `LAB-LANG-COLLECTION-COMPREHENSION-P2`: parse-time desugar of `[ E for x in C (if P)? ]`,
the two diagnostics, the test matrix above, with one pure collection fixture and one Todo ViewArtifact
`Collection[HtmlNode]` fixture (+ serialization parity vs explicit map/filter).

---

*Readiness/design only — verified against live lexer/parser/typechecker (2026-06-20). `for`/`in`/`if` are
contextual (no lexer change); `for`-as-FiniteLoop is a body-decl production and does not conflict with
`for` inside `[ … ]`. v0 = single generator + optional filter, pure parse-sugar to `map`/`filter`. Next:
LAB-LANG-COLLECTION-COMPREHENSION-P2.*
