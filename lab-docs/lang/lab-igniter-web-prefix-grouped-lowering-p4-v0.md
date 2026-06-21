# lab-igniter-web-prefix-grouped-lowering-p4-v0 — remove the IgWeb route-depth wall

**Card:** `LAB-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P4` · **Delegation:** `OPUS-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P4`
**Status:** CLOSED (lab implementation-proof) — IgWeb route lowering now emits a **balanced binary tree
over the distinct-pattern leaves** (depth `O(log N)`) instead of a route-linear nested-if chain (depth
`O(N)`). This removes the ~116-route compile/LOAD wall (P2/P3) while keeping behavior identical. **Only
`lang/igniter-compiler/src/igweb.rs` changed; no `.igweb` syntax, no new `.ig` node, no server route table,
no dynamic dispatch.**
**Authority:** Lab lowering. Generated `.ig` stays the inspectable semantic truth; `igniter-server` stays
route-free.

## Before / after generated shape

**Before (route-linear chain, depth = N distinct patterns):**
```ig
if matches(req.path, "^/a$") { <methods> } else {
  if matches(req.path, "^/b$") { <methods> } else {
    … N levels … else { Respond 404 } } }
```
N nested `if/else` ⇒ the SemanticIR is N deep ⇒ machine LOAD's serde recursion limit (~128) is exceeded at
**~116 routes** (`Load(SerializationError("recursion limit exceeded"))`, P2: 115 ok / 118 fail).

**After (balanced tree, depth = `O(log N)`):**
```ig
if matches(req.path, "^(<left-half patterns alternation>)$") {
  <left subtree>          -- authored-EARLIER half
} else {
  <right subtree>         -- authored-later half
}
-- leaf (one pattern):
if matches(req.path, "^/a$") { <method-chain> } else { Respond 404 }
```
The tree splits the distinct patterns (first-seen/authored order) in half recursively. Internal nodes test
an **exact alternation** of the left half's patterns (`^(p0|p1|…)$`, anchors stripped + OR'd) purely as a
**boolean prune**; leaves re-test their own single pattern and run the existing method-chain. Nesting depth
is `ceil(log2 N) + 1` — for **1000 routes ≈ 11 levels**, far under the serde limit. The big alternation
strings are flat leaf values, not nesting.

## How authored-order priority is preserved (the hard invariant)

A naive radix trie does **most-specific-wins** — wrong for IgWeb (P18 accepts static-vs-param shadowing by
**authored order**). Here the tree's **left half is always the authored-earlier patterns**, and the internal
test is the **exact union** of the left half: so "left-combined matches" ⟺ "some authored-earlier pattern
matches" ⟺ "the first authored match is in the left subtree". Descending left whenever the left-combined
matches therefore reproduces **first-authored-match-wins**, exactly as the linear chain. Proven by
`route_tree_preserves_authored_order_shadowing`: `/r/overdue` (static) before `/r/:id` (param) → static
wins; reversed → param wins — identical to the old chain. **No reordering, no most-specific-wins.**

## 404 / 405 parity

- **405** (known path, wrong method): same-path routes still group into one leaf (`route_entries` groups by
  distinct pattern, first-seen) with the unchanged `method_chain` ending in `Respond 405`.
- **404** (no pattern matches): a non-matching path fails every internal prune, descends to a leaf, and the
  leaf's exact re-test fails → its `else Respond 404`. The leaf re-test is the **source of truth**, so
  correctness never depends on the prune regexes.

## Capture parity

Leaves are the existing `method_chain` → `handler_arm`, emitting the same `capture(req.path, "<regex>", i)`
positional captures (`Option[String]`, path order). The prune regexes are used only for `is_match` (boolean)
— captures are never taken from them. Proven by the unchanged capture assertions
(`call_contract("Handler", req, capture(...))`) across the existing scope/resource/nested/via tests.

## Scale proof — the wall is removed

- **In-process (fast, permanent regression):** `route_tree_depth_is_bounded_for_1000_routes` lowers **1000**
  synthetic `/r{i}/:id` routes and asserts the generated `.ig` max indent is `< 120` spaces (`O(log N)`,
  ~20–40 vs ~2000 for the old chain). Since machine LOAD's serde recursion follows the IR nesting depth, a
  bounded depth means LOAD can no longer overflow.
