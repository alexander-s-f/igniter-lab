# DataFrames Pressure Registry

This registry tracks language and stdlib pressure from the `dataframes` app. The app models matrices in COO form and dataframes in long form, then records where flat collection operations are sufficient and where relational operations are missing.

## Baseline

Rust compilation currently succeeds for:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/dataframes/types.ig ../igniter-apps/dataframes/matrix.ig ../igniter-apps/dataframes/dataframe.ig ../igniter-apps/dataframes/example.ig --out /tmp/dataframes.igapp
```

Fresh observed result: all stages complete, 8 contracts emit, and diagnostics are empty. Current source hash: `sha256:61e705b88646fab28cee835a69a92bc9c0bb2f57e32e9bc554e750862e6aa6a4`. Liveness counters are small (`typechecker.infer_expr.max_depth=8`, `form_resolver.walk_expr.max_depth=8`). This baseline should be frozen by a dedicated proof card before being used as regression evidence.

## Pressures

| ID | Name | Evidence | Status | Next route |
|---|---|---|---|---|
| DF-P01 | Dataframes Rust baseline | Wave recheck: Rust still CLEAN (0 diagnostics) | Positive, needs frozen proof | `LAB-DATAFRAMES-BASELINE-P1` |
| DF-P02 | COO unary matrix operations | `MatrixTranspose` and `MatrixScale` are expressible as pure `map` transforms over `Cell` | Positive | Keep as collection-HOF fixture evidence |
| DF-P03 | Relational membership | Filtering one long-format dataframe slice and applying the resulting row IDs to another slice needs Bool membership (`contains` / `any` / `exists`) | Active | `LAB-STDLIB-COLLECTION-CONTAINS-P1` |
| DF-P04 | READY | Empty / non-empty guards | `is_empty`/`non_empty` now available (LANG-STDLIB-IS-EMPTY-PROP-P3/P4 CLOSED); filter-then-empty-check pattern is now implementable; app doesn't yet use it | App can use `filter + is_empty` pattern |
| DF-P05 | Relational collection algebra | Matrix addition and dataframe row filtering need `join`, `group_by`, or `flat_map`; flat `map`/`filter` is not enough | Active, larger design | `LAB-STDLIB-RELATIONAL-COLLECTIONS-P1` |
| DF-P06 | Lambda record literal ambiguity | `map(cells, c -> { row: c.col, col: c.row, val: c.val })` parses `{` as a block, not a record literal | Active parser pressure | `LAB-LAMBDA-RECORD-LITERAL-P1` |
| DF-P07 | Contract invocation workaround | Record construction inside lambdas is moved into helper contracts and invoked through `call_contract` | Active bridge pressure | Typed invocation / forms route; call_contract parity |
| DF-P08 | RESOLVED | Ruby call_contract parity | Wave P2: 8 diagnostics (6× `Unknown function: call_contract`, 2× `Unresolved symbol`). Wave P3: all 6 call_contract errors gone; `LAB-RUBY-CALL-CONTRACT-PARITY-P3` CLOSED; Ruby TC `when "call_contract"` arm handles dispatch | `LAB-RUBY-CALL-CONTRACT-PARITY-P3` CLOSED |
| DF-P09 | RESOLVED | Ruby emitter UTF-8 encoding | LANG-EMITTER-ENCODING-P2 CLOSED — 6 encoding sites fixed; Wave P2 unstripped Ruby recheck: no JSON crash; 8 actual diagnostics surface; types.ig box-drawing chars are tolerated | `LANG-EMITTER-ENCODING-P2` CLOSED |
| DF-P10 | ACTIVE | Ruby record literal inference gap | Wave P3: 2 `Unresolved symbol` diags remain — `c00`, `p1`. Wave P4: unchanged — LANG-TYPED-COMPUTE-BINDING-P2 had no effect. Root cause re-classified: computes use unannotated record literals (`compute c00 = { row: 0, col: 0, val: 1 }`, `compute p1 = { row_id: 1, ... }`); Ruby TC returns Unknown for unannotated record literal computes | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |

## Route Notes

First wave should stay focused on already-open collection primitives: append, equality, import surface, and empty guards. Dataframes belongs to the second wave because it introduces relational algebra, not just scalar collection helpers.

Recommended order:

1. `LAB-DATAFRAMES-BASELINE-P1` to freeze the Rust-positive app baseline (still CLEAN in wave recheck).
2. Resolve call_contract parity (DF-P07/DF-P08) before attempting dataframe-specific stdlib.
3. `LAB-LAMBDA-RECORD-LITERAL-P1` to isolate parser pressure from stdlib pressure.
4. `LAB-STDLIB-COLLECTION-CONTAINS-P1` for Bool-producing membership helpers.
5. `LAB-STDLIB-RELATIONAL-COLLECTIONS-P1` for `group_by` / `join` / `flat_map` readiness.

Wave recheck summary (2026-06-12 P1): Rust CLEAN; Ruby blocked by call_contract + UTF-8 encoding issue; DF-P04 (is_empty) READY.

Wave P2 recheck (2026-06-12): Rust still CLEAN (0 diagnostics, status ok). Ruby: 8 diagnostics (6× call_contract, 2× Unresolved symbol) — DF-P09 RESOLVED (LANG-EMITTER-ENCODING-P2 fixed); unstripped run produces actual diagnostics without crash. Dominant Ruby blocker: call_contract parity (DF-P08).

Wave P3 recheck (2026-06-13): Rust: CLEAN (0 diagnostics). Ruby: 2 diagnostics (`Unresolved symbol: c00`, `Unresolved symbol: p1`). DF-P08 RESOLVED — LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED; all 6 call_contract errors gone. Remaining: 2 unresolved symbols from typed compute binding gap (DF-P10).

## Wave P5 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged from Wave P4. Ruby: oof / 2 diagnostics — unchanged from Wave P4. LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had zero effect: DF-P10 computes (`c00`, `p1`) are unannotated record literals — P2 only activates for `compute name : Type = { ... }` annotated forms. DF-P10 (ACTIVE_TRUE_INTERMEDIATE): 2 unannotated record literal computes still Unknown. No new pressures.

## Wave P4 Recheck Summary (2026-06-13)

Rust: CLEAN (ok / 0 diagnostics). Ruby: oof / 2 diagnostics — unchanged from Wave P3. LANG-TYPED-COMPUTE-BINDING-P2 had zero effect: `c00` and `p1` computes are unannotated record literals (`compute c00 = { row: 0, col: 0, val: 1 }`, `compute p1 = { row_id: 1, ... }`), not `compute name : Type = expr` annotated bindings. Root cause re-classified to `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1`. No new pressures.

## Wave P3 Recheck Summary (2026-06-13)

Rust: CLEAN (ok / 0 diagnostics). Ruby: oof / 2 diagnostics — `Unresolved symbol: c00`, `Unresolved symbol: p1`. Resolutions since Wave P2: DF-P08 RESOLVED — LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED; all 6 call_contract errors eliminated. Remaining blockers: 2 unresolved symbols — typed compute binding gap (DF-P10); call_contract output variables not registered in symbol_types; route: `LANG-TYPED-COMPUTE-BINDING-P1`.

## Non-Goals

- No dataframe package proposal is authorized by this app.
- No runtime authority, IO, or external storage claim is implied.
- No mutable HashMap or ambient indexing surface is implied.
- No walk-through artifact is tracked; durable evidence lives in this app folder only.
