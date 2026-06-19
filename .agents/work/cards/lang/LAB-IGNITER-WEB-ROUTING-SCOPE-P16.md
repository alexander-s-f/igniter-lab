# LAB-IGNITER-WEB-ROUTING-SCOPE-P16 — `.igweb` scope prefix lowering

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-SCOPE-P16

## Intent

Implement the first advanced IgWeb routing slice: **`scope` only**.

`scope` is pure authoring typography:

```igweb
scope "/accounts/:account_id" {
  route GET "/todos"          -> AccountTodosIndex
  route GET "/todos/:todo_id" -> AccountTodoShow
}
```

It must lower to the exact same flat route semantics the author could write by hand:

```igweb
route GET "/accounts/:account_id/todos"          -> AccountTodosIndex
route GET "/accounts/:account_id/todos/:todo_id" -> AccountTodoShow
```

No new runtime behavior. No route table. No resources. No `via`.

## Authority

Lab implementation only. `.igweb` remains a Projection Dialect that deterministically lowers to
ordinary `.ig`; generated `.ig` + compiler/VM/server path remain the behavioral truth.

This card may change:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- a proof doc under `lab-docs/lang/`
- this card's closing report

Everything else is closed unless verify-first proves an unavoidable test-support touch is needed.

## Verify First

