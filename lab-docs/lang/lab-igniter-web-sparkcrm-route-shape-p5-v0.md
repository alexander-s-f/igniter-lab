# lab-igniter-web-sparkcrm-route-shape-p5-v0 — product route-shape pressure (no live SparkCRM)

**Card:** `LAB-IGNITER-WEB-SPARKCRM-ROUTE-SHAPE-P5` · **Delegation:** `OPUS-IGNITER-WEB-SPARKCRM-ROUTE-SHAPE-P5`
**Status:** READINESS / PRODUCT-PRESSURE (v0) — classifies SparkCRM's **real route shape** against current
IgWeb. **Static file characterization only: no SparkCRM execution, no Ruby, no DB, no secrets/data, no
migration claim, no canon claim.**
**Authority:** Lab readiness, grounded in live `config/routes.rb` + `config/routes/*.rb` and IgWeb
`igweb.rs` / P16–P18 / P3.

## Headline

**SparkCRM's route *shape* is ~95% already expressible in current IgWeb syntax** (`scope`/`resource`/
nested/`member`/`collection`/path-base). The blocker is **not missing syntax — it is the compile wall**
(P2/P3: ~116 routes), which **P4 prefix-grouped lowering removes**. SparkCRM's max nesting depth is **4**,
confirming P3's "tree depth ≈ path segments ≈ 5–10" bound. Rails itself matches **first-in-file-order**, so
SparkCRM **confirms** IgWeb's authored-order priority (P18) — **zero pressure to change it.**

## Q1 — declarations by source file (live counts)

| File | lines | DSL decls |
|---|---:|---:|
| `routes/admin.rb` | 306 | **189** |
| `routes/operators.rb` | 75 | 49 |
| `routes/api.rb` | 72 | 48 |
| `routes/app.rb` | 57 | 40 |
| `routes/settings.rb` | 56 | 36 |
| `routes/webhooks.rb` | 47 | 20 |
| `routes.rb` | 50 | 12 |
| `routes/reports.rb` | 12 | 7 |
| `routes/services.rb` | 11 | 6 |
| `routes/static.rb` | 7 | 5 |
| `routes/development.rb` | 10 | 1 |
| **total** | — | **413** |

## Q2 — keyword breakdown (all files)

`resources` **109** · `resource` **67** · `post` 65 · `get` 62 · `member` 28 · `collection` 22 · `scope`
16 · `patch` 16 · `namespace` 15 · `root` 6 · `match` 4 · `delete` 3 · `mount` 5 · `constraints` 1.
Options: `only:` **110** · `module:` **41** · `path:` 15 · `authenticated` 6 · `defaults:` 5 · `format:` 5
· `via:` 4 · `devise_for` 3 · `except:` 2 · glob `*path` **0**.

## Q3 — nesting depth

**Max depth ≈ 4** (deepest `do`-block at 8-space indent in `admin.rb`), e.g.
`authenticated → namespace :admin → scope :global → resources :call_records → collection`. Real production
nesting is shallow (≤4–5), which is exactly the bound P3's prefix-grouped tree reduces `.ig` depth to —
**SparkCRM validates the P4 design assumption.**

## Q4 — conservative concrete route count

Rails expands `resources`→~7 (index/show/new/edit/create/update/destroy), `resource`→~6, plus explicit
verbs and member/collection extras:

```
109 resources × 7   ≈ 763
 67 resource  × 6   ≈ 402
 explicit verbs      ≈ 146   (post/get/patch/delete)
 member 28 + collection 22 ≈ 50
                     ─────────
 gross               ≈ 1361   (net ~700–1000 after `only:`/`except:` trims 110+ resources)
```

So **~700–1300+ concrete routes** — **6–11× past the ~116 wall**. Consistent with P3.

## Q5–Q7 — feature classification vs current IgWeb

| Rails form (count) | IgWeb today | Class |
|---|---|---|
| `resources` (109) / `resource` (67) | `resource <name> "<base>" { index/show/create/update/delete }` (P17) | **Supported now** |
| `only:` (110) / `except:` (2) | author exactly the actions you want (P17 has no auto-7; you list them) | **Supported now** (free) |
| nested `resources … do` (depth ≤4) | `scope` wraps `resource` (P18, no `nested` keyword) | **Supported now** |
| `member` (28) / `collection` (22) | `member`/`collection` action with explicit METHOD + suffix (P17) | **Supported now** |
| `namespace` (15) / `scope` (16) / `path:` (15) | path prefix via `scope "/p"` + resource `<base>` | **Supported now** (path part) |
| `via:` (4) / explicit verbs | `route <METHOD> "…" -> Contract` | **Supported now** |
| `module:` (41) | N/A — IgWeb names the **contract** explicitly (`-> Handler`); no module concept | **N/A (handled by explicit naming)** |
| **everything above at 700–1300 routes** | blocked **only** by the compile wall | **Supported after P4 (scale, not syntax)** |
| `constraints` (1) | regex/format segment constraint — no IgWeb equivalent | **Unsupported v0** (do in handler / future) |
| `format:` (5) / `defaults:` (5) | content-format negotiation — IgWeb has none (P11: server is JSON; format is a handler/content-type concern) | **Unsupported v0** (different model) |
| `mount` (5) — `Sidekiq::Web`, `PgHero::Engine` | mounting external **Rack apps** | **Not IgWeb routes** → §Q8 |
| `authenticated` (6) / `devise_for` (3) | Devise auth gating / generated auth routes | **Different model** → §Q8 |
| glob `*path` (0) | catch-all | **Unsupported v0** (absent here anyway) |

