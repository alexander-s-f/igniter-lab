# LAB-STDLIB-STRING-CHAR-AT-VM-P1 Proof

**Date:** 2026-06-15  
**Card:** `LAB-STDLIB-STRING-CHAR-AT-VM-P1`  
**Runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_string_char_at_vm_p1.rb`  
**Result:** CLOSED - 96/96 PASS  
**Authority:** lab VM runtime support for already-typed `stdlib.string` calls only

## Verdict

The VM now executes:

- `stdlib.string.char_at(source, index) -> String`
- `stdlib.string.substring(source, start, length) -> String`

Both canonical names and current bare runtime aliases are handled. The bytecode
`OP_CALL` path and the `eval_ast` tree-walker path share the same helpers, so
lambda/HOF bodies do not lag the normal bytecode path for this surface.

## Runtime Policy

This VM slice follows the card's runtime instruction: index by Unicode scalar
values, matching the existing `stdlib.text.rune_slice` family rather than using
raw byte offsets.

Observed examples:

| Call | Result |
|---|---|
| `char_at("abc", 1)` | `"b"` |
| `substring("module", 2, 3)` | `"dul"` |
| `char_at("aé🚀", 1)` | `"é"` |
| `substring("aé🚀z", 1, 2)` | `"é🚀"` |

Bounds behavior follows the existing VM text-slice style: out-of-bounds or
negative `char_at` returns `""`; substring clamps a negative start to zero and
returns `""` when the requested range is empty.

Wrong arity and wrong argument types remain runtime errors.

## Implementation

Changed:

```text
igniter-lab/igniter-vm/src/vm.rs
igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md
```

No frontend source was changed:

- no parser change,
- no typechecker change,
- no compiler/emitter change,
- no stdlib inventory change,
- no app source migration.

## Proof Matrix

| Section | Topic | Checks |
|---|---|---:|
| A | Source shape and gates | 16 |
| B | Frontend fixture and SIR | 12 |
| C | OP_CALL runtime happy paths | 12 |
| D | Runtime failure and bounds policy | 14 |
| E | eval_ast lambda path | 8 |
| F | igniter_parser runtime path | 14 |
| G | Text regression and boundaries | 8 |
| H | Closure artifacts | 12 |
| **Total** | | **96** |

## igniter_parser Result

The proof compiles `igniter_parser` with the existing app sources:

```text
types.ig lexer.ig parser.ig api.ig
```

Then it runs:

```text
igniter-vm run --entry ParseSource --inputs {"source":"module Demo"}
```

Result:

```json
[
  {
    "children_ids": [],
    "id": "node-1",
    "kind": "ModuleDecl",
    "text": "ParsedModule"
  }
]
```

This advances past the prior `OP_CALL: Unknown/unimplemented function
'stdlib.string.char_at'` gap. `igniter_parser` still belongs to the app-side
demo-entry wave for zero-input demo work; this card closes only the VM string
runtime tail.

## Regression Guard

The proof also checks that `stdlib.text.rune_slice("aé🚀", 1, 2)` still returns
`"é"`. Existing `stdlib.text.*` behavior remains unchanged.

## Closed Surfaces

- No front-end compiler changes.
- No parser/typechecker changes.
- No new stdlib surface.
- No inventory authority change.
- No app source migration.
- No dynamic dispatch relaxation.
- No byte-vs-rune canon policy expansion beyond this lab VM runtime behavior.

## Command

```text
cd /Users/alex/dev/projects/igniter-workspace
ruby igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_string_char_at_vm_p1.rb
RESULT: 96/96 PASS
```
