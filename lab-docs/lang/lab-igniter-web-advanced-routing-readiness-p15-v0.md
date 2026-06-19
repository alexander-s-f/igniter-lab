# lab-igniter-web-advanced-routing-readiness-p15-v0 — scope / resources / nested / via

**Card:** `LAB-IGNITER-WEB-ADVANCED-ROUTING-READINESS-P15` · **Delegation:** `OPUS-IGWEB-ADVANCED-ROUTING-P15`
**Status:** READINESS / DESIGN (v0) — proposes the next `.igweb` routing-DX layer above the flat-route
proof. **No code, no parser/lowerer change, no server change, no runner change, no canon claim.**
**Authority:** Lab readiness. `.igweb` stays a **Projection Dialect**
(`lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`): authored sugar that deterministically lowers
to ordinary, inspectable `.ig`. The generated `.ig` + existing compiler/VM/server path remain the
behavioral truth.

---

## 0. Verify-first — live surfaces actually read

Read on 2026-06-19 (all paths resolved after the lab reorg; no broken link encountered):

| Surface | What it told us |
|---|---|
| `lang/igniter-compiler/src/igweb.rs` | The whole lowering. `lower_igweb(src) -> Result<String, IgwebError>`. Flat `route METHOD "pat" -> Contract [requires idempotency]`. `pattern_to_regex` turns `:name` → `([^/]+)`, anchored `^…$`. Emits `module AppRoutes` / `pure contract <entry>` with a nested `if matches(req.path, "<re>") { method-chain } else { next } … Respond 404`. Each arm is a **static** `call_contract("Literal", req, capture(req.path,"<re>",i)…)`. |
| `lang/igniter-compiler/tests/igweb_lowering_tests.rs` | Generated 5-route Todo compiles clean through the **real** multifile compiler (no `OOF-RE1`/`OOF-TY0`); `/accounts/:account_id/todos/:id` lowers to two positional captures. |
| `server/igniter-web/src/lib.rs` | `build_igweb_app` lowers `.igweb`, loads the combined modules into `IgniterMachine`, returns an erased `Arc<dyn ServerApp>`. `IgWebServerApp::call` just `dispatch(entry, req)` → maps `Decision` → `ServerDecision`. **The host owns NO route table.** |
| `server/igniter-web/src/bin/igweb-serve.rs` + runner in `lib.rs` | `igweb.toml` + sources → build → `ReloadableApp` → bounded `serve_loop`. Manifest cannot name routes/bind/secrets/effect identity. |
| `server/igniter-web/examples/todo_app/{routes.igweb,todo_handlers.ig}` | Live authored shapes. Handlers take params as `input id : Option[String]`. |
| `server/igniter-web/README.md` | Mental model: app owns routes/handlers/types/effect-targets; server owns transport/loop/reload/middleware. |
| `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md` | The governance contract: deterministic lowering, inspectable target, no hidden runtime authority, no dynamic dispatch beyond target, no server-core/domain leak. |
| `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md` | P4 proof + honest limitations: literal segments assumed regex-safe; import plumbing fixed; "no resource grouping (deferred to `…-RESOURCE-SUGAR-P*`)". |
| `lab-docs/lang/lab-igniter-web-runner-p12-v0.md`, `…-runner-check-p14-v0.md` | Generic runner + `check` dry-build; loopback only; effects observed as protocol decisions (`202`), never executed. |

**Deltas vs the card's assumptions (live code wins):**

1. **Param names are author-facing only.** In `handler_arm`, params iterate as `(idx, _name)` — the
   name is discarded; only the **positional** `capture(..., idx+1)` reaches the handler. So today
   `:account_id` and `:id` are documentation, not bindings. Any future `scope`/`resources`/`via`
   name-merge story is therefore about *authoring clarity and collision detection*, not about a runtime
   name → value map. This is load-bearing for §7 and §10.
2. **Duplicate param names are currently NOT refused.** `pattern_to_regex` happily emits two
   `([^/]+)` for `/a/:id/b/:id`. Flat authoring rarely hits this; **`scope` makes it routine**
   (prefix `:id` + route `:id`). So duplicate-name refusal is *new behavior the first advanced card must
   add*, not a regression of something that exists.
