# igniter-vm — Implemented Surface

**Status:** live implementation index (bytecode compiler + opcodes)
**Verify-first rule:** any doc claim that one of these is "not implemented",
"deferred", or "blocked" is **stale** — this file + a source grep are ground truth.
Last verified against source: **2026-06-27**.
Surface refresh: **2026-06-27** doc/source grep for stdlib collection `zip`, HOF math parity,
deterministic math evidence tiers, Vec3/Mat3 package proofs, package/admission pointers, the
current formatting surface (`to_text` exact Integer/Decimal, explicit `float_to_text`, and
rune-counted `pad_left`), VM crash-safety budgets, Decimal money safety, map-lambda
`call_contract` parity, and `eval_ast` `variant_construct`.

Machine fleet note: 2026-06-27
`cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep -- --nocapture`
is **13/13 OK**. The prior 2026-06-24 HOLD is closed by `LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5`
and the compiler match-arm record-literal fix. Do not cite the old 11/13 note as current.

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
| equality `== !=` | ✅ implemented | `compiler.rs:340,355,412,427` | `OP_EQ 0x09` / `OP_NE 0x19` | compiler emits `a == b` as SIR `binary_op op:"=="` (NOT `stdlib.primitive.eq` — that is the typechecker's internal type name only); `vm.rs OP_EQ`/`eval_ast "=="` both route to `value_eq_exact` (String/Text, Integer, Bool, scale-normalized Decimal). Mismatched scalars rejected at COMPILE time (`OOF-TY0`). Proof: `tests/primitive_eq_parity_tests.rs` (`LAB-VM-PRIMITIVE-EQ-PARITY-P1`). |
| comparison `< <= >= >` | ✅ implemented | `compiler.rs:296-299,343-352` | `OP_LT/LE/GE/GT 0x16-0x18,0x10` | also in call form `:415-424`; Integer/Float/Decimal (+ String for `< <= >=`) |
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
| app-local `def` function registry | ✅ | LAB-FUNCTION-SIR-RUNTIME-P1: emitter writes a `functions` array (`function_ir`) into the SIR; `main.rs` builds `VM.functions` (`FunctionEntry{params,body}`); `eval_ast` `call` invokes registry names inside lambda bodies (bind params → fresh inputs, `MAX_CALL_DEPTH`-bounded `decreases fuel` recursion, no dynamic dispatch). Proof: `verify_lab_function_sir_runtime_p1.rb`; spreadsheet `RunWorkbookDemo` runs |
| crash-safety budgets | ✅ | `MAX_EVAL_AST_DEPTH`, `MAX_COLLECTION_ELEMENTS`, `MAX_VM_STEPS`, and checked integer arithmetic guard eval-tree depth, collection/range allocation, non-progress bytecode loops, and overflow/divide-edge cases. Proof: `LAB-IGNITER-VM-EVAL-DEPTH-AND-COLLECTION-BUDGET-P2` plus checked arithmetic tests. |
| reactive projection loop | ✅ | `pipeline.rs` — webhook trigger → execute → commit bitemporal fact |
| execution trace | ✅ | `igniter-vm trace <app> --entry N --inputs in.json` (IDE/debug substrate) |
| bytecode source-map | ✅ | `igniter-vm bytecode-map <app>` |
| compiled example apps | ✅ | `igniter-compiler/out/*.igapp` (add, decimal_contract, availability_projection, tenant_availability_projection, vendor_lead_pipeline, …) |
| recursive self-call / TCO | ⛔ v0 hold | `call_contract` dispatches with depth-guard; self-recursion/cycles closed in v0 (ledger D-007) |
| source-compiling REPL (interactive + headless) | ✅ (machine-owned) | `igniter-machine` binary `igniter-repl` (feature `repl`): `load <path.ig>` → `IgniterMachine::load_contract_source` (full front-end in-process) → `dispatch <Name> [json]`; plus headless `--script <file>` (P20) → `tests/repl_headless_smoke_tests.rs`. Corrects the prior "REPL missing" claim (`LAB-IGNITER-VM-SOURCE-RUN-REPL-READINESS-P1`). |
| non-interactive one-shot `source → result` (single command) | ❌ missing (only remaining gap) | the `.ig`+contract+JSON → stdout-result-JSON ergonomic for CI/scripting; today expressible as a 2-line `igniter-repl --script`. First impl card `LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2` (machine-owned, reuses `load_contract_source`+`dispatch`, pure-dispatch, no dynamic dispatch). `igniter-vm` still runs only compiled `.igapp`. |

## Stdlib / Package Proofs

These rows are live lab evidence, not canon language authority. They cross `igniter-compiler`,
`igniter-vm`, and `igniter-stdlib` because the VM proof for a stdlib feature often depends on the
compiler emitting the right SIR and the VM evaluating the HOF/eval_ast path correctly.

| Surface | Status | Where / proof |
|---|---|---|
| Collection `zip` signature | Implemented in stdlib declarations | `lang/igniter-stdlib/stdlib/collections.ig` declares `zip(a,b) -> Collection[Pair[A,B]]` with shorter-length truncation semantics; proof marker `LAB-STDLIB-COLLECTION-ZIP-PROOF-P2`. |
| HOF runtime parity for math calls | Implemented for covered shapes | `lang/igniter-vm/tests/stdlib_math_hof_tests.rs` covers `sin`, `cos`, `sqrt`, `pi`, `det_sin`, `det_sqrt` inside `fold`/`map` lambda bodies through `eval_ast`, not only bytecode `OP_CALL`. |
| HOF map-lambda `call_contract` parity | Implemented for covered specimen | `lab-docs/lang/lab-vm-map-lambda-callcontract-parity-p1-v0.md` and `map_lambda_callcontract_parity_tests` prove the Rust compiler/VM path keeps the map-lambda `call_contract("...")` shape executable. |
| `eval_ast` `variant_construct` in lambda bodies | Implemented for covered fleet blocker | `LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5` adds the `variant_construct` evaluator arm used by `batch_importer`; the machine fleet sweep is 13/13 OK on 2026-06-27. |
| Deterministic math evidence tiers | Implemented for current Tier-1/Tier-2 proofs | Deterministic functions are tested by golden bits / error behavior in VM tests; fast math exists as separate convenience evidence, not replay-safe equivalence. |
| Decimal money arithmetic/comparison | Implemented in stdlib + VM call paths | `lang/igniter-stdlib/src/decimal.rs` uses bounded scale, checked i128 intermediates, exact-only division, and scale-normalized comparison; VM equality/order routes through Decimal comparison rather than f64. Proof docs: `lab-stdlib-decimal-money-contract-readiness-p1.md`, `lab-stdlib-decimal-money-safe-p2.md`. |
| Exact text conversion `to_text` | Implemented for `Integer` and `Decimal`; `Float` is explicit-only via `float_to_text` | `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` accepts `to_text` / `stdlib.string.to_text` for `Integer | Decimal -> String` and rejects `Float`; `lang/igniter-vm/src/vm.rs` routes both bytecode `OP_CALL` and `eval_ast` through the same VM arm. `Integer` renders exact base-10; `Decimal { value, scale }` renders canonical fixed decimal text with exactly `scale` fractional digits, no locale/grouping/currency/rounding. Proof docs: `lab-lang-number-to-text-p1-v0.md`, `lab-lang-decimal-to-text-p2-v0.md`; tests: `stdlib_to_text_tests` in compiler + VM. |
| Float formatter `float_to_text` | Implemented as explicit fixed-point formatter | `float_to_text(x, decimals, rounding)` / `stdlib.string.float_to_text` is `(Float, Integer, String) -> String`. Current implemented mode is `"half_even"` only; Float must be finite; `decimals` is bounded to `0..=17`; output is fixed-point text with negative rounded zero normalized and no exponent form. Unsupported literal rounding modes are typecheck errors; dynamic unsupported modes are runtime errors. Proof doc: `lab-lang-float-to-text-impl-p7-v0.md`; tests: `stdlib_float_to_text_tests` in compiler + VM. |
| String `pad_left` | Implemented as rune-counted table primitive | `pad_left(text, width, pad)` / `stdlib.string.pad_left` is `(String, Integer, String) -> String`, counts Unicode scalar chars like `char_at`/`substring`, no-ops when `width <= len(text)`, and errors only for an empty pad when padding is needed. Numeric/report alignment composes explicitly as `pad_left(to_text(x), width, pad)`. Proof doc: `lab-lang-string-pad-left-p3-v0.md`; tests: `stdlib_pad_left_tests` in compiler + VM. |
| Float `Vec3` local package | Implemented as package proof | `lang/igniter-compiler/tests/fixtures/project_mode/linalg_vec3` plus `lang/igniter-vm/tests/linalg_vec3_tests.rs`; pure `.ig`, package resolver path, no VM builtins. |
| Float `Mat3` local package | Implemented as package proof | `lang/igniter-compiler/tests/fixtures/project_mode/linalg_mat3` plus `lang/igniter-vm/tests/linalg_mat3_tests.rs`; imports Vec3 and Mat3 through project mode and runs exact VM value checks. |
| Nested HOF coverage | Partly implemented / coverage-bounded | Covered HOF+math lambda paths run; do not generalize to every nested HOF, `filter_map`, `reduce`, recursion, or dynamic dispatch without a specific test. |

## Package / Admission Pointer

Package graph/archive/admission is owned by `igniter-compiler`, not `igniter-vm`. For current package
surface truth, start with `lang/igniter-compiler/src/main.rs` (`igc package graph|pack|verify|admit`),
`lang/igniter-compiler/src/project.rs` (`admit_archive`, archive verification, local package graph),
`lang/igniter-compiler/tests/package_lockfile_cli_tests.rs`, and
`lang/igniter-compiler/tests/package_workspace_tests.rs`.

`igc package admit` is a local deterministic admission proof over a source `.igpkg`; do not infer
registry publication, signing, semver solving, deployment permission, or package execution.

## Runtime wave — CLOSED 2026-06-15 (RUN-OK 1 → 18)

Full arc + per-fix detail: `.agents/work/cards/lang/LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1.md`.

Resolved this wave (all in `igniter-vm`, + one typechecker relax): stdlib collection
ops (namespaced→bare HOF aliases); `integer.{lt,gt,lte,gte}` + `collection.append` +
`string.concat`/`stdlib.string.char_at`/`stdlib.string.substring` + lenient `collection.concat`; **dispatch unification** (`VM::call_contract_value`
single-sourced; `&VM` threaded into `eval_ast`/`eval_lambda`); field_access generalized;
`MAX_CALL_DEPTH` 8→64; **closures (B)** + aggregate-source-ref; `if_expr` dual-shape +
dispatch-table completeness + `filter_map`; **`match_expr` in `eval_ast`**; homogeneous
numeric relax (typechecker).

**Cross-cutting root, now CLOSED:** nearly every gap was `eval_ast` (the tree-walker
for lambda/HOF bodies) lagging the bytecode path on a node kind — `call_contract`,
`if_expr`, `stdlib.*`, `match`. The two paths are now near-parity. Future
"X not found in eval_ast" is a *known class*, not a new mystery.

### RUN-OK rechecks — CLOSED 2026-06-15 (RUN-OK 24/25 current)

Proof: `igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p1.rb`.
Rollup: `.agents/docs/vm-run-ok-recheck-p1-2026-06-15-v0.md`.

Delta vs checkpoint: **+5 RUN-OK**. `advanced_logistics`, `vector_editor`,
`erp_logistics`, `igniter_parser`, and `bookkeeping` now run through selected
entrypoints. The old needs-inputs/demo-entry and Decimal construction buckets are
closed for the active registry-backed runtime fleet.

P2 recheck (`verify_lab_vm_run_ok_recheck_p2.rb`) stayed **RUN-OK 23/25** because
`LAB-VM-EVALAST-EVAL-EXPR-P1` closed as a routed spike, not implementation.

P3 recheck (`verify_lab_vm_run_ok_recheck_p3.rb`) is now **RUN-OK 24/25**. `spreadsheet`
`RunWorkbookDemo` moved to RUN-OK after `LAB-FUNCTION-SIR-RUNTIME-P1` materialized
app-local `def` functions into executable SIR and the VM static function registry.

Current non-green app:

| class | apps | owner / next route |
|---|---|---|
| governance-gated | rule_engine | `LAB-DYNAMIC-CONTRACT-DISPATCH` DEFER (ledger D-001) |

`rule_engine` remains intentionally fail-closed. This recheck is evidence-only and
does not relax dynamic dispatch.

`LAB-VM-EVALAST-EVAL-EXPR-P1` reclassified `spreadsheet`: the VM sees
`{kind:"call", fn:"eval_expr"}` inside a map lambda, but the `.igapp` has no
`functions` table or function sidecar. No VM-only source patch was made; route is
function SIR materialization plus VM static app-local function runtime.

`LAB-FUNCTION-SIR-RUNTIME-P1` closed that route for Rust+VM: the `.igapp` now carries
`functions`, and P3 live runtime evidence shows `spreadsheet` RUN-OK.

## Do Not Infer / Still Not Implemented

- `rule_engine` remains intentionally fail-closed behind dynamic-dispatch governance; RUN-OK 24/25 is
  not whole-fleet green.
- Machine fleet 13/13 OK is a finite zero-input sweep. It does not prove arbitrary dynamic dispatch,
  public language completeness, recursive self-call/TCO, or every nested HOF shape.
- Recursive self-call / TCO stays on v0 hold; `call_contract` is depth-guarded and self-recursion/cycles
  are closed.
- A source-compiling REPL EXISTS (machine `igniter-repl`: interactive + headless `--script`); the
  only remaining source-run gap is a non-interactive **one-shot single command** (`…-RUN-SOURCE-ONESHOT-P2`).
  `igniter-vm` itself still runs only a compiled `.igapp`. (Corrected by `…-VM-SOURCE-RUN-REPL-READINESS-P1`.)
- Generic matrix libraries, arbitrary nested HOF coverage, `filter_map`/`reduce` eval_ast parity, and
  package execution/admission are not proven by the Vec3/Mat3 or stdlib math rows.
- Package/admission evidence in this file is a pointer to compiler-owned surfaces, not VM authority.
- Do not infer implicit `to_text(Float)` from Float formatting. Float text is implemented only through
  explicit `float_to_text(x, decimals, rounding)`.
- `float_to_text` is a narrow fixed-point formatter, not a broad formatting framework: no locale,
  currency, grouping, exponent/scientific notation, additional rounding modes, `float_to_decimal`, or
  canon determinism claim.
- `pad_left` is a table primitive, not a general formatter: no `pad_right`/center, display-width policy,
  grouping, locale, currency, exponent/scientific notation, or implicit numeric-to-string coercion.

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
