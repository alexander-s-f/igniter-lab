# lab-igniter-web-routing-via-chain-readiness-p21-v0 — multi-`via` chain design

**Card:** `LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-READINESS-P21` · **Delegation:** `OPUS-IGWEB-VIA-CHAIN-P21`
**Status:** READINESS / DESIGN (v0) — designs multiple route-level `via` guards (left-to-right,
short-circuit). **No implementation, no parser/lowerer/compiler/server/runner change, no canon claim.**
**Authority:** Lab readiness. `.igweb` stays a **Projection Dialect**; generated `.ig` + real compiler
remain the behavioral truth. Builds on P20 (single `via`).

---

## 1. Executive summary

A naive multi-`via` chain over the built-in `Result` **cannot work**, and live code proves why: `match`
arm bodies are single expressions, pattern bindings are bare field names with **no rename**, and `Result`'s
success field is always `value` — so nesting one guard's `match` inside another's `Ok` arm **shadows** the
outer `value`, and a two-context handler can never see the first context. The fix is not a clever lowering;
it is choosing the right authoring model.

**Recommendation: do the composite-context guard FIRST, defer syntax-level chaining.** A single P20 `via`
whose guard internally chains loads (proven shape — `lead_router`/`call_router` already do exactly this) and
returns one context record covers the real multi-load use cases with **zero `.igweb` change** and maximum
transparency. Syntax-level `via A … via B …` is fully designed below but deferred, because it forces the
guard convention to shift from the clean built-in `Result[Ctx, Decision]` (which P20 just proved) to bespoke
per-guard variants with distinct success-field names — real authoring cost for marginal ergonomic gain.

Next card: **`LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22`** (document + fixture-prove the composite-guard
pattern; no lowering change).

## 2. Verify-first facts (live code; supersedes any older sketch)

| Fact | Verdict | Evidence |
|---|---|---|
| `match` arm body is a single expression (no `compute` inside an arm) | **confirmed** | `parser.rs:110-112` (`MatchArm.body: Box<Expr>`), `parse_match_arm_inner` → `parse_expr()` |
| match pattern bindings are bare field names; **no rename** (`Ok { value: x }` not supported) | **confirmed** | `parser.rs:115-120` (`MatchPattern.bindings: Vec<String>`), `parse_match_pattern_inner` pushes `name_token()` |
| built-in `Result` arms: `Ok { value }` / `Err { error }`; constructed by `ok(..)` / `err(..)` | **confirmed (P20)** | `typechecker.rs:360-405`, `:5160-5200`; P20 proof doc |
| **records construct as bare `{ field: value }` literals** (type from annotation), NOT `TypeName { … }` | **confirmed** | `lead_router/pipeline.ig:104-108` (`compute c0 = { params: params, … }`), `NullVendor` |
| a bespoke 2-arm variant can thread an accumulating context through a multi-step chain | **confirmed, live** | `lead_router`: `variant Pipe { Proceed { ctx }, Reject { stage, message } }`, `match prev { Reject{…}=>passthrough, Proceed{ctx}=> enrich-or-reject }` (`pipeline.ig:128-150`) |
| guards can chain internal `compute`/`call_contract` and return one value | **confirmed, live** | `call_router/service.ig:14-37`, `lead_router` step contracts |

**The shadowing hazard, concretely.** With built-in `Result`, the only short-circuiting shape is nesting:

```ig
match call_contract("LoadAccount", req, cap1) {
  Ok { value } =>                                   -- value = account
    match call_contract("LoadProject", req, value, cap2) {   -- account passed to LoadProject (ok)
      Ok { value } =>                               -- value = project — SHADOWS account
        call_contract("Handler", req, value, …)     -- can only see project, NOT account
      Err { error } => error
    }
  Err { error } => error
}
```

