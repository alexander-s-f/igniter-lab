# LAB-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P4 - Remove IgWeb route-depth wall

Status: CLOSED
Lane: parallel / IgWeb / lowering / scalability
Type: implementation-proof
Delegation code: OPUS-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P4
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-WEB-ROUTE-SCALING-BENCH-P2` proved a structural wall: current IgWeb lowering emits an
O(N)-deep nested route chain and fails around ~116 routes (`115 ok / 118 fail`). `LAB-LANG-REGEXP-RUNTIME-
CACHE-P4` reduced dispatch cost but does not touch the compile/load depth wall.

`LAB-IGNITER-WEB-ORDER-PRESERVING-ROUTE-INDEX-READINESS-P3` added real SparkCRM pressure:

- SparkCRM has 413 Rails routing DSL lines.
- 109 `resources` + 67 `resource` + 56 nested blocks imply roughly 700-1300+ concrete routes.
- That is 6-10x beyond the current IgWeb wall.

This is no longer a micro-optimization. It is a buildability blocker.

## Goal

Change `lang/igniter-compiler/src/igweb.rs` so IgWeb emits a segment-prefix-grouped route tree instead of
a linear nested-if chain, while preserving the observable behavior of current IgWeb routes.

The generated `.ig` remains the semantic truth. `igniter-server` must remain route-free.

## Verify First

Read live surfaces:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `server/igniter-web/examples/route_scaling_bench.rs`
- `lab-docs/lang/lab-igniter-web-route-scaling-bench-p2-v0.md`
- `lab-docs/lang/lab-igniter-web-order-preserving-route-index-readiness-p3-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`

Confirm or correct:

- the current route priority rule is authored-order, including static-vs-param shadowing;
- same-path method grouping still returns 405 for known path / wrong method;
- captures are positional and names are author-facing only;
- generated `.ig` uses only static `call_contract("Literal", ...)`;
- current scaling wall is still reproducible before the change.

Live code wins over this card.

## Design Constraints

Non-negotiable:

- No dynamic `call_contract`.
- No server-core route table.
- No new `.ig` semantic node.
- No `most-specific-wins` reordering.
- Preserve 404/405 behavior.
- Preserve capture values and order.
- Preserve authored-order priority as the final tiebreaker.
- Generated `.ig` remains inspectable and compilable.

Preferred shape:

```text
route specs
  -> segment prefix grouping
  -> shallow generated `.ig`
  -> leaves call existing handler arms
```

Grouping may narrow candidates by path segment, but when multiple routes remain possible, source order must
decide exactly as before.

## Required Implementation Questions

1. What internal route representation is needed before emission?
2. How are static segments, param segments, root routes, and trailing slashes represented?
3. How does the emitter preserve authored-order when static and param branches overlap?
4. How does same-path method grouping stay equivalent?
5. How are captures accumulated and passed positionally to handler arms?
6. How does mismatch fall through to 404 vs known-path wrong-method 405?
7. What generated `.ig` shape stays readable enough for lab evidence?
8. What scale should the proof compile: 500, 1000, or both?
9. What cases remain unsupported in v0 (constraints, globs, mounts)?
10. Does route-scaling bench show the wall is removed?

## Required Acceptance

- [x] `igweb_lowering_tests` all pass (11).
- [x] Existing scope/resource/nested/via/context tests still pass (lib 57).
- [x] Equivalence: static-vs-param authored-order shadowing (`route_tree_preserves_authored_order_shadowing`).
- [x] Equivalence: same-path 405 (method-chain unchanged; `status: 405` present).
- [x] Equivalence: capture order for nested resource paths (unchanged `capture(...)` assertions).
- [x] Generated code uses static `call_contract` literals only.
- [x] 500-route synthetic app compiles and loads (bench `compile_load_routes_500` ok, 1.48 s).
- [x] 1000-route synthetic app compiles and loads (bench `compile_load_routes_1000` ok, 2.96 s; depth ~11 levels).
- [x] `route_scaling_bench` rerun reports the wall removed (500/1000 ok; was ~116).
- [x] `igniter-web cargo test` passes (todo_view_app 14, …).
- [x] `igniter-web cargo test --features machine` passes.
- [x] `git diff --check` clean (one file: `igweb.rs`).

---

## Closing Report (2026-06-21)

**Change (only `lang/igniter-compiler/src/igweb.rs`, +120/−22):** `route_chain` (route-linear nested-if,
depth = N) → a **balanced binary tree over the distinct-pattern leaves** (depth `O(log N)`). Leaf =
`if matches(req.path, "^/exact$") { method-chain } else { Respond 404 }` (exact re-test = source of truth);
internal node = `if matches(req.path, "^(<left-half alternation>)$") { left } else { right }`, **left = the
authored-EARLIER half**, combined union **exact** → "left matches" ⟺ "first authored match is in left" →
**first-authored-wins / P18 shadowing preserved**, no most-specific-wins. Proof doc:
`lab-docs/lang/lab-igniter-web-prefix-grouped-lowering-p4-v0.md`.

**Wall removed:** in-process `route_tree_depth_is_bounded_for_1000_routes` — 1000 routes lower to a tree
**~11 levels** deep (vs ~2000 for the old chain), far under the serde recursion limit. End-to-end
`route_scaling_bench -- 500 1000` → **both compile + LOAD (`all_ok:true`)**; impossible before (~116 wall).

**Behavior-identical:** igweb lib **57** (55 + 2 new: depth bound + shadowing equivalence) + integration
**11** green; igniter-web all suites + `--features machine` green; byte-identity scope/resource/nested,
404/405, captures, via all preserved. Generated `.ig` stays the inspectable truth; server route-free; no new
`.ig` node; static `call_contract` only.

**Bonus signal (bench):** the P1 route-position skew **flattens** (first ≈ last ≈ miss — O(log N) descent).
A **residual O(N) per-dispatch base cost** remains (500 → ~53 ms, 1000 → ~109 ms) but it is the
**per-dispatch VM rebuild over the N-contract program** (the *other* P2 finding), orthogonal to this lowering
→ next: `LAB-LANG-RUNTIME-HOTPATH-READINESS-P3` (reuse VM/dispatch-table across requests).

**Unsupported in v0 (unchanged):** Rails constraints/globs/mount. **Next:** the per-dispatch-VM hotpath.

## Required Verification

Run and report:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example route_scaling_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
git diff --check
```

If a broad test has a pre-existing unrelated failure, isolate it with a before/after or targeted proof.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-prefix-grouped-lowering-p4-v0.md
```

Include:

- before/after generated-shape explanation;
- how authored-order is preserved;
- how 404/405 parity is preserved;
- capture parity proof;
- exact synthetic route count that compiles/loads;
- route-scaling bench sample;
- any unsupported route forms.

Update this card with a closing report.

## Closed Scope

- No server-core router.
- No new `.igweb` syntax.
- No Rails constraints/globs/mount support.
- No public performance claim.
- No canon claim.
