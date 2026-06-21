# lab-igniter-web-order-preserving-route-index-readiness-p3-v0 — boundary-safe route index design

**Card:** `LAB-IGNITER-WEB-ORDER-PRESERVING-ROUTE-INDEX-READINESS-P3` · **Delegation:** `OPUS-IGNITER-WEB-ORDER-PRESERVING-ROUTE-INDEX-READINESS-P3`
**Status:** READINESS / ARCHITECTURE (v0) — designs a boundary-safe, order-preserving route index. **No
code, no `.igweb`/`.ig` change, no server router, no public perf claim, no canon claim.**
**Authority:** Lab readiness, grounded in P2 (route-scaling bench), P4 (regexp cache), P16–P18 (scope/
resource/nested), P0 (Projection Dialects), and **real production pressure: SparkCRM's routes**.
**Gate: PROCEED** — but driven by the compile **wall**, not dispatch latency (§Q12).

## Terminology correction

Not a **suffix tree** (that is substring search within one string). Route matching wants a **segment/radix
prefix index** — a tree keyed by path *segments*, with `:param` segments as wildcard edges. Below, the
concrete recommendation is a **prefix-grouped route tree** emitted as ordinary `.ig`.

## Verify-first evidence (P2/P4 live + real production scale)

- **P4 (regexp cache, landed):** removed per-call `Regex::new` recompilation in the VM — dispatch win
  (late route −48%). It does **not** touch the compile/LOAD wall (the wall is IR *depth*, not regex).
- **P2 (route-scaling bench):** IgWeb lowers N routes to an **O(N)-deep nested `if matches(...) { … } else { … }`**
  tree. The machine LOAD deserializes that SemanticIR with serde, whose recursion limit (~128) is exceeded
  at **~116 routes** → `Load(SerializationError("recursion limit exceeded"))` (probed: 115 ok / 118 fail);
  far beyond, the typechecker stack-overflows. **An app with > ~115 routes cannot be built today.**
- **Real production pressure — SparkCRM** (`config/routes.rb` + `config/routes/*.rb`): **413 routing DSL
  lines**, incl. **109 `resources` + 67 `resource`** (Rails expands each to ~6–7 HTTP routes), 65 `post`,
  62 `get`, 28 `member`, 22 `collection`, 16 `scope`, 15 `namespace`, **56 nested resource blocks**.
  Conservative expansion ⇒ **~700–1300+ actual routes** — **6–10× past the ~116 wall.** A real CRM's route
  surface is **structurally unbuildable** in IgWeb today. (Also present, and v0-unsupported: 6 `constraints`,
  1 glob `*path`, `mount` of Rack engines — §Q11.)
- **Current priority semantics (live `igweb.rs`):** routes flatten in **authored order**; `patterns_in_order`
  groups distinct patterns **first-seen**; same-path methods share one `matches` arm with a method sub-chain
  ending in `Respond 405`; the chain ends in `Respond 404`. **First matching arm in source order wins** —
  P18's static-vs-param shadowing.
- **Route metadata survives lowering** inside the builder (`igweb.rs` has the `Route` structs: method,
  composed pattern, regex, params, contract, requires_idem) — so a derived index needs **no re-parsing of
  the generated `.ig`**.

## Answers to the required questions

**Q1 — needed after P4?** **Yes.** P4 fixed dispatch *recompilation*; it cannot fix the **compile/LOAD
depth wall** (the nested-if IR is O(N) deep before the VM ever runs). Different problem, different layer.

**Q2 — justified by P2 at 100/500?** **More than justified — it's a hard blocker.** P2 proved you cannot
even *build* 100/500 routes (wall ~116). SparkCRM proves real apps need ~10× that. So the index is a
**prerequisite for real-app parity**, not a latency nicety.