**Bottom line:** the routing *structure* — namespaces, scopes, nested resources, member/collection — is
**already expressible**; the only thing standing between SparkCRM-shaped routing and IgWeb is the **scale
wall P4 removes**. The genuinely-unsupported items (`constraints`, `format`/`defaults`, `mount`, Devise) are
a **small minority** and most belong outside the route table (§Q8).

## Q8 — what belongs to server / middleware / external, not IgWeb routes

- **`mount Sidekiq::Web` / `mount PgHero::Engine`** — external Rack/observability apps; serve them as
  **separate processes/services**, never inside the IgWeb `Serve` capsule. Not a route-table concern.
- **`authenticated do … end` / `devise_for`** — **auth is middleware or a `via` guard**, not a routing
  primitive. The auth envelope is `AuthTokenApp` (P8 middleware) or a route-level `via Guard` (P19/P20);
  the gate runs *before/around* the handler, not as a match arm. Generated Devise routes (sign_in/out) are
  ordinary app routes you'd author explicitly if needed.
- **`constraints` / `format:` / `defaults:`** — content-format/negotiation policy; lives in the **handler**
  (which decides the `Decision`/response) or a future explicit gate, not in route matching.
- **static assets** (CSS/JS/wasm) — external static server (P1/P11), not IgWeb routes.

## Q9 — proposed synthetic fixture for P4/P6 scale proof

The current `route_scaling_bench` uses **flat** `/r{i}/:id` routes — good for the depth wall, but it does
**not** exercise the *prefix-grouping* P4 optimizes (no shared prefixes). A SparkCRM-shaped fixture should
add **shared-prefix nesting + member/collection**, so the prefix-grouped tree's benefit is visible:

```igweb
app SparkShape entry Serve {
  handlers SparkHandlers
  scope "/admin" {
    scope "/global" {
      resource r0 "/r0" {
        index  GET            -> R0Index
        show   GET "/:id"     -> R0Show
        create POST           -> R0Create requires idempotency
        update PATCH "/:id"   -> R0Update requires idempotency
        delete DELETE "/:id"  -> R0Delete requires idempotency
        member PATCH "/:id/cancel" -> R0Cancel requires idempotency   -- member custom verb
        collection GET "/report"   -> R0Report                        -- collection custom verb
      }
      -- … rM repeated to reach N concrete routes
    }
  }
}
```

Properties: **depth-4 nesting** (matches SparkCRM), **shared `/admin/global/` prefix** (exercises
grouping), **member/collection custom verbs**, scaling to **500 and 1000** concrete routes. This proves both
(a) the wall is gone and (b) grouping actually shares prefixes — a flat fixture would under-state the win.
Generate it in a tempdir, no DB, like `route_scaling_bench`.

## Q10 — pressure to change authored-order priority?

**None — the opposite.** Rails route matching is **first-match-in-file-order** (the same model IgWeb P18
chose). SparkCRM depends on it (static/specific routes authored before broad resource params). So SparkCRM
**confirms** authored-order priority and is **evidence against** a most-specific-wins index. P4's
prefix-grouped lowering must keep authored order as the tiebreaker (P3 §Q4) — SparkCRM is the production
witness that this is correct.

## Exact blockers after P4

Once P4 removes the depth wall, the **only** remaining IgWeb gaps for SparkCRM-shaped routing are the
minority features in §Q5–Q7/Q8: `constraints`, `format:`/`defaults:`, `mount`, Devise auth-as-routing.
None block the **bulk** of the route table; each has a clear home (handler / middleware / external / future
gate). There is **no missing core routing syntax** — namespaces/scopes/nested-resources/member/collection
all exist.

## Acceptance — mapping

- [x] Current counts from live SparkCRM route files (Q1/Q2, per-file + totals).
- [x] Supported shape separated from unsupported Rails-only features (Q5–Q8 table).
- [x] No SparkCRM secrets/DB/data read; no execution (static `grep`/`wc` only).
- [x] One synthetic IgWeb route fixture proposed (Q9, nested-prefix + member/collection at 500/1000).
- [x] Exact blockers after P4 named (constraints / format / mount / Devise — all minority, all re-homed).
- [x] No code changes (doc only); no migration claim; no live SparkCRM claim.

## Verification

```text
$ git diff --check   → clean (doc-only; static grep/wc characterization, no app execution)
```

## Closed scope (honored)

No SparkCRM migration; no Rails route-parser implementation; no live SparkCRM execution; no route-semantics
claim beyond static file characterization; no canon claim.

---

*Readiness/product-pressure only. Compiled 2026-06-21; static characterization of SparkCRM `config/routes*`
(413 decls, 109 `resources` + 67 `resource`, depth ≤4, ~700–1300+ concrete routes). The route SHAPE is
already expressible in IgWeb syntax; the sole blocker is the compile wall P4 removes; authored-order priority
is confirmed by Rails' own semantics. No code, no migration, no live SparkCRM execution.*
