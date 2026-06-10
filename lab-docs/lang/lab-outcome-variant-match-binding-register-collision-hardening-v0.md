# lab-outcome-variant-match-binding-register-collision-hardening-v0

**Track:** lab-outcome-variant-match-binding-register-collision-hardening-v0  
**Route:** LAB FIX + PROOF / VM COMPILER HARDENING / NO SEMANTIC CHANGE  
**Authority:** lab_only — not canon, not production  
**Proof result:** 43/43 PASS  
**Date:** 2026-06-10  
**Predecessor:** LAB-OUTCOME-VARIANT-P2  

---

## Problem Statement

In LAB-OUTCOME-VARIANT-P2, three extract contracts had to rename their compute
nodes to avoid a VM compiler panic:

| Natural name | Forced rename | Reason |
|-------------|--------------|--------|
| `observed_at` | `ts` | compute name == binding name → panic |
| `request_id` | `rid` | compute name == binding name → panic |
| `attempt` | `n_attempt` | compute name == binding name → panic |

The root cause: the compiler allocated a register for the compute node in Step 1,
then silently deleted that register entry during match arm binding cleanup in Step 2.

---

## Root Cause Analysis

The VM compiler processes a contract in three steps:

**Step 1** (`compiler.rs:115–122`): Allocate register IDs for every compute node.

```rust
for node in nodes_arr {
    if let Some(name) = node.get("name")... {
        let reg = self.next_register;
        self.next_register += 1;
        self.compute_node_registers.insert(name, reg);  // e.g. "attempt" → 0
    }
}
```

**Step 2** (`compiler.rs:124–150`): Compile each compute node's expression and emit
`OP_STORE_REG` to save the result. For the `attempt` compute node, this calls
`compile_expr(match_node)`.

**Inside match arm compilation** (compiler.rs, match_node branch):

```rust
// For arm: ConfirmedFailed { attempt } => attempt
self.compute_node_registers.insert("attempt", arm_reg);  // OVERWRITES "attempt" → 0
// ... compile arm body ...
self.compute_node_registers.remove("attempt");           // DELETES "attempt" entirely
```

**Back in Step 2**, after `compile_expr` returns:

```rust
let reg = *self.compute_node_registers.get("attempt").unwrap();  // PANIC: key gone
self.emit(OP_STORE_REG, vec![Value::Integer(reg)]);
```

The `remove("attempt")` in the arm cleanup deletes the outer compute node's register,
not just the scoped arm binding.

---

## Fix: Lexical Scoping Discipline

Before inserting each arm binding, save any existing value for that name. After the
arm body compiles, restore the saved value (or remove the key if nothing was there).

**Before** (two-phase: insert, then remove):

```rust
let mut binding_regs: Vec<(String, i64)> = Vec::new();
for binding in &bindings {
    // ... allocate and emit ...
    self.compute_node_registers.insert(binding.clone(), reg);  // overwrites outer
    binding_regs.push((binding.clone(), reg));
}
self.compile_expr(body)?;
for (name, _) in &binding_regs {
    self.compute_node_registers.remove(name);  // deletes outer register
}
```

**After** (save + restore):

```rust
let mut saved_outer: Vec<(String, Option<i64>)> = Vec::new();
for binding in &bindings {
    let outer = self.compute_node_registers.get(binding).copied();  // save
    saved_outer.push((binding.clone(), outer));
    // ... allocate and emit ...
    self.compute_node_registers.insert(binding.clone(), reg);  // shadow
}
self.compile_expr(body)?;
for (name, maybe_outer) in &saved_outer {
    match maybe_outer {
        Some(outer_reg) => { self.compute_node_registers.insert(name.clone(), *outer_reg); }
        None => { self.compute_node_registers.remove(name); }
    }
}
```

This matches standard lexical scoping: an arm binding's lifetime is strictly the arm
body. If the name shadowed an outer register, the outer register is fully restored.

---

## File Changed

`igniter-lab/igniter-vm/src/compiler.rs` — match arm binding section (one block,
~15 lines replaced). No other files modified.

---

## What the Fix Enables

After the fix, the natural source pattern works without any renaming workaround:

```igniter
compute attempt: Integer = match outcome {
  ConfirmedFailed { attempt } => attempt
  StillUnknown    { attempt } => attempt
  Otherwise       {}          => 0
}
output attempt: Integer
```

Both the compute node name and the binding name can be `attempt`. The arm binding
shadows the compute node register during the arm body, then the outer register is
restored before `OP_STORE_REG` fires.

---

## Proof Sections (43 checks)

| Section | Checks | What is proved |
|---------|--------|---------------|
| P3-COMPILE | 5 | Collision fixture compiles; 6 contracts; no OOF diags |
| P3-COLLISION | 8 | Integer + String direct compute==binding collision works |
| P3-SHADOW | 5 | Outer register intact after collision arm exits |
| P3-NESTED | 5 | P2 arm body function calls + RouteCollision unaffected |
| P3-MULTIARM | 6 | Multiple arms sharing binding name: each arm independently correct |
| P3-REG | 8 | P2 (56/56) + P1 (11-arm) + LAB-VARIANT-VM-P1 regressions green |
| P3-CLOSED | 6 | No new opcodes, no binding_regs artifact, closed surfaces verified |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| What caused the collision? | `remove(name)` in arm cleanup deleted the outer compute node register |
| Fix discipline? | Save outer before insert; restore or remove after arm body |
| compute == binding now works? | YES — P3-COLLISION proves Integer + String cases |
| Multiple arms sharing binding name? | YES — P3-MULTIARM proves independent shadow/restore per arm |
| P2 + VM-P1 regressions green? | YES — P3-REG proves all |
| Semantics changed? | NO — routing, values, opcodes all identical |
| Next route? | LAB-FAILURE-TAXONOMY-P1 planning (unless deeper scope issues found) |

---

## Constraints Respected

- No source grammar changes  
- No new VM opcodes  
- No `Value::Variant`  
- No TypeChecker changes  
- No Ruby canon changes  
- No failure taxonomy  
- No `Outcome[T,E]`  
- `__arm`/`__variant` not public API  
- Path B semantics unchanged  
- Fix is scoped + lexical, not ad hoc per fixture  

---

## What This Proves

- The collision was a VM compiler implementation bug (missing save/restore discipline)
- The fix is lexical: arm binding lifetime = arm body only
- Compute node names can now freely match binding names in their match expressions
- LAB-OUTCOME-VARIANT-P2 renamed computes (`ts`, `rid`, `n_attempt`) remain correct
  but are no longer required to avoid collision — they were workarounds for this bug
- P2, P1, and LAB-VARIANT-VM-P1 fixtures all pass unchanged

## What This Does NOT Prove

- Nested match expressions where an inner binding collides with an outer match arm
  binding (not a current fixture; the fix's save/restore chain handles this correctly
  by construction, but no explicit proof is included)
- Ruby canon parity (Ruby TC does not execute match arm bindings at runtime)
- Production runtime support
