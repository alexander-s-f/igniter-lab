# LAB-SRCMAP-P1 — Agent Return Packet

Source-map substrate: stable `node_id` + source span metadata threaded from the Rust lexer/parser through SemanticIR emission, with a durable `sourcemap.json` artifact.

---

## Status

**Complete.** 61/61 proof checks pass.

---

## Changed Files

### Rust Compiler (igniter-lab/igniter-compiler/src/)

- **`lexer.rs`** — Added exported `Span` struct (v0 source location concept; not yet used by the main token stream, but establishes the shared type).

- **`parser.rs`** — Additive changes only:
  - Added `SpanEntry` struct and `SpanEntry::at()` constructor
  - Added `span_table: Vec<SpanEntry>`, `current_contract: String`, `current_decl: String` to `Parser` struct
  - Added `record_span()` helper
  - Instrumented 12 node types: `parse_contract_decl`, `parse_type_decl`, `parse_variant_decl_top`, `parse_body_decl` (input/output/compute), `parse_compute_decl`, `parse_array_literal`, `parse_record_or_block`, `parse_postfix` (field_access + call), `parse_primary` (match_expr + variant_construct)

- **`emitter.rs`** — Additive changes only:
  - Added `node_id` field to compute SIR nodes in `typed_node()`
  - Added `node_id` field to input/output ports in `typed_ports()`
  - Added `node_id` field to `variant_declarations` entries in `emit_typed()`
  - Added `source_map: Option<Value>` to `EmitResult`
  - Added `build_sourcemap(&self, typed, span_table) -> Value` method
  - Added `span_entry_sir_path()` helper (JSONPath-style path generation)

- **`assembler.rs`** — Added sourcemap sidecar write: if `emit_result.source_map` is `Some`, writes `sourcemap.json` inside the `.igapp` directory and adds `sourcemap_ref` to `manifest.json`.

- **`main.rs`** — Extracts `span_table` via `std::mem::take(&mut parser.span_table)` after parse; calls `emitter.build_sourcemap(&typed, &span_table)` in the ok path before assembly.

### Fixtures (igniter-view-engine/fixtures/source_map/)

- **`srcmap_basic_contract.ig`** — `type Point`, `pure contract ComputeDistance` with arithmetic field-access expressions. Covers: contract, type, input, output, compute, field_access.

- **`srcmap_nested_record.ig`** — `type Source`, `pure contract BuildQueryPlan` with record literal, `split()` call, and array literal. Covers: type, contract, input, output, compute, record_literal, call, array_literal.

- **`srcmap_variant_match.ig`** — `variant Status`, `contract CheckStatus` with match expression and variant construct. Covers: variant, contract, input, output, compute, match_expr, variant_construct.

- **`srcmap_error_fixture.ig`** — Malformed contract with missing type annotations. Produces parse errors; verifies no `sourcemap.json` is written on failure.

### Proof Runner

- **`igniter-view-engine/proofs/verify_lab_srcmap_p1.rb`** — 61 checks across 8 sections.

### Lab Doc

- **`igniter-lab/lab-docs/ide/lab-rust-source-map-node-span-to-semanticir-v0.md`** — Full design record.

---

## Proof Results

```
61/61 PASS    0 FAIL

SRCMAP-COMPILE:     All positive fixtures compile clean.
SRCMAP-SCHEMA:      sourcemap.json shape correct (srcmap-v0).
SRCMAP-COVERAGE:    All 12 node_kind values present.
SRCMAP-SIR-LINK:    node_id in sourcemap matches SIR nodes.
SRCMAP-STABILITY:   Identical source → identical sourcemap.
SRCMAP-NONSEMANTIC: SIR semantics unchanged; node_id additive only.
SRCMAP-ERROR:       Error fixture → no sourcemap written.
SRCMAP-CLOSED:      VM/bytecode/opcodes untouched.
```

---

## Design Decisions

**span_table as Vec (not embedded in AST):** Adding position to `Expr`, `BodyDecl`, and `TypedDecl` structs would have broken every pattern match across classifier, typechecker, and emitter. The flat `Vec<SpanEntry>` approach is purely additive and requires no changes to existing match arms.

**Dotted stdlib call constraint:** `stdlib.numeric.subtract` tokenizes as a FieldAccess chain, not a single `Ref`. The parser's call detection requires `Expr::Ref { name }` before `(`. Fixtures use arithmetic operators and bare single-identifier calls (`split`, `range`) instead. Documented for LAB-SRCMAP-P2.

**First-occurrence deduplication:** The `build_sourcemap()` method de-duplicates by `node_id`, keeping first occurrence. This handles cases where `field_access:C.D@L12` might be recorded multiple times within a single complex expression.

**node_id is additive:** The field is inserted alongside existing SIR fields (`kind`, `name`, `expr`, `type`, `deps`). No existing field is renamed or removed. The `SRCMAP-NONSEMANTIC` proof section verifies this.

---

## Closed Surfaces (Confirmed Untouched)

- IDE UI / Tauri / Svelte
- VM trace / stepper / breakpoints
- Bytecode, opcodes, Value enum
- VM execution pipeline
- Ruby canon (igniter-lang)
- Language grammar
- Runtime semantics
