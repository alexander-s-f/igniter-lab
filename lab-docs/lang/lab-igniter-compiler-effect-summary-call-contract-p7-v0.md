# LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7 v0

Date: 2026-06-28
Status: DONE (characterization + regression-lock; no propagation needed)
Lane: igniter-lab / compiler / interprocedural effect summary
Skill: idd-agent-protocol
Card: `.agents/work/cards/lang/LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7.md`
Depends-On: `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6`
Follows audit-control-board row **A20**.

## Authority boundary

Compiler diagnostic / test surface only. No new `.ig` syntax, no VM/web/machine
changes, no SIR metadata export, no canon edit, no weakening of P6 `OOF-M1`. Live
source wins.

## Decision (the headline)

**No effect propagation is implemented, because the inter-contract laundering
vector is already closed by construction.** Adding a contract-level `ambient_io`
graph over `call_contract` edges today would be **dead code**: there is no
constructible path where a `pure` contract reaches ambient I/O through a literal
`call_contract`. The slice is therefore a **characterization + regression-lock**:
3 tests pin the invariant so the moment it could break (a future relaxation of
the v0 callee rule) is caught.

This is a stronger outcome than the card's two anticipated branches ("propagate
into OOF-M1" / "readiness explains not-yet-safe"): the honest third answer is
"not *needed* — already closed."

## Live shape of `call_contract` (verified before deciding)

`call_contract` is a special form handled inside `infer_stdlib_call`
(`typechecker/stdlib_calls.rs:2488`), not a normal `Expr::Call` and not an
app-local `def`. v0 semantics at the call site:

| Check | Location | Behavior |
|---|---|---|
| ≥1 arg, first arg is `String` | `stdlib_calls.rs:2490,2501` | else `OOF-TY0` |
| **literal**-String callee → static registry lookup | `stdlib_calls.rs:2514-2524` | non-literal skips lookup |
| unknown callee | `stdlib_calls.rs:2525-2535` | `OOF-TY0` |
| **callee must be `pure`** | `stdlib_calls.rs:2536-2546` | `modifier != "pure"` → `OOF-TY0` ("only pure contracts may be called via call_contract in v0") |
| self-recursion closed | `stdlib_calls.rs:2547-2559` | `OOF-TY0` (use `recur()`) |
| arity (`positional_count == input_count`) | `stdlib_calls.rs:2560-2572` | `OOF-TY0` |
| valid literal pure callee | `stdlib_calls.rs:2573-2581` | resolves to callee's single-output type, else `Unknown` |
| **non-literal / dynamic callee** | `stdlib_calls.rs:2586-2588` | no static lookup; `resolved_type = Unknown`; "VM fail-closed as in P9" |

The callee `modifier` is the contract's declared modifier, carried in
`ContractRegistryEntry` (`typechecker.rs:57-64`), built from
`classified.modifier` (`typechecker.rs:2185-2224`).

## Why the vector is closed by construction

A `pure` contract laundering ambient I/O through `call_contract` would require
reaching an effectful callee. That is impossible in v0:

1. **Pure-only callees.** A literal `call_contract` to any non-`pure` contract
   (`observed`/…) is refused with `OOF-TY0` (`stdlib_calls.rs:2536`). So a pure
   surface cannot even *name* an effectful contract as a target — the effect is
   never reached.
2. **Pure callees are provably I/O-free.** A contract declared `pure` cannot
   perform ambient I/O: direct `stdlib.IO.*` is caught by the classifier
   (`E-IO-AMBIENT-BLOCKED`), and transitive-via-`def` I/O by P6 (`OOF-M1`). Each
   `pure` contract is checked independently. So there is no "pure but secretly
   effectful" contract for a literal `call_contract` to target.
3. **Induction.** (1)+(2) compose at every hop: a pure contract can only call
   pure contracts, which can only call pure contracts, none of which can do I/O.
   The pure sub-language is closed under `call_contract`. No `OOF-M1`
   propagation over contract edges can find a laundering path the purity gate
   does not reject earlier.

`igweb_lowering_tests` (P6) already confirms generated `pure contract Serve`
shells with `call_contract("…")` leaves are not flagged — consistent with this:
those leaves are pure handlers.

