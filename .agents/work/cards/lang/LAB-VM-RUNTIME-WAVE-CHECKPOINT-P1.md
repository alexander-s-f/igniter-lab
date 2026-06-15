# Card: LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1 — runtime wave closure

**Status: CHECKPOINT 2026-06-15.** Fixes the milestone: **fleet RUN-OK 1 → 18**.
Purpose: stop future drift — the shared VM/compiler layer is now largely clean, so
agents should NOT hunt for "one more common VM bug". Remaining non-green apps are
classified by owner below; they are not a shared runtime gap.

## The arc (1 → 18)

| step | fix | RUN-OK |
|---|---|---|
| start | P0 live runner `tools/igniter` (`.ig → compile → run`) | 1 |
| stdlib collection ops | alias namespaced `stdlib.collection.*` → existing bare HOF; + `integer.{lt,gt,lte,gte}`, `collection.append` | 6 |
| dispatch unification | extracted `VM::call_contract_value`; threaded `&VM` into `eval_ast`/`eval_lambda`; bytecode + tree-walker share one call_contract | 12 |
| field access + depth | generalized `eval_ast` field_access (any object expr → Record field); `MAX_CALL_DEPTH` 8→64 | 13 |
| closures (B) + aggregate-ref | compile-time capture list (`captures:[{name,reg}]`) + runtime snapshot via `inputs` chokepoint; reused for aggregate source/pipeline refs | 15 |
| compiler dispatch completeness | `if_expr` dual-shape (`condition/then` + `cond/then` block-unwrap) in both VM readers; `filter_map`; fixed silent dispatch-entry skip | 16 |
| eval_ast match | added `match_node/match_expr` to the tree-walker (mirrors bytecode `__arm`) — restored batch_importer's *honest* green | 17 |
| triage + wrapper | `vector_math` green via correct entry; fixed `tools/igniter` silent-exit on multi-root; homogeneous numeric relax (typechecker) | 18 |

Also done this wave: homogeneous numeric relaxation (typechecker Integer→Int/Float/
Decimal for same-type ops); `stdlib.string.concat` + lenient `collection.concat`.

## The cross-cutting root (now closed)

Almost every gap was the same shape: **`eval_ast` (the tree-walker that runs lambda /
HOF bodies) lagged the bytecode path** on a node kind — `call_contract`, `if_expr`,
`stdlib.*`, `match`. The two execution paths are now near-parity. This is the insight
that stops the drift: future "X not found in eval_ast" is a *known class*, not a new
mystery.

## Remaining 7 — by owner (NOT a shared VM bug)

| class | apps | owner / route |
|---|---|---|
| **needs-inputs / demo-entry** | advanced_logistics, spreadsheet, vector_editor, erp_logistics, igniter_parser | app-side — no zero-input demo contract; → `LAB-APP-DEMO-ENTRY-WAVE-P1` |
| **Decimal policy** | bookkeeping | heterogeneous Float→Decimal — neighbor `LAB-NUMERIC-DECIMAL-BOUNDARY-P1` (policy) → impl `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` |
| **governance-gated** | rule_engine | Unknown / dynamic dispatch — `LAB-DYNAMIC-CONTRACT-DISPATCH` DEFER (ledger D-001) |
| **tiny stdlib tail** | igniter_parser (once input given) | `stdlib.string.char_at` → `LAB-STDLIB-STRING-CHAR-AT-VM-P1` |

## Updated surfaces

- `igniter-vm/IMPLEMENTED_SURFACE.md` — runtime capabilities + "Known runtime gaps"
  reflect this wave (most resolved; remaining classified by owner).
- This card is the wave's single closure record; per-fix cards link from here.

## Next wave (independent branches — pick any)

1. **`LAB-APP-DEMO-ENTRY-WAVE-P1`** — add a zero-input demo/orchestrator entry per
   needs-input app (no VM/compiler change). Highest RUN-OK yield.
2. **`LAB-NUMERIC-DECIMAL-CONSTRUCT-P1`** — explicit `decimal(value, scale)`; gated on
   the boundary policy decision.
3. **`LAB-STDLIB-STRING-CHAR-AT-VM-P1`** — small VM string op; unblocks igniter_parser's tail.

Recommendation: branch 1 (demo entries) next — cleanest RUN-OK growth, zero runtime risk.
