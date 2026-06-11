# Spreadsheet Engine Domain Pressure Report

**Date:** 2026-06-11  
**Target:** Igniter TypeChecker, Grammar, and Recursion Semantics  
**App:** Reactive Spreadsheet Engine (`igniter-apps/spreadsheet`)

## Overview
This report synthesizes the boundaries encountered when modeling an AST and a recursive calculation engine in Igniter.

---

## 1. Managed Recursion is Present but Strict (`OOF-L4`)
**Symptom:**  
The Rust compiler rejects `eval_expr` with:
`Recursive function 'eval_expr' must specify 'decreases fuel'` (`OOF-L4`).

**Analysis:**  
This is a high-signal finding! While older specs noted that recursive functions would trigger `OOF-F1` (self-reference), the TypeChecker has actually implemented `ch13-managed-recursion`. It acknowledges the recursive AST traversal but strictly demands a termination metric (`decreases fuel`). Without knowing the exact syntax for injecting fuel into the environment, AST evaluation is blocked.

---

## 2. Multi-File TypeEnv Visibility Fails Again
**Symptom:**  
`Unresolved field: Grid.cells` (`OOF-P1`) when compiling `engine.ig`.

**Analysis:**  
This confirms the finding from the Bookkeeping app: the `MultifileResolver` does not merge `import SpreadsheetTypes` into the local `TypeEnv`. The compiler sees `grid.cells` but has no definition for `Grid` locally, causing a fatal lookup failure.

---

## 3. Ambiguity in Parser: `RecordLit` vs `BlockExpr`
**Symptom:**  
Using inline records inside lambdas (`cell -> { id: cell.id, val: eval_expr(...) }`) caused catastrophic parser syntax errors (`Unexpected token in expression: Colon`).

**Analysis:**  
The grammar definition for `Lambda` allows a block `-> Expr`. The parser eagerly interprets `{` as the start of a `BlockExpr` (`{ Stmt* Expr }`) rather than a `RecordLit` (`{ name: expr }`). When it encounters a colon `:`, it crashes. To bypass this, developers are forced to extract the logic into a `let` block or rely on pre-defined structural types.

---

## 4. `TypeRef` Grammar Does Not Support Inline Records
**Symptom:**  
Annotations like `output evaluated_cells : Collection[Record { id: Text, val: CellValue }]` fail to parse.

**Analysis:**  
The `TypeRef` BNF strictly accepts predefined names (`Name`), primitive strings, or wrapper types (`Collection[T]`). It does *not* support anonymous inline record types. Types must be formally declared in a `type` block and referenced by name.

---

## 5. Recursive Structural Types are Allowed!
**Positive Finding:**  
When compiling `types.ig` in isolation, the Rust compiler emitted `status: "ok"`. The declaration:
```igniter
type Expr {
  left : Expr?
  right : Expr?
}
```
successfully passed the parser, classifier, and typechecker. This proves that Igniter's `TypeEnv` handles recursive structural definitions perfectly, providing a solid foundation for AST representation once the recursion engine limits (`OOF-L4`) are addressed.
