# Forms First Proof

Status: active

Goal:
Follow contract invocation form resolution from a source fixture to the compiler-generated `form_table.json` and `form_resolution_trace.json` artifacts.

This lesson explores how the experimental compiler maps syntactic operators to type-directed contract invocations.

## Read

Start with these files:

| File | Why It Matters |
| --- | --- |
| [Positive forms fixture](../../igniter-compiler/fixtures/forms/positive_forms.ig) | Source fixture defining forms (e.g., `Add`, `Concat`) and using them (e.g., `a + b`). |
| [Form registry](../../igniter-compiler/src/form_registry.rs) | Rust implementation tracking registered forms and syntax triggers. |
| [Form resolver](../../igniter-compiler/src/form_resolver.rs) | Rust implementation resolving ambiguous operators using operand types. |

## Try

From the `igniter-compiler/` package directory:

```bash
cargo run -- compile fixtures/forms/positive_forms.ig --out out/forms_test.igapp
```

This compiles the fixture and writes the `.igapp` bundle folder structure under `out/forms_test.igapp`.

## Observe

Inspect the generated form artifacts in the output directory:

### 1. The Form Table (`form_table.json`)
Open `out/forms_test.igapp/form_table.json`. This lists the static forms registered during compilation:

```json
{
  "artifact": "form_table",
  "entry_count": 5,
  "resolved": [
    {
      "contract": "Add",
      "id": "Add::infix",
      "kind": "infix",
      "trigger": "+"
    },
    {
      "contract": "Concat",
      "id": "Concat::infix",
      "kind": "infix",
      "trigger": "++"
    }
    // Sum::postfix, Where::block_method, Guard::keyword_block...
  ]
}
```

The compiler parser is **type-blind**: it parses all operators (like `+` or `++`) as generic syntax nodes. The typechecker then resolves them using this table.

### 2. The Resolution Trace (`form_resolution_trace.json`)
Open `out/forms_test.igapp/form_resolution_trace.json`. This tracks how expressions were resolved:

- **Type-directed resolution**: Look at the entry for `UseAdd::total` (`a + b`). The trace shows the compiler identified the `+` trigger, found `Add` as a candidate, validated that both operands are `Integer`, and selected it:
  ```json
  {
    "contract_ctx": "UseAdd",
    "decl_name": "total",
    "expr_kind": "binary_op",
    "filter_status": "typed_candidate_selected",
    "resolved_to": "Add",
    "trigger": "+"
  }
  ```
- **Explicit Call Bypass**: Look at `ExplicitCallPath::char_count` (`length(s)`). Because it uses standard call syntax rather than a form operator, it bypasses the resolver entirely:
  ```json
  {
    "contract_ctx": "ExplicitCallPath",
    "decl_name": "char_count",
    "expr_kind": "call",
    "filter_status": "explicit_call_bypass",
    "trigger": "length"
  }
  ```

## What This Proves

This walkthrough demonstrates that:
- The parser accepts custom form definitions (infix, postfix, block method, keyword block).
- The resolver resolves operators based on type contexts (type-directed dispatch).
- Syntactic call nodes (like `length(s)`) bypass the form resolver and lower directly to standard calls.
- Resolved contract mappings are statically emitted, meaning the runtime does not need to perform dynamic form lookup.

It does not prove:
- Stable grammar syntax or public API conventions.
- Mainline compiler acceptance of custom forms.
- Runtime support for dynamic dispatch.

## Troubleshooting

| Symptom | Next Step |
| --- | --- |
| Compiler fails with type errors | Forms resolution depends on successful typechecking. Verify that operand types match the form's declared input types. |
| Operator fails to resolve | Check `form_resolution_trace.json` under `"trace"` to see why candidates were filtered out (e.g., status is `"primitive_pass_through"` or mismatch). |

## Boundary

Form resolution is an experimental lab feature. Passing this lesson produces proof-local evidence only and does not promote lab behavior into canon.