3. **405-vs-404 is an emergent property of pattern grouping**, not a routing feature: same-path routes
   share one `matches(...)` arm whose inner method-chain ends in `Respond 405`; an unmatched path falls
   through every arm to the trailing `Respond 404`. Any sugar that lowers same-path actions into the
   **same pattern group** inherits correct 405 for free (§9).

---

## 1. Current surface summary (what flat `.igweb` supports and how it lowers)

Grammar (P4, live):

```igweb
app <Name> entry <ServeContract> {
  handlers <ModuleName>
  route <METHOD> "<pattern>" -> <Contract> [requires idempotency]
  ...
}
```

Lowering (deterministic, byte-stable; routes keep source order, patterns grouped first-seen):

```text
module AppRoutes
import IgWebPrelude
import <ModuleName>

pure contract <entry> {
  input req : Request
  compute decision : Decision =
    if matches(req.path, "^/todos/([^/]+)$") {
      if req.method == "GET" {
        call_contract("TodoShow", req, capture(req.path, "^/todos/([^/]+)$", 1))
      } else { Respond { status: 405, body: "method not allowed" } }
    } else {
      … next pattern …
      Respond { status: 404, body: "not found" }
    }
  output decision : Decision
}
```

- `:name` segment → regex group `([^/]+)`; pattern → anchored `^…$`.
- params extracted positionally `capture(req.path,"<re>",i)` (1-based), typed `Option[String]`.
- `requires idempotency` → fail-closed `if req.idempotency_key == "" { Respond 400 } else { <call> }`.
- targets are **static literal** `call_contract` — no dynamic dispatch.
- 404 = no pattern matched; 405 = pattern matched, method did not.

This is the behavioral truth every advanced layer below must lower **back down to, unchanged**.

---

## 2. Design principles (the bar every option must clear)

Carried verbatim from P0 + the card; an option that violates any MUST is rejected, not negotiated.

1. **Transparent lowering (MUST).** Sugar deterministically expands to the *same flat route list* the
   author could have written by hand. No behavior exists only in the sugar.
2. **Explicit contract names (MUST).** Every handler is named in source. **No** `Todo`+`index`→`TodoIndex`
   synthesis, no pluralization, no controller-name derivation.
3. **Source-order determinism (MUST).** Flattened routes preserve authored order; pattern grouping stays
   first-seen. Same input → byte-identical `.ig`.
4. **Inspectable generated `.ig` (MUST).** The expanded routes remain a flat, boring `if/match` tree a
   human and an agent can read and re-compile. "Do not hand-edit", but always readable.
5. **No server route table (MUST).** `igniter-server`/`igweb-serve` never learn patterns; the route table
   *is* the generated `Serve` capsule. Verified live: `IgWebServerApp::call` only `dispatch`es.
6. **No hidden controller conventions (MUST).** No implicit action→method/path/name mapping that the
   reader can't see in the generated `.ig`. Any convention is a *small, closed, documented table*, applied
   visibly, never derived from naming.
7. **No effect authority in routing sugar (MUST).** Routing sugar names logical targets at most; it
   introduces no IO/effect/secret/passport. `requires idempotency` stays a fail-closed guard, not an
   effect.
8. **No dynamic dispatch beyond the target (MUST).** `.ig` has none; every lowered call stays a literal.
   This is the hard wall under `via` (§4.4): a guard pipeline must lower to `match`-over-static-calls.
9. **Reduce boilerplate without adding semantics (SHOULD, the dialect smell test).** If a feature adds
   *meaning* rather than *typography*, it's a contract/library, not a dialect feature.

---

## 3. Option matrix

Legend: **Power** = DX leverage gained · **Magic** = distance between source and generated `.ig`
(lower is better) · **New semantics** = does it add meaning beyond path typography?

