# lab-lang-loop-ir-conformance-recovery-p1-v0 — PROP-039 loop SemanticIR conformance recovery

**Card:** `LAB-LANG-LOOP-IR-CONFORMANCE-RECOVERY-P1` · **Delegation:** `OPUS-LANG-LOOP-IR-CONFORMANCE-P1`
**Status:** CLOSED (lab recovery) — `loop_conformance_tests` is green (14/14) and the **full
`igniter-compiler` suite is green**. **The fix was test-source-only (4 stale loop bodies); no
emitter/typechecker/parser/lexer change.**
**Authority:** Lab. The emitter's `loop_node` shape was already correct; the failures were stale test
inputs against accepted PROP-039 gate-8 rules.

## Root cause — NOT an emitter bug (the card's hypothesis was wrong, as it anticipated)

The card hypothesized the emitter drops loop nodes or emits old `kind:"loop"`. **Live evidence disproves
that.** The real chain:

1. `emitter::emit_typed` sets `semantic_ir = Some(...)` **only if `typed.type_errors.is_empty()`**
   (`emitter.rs:32-38`). Any type error ⇒ `semantic_ir = None`.
2. All 4 failing tests used a loop body that **mutates outer state**:
   `compute total = total + item`. That fires **OOF-L7** ("body compute in loop '…' targets outer
   contract symbol 'total' — outer state is read-only", `typechecker.rs:1291-1293`).
3. OOF-L7 is a type error ⇒ `ok=false` ⇒ `semantic_ir = None` ⇒ `loop_nodes_from_emit` returns empty ⇒
   all 4 tests fail with "Expected loop_node in SemanticIR" (and `test_ir_kind_is_loop_node_not_loop`
   panics on `semantic_ir.expect(...)` because it is `None`).

So the loop node was never "lost" by the emitter — **no SemanticIR was produced at all**, because the
test sources violate the loop body rules.

### Layer characterization (parser / classifier / typechecker / emitter)

- **Parser** — correct. `for`/`loop` parse into loop body decls; `lead name: Type = literal` parses via
  `parse_lead_decl` (`parser.rs:2313`). The 10 always-green OOF/parser tests confirm parsing.
- **Classifier** — correct. Sets `loop_class` ("finite"/"budgeted"), `item`, `max_steps` options
  (`classifier.rs:1088-1190`).
- **Typechecker** — correct and **intentionally strict** (PROP-039 gate 8, `typechecker.rs:1100,1209-1307`):
  a loop body `compute` may target **only a declared `lead`** binding (loop-local accumulator initialised
  to a static literal). Targeting the loop item or outer state → **OOF-L7**; targeting an undeclared
  symbol → **OOF-L5**. This is the accepted dataflow-purity model (accumulation is a `lead`, not outer
  mutation).
- **Emitter** — **already correct**. `typed_node` dispatches `kind=="loop"` → `loop_node` (`emitter.rs:825,2412`),
  which emits `kind:"loop_node"`, `loop_class`, `termination` (`collection_exhaustion`/`budget_exhaustion`),
  `source_ref`, `item`, and top-level `max_steps` (budgeted). It runs correctly **once the source compiles
  clean**.

**Responsible layer: none — the test SOURCES were stale** against the implemented gate-8 (`OOF-L5/L7` +
`lead`). Exactly the "assertions/inputs stale rather than emitter behaviour" case the card flagged.

## The fix (test inputs only)

Each failing test's loop body was rewritten from outer-state mutation to a `lead` accumulator:

```diff
-  for Scan item in items {
-    compute total = total + item
-  }
+  for Scan item in items {
+    lead acc: Integer = 0
+    compute acc = acc + item
+  }
```

Applied to all 4 (`for ProcessAll`, `for Scan`, `loop Process … max_steps:50`, `loop DoLoop … max_steps:10`).
The test **assertions are unchanged** (they still demand the full `loop_node` shape); only the inputs were
corrected to be OOF-L5/L7-clean so the emitter is actually reached. No rule was weakened, no test renamed,
no emitter/typechecker/parser/lexer touched.

## Before / after SemanticIR

- **Before:** source has OOF-L7 → `emit_res.semantic_ir == None` → 0 loop nodes.
- **After (finite `for`):** `{ "kind":"loop_node", "loop_class":"finite", "termination":"collection_exhaustion",
  "source_ref":"items", "item":"item" }` (no `max_steps`).
- **After (budgeted `loop … max_steps:50`):** `{ "kind":"loop_node", "loop_class":"budgeted",
  "termination":"budget_exhaustion", "source_ref":"nums", "max_steps":50 }`.
- No `kind:"loop"` anywhere (regression test green).

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test loop_conformance_tests
  → 14 passed; 0 failed   (was 10 passed; 4 failed)
$ cd lang/igniter-compiler && cargo test
  → full suite GREEN — no failing binary (lib 55, loop 14, + all others 0 failed)
$ git diff --check   → clean
  changed: lang/igniter-compiler/tests/loop_conformance_tests.rs (+8 / -4) — ONLY file
```

The 4 previously-failing tests now pass: `test_finite_loop_parses_successfully`, `test_finite_loop_ir_shape`,
`test_budgeted_loop_ir_shape`, `test_ir_kind_is_loop_node_not_loop`. The 10 OOF/parser tests stay green.
No `string_escapes`/lexer files touched (parallel `LAB-LANG-STRING-ESCAPES-P1` unaffected).

## Acceptance — mapping

- [x] `loop_conformance_tests` focused run green (14/14).
- [x] Finite `for` emits `kind:"loop_node"`, `loop_class:"finite"`, `termination:"collection_exhaustion"`, `source_ref`.
- [x] Budgeted `loop … max_steps:N` emits `loop_node`, `loop_class:"budgeted"`, `max_steps`.
- [x] No old `kind:"loop"` in SemanticIR.
- [x] Existing OOF loop tests remain green.
- [x] No lexer/string-escape, IgWeb, Todo, or renderer files modified (only the test file).
- [x] `git diff --check` clean.

## Deferred — PROP-039 lab↔canon question (out of scope here)

A genuine divergence surfaced and is **flagged, not resolved** (the card forbids PROP-039 redesign):

- The current Rust typechecker requires the **`lead` accumulator** model (outer state read-only in loop
  bodies — OOF-L7).
- But the canon-target fixture `fixtures/loops/loop_accumulator.ig` still uses outer-state accumulation
  (`compute total = total + item`) and carries the header *"Conformance note: Rust compiler update needed
  to accept canon syntax"*.

So there is an open question of which is the intended canon loop-body shape: `lead`-only (current Rust) vs
outer-state accumulation (the fixture's target). This recovery card aligns the **tests** with the
**implemented** behaviour and does not decide the canon question — a separate PROP-039 reconciliation
card should. (`fixtures/loops/loop_accumulator.ig` is a known canon-target fixture, not part of the
green suite, and was left untouched.)

## Closed scope (honored)

No string-escape change; no IgWeb/Todo/view/render change; no VM runtime loop execution; no
recursion/fuel expansion; no new loop syntax; no PROP-039 redesign; no emitter/typechecker/parser change;
no canon claim. Test inputs only.

---

*Lab recovery. Compiled 2026-06-20; `loop_conformance_tests` 14/14, full `igniter-compiler` suite green,
`git diff --check` clean, one file changed. Root cause = stale test loop bodies violating accepted
OOF-L5/L7 (`lead`-accumulator) rules — emitter `loop_node` shape was already correct.*
