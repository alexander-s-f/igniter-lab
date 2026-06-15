# LAB-APP-DEMO-ENTRY-WAVE-P1

**Status:** CLOSED - APP FIXTURE WAVE  
**Date:** 2026-06-15  
**Route:** lab / runtime / needs-input apps / demo entrypoints  
**Authority:** app-side demo/orchestrator entries only. No compiler, VM, typechecker, IO, storage, queue, clock, or scheduler authority.

## Verdict

Added zero-input companion `example.ig` entries for four needs-input apps:

| App | Entrypoint | Rust | Ruby | VM no-input run | Source hash |
| --- | --- | --- | --- | --- | --- |
| `advanced_logistics` | `RunDailyRoutesDemo` | ok/0 | ok/0 | success | `sha256:df623dec726a847355914892805d433c7ead695d9c70e2cf0316b3f332862102` |
| `spreadsheet` | `RunWorkbookDemo` | ok/0 | oof/6 | blocked: `Unsupported operator: eval_expr` | `sha256:5802728da8d4eda2ff055057f92d55ca292a61f6ecea136695659e2e7683bd05` |
| `vector_editor` | `RunCanvasClickDemo` | ok/0 | ok/0 | success | `sha256:967b2b50a666b89cb64ecbd72d2d12f09ed958aec53fd92d63feaa2f2db04144` |
| `igniter_parser` | `RunParseDemo` | ok/0 | ok/0 | blocked: `stdlib.string.char_at` | `sha256:915ea3463bc49ce78f6edd2492d4bedb2111934795e7a4b23de1535b0d6dd04c` |

Net runtime result: **2/4 VM-success**. The other 2 apps now have zero-input entries and named residual blockers.

## App Notes

### advanced_logistics

Added `igniter-apps/advanced_logistics/example.ig`.

- Factories: `MakeLocation`, `MakePackage`, `MakeTransport`, `MakeOrder`.
- Entrypoint: `RunDailyRoutesDemo`.
- Runtime path: builds two vans and two orders, then calls `PlanDailyRoutes`.
- VM result: success; `van-a` accepts both orders and `van-b` accepts the smaller order.
- Production contracts unchanged.

### spreadsheet

Added `igniter-apps/spreadsheet/example.ig`.

- Factories: `MakeNumberExpr`, `MakeCell`, `MakeGrid`.
- Entrypoint: `RunWorkbookDemo`.
- Rust compile: ok/0.
- VM residual: `Unsupported operator: eval_expr`.
- Ruby residual: existing app-local function blocker remains, and the demo fixture exposes Ruby optional-recursive record typing for `Expr?` fields.
- Production contracts unchanged.

Residual routes:

- `SS-P08`: VM app-local `def` call support for `eval_expr`.
- `SS-P09`: Ruby optional/recursive record typing for `Expr?` fields.

### vector_editor

Added `igniter-apps/vector_editor/example.ig`.

- Factories: `MakePoint`, `MakeLayer`, `MakeDocument`, `MakeToolState`.
- Entrypoint: `RunCanvasClickDemo`.
- Runtime path: builds an empty one-layer document and a draw-rect tool state, then calls `HandleCanvasClick`.
- VM result: success; `rect-new` is appended to `layer-1`.
- Production handlers unchanged.

### igniter_parser

Added `igniter-apps/igniter_parser/example.ig`.

- Entrypoint: `RunParseDemo`.
- Runtime path: calls `ParseSource("module Demo")`.
- Ruby/Rust compile: ok/0.
- VM residual: `OP_CALL: Unknown/unimplemented function 'stdlib.string.char_at' with 2 arguments`.
- Production parser/lexer contracts unchanged.

Residual route:

- `IP-P08`: `LAB-STDLIB-STRING-CHAR-AT-VM-P1`.

## Proof

Proof runner:

`igniter-view-engine/proofs/verify_lab_app_demo_entry_wave_p1.rb`

The proof live-checks:

- each app's source files and `entrypoint`,
- Rust compile status, source hash, manifest entrypoint, and SIR contract count,
- Ruby compile status and classified residuals,
- `tools/igniter run igniter-apps/<app>` no-input runtime result,
- app pressure registry updates,
- portfolio/card closure artifacts,
- no tracked edits to `igniter-compiler`, `igniter-vm/src/compiler.rs`, or `igniter-vm/src/vm.rs`.

## Closed Surfaces

- No VM changes.
- No compiler or typechecker changes.
- No IO, file, queue, HTTP, scheduler, clock, or database authority.
- No dynamic dispatch relaxation.
- No broad app refactor.
- No production handler semantics changed.
- No canon language authority.
