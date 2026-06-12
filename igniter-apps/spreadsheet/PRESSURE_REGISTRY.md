# Spreadsheet Pressure Registry

**Date:** 2026-06-12  
**App:** `igniter-lab/igniter-apps/spreadsheet`  
**Purpose:** compact registry of language/compiler pressures surfaced by the spreadsheet domain fixture.

This registry is evidence routing, not implementation authority.

---

## Pressure Entries

| ID | Pressure | Current Evidence | Status | Suggested Route |
|---|---|---|---|---|
| SS-P01 | Recursive structural record types | Rust `types.ig` compiles; `Expr` contains `Expr?` fields. | positive / guard | Keep as regression evidence. |
| SS-P02 | Function-level managed recursion | `decreases fuel` added to `eval_expr`. Rust and Ruby both accept. | **resolved** | Closed by LAB-FUNCTION-RECURSION-P4 (Rust) + LAB-RUBY-FUNCTION-RECURSION-P2 (Ruby). |
| SS-P03 | Mutual recursion SCC policy | `decreases fuel` added to `eval_ref` (SCC-complete). Both toolchains accept. | **resolved** | Closed by same SCC implementation. All SCC members now carry evidence. |
| SS-P04 | Option / nullable arithmetic | Recursion no longer blocks. Rust accepts `Float? + Float?` silently. Ruby does not reach this path (blocked by SS-P05/SS-P06). | **active** | `LAB-STDLIB-OPTION-P1` |
| SS-P05 | Collection `map` parity | Ruby reports `Unknown function: map`; Rust reaches recursion after `map` context. | active | `LAB-STDLIB-COLLECTION-P1` |
| SS-P06 | Stringly composition | `api.ig` uses `call_contract("CalculateGrid", grid)`. | design pressure | typed-ref/forms migration route |
| SS-P07 | Inline record literal vs block ambiguity | Historical report; current fixture does not exercise it. | historical / needs fresh proof | `LAB-PARSER-RECORD-LAMBDA-P1` if reopened |

---

## Evidence Commands

Rust type-only compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/types.ig --out /tmp/spreadsheet-types.igapp
```

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/types.ig ../igniter-apps/spreadsheet/engine.ig ../igniter-apps/spreadsheet/api.ig --out /tmp/spreadsheet-full.igapp
```

Ruby full multi-file compile:

```bash
cd ../../../igniter-lang
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; c=IgniterLang::CompilerOrchestrator.new; p c.compile_sources(source_paths: [\"../igniter-lab/igniter-apps/spreadsheet/types.ig\", \"../igniter-lab/igniter-apps/spreadsheet/engine.ig\", \"../igniter-lab/igniter-apps/spreadsheet/api.ig\"], out_path: "/tmp/spreadsheet-ruby.igapp")'
```

---

## Routing Notes

- SS-P02 and SS-P03 are resolved. Both `eval_expr` and `eval_ref` carry `decreases fuel`. Rust compiles clean.
- SS-P04 is now unblocked. Rust accepts `Float? + Float?` without error (may indicate Rust leniency or a genuine gap). Ruby does not yet surface it due to SS-P05/SS-P06 blocking first.
- SS-P05 remains the next active Rust/Ruby parity pressure: `map` is unknown in Ruby; Rust does not error.
- SS-P06 belongs to typed-ref/forms composition work, not recursion.
- SS-P07 should not be treated as active without a minimal current parser fixture.

## Fresh Evidence (2026-06-12)

Rust full multi-file after fix:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/spreadsheet/types.ig ../igniter-apps/spreadsheet/engine.ig ../igniter-apps/spreadsheet/api.ig --out /tmp/spreadsheet-followup.igapp
```

Result: `status: ok`, zero diagnostics.

Ruby full multi-file after fix:

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

No recursion-related diagnostics in either toolchain.
