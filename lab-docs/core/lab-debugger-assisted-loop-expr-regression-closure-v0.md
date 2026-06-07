# Loop Collection Expression Mismatch Closure (v0)

This document provides proof and technical details on closing the loop collection expression compiler-to-VM mismatch regression (`VM execution error: Missing loop collection expr`).

---

## The Regression Context

During compilation, loop nodes represent iteration over collection inputs or expressions. A regression occurred where:
- The parser/typechecker frontend parsed loops correctly, leaving loop collection references inside the `expr` field of loop AST nodes.
- The `igniter-compiler` assembler (in `assembler.rs`) renamed the `expr` field to `expression` when outputting the compiled JSON contract (as part of generic compute node mapping) and silently stripped `body_nodes` and `options` properties.
- The `igniter-vm` compiler expects the collection reference inside the `expr` field and crashed when encountering compiled loop nodes containing only `expression`.

---

## Resolution Strategy (Option C)

We selected and implemented **Option C** to guarantee absolute robustness, backwards compatibility, and clear telemetry visualization inside the IDE debugger.

### 1. Assembler Alignment
We updated `igniter-lab/igniter-compiler/src/assembler.rs` with a recursive `assemble_compute_node` helper:
- When encountering `kind == "loop"`, it preserves and writes both `"expr"` and `"expression"` mapped to the same compatible expression.
- It retains `"options"` containing the `max_steps` constraint.
- It recursively compiles and preserves the array of compute nodes inside `"body_nodes"`.
- For `"service_loop_node"`, it similarly retains `"interval"`, `"temporal_binding"`, and its body.

### 2. VM Compiler Robustness
We updated `igniter-lab/igniter-vm/src/compiler.rs` under the `"loop"` arm:
- The loop collection is read using `node.get("expr").or_else(|| node.get("expression"))`.
- Inner body compute node expressions are similarly read from either key in a robust manner.

---

## Verification Evidence

### Before/After Artifact Shape

#### Before (Broken loop contract JSON)
```json
{
  "dependencies": ["input:items", "input:total"],
  "expression": {
    "kind": "ref",
    "name": "items"
  },
  "fragment_class": "core",
  "kind": "loop",
  "name": "Accumulate",
  "node_id": "node_Accumulate"
}
```

#### After (Correctly aligned loop contract JSON)
```json
{
  "dependencies": ["input:items", "input:total"],
  "expr": {
    "kind": "ref",
    "name": "items"
  },
  "expression": {
    "kind": "ref",
    "name": "items"
  },
  "fragment_class": "core",
  "kind": "loop",
  "name": "Accumulate",
  "node_id": "node_Accumulate",
  "options": {
    "max_steps": 1000
  },
  "body_nodes": [
    {
      "dependencies": ["input:item", "input:total"],
      "expr": {
        "kind": "binary_op",
        "left": { "kind": "ref", "name": "total" },
        "op": "+",
        "right": { "kind": "ref", "name": "item" }
      },
      "expression": {
        "kind": "binary_op",
        "left": { "kind": "ref", "name": "total" },
        "op": "+",
        "right": { "kind": "ref", "name": "item" }
      },
      "fragment_class": "core",
      "kind": "compute",
      "name": "total",
      "node_id": "node_total",
      "type_tag": "Integer"
    }
  ],
  "type_tag": "Nil"
}
```

### End-to-End Execution Proof
We executed the regression fixture using `igniter-vm` with the inputs `[1, 2, 3, 4, 5]`:
- **Command**:
  ```bash
  cargo run --manifest-path ../igniter-vm/Cargo.toml --release -- run --contract out/loop_expr_regression_closure/loop_accumulator.igapp --inputs out/loop_expr_regression_closure/loop_accumulator_inputs.json --json
  ```
- **Output**:
  ```json
  {"latency_us":56,"observations":[],"result":15,"status":"success"}
  ```
- **Result**: Sum evaluation computed correctly (`15`), proving the VM loop iteration logic is fully operational.
