# LAB-IGNITER-WEB-COMPOSITE-GUARD-RUNTIME-P24 — sealed ctor in branch positions

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation (compiler)
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-COMPOSITE-GUARD-RUNTIME-P24

## Intent

Fix the runtime gap found by P23 (`lab-docs/lang/lab-igniter-web-todo-v2-app-p23-v0.md`): a `.ig` contract
that constructs a built-in sealed `Result`/`Option` (`ok()`/`err()`/`some()`/`none()`) **inside an
`if`/`match` branch** compiles and passes `igweb-serve check`, then **500s at dispatch** because the
constructor is emitted as an untagged record (`{ ok: x }`) instead of a tagged sealed variant.

`check`-clean code must not 500 at dispatch. After the fix, the natural composite-guard shape
(`compute r = if account_ok { ok(ctx) } else { err(...) }`) must execute correctly.

## Root cause (verified)

- `infer_sealed_construct` (`typechecker.rs:5114`) lowers `ok`/`err`/`some`/`none` to a sealed
  `variant_construct` SIR node, carried as the compute's `annotated_expr`.
- The emitter uses `annotated_expr` only at the **compute-decl top level** (`emitter.rs:846-849`). When the
  constructor is nested in an `if`/`match` branch, the decl's `annotated_expr` is `None`, so the emitter
  falls back to `semantic_expr_for_compute` → `semantic_expr`, which does **not** recognize the sealed
  constructor and lowers `ok(x)` as a generic call → untagged `{ ok: x }` record.
- `semantic_expr` (`emitter.rs:955`) already intercepts specific call `fn`s (recur, stdlib.numeric.add,
  comparisons, text/collection stdlib) — a clean injection point for sealed-ctor recognition.

## Authority

Lab implementation. This card may change:

- `lang/igniter-compiler/src/emitter.rs` (sealed-ctor recognition in `semantic_expr`);
- `lang/igniter-compiler/tests/` (a focused repro test);
- `server/igniter-web/examples/todo_v2_app/todo_handlers.ig` (revert to the natural shape once fixed);
- a proof doc under `lab-docs/lang/`;
- this card's closing report.

Must **not** change: the VM/`igniter-machine`, parser/typechecker *semantics* (only emitter lowering),
`igniter-server`, the runner, `.igweb` lowering (`igweb.rs`), or canon. No new language surface.

This is a **core emitter change** (affects all `.ig`): the fix must be additive and the full compiler + VM
+ igniter-web suites must stay green.

## Verify First

- `lab-docs/lang/lab-igniter-web-todo-v2-app-p23-v0.md` (the finding + the two symptoms)
- `lang/igniter-compiler/src/typechecker.rs` (`infer_sealed_construct`, ~5114)
- `lang/igniter-compiler/src/emitter.rs` (`semantic_expr` ~955, decl lowering ~846, `lower_annotated_expr` ~1357)
- existing sealed-ctor / match tests in `lang/igniter-compiler/tests/` and `lang/igniter-vm/`
- a working prod match (`apps/igniter-apps/lead_router/pipeline.ig`) for the user-variant baseline

Live code wins. If the fix needs a VM change (not just emitter), STOP and report — that reshapes the card.

## Required Behavior

1. `ok(x)` / `err(x)` / `some(x)` / `none()` lower to the **same** sealed `variant_construct` shape in
   ANY position (decl top, `if`-branch, `match`-arm body, nested).
2. The natural composite guard runs:

   ```ig
   compute r : Result[Ctx, Decision] = if ok_a {
     if ok_b { ok(ctx) } else { err(Respond { status: 404, body: "..." }) }
   } else {
     err(Respond { status: 404, body: "..." })
   }
   ```

3. No regression to: existing sealed-ctor decls, user-variant `match` (lead_router), the `.igweb`
   via/composite-guard compile tests, or VM execution of variants.
