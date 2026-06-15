# LAB-STDLIB-STRING-CHAR-AT-VM-P1

**Status:** CLOSED — IMPLEMENTED 96/96 PASS
**Route:** lab / VM / stdlib.string runtime parity
**Date:** 2026-06-15
**Date closed:** 2026-06-15
**Authority:** VM runtime support for already-typed stdlib.string calls; no front-end changes

## Goal

Implement VM runtime support for `stdlib.string.char_at` and verify `substring` coverage
for the `igniter_parser` runtime path.

The language/frontend side already accepts the string surface from the earlier
`LANG-STDLIB-STRING-SURFACE` work. The remaining gap is VM execution: with a real
`source` input, `igniter_parser` reaches `stdlib.string.char_at` and the VM cannot run it.

## Gate

Start after:

- `LANG-STDLIB-STRING-SURFACE-P3` / substring implementation work is closed in canon/lab.
- `LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1` records this as a small tail, not a broad VM gap.

May run before or in parallel with `LAB-APP-DEMO-ENTRY-WAVE-P1`; the app wave should treat
`igniter_parser` full success as gated on this card.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-APP-DEMO-ENTRY-WAVE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/vm.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/compiler.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/igniter_parser/`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch8-stdlib.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`
- Existing VM text/string stdlib handlers.

## Implementation Shape

- Add VM `OP_CALL` / stdlib call handling for `stdlib.string.char_at(s, i) -> String`.
- Verify whether `stdlib.string.substring(s, start, length)` already runs. If not, add it
  in the same narrow family because `igniter_parser` token text uses both surfaces.
- Use rune/character indexing consistent with existing `stdlib.text.rune_slice` behavior.
- Fail closed on wrong arity, non-string source, non-integer index/start/length, and out-of-bounds if current VM convention requires an error.
- Prefer explicit canonical names; add bare-name aliases only if current SIR can still emit them in runtime paths.

## Deliverables

- VM implementation in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/vm.rs` and/or narrow helper module.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_string_char_at_vm_p1.rb`, target at least 70 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-stdlib-string-char-at-vm-p1-v0.md`.
- Update this card and portfolio index.

## Acceptance

- Direct VM fixture for `stdlib.string.char_at("abc", 1)` returns `"b"` or the documented rune-equivalent.
- Direct VM fixture for substring either passes or is explicitly proven already supported.
- `igniter_parser` with a simple `source` input advances past the prior `char_at` gap.
- No compiler/typechecker/inventory changes are needed in this card.
- Existing `stdlib.text.*` behavior remains unchanged.

## Closure Summary

Implemented VM runtime support in:

- `igniter-lab/igniter-vm/src/vm.rs`

Updated runtime surface index:

- `igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md`

The VM now handles both canonical and current bare runtime names:

- `stdlib.string.char_at` / `char_at`
- `stdlib.string.substring` / `substring`

Both the bytecode `OP_CALL` path and the `eval_ast` tree-walker path call the same
helpers, preserving parity for HOF/lambda bodies.

Runtime policy follows this card's instruction: rune/character indexing,
consistent with `stdlib.text.rune_slice`.

Proof:

```text
cd /Users/alex/dev/projects/igniter-workspace
ruby igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_string_char_at_vm_p1.rb
RESULT: 96/96 PASS
```

Key evidence:

- `char_at("abc", 1)` returns `"b"`.
- `substring("module", 2, 3)` returns `"dul"`.
- `char_at("aé🚀", 1)` returns `"é"`.
- `substring("aé🚀z", 1, 2)` returns `"é🚀"`.
- `map(words, word -> char_at(word, 1))` runs through `eval_ast`.
- `igniter_parser` `ParseSource` with `source: "module Demo"` reaches VM success and returns a `ModuleDecl` node.
- `stdlib.text.rune_slice` regression remains green.

Artifacts:

| Artifact | Path |
|---|---|
| VM implementation | `igniter-lab/igniter-vm/src/vm.rs` |
| Runtime surface index | `igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md` |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_string_char_at_vm_p1.rb` |
| Lab doc | `igniter-lab/lab-docs/lang/lab-stdlib-string-char-at-vm-p1-v0.md` |
| Portfolio index | `igniter-lab/.agents/portfolio-index.md` |

## Closed Surfaces

- No front-end compiler changes.
- No parser/typechecker changes.
- No new stdlib surface.
- No byte-vs-rune policy expansion beyond matching existing text semantics.
- No `igniter_parser` app migration beyond optional demo entry in the app wave.

## Agent Recommendation

Give this to **Codex GPT 5.5** as a fast VM stdlib parity slice.
