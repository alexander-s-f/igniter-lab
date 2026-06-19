# lab-igniter-web-composite-guard-runtime-p24-v0 — sealed ctor in branch positions

**Card:** `LAB-IGNITER-WEB-COMPOSITE-GUARD-RUNTIME-P24` · **Delegation:** `OPUS-IGWEB-COMPOSITE-GUARD-RUNTIME-P24`
**Status:** CLOSED (lab implementation, compiler) — fixes the P23 runtime gap: built-in sealed constructors
(`ok`/`err`/`some`/`none`) used **inside an `if`/`match` branch** now lower to a tagged `variant_construct`
in every position, so the natural composite-guard shape (`if account_ok { ok(ctx) } else { err(..) }`)
**executes** instead of 500-ing at dispatch. **One-spot emitter change; no VM/parser/typechecker-semantic/
server/runner/`.igweb`/canon change.**
**Authority:** Lab compiler tooling. Implements P23's recommended next card.

## 1. Root cause (verified)

- The typechecker lowers `ok`/`err`/`some`/`none` to a sealed `variant_construct` SIR node
  (`typechecker.rs:5114 infer_sealed_construct`), carried as a compute's `annotated_expr`.
- The emitter consumes `annotated_expr` **only at the compute-decl top level** (`emitter.rs:846-849`). When
  the constructor is nested in an `if`/`match` branch, that decl's `annotated_expr` is `None`, so lowering
  falls to `semantic_expr`, which did **not** recognize the sealed constructor and emitted `ok(x)` as a
  generic call → an **untagged `{ ok: x }` record**. The VM then can't read the variant tag (`__arm`), so
  it 500s at dispatch — even though the program compiled and passed `igweb-serve check`.

This is an **emitter (SIR-lowering) bug, not a VM bug**: the VM handles tagged `variant_construct`
correctly (the flat `compute r = ok(ctx)` case always worked); the emitter simply never produced a tagged
node in branch positions.

## 2. The fix (one spot, additive)

In `semantic_expr` (`emitter.rs`, the recursive fallback lowering that already intercepts `recur`,
`stdlib.numeric.add`, comparisons, text/collection stdlib), recognize the four sealed constructors and
emit the **same** tagged `variant_construct` shape the typechecker produces — mirroring
`infer_sealed_construct`:

```rust
// ok → arm "Ok"/variant "Result"/field "value"; err → "Err"/"Result"/"error";
// some → "Some"/"Option"/"value"; none → "None"/"Option"/(no field). sealed: true.
if call.fn ∈ {ok, err, some, none} {
    return { kind: "variant_construct", arm, variant, fields: { <field>: semantic_expr(arg) }, sealed: true };
}
```

Because `semantic_expr` is the general recursive lowering, sealed constructors now lower correctly in
**any** nested position (if-branches, nested ifs, call args, etc.). The top-level path is unchanged (it
still uses the typechecker's `annotated_expr`), so there is no double-handling.

### Before / after (emitted SemanticIR for `if flag { ok(v) } else { err(Respond{..}) }`)

- **Before:** the branch `ok(v)` lowered to an untagged record (`{ ok: <v> }`) → VM `'__arm' not found`.
- **After:** `semantic_ir_program.json` carries `"kind":"variant_construct","arm":"Ok",…,"sealed":true`
  and `…"arm":"Err"…` for the two branches (asserted by the new compiler test).

## 3. Runtime proof (the natural shape now runs)

The P23 `todo_v2_app` composite guards were reverted from the if-select-flat workaround to the **natural**
shape — `compute r : Result[..] = if account_ok { ok(ctx) } else { err(Respond{..}) }` (and the nested
two-check variant) — and the nine-behavior loopback test passes unchanged through `igweb-serve`. So the
shape P23 had to avoid now executes correctly.

## 4. Remaining gap (documented, not forced)

The fix covers sealed constructors in `if`/`match` **branch** positions. It does **not** cover an internal
`match` over a built-in `Result` that returns a value from an arm, e.g.

```ig
compute r : Result[Ctx, Decision] = match account {   -- still mis-binds at runtime
  Err { error } => err(error)
  Ok  { value } => ok(ctx)
}
```

(confirmed: switching a guard to this shape still 500s with my fix in place). This is a separate
`match_node` arm-body lowering path (`lower_annotated_expr` for `match_expr` passes arms through without
re-lowering their sealed ctors). Per the card it is **not forced** here. Authors use `if` for the guard
short-circuit (the idiomatic, now-working shape). Follow-up: `LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25`
— re-lower `match_node` arm bodies through the sealed-aware path (or carry their `annotated_expr`).

## 5. Tests and commands — exact pass counts

```text
$ cd lang/igniter-compiler && cargo test --test sealed_ctor_branch_tests → 1 passed; 0 failed  (NEW: branch ctor → tagged variant)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests     → 9 passed; 0 failed  (unchanged)
$ cd server/igniter-web    && cargo test                                 → 30 passed; 0 failed  (incl. todo_v2 natural-shape guard)
$ cd lang/igniter-compiler && cargo test  (full)                         → 68 passed; 4 failed  ← 4 failures PRE-EXIST (loop-IR-shape; identical at HEAD without this change)
$ cd lang/igniter-vm       && cargo test                                 → 15 passed; 1 failed  ← 1 failure PRE-EXISTS (loop proof; identical at HEAD)
$ git diff --check  → clean; only emitter.rs modified
```

**Zero regressions from this change:** the compiler suite is `68 passed / 4 failed` **both with and without
the emitter change** (verified by `git stash`); all 5 failing tests are pre-existing loop-IR-shape tests
unrelated to sealed constructors.

## 6. Files changed

- `lang/igniter-compiler/src/emitter.rs` — sealed-ctor recognition in `semantic_expr` (the only source change).
- `lang/igniter-compiler/tests/sealed_ctor_branch_tests.rs` — new IR-level regression test.
- `server/igniter-web/examples/todo_v2_app/todo_handlers.ig` — guards reverted to the natural `if`-shape;
  comment updated.

No VM / parser / typechecker-semantic / `igniter-server` / runner / `.igweb` / canon change.

## 7. Next recommendation

`LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25` — fix the remaining `match`-over-`Result`-returning-a-value
mis-bind (§4), so the P22-style `match { Ok{value} => ok(ctx) … }` guard also runs (it currently compiles
but 500s). Lower priority than this card because `if` already gives a clean, working composite-guard
short-circuit. After that, the IgWeb routing wave (scope → resource → nested → via → composite guard) is
runtime-complete; return to real app pressure or the relational QueryPlan bridge.

---

*Lab implementation (compiler). Compiled 2026-06-19; new branch-ctor IR test + igweb 9 + igniter-web 30
green; natural-shape composite guard runs through `igweb-serve`; zero regressions (compiler/VM counts
identical to HEAD; 5 pre-existing loop failures). One-spot emitter fix; no VM/server/runner/`.igweb`/canon
change.*