4. If the internal `match`-over-`Result`-returning-a-value mis-bind (P23 symptom 1) is NOT covered by the
   same fix, document it precisely as a remaining gap with a follow-up card — do not force it.

## Required Tests

1. **Compiler unit/integration:** a `.ig` contract returning `if c { ok(x) } else { err(y) }` lowers to a
   tagged sealed `variant_construct` (assert the emitted IR/SIR carries `arm: "Ok"/"Err"`, not a plain
   `{ ok: ... }`), and compiles clean.
2. **Runtime proof:** the `todo_v2_app` reverted to the natural `if { ok } else { err }` guard shape passes
   all nine loopback behaviors through `igweb-serve` (the P23 test, unchanged assertions).
3. **Regression:** full `lang/igniter-compiler` tests, `lang/igniter-vm` tests, and `server/igniter-web`
   tests stay green. State exact counts.

## Required Proof Doc

`lab-docs/lang/lab-igniter-web-composite-guard-runtime-p24-v0.md` — root cause, the one-spot emitter fix,
before/after IR snippet, the natural-shape runtime proof, regression counts, and what (if anything) remains
(e.g. internal match-over-Result), plus the next-card recommendation.

## Acceptance

- [x] Root cause confirmed and fix located in the emitter (not the VM).
- [x] `ok/err/some/none` lower to sealed `variant_construct` in branch/nested positions.
- [x] `todo_v2_app` natural-shape guard runs (nine behaviors green).
- [x] Full compiler + VM + igniter-web suites green with exact counts (zero new failures; pre-existing loop tests excepted).
- [x] No VM / parser / server / runner / `.igweb` / canon change.
- [x] Proof doc written; card closed with report.

---

## Closing Report (2026-06-19)

**Outcome:** the P23 runtime gap is fixed with a **one-spot emitter change**. Built-in sealed constructors
(`ok`/`err`/`some`/`none`) in an `if`/`match` **branch** now lower to a tagged `variant_construct` in every
position, so the natural composite-guard shape `if account_ok { ok(ctx) } else { err(..) }` **executes**.
Proof doc: `lab-docs/lang/lab-igniter-web-composite-guard-runtime-p24-v0.md`.

**Root cause (emitter, not VM):** the typechecker's sealed `variant_construct` is consumed only at the
compute-decl top level (`emitter.rs:846`); in branch positions lowering fell to `semantic_expr`, which
emitted an untagged `{ ok: x }` record → VM 500 (`'__arm' not found`). Fix: `semantic_expr` now recognizes
the four sealed constructors and emits the same tagged node as `infer_sealed_construct` — additive, the
top-level path unchanged.

**Proof — all green:**
- NEW `sealed_ctor_branch_tests` → **1 passed** (asserts `if flag { ok(v) } else { err(..) }` emits
  `"arm":"Ok"`/`"arm":"Err"` in `semantic_ir_program.json`).
- `todo_v2_app` reverted to the **natural `if`-shape** guards → **nine-behavior loopback green** (the
  runtime proof; P23's workaround no longer needed).
- `igweb_lowering_tests` 9, `igniter-web` 30 green.
- **Zero regressions:** full compiler suite `68 passed / 4 failed` identical **with and without** the change
  (verified by `git stash`); the 4 compiler + 1 VM failures are pre-existing loop-IR-shape tests. `git diff
  --check` clean; only `emitter.rs` modified.

**Remaining gap (documented, not forced):** an internal `match` over a built-in `Result` that returns a
value from an arm still mis-binds (separate `match_node` arm-lowering path). Authors use `if` for the guard
short-circuit. Follow-up: `LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25`.

**Next:** `LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25` (lower priority — `if` already works), then return to
real app pressure / relational QueryPlan bridge. The IgWeb routing wave is now runtime-complete for the
`if`-based composite guard.

## Closed Surfaces

No VM change; no parser/typechecker semantic change (emitter lowering only); no `igniter-server`/runner/
`.igweb` change; no new syntax; no DB/effects/public bind; no canon claim.
