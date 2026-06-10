# Lab: Rust Source Map — Node Span to SemanticIR v0

**Track:** LAB-SRCMAP-P1  
**Status:** Complete  
**Authority:** lab_only — not canon, not production

---

## Purpose

This document records the design and implementation decisions for the first honest source-map substrate in the Igniter Rust compiler. The output is a durable `sourcemap.json` artifact that maps source ranges to SemanticIR nodes.

This is the keystone for the debugger track: LAB-SRCMAP-P1 → LAB-SRCMAP-P2 → LAB-VMTRACE-P1 → LAB-IDE-STEP-P1 → LAB-TEXTBOOK-P1.

---

## Span Provenance Gap

Before this work: the lexer captured `Token.line` and `Token.col` for every token, but the parser dropped all position information. `Instruction{opcode, args}` had no provenance. SemanticIR nodes had no stable identity.

After this work: position is threaded from token to parser `SpanEntry`, then assembled into `sourcemap.json` as a sidecar artifact alongside the `.igapp` directory.

---

## Design: SpanEntry / span_table

The parser accumulates a `Vec<SpanEntry>` as it parses. Each entry is appended at the point where a token's position is still available (before the token is consumed). The span_table is extracted after `parser.parse()` via `std::mem::take(&mut parser.span_table)`.

```rust
pub struct SpanEntry {
    pub node_id: String,
    pub kind: String,
    pub start_line: usize,
    pub start_col: usize,
    pub end_line: usize,    // 0 = not tracked in v0
    pub end_col: usize,     // 0 = not tracked in v0
}
```

Key design choice: the span_table is a flat Vec (not embedded in AST nodes). This avoids perturbing every pattern match on `Expr`, `BodyDecl`, and `TypedDecl` — which would have required touching hundreds of match arms across classifier, typechecker, and emitter.

---

## Deterministic node_id Scheme

Stable IDs that survive whitespace changes and line-number drift:

| node kind | node_id format |
|-----------|----------------|
| contract | `contract:Name` |
| type | `type:Name` |
| variant | `variant:Name` |
| input | `input:Contract.Name` |
| output | `output:Contract.Name` |
| compute | `compute:Contract.Name` |
| record_literal | `record_literal:Contract.Decl@L{line}` |
| array_literal | `array_literal:Contract.Decl@L{line}` |
| field_access | `field_access:Contract.Decl@L{line}` |
| call | `call:Contract.Decl@L{line}` |
| match_expr | `match:Contract.Decl@L{line}` |
| variant_construct | `variant_construct:Contract.Decl@L{line}` |

Declaration-level IDs (contract, type, variant, input, output, compute) use only the name — these are 1:1 with source declarations and stable across edits elsewhere.

Expression-level IDs (record_literal, array_literal, field_access, call, match_expr, variant_construct) use `@L{line}` as a disambiguation suffix. First occurrence wins in de-duplication.

---

## v0 Span Accuracy

- **Declaration spans**: exact — captured at the keyword or name token start position.
- **Expression spans**: best-effort — captured at the delimiter token start position (opening `{`, `[`, `.`, `(`, `match`).
- **End positions**: absent in v0 — `end_line` and `end_col` are always 0.

The `provenance_note` field in the sourcemap documents this:
```
"v0: declaration spans exact (token-start of name); expression spans best-effort
     (token-start of delimiter); end positions absent (not tracked in v0)"
```

---

## Parser Context State

Two fields track enclosing scope during expression parsing:

```rust
pub struct Parser {
    // ... existing fields ...
    pub span_table: Vec<SpanEntry>,
    current_contract: String,    // set at contract entry, cleared at contract exit
    current_decl: String,        // set at compute name, used for expression scope
}
```

Expression-level span recording is gated on `!current_contract.is_empty() && !current_decl.is_empty()`. This ensures expression spans are only recorded inside named compute declarations within named contracts.

---

## node_id in SemanticIR

