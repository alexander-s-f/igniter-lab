# LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6

Date: 2026-06-28
Status: DONE
Lane: igniter-lab / compiler / purity and interprocedural effect summary
Skill: idd-agent-protocol
Card: `.agents/work/cards/lang/LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6.md`
Closes: audit-control-board row **A20**; hardening item **NW-T2-4**; audit finding **§B-U5**.

## Authority Boundary

This is a lab implementation packet. It adds a **compiler diagnostic** only.

- No new public `.ig` syntax, no `Decision` runtime semantics, no VM/runtime effect
  execution, no host (web/machine) IO wiring, no capability-authority redesign.
- No canon `igniter-lang` edits. Live source wins; the slice is gated by tests.
- Authority for "what may run" stays with the host/machine boundary. This slice only
  decides "what the compiler accepts as `pure`."

## The Gap (verified before editing)

Purity was decided by an **inline, intra-contract** scan: the classifier walks contract
body expressions and flags `stdlib.IO.*` calls in `pure` contracts
(`classifier.rs` `expr_has_io_call` / `check_expr_io`, `E-IO-AMBIENT-BLOCKED`,
`OOF-M1`). It never resolved a call's `fn_name` to its `def` body. So:

```
def leak(p) = stdlib.IO.read_text(p, cap)   -- effectful helper

pure contract Launder {
  compute result = leak(path)               -- presented as a plain call → undetected
}
```

The contract declared `pure` but performed I/O transitively. (audit `§B-U5`.)

Re-verified live facts:
- `stdlib.IO.*` is lexed as a **single identifier token** (`lexer.rs:642`), so
  `stdlib.IO.read_text(...)` parses to `Expr::Call { fn_name: "stdlib.IO.read_text" }`,
  not a `FieldAccess` chain. A `starts_with("stdlib.IO.")` test on `Call` is correct.
- The typechecker already builds a per-`def` call graph and Tarjan SCCs for the OOF-L4
  recursion gate (`collect_fn_calls`, `tarjan_sccs`). Reused, not reinvented.
- `def`s reach the typechecker as raw parser AST via `typecheck(&classified, &parsed.functions)`.

## Effect Categories Modeled

First slice models a **single boolean effect**: `ambient_io`.

| Flag | Meaning |
|---|---|
| `ambient_io` | A `def` body directly calls a `stdlib.IO.*` sink, **or** transitively reaches one through the app-local call graph. |

This is deliberately the smallest useful surface. The richer flag set proposed in the P5
readiness packet (`declared_effect_surface`, `decision_response`, `decision_read_staged`,
`decision_effect_intent`, `unknown_dynamic`) is **not** part of this slice — see "Outside
this slice". Modeling `ambient_io` as one bool is sufficient because the enforcement target
(A20 / NW-T2-4) is exactly "a `pure` contract laundering ambient I/O through a `def`", and
host intents (`ReadThen` / `InvokeEffect`) are **not** ambient I/O and must remain legal
from pure handlers.

## Graph / Fixpoint Handling

`compute_ambient_io_summary(functions)` in `typechecker.rs`:

1. **Seed** — `ambient_io[def] = block_has_io_call(def.body)`, a full-coverage AST walk
   for any `stdlib.IO.*` `Call` (mirrors the classifier predicate; covers `match`,
   variant construction, lambdas, `?`-wrapped calls, etc.).
2. **Propagate** — reuse `collect_fn_calls` (def→def edges) + `tarjan_sccs`. Tarjan emits
   SCCs in **reverse-topological order** (callees before callers), so a single forward pass
   over the condensation suffices: a callee's summary is final before any caller is visited.
3. **Cycles** — every member of an SCC shares one summary value. The SCC is `ambient_io`
   iff any member touches I/O directly, or any member calls out to an already-`ambient_io`
   def. This is **deterministic and total**: `tarjan_sccs` is fed sorted node names and
   produces sorted SCCs, and the boolean lattice has a unique least fixpoint independent of
   `HashMap` iteration order. (Test `cyclic_helper_graph_with_io_is_deterministic_oof_m1`
   runs the pass twice and asserts identical output.)

**Cross-cutting fix:** `expr_collect_calls` previously dropped `Expr::Try` (`expr?`), so
`?`-wrapped call edges were invisible to **both** the OOF-L4 graph and this summary. Added
one `Try` arm so fallible-binding calls are real edges. The full compiler suite stays green,
confirming no recursion fixture relied on `?` hiding a call.

## Enforcement (direct vs transitive)

