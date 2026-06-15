# igniter-vm — Implemented Surface

**Status:** live implementation index (bytecode compiler + opcodes)
**Verify-first rule:** any doc claim that one of these is "not implemented",
"deferred", or "blocked" is **stale** — this file + a source grep are ground truth.
Last verified against source: **2026-06-15**.

> Scope: this crate owns bytecode lowering (`src/compiler.rs`) and the opcode set
> (`src/instructions.rs`). Front-end surfaces (parse / classify / typecheck) live in
> `igniter-compiler` and get their own surface index later.

## Expression-kind lowering (`src/compiler.rs::compile_expr`)

| Surface | Status | Code anchor | Opcode | Proof / regression | Notes |
|---|---|---|---|---|---|
| unary op | ✅ implemented | `compiler.rs:590-605` | `OP_NOT 0x1C` / `OP_NEG 0x21` | `igniter-compiler/verify_unary_operators_p4.rb` | `!`, `-` |
| array literal | ✅ implemented | `compiler.rs:608-613` | `OP_PUSH_ARRAY 0x1E` | `igniter-compiler/verify_compiler.rb` (suite) | element_count arg |
| record literal | ✅ implemented | `compiler.rs:616-628` | `OP_PUSH_RECORD 0x1F` | `igniter-compiler/verify_compiler.rb` (suite) | deterministic key sort |
| concat | ✅ implemented | `compiler.rs:631-636` (+ `:302`) | `OP_CONCAT 0x1D` | `igniter-compiler/verify_str_core.rb` | also via binary `++` |
| let binding | ✅ implemented | `compiler.rs:639-661` | `OP_STORE_REG 0x03` / `OP_LOAD_REG 0x04` | `igniter-compiler/verify_compiler.rb` (suite) | register alloc + body |
| lambda / fn | ✅ implemented | `compiler.rs:664-667` | `OP_PUSH_LIT 0x01` | `igniter-compiler/verify_hof_lambda_error_propagation_p2.rb` | serialized; consumed by HOF ops |
| variant construct | ✅ implemented | `compiler.rs:677+` | `OP_PUSH_RECORD` (+`__arm`) | — | LAB-VARIANT-VM-P1 |

## Operators & opcodes (`src/compiler.rs` binary/call · `src/instructions.rs`)

| Surface | Status | Code anchor | Opcode | Notes |
|---|---|---|---|---|
| comparison `< <= >= !=` | ✅ implemented | `compiler.rs:296-299` | `OP_LT/LE/GE/NE 0x16-0x19` | also in call form `:336-339` |
| logic `&& ||` | ✅ implemented | `compiler.rs:300-301` | `OP_AND/OR 0x1A-0x1B` | |
| named call `fn(args)` | ✅ implemented | `compiler.rs:343-345` | `OP_CALL 0x20` | fallback when not a builtin op |
| HOF `map/filter/fold/reduce` | ✅ implemented | `compiler.rs:307-346` | (lambda + op dispatch) | consumes lambda literal |
| opcode definitions | ✅ present | `instructions.rs:28-39` | `0x16`–`0x21` | full comparison/logic/collection/call set |

## Provenance

These surfaces were the stale claims in `igniter-lab/lab-docs/igniter-delta-1.md`
(cat.1 "missing opcodes", cat.3 "compiler missing expression kinds"), proven
**already implemented** during reconcile pass 1. Closed ledger rows:
`igniter-gov/delta-ledger-history.md` → **D-003a** (opcodes), **D-006** (expression
kinds).

## Maintenance

When a surface lands or changes, add/update its row here in the same commit as the
code. This file is the crystallized answer to "does X exist?" — keep it as current
as the code it indexes. Projection: `igniter-gov/projects/igniter-vm.md`.