Three places in the emitter add `node_id` to SIR JSON:

1. **Compute nodes** (`typed_node`, kind="compute"): `node_id = "compute:{contract_name}.{decl_name}"`
2. **Input/output ports** (`typed_ports`): `node_id = "{kind}:{contract_name}.{decl_name}"`
3. **variant_declarations** (`emit_typed`): `node_id = "variant:{name}"`

The `node_id` field is additive — it does not replace or rename any existing SIR field.

---

## sourcemap.json Structure

```json
{
  "schema_version": "srcmap-v0",
  "source_file": "path/to/source.ig",
  "module": "Module.Name",
  "nodes": [
    {
      "node_id": "compute:ContractName.decl_name",
      "kind": "compute",
      "sir_path": "$.contracts[?(@.contract_name=='ContractName')].nodes[?(@.name=='decl_name')]",
      "source_span": {
        "start_line": 12,
        "start_col": 3
      }
    }
  ],
  "provenance_note": "..."
}
```

The `sir_path` field uses JSONPath filter notation to locate the corresponding node in `semantic_ir_program.json`. This is the structural link between the two artifacts.

---

## sir_path Scheme

| node_id prefix | sir_path pattern |
|----------------|-----------------|
| `contract:N` | `$.contracts[?(@.contract_name=='N')]` |
| `type:N` | `$.type_env['N']` |
| `variant:N` | `$.variant_declarations[?(@.name=='N')]` |
| `input:C.N` | `$.contracts[?(@.contract_name=='C')].inputs[?(@.name=='N')]` |
| `output:C.N` | `$.contracts[?(@.contract_name=='C')].outputs[?(@.name=='N')]` |
| `compute:C.N` | `$.contracts[?(@.contract_name=='C')].nodes[?(@.name=='N')]` |
| expression `C.D@L{n}` | `$.contracts[?(@.contract_name=='C')].nodes[?(@.name=='D')].expr.{kind}` |

---

## Implementation Constraint: Dotted Stdlib Calls

The lexer only includes dots in identifiers when the segment after `.` is PascalCase (uppercase first char) or the specific `stdlib.IO` prefix. As a result, `stdlib.numeric.subtract` tokenizes as `stdlib` `.` `numeric` `.` `subtract` — three separate tokens with two `Dot` tokens between them.

The parser's call detection requires `Expr::Ref { name }` immediately before `(`. A dotted path (`FieldAccess` chain) does not satisfy this. Thus `stdlib.numeric.subtract(x, y)` fails to parse as a call — the `(` is left unconsumed and triggers a body-declaration error.

**v0 fixture resolution**: all four fixtures use arithmetic operators (`+`, `-`, `*`) and bare single-identifier calls (`split`, `range`) that the parser and typechecker handle correctly. This constraint is documented for LAB-SRCMAP-P2 resolution.

---

## Files Modified

**Authorized writes only:**

- `igniter-compiler/src/lexer.rs` — added `Span` struct export
- `igniter-compiler/src/parser.rs` — added `SpanEntry`, `span_table`, `current_contract`, `current_decl`, span recording at 12 node types
- `igniter-compiler/src/emitter.rs` — added `node_id` to SIR, `build_sourcemap()`, `span_entry_sir_path()`
- `igniter-compiler/src/assembler.rs` — writes `sourcemap.json` sidecar, adds `sourcemap_ref` to manifest
- `igniter-compiler/src/main.rs` — extracts span_table, calls `build_sourcemap()`
- `igniter-view-engine/fixtures/source_map/` — 4 fixtures
- `igniter-view-engine/proofs/verify_lab_srcmap_p1.rb` — 61-check proof runner

**Closed surfaces (not modified):**

- IDE UI / Tauri / Svelte
- VM trace / stepper / breakpoints
- Bytecode, opcodes, Value enum
- VM execution pipeline
- Ruby canon (igniter-lang)
- Language grammar
- Runtime semantics

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
