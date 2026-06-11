# Bookkeeping Domain Pressure Report

**Date:** 2026-06-11  
**Target:** Igniter Standard Library (`stdlib`) & TypeChecker  
**App:** Double-Entry Bookkeeping (`igniter-apps/bookkeeping`)

## Overview
This report synthesizes the gaps and `OOF` (Out-of-Frame) boundaries encountered when attempting to compile a pure Igniter double-entry bookkeeping application. This domain successfully pressured the compiler's handling of multi-file imports, decimal arithmetic, numeric literals, and standard library variants.

---

## 1. Multi-File Module Resolution is Incomplete
**Symptom:**  
The Rust compiler fails with `unknown callee 'VerifyBalancing' — not found in this module` when compiling `api.ig`.  
Both compilers throw `Unresolved field: Transaction.postings` when compiling `ledger.ig`.

**Analysis:**  
While the syntax `import BookkeepingTypes` parses successfully, the compiler pipelines do not currently perform full multifile closure. The `TypeEnv` and contract bindings from the imported files are not merged into the local file's scope, rendering external records and `call_contract` targets invisible.

---

## 2. Decimal Arithmetic and Equality Gaps
**Symptom:**  
`is_balanced = total_debits == total_credits` fails with:
`Type mismatch for ==: cannot compare Decimal with Decimal`

**Analysis:**  
The typechecker currently lacks the canonical match arms for `Decimal[N] == Decimal[N]`. While `Decimal` is structurally supported in `ch3-type-system.md`, equality checks for parameterized types are not fully lowered or validated in the compiler kernel.

---

## 3. Float vs. Decimal Literal Ambiguity
**Symptom:**  
`fold(txs, 0.00, ...)` fails with:
`Type mismatch: expected Decimal, got Float`

**Analysis:**  
The Igniter parser classifies `0.00` strictly as a `FloatLit`, assigning it a `Float` type. Because the `total` output expects `Decimal[2]`, the typechecker rejects it. The language currently lacks a literal syntax for Decimals (e.g., `0.00D`) and does not automatically coerce `Float` to `Decimal` in a typed context, creating severe friction for financial applications.

---

## 4. Variant Namespacing is Strict
**Symptom:**  
`ok(tx)` and `err("...")` fail with `Unknown function: ok` in the Ruby compiler.

**Analysis:**  
The standard library requires explicitly qualified namespacing for variants (e.g., `stdlib.result.ok`), or requires explicit importing of the constructors. The compiler does not implicitly inject the `Result` constructors into the global scope.

---

## 5. Closure / Lambda Parsing Succeeds
**Positive Finding:**  
Constructs like `map(credits, p -> p.amount)` and `filter(tx.postings, p -> p.direction == "Debit")` successfully passed the parser and classifier stages in the Rust compiler without syntax errors. This confirms that the recent parser grammar updates effectively handle inline lambda expressions for collection iterations.

---

## Next Steps for the Platform
1. **Module System:** Implement the `TypeEnv` merge logic for `import` statements so types and contracts cross boundaries.
2. **Decimal Support:** Add literal suffix syntax for `Decimal` (e.g., `100.00d`) and add `==` support for `Decimal` types.
3. **Stdlib Ergonomics:** Determine the canonical pattern for invoking `Result` and `Option` constructors (qualified vs. implicitly global).