Because arm bodies are single expressions (no `compute` to stash the outer value) and bindings can't be
renamed, the handler in the inner arm cannot reach `account`. So **built-in `Result` chaining is structurally
impossible** for a handler needing ≥2 contexts. Short-circuit requires nesting (calling `LoadProject` only
inside `LoadAccount`'s `Ok`), so it can't be flattened away (Q6).

## 3. Recommendation (Q1)

**B — composite-context guard first.** Keep P20 single-`via` unchanged. Author one guard that internally
performs the chain and returns one context:

```igweb
route GET "/accounts/:account_id/projects/:project_id/todos/:todo_id"
  via LoadProjectTodoContext(account_id, project_id) as ctx
  -> ProjectTodoShow
```

```ig
-- guard (authored .ig), lead_router-style internal chaining, returns ONE context:
pure contract LoadProjectTodoContext {
  input req        : Request
  input account_id : Option[String]
  input project_id : Option[String]
  compute account : Result[Option[String], Decision] = ok(account_id)   -- or a real load
  compute r : Result[ProjectTodoCtx, Decision] = match account {
    Err { error } => err(error)
    Ok  { value } => ok({ account: value, project: project_id })         -- bare-record context
  }
  output r : Result[ProjectTodoCtx, Decision]
}
```

Generated routing `.ig` is **unchanged from P20** (one `match`, fully inspectable). This needs **no lowering
change** and reuses the P20-proven shape. It covers the real "load A then load B" needs; multi-`via` syntax
is sugar over it, not new power.

## 4. Rejected / deferred alternatives

- **A. Syntax-level chain over built-in `Result`** — *impossible* (shadowing, §2). Rejected on live grounds.
- **D. Generated helper contracts / wrapper records in routes.ig** — the lowering would synthesize contracts
  or records; record construction is a bare `{…}` literal whose type comes from an *annotation* the lowering
  can't supply context-free, and emitting synthetic contracts hurts the inspectability IgWeb promises.
  Rejected for transparency.
- **E. Syntax-level chain over bespoke per-guard variants** — *possible and clean*, but a **convention
  shift** (below). **Deferred**, not rejected: open it only if composite guards prove too clunky under real
  pressure.

## 5. Deferred design — syntax-level chain (for a later `…-VIA-CHAIN-P23`)

If/when syntax chaining is opened, this is the only live-expressible shape.

### 5.1 Grammar (Q2)

```igweb
route METHOD "pattern"
  via GuardA(arg, …) as a
  via GuardB(a, arg, …) as b      -- later guards may consume earlier `as` names AND path params
  -> Handler
```

- later guards **may** consume earlier contexts by `as` name and remaining path params;
- zero-arg guards allowed (`via RequireAuth() as session`);
- `via` stays **route-level only**, still forbidden after `->`, still forbidden on scope/resource headers;
- duplicate `as` names **rejected** (also pre-empts shadowing); forward references (`GuardA(b)` before `b`)
  **rejected**.

### 5.2 Return convention (the convention shift)

Each chained guard returns a **bespoke 2-arm variant** whose success-arm field name **equals its `as`
name**, with a fixed success-arm name and a uniform `Reject { decision : Decision }`:

```ig
variant LoadAccountResult { Loaded { account : Ctx }, Reject { decision : Decision } }
variant LoadProjectResult { Loaded { project : Ctx }, Reject { decision : Decision } }
```

Distinct field names (`account`, `project`) → distinct match bindings → **no shadowing**. This abandons the
built-in `Result` that P20 uses (its field is fixed `value`); single-`via` and multi-`via` would then differ,
or single-`via` would be retrofitted onto the bespoke convention — the main cost of this path.

### 5.3 Lowering sketch (Q5, strategy E)

```ig
match call_contract("LoadAccount", req, capture(req.path, "<re>", 1)) {
  Reject { decision } => decision
  Loaded { account } =>
    match call_contract("LoadProject", req, account, capture(req.path, "<re>", 2)) {
      Reject { decision } => decision
      Loaded { project } =>
        call_contract("ProjectTodoShow", req, account, project, capture(req.path, "<re>", 3))
    }
}
```

Left-to-right; first `Reject` returns `decision` and stops; distinct names keep both contexts live in the
innermost arm. Real compiler typechecks it (bespoke variants + match are live-proven by `lead_router`).

### 5.4 Handler args & "consumed" (Q3, Q4)

Order: `req, ctx_a, ctx_b, …, <path captures consumed by NO guard, in path order>`. "Consumed" = a path param
passed to **any** guard (not re-passed to the handler). Prior contexts passed to later guards are **still**
available to the handler (they're named bindings, not consumed). Captures used only on a failed path don't
arise — a failed guard short-circuits before later code.

### 5.5 Failure & idempotency (Q7, Q8)

Left-to-right short-circuit; guard-owned mapping; first `Reject { decision } => decision`. **No status-code
mapping in `.igweb`.** `requires idempotency` keeps the keyless 400 **outermost**, wrapping the whole nested
chain:

```ig
if req.idempotency_key == "" { Respond { status: 400, body: "missing idempotency-key" } } else { <nested chain> }
```

### 5.6 Composition (Q9)

Allowed in plain route, route in `scope`, resource action, and nested scope+resource — `via` rides the
**flattened** route exactly as P20's single `via` does; no new grouping, no route-priority change, 404/405
unchanged.

### 5.7 Rejections (Q10) — line-positioned `IgwebError`

duplicate `as` names · unknown guard arg name · guard references a later/undefined `as` name (forward ref) ·
context name colliding with a path-param name · `via` after `->` · `via` on scope/resource header · empty/bad
guard or context name · a guard arg that is neither a prior `as` name nor a path param.

## 6. Implementation acceptance-test matrix (Q11, for the deferred chain card)

1. two-guard chain lowers to the nested `Loaded/Reject` shape, left-to-right, exact snippet (byte-assert);
2. handler receives `req, ctx_a, ctx_b, <unconsumed captures>` in that order;
3. later guard consumes an earlier `as` name **and** a path param;
4. first `Reject` short-circuits (inner guard/handler absent on that path);
5. `requires idempotency` 400 guard outermost over the whole chain;
6. composition through scope / resource action / nested;
7. duplicate `as`, unknown arg, forward reference, name collision, `via`-after-`->`, header-`via` → errors;
8. **real multifile compile** of a chain (bespoke `Loaded/Reject` guards) clean — no `OOF-RE1`/`OOF-TY0`;
9. a guard whose success field ≠ its `as` name → **normal** typecheck failure (no bespoke `.igweb` rule);
10. determinism / byte-stability; `igniter-web`/`igniter-server` unchanged, serde-only.

(The composite-guard card `P22` needs a smaller matrix: the composite guard compiles + runs through P20's
single-`via` path unchanged; bare-record `{…}` context typechecks; no lowering change.)

## 7. Next-card recommendation (Q12)

**`LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22`** — document and fixture-prove the composite-context guard
pattern over the **unchanged** P20 lowering. Why: it is the smaller, honest step; it keeps generated `.ig`
maximally inspectable (one `match`); it needs no convention shift away from built-in `Result`; and it covers
the multi-load use cases today. Open `…-VIA-CHAIN-P23` (syntax-level chain, §5) only if real authoring
pressure shows composite guards are too clunky. Scope-level `via` inheritance remains a separate later track
(`…-VIA-SCOPE-READINESS`).

---

*Readiness/design only. Compiled 2026-06-19; grounded in live `parser.rs`, `typechecker.rs`, prod
`lead_router`/`call_router` `.ig`, and the P20 lowering/fixture. No code, parser, server, runner, or canon
change.*