## Static vs dynamic target policy

- **Literal callee:** statically resolved; **pure-only**, fail-closed `OOF-TY0`
  on a non-pure or unknown target. This is the load-bearing protection.
- **Non-literal / dynamic callee:** not statically resolvable; resolves to
  `Unknown` and is VM fail-closed (`stdlib_calls.rs:2586`). No constructible
  `.ig` case exists — igweb emits literal callees only
  (`igweb.rs:1435-1436` "no dynamic dispatch: every call_contract is on a string
  literal"), and the dynamic-dispatch route DEFERs/fail-closes. Out of scope per
  the card ("No dynamic contract dispatch"). No dynamic-dispatch semantics were
  introduced.

## Questions answered (from the card)

1. **Is a literal `call_contract` a static contract edge to the typechecker?**
   Yes — `infer_stdlib_call` does a static registry lookup on a literal-String
   callee (`stdlib_calls.rs:2514-2524`).
2. **Same summary graph as `def`, or a separate graph?** Neither is needed now.
   A contract effect graph would be *separate* from the P6 `def` summary
   (contracts carry a declared `modifier`; `def`s do not). But it is unnecessary
   while the callee-purity gate closes the vector. If v0 relaxes that gate, the
   separate contract graph becomes the right tool (see follow-up).
3. **Non-literal / dynamic targets?** Deferred and fail-closed (`Unknown` +
   VM fail-closed); no constructible case; no new semantics.
4. **Recursive contract edges via existing SCC machinery?** Self-recursion is
   already closed (`OOF-TY0`, `stdlib_calls.rs:2547`). Mutual contract recursion
   would, if ever propagated, reuse the same `tarjan_sccs` machinery P6 uses for
   `def`s — but it is moot while callees are pure-only.
5. **Persist effect flags into SIR now?** No — out of scope and unnecessary; the
   enforcement is a compile-time diagnostic, identical to P6's stance.

## Proof (tests)

`lang/igniter-compiler/tests/effect_summary_call_contract_tests.rs` (3/3):

| Test | Proves |
|---|---|
| `pure_contract_cannot_call_contract_an_effectful_contract` | a pure contract calling `call_contract` on an `observed` I/O contract is refused at the call site (`OOF-TY0` pure-only gate) — the effect is never reached. |
| `pure_contract_call_contract_to_pure_target_is_clean` | no false positive: pure → literal `call_contract` → pure I/O-free contract is clean (no `OOF-M1`, no `OOF-TY0`). |
| `a_pure_contract_that_launders_is_rejected_so_no_effectful_pure_target_exists` | induction base: a contract declared `pure` that launders I/O via a def is itself rejected (`OOF-M1`, P6) — so every legal `call_contract` callee is provably I/O-free. |

Verification:

```text
cargo test ... --test effect_summary_call_contract_tests       3 passed
cargo test ... --test effect_summary_interprocedural_tests     7 passed   (P6 unchanged)
cargo test ... (full compiler suite)                           0 failed (318 passed)
git diff --check                                               PASS
```

## Covered vs deferred edges

- **Covered (locked):** literal `call_contract` from a pure contract — closed by
  the pure-only callee gate; pure callees provably I/O-free; positive
  no-false-positive case.
- **Deferred (no action needed now):**
  - Dynamic / non-literal `call_contract` — fail-closed `Unknown`, no
    constructible case, no dynamic semantics introduced.
  - Contract-level `ambient_io` propagation over `call_contract` edges — **only
    becomes necessary if a future card relaxes the v0 pure-only callee rule**
    (i.e. allows `pure → call_contract(observed)`), at which point test (1) above
    breaks and signals the need. Follow-up card named below.

## Follow-up card (conditional)

```text
LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CONTRACT-GRAPH-P8
```
Open **only if/when** v0 allows effectful `call_contract` callees. It would add a
separate contract-level effect summary (reusing `tarjan_sccs`) that propagates
`ambient_io` across literal `call_contract` edges into `OOF-M1`. Until then it is
dead code and intentionally not built.
