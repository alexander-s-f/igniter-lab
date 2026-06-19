# LAB-IGNITER-WEB-CONTEXT-COMPOSITION-READINESS-P25 - hierarchical request context composition

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab readiness
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-CONTEXT-COMPOSITION-P25

## Intent

Design the next IgWeb composition layer for "root controller" request context:

```text
ReqInfo / current user / auth session / tenant-account / timezone / locale /
permissions / request-scoped facts
```

The current `via` route guard is good for local route-specific loads, but it
does not cover hierarchical shared context without either duplication or hidden
server magic. This card should find a beautiful, explicit Igniter-like authoring
form that lowers deterministically to plain `.ig`.

Candidate shape to pressure-test:

```igweb
import ReqInfo, RequireUser, LoadAccount, LoadTodo

app TodoWeb entry Serve(req: Request) {
  let req_info = ReqInfo(req)
  guard user = RequireUser(req, req_info)

  scope "/accounts/:account_id" {
    guard account = LoadAccount(req, user, account_id)

    resource todos "/todos" {
      index GET -> TodoIndex(req, req_info, user, account)

      show GET "/:todo_id" {
        guard todo = LoadTodo(req, account, todo_id)
        -> TodoShow(req, req_info, user, account, todo)
      }
    }
  }
}
```

This is not a commitment to syntax. It is the primary sketch to test.

## Authority

Readiness/design only. `.igweb` remains a Projection Dialect. Generated `.ig`
and the real compiler remain the behavioral truth.

This card may create:

- one readiness packet under `lab-docs/lang/`;
- this card's closing report.

This card must **not** change:

- `lang/igniter-compiler/src/igweb.rs`;
- parser/typechecker/VM semantics;
- `server/igniter-web` runner/API;
- `server/igniter-server`;
- `runtime/igniter-machine`;
- examples/tests/fixtures;
- Cargo dependencies;
- canon docs.

No implementation. No source-map work. No DB/live effects. No public listener.

## Verify First

Read live code/docs before designing:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-web/examples/todo_v2_app/routes.igweb` if present
- `lab-docs/lang/lab-igniter-web-routing-via-p20-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md`
- `lab-docs/lang/lab-igniter-web-advanced-routing-readiness-p15-v0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`

Then verify the live language constraints this design depends on:

- whether generated `.ig` can represent inherited bindings using only current
  `compute`, `if`, `match`, `call_contract`, records, `Result`, and variants;
- built-in `Result` arm names and field names (`Ok { value }`,
  `Err { error }`) and how that affects multiple guard bindings;
- whether route blocks currently exist only as `.igweb` sugar or require new
  parser structure;
- how route-level `via` currently orders `req`, guard context, and remaining
  captures;
- how `scope` and `resource` erase to flat routes;
- how P23 Todo V2 pressure, if already present, exposes duplication or
  readability pain.

Live code wins over this card's sketch.

## Problem Statement

IgWeb now has:

- `scope` for path hierarchy;
- `resource` for method/path sugar;
- route-level `via` for one local guard context;
- composite guards for multi-load inside one authored `.ig` contract;
- `igweb-serve` for no-Rust app startup.

But common web apps need shared request context:

- request id / correlation / normalized headers / cookies;
- current user/session;
- tenant/account;
- timezone/locale;
- permission context;
- route-subtree-specific parent records.

Writing these as `via` on every route duplicates code and hides the intended
hierarchy. Moving them into `igniter-server` or Rust middleware would break the
route-free/domain-free server boundary and recreate Rails callback magic.

We need a Projection-Dialect form for **hierarchical context composition**:
explicit in `.igweb`, inherited by nested route scopes, passed explicitly to
handlers, and lowered to ordinary `.ig`.

## Key Design Questions

Answer all questions in the readiness packet:

1. **Concept name.** Is the right term `context`, `let/guard binding`,
   `pipeline`, `before`, `use`, or something else? Prefer terms that avoid
   hidden middleware/callback connotations.
2. **Syntax.** Evaluate at least these families:
   - `let req_info = ReqInfo(req)` / `guard user = RequireUser(...)`;
   - `context req_info = ReqInfo(req)` / `context user via RequireUser(...)`;
   - `use RequireUser as user`;
   - block-local route body bindings only.
3. **Return convention.** Should fallible bindings require
   `Result[T, Decision]`? Should infallible bindings be plain values? Is the
   distinction explicit (`let` vs `guard`) or inferred from type?
4. **Inheritance.** How do bindings flow through `app`, `scope`, `resource`,
   and route body blocks? What shadows what? What name collisions are refused?
5. **Handler arguments.** Are inherited contexts automatically passed, or must
   handlers list them explicitly? The expected answer should preserve explicit
   dataflow.
6. **Lowering.** Sketch generated `.ig` for:
   - app-level `let`;
   - app-level `guard`;
   - scope-level guard consuming a path param;
   - route-local guard consuming both context and path param;
   - mutating route with `requires idempotency`.
7. **Short-circuit.** What response does a failed guard return? Does the guard
   own failure mapping (`Err { error : Decision }`) as P20 does?
8. **Ordering.** Does `requires idempotency` remain outermost? Do app/scope
   guards run before or after method/path match? Avoid doing expensive auth for
   unrelated paths if the generated shape can stay clean.
9. **Cookies/headers/request info.** Should `.igweb` introduce cookie/header
   syntax, or should this remain ordinary `Request` + `ReqInfo(req)` contracts?
10. **Relationship to P8 Rust middleware.** What belongs in server middleware
    (`TraceApp`, `BodyLimitApp`, auth envelope) vs IgWeb context composition
    (current user, account, timezone)?
11. **Relationship to P20/P22 `via`.** Does route-level `via` remain useful?
    Should `guard` binding supersede it or coexist?
12. **Projection Dialect contract.** How does the design maintain:
    deterministic lowering, inspectable generated `.ig`, no hidden runtime
    authority, no server route table, and no domain leakage into server core?
13. **Error model.** What line-positioned `IgwebError`s are needed for unknown
    names, duplicate bindings, forward references, invalid `guard` return
    shape, context/path-param collisions, and block misuse?
14. **Minimum implementation slice.** What is the smallest next implementation
    after readiness? It should be one bounded P-card, not the whole framework.

## Required Comparisons

Compare the design against:

- Rails root controller filters / `before_action` / current_user;
- Rack middleware (wrapper pipeline, route-free server);
- Sidekiq middleware (serialized payload + infrastructure concerns);
- current IgWeb `via` and composite-guard pattern.

Do not cargo-cult Rails. Extract only successful patterns:

- hierarchy and locality are useful;
- hidden mutable controller state is not;
- metaprogrammed callback magic is not;
- server-domain coupling is not.

## Required Output

Create:

```text
lab-docs/lang/lab-igniter-web-context-composition-readiness-p25-v0.md
```

The packet must include:

1. executive summary;
2. verify-first facts and any deltas from this card;
3. problem statement with concrete Todo/Spark-shaped pressure examples;
4. evaluated syntax options and recommendation;
5. proposed semantics for `let`/`guard` or the chosen alternative;
6. inheritance and name-resolution rules;
7. lowering sketches to plain `.ig`;
8. short-circuit and idempotency ordering rules;
9. relationship to Rust middleware, route-level `via`, and composite guards;
10. closed surfaces / anti-magic rules;
11. implementation acceptance matrix for the next card;
12. next-card recommendation.

## Acceptance

- [x] No production code, tests, examples, or Cargo files changed.
- [x] The packet answers all 14 design questions.
- [x] The packet explicitly states why route-level `via` alone is insufficient.
- [x] The packet preserves server route-free/domain-free boundary.
- [x] The packet preserves explicit handler dataflow; no hidden controller ivars
      or implicit globals.
- [x] The packet gives at least one generated `.ig` sketch for app/scope/route
      binding.
- [x] The packet handles P21 shadowing constraints honestly; no impossible
      `Result` nesting claims.
- [x] The packet says whether cookies/headers are Request/ReqInfo concerns or
      new `.igweb` syntax.
- [x] The packet identifies the smallest safe implementation card after P25.
- [x] This card is closed with a concise closing report.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-igniter-web-context-composition-readiness-p25-v0.md` — readiness packet,
**no code** (`git diff` clean; only packet + card new). Answers all 14 questions + the required comparisons
and lowering sketches.

