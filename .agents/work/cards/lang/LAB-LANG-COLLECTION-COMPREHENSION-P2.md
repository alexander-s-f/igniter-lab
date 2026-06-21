# LAB-LANG-COLLECTION-COMPREHENSION-P2 - Single-generator collection comprehension

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: implementation-proof
Delegation code: OPUS-LANG-COLLECTION-COMPREHENSION-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1` recommends a single-generator collection comprehension
that desugars to the proven `map` / `filter` substrate.

Candidate:

```ig
[ TodoLabel(t) for t in todos if t.done == false ]
```

Desugar:

```ig
map(filter(todos, t -> t.done == false), t -> TodoLabel(t))
```

No new SIR node kind; no runtime semantics; no DB/SQL pushdown.

## Goal

Implement v0:

```ig
[ Expr for item in collection ]
[ Expr for item in collection if predicate ]
```

as parser-time sugar over existing `map` / `filter` / lambda AST.

## Verify First

Read live code before editing:

- `lang/igniter-compiler/src/parser.rs`
  - `parse_array_literal`;
  - lambda parsing;
  - contextual keyword handling for `for`, `in`, `if`;
- `lang/igniter-compiler/src/typechecker.rs`
  - `map` / `filter` builtin typing;
  - lambda parameter element inference;
  - collection diagnostics;
- `lang/igniter-compiler/src/emitter.rs`
  - map/filter/lambda lowering;
- `lang/igniter-compiler/src/classifier.rs` / `form_resolver.rs`
  - expression refs/call/exhaustiveness if a marker node is introduced;
- Todo/ViewArtifact fixtures that build `Collection[HtmlNode]`;
- readiness packet:
  - `lab-docs/lang/lab-lang-collection-comprehension-readiness-p1-v0.md`.

Confirm or correct:

- whether parse-time desugar avoids any typechecker/emitter changes;
- whether ordinary array literals remain unchanged;
- whether the first expression can be parsed before seeing `for` without ambiguity;
- exact diagnostics inherited from `map` / `filter`;
- whether source variable scoping matches lambda scoping.

Live code wins over this card.

## Recommended Implementation Shape

Prefer parser-only desugar:

1. In `parse_array_literal`, parse first `Expr`.
2. If next token value is `for`, parse:
   - item identifier;
   - `in`;
   - source expression;
   - optional `if` predicate;
   - closing `]`.
3. Build ordinary AST:
   - no filter: `map(source, item -> element_expr)`;
   - filter: `map(filter(source, item -> predicate), item -> element_expr)`.

Do not add a `Comprehension` SIR or runtime form unless parse-time desugar proves impossible.

## Required Acceptance

- [x] `[ E for x in C ]` parses and compiles as `map(C, x -> E)`.
- [x] `[ E for x in C if P ]` parses and compiles as `map(filter(C, x -> P), x -> E)`.
- [x] Output type is `Collection[typeof E]`.
- [x] Element variable is scoped only inside element expression and predicate (no leak).
- [x] Outer graph nodes can be captured by element expression/predicate.
- [x] Non-collection source is rejected (inherited `map` diagnostic).
- [x] Non-bool predicate is rejected (inherited `filter` diagnostic).
- [x] Ordinary + empty array literals still parse unchanged.
- [x] Serialization/SIR parity with explicit map/filter proven (byte-identical call/lambda nodes).
- [x] Todo ViewArtifact `Collection[HtmlNode]` list fixture compiles.
- [x] No multiple generators.
- [x] No local `let` inside comprehension.
- [x] No effectful iteration or SQL pushdown.
- [x] `lang/igniter-compiler cargo test` green (162/0).
- [x] `server/igniter-web cargo test` green (52/0).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Outcome:** single-generator comprehension `[ E for x in C (if P)? ]` implemented as **parser-only** pure
sugar. Proof doc: `lab-docs/lang/lab-lang-collection-comprehension-p2-v0.md`.

**Implementation:** `parse_array_literal` (the *only* file touched in this card) parses the first element,
detects `for` (a contextual identifier, not a keyword token), then desugars at parse time:
`[E for x in C]` → `map(C, x->E)`; `[E for x in C if P]` → `map(filter(C, x->P), x->E)`. Produces existing
`Call`/`Lambda` nodes → **no new SIR node kind, and zero typechecker/emitter/classifier changes** (no variant
to sweep). Diagnostics (non-collection source, non-bool predicate) are inherited from `map`/`filter`.

**Verified:** item var is lambda-scoped (no leak → `Unresolved symbol`); outer capture works; output
`Collection[typeof E]`; SIR **byte-identical** to explicit `map(filter(...))`; `Collection[HtmlNode]`
record-element list compiles. **Ergonomic bonus:** the comprehension is *more* expressive than explicit
`map(…, t -> { … })`, whose `{` after `->` parses as a lambda block, not a record — the comprehension is the
only clean record-element list surface today.

**Proof — all green:** collection_comprehension_tests **10**; igniter-compiler **162/0**; igweb lowering 11;
string_escapes 10; loop_conformance 14; match_arm 6; record_spread 9; igniter-web **52/0**; `git diff --check`
clean.

**Coordination note:** mid-card, a concurrent agent's `LAB-LANG-FALLIBLE-BINDING-P2` (`Expr::Try`) work
landed in the same crate (shared tree). It briefly red the build during its own exhaustiveness sweep, then
went green; my change is isolated to `parse_array_literal` with no overlap. Full suite green with both
present.

**Next:** simplify one live Todo/ViewArtifact list fixture with the comprehension; reassess multi-generator /
local-`let` pressure.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-collection-comprehension-p2-v0.md
```

It must include:

- exact grammar implemented;
- exact parse-time desugar;
- files changed;
- scope/type rules;
- diagnostics examples;
- SIR parity evidence;
- Todo/ViewArtifact proof;
- exact test commands and counts;
- what remains deferred.

Update this card with a closing report.

## Closed Scope

- No multiple generators.
- No local `let` inside comprehension.
- No `flat_map` / grouping.
- No effectful loops.
- No SQL/DB pushdown.
- No fallible `?` interaction.
- No signature-bound contract changes.
- No canon claim.

## Suggested Next

If P2 lands, use it to simplify one Todo/ViewArtifact list authoring fixture and then reassess whether
multi-generator or local-let pressure is real.
