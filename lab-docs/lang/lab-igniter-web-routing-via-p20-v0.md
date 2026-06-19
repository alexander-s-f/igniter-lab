# lab-igniter-web-routing-via-p20-v0 — route-level single `via` guard

**Card:** `LAB-IGNITER-WEB-ROUTING-VIA-P20` · **Delegation:** `OPUS-IGWEB-VIA-P20`
**Status:** CLOSED (lab implementation) — one route-level `via Guard(args) as name` guard, lowering to a
static `call_contract + match` over the built-in sealed `Result`. The guard either produces a typed
context for the handler (`Ok`) or short-circuits with a `Decision` (`Err`). Proven through the **real**
multifile compiler.
**No multi-`via`, no scope/resource-level `via`, no source-map, no runner/CLI change, no `igniter-server`
change, no dynamic dispatch, no effect/capability identity in `.igweb`, no canon claim.**
**Authority:** Lab tooling. `.igweb` stays a **Projection Dialect**; generated `.ig` is the behavioral
truth. Implements P19's narrow recommendation.

## Verify-first deltas (live code corrected the P19 sketch)

P19 designed the shape; building it against the **real** compiler corrected two concrete facts — both
found by running the generated `.ig` through `igniter_compiler`, not by reading docs:

1. **Built-in `Result` arm fields are `Ok { value }` and `Err { error }` — NOT `Err { value }`.**
   `typechecker.rs:360-405` (`sealed_arm_field_types`): `Result[P0,P1] → Ok{value:P0}, Err{error:P1}`.
   The first compile attempt with `Err { value } => value` failed with
   *"binding 'value' is not a field of Result::Err"*. The lowering now emits `Err { error } => error`.
2. **Sealed `Result`/`Option` are constructed by the lowercase functions `ok(..)` / `err(..)` (and
   `some(..)` / `none()`), NOT by record-literal `Ok { value: .. }`.** `typechecker.rs:5160-5200` handles
   `ok`/`err` as sealed constructors; a bare `Ok { .. }` is treated as user-variant construction and fails
   *"variant_construct arm 'Ok' is not declared in any variant"*. This only affects **guard authoring**
   (the fixture/app side), not the generated routing `.ig` — the lowering only ever *matches* `Result`,
   never constructs it. The fixture guard is `compute r : Result[Option[String], Decision] = ok(account_id)`.

Both deltas are now encoded in the lowering + fixture and proven by a clean real compile. Everything else
in P19 held: variants/`match`/multiple-compute/`call_contract`/positional captures all behaved as designed.

## Grammar delta

One optional route-level clause, between the pattern and `->`:

```igweb
route GET "/accounts/:account_id/todos/:todo_id"
  via LoadAccount(account_id) as account
  -> AccountTodoShow
```

The single-line form is equivalent and also supported:

```igweb
route GET "/accounts/:account_id/todos/:todo_id" via LoadAccount(account_id) as account -> AccountTodoShow
```

- `via <Contract>(<param,...>) as <name>` — `Contract` is a static literal; args are author-facing path
  param names from the composed pattern; `<name>` is author-facing (lowered to the built-in `Ok { value }`
  binding — runtime stays positional).
- Works in `resource` actions too (they synthesize route tails that delegate to route parsing), so it
  composes with P16 `scope` / P17 `resource` / P18 nesting.
- **Multi-line authoring** is supported via a small line-folding pre-pass (`fold_logical_lines`): a
  `route`/action statement lacking `->` greedily joins following non-block lines until `->` appears.
  Single-line statements already contain `->`, so P16/P17/P18 output is byte-unchanged (verified).

Rejected in P20 (line-positioned `IgwebError` or downstream `expected ->`): a second `via`, `via` on a
`scope`/`resource` header, `via` after `->`, omitted `as`/name, missing parens/guard name, and a guard
arg that is not a path param.

## Why P20 is single route-level `via` only