**Recommendation:** two explicit binding keywords — **`let`** (infallible value → plain `compute`) and
**`guard`** (fallible `Result[T, Decision]` → `match`/`if` short-circuit) — at `app`/`scope`/route-body
level, **inherited** by nested routes (lowering replays the active chain into each flattened route arm),
with **explicit handler arg lists** (no auto-injection). Generalizes route-level `via`.

**Honest core (the P21 wall, re-verified against P24):** built-in `Result` arms bind the fixed field
`value`, match arms can't rename or introduce computes, so **N guards nest N matches and inner `value`s
shadow outer ones**. Deep chains (user@app → account@scope → todo@route) therefore need an **accumulating
context record** (live-proven `lead_router` pattern, now ergonomic post-P24 via `if { ok(enriched) } else { err }`),
not separate bindings — OR distinct-field bespoke variants. **`let`s never shadow** (top-level computes).
So **v0 narrows to `let` + ONE `guard` per route** (no stacking → no shadow), collapsing to the exact P20
shape; depth-2 accumulation is a deferred slice. No impossible `Result`-nesting claimed.

**Other answers:** guards run *inside* the route arm (after path/method match — no auth on unrelated
paths); idempotency-400 stays outermost (P20 order); cookies/headers stay `Request` + an authored
`ReqInfo(req)` contract (**no new `.igweb` syntax**); transport (trace/body-limit/auth-envelope) stays P8
Rust middleware, domain context stays IgWeb bindings; `via` coexists as the single-route alias.

**Delta flagged:** the card's sketch needs **real new grammar** (app param list, app/scope `let`/`guard`
statements, route body blocks, explicit handler arg lists) — not sugar over the current line-oriented
dialect; P26 is a parser+lowering card, not pure lowering.

**Next:** `LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26` — smallest slice (§16): `let` + one `guard` + explicit
handler args, compile + runtime proof. Depth-2 accumulation (`…-P27`) follows. `LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25`
(P24 follow-up) remains orthogonally worthwhile but `if` already suffices.

## Suggested Next Card Name

If readiness supports the direction:

```text
LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26
```

Expected implementation should be intentionally narrow: app/scope/route-local
`let` + single `guard`, explicit handler args, deterministic lowering, compile
proof. Defer source-map, multi-guard stacks, automatic handler arg injection,
assets, DB integration, and canon.