| Option | Power | Magic | New semantics? | Lowers to flat routes? | Static dispatch kept? | Verdict |
|---|---|---|---|---|---|---|
| **`scope` prefix + param group** | Med | **Low** | No (pure string prefix) | Yes — concat prefix+pattern, reuse `pattern_to_regex` | Yes | **Ship first (P16).** Highest value-to-magic ratio. |
| **`resources` action macro** | **High** | Med | Mild — a *closed, visible* action→(method,suffix) table | Yes — each action → one `route` line | Yes | **Ship second (P17),** explicit contracts only, no auto-naming. |
| **nested via `scope`+`resource`** | Med | Low | No (composition of two proven layers) | Yes | Yes | **Ship third (P18) as composition.** Reject a dedicated `nested` keyword. |
| **dedicated `nested {}` keyword** | Low | Med | Yes — a *second* scoping mechanism w/ its own rules | Yes | Yes | **Reject.** `scope` already nests; new keyword = surface w/o power. |
| **resource-level `requires idempotency` default** | Low | Med | Yes — implicit per-method guard | Yes | Yes | **Defer/reject.** Auto-applying guards by method is the magic we avoid; keep it per-action. |
| **`via` guard pipeline** | High | **High** | **Yes** — parent-contract call + typed context + failure→Decision mapping + name binding | Yes (as `match` over static calls) — but needs a standardized result variant | Yes (if designed carefully) | **Defer to its own track.** It's a request-pipeline/guard feature, not path matching. |
| **conventional auto-names (`TodoIndex` from `todos`+`index`)** | Low | **High** | Yes — naming magic | n/a | n/a | **Reject permanently.** Violates principle 2 & 6. |
| **server-side route table** | — | — | — | — | — | **Reject permanently.** Violates principle 5. |

---

## 4. The four candidate layers, evaluated separately

### 4.1 `scope` — prefix + param grouping

**Proposed v0 syntax:**

```igweb
scope "/accounts/:account_id" {
  route GET "/todos"          -> AccountTodosIndex
  route GET "/todos/:todo_id" -> AccountTodoShow
}
```

**Lowering = textual prefix composition, then the existing flat pipeline.** `scope "/p" { route M "/s" -> C }`
≡ `route M "/p/s" -> C`. After concatenation, nothing downstream changes: `pattern_to_regex`, pattern
grouping, method chains, 404/405, captures all behave exactly as if the author wrote the flat route.
**Scopes vanish at lowering** — this is the anti-magic core: there is no "scope matched" runtime state.

Answers to the card's research questions:

- **Should `scope` be the first advanced primitive?** Yes. It is the only option that is pure typography
  (zero new semantics) yet removes the dominant real-world boilerplate (repeated path prefixes).
