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

## Known runtime gaps — fleet pressure 2026-06-15

Surfaced by running `igniter-apps/*` through `tools/igniter` (compile → run).
27 apps; 1 ran clean (`web_router`), the rest hit these gaps (priority order):

| # | gap | evidence | apps blocked |
|---|---|---|---|
| ~~1~~ | ✅ **RESOLVED 2026-06-15** — VM stdlib collection ops. Was: `OP_CALL: unimplemented 'stdlib.collection.filter'`. Fix: `vm.rs` OP_CALL now aliases `stdlib.collection.{filter,map,fold,reduce,count,range,first,last,sum,take,zip,any,all,find}` → existing bare HOF handlers, + new `stdlib.integer.{lt,gt,lte,gte}` and `stdlib.collection.append`. | RUN-OK 1→6 | unblocked job_runner, reconciler, arch_patterns, decision_tree, neural_net |
| 2 | **cross-contract dispatch** — `call_contract: no contract named X` / `call_contract expects exactly 2 operands; got 3` (arity). NOW THE TOP BLOCKER. | dsa, dataframes, lead_router | ~7 |
| 3 | **field access resolution** — `Field access not resolved` | air_combat | 1 |
| 4 | **multi-contract entry / run-profile** — only one bare `entrypoint` expressible (PROP-029 run-profiles) | vector_math, igniter_parser, … | ~6 (UX/lang, not VM) |
| 5 | front-end type errors (compiler, not VM) | bookkeeping, erp_logistics, rule_engine | 3 |

Implemented stdlib (OP_CALL) now includes the collection HOF set above. **Next
lever = #2 cross-contract dispatch** (`call_contract` callee resolution + arity).

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