**Q3 — exact semantics to preserve (hard invariants):**
1. **authored order = priority** (first source-order match wins; static-vs-param shadowing, P18);
2. **404 vs 405** (no pattern matched → 404; pattern matched, method didn't → 405) — from same-path grouping;
3. **path captures** positional `capture(req.path, regex, i)` → `Option[String]`, in path order (names
   author-facing only);
4. **static `call_contract("Literal", …)`** targets only — **no dynamic dispatch**.

**Q4 — author-order priority in a radix index (the crux).** A naive radix trie does **most-specific-wins**
(longest static prefix beats `:param`) — that **silently changes** which route wins and is **wrong** for
IgWeb. The fix: the index is an **accelerator, not a new policy**. Tag every route with its **authored-order
ordinal**; when a path could match several leaves (e.g. a static `/r/overdue` and a param `/r/:id`), return
the **minimum authored ordinal** among matches — i.e. the index narrows candidates in O(path), and
**authored order breaks ties**, reproducing the linear chain's "first source-order match" exactly. Static
and param edges coexist at each level; param is the wildcard edge, tried so authored order still decides.

**Q5 — same-path method grouping + 405.** Routes sharing a composed path collapse to one tree node carrying
a `{method → (target, requires_idem)}` map. Path reaches the node but the method is absent → **405**; path
reaches no node → **404**. Identical to today's pattern-group + method-chain.

**Q6 — capture equivalence.** Param (`:name`) edges capture the segment at that position; captures collect
in **path order** and pass positionally to the static handler call — byte-identical to the current
`capture(req.path, regex, i)` sequence.

**Q7 — where it lives (≥3 homes compared):**

| Home | Verdict |
|---|---|
| **(A) VM `matches`-chain optimizer** (recognize the if-chain in SIR, run a trie) | **Reject.** Most boundary-pure, but it would have to recognize an IgWeb-specific shape generically, AND it **does not fix the compile wall** — the O(N)-deep IR already fails serde LOAD before the VM runs. |
| **(B) `igniter-web` builder sidecar index** | **Partial.** The builder has the route metadata and could build a flat index, but if the generated `.ig` stays O(N)-deep nested it still hits the wall; a sidecar that *replaces* dispatch risks the `.ig` no longer being the truth. |
| **(C) lowering emits a prefix-grouped `.ig` tree** (`igweb.rs`) | **RECOMMEND.** Restructure the emission from a *route-linear* nested chain (depth = N) to a **segment-prefix-grouped** tree (depth = path-segment count ≈ 5–10, independent of N). Removes the depth wall (serde + stack) **and** gives O(segments) dispatch. Uses only existing `.ig` (`if`/`match`/`matches`/`capture`/`call_contract`) — **no new semantic node, no dynamic dispatch, `.ig` stays the inspectable truth.** |
| **(D) `igniter-server` router** | **Reject** — violates the route-free server boundary. |

**Why (C) and not a data-driven flat dispatch:** a fully data-driven table (`find(routes, …)` then
`call_contract(matched.target)`) would require **dynamic dispatch** on the matched target — forbidden
(`.ig` has none; targets are compile-time literals). Prefix-grouping keeps every leaf a **static** call, so
it stays within the invariant while bounding depth. The "route index" is therefore the **prefix-grouped
emission**, derived from the existing route metadata.

**Q8 — inspectable artifact.** Three layers, all app-owned: source `.igweb` (authored) → generated `.ig`
(now prefix-grouped, **still the semantic truth**) → optional route-index/trie dump for debugging. The
server sees none of them — it dispatches the compiled `Serve` capsule as today.

**Q9 — invalidation/rebuild.** The index is **derived at build time** from the `.igweb` (it *is* the
generated `.ig`). On hot-reload (`ReloadableApp`), it is regenerated with the app — there is no separate
mutable cache to invalidate.

**Q10 — equivalence-test matrix (for the implementation card):** prove the prefix-grouped lowering is
**behavior-identical** to the linear chain (not necessarily byte-identical `.ig`):
1. for a route corpus (static-only, param, **static+param overlap/shadowing**, same-path GET/POST, nested
   scope+resource, member/collection) and a path corpus (first/middle/last/**miss**), assert identical
   `(status, target, captures)`;
2. **404 vs 405** identical on method-mismatch and unmatched paths;
3. **capture values + order** identical on multi-param paths (e.g. `/accounts/:a/todos/:t`);
4. **authored-order tiebreak**: `collection "/overdue"` before/after `show "/:id"` resolves identically;
5. **the wall is gone**: synth apps at N = 200 / 500 / 1000 **compile + load** (P2's harness, now passing);
6. dispatch trend: O(segments) not O(N) (route-scaling bench flattens);
7. `igniter-server` dep tree unchanged; `git diff --check` clean.

**Q11 — explicitly unsupported in v0 (honest scope of the scale claim).** IgWeb can express SparkCRM's
**route structure** (nested scope/resource, member/collection, namespaces) but **not** every Rails feature:
**regex/format `constraints`** (SparkCRM: 6), **glob/catch-all `*path`** (1), **Rack `mount`** of engines
(Sidekiq/PgHero), and `path:`/`module:` remapping beyond what `scope`/`resource` already cover. v0 names
these unsupported so "IgWeb can handle a real CRM's routes" is not overstated — it can handle the *shape*,
once the wall is removed, minus these features.

**Q12 — proceed / defer / reject? → PROCEED.** The implementation is justified by **buildability**, not
performance: today IgWeb caps at ~115 routes and a real app needs ~10×. The smallest implementation is a
**prefix-grouped lowering in `igweb.rs`** (option C): behavior-identical, no new `.ig` node, no dynamic
dispatch, no server change — it removes the depth wall and the O(N) scan together. Regexp-cache (P4) is
**not enough** (it never touches the wall). Defer only the data-driven/trie-in-VM variants (A/B).

## Recommended next card (implementation)

`LAB-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P*` — change `igweb.rs` `route_chain` to emit a **segment-prefix-
grouped** `if`-tree (depth bounded by path-segment count, not route count) instead of the route-linear
chain, with the §Q10 equivalence matrix and the 500/1000-route compile proof. Hard invariants: authored-
order tiebreak, 404/405 parity, capture parity, static-`call_contract`-only, server route-free, `.ig` is
the truth. **No new `.igweb` syntax, no new `.ig` semantic node.**

## Acceptance — mapping

- [x] Uses live P4/P2 evidence (and real SparkCRM scale).
- [x] Corrects suffix-tree → segment/radix prefix index (prefix-grouped tree).
- [x] Keeps `igniter-server` route-free (home is the lowering, not the server).
- [x] Authored-order priority a hard invariant (Q3/Q4); most-specific-wins rejected with reason.
- [x] Static-vs-param shadowing explained (P18); 404/405 + capture equivalence covered (Q5/Q6/Q10).
- [x] ≥3 homes compared (VM optimizer / builder sidecar / prefix-grouped lowering / server router).
- [x] Implementation gate: **PROCEED** (driven by the compile wall).
- [x] Equivalence-test matrix listed (Q10).
- [x] v0-unsupported cases named (constraints/glob/mount — Q11).
- [x] No code changes; no canon claim.

## Verification

```text
$ git diff --check                                   → clean (doc-only)
$ cargo run --example route_scaling_bench            → 10/50/90 curve; wall at ~116 (P2, evidence cited)
$ cargo run --example app_pressure_bench             → all_ok (P1/P4, regexp cache present)
```

## Closed scope (honored)

No route-index implementation; no route reordering; no server-core router; no new `.igweb` syntax; no new
`.ig` semantic node; no public performance claim; no canon claim.

---

*Readiness/architecture only. Compiled 2026-06-21; grounded in live `igweb.rs`, P2 (compile wall ~116
routes), P4 (regexp cache), P16–P18 priority semantics, and SparkCRM production routes (~700–1300+ routes,
6–10× past the wall). The recommended fix is a prefix-grouped `.ig` lowering — behavior-identical, depth-
bounded, server route-free. No code change.*
