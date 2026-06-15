# Card: LAB-VM-HOF-CLOSURE-CONVERSION-P1 — closure conversion (decided: B)

**Status: IMPLEMENTED 2026-06-15 (B).** Mechanism proven, no regression (RUN-OK held
at 13). Supersedes `LAB-VM-HOF-CLOSURE-CAPTURE-P1`.

## Implementation (all in igniter-vm — no front-end change needed)

- `compiler.rs` lambda lowering: compute the body's `ref` names (`collect_ref_names`),
  intersect with `compute_node_registers`, emit `captures:[{name,reg}]` into the
  serialized lambda. (Inputs already reach lambdas via the runtime `inputs` map, so
  only compute bindings — held in registers by index — need capturing.)
- `vm.rs` OP_CALL chokepoint: `collect_captures` recursively gathers every `captures`
  entry from a lambda arg (incl. nested lambdas — all reference the executing
  contract's registers), resolves each via the live `registers`, and exposes them by
  augmenting `inputs` for the handler. One chokepoint covers every HOF arm + nested HOFs.

**Proof of mechanism:** sim_framework now captures `new_tick` / `rule_names` and
progresses past the closure error (then hits unrelated gaps below). Build clean; the
13 previously-green apps unaffected.

## Proof targets — GREEN 2026-06-15

sim_framework (`RunEcosystemSim`) and trade_robot (`RunTradingBot`) now run end-to-end
(after the adjacent `LAB-VM-AGGREGATE-SOURCE-REF-P1` fix, which reused this card's
capture machinery for aggregate source/pipeline refs). air_combat regression intact.
**Fleet RUN-OK 13 → 15.**

## Decision

**B = compile-time closure analysis + runtime snapshot of only declared captures.**
The compiler computes each lambda's free variables and writes a **capture list** into
the lambda artifact. At HOF entry the VM builds a closure env from *only those
captures* (a read-only snapshot of current values), then runs the body with
`captured_env + {param: item}`. Values are resolved at runtime — nothing is baked at
compile time. Not A (whole-scope runtime capture): no over-capture, lambdas become
self-documenting, purity is provable (read-only snapshot, no write-back).

## Spec — answers to the required questions

**Free-var detection (compiler).** Lexically walk the lambda body AST; collect every
`ref` / `field_access` root name; subtract names bound *inside* the lambda. The
remainder are free vars.

**Captured binding classes.** Enclosing **inputs** + **earlier `compute` bindings** +
enclosing lambda captures/params (for nested lambdas). A free var must resolve to one
of these in the enclosing contract; if it resolves to none → compile error
(undefined), not a silent runtime miss.

**Not captured.** Lambda's own params; `let`/match-arm bindings introduced inside the
lambda; contract names (call_contract targets); stdlib function names; type names.

**Shadowing.** Innermost wins: lambda param > inner let/match binding > captured outer
name. Free-var detection respects this (a name shadowed by an inner binder is not free).

**Representation (lambda artifact).** Add `captures: [{name, reg}]` to the serialized
lambda node:
- `reg >= 0` → read enclosing **compute** register `registers[reg]`.
- `reg = -1` (or absent) → resolve `name` by name in the enclosing **inputs** /
  `local_env` (inputs + outer lambda captures are name-addressed).
The compiler already has the name→register map (`compute_node_registers`) to fill `reg`.

**VM semantics (HOF entry).** For each capture build `captured_env[name] = <resolved
value>` (clone — read-only snapshot). Run the lambda with
`local_env = captured_env` then insert `{param: item}` (param shadows). No mutation
of captured values, no write-back to the enclosing frame. Applies in both the
bytecode HOF handlers and `eval_ast`/`eval_lambda` (the unified path).

## Proof targets

```text
igniter run igniter-apps/sim_framework  → success   (captures new_tick, config, rule_names)
igniter run igniter-apps/trade_robot    → success   (captures closes, …)
igniter run igniter-apps/air_combat --entry RunDuel → still success (regression)
```
Fleet RUN-OK 13 → 15+.

## Closed (out of scope for P1)

No dynamic scope; no mutable closures / write-back; no IO from captures; no app
rewrites; no auto-entry change (see `LAB-VM-ENTRYPOINT-SELECTION-P1`); no change to
purity rules beyond proving captures are read-only.

## Touch points

- `igniter-compiler`: free-var analysis at lambda lowering; emit `captures` into the
  lambda artifact (`emitter.rs` + the lambda lowering path).
- `igniter-vm`: HOF entry builds `captured_env` from `captures` before running the
  lambda body (`vm.rs` HOF handlers + `eval_lambda`).
