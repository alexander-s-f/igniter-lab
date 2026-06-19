# lab-igniter-web-routing-scope-p16-v0 — `.igweb` `scope` prefix lowering

**Card:** `LAB-IGNITER-WEB-ROUTING-SCOPE-P16` · **Delegation:** `OPUS-IGWEB-SCOPE-P16`
**Status:** CLOSED (lab implementation) — the first advanced IgWeb routing slice: a `scope "<prefix>" { … }`
authoring block that **deterministically composes a path prefix onto its routes and disappears before
the existing flat-route lowering**. Proven byte-identical to hand-written flat routes and compiling clean
through the real multifile compiler.
**No `resource`, no `nested` keyword, no `via`, no source-map, no runner/CLI change, no `igniter-server`
change, no canon claim.**
**Authority:** Lab tooling. `.igweb` stays a **Projection Dialect**
(`lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`); the generated `.ig` remains the behavioral
truth. Implements the recommendation in
`lab-docs/lang/lab-igniter-web-advanced-routing-readiness-p15-v0.md`.

## Verify-first deltas confirmed in code

The three P15 live facts held and shaped the implementation:

1. **Params bind positionally.** `handler_arm` emits `capture(req.path, "<re>", idx+1)` and discards the
   `:name`. So scope param-merge is positional: the prefix's `:account_id` is `capture(...,1)`, the
   route's `:todo_id` is `capture(...,2)`. Names stay author-facing.
2. **Duplicate names were not refused.** Now refused on the **composed** pattern (and, by the same code
   path, on a flat `/a/:id/b/:id`). New, intentional behavior.
3. **405-vs-404 is emergent from pattern grouping.** `scope` is pure prefix composition that vanishes
   before grouping, so grouping/405/404 are untouched — confirmed by the byte-identity proof.

## Grammar delta

Added one block form (and nothing else):

```igweb
scope "<prefix>" {
  route ...
  scope ...
}
```

- `scope` may appear only inside `app { … }`; nested `scope` is allowed.
- the prefix is a quoted path starting with `/`; the line ends with `{`.
- `route` inside a scope uses the **existing** route grammar unchanged.
- malformed scope lines and unclosed scopes produce line-positioned `IgwebError`
  (unclosed uses `line: 0`, matching the existing unclosed-`app` diagnostic).

## Exact lowering rule

`scope` is **authoring typography, erased at lowering**. There is no runtime "scope matched" state.

1. The parser keeps a **stack of absolute (already-composed) scope prefixes**. Entering
   `scope "/p" {` pushes `compose_path(current_base, "/p")`; `}` pops the innermost scope, or closes the
   `app` block when no scope is open.
2. Each `route` composes its own pattern onto the innermost prefix:
   `compose_path(prefix, route_pattern)`, where `compose_path` joins with exactly one `/` and drops any
   trailing slash so the composed `pattern` string is **canonical** (two spellings of one path produce one
   pattern string → first-seen grouping and 405 stay correct).
3. After composition, the **unchanged** P4 pipeline runs: `pattern_to_regex`, first-seen pattern grouping,
   method chains, `Respond 404/405`, static `call_contract` arms, positional `capture(...)`.

```text
scope "/accounts/:account_id" { route GET "/todos/:todo_id" -> AccountTodoShow }
        │  compose_path("/accounts/:account_id", "/todos/:todo_id")
        ▼  route GET "/accounts/:account_id/todos/:todo_id" -> AccountTodoShow   (flat — scope gone)
        │  existing P4 lowering, unchanged
        ▼  if matches(req.path, "^/accounts/([^/]+)/todos/([^/]+)$") { if req.method == "GET" {
             call_contract("AccountTodoShow", req,
               capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 1),
               capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 2))
           } else { Respond 405 } } else { … Respond 404 }
```

`compose_path` edge cases: `("/todos", "/")` → `/todos`; `("/", "/x")` → `/x`; top-level (empty prefix)
leaves the route pattern untouched, so plain routes are byte-for-byte identical to before this card.

## Duplicate param policy

After composition, if any `:name` repeats in the composed pattern, lowering fails with
`duplicate path param ` `:<name>` ` in composed pattern `<path>``, carrying the offending route's line.
Rationale (P15): params bind positionally, so a repeated name is silent ambiguity for the reader — fail
closed. This also retroactively refuses a flat `/a/:id/b/:id` (previously lowered silently).

