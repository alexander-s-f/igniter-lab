# Spreadsheet Engine Domain Pressure Report

**Date:** 2026-06-11
**Target:** Igniter TypeChecker, function recursion, recursive structural types, collection stdlib, and app composition
**App:** Reactive Spreadsheet Engine (`igniter-lab/igniter-apps/spreadsheet`)
**Status:** living pressure report / not a production app

---

## Summary

This spreadsheet fixture is a compact pressure test for AST-like data and recursive
evaluation. It stresses a different frontier than bookkeeping:

- recursive structural record types;
- function-level recursion and mutual recursion;
- managed recursion termination evidence;
- Option-like arithmetic over nullable numeric fields;
- collection `map` over cells;
- stringly contract composition at the API layer.

The earlier report treated multi-file type visibility as a major blocker. That is now
partly stale. Current Rust multi-file compilation resolves imported `Grid` and `Cell`
shapes correctly. The primary Rust blocker is now managed recursion for `def` functions:
`eval_expr` must provide `decreases fuel`.

---

## Current Files

| File | Role |
|---|---|
| `types.ig` | Defines `CellValue`, recursive `Expr`, `Cell`, and `Grid`. |
| `engine.ig` | Defines recursive evaluator functions and `CalculateGrid`. |
| `api.ig` | Defines `RecalculateWorkbook`, intended as the operational entrypoint. |
| `PRESSURE_REGISTRY.md` | Structured pressure registry derived from this report. |

---

## Fresh Live Check

Commands run on 2026-06-11 against current local toolchains.

Rust type-only compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/types.ig --out /tmp/spreadsheet-types.igapp
```

Result: `status: ok`, zero diagnostics.

Rust engine single-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/engine.ig --out /tmp/spreadsheet-engine.igapp
```

Result: `status: oof`.

Key diagnostics:

