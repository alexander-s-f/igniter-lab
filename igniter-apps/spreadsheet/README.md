# Reactive Spreadsheet Engine (Domain Pressure Test)

This directory contains a prototype of an Excel-like calculation engine written in pure Igniter (`.ig`). The primary purpose is to apply domain pressure to Igniter's handling of Abstract Syntax Trees (ASTs), parsing, recursive evaluation, and `Option` arithmetic.

## Domain Model
Building a spreadsheet engine in a functional constraint-language tests several extreme boundaries:
- **Recursive Data Structures:** Cells hold formulas that recursively reference other formulas (ASTs). We modeled `Expr` with `left: Expr?` and `right: Expr?`.
- **Recursive Evaluation:** Resolving a spreadsheet requires recursively traversing the AST and following `ref_id` links to other cells.
- **Variant Handling:** A cell can result in a Number, String, or Error, necessitating variant modeling.

## Files
- `types.ig` — Defines the recursive `Expr` AST structure and the `Grid`.
- `engine.ig` — Contains the heavily recursive `eval_expr` and `eval_ref` functions to calculate values.
- `api.ig` — The entrypoint contract `RecalculateWorkbook`.

## Running the Compilers

**Using the Rust Compiler:**
```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/types.ig --out /tmp/spreadsheet_types.igapp
cargo run -- compile ../igniter-apps/spreadsheet/engine.ig --out /tmp/spreadsheet_engine.igapp
```

See [REPORT.md](./REPORT.md) for the detailed findings regarding compiler boundaries and OOF diagnostics. For the compact routing table, see [PRESSURE_REGISTRY.md](./PRESSURE_REGISTRY.md).
