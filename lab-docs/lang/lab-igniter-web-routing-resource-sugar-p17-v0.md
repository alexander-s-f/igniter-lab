# lab-igniter-web-routing-resource-sugar-p17-v0 — `.igweb` `resource` sugar

**Card:** `LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P17` · **Delegation:** `OPUS-IGWEB-RESOURCE-P17`
**Status:** CLOSED (lab implementation) — a `resource <name> "<base>" { … }` authoring block that expands
REST-shaped action lines into ordinary flat `.igweb` routes via a **closed action table used as a
validator, not a generator**. Proven byte-identical to hand-written flat routes, composing with P16
`scope`, and compiling clean through the real multifile compiler.
**No `nested` keyword, no `via`, no source-map, no runner/CLI change, no `igniter-server` change, no
contract-name generation, no pluralization, no resource-level idempotency default, no canon claim.**
**Authority:** Lab tooling. `.igweb` stays a **Projection Dialect**; the generated `.ig` is the
behavioral truth. Implements P15 §4.2 and builds on
`lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md`.

## Verify-first deltas confirmed

The P15/P16 facts held and shaped the implementation:

1. **Params bind positionally; names author-facing.** A `resource` action never names or binds params; it
   only contributes path suffix text that lowers to positional `capture(...)`.
2. **Duplicate names refused on composed patterns.** Reused unchanged — a scope+resource path that repeats
   `:id` is refused (test 9), because resource delegates to `parse_route`.
3. **405-vs-404 from same-path grouping.** `index` + `create` land in one `/todos` pattern group, so 405
   emerges with no resource-specific code (test 6).
4. **`scope` composes.** A `resource` inside a `scope` composes prefix → base → suffix (test 8).

## Grammar delta

Added one block form (and nothing else):

```igweb
resource <name> "<base>" {
  index  GET             -> TodoIndex
  create POST            -> TodoCreate requires idempotency
  show   GET    "/:id"   -> TodoShow
  update PATCH  "/:id"   -> TodoUpdate requires idempotency
  delete DELETE "/:id"   -> TodoDelete requires idempotency

  member     POST "/:id/done" -> TodoDone   requires idempotency
  collection GET  "/search"   -> TodoSearch
}
```

- `resource` may appear inside `app { … }` or inside `scope { … }`.
- `<name>` is author-facing only — **never** used to derive a contract name.
- `<base>` is a quoted path starting with `/`; composes with the active scope prefix.
- v0 keeps the resource body flat: only action lines and `}` (no nested `scope`/`resource` inside a
  resource — those dispatch as unknown actions and are refused).
- malformed resource lines and unclosed resources produce line-positioned `IgwebError`.

## Closed action table (validator, not generator)

| action | method rule | suffix rule | effective suffix |
|---|---|---|---|
| `index` | must be `GET` | none allowed | `/` (→ base) |
| `create` | must be `POST` | none allowed | `/` (→ base) |
| `show` | must be `GET` | optional | supplied or `/:id` |
| `update` | must be `PATCH` or `PUT` | optional | supplied or `/:id` |
| `delete` | must be `DELETE` | optional | supplied or `/:id` |
| `member` | explicit method | **required** quoted suffix | supplied |
| `collection` | explicit method | **required** quoted suffix | supplied |

**Rationale.** The full seven-action table was kept (not narrowed) because each action is one match arm
and one acceptance test — the table is small, closed, and fully covered, so narrowing would lose
coverage without reducing risk. The table only *validates* method + suffix shape and computes the
effective suffix; it **never** invents a contract name, a method, or a path. `member`/`collection` are
the explicit escape hatch and therefore demand an explicit method + suffix (no convention to draw from).

## Exact lowering rule

`resource` is **authoring sugar, erased before lowering**, reusing the P16/P4 route path verbatim:

1. The parser tracks `in_resource: Option<(String, usize)>` = the resource's absolute base (`scope`
   prefix composed with `<base>`) plus the header line for unclosed-block diagnostics. `}` closes the
   innermost block: resource → scope → app.
2. Each action line is parsed by `parse_resource_action`: split on `->` (so a missing contract is a clear
   error even with no suffix), read the method + optional quoted suffix, validate via the closed table to
   get the *effective suffix*, then **synthesize the equivalent flat route tail**
   `<METHOD> "<effective>" -> <Contract> [requires idempotency]` and feed it to the existing
   `parse_route(tail, base)`.
3. `parse_route` then does the **unchanged** work: compose `base + effective`, build the anchored regex,
   refuse duplicate params, attach the idempotency guard, and emit the static `call_contract` arm. So
   resource sugar adds **zero new lowering** — composition, dup-refusal, grouping, 405/404, and the 400
   guard all come from the path already proven in P16/P4.

```text
resource todos "/todos" { show GET "/:id" -> TodoShow }
        │  table: show → method GET ok, effective suffix "/:id"
        ▼  synthesize  GET "/:id" -> TodoShow   on base "/todos"
        │  existing parse_route + P4 lowering, unchanged
        ▼  if matches(req.path, "^/todos/([^/]+)$") { if req.method == "GET" {
             call_contract("TodoShow", req, capture(req.path, "^/todos/([^/]+)$", 1))
           } else { Respond 405 } } else { … Respond 404 }
```

## Anti-magic policy (explicit)

- **No auto contract names.** `index GET -> TodoIndex` is valid only because `TodoIndex` is authored;
  `index GET` (no `->`) is refused (test 2). There is no `TodosController#index`, no derivation.
