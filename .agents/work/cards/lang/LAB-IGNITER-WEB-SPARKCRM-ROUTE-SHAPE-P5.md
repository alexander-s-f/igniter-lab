# LAB-IGNITER-WEB-SPARKCRM-ROUTE-SHAPE-P5 - Product route-shape pressure without live SparkCRM

Status: CLOSED
Lane: parallel / IgWeb / product-pressure / readiness
Type: readiness
Delegation code: OPUS-IGNITER-WEB-SPARKCRM-ROUTE-SHAPE-P5
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

SparkCRM's Rails routes gave decisive pressure for `LAB-IGNITER-WEB-ORDER-PRESERVING-ROUTE-INDEX-READINESS-
P3`: hundreds of route declarations expand to roughly 700-1300+ concrete routes, far beyond the current IgWeb
compile wall.

Before turning SparkCRM into an Igniter app, we need a sober route-shape packet:

- What route forms map cleanly to IgWeb today?
- What route forms require future syntax?
- What route forms should stay outside IgWeb?
- What synthetic fixture should be used to prove scale after P4?

This card is not a SparkCRM migration. It is product-pressure characterization.

## Goal

Read SparkCRM route files and produce a route-shape readiness packet that classifies real production route
features against current IgWeb:

- supported now (`scope`, `resource`, nested resources, member/collection-like suffixes);
- supported after prefix-grouped lowering only due to scale;
- unsupported v0 (`constraints`, glob, Rack mount, custom Rails helpers if any);
- dangerous to imitate blindly.

## Verify First

Read:

- `/Users/alex/dev/projects/sparkcrm/config/routes.rb`
- `/Users/alex/dev/projects/sparkcrm/config/routes/*`
- `lab-docs/lang/lab-igniter-web-order-preserving-route-index-readiness-p3-v0.md`
- `lang/igniter-compiler/src/igweb.rs`
- `lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-resource-sugar-p17-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`

Live SparkCRM files win over prior counts.

## Required Questions

1. How many route declarations exist by source file?
2. How many `resources`, `resource`, `namespace`, `scope`, member, collection, custom verbs?
3. How many nested blocks and what is the maximum nesting depth?
4. What conservative concrete route count does Rails likely expand to?
5. Which forms map to current IgWeb syntax?
6. Which forms need only P4 prefix-grouped lowering?
7. Which forms need new IgWeb syntax or should be rejected?
8. Which forms belong to server/middleware/static assets instead of IgWeb routes?
9. What minimal synthetic SparkCRM-shaped fixture should P4/P6 use?
10. Is there any pressure for changing authored-order priority?

## Required Acceptance

- [x] Provides current counts from live SparkCRM route files (per-file + totals).
- [x] Separates supported shape from unsupported Rails-only features (Q5–Q8 table).
- [x] Does not read SparkCRM secrets, DB, or production data (static `grep`/`wc` only).
- [x] Does not execute SparkCRM.
- [x] Proposes one synthetic IgWeb route fixture shape (Q9).
- [x] Names exact blockers after P4 (constraints / format / mount / Devise — all minority, re-homed).
- [x] No code changes (doc artifact only).
- [x] No migration claim.
- [x] No live SparkCRM claim.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-web-sparkcrm-route-shape-p5-v0.md` — product-pressure
characterization, **no code** (`git diff` clean; static `grep`/`wc` only, no SparkCRM execution/secrets/DB).
Answers Q1–Q10.

**Headline finding:** SparkCRM's route **shape is ~95% already expressible in current IgWeb syntax**
(`scope`/`resource`/nested/`member`/`collection`/path-base). The blocker is **not missing syntax — it is the
compile wall** (P2/P3 ~116 routes) that the neighbour's **P4 prefix-grouped lowering removes**.

**Live counts:** 413 DSL decls across 11 files (admin.rb 189 biggest); **109 `resources` + 67 `resource`**;
member 28 / collection 22; namespace 15 / scope 16. **Max nesting depth = 4** — confirms P3's "tree depth ≈
path segments ≈ 5–10" bound. Conservative expansion **~700–1300+ concrete routes** (6–11× past the wall).

**Classification:** *Supported now* (blocked only by scale): resources/resource (with `only:` free via
explicit action lines), nested scope+resource, member/collection, namespace/scope/`path:`, explicit verbs.
*N/A:* `module:` (IgWeb names contracts explicitly). *Unsupported v0 / re-homed:* `constraints` (1),
`format:`/`defaults:` (content-negotiation), `mount` (5 → external Rack apps), `authenticated`/`devise_for`
(auth → middleware/`via`, not routing) — a small minority, each with a clear non-route home.

**Q10:** **zero pressure** to change authored-order priority — Rails is **also** first-match-in-file-order,
so SparkCRM *confirms* IgWeb P18 and is evidence *against* most-specific-wins.

**Q9 fixture for P4/P6:** nested `scope "/admin" { scope "/global" { resource … member/collection } }` to 500
/1000 routes — adds **shared-prefix nesting + custom verbs** (the current flat `/r{i}/:id` bench under-states
prefix-grouping). **Next:** feed this fixture to P4's lowering proof.

## Required Verification

Doc-only:

```bash
git diff --check
```

Optional helper commands are allowed, but do not execute the SparkCRM app or require Ruby gems.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-sparkcrm-route-shape-p5-v0.md
```

Update this card with a closing report.

## Closed Scope

- No SparkCRM app migration.
- No Rails route parser implementation.
- No live SparkCRM execution.
- No route semantics claim beyond static file characterization.
- No canon claim.
