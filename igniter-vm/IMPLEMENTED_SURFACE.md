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

## Runtime / execution (the live language path)

Verified end-to-end 2026-06-15: `igniter-compiler` (Rust front-end) emits a
SemanticIR `.igapp`; `igniter-vm` runs it. Proof: `Add(a=2,b=3)` →
`{"result":5,"status":"success","latency_us":154}` via the release binary.

| Capability | Status | Anchor / how |
|---|---|---|
| one-shot run | ✅ | `igniter-vm run --contract <app.igapp> --inputs in.json [--entry N] [--as-of T] [--json]` (`main.rs`) |
| input model | ✅ | reads `semantic_ir_program.json` + `manifest.json` from an `.igapp` dir (not `.ig` source) |
| temporal as_of | ✅ | `--as-of` injects temporal coordinate; `OP_LOAD_AS_OF` |
| TBackend binding | ✅ | `--tbackend`; `MemoryHistoryBackend` (zero-dep) / `LedgerTcpBackend` (`tbackend.rs`) |
| reactive projection loop | ✅ | `pipeline.rs` — webhook trigger → execute → commit bitemporal fact |
| execution trace | ✅ | `igniter-vm trace <app> --entry N --inputs in.json` (IDE/debug substrate) |
| bytecode source-map | ✅ | `igniter-vm bytecode-map <app>` |
| compiled example apps | ✅ | `igniter-compiler/out/*.igapp` (add, decimal_contract, availability_projection, tenant_availability_projection, vendor_lead_pipeline, …) |
| recursive self-call / TCO | ⛔ v0 hold | `call_contract` dispatches with depth-guard; self-recursion/cycles closed in v0 (ledger D-007) |
| single `source → run` command / REPL | ❌ missing | two-step (compile then run); the main DX gap for "live" |

## Runtime wave — CLOSED 2026-06-15 (RUN-OK 1 → 18)

Full arc + per-fix detail: `.agents/work/cards/lang/LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1.md`.

Resolved this wave (all in `igniter-vm`, + one typechecker relax): stdlib collection
ops (namespaced→bare HOF aliases); `integer.{lt,gt,lte,gte}` + `collection.append` +
`string.concat`/lenient `collection.concat`; **dispatch unification** (`VM::call_contract_value`
single-sourced; `&VM` threaded into `eval_ast`/`eval_lambda`); field_access generalized;
`MAX_CALL_DEPTH` 8→64; **closures (B)** + aggregate-source-ref; `if_expr` dual-shape +
dispatch-table completeness + `filter_map`; **`match_expr` in `eval_ast`**; homogeneous
numeric relax (typechecker).

**Cross-cutting root, now CLOSED:** nearly every gap was `eval_ast` (the tree-walker
for lambda/HOF bodies) lagging the bytecode path on a node kind — `call_contract`,
`if_expr`, `stdlib.*`, `match`. The two paths are now near-parity. Future
"X not found in eval_ast" is a *known class*, not a new mystery.

### Remaining non-green — by owner (NOT a shared VM bug)

| class | apps | owner |
|---|---|---|
| needs-inputs / demo-entry | advanced_logistics, spreadsheet, vector_editor, erp_logistics, igniter_parser | `LAB-APP-DEMO-ENTRY-WAVE-P1` (app-side) |
| Decimal policy → construct | bookkeeping | `LAB-NUMERIC-DECIMAL-BOUNDARY-P1` → `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` |
| governance-gated | rule_engine | `LAB-DYNAMIC-CONTRACT-DISPATCH` DEFER (ledger D-001) |
| tiny stdlib tail | igniter_parser | `LAB-STDLIB-STRING-CHAR-AT-VM-P1` |

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