- **How do nested params merge?** By **position**, because that is all the live lowering uses (delta #1).
  `:account_id` from the prefix is `capture(...,1)`; `:todo_id` from the route is `capture(...,2)`. The
  handler receives them in path order. Names stay author-facing.
- **How does it lower to flat routes?** Concatenate `scope.prefix + route.pattern` (normalizing the `/`
  join), emit ordinary `route` lines, then run the unchanged P4 lowering.
- **Duplicate param names?** **Refuse at lowering** with a line-positioned `IgwebError` once the *composed*
  pattern contains a repeated `:name` (e.g. `scope "/x/:id" { route GET "/y/:id" }`). New behavior (delta
  #2). Rationale: positional capture means a duplicate name is silently ambiguous to the reader; fail
  closed. (This also retroactively hardens flat routes against `/a/:id/b/:id`.)
- **Should route order remain pure source order?** Yes. Flatten scopes in source order; a route inside a
  scope takes the position of its `route` line. Pattern grouping stays first-seen on the flattened list.

Nesting `scope` inside `scope` is just prefix-of-prefix — same rule, no special case.

### 4.2 `resources` — explicit authoring macro

**Proposed v0 syntax (the value is a *closed, visible* action table — not naming magic):**

```igweb
resource todos "/todos" {
  index  GET            -> TodoIndex
  create POST           -> TodoCreate  requires idempotency
  show   GET    "/:id"  -> TodoShow
  update PATCH  "/:id"  -> TodoUpdate  requires idempotency
  delete DELETE "/:id"  -> TodoDelete  requires idempotency

  member POST "/:id/done" -> TodoDone  requires idempotency
}
```

**Lowering = each action line → one flat `route` line under the resource base path:**

```igweb
route GET    "/todos"          -> TodoIndex
route POST   "/todos"          -> TodoCreate  requires idempotency
route GET    "/todos/:id"      -> TodoShow
route PATCH  "/todos/:id"      -> TodoUpdate  requires idempotency
route DELETE "/todos/:id"      -> TodoDelete  requires idempotency
route POST   "/todos/:id/done" -> TodoDone    requires idempotency
```

Then the unchanged P4 pipeline. Crucially `index`+`create` collapse onto base `/todos` (one pattern,
GET/POST method-chain) and `show`/`update`/`delete` onto `/todos/:id` (one pattern, three-method chain) —
so **405 emerges for free** (e.g. `DELETE /todos` → 405, `PUT /todos/:id` → 405). This is a concrete
lowering obligation: actions that share a composed path MUST land in the same pattern group.

Answers to the card's research questions:

- **Should contracts always be named explicitly in v0?** **Yes — MUST.** No auto-naming. `index` does not
  imply a `TodoIndex` contract; the author writes `-> TodoIndex`. This is the single most important
  anti-Rails decision.
- **Should conventional names be rejected/deferred?** Conventional *name derivation* is rejected
  permanently (principle 2). Conventional *method+suffix* (the action table) is accepted but **validated,
  not invented** (next bullet).
- **Which REST actions belong in v0?** The closed standard set `{index, show, create, update, delete}`
  plus the custom escapes `{member, collection}`. The standard five carry a canonical (method, suffix):
  `index`=GET base, `create`=POST base, `show`=GET `/:id`, `update`=PATCH `/:id`, `delete`=DELETE `/:id`.
  **The author still writes the method**; the lowering **refuses a method that contradicts the action's
  canonical method** (e.g. `index POST` → line error). So the table is a *validator*, not a generator —
  source stays fully explicit, mistakes are caught, nothing is hidden. (`PUT` vs `PATCH` for `update`:
  accept either; refuse `GET`.)
- **Should unsupported actions fail at lowering time?** Yes — an unknown action keyword → line-positioned
  `IgwebError`. `member`/`collection` are the explicit escape hatch: they require an explicit METHOD and
  suffix (member = `/:id/<verb>`, collection = `/<verb>`) precisely because there is no convention to draw
  from, so nothing is implicit.
- **How do key/idempotency requirements compose?** Per-action `requires idempotency`, identical to flat
  routes — see §8. **No** auto-idempotency-by-method.

### 4.3 nested resources — composition, not a new keyword

**Recommendation: nested resources = `scope` wrapping `resource`. Do NOT add a `nested` keyword.**

```igweb
resource accounts "/accounts" {
  show GET "/:id" -> AccountShow
}

scope "/accounts/:account_id" {
  resource todos "/todos" {
    index GET           -> AccountTodosIndex
    show  GET   "/:todo_id" -> AccountTodoShow
  }
}
```

Lowers to flat:

```igweb
route GET "/accounts/:id"                         -> AccountShow
route GET "/accounts/:account_id/todos"           -> AccountTodosIndex
route GET "/accounts/:account_id/todos/:todo_id"  -> AccountTodoShow
```

Answers to the card's research questions:

- **Should `nested` exist, or is `scope` enough?** `scope` is enough. `scope "/accounts/:account_id" { resource todos … }`
  already expresses nested resources with **zero new primitives**. A dedicated `nested {}` block inside
  `resource` would be a *second* scoping mechanism with its own param-merge rules — more surface, no new
  power. **Reject `nested`.** (This refines the card's thesis: P18 proves *composition*, it does not add a
  keyword.)
- **Should nested resources be sugar over explicit `scope`?** Yes — that is exactly the recommendation.
- **How are parent/child param names chosen without magic?** They are not "chosen" — the author writes
  `:account_id` and `:todo_id` literally; merge is positional (delta #1); duplicate names across the
  nesting are refused (§4.1). No `parent_id`-style synthesis.
- **Can the lowered `.ig` stay flat and boring?** Yes — it is the same three flat routes shown above. The
  nesting is entirely an authoring-time concatenation.

### 4.4 `via` — contract pipeline (defer to its own track)

**Pressure example:**

```igweb
scope "/accounts/:account_id" via LoadAccount {
  route GET "/todos/:todo_id" -> TodoShow
}
```

**This is feasible to keep static, and that is the interesting finding** — but it is a *request-pipeline /
guard-contract* feature, not path matching, and should not ride in on the scope card. A faithful lowering
would be:

```text
match call_contract("LoadAccount", req, capture(path, <re>, 1)) {
  Found(ctx)   -> call_contract("TodoShow", req, ctx, capture(path, <re>, 2))
  Reject(deci) -> deci      -- the guard's own Respond 404/403/500
}
```

That is `match` over **static** `call_contract`s — no dynamic dispatch, so principle 8 survives. But it
forces four genuinely new design decisions that path-matching never raised:

- **What type does the parent return?** It cannot return a bare context (failure must short-circuit). It
  needs a standardized sum, e.g. `variant Loaded[T] { Found { value: T }, Reject { decision: Decision } }`,
  which every guard contract must adopt. That is a *contract convention*, i.e. new semantics.
- **Where does failure mapping live?** Inside the guard contract (it returns `Reject { decision }`), not
  in the routing sugar — otherwise the sugar would acquire effect/decision authority (principle 7).
- **How are names bound into the child input?** The guard's `value` must thread into the child
  `call_contract` as an argument, ahead of the path captures. That is a binding rule the flat model has no
  analogue for.
- **Can it stay static?** Yes (shown above) — this is why `via` is *eventually* in-bounds, not forbidden.

Answers to the card's research questions: `via` **is** a separate request-pipeline feature (not routing);
the parent returns a standardized `Loaded`-style sum; failure mapping lives in the guard contract; names
bind positionally ahead of captures; it stays static `call_contract`; and **yes, P15 recommends deferring
`via`** until `scope` + `resources` are proven. It earns a *readiness* card of its own, informed by this
sketch.

---

## 5. Recommended sequence (P16 → P18, + a separate `via` track)

Ordered by risk (lowest first); each lowers to the unchanged P4 flat pipeline.

1. **`LAB-IGNITER-WEB-ROUTING-SCOPE-P16`** — `scope "/prefix/:param" { route … }` only. Prefix
   composition, positional param merge, **duplicate-param refusal**, nested `scope`-in-`scope`,
   source-order + 404/405 preserved. **No** resources, **no** server change. *Lowest risk: pure
   typography.*
2. **`LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P17`** — `resource <name> "<base>" { <action> METHOD ["suffix"] -> Contract [requires idempotency] }`.
   Closed action table as **validator**, explicit contracts (no auto-naming), `member`/`collection`
   escapes, same-path actions grouped into one pattern (correct 405), per-action idempotency. Composes
   with P16 scope. *Medium risk: a small closed convention.*
3. **`LAB-IGNITER-WEB-ROUTING-NESTED-P18`** — prove `scope`-wraps-`resource` nesting end-to-end (param
   merge across nesting, duplicate refusal, flat boring output). **Adds no keyword.** *Low risk: pure
   composition of P16+P17.*
4. **`LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19`** *(separate track, readiness first)* — design the
   guard-contract pipeline: the `Loaded` sum convention, failure mapping ownership, name binding, and the
   `match`-over-static-calls lowering. **No implementation in the readiness card.**

This both honors and sharpens the card's thesis: scope → resources → nested, via deferred — with two
refinements grounded in live constraints: (a) **nested needs no new keyword** (delta: `scope` already
nests, so P18 is composition not a primitive); (b) the resource action table is a **validator, not a
generator** (delta #1: names are author-facing, so the dialect should *check* method/suffix, never
*invent* contract names).

---

## 6. Concrete v0 syntax proposal

**Todo (flat + scope + resource forms, all lowering identically):**

```igweb
app TodoWeb entry Serve {
  handlers TodoHandlers

  route GET "/health" -> Health        -- plain routes still allowed alongside sugar

  resource todos "/todos" {
    index  GET            -> TodoIndex
    create POST           -> TodoCreate requires idempotency
    show   GET    "/:id"  -> TodoShow
    member POST "/:id/done" -> TodoDone requires idempotency
  }
}
```

**Nested account/todo (scope-wrapping-resource):**

```igweb
app AccountsWeb entry Serve {
  handlers AccountHandlers

  resource accounts "/accounts" {
    show GET "/:id" -> AccountShow
  }

  scope "/accounts/:account_id" {
    resource todos "/todos" {
      index GET             -> AccountTodosIndex
      show  GET "/:todo_id" -> AccountTodoShow
    }
  }
}
```

Plain `route`, `scope`, and `resource` are freely interleavable; all three are authoring forms over the
**same** flat route list.

---

## 7. Lowering sketch (generated flat arms + static `call_contract`)

The nested example above expands (before the P4 `.ig` emit) to this flat list, in source order:

```igweb
route GET "/health"                              -> Health
route GET "/accounts/:id"                        -> AccountShow
route GET "/accounts/:account_id/todos"          -> AccountTodosIndex
route GET "/accounts/:account_id/todos/:todo_id" -> AccountTodoShow
```

…and then through the **unchanged** P4 generator to (abbreviated):

```text
if matches(req.path, "^/health$") {
  if req.method == "GET" { call_contract("Health", req) } else { Respond { status: 405, … } }
} else if matches(req.path, "^/accounts/([^/]+)$") {
  if req.method == "GET" {
    call_contract("AccountShow", req, capture(req.path, "^/accounts/([^/]+)$", 1))
  } else { Respond { status: 405, … } }
} else if matches(req.path, "^/accounts/([^/]+)/todos$") {
  if req.method == "GET" {
    call_contract("AccountTodosIndex", req, capture(req.path, "^/accounts/([^/]+)/todos$", 1))
  } else { Respond { status: 405, … } }
} else if matches(req.path, "^/accounts/([^/]+)/todos/([^/]+)$") {
  if req.method == "GET" {
    call_contract("AccountTodoShow", req,
      capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 1),
      capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 2))
  } else { Respond { status: 405, … } }
} else { Respond { status: 404, body: "not found" } }
```

Every arm is a static literal `call_contract`; every param is a positional `capture`. **The advanced
sugar adds exactly zero new node types to the generated `.ig`.** That is the whole proposal: new
*authoring*, identical *artifact*.

---

## 8. Param model

- **Ordered captures (the only binding mechanism).** Params reach handlers positionally,
  `capture(req.path, "<re>", i)` 1-based, in path order across scope+resource composition. Grounded in
  delta #1.
- **Named params (`:name`).** Author-facing: improve readability and drive duplicate detection. Names do
  **not** appear in generated `.ig`; handlers still bind by position (`input id : Option[String]`,
  `input todo_id : Option[String]` in path order). A future named-binding model is out of scope and would
  be a *compiler/canon* change, not a dialect change.
- **Duplicate names.** Refused at lowering on the **composed** pattern, line-positioned. New behavior
  (delta #2); chiefly motivated by `scope`/nesting where prefix+route name clashes become common.
- **Optional / missing values.** No optional-segment syntax (`:id?`) in v0. A path that lacks a segment
  is simply a *different path* → no pattern matches → `404`. `capture` types as `Option[String]` purely
  because the regex stdlib returns an option; under a matched route the group is always present.
- **Unicode / regexp assumptions.** `:name` → `([^/]+)` matches any non-`/` run, Unicode included (Rust
  regex is Unicode-aware). **Literal segments are still assumed regex-safe** (alnum/`-`/`_`), the P4
  limitation — and scope/resource composition *concatenates more literal segments*, so a production
  lowering must escape regex metacharacters in literal prefix/suffix parts. Flag for P16: a `scope` prefix
  containing a regex metachar is a sharp edge; either escape literals or refuse non-`[A-Za-z0-9_-/:]`
  prefix chars in v0.

---

## 9. Idempotency model

- `requires idempotency` stays **per route / per action**, lowering to the same fail-closed guard:
  `if req.idempotency_key == "" { Respond 400 } else { <call> }`, emitted *before* the handler can return
  `InvokeEffect`.
- In `resource`, mutating actions (`create`/`update`/`delete`/mutating `member`) declare it **explicitly**;
  the lowering never infers it from the method. A resource-level default (`resource todos "/todos" requires idempotency { … }`)
  is **deferred/rejected** for v0 — auto-applying a guard by HTTP method is exactly the implicit behavior
  the dialect avoids (principle 6). Explicit per-action keeps the guard visible at each call site.
- The guard is a pure 400 decision, never an effect — so idempotency stays inside principle 7 (no effect
  authority in routing sugar). Actual effect execution remains host-gated (observed `202`, never run).

---

## 10. 404 vs 405 under scopes / resources / nesting

**Unchanged from the flat model, by construction**, because the sugar vanishes at lowering (§7):

- **404** — the composed path matched **no** pattern arm (falls through to trailing `Respond 404`). There
  is no "scope matched but child didn't" state: a scope is string concatenation, not a runtime gate. So
  `/accounts/1/nope` → 404 even though `/accounts/:account_id/...` scopes exist.
- **405** — a composed pattern matched the path but the **method** arm didn't (inner method-chain ends in
  `Respond 405`). Correct 405 depends on the **same-path-grouping obligation**: `resource` MUST lower
  `index`+`create` onto one `/todos` pattern and `show`+`update`+`delete` onto one `/todos/:id` pattern,
  so e.g. `DELETE /todos` and `PUT /todos/:id` yield 405, not 404. This is the single behavioral
  invariant the resource lowering must test (§12).
- **Edge note:** because params are `([^/]+)`, `/accounts//todos` (empty segment) does **not** match
  `/accounts/:account_id/todos` → 404. Acceptable and consistent across all forms; document it.

---

## 11. Agent / DX evaluation

| Form | Human read | Agent **generate** | Agent **debug** | Net |
|---|---|---|---|---|
| flat `route` | verbose but total | trivial (no convention knowledge) | trivial (source ≈ artifact) | best transparency, worst density |
| `scope` | clear | trivial (prefix concat) | easy (mentally inline the prefix) | **best ratio** |
| `resource` | most compact | needs the closed action table | easy *if* the table is documented | best human DX, mild agent load |
| `nested` keyword (rejected) | two scoping models to learn | harder | harder | worse than scope-wrap |
| `via` (deferred) | compact | needs `Loaded` convention | hardest (control-flow not just paths) | power at real cost |

Key DX findings:

- **The generated flat `.ig` is the debugging surface for every form.** An agent diagnoses a routing bug
  by reading `routes.ig`, where scope/resource have already disappeared into explicit arms. This is the
  payoff of "no new node types" (§7).
- **Advanced sugar widens the `.igweb`↔`.ig` line distance**, which raises the value of the *deferred*
  source map (`LAB-IGNITER-WEB-SOURCE-MAP-READINESS-P15`, P0 §4 SHOULD). Recommend: when P17 lands, a
  downstream compile error on a generated arm should be traceable to the `resource`/`scope` line. Not a
  blocker for P16 (scope distance is small), but it should land before resources see heavy use.
- **For agents authoring routes, `scope` is the safe default** (no convention to memorize); `resource` is
  a productivity win once the closed action table is in the dialect docs. Auto-naming would have been an
  agent *trap* (it must guess the derived contract name) — another reason it stays rejected.

---

## 12. Risks & anti-magic list (intentionally rejected or deferred)

**Rejected permanently:**

- Auto-derived contract names (`todos`+`index` → `TodoIndex`). Violates principles 2 & 6.
- Auto-pluralization / inflection of any kind.
- A server-side route table or any pattern knowledge in `igniter-server`/`igweb-serve`. Violates 5.
- Dynamic dispatch (`call_contract(req.something, …)`). Violates 8.
- Implicit parent-record loading triggered by nesting (the Rails `before_action` reflex). That is `via`,
  and it is *explicit* or it does not exist.

**Deferred (in-bounds later, with a named card):**

- `via` guard pipeline → `LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19` (§4.4).
- Dedicated `nested {}` keyword → not planned; `scope`-wrap covers it (§4.3).
- Resource-level idempotency default → revisit only if explicit-per-action proves painful (§9).
- Named (non-positional) param binding → a compiler/canon concern, not a dialect feature (§8).
- `.igweb`→`.ig` source map → readiness already carded; pair with P17.

**Live risks to manage in implementation:**

1. **Regex-metachar literals** in scope prefixes / resource bases (§8) — escape or restrict.
2. **Duplicate param names** now reachable routinely via scope (§4.1) — must refuse, line-positioned.
3. **Same-path grouping** in resources — must land actions in one pattern or 405 silently degrades to 404
   (§10) — must test.
4. **Source-order flattening** of interleaved plain/scope/resource forms — must stay deterministic and
   first-seen for pattern grouping (§2.3).

---

## 13. Acceptance tests for the first implementation card (`…-SCOPE-P16`) — specified, not implemented

These are the obligations P16 must prove (mirroring the P4 test style: lib-unit lowering + a real
multifile compile). **Do not implement here.**

1. **Prefix composition.** `scope "/accounts/:account_id" { route GET "/todos" -> X }` lowers to the
   **byte-identical** `.ig` of the hand-written flat `route GET "/accounts/:account_id/todos" -> X`.
2. **Positional param merge.** `scope "/accounts/:account_id" { route GET "/todos/:todo_id" -> X }` →
   `matches(req.path, "^/accounts/([^/]+)/todos/([^/]+)$")` + `capture(...,1)` + `capture(...,2)` in path
   order.
3. **Nested scope.** `scope "/a/:x" { scope "/b/:y" { route GET "/c" -> X } }` →
   `^/a/([^/]+)/b/([^/]+)/c$`.
4. **Duplicate-param refusal.** `scope "/x/:id" { route GET "/y/:id" -> X }` → `IgwebError` with the
   offending line.
5. **Source order preserved.** Interleaved plain routes and a scope keep authored order; pattern grouping
   stays first-seen (assert generated arm order).
6. **404 / 405 unchanged.** A scoped GET-only path yields 405 for POST and 404 for an unmatched sibling
   path (assert `status: 405` / `status: 404` present in the right arms).
7. **Idempotency through scope.** `scope "/a/:x" { route POST "/y" -> X requires idempotency }` still emits
   the `status: 400` keyless guard inside the composed arm.
8. **Real compile.** The generated scoped project compiles clean through the **real** multifile compiler —
   no `OOF-RE1`, no `OOF-TY0` (reuse the P4 `compile_generated` harness).
9. **No server change.** `igniter-server` tree stays serde-only; `igweb-serve` is untouched.
10. **Determinism.** Same `.igweb` → byte-identical `.ig` across two lowerings.

(P17 resources and P18 nested will carry their own acceptance lists — notably the resource **same-path
grouping → 405** test and the **action-method validation** refusals — when those cards open.)

---

## Acceptance — this card

- [x] Verify-first cites current live files actually read (§0), incl. three deltas where live code
      corrected the card's framing.
- [x] All 12 required analysis sections answered (§1 surface, §2 principles, §3 matrix, §5 sequence,
      §6 syntax, §7 lowering, §8 params, §9 idempotency, §10 404/405, §11 DX, §12 risks, §13 P16 tests).
- [x] Preserves `.igweb` as a Projection Dialect (every form lowers to the unchanged flat `.ig`; no new
      generated node types — §7).
- [x] Keeps the server route-free and domain-free (§2.5, §10; grounded in live `IgWebServerApp::call`).
- [x] Syntax examples include flat, scoped, resource, nested, and `via` pressure (§4, §6).
- [x] First implementation card named and bounded: `LAB-IGNITER-WEB-ROUTING-SCOPE-P16` (§5, §13).
- [x] Thesis pressure-tested: order upheld, with two live-grounded refinements (nested needs no keyword;
      resource table validates rather than generates) (§5).

---

*Readiness/design only. Compiled 2026-06-19; grounded in live `igweb.rs` + `igniter-web` runner/server +
P0/P4/P12/P14 docs. No code, parser, server, runner, or canon change.*
