# LAB-TODOAPP-DEMO-HTML-P56

Status: TODO (reduced after P55)
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

- [ ] HTML demo command exists and is documented in `DEMO.md`.
- [ ] It fetches real HTML from the running TodoApp demo server.
- [ ] It saves an ignored local artifact and prints the path.
- [ ] It checks `text/html`.
- [ ] It checks escaping (no raw `<script>` from authored/user content).
- [ ] It checks at least one detail/load-more link if rows exist.
- [ ] Existing HTML tests still pass.
- [ ] `git diff --check` clean.

## Reporting

Close with:

- exact command;
- saved artifact path;
- what HTML route was inspected;
- whether money report remains proof-only or runnable;
- verification summary.