- **No pluralization / inflection.** `<name>` is inert.
- **No hidden parent loading.** A nested resource is `scope`-wraps-`resource` path composition only; no
  parent record is fetched (that would be `via`, deferred).
- **No resource-level idempotency default.** Each mutating action declares `requires idempotency`
  explicitly; the lowering never infers a guard from the method.
- **No controller conventions, no server route table** — the generated `Serve` capsule is still the only
  route table.

## Same-path grouping / 405 proof

`index GET` and `create POST` both compose to base `/todos`, so they share one `matches(req.path, "^/todos$")`
arm with a GET→POST method chain ending in `Respond 405`. Asserted directly:
`resource_same_path_grouping_405` checks **exactly one** `^/todos$` matches-arm plus both method arms and
the presence of `405`/`404`. `resource_default_member_suffix_is_id` likewise asserts a single
`^/todos/([^/]+)$` arm for `show`+`update`+`delete`. So `DELETE /todos` → 405 (not 404) and
`PUT /todos/:id` → 405, exactly as flat routes would.

## Scope composition proof

`scope "/accounts/:account_id" { resource todos "/todos" { index … ; show GET "/:todo_id" … } }` lowers to
`^/accounts/([^/]+)/todos$` and `^/accounts/([^/]+)/todos/([^/]+)$` with positional captures 1/2
(`resource_composes_with_scope`). Duplicate names across the composition are refused
(`resource_duplicate_param_refused`: `scope "/todos/:id" { resource comments "/comments" { show GET "/:id" } }`).

## Tests and commands — exact pass counts

```text
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 29 passed; 0 failed  (16 prior + 13 new)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests →  4 passed; 0 failed  (3 prior + 1 new)
$ cd server/igniter-web    && cargo test                             → 29 passed; 0 failed  (5 builder + 7 example + 17 runner)
$ cd server/igniter-server && cargo test --features machine          → all green; 0 failed (14 binaries)
$ cd server/igniter-server && cargo tree -e normal | grep -iE 'igniter-web|igniter-compiler|regex|tokio' → (none) serde-only
$ git diff --check                                                   → clean (implementation only igweb.rs + tests; plus proof/card docs)
```

New lib tests (13) — mapped to the card's required behaviors:

- **1 byte identity** `resource_is_byte_identical_to_flat`.
- **2 explicit contract** `resource_requires_explicit_contract` (line 4, message mentions `->`).
- **3 method validation** `resource_action_method_is_validated` (`index POST`, `create GET`).
- **4 default suffix** `resource_default_member_suffix_is_id` (show/update/delete → `/:id`, single group).
- **5 custom suffix** `resource_custom_suffixes_lower` (`show "/:slug"`, `member "/:id/done"`).
- **6 grouping/405** `resource_same_path_grouping_405`.
- **7 idempotency** `resource_idempotency_guard`.
- **8 scope composition** `resource_composes_with_scope`.
- **9 duplicate refusal** `resource_duplicate_param_refused`.
- **10 source order** `resource_preserves_source_order` (route/resource/scope interleave).
- **13 determinism** `resource_lowering_is_deterministic`.
- robustness: `resource_member_needs_suffix_and_unknown_refused`, `unclosed_resource_is_reported`.

New integration test (1) — covers card tests **1 + 11** together:

- `resource_todo_is_byte_identical_to_flat_and_compiles` — the 5-route Todo authored with a `resource`
  block lowers **byte-identically** to the flat `TODO_IGWEB` **and** compiles clean through the **real**
  multifile compiler (no `OOF-RE1`, no `OOF-TY0`).

Card test **12 (no server change)** verified by the green `igniter-web`/`igniter-server` runs + serde-only
`cargo tree` (both untouched on disk).

## Closed surfaces (still closed after this card)

`nested` keyword, `via`, `.igweb`→`.ig` source maps, package manager, runner/CLI changes,
`igniter-server` changes, live effects / public bind / credentials / `[effects]`, canon claim, controller
conventions, contract-name generation, and resource-level idempotency defaults. Only `igweb.rs` + its
tests changed.

## Honest limitations (carried + new)

- Literal segments are still assumed regex-safe (P4); resource bases/suffixes concatenate more literals,
  so a regex metacharacter in a base or suffix is an unescaped sharp edge (acceptable lab v0).
- The resource body is flat in v0: no `scope`/`resource` nested *inside* a resource (they parse as unknown
  actions and are refused). Cross-resource nesting is expressed as `scope`-wraps-`resource`, which P18 will
  prove as composition.
- Unknown-action and nested-block-inside-resource share the generic "unknown resource action" diagnostic;
  acceptable for v0.
- Authoring distance from `.igweb` to generated `.ig` grows further with resources; the deferred source
  map gains value but is not required here.

## Next recommendation

`LAB-IGNITER-WEB-ROUTING-NESTED-P18` — a **composition proof only**: prove `scope`-wraps-`resource`
nesting end-to-end (param merge across nesting, duplicate refusal, flat boring output, real compile).
**Adds no keyword** — `scope` already nests (P15 §4.3). Then the separate
`LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19` track designs the guard pipeline (typed context + failure
mapping), which is not path matching.

---

*Lab implementation. Compiled 2026-06-19; igniter-compiler 29 lib + 4 integration green; resource Todo
lowers byte-identically to flat and compiles clean through the real multifile compiler; igniter-web 29
green; igniter-server green + serde-only. No server/runner/canon change.*
