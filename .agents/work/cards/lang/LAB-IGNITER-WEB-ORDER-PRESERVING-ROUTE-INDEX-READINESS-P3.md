# LAB-IGNITER-WEB-ORDER-PRESERVING-ROUTE-INDEX-READINESS-P3 - Boundary-safe route index design

Status: CLOSED
Lane: parallel / IgWeb / performance / architecture
Type: readiness
Delegation code: OPUS-IGNITER-WEB-ORDER-PRESERVING-ROUTE-INDEX-READINESS-P3
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

IgWeb currently lowers routes into explicit `.ig`:

```text
if matches(req.path, "^...$") { method-chain } else { next }
```

This is valuable because the generated `.ig` `Serve` contract is the inspectable semantic truth, and
`igniter-server` remains route-free.

Bench pressure raised the idea of a faster route structure. Correct terminology is not a suffix tree; route
matching usually wants a segment/radix prefix index. But IgWeb has a crucial semantic invariant:

```text
authored route order = priority
```

P18 explicitly accepted static-vs-param shadowing by order. Any route index that silently changes to
"most-specific wins" is wrong.

This card is design/readiness only. It should run after, or at least read, regexp-cache P4 and route-scaling
bench P2.

## Goal

Design a boundary-safe route-index optimization, if evidence justifies it, without moving routing authority
into `igniter-server`.

Questions:

1. Can an order-preserving radix/segment index be behavior-identical to the current `.ig` chain?
2. Where can such an index live without breaking Projection Dialect governance?
3. What proof is required before implementation?
4. When should we reject the index because regexp-cache is enough?

## Verify First

Read live code and docs:

- `lang/igniter-compiler/src/igweb.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/examples/app_pressure_bench.rs`
- any route scaling bench from `LAB-IGNITER-WEB-ROUTE-SCALING-BENCH-P2`
- any regex cache result from `LAB-LANG-REGEXP-RUNTIME-CACHE-P4`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md`
- `lab-docs/lang/lab-igniter-web-route-scaling-bench-p2-v0.md` if present

Confirm or correct:

- exact current priority semantics;
- exact generated `.ig` shape for same-path method grouping;
- whether route metadata survives lowering or would need to be re-derived from generated `.ig`;
- whether `igniter-web` builder can retain route metadata as an optimization sidecar;
- whether the VM can optimize a `matches` chain without IgWeb-specific knowledge.

Live code wins over this card.

## Design Constraints

Non-negotiable:

- `igniter-server` must remain route-free.
- Generated `.ig` remains semantic truth.
- Authored order priority must be preserved.
- Method 405 vs 404 behavior must be identical.
- Path param capture order and values must be identical.
- No hidden dynamic dispatch beyond generated static `call_contract` targets.
- Optimization must be optional / derived / inspectable enough for lab status.

Possible homes to evaluate:

| Home | Notes |
|---|---|
| VM regexp/matches-chain optimizer | Most boundary-pure, hardest to recognize route shape generically. |
| `igniter-web` builder sidecar index | Knows `.igweb` route metadata; must prove generated `.ig` remains truth and sidecar is behavior-identical. |
| generated `.ig` special form | Probably too early; risks new semantic node. |
| `igniter-server` router | Reject unless governance changes; violates route-free server. |

## Required Questions To Answer

1. Is route-index still needed after regexp-cache P4?
2. Is route-index justified by route-scaling P2 at 100/500 routes?
3. What exact route semantics must be preserved?
4. How to represent author-order priority in a trie/radix index?
5. How to preserve same-path method grouping and 405 behavior?
6. How to preserve capture values and positional ordering?
7. Where should the optimization live?
8. What artifact is inspectable: source `.igweb`, generated `.ig`, route-index dump?
9. What invalidates/rebuilds the index on reload?
10. What tests prove equivalence against the current `.ig` chain?
11. What cases must be explicitly unsupported in v0?
12. Should implementation proceed, or should we stop at regex-cache?

## Required Acceptance

- [x] Uses live P4/P2 evidence (+ real SparkCRM production scale).
- [x] Corrects suffix-tree terminology to segment/radix prefix index (prefix-grouped tree).
- [x] Keeps `igniter-server` route-free (home is the lowering, not the server).
- [x] Preserves authored order priority as a hard invariant (Q3/Q4).
- [x] Explains static-vs-param shadowing and why most-specific-wins is wrong for IgWeb.
- [x] Covers 404/405 equivalence.
- [x] Covers path capture equivalence.
- [x] Compares ≥3 homes (VM optimizer / builder sidecar / prefix-grouped lowering / server router).
- [x] Implementation gate: **PROCEED** (driven by the compile wall).
- [x] Lists an equivalence-test matrix for a future implementation.
- [x] No code changes.
- [x] No canon claim.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-web-order-preserving-route-index-readiness-p3-v0.md` — readiness
packet, **no code** (`git diff` clean). Answers Q1–Q12, grounded in P2/P4 + **real SparkCRM production
routes** (per the user's pressure pointer).

**Decisive evidence:** P4 fixed dispatch regex *recompile* but NOT the compile **wall**; P2 proved IgWeb
can't build > ~115 routes (O(N)-deep nested-if IR → serde recursion limit at ~116; probed 115 ok / 118 fail).
**SparkCRM** (`config/routes*`): 413 DSL lines, 109 `resources` + 67 `resource` + 56 nested blocks ⇒
**~700–1300+ actual routes, 6–10× past the wall** — a real CRM is **structurally unbuildable in IgWeb today.**

**Gate: PROCEED** — justified by **buildability**, not latency. Recommended home = **option C: a
prefix-grouped `.ig` lowering** in `igweb.rs` (emit a segment-prefix tree, depth = path-segment count ≈ 5–10,
not route count) — removes the depth wall **and** the O(N) dispatch scan, using only existing `.ig`
(if/match/matches/capture/static `call_contract`): **no new `.ig` node, no dynamic dispatch, server stays
route-free, `.ig` stays the truth.** Rejected: VM optimizer (doesn't fix the wall), data-driven flat dispatch
(needs forbidden dynamic dispatch), server router (route-free boundary).

**Hard invariants preserved:** authored-order priority as a **tiebreaker** (index narrows candidates in
O(path); first-source-order wins — most-specific-wins explicitly rejected as P18-breaking), 404/405 parity,
positional capture parity, static-call-only. v0-unsupported (named): Rails `constraints` (6), glob `*path`
(1), Rack `mount`.

**Next card:** `LAB-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P*` — implement the prefix-grouped emission + the
§Q10 equivalence matrix + a 500/1000-route compile proof.

## Required Verification

Doc-only:

```bash
git diff --check
```

Optional but preferred if P2/P4 exist:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example route_scaling_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example app_pressure_bench
```

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-order-preserving-route-index-readiness-p3-v0.md
```

Update this card with a closing report.

## Closed Scope

- No route-index implementation.
- No route reordering.
- No server-core router.
- No new `.igweb` syntax.
- No new `.ig` semantic node.
- No public performance claim.
- No canon claim.