## Tests and commands — exact pass counts

```text
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 16 passed; 0 failed  (4 prior + 12 new)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests →  3 passed; 0 failed  (2 prior + 1 new)
$ cd server/igniter-web    && cargo test                             → 29 passed; 0 failed  (5 builder + 7 example + 17 runner)
$ cd server/igniter-server && cargo test --features machine          → all green; 0 failed
$ cd server/igniter-server && cargo tree -e normal | grep -iE 'igniter-web|igniter-compiler|regex|tokio' → (none) serde-only
$ git diff --check                                                   → clean (only igweb.rs + its tests changed)
```

New lib tests (12) — mapped to the card's required behaviors:

- **1 byte-identical** `scope_prefix_is_byte_identical_to_flat` — scoped route ≡ flat route's `.ig`.
- **2 positional merge** `scope_positional_param_merge` — composed regex + `capture(...,1/2)` in path order.
- **3 nested scope** `nested_scope_composes_prefixes` — `^/a/([^/]+)/b/([^/]+)/c$`.
- **4 duplicate refusal** `scope_duplicate_param_is_refused` (line 4) + `flat_duplicate_param_is_refused`
  (line 3, the retroactive flat case).
- **5 source order** `scope_preserves_source_order` — plain/scope/plain arms keep authored order.
- **6 404/405** `scope_preserves_404_405` — scoped GET-only path keeps method-mismatch 405 + trailing 404.
- **7 idempotency** `scope_preserves_idempotency_guard` — scoped POST keeps the keyless `status: 400` guard.
- **10 determinism** `scope_lowering_is_deterministic` — byte-identical across two lowerings.
- robustness: `malformed_scope_line_is_line_positioned`, `unclosed_scope_is_reported`.

New integration test (1) — covers card tests **1 + 8** together:

- `scoped_todo_is_byte_identical_to_flat_and_compiles` — the 5-route Todo authored with a
  `scope "/todos" { … }` block lowers **byte-identically** to the flat `TODO_IGWEB`, **and** the generated
  project compiles clean through the **real** multifile compiler (no `OOF-RE1`, no `OOF-TY0`).

Card tests **9 (no server change)** verified by the `igniter-web`/`igniter-server` green runs + the
serde-only `cargo tree` (both untouched on disk; useful boundary regressions).

## Closed surfaces (still closed after this card)

`resource`, the `nested` keyword, `via`, `.igweb`→`.ig` source maps, package manager, runner/CLI changes,
`igniter-server` changes, live effects / public bind / credentials / `[effects]`, canon claim, and any
controller convention or contract-name generation. Only `igweb.rs` + its tests changed.

## Honest limitations (carried + new)

- Literal segments are still assumed regex-safe (the P4 limitation); `scope` concatenates **more** literal
  segments, so a regex metacharacter in a scope prefix is an unescaped sharp edge. Acceptable for lab v0;
  a production lowering must escape literals (flagged in P15 §8).
- Unclosed-scope diagnostics use `line: 0` (no per-line tracking of the opening brace), consistent with the
  existing unclosed-`app` error. Malformed scope **lines** are line-positioned.
- Scope adds authoring distance between `.igweb` and generated `.ig`; the deferred source map
  (`LAB-IGNITER-WEB-SOURCE-MAP-READINESS-P15`) gains value but is not required here (scope distance is one
  prefix).

## Next recommendation

`LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P17` — `resource <name> "<base>" { <action> METHOD ["suffix"] -> Contract [requires idempotency] }`
as per P15 §4.2: a **closed action table used as a validator (not a generator)**, explicit contract names
(no auto-naming), `member`/`collection` escapes, same-path actions grouped into one pattern (correct 405),
per-action idempotency, composing with this card's `scope`. Then `…-NESTED-P18` proves `scope`-wraps-
`resource` (no new keyword), and the separate `…-VIA-READINESS-P19` track designs the guard pipeline.

---

*Lab implementation. Compiled 2026-06-19; igniter-compiler 16 lib + 3 integration green; scoped Todo lowers
byte-identically to flat and compiles clean through the real multifile compiler; igniter-web 29 green;
igniter-server green + serde-only. No server/runner/canon change.*
