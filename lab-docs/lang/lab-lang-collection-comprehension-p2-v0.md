# lab-lang-collection-comprehension-p2-v0 — single-generator collection comprehension

**Card:** `LAB-LANG-COLLECTION-COMPREHENSION-P2` · **Delegation:** `OPUS-LANG-COLLECTION-COMPREHENSION-P2`
**Status:** CLOSED (lab implementation-proof) — `[ E for x in C (if P)? ]` works as **pure parse-time sugar**
over the proven `map` / `filter` substrate. **Parser-only** (zero typechecker/emitter/classifier changes),
no new SIR node kind, no runtime semantics, no DB/SQL pushdown, no canon claim.
**Authority:** Lab tooling. Implements `LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1`.

## Grammar implemented

```
ArrayLiteral := '[' ( Comprehension | ExprList ) ']'
Comprehension := Expr 'for' Ident 'in' Expr ( 'if' Expr )?
```

Single generator, optional single `if` filter. Parsed in `parse_array_literal`: parse the first element
`Expr`; if the next token's value is `for`, switch to comprehension mode (item `Ident`, `in`, source `Expr`,
optional `if` predicate, `]`).

## Exact parse-time desugar

```ig
[ E for x in C ]        ⇒  map(C, x -> E)
[ E for x in C if P ]   ⇒  map(filter(C, x -> P), x -> E)
```

Produces ordinary `Expr::Call { fn: "map"/"filter" }` + `Expr::Lambda { params:[x], body: Expr(...) }` AST
nodes — the **exact** nodes a hand-written `map`/`filter` produces. Everything downstream (element-type
inference, lowering, VM) is the already-proven path, untouched.

## Files changed

| File | Change |
|---|---|
| `parser.rs` | `parse_array_literal` rewritten: parse first element, detect `for` (a contextual identifier — it is *not* a keyword token; the FiniteLoop body-decl also matches it by value), then desugar to map/filter; ordinary + empty array literals preserved unchanged. **No other file touched.** |
| `tests/collection_comprehension_tests.rs` | new (10 tests) |

No typechecker, emitter, classifier, or form_resolver change was needed — the comprehension emits existing
node kinds, so there is no new variant to sweep.

## Scope & type rules (verified)

- **Item variable is comprehension-local** — it becomes the lambda parameter. Referencing it outside the
  comprehension fails with `Unresolved symbol` (test `item_var_does_not_leak`).
- **Outer graph nodes are captured** by the element expression / predicate exactly as a lambda body captures
  them (test `outer_node_capture_works` — `concat(prefix, t.title)`); captures become dependency edges.
- **Output type** is `Collection[typeof E]` via existing `map` inference (`x` bound to `C`'s element type).
- **Source order implies no sequencing** — it is a pure expression desugaring to `map`/`filter` graph nodes;
  evaluation follows data dependencies, not text.

## Diagnostics (inherited from map/filter — verified live)

```text
[ x for x in n ]   (n : Integer)        → OOF-TY0 stdlib.collection.map: first argument must be Collection[T], got Integer
[ t.title for t in todos if t.title ]   → OOF-TY0 stdlib.collection.filter: predicate must return Bool, got Text
```

No new diagnostic code was added — the existing `map`/`filter` checks fire on the desugared nodes, which is
exactly the readiness prediction.

## SIR parity evidence

`[ t.title for t in todos if t.done == false ]` and the hand-written
`map(filter(todos, t -> t.done == false), t -> t.title)` produce **byte-identical** `call` + `lambda` nodes
in `semantic_ir_program.json` (test `comprehension_sir_identical_to_explicit_map_filter`). The comprehension
is *exactly* the explicit form.

## Todo / ViewArtifact proof

`[ { tag: t.title, text: t.title } for t in todos if t.done == false ] : Collection[HtmlNode]` compiles
(test `viewartifact_html_node_list_compiles`).

**Ergonomic note (a real win):** the comprehension is *more* expressive than the explicit
`map(…, t -> { … })` here — in the explicit lambda, the `{` after `->` parses as a lambda **block body**, not
a record literal, so `t -> { tag: … }` does not compile. The comprehension forces the element into
expression position and disambiguates it. (For a record-element list, the comprehension is the only clean
surface today.)

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test collection_comprehension_tests → 10 passed
    (no-filter; filter; outer capture; item-scope no-leak; non-collection→reject; non-bool→reject;
     ordinary array; empty array; Collection[HtmlNode]; SIR parity vs explicit map/filter)
$ cd lang/igniter-compiler && cargo test --no-fail-fast                         → 162 passed; 0 failed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests            → 11 passed
$ cd lang/igniter-compiler && cargo test --test string_escapes_tests            → 10 passed
$ cd lang/igniter-compiler && cargo test --test loop_conformance_tests          → 14 passed
$ cd lang/igniter-compiler && cargo test --test match_arm_bindings_tests        → 6 passed
$ cd lang/igniter-compiler && cargo test --test record_spread_tests             → 9 passed
$ cd server/igniter-web    && cargo test --no-fail-fast                         → 52 passed; 0 failed
$ git diff --check                                                              → clean
```

Note: this card's edit is isolated to `parse_array_literal`. The shared working tree also carries concurrent
`LAB-LANG-FALLIBLE-BINDING-P2` (`Expr::Try`) work in the same crate; it compiles and the full suite is green
(162/0). No overlap with the comprehension change.

## Acceptance — mapping

- [x] `[ E for x in C ]` parses + compiles as `map(C, x -> E)`.
- [x] `[ E for x in C if P ]` parses + compiles as `map(filter(C, x -> P), x -> E)`.
- [x] Output type is `Collection[typeof E]`.
- [x] Element variable scoped only inside element expr + predicate (no leak).
- [x] Outer graph nodes captured by element expr/predicate.
- [x] Non-collection source rejected (inherited `map` diagnostic).
- [x] Non-bool predicate rejected (inherited `filter` diagnostic).
- [x] Ordinary + empty array literals still parse unchanged.
- [x] SIR parity with explicit map/filter proven (byte-identical).
- [x] Todo ViewArtifact `Collection[HtmlNode]` list fixture compiles.
- [x] No multiple generators; no local `let`; no effectful iteration / SQL pushdown.
- [x] `lang/igniter-compiler cargo test` green (162/0); `server/igniter-web` green (52/0).
- [x] `git diff --check` clean.

## Deferred / non-goals (honored)

No multiple generators; no local `let` inside the comprehension; no `flat_map`/grouping; no effectful loops;
no SQL/DB pushdown; no fallible `?` interaction; no signature-bound change; no canon claim. A helper-contract
element (`[ TodoLabel(t) for t in todos ]`) needs module-resolved contract calls (orthogonal to the
comprehension) — that integration is a follow-on in the igweb authoring stack.

## Next

Use the comprehension to simplify one live Todo/ViewArtifact list-authoring fixture, then reassess whether
multi-generator or local-`let` pressure is real.

---

*Lab implementation-proof. Compiled 2026-06-21; igniter-compiler 162/0 (incl. 10 new), igweb lowering 11,
string_escapes 10, loop_conformance 14, match_arm 6, record_spread 9, igniter-web 52/0; `git diff --check`
clean. Comprehension is parser-only pure sugar — byte-identical to explicit map/filter, no new SIR node kind,
no authority.*