After the OOF-L4 block, for each `pure` contract the typechecker collects every app-local
`def` called anywhere in the body (top-level nodes + loop / service-loop inner nodes) via
`expr_collect_calls`, and emits **`OOF-M1`** for each reached def whose summary is
`ambient_io` (sorted, deduped → deterministic, one diagnostic per laundering def).

Diagnostic code is `OOF-M1` — the same pure-modifier-violation family the classifier uses
for direct I/O, as specified by NW-T2-4's acceptance. The two paths are distinguished by
**message**, not code:

- **Direct** (classifier, unchanged):
  `E-IO-AMBIENT-BLOCKED` / `OOF-M1` — `stdlib.IO.*` inline in a pure contract body.
- **Transitive** (this slice, typechecker):
  `OOF-M1` — *"pure contract 'X' performs ambient I/O transitively through helper def 'Y'
  (a stdlib.IO.* sink is reachable via the call graph); pure contracts cannot launder
  effects through a def …"*

`OOF-M1` begins with `OOF-`, so the typechecker `pass_result` correctly flips to `oof` and
all downstream "any OOF" gates treat the program as failing.

## Proof (tests)

`lang/igniter-compiler/tests/effect_summary_interprocedural_tests.rs` (7/7):

| Test | Proves |
|---|---|
| `pure_contract_launders_io_through_def_is_oof_m1` | core gap: pure → def → `stdlib.IO.*` ⇒ OOF-M1. |
| `pure_contract_calling_pure_def_is_clean_of_oof_m1` | no false positive on a side-effect-free def. |
| `transitive_two_hop_laundering_is_oof_m1` | I/O two def-hops deep is still caught. |
| `try_wrapped_laundering_is_detected` | `?`-wrapped call edges are traversed. |
| `cyclic_helper_graph_with_io_is_deterministic_oof_m1` | mutual recursion: deterministic, exactly one diagnostic, no panic. |
| `observed_contract_calling_io_def_is_not_oof_m1` | scope guard: only `pure` is restricted. |
| `direct_io_in_pure_contract_still_flagged` | regression guard: classifier `E-IO-AMBIENT-BLOCKED` intact. |

Verification:

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test effect_summary_interprocedural_tests
  7 passed; 0 failed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml      (full suite)
  34 test binaries, 0 failed
cargo test ... --test effect_name_parity_tests --test igweb_lowering_tests
  4 passed / 11 passed
git diff --check
  PASS
```

`igweb_lowering_tests` green confirms generated `pure contract Serve` shells with
`call_contract("…")` leaves are **not** flagged — `call_contract` is not an app-local `def`,
so it is correctly outside the summary.

## Outside This First Slice (deliberate)

- **`call_contract("Name")` callee propagation.** A `def`/contract reaching I/O through a
  static inter-contract call is not yet summarized. Today the host/machine boundary already
  refuses pure contracts for declared host effects
  (`capability_io_host_tests.rs`); this is the compiler-side follow-on.
- **Richer flag set + SIR metadata.** The P5 readiness flags
  (`declared_effect_surface`, `decision_*`, `unknown_dynamic`) and emitting an
  `effect_summary` field into SIR are not implemented. The card's binding acceptance is the
  `OOF-M1` enforcement; SIR emission touches the emitter/`TypedProgram` and is the next slice.
- **Dynamic dispatch.** Non-literal callees (none exist in current `.ig`) would need a
  conservative `unknown_dynamic` fail-closed rule; deferred until such a callee exists.
- **Effect kinds beyond `ambient_io`.** Network, clock, etc. are not separately classified;
  `now()` remains independently forbidden in functions/contracts (`OOF-L2`).

## Questions Answered (from the card)

1. **Effect categories in the compiler today?** Direct `stdlib.IO.*` (classifier
   `E-IO-*` + `OOF-M1`); `now()` time-effect (`OOF-L2`); declared capability/effect surface
   (host-consumed metadata). This slice adds the transitive `ambient_io` summary.
2. **One boolean or an enum/set?** One boolean (`ambient_io`) — the minimal surface that
   closes A20 without rejecting legal pure→`Decision` host-intent patterns.
3. **Cycles?** SCC-condensation summary over the existing Tarjan machinery; deterministic
   least-fixpoint, members of a cycle share one value.
4. **Diagnostic code for transitive effect?** `OOF-M1` (per NW-T2-4), distinguished from the
   direct case by message text.
5. **Tests proving direct effects unchanged?** `effect_name_parity_tests` (capability
   binding), `igweb_lowering_tests` (pure Serve shells), and the new
   `direct_io_in_pure_contract_still_flagged` guard.