- **End-to-end (real build + machine LOAD + dispatch via `route_scaling_bench -- 500 1000`, `all_ok:true`):**

| N | compile_load (build+LOAD) | dispatch first | last | miss |
|---|---|---|---|---|
| **500** | 1.48 s ✓ | 55,414 | 53,404 | 53,216 |
| **1000** | 2.96 s ✓ | 108,867 | 108,969 | 109,935 |

  Both **compile + LOAD succeed** — impossible before (the old chain failed at ~116). Two signals:
  1. **The route-position skew is GONE.** `first ≈ last ≈ miss` at each N (e.g. 500: 55/53/53 ms) — the
     balanced tree descends `O(log N)` regardless of which route is hit, so the P1 "later routes slower"
     curve **flattens** (the old chain had `last ≫ first`).
  2. **A residual `O(N)` base cost remains** (500 → ~53 ms, 1000 → ~109 ms, ~linear in N) — but it is **not**
     the route walk: it is the **per-dispatch VM rebuild + dispatch-table build over the N-contract program**
     (`IgniterMachine::dispatch` builds a fresh VM each request — the *other* P2 finding). That is a
     separate hotpath card, orthogonal to this lowering. (compile_load is also super-linear — the
     typechecker over N contracts — again orthogonal to the depth wall, which is removed.)

## Equivalence — existing tests (behavior unchanged)

`cargo test --lib igweb::tests` → **57 passed** (55 prior + 2 new), `cargo test --test igweb_lowering_tests`
→ **11 passed**. Covered: byte-identity of scope/resource/nested lowering (both sides transform identically),
authored-order/source-order, same-path 405, multi-param capture order, via guard, idempotency 400 — all
green. The two new tests add the depth bound and the shadowing equivalence.

## Unsupported in v0 (unchanged, honest)

Rails `constraints` (regex/format), glob/catch-all `*path`, Rack `mount` — IgWeb expresses the route
**structure** (scope/resource/nested/member/collection), not these features. The tree change is orthogonal
to this scope.

## Commands & counts

```text
$ cd lang/igniter-compiler && cargo test --lib igweb::tests        → 57 passed (incl. depth + shadowing)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 11 passed
$ cd server/igniter-web   && cargo test                            → all suites green (todo_view_app 14, …)
$ cd server/igniter-web   && cargo test --features machine          → green (e2e 2)
$ cd server/igniter-web   && cargo run --example route_scaling_bench -- 500 1000 → 500 + 1000 compile+load OK
$ git diff --check                                                  → clean
```

## Acceptance — mapping

- [x] `igweb_lowering_tests` all pass (11); existing scope/resource/nested/via/context tests pass (lib 57).
- [x] Equivalence: static-vs-param authored-order shadowing (`route_tree_preserves_authored_order_shadowing`).
- [x] Equivalence: same-path 405 (method-chain unchanged; `status: 405` present).
- [x] Equivalence: capture order for nested resource paths (unchanged `capture(...)` assertions).
- [x] Generated code uses static `call_contract` literals only (no dynamic dispatch).
- [x] 500-route synthetic app compiles and loads.
- [x] 1000-route synthetic app compiles and loads (depth ~11 levels, far under the serde limit).
- [x] `route_scaling_bench` reruns and reports the wall removed.
- [x] `igniter-web cargo test` (+`--features machine`) pass.
- [x] `git diff --check` clean (one file: `igweb.rs`).

## Closed scope (honored)

No server-core router; no new `.igweb` syntax; no Rails constraints/globs/mount; no public performance
claim; no canon claim. One file changed.

---

*Lab implementation-proof. Compiled 2026-06-21; balanced route tree (depth O(log N)) replaces the linear
chain, removing the ~116-route compile/LOAD wall; behavior-identical (authored-order shadowing, 404/405,
captures, static calls preserved); igweb lib 57 + integration 11 green; 1000 routes lower to ~11 levels;
500/1000-route apps compile + load. Only `igweb.rs` changed.*