- `Unresolved field: Grid.cells`
- `Recursive function 'eval_expr' must specify 'decreases fuel'`

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/types.ig ../igniter-apps/spreadsheet/engine.ig ../igniter-apps/spreadsheet/api.ig --out /tmp/spreadsheet-full.igapp
```

Result: `status: oof`.

Key diagnostic:

- `Recursive function 'eval_expr' must specify 'decreases fuel'`

Important update: in Rust multi-file mode, the old `Grid.cells` import/type visibility
failure disappears. Multi-file resolution is no longer the primary blocker for this fixture.

Ruby canon full multi-file compile currently reports narrower surface coverage:

- `Unknown function: call_contract`
- `Unknown function: map`
- `Type mismatch: expected Collection, got Unknown`

Ruby does not currently surface the same `OOF-L4` function-recursion diagnostic in this fixture,
which indicates a Rust/Ruby parity gap around function-level recursion checking.

---

## Updated Findings

### 1. Recursive Structural Types Work

`types.ig` declares:

```igniter
type Expr {
  kind : Text
  num_val : Float?
  ref_id  : Text?
  left : Expr?
  right : Expr?
}
```

Rust compilation of `types.ig` succeeds with zero diagnostics. This is a strong positive finding:
Igniter can represent AST-shaped recursive data as named records.

Status: positive / keep as regression guard.

Pressure registry entry: `SS-P01`.

---

### 2. Function-Level Recursion Is Recognized But Requires Termination Evidence

`engine.ig` defines recursive functions:

```igniter
def eval_expr(expr: Expr, grid: Grid) -> CellValue { ... }
def eval_ref(ref_id: Text, grid: Grid) -> CellValue { ... }
```

Rust full multi-file compilation reports:

```text
Recursive function 'eval_expr' must specify 'decreases fuel'
```

This is high-signal: the compiler detects recursion, but the current source does not express the
required termination metric. This is distinct from contract-level `recur()` work. Spreadsheet needs
managed recursion for `def` functions and AST traversal.

Status: active pressure.

Pressure registry entry: `SS-P02`.

---

### 3. Mutual Recursion Needs A Policy

`eval_expr` can call `eval_ref`, and `eval_ref` calls `eval_expr`. The current diagnostic names
`eval_expr`, but the conceptual graph is a mutually recursive evaluator pair.

The language needs to decide how function-level mutual recursion is represented:

- one shared fuel budget?
- explicit recursive group?
- only self-recursive functions in v0?
- require all functions in the SCC to declare termination evidence?

Status: active design pressure.

Pressure registry entry: `SS-P03`.

---

### 4. Option / Nullable Arithmetic Is Blocked Behind Recursion

The evaluator attempts:

```igniter
left_val.num_val + right_val.num_val
```

where `num_val` is `Float?`. The current compiler does not reach this as the primary error because
managed recursion blocks first. Once recursion is satisfied, spreadsheet should pressure Option/nullable
arithmetic semantics:

- unwrap required?
- propagate error?
- `Option[Float] + Option[Float]` closed?
- helper required?

Status: pending behind recursion.

Pressure registry entry: `SS-P04`.

---

### 5. Collection `map` Parity Remains Open

`CalculateGrid` uses:

```igniter
compute evaluated_cells = map(grid.cells, cell -> eval_expr(cell.ast, grid))
```

Rust gets far enough to report recursion after multi-file resolution. Ruby canon reports `Unknown function: map`.
This aligns with the stdlib collection gap: collection helpers need entry contracts, signatures, and parity.

Status: active stdlib parity pressure.

Pressure registry entry: `SS-P05`.

---

### 6. Stringly `call_contract` In API Layer Is A Composition Pressure

`api.ig` uses:

```igniter
compute evaluated_cells = call_contract("CalculateGrid", grid)
```

This is the same composition smell surfaced elsewhere. Recent typed contract reference and form work provides
a better future substrate, but this app should not be migrated ad hoc until that route is explicitly opened.

Status: design pressure.

Pressure registry entry: `SS-P06`.

---

### 7. Inline Record Literal vs Block Ambiguity Is Historical / Not Currently Exercised

The earlier report noted that lambda bodies like:

```igniter
cell -> { id: cell.id, val: eval_expr(...) }
```

could be parsed as a block rather than a record literal. The current fixture no longer exercises this exact
shape. Keep the finding as historical pressure, but do not rank it above the active recursion and stdlib gaps
without a fresh minimal fixture.

Status: historical / needs fresh proof if reopened.

Pressure registry entry: `SS-P07`.

---

## Current Pressure Ranking

| Rank | Pressure | Why |
|---:|---|---|
| 1 | Function-level managed recursion | Blocks AST evaluation in Rust multi-file. |
| 2 | Mutual recursion policy | Spreadsheet evaluator naturally forms an SCC. |
| 3 | Collection `map` parity | Needed for grid-level evaluation and Ruby parity. |
| 4 | Option/nullable arithmetic | Expected next blocker after recursion. |
| 5 | Stringly `call_contract` | App composition pressure; route through typed refs/forms. |
| 6 | Inline record/block ambiguity | Historical; needs fresh minimized proof. |

---

## Recommended Next Routes

1. **LAB-FUNCTION-RECURSION-P1** or **LAB-MANAGED-RECURSION-FUNCTIONS-P1**
   Function-level recursion, `decreases fuel`, mutual recursion policy, and AST traversal proof.

2. **LAB-STDLIB-COLLECTION-P1**
   `map`/collection helper parity, especially over recursive record shapes.

3. **LAB-STDLIB-OPTION-P1**
   Nullable arithmetic / Option helpers once recursion no longer blocks evaluation.

4. **Typed-ref/forms migration route**
   Later replacement for stringly `call_contract` in `api.ig`.

5. **LAB-PARSER-RECORD-LAMBDA-P1**
   Only if the inline record literal vs block ambiguity is reopened with a minimal current fixture.

---

## Non-Goals

This app does not authorize:

- production spreadsheet runtime;
- general recursive interpreter implementation;
- arbitrary recursion without termination evidence;
- implicit Option unwrapping;
- `call_contract` canonization;
- collection stdlib implementation without entry contracts;
- parser changes for inline record literals;
- VM/runtime changes.

---

## Operating Decision

Keep spreadsheet as an AST/recursion pressure fixture. Do not weaken recursion checks locally to make it compile.
Use it to route managed-recursion and collection/Option stdlib slices deliberately.
