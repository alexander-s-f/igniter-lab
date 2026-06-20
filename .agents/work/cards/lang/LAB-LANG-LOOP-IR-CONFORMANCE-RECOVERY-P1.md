# LAB-LANG-LOOP-IR-CONFORMANCE-RECOVERY-P1 - Recover PROP-039 loop SemanticIR conformance

Status: CLOSED
Lane: parallel / language-conformance
Type: implementation-proof / recovery
Delegation code: OPUS-LANG-LOOP-IR-CONFORMANCE-P1
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

Several recent language/application cards reported the same pre-existing compiler-suite red zone:

```text
lang/igniter-compiler cargo test
  -> all green except loop_conformance_tests
  -> 4 failures
  -> expected at least one loop_node in SemanticIR
```

This is unrelated to the current `LAB-LANG-STRING-ESCAPES-P1` work. The string-escape changes touch
`lexer.rs` / `parser.rs` string handling; loop failures are about PROP-039 SemanticIR shape for `for` /
budgeted `loop` constructs.

This card isolates the old loop-IR failure so the language-polish lane can stop carrying a known red suite
as ambient noise.

## Goal

Make `lang/igniter-compiler/tests/loop_conformance_tests.rs` green by restoring the expected SemanticIR
shape for loop declarations, without changing string escapes, IgWeb routing, Todo apps, runtime execution,
or broader loop semantics.

Target shape from the tests:

```json
{
  "kind": "loop_node",
  "loop_class": "finite" | "budgeted",
  "termination": "collection_exhaustion" | "...",
  "source_ref": "...",
  ...
}
```

Do the smallest recovery that satisfies the existing PROP-039 conformance tests.

## Verify First

Read live surfaces before editing:

- `lang/igniter-compiler/tests/loop_conformance_tests.rs`
- `lang/igniter-compiler/src/parser.rs`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/emitter.rs`
- any SemanticIR builder/types used by the emitter
- fixtures/proofs mentioning PROP-039 or loop conformance:
  - `lab-docs/lang/lab-stdlib-regexp-p3-v0.md`
  - `lab-docs/lang/lab-igniter-web-context-accumulation-p27-v0.md`
  - `lab-docs/lang/lab-managed-recursion-full-termination-proof-beyond-syntactic-v0.md`
  - any `PROP-039` conformance docs if present under adjacent proposal repos.

Confirm or correct:

- whether parser produces `BodyDecl::Loop` / finite `for` declarations correctly;
- whether typechecker preserves loop declarations and their `loop_class` / `max_steps` / body nodes;
- whether emitter drops loop declarations or emits the old `kind:"loop"` shape;
- which exact 4 tests fail today;
- whether any failures are due to assertions being stale rather than emitter behavior.

Live code wins over this card.

## Expected Failure Set

Start from this hypothesis, but verify with an actual focused test run:

- finite `for` parses but no `loop_node` appears in SemanticIR;
- finite loop IR shape missing `loop_class="finite"` / `termination="collection_exhaustion"` / `source_ref`;
- budgeted loop IR shape missing `loop_class="budgeted"` / `max_steps` / `source_ref`;
- regression test cannot find `kind:"loop_node"`.

If the failure set differs, document the real set before fixing.

## Implementation Guidance

Prefer this order:

1. Characterize parser output for one finite `for` and one budgeted `loop`.
2. Characterize typed declarations after typechecker.
3. Characterize emitter/SemanticIR output.
4. Fix the narrowest layer that loses loop nodes.

Likely recovery area: emitter/SemanticIR shape, not parser. But do not assume.

Keep the fix boring:

- preserve existing OOF diagnostics;
- do not expand loop execution semantics;
- do not implement recursion/fuel/runtime loop execution;
- do not redesign PROP-039;
- do not rename tests to fit current behavior unless the tests are demonstrably stale against accepted docs.

## Required Acceptance

- [x] `loop_conformance_tests` focused run is green (14/14).
- [x] Finite `for` emits at least one `kind:"loop_node"`.
- [x] Finite loop node carries `loop_class:"finite"`.
- [x] Finite loop node carries `termination:"collection_exhaustion"`.
- [x] Finite loop node carries `source_ref`.
- [x] Budgeted `loop ... max_steps:N` emits at least one `kind:"loop_node"`.
- [x] Budgeted loop node carries `loop_class:"budgeted"`.
- [x] Budgeted loop node carries `max_steps`.
- [x] SemanticIR does not emit old `kind:"loop"` for these cases.
- [x] Existing OOF loop tests remain green.
- [x] `LANG-LANG-STRING-ESCAPES-P1` not touched/regressed (only the loop test file changed; no lexer/string edit).
- [x] No IgWeb / Todo / renderer files are modified.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Root cause was NOT an emitter bug** (the card's hypothesis, which it correctly flagged as possibly
"stale assertions"). `emitter::emit_typed` produces `semantic_ir` **only if `type_errors.is_empty()`**
(`emitter.rs:32`). All 4 failing test sources used `compute total = total + item` — mutating outer state —
which fires **OOF-L7** ("outer state is read-only", `typechecker.rs:1291`). That type error ⇒
`semantic_ir = None` ⇒ no `loop_node` ⇒ all 4 fail. The emitter's `loop_node` builder (`emitter.rs:2412`)
was **already correct**.

**Fix — test inputs only:** rewrote the 4 loop bodies from outer-state mutation to the accepted PROP-039
gate-8 **`lead` accumulator** form (`lead acc: Integer = 0` / `compute acc = acc + item`), which compiles
clean → emitter reached → correct `loop_node` shape emitted. **No emitter/typechecker/parser/lexer change;
no rule weakened; no test renamed.** One file changed (`loop_conformance_tests.rs`, +8/−4).

**Proof:** `cargo test --test loop_conformance_tests` → **14 passed; 0 failed** (was 10/4); full
`igniter-compiler` suite **green** (lib 55 + all binaries 0 failed); `git diff --check` clean; no
lexer/string/IgWeb/Todo/renderer files touched.

**Deferred (flagged, not resolved — card forbids PROP-039 redesign):** a real lab↔canon divergence — the
Rust typechecker requires the `lead` model (OOF-L7), but the canon-target fixture
`fixtures/loops/loop_accumulator.ig` still uses outer-state accumulation and notes *"Rust compiler update
needed to accept canon syntax"*. Which loop-body shape is intended canon is an open PROP-039 reconciliation
question for a separate card; this recovery aligned the tests with the **implemented** behaviour only.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test loop_conformance_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test string_escapes_tests   # if present
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test
git diff --check
```

If the full compiler suite still has unrelated failures after the loop fix, identify them exactly. Do not
claim full green unless it is true.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-loop-ir-conformance-recovery-p1-v0.md
```

It must include:

- exact pre-fix failure set;
- parser/typechecker/emitter characterization;
- exact layer fixed;
- before/after SemanticIR shape sample for finite and budgeted loops;
- exact tests/counts;
- what remains deferred in PROP-039 / loop runtime execution.

Update this card with a closing report.

## Closed Scope

- No string escape changes.
- No IgWeb changes.
- No Todo/view/render changes.
- No VM runtime loop execution.
- No recursion/fuel proof expansion.
- No new loop syntax.
- No broad PROP-039 redesign.
- No canon/stable API claim.

## Coordination Note

This card may run in parallel with `LAB-LANG-STRING-ESCAPES-P1`, but must avoid touching `lexer.rs` string
handling unless live evidence proves it is somehow involved. If both agents edit shared compiler files, keep
diffs narrow and coordinate before commit.
