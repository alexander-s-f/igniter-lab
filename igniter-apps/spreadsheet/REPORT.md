# Spreadsheet Engine Domain Pressure Report

**Date:** 2026-06-12
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

The earlier report treated multi-file type visibility as a major blocker — that is resolved.
Managed recursion was the primary Rust blocker — that is now also resolved. Both `eval_expr`
and `eval_ref` carry `decreases fuel` (SCC-complete, SS-P03). Rust compiles with `status: ok`
and zero diagnostics. The primary remaining pressures are collection `map` parity (SS-P05)
and Option/nullable arithmetic (SS-P04).

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

Commands run on 2026-06-12 after LAB-FUNCTION-RECURSION-P4 (Rust SCC OOF-L4) and
LAB-RUBY-FUNCTION-RECURSION-P2 (Ruby SCC OOF-L4) closed. Both `eval_expr` and `eval_ref`
now carry `decreases fuel` in `engine.ig` (SS-P03 SCC-complete fix applied).

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/types.ig ../igniter-apps/spreadsheet/engine.ig ../igniter-apps/spreadsheet/api.ig --out /tmp/spreadsheet-followup.igapp
```

Result: `status: ok`, **zero diagnostics**.

Rust recursion pressures are fully resolved.

Ruby full multi-file compile:

```bash
cd ../../../igniter-lang
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; c=IgniterLang::CompilerOrchestrator.new; p c.compile_sources(source_paths: ["../igniter-lab/igniter-apps/spreadsheet/types.ig", "../igniter-lab/igniter-apps/spreadsheet/engine.ig", "../igniter-lab/igniter-apps/spreadsheet/api.ig"], out_path: "/tmp/spreadsheet-ruby.igapp")'
```

Result: `status: oof`.

Ruby remaining diagnostics (all in `RecalculateWorkbook`, `api.ig`):

- `OOF-TY0: Unknown function: call_contract` — SS-P06
- `OOF-TY0: Type mismatch: expected Collection, got Unknown` — cascade from SS-P06
- `OOF-TY0: Unknown function: map` — SS-P05
- `OOF-TY0: Type mismatch: expected Collection, got Unknown` — cascade from SS-P05

No recursion-related diagnostics in either toolchain. The Ruby SCC gate (LAB-RUBY-FUNCTION-RECURSION-P2)
correctly accepts both `eval_expr` and `eval_ref` since both now carry `decreases fuel`.

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

### 2. Function-Level Managed Recursion — RESOLVED

`engine.ig` now declares:

```igniter
def eval_expr(expr: Expr, grid: Grid) -> CellValue decreases fuel { ... }
def eval_ref(ref_id: Text, grid: Grid) -> CellValue decreases fuel { ... }
```

Both Rust and Ruby accept this without recursion diagnostics. The Rust SCC gate
(LAB-FUNCTION-RECURSION-P4) and Ruby SCC gate (LAB-RUBY-FUNCTION-RECURSION-P2) both
correctly identify `{eval_expr, eval_ref}` as a mutual SCC and require evidence from all members.

Status: **resolved**.

Pressure registry entry: `SS-P02`.

---

### 3. Mutual Recursion SCC Policy — RESOLVED

`eval_expr` and `eval_ref` form a mutual recursive SCC. The accepted rule (proved in
LAB-FUNCTION-RECURSION-P3 and implemented in P4/Ruby-P2): every member of a nontrivial
SCC must carry `decreases fuel`. Both functions carry it; both toolchains accept the module.

Previously: only `eval_expr` was identified (self-call gap). Now: both members are required by
the SCC gate, and both are annotated (SS-P03 SCC-complete fix, not just SS-P02 minimal).

Status: **resolved**.

Pressure registry entry: `SS-P03`.

---

### 4. Option / Nullable Arithmetic — Now Unblocked

The evaluator attempts:

```igniter
left_val.num_val + right_val.num_val
```

where `num_val` is `Float?`. With recursion resolved, Rust now compiles the full module with
`status: ok` and does not flag this expression. Rust may be lenient about `Float? + Float?`, or
it may be treating the result as Unknown and propagating silently. Either way, this is now a live
Rust leniency signal or a genuine unblocked pressure.

Ruby does not yet surface this because SS-P05 (`map`) and SS-P06 (`call_contract`) block the
`CalculateGrid` contract before the Option path is exercised.

The open questions remain:
- Does Rust accept `Option[Float] + Option[Float]` silently? If so, is that correct?
- Will Ruby surface an error once `map` is available?
- Unwrap required? Error propagation? Helper needed?

Status: **active** (recursion no longer masks it in Rust).

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

| Rank | Pressure | Status | Why |
|---:|---|---|---|
| ~~1~~ | ~~Function-level managed recursion~~ | **resolved** | `decreases fuel` on `eval_expr`; Rust and Ruby clean. |
| ~~2~~ | ~~Mutual recursion SCC policy~~ | **resolved** | `decreases fuel` on `eval_ref`; SCC-complete. Both toolchains accept. |
| 1 | Collection `map` parity | active | Ruby: `Unknown function: map`. Blocks `CalculateGrid` in Ruby. |
| 2 | Option/nullable arithmetic | active | Rust accepts `Float? + Float?` silently (leniency or gap). Ruby does not reach it yet. |
| 3 | Stringly `call_contract` | design pressure | `api.ig` uses `call_contract("CalculateGrid", grid)`. Route through typed refs/forms. |
| 4 | Inline record/block ambiguity | historical | Needs fresh minimized proof before reopening. |

---

## Recommended Next Routes

1. **LAB-STDLIB-COLLECTION-P1**
   `map`/collection helper parity, especially over recursive record shapes.
   Unblocks `CalculateGrid` in Ruby and closes SS-P05.

2. **LAB-STDLIB-OPTION-P1**
   Nullable arithmetic / Option helpers. Recursion no longer blocks evaluation;
   Rust may be silently accepting `Float? + Float?`. Ruby will surface this once `map` is available.

3. **Typed-ref/forms migration route**
   Later replacement for stringly `call_contract` in `api.ig`. Not urgent while SS-P05 remains open.

4. **LAB-PARSER-RECORD-LAMBDA-P1**
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