Before editing, read the live surfaces:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `lab-docs/lang/lab-igniter-web-advanced-routing-readiness-p15-v0.md`
- `server/igniter-web/README.md`
- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-web/src/lib.rs`

Live code wins. P15 found three important live facts:

1. Param names are author-facing today; handler calls bind params positionally via `capture(..., idx+1)`.
2. Duplicate param names are not refused today; P16 must add refusal for composed patterns.
3. 405-vs-404 is an emergent property of pattern grouping; `scope` must preserve the existing grouping.

## Scope Grammar

Add only:

```igweb
scope "<prefix>" {
  route ...
  scope ...
}
```

Rules:

- `scope` may appear only inside `app { ... }`.
- `scope` prefix must be a quoted path starting with `/`.
- nested `scope` is allowed.
- `route` inside scope uses the existing route grammar unchanged.
- composed path is `scope_prefix + route_pattern`, with exactly one `/` at the join.
- scope disappears before the existing route grouping / `.ig` generation.
- line-positioned `IgwebError` for malformed scope lines and unclosed scopes.

## Required Behavior

### Prefix composition

`scope "/accounts/:account_id" { route GET "/todos" -> X }`
must be byte-identical to the generated `.ig` from flat
`route GET "/accounts/:account_id/todos" -> X`, modulo only unavoidable comments if the existing
generator forces them. Prefer exact byte identity.

### Positional params

Param capture order is path order across the composed prefix+route:

```igweb
scope "/accounts/:account_id" {
  route GET "/todos/:todo_id" -> AccountTodoShow
}
```

Generates regex:

```text
^/accounts/([^/]+)/todos/([^/]+)$
```

and handler call arguments:

```text
capture(..., 1), capture(..., 2)
```

### Duplicate param refusal

Refuse duplicate param names in the **composed** pattern:

```igweb
scope "/x/:id" {
  route GET "/y/:id" -> X
}
```

Return `IgwebError` with the offending route/scope line and a clear message. This is new behavior and
is intentional: names are author-facing, so duplicate names are ambiguity, not data.

### Source order and grouping

Flatten scopes in source order. Interleaved plain routes and scoped routes must preserve authored order.
Existing first-seen pattern grouping must remain unchanged, so 405/404 behavior is preserved.

## Closed Surfaces

- No `resource`.
- No `nested` keyword.
- No `via`.
- No source-map.
- No package manager.
- No runner/CLI changes.
- No `igniter-server` changes.
- No live effects, public bind, credentials, or `[effects]`.
- No canon claim.
- No controller conventions or contract-name generation.

## Required Tests

Add focused tests in the existing IgWeb lowering test area. Cover all:

1. **Prefix composition:** scoped route lowers byte-identically to equivalent flat route.
2. **Positional param merge:** composed regex and captures are in path order.
3. **Nested scope:** `scope "/a/:x" { scope "/b/:y" { route GET "/c" -> X } }` lowers to
   `^/a/([^/]+)/b/([^/]+)/c$`.
4. **Duplicate-param refusal:** repeated `:id` across scope+route returns `IgwebError` with line.
5. **Source order preserved:** plain/scope/plain interleaving keeps generated arm order.
6. **404 / 405 unchanged:** scoped GET-only path still has method-mismatch 405 and unmatched-path 404.
7. **Idempotency through scope:** scoped mutating route still emits the `status: 400` keyless guard.
8. **Real compile:** generated scoped project compiles with real multifile compiler; no `OOF-RE1` /
   `OOF-TY0`.
9. **No server change:** `igniter-server` tree untouched; `igweb-serve` untouched.
10. **Determinism:** same `.igweb` lowers to byte-identical `.ig` across two calls.

## Required Proof Doc

Write:

`lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md`

Include:

- grammar delta;
- exact lowering rule;
- duplicate param policy;
- tests and commands with exact pass counts;
- explicit statement that `resources`, `via`, server/runner, and source-map remain closed;
- next route recommendation, likely `LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P17`.

## Suggested Commands

Adjust after verify-first:

```bash
cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd server/igniter-web && cargo test
cd server/igniter-server && cargo test --features machine
git diff --check
```

If `server/igniter-web` / `server/igniter-server` are not touched, they are still useful boundary
regressions. If skipped, state why.

## Acceptance

- [x] Verify-first surfaces read and any deltas reported.
- [x] `scope` grammar implemented; nested `scope` works.
- [x] All 10 required tests covered.
- [x] Real compiler proof passes.
- [x] No `igniter-server` / runner changes.
- [x] Proof doc written.
- [x] Card updated with closing report and status `CLOSED`.

---

## Closing Report (2026-06-19)

**Deliverable:** `scope "<prefix>" { … }` implemented in `lang/igniter-compiler/src/igweb.rs` as pure
authoring typography that composes a path prefix onto its routes and **vanishes before** the existing
flat-route lowering. Proof doc: `lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md`.

**Implementation (only `igweb.rs` + its tests changed):**
- `lower_igweb` keeps a stack of absolute scope prefixes; `}` closes the innermost scope, else the app.
- `compose_path(prefix, suffix)` joins with one `/` and canonicalizes the trailing slash (so composed
  pattern strings stay canonical → first-seen grouping / 405 intact).
- `parse_route` takes the enclosing prefix, composes **before** `pattern_to_regex`, then lowers as flat.
- `parse_scope_prefix` parses `scope "<prefix>" {` with line-positioned errors; unclosed scope reported.
- **Duplicate param refusal** on the composed pattern (`first_duplicate`) — new behavior; also retroactively
  refuses flat `/a/:id/b/:id`.

**Verify-first deltas confirmed:** (1) params bind positionally (names author-facing); (2) duplicate names
now refused; (3) scope erases before grouping, so 404/405 unchanged — proven by byte-identity.

**Proof — all green:**
- `cargo test --lib igweb::tests` → **16 passed** (4 prior + 12 new).
- `cargo test --test igweb_lowering_tests` → **3 passed** (2 prior + 1 new). The new
  `scoped_todo_is_byte_identical_to_flat_and_compiles` proves the scoped 5-route Todo lowers
  **byte-identically** to the flat form **and** compiles clean through the real multifile compiler
  (no `OOF-RE1`/`OOF-TY0`) — covering required tests 1 + 8 together.
- `server/igniter-web` → **29 passed** (consumer of `lower_igweb`, untouched).
- `server/igniter-server --features machine` → green; `cargo tree -e normal` serde-only (untouched).
- `git diff --check` clean.

**Closed surfaces honored:** no `resource`/`nested`/`via`, no source-map, no runner/CLI/server change, no
canon claim, no contract-name generation. **Next:** `LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P17`.
