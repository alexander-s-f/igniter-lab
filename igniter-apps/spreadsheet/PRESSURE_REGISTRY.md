# Spreadsheet Pressure Registry

**Date:** 2026-06-11  
**App:** `igniter-lab/igniter-apps/spreadsheet`  
**Purpose:** compact registry of language/compiler pressures surfaced by the spreadsheet domain fixture.

This registry is evidence routing, not implementation authority.

---

## Pressure Entries

| ID | Pressure | Current Evidence | Status | Suggested Route |
|---|---|---|---|---|
| SS-P01 | Recursive structural record types | Rust `types.ig` compiles; `Expr` contains `Expr?` fields. | positive / guard | Keep as regression evidence. |
| SS-P02 | Function-level managed recursion | Rust full multi-file: `eval_expr` must specify `decreases fuel`. | active | `LAB-FUNCTION-RECURSION-P1` |
| SS-P03 | Mutual recursion policy | `eval_expr` and `eval_ref` form a recursive evaluator pair. | active | `LAB-FUNCTION-RECURSION-P1` |
| SS-P04 | Option / nullable arithmetic | `Float? + Float?` path exists but is blocked behind recursion first. | pending | `LAB-STDLIB-OPTION-P1` |
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

- SS-P02 and SS-P03 should stay together: self-recursion and mutual recursion are one evaluator problem here.
- SS-P04 should wait until recursion no longer blocks the evaluator path.
- SS-P05 can proceed independently as collection stdlib parity, but spreadsheet gives a good future regression fixture.
- SS-P06 belongs to typed-ref/forms composition work, not recursion.
- SS-P07 should not be treated as active without a minimal current parser fixture.
