# LAB-TODOAPP-DEMO-HTML-P56

Status: DONE
Route: fast_lane / TodoApp payoff / HTML DX
Skill: idd-agent-protocol

## Goal

Make the TodoApp HTML payoff easy to inspect after the P55 demo exists.

P55 already added a quick `scripts/todo_demo.sh html` verifier. This card is now
the smaller follow-up: persist an openable HTML artifact and make the human
inspection path nicer, without changing routes or rendering substrate.

P55 should prove the API/product cycle. This card adds a small, human-friendly
HTML inspection path around the existing HTML routes:

- `GET /accounts/:account_id/todos.html`
- `GET /accounts/:account_id/report/money` only if the required typed host
  policy is actually runnable; otherwise keep it documented as proof-only.

## Current Authority

Read first:

- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_html_tests.rs`
- `server/igniter-web/tests/todo_postgres_money_report_tests.rs`
- P55 demo script and `DEMO.md`

## Task

Add the smallest useful HTML DX layer:

- a `scripts/todo_demo.sh html` command, or similar, that fetches the HTML route
  from the running P55 demo server;
- writes the response to an ignored local artifact such as
  `.todo_demo/todos.html`;
- prints a `file://` or absolute path the user can open;
- asserts `Content-Type: text/html`;
- asserts escaped content and at least one Todo/detail link.

Do not build a UI framework. Do not add JS. Do not introduce `.ig.html`.

## Boundary

- Existing RenderView/render-html path only.
- No new route unless P55 showed a hard blocker.
- No browser automation required unless trivial and already available.
- No production report/export claim.
- Money report stays honest: if typed field kinds are not runnable through
  `host.toml`, do not pretend the DB-backed money route is product-ready.

## Acceptance

- [x] HTML demo command exists and is documented in `DEMO.md`.
- [x] It fetches real HTML from the running TodoApp demo server.
- [x] It saves an ignored local artifact and prints the path.
- [x] It checks `text/html`.
- [x] It checks escaping (no raw `<script>` from authored/user content).
- [x] It checks at least one detail/load-more link if rows exist.
- [x] Existing HTML tests still pass.
- [x] `git diff --check` clean.

## Closing

**Exact command** (from `server/igniter-web/`, server already `start`ed):

```bash
scripts/todo_demo.sh html
```

**What it does now (enhanced from the P55 stub).** Seeds one demo todo whose
title carries markup (`Demo <script>alert(1)</script> task`) via the real product
write path, fetches `GET /accounts/acct-demo/todos.html` with **no client
correlation** (P58: trace-derived correlations run fresh), **saves the response
to an openable artifact** and prints its path, runs six assertions, then removes
the seeded row (the artifact keeps the rendered snapshot).

**Saved artifact path** (gitignored):
`server/igniter-web/.todo_demo/todos.html` — printed as both an absolute path and
`file://…/.todo_demo/todos.html`. Added `.todo_demo/` + `**/.todo_demo/` to the
repo `.gitignore`; `git check-ignore` confirms it is never committed.

**HTML route inspected.** `GET /accounts/:account_id/todos.html` (the existing
`AccountTodoHtml` → `ReadThen` → `RenderView` path). No new route, no JS, no
`.ig.html`, no rendering-substrate change. Six checks: `200`, `text/html`,
HTML structure, **escaped `&lt;script&gt;`** from the seeded title, **no raw
`<script>`**, and **≥1 per-row detail link** (`href="/accounts/acct-demo/todos/todo_…"`).

**Money report stays proof-only.** `GET /accounts/:id/report/money` needs a host
policy with a typed `Decimal` field kind that `host.toml` cannot express yet
(`LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS`). It is proven DB-free in
`todo_postgres_money_report_tests` (4/4) only; the demo deliberately does **not**
drive it, and DEMO.md §5 documents it as proof-only — no product-ready report
claim.

**Verification summary (this box, local PG):**

- `scripts/todo_demo.sh html` → 6/6 PASS; artifact written + path printed; idempotent on re-run.
- `cargo test --features machine --test todo_postgres_html_tests` → 4/4 pass.
- `cargo test --features machine --test todo_postgres_money_report_tests` → 4/4 pass (DB-free).
- `scripts/todo_demo.sh smoke` → still PASS (15/15).
- `scripts/check_todo_product_surface.sh` → PASS (no DB).
- artifact gitignored (`git check-ignore` ✓); no trailing whitespace;
  `git diff --check` clean.

**Lab-only / unchanged.** Loopback demo, not production; same v0 constraints as
P55 (surrogate ids, object create body, no pooling). P58 removed the old
unique-correlation workaround; plain reads are now fresh even under `trace=true`.