P19 §7 (delta #2 there): both `Result` arms bind a fixed field, so chaining guards by nesting one `match`
in another's `Ok` arm shadows the success binding. Rather than ship a half-working chain, v0 takes **one**
guard; multi-step loading is expressed by a **composite-context guard** (a single guard contract that does
several `compute`/`call_contract` loads internally and returns one context) — a proven shape, no `.igweb`
change. Multi-`via` and scope-level `via` are deferred (see "Next").

## Exact lowering rule

`via` changes **only** the per-route handler expression (`handler_arm`); the if/method tree, pattern
grouping, 404/405, and scope/resource composition are untouched. For

```igweb
route GET "/accounts/:account_id/todos" via LoadAccount(account_id) as account -> AccountTodosIndex
```

the route arm becomes:

```ig
match call_contract("LoadAccount", req, capture(req.path, "^/accounts/([^/]+)/todos$", 1)) {
  Ok { value } => call_contract("AccountTodosIndex", req, value)
  Err { error } => error
}
```

(emitted single-line). Steps:

1. **Guard call** — `call_contract("<Guard>", req, <each named arg → its positional capture>)`. Arg names
   resolve statically to `capture(req.path, "<re>", i)` by their position in the composed pattern; an
   unknown name is a line error.
2. **Match** — the built-in sealed `Result`: `Ok { value } => <handler call>` and
   `Err { error } => error` (the guard's short-circuit `Decision` forwarded unchanged).
3. **Handler call** — `call_contract("<Handler>", req, value, <captures NOT consumed by the guard, in path
   order>)`. A capture passed to the guard is consumed (not re-passed); the handler receives the typed
   context, not the raw string.

No custom typechecking is added in `.igweb`: if the guard does not return `Result[_, Decision]`, or the
handler signature does not match `req, Ctx, remaining captures`, the **normal** compiler rejects the
generated `.ig` (proven — see tests).

## `Result[Ctx, Decision]` return-shape proof

`via_project_compiles_clean` lowers a 3-route via app (index/show/create) whose guard is
`LoadAccount(req, account_id) -> Result[Option[String], Decision] = ok(account_id)` and whose handlers
take `account` (+ `todo_id` for show), then compiles it through the **real** multifile compiler — **no
`OOF-RE1`, no `OOF-TY0`**. The negative `via_guard_returning_non_result_fails_typecheck` points `via` at
`Health` (which returns `Decision`, not `Result`); the generated `match { Ok … Err … }` then **fails** the
normal typecheck — proving P20 added no bespoke `.igweb` type rule and leans on the compiler.

## Handler argument / consumed-capture rule

Handler args = `req`, the guard's `value`, then captures whose param name was **not** a guard arg, in path
order. Proven by `via_handler_gets_value_then_unconsumed_captures`: for
`/accounts/:account_id/todos/:todo_id via LoadAccount(account_id) as account -> AccountTodoShow`, the
handler call is `call_contract("AccountTodoShow", req, value, capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 2))`
— `account_id` (capture 1) consumed, `todo_id` (capture 2) passed through.

## Idempotency ordering proof

`requires idempotency` keeps the keyless `400` guard **outermost**, wrapping the via match (fail fast
before loading). Proven by `via_idempotency_guard_is_outermost`:
`if req.idempotency_key == "" { Respond { status: 400, … } } else { match call_contract("LoadAccount", req … }`.

## Resource / scope / nested composition proof

`via_through_scoped_resource_action`: a `show GET "/:todo_id" via LoadAccount(account_id) as account`
inside `scope "/accounts/:account_id" { resource todos "/todos" { … } }` lowers to the composed
`^/accounts/([^/]+)/todos/([^/]+)$` with the guard capturing index 1 and the handler receiving `value` +
capture 2 — `via` rides the flattened route untouched; no new grouping, priority, or 404/405 change.

## Tests and commands — exact pass counts

```text
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 45 passed; 0 failed  (36 prior + 9 new)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests →  7 passed; 0 failed  (5 prior + 2 new)
$ cd server/igniter-web    && cargo test                             → 29 passed; 0 failed  (5 builder + 7 example + 17 runner)
$ cd server/igniter-server && cargo test --features machine          → all green; 0 failed (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | grep -iE 'igniter-web|igniter-compiler|regex|tokio' → (none) serde-only
$ git diff --check                                                   → clean (only igweb.rs + its tests changed; new via fixture)
```

New lib tests (9): `via_lowers_to_guard_match` (1+2+7), `via_handler_gets_value_then_unconsumed_captures`
(3), `via_unknown_arg_refused` (4), `via_bad_shapes_refused` (5, six shapes), `via_idempotency_guard_is_outermost`
(6), `via_through_scoped_resource_action` (8+9), `via_multiline_equals_single_line`, `via_lowering_is_deterministic`
(13), `via_zero_arg_guard`. New integration tests (2): `via_project_compiles_clean` (10), `via_guard_returning_non_result_fails_typecheck`
(11). Test 12 (no server change) = green `igniter-web`/`igniter-server` + serde-only tree.

## Files changed

- `lang/igniter-compiler/src/igweb.rs` — `Via` struct + `Route.via`; `fold_logical_lines` (multi-line);
  `parse_via_inner`/`strip_keyword`/`capture_expr`; `via` parsing in `parse_route` + arg→capture
  resolution; `via` forwarding in `parse_resource_action`; guard-match emission in `handler_arm`.
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs` — via lib + integration tests.
- `lang/igniter-compiler/tests/fixtures/igweb_via/handlers.ig` — guard returning `Result[Option[String], Decision]`
  via `ok(..)`, plus context-taking handlers (test support).

## Closed surfaces (still closed)

multi-`via`, scope-level `via`, resource-header `via`, `via` inheritance, source-map, runner/CLI change,
`igniter-server` change, package manager/dialect registry, real auth/secrets/passport/SparkCRM/DB/network/
public bind, dynamic dispatch, capability identity / effect policy in `.igweb`, canon claim.

## Honest limitations

- **Reject-as-effect not statically enforced.** `Err { error } => error` forwards whatever `Decision` the
  guard returns; v0 documents (does not enforce) that a guard rejection should be a `Respond`, not an
  `InvokeEffect`. Deferred to a lint/later card.
- **Context type in the proof fixture is `Option[String]`**, chosen to keep the compile proof about the
  guard-match lowering rather than record construction (record/`type` values construct differently — see
  delta #2; the guard-match shape is the thing P20 proves).
- **`as <name>` is author-facing only** — it lowers to the built-in `Ok { value }` binding. A named
  runtime binding would need bespoke per-guard variants (a multi-`via` concern, deferred).

## Next recommendation

`LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-P21` — multi-`via` left-to-right short-circuit, requiring either
bespoke per-guard variants with **distinct** success-arm field names (so nested matches don't shadow) or a
binding-rename lowering; and/or `LAB-IGNITER-WEB-ROUTING-VIA-SCOPE-P22` — scope-level `via` inheritance
into nested handlers (input-order + shadowing design). Both build on this route-level proof.

---

*Lab implementation. Compiled 2026-06-19; igniter-compiler 45 lib + 7 integration green; a route-level
`via` app compiles clean through the real multifile compiler (`match` over built-in `Result`); a
non-`Result` guard correctly fails the normal typecheck; igniter-web 29 green; igniter-server green +
serde-only. No server/runner/canon change.*
