# ERP Logistics Domain Pressure Report

**Date:** 2026-06-11  
**Target:** Igniter Multi-file Compilation & Binary Operators  
**App:** ERP Logistics Engine (`igniter-apps/erp_logistics`)

## Overview
This report synthesizes the boundaries encountered when modeling an ERP Logistics application spanning multiple files. The primary goal was to bypass the `OOF-P1` (Unresolved field) errors seen in previous domain tests by feeding multiple files simultaneously to the Rust compiler.

---

## 1. SUCCESS: Multi-file Compilation Resolves `TypeEnv`
**Symptom:**  
In previous apps (Bookkeeping, Spreadsheet), `call_contract` and external record types failed because the compiler was only fed the entrypoint file. In this app, executing `cargo run -- compile types.ig warehouse.ig api.ig` resulted in **successful cross-file resolution**.

**Analysis:**  
The `igniter-compiler` natively merges the `TypeEnv` and contract registries of all files provided in the CLI arguments (`SOURCE [SOURCE ...]`). The `import` statements themselves do not currently trigger file-system traversal or parsing. To compile large Igniter applications, the build system (e.g. `igc`) must collect and pass the entire dependency graph explicitly to the compiler core.

---

## 2. Float Comparison is Not Implemented
**Symptom:**  
`shipment.weight < 1000.0` threw the following error:
`Type mismatch for <: expected Integer on both sides, got Float < Float` (`OOF-TY0`).

**Analysis:**  
The Rust typechecker's `operator_type` function explicitly restricts the `<` (and likely `<=`) operator to `Integer` operands. `Float` comparisons are currently unimplemented, blocking basic physical bounds checking (weight, volume, distance) in logistics and scientific domains.

---

## 3. Unary Operators on Floats
**Symptom:**  
Attempting to return `-1.0` threw `Unexpected token in expression: Op` (`OOF-P0`).

**Analysis:**  
The parser strictly rejects negative float literals or unary `-` operations applied to floats at the AST level, requiring numeric bounds or fallback returns to use `0.0` or positive flags instead of standard error code numeric primitives.

---

## Next Steps for the Platform
1. **Operator Expansion:** The typechecker must implement match arms for `Float < Float`, `Float <= Float`, and `Float == Float`.
2. **Unary Minus:** Ensure `PrefixExpr` successfully parses negative numeric literals.
3. **Build Tooling:** The `igc` Ruby wrapper needs to be updated to traverse `import` statements and automatically feed the transitive closure of `.ig` files into the Rust compiler as a single batch command.
