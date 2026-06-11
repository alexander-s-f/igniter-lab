# LAB-STDLIB-INVENTORY-SUBTASK-GEMINI v0

**Track:** stdlib-like-name-rg-inventory-v0
**Route:** FAST RESEARCH SUBTASK / INVENTORY ONLY
**Status:** CLOSED
**Date:** 2026-06-11

## 1. Summary
- **Total files scanned:** >17,000 matches across `igniter-lang`, `igniter-lab`, `igniter-gov` (using broad ripgrep scan).
- **Total stdlib-like names found:** 40+ unique helpers/builtins detected.
- **Top drift risks:** 
  - `datetime` operations: `parse_datetime`/`format_datetime` (Rust) vs expected `stdlib.date` canonical names.
  - `map` operations: Bare aliases (`map_get`, `map_has_key`) used heavily alongside qualified `stdlib.map.*` names.
  - Epistemic outcomes (`unknown_external_state`, `timed_out`) exist as stringly-typed `kind` values in fixtures rather than canonical stdlib types.

## 2. Inventory Table

| Name | Category Guess | Status | File | Evidence Snippet / Note | Confidence |
|---|---|---|---|---|---|
| `stdlib.text.*` | Text Core | rust-lab / production-ruby | `igniter-vm/src/vm.rs`, `igniter_lang/typechecker.rb` | Handled explicitly in VM/Typecheckers (e.g., `stdlib.text.starts_with`) | High |
| `starts_with`, `ends_with` | Text Core | inconsistent | `igniter-vm/src/vm.rs` | Bare aliases supported alongside qualified `stdlib.text.*` | High |
| `map_get`, `map_has_key` | Map Core | inconsistent | `igniter_lang/typechecker.rb`, `typechecker.rs` | Typecheckers map these bare aliases directly to `stdlib.map.get` | High |
| `map_from_pairs` | Map Core | production-ruby | `igniter_lang/typechecker.rb` | Handled in `infer_map_from_pairs` | High |
| `array_literal` | Collection | production-ruby | `igniter_lang/typechecker.rb`, `parser.rs` | Emitted by parser, typechecker infers as Collection[T] | High |
| `parse_datetime`, `format_datetime` | Temporal | rust-lab | `igniter-compiler/src/typechecker.rs` | Explicit match arm requiring 2 arguments | High |
| `stdlib.integer.add/gt` | Numeric | production-ruby | `igniter-lang/out/add.igapp/...` | Canonical IR lowering of operators | High |
| `stdlib.option.wrap` | Monadic | production-ruby | `igniter-lang/out/conformance/...` | Extracted from monadic_extension proofs | High |
| `unknown_external_state` | Epistemic Outcome | fixture-only | `igniter-view-engine/fixtures/failure_taxonomy/...` | Used as stringly-typed `kind` in KDR/epistemic proofs | Medium |
| `timed_out` | Epistemic Outcome | fixture-only | `igniter-view-engine/fixtures/...` | Used as stringly-typed `kind` | Medium |
| `query_error`, `system_error` | Domain Errors | fixture-only | `igniter-view-engine/fixtures/...` | Seen in Rack/Sidekiq/Failure Taxonomy proofs | Medium |

## 3. Dispatch / Implementation Sites

### Ruby TypeChecker (`igniter-lang/lib/igniter_lang/typechecker.rb`)
- Has dedicated static maps/cases for: `starts_with`, `ends_with`, `map_get` (mapped to `stdlib.map.get`), `map_has_key`, `map_from_pairs`.
- Lowers bare string manipulation to `stdlib.text.*` equivalents.

### Rust TypeChecker (`igniter-lab/igniter-compiler/src/typechecker.rs`)
- Giant `match` statement on `fn_name.as_str()`.
- Captures: `contains`, `starts_with`, `ends_with` and forces them towards `stdlib.text.*`.
- Explicitly handles `parse_datetime`, `format_datetime`.
- Resolves `map_get` / `stdlib.map.get` signatures (`Map[String, V], String -> Option[V]`).

### Rust VM/Compiler (`igniter-lab/igniter-vm/src/vm.rs`)
- OP_CALL handling explicitly intercepts `stdlib.text.starts_with`, `stdlib.text.split`, `stdlib.text.byte_length`, etc., as well as their bare alias counterparts.
- Implements strict runtime arity checking and validation (e.g. `split` empty delimiter is an operational error).

## 4. Drift / Mismatch List
- **`map_get` vs `stdlib.map.get`:** Both the Rust and Ruby toolchains carry explicit logic to support both bare aliases and fully qualified names.
- **`parse_datetime` / `format_datetime`:** These names are hardcoded in the Rust TypeChecker, but `RES-001` notes Ch8 specifies `add_duration`, `diff`, `as_of`.
- **Stringly-typed Outcomes:** `unknown_external_state`, `timed_out` are heavily used in `igniter-view-engine` fixtures as primitive string `kind` properties instead of stdlib-level envelope types.

## 5. Candidate Blind Spots
- **Missing Categories:** Numeric coverage (e.g., math ops like `abs`, `min`, `max`, `round`, `floor`, `ceil`) does not have dedicated standard library handlers in the extracted typechecker snippets, implying they might fall back on `stdlib.integer.*` primitives or be completely absent/proof-local.
- **High-Signal Helpers for `LAB-STDLIB-FOUNDATION-P1`:**
  - `array_literal` type inference mechanics.
  - The legacy handler bridging logic for bare strings (`starts_with` -> `stdlib.text.starts_with`).
  - The epistemic outcomes used in ViewEngine proofs (`unknown_external_state`) — these are critical missing sum-types that need formal `stdlib.outcome` treatment.
