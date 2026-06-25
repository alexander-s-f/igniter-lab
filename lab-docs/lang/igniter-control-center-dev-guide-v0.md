# igniter control-center — developer guide (v0)

Educational DX, **not** a stability promise or new authority. For the precise current-truth surface see
[`lab-distribution-implemented-surface-v0.md`](lab-distribution-implemented-surface-v0.md); when an old proof
card disagrees with live `bin/igniter`, **the implemented-surface doc and live source win**.

All examples use **placeholder** env values only (`export NAME=`). Never commit `.env`, DSNs, or tokens.

---

## 1. What is `bin/igniter`?

A thin **control-center / router** over the package-local binaries — it adds NO authority of its own. Every
verb delegates to a named owner that enforces the real policy: loopback/public-bind refusal + request bound
live in `igweb-serve`; package trust in `igc`; host config/secrets stay in `--host-config` / the host
environment. The router only hides binary names and build paths.

```bash
igniter --help            # the command family
igniter <verb> --help     # per-verb help (serve / app / env / toolchain …)
```

From a source checkout the first run of a verb may build the binary it needs (hidden plumbing). To skip
building, point `IGNITER_IGWEB_SERVE_BIN` at a prebuilt `igweb-serve`.

---

## 2. Run a pure app  *(DB-free)*

A "pure" app has no `host.example.toml` — observed/loopback only, no machine mode.

```bash
# dry build/verify — opens NO socket
igniter check server/igniter-web/examples/todo_app

# serve on loopback, bounded (NOT a daemon — it exits after N requests)
igniter serve server/igniter-web/examples/todo_app --addr 127.0.0.1:8080 --max-requests 5
# → prints: listening http://127.0.0.1:8080 …   (a non-loopback --addr is REFUSED)
```

What this does **not** do: no public bind, no daemon, no DB, no secrets.

---

## 3. Run a machine / Postgres-shaped app  *(requires local Postgres)*

The committed catalogue is `host.example.toml` — it holds env-var **names** only (e.g. `dsn_env`,
`passport_env`), never values. Workflow:

```bash
APP=server/igniter-web/examples/todo_postgres_app

# (a) which env vars does it need, and are they set here? (NAMES + set/unset/empty — values never read)
igniter env doctor $APP

# (b) get a blank shell skeleton to fill in your own shell (values stay blank); each line carries a
#     `# [section].key` comment naming where the var came from
igniter env template $APP

# (c) export the REAL values in your shell only (never commit them), then GATE:
export IGNITER_TODO_PG_DSN=        # ← your local test DB connection string
export IGNITER_TODO_EFFECT_TOKEN=  # ← your local bearer credential
igniter env check $APP             # exit 0 if all set non-empty; exit 1 if any unset/empty

# (d) copy host.example.toml → host.toml (operator-owned, NEVER committed/bundled) and serve machine-mode:
cp $APP/host.example.toml $APP/host.toml      # then keep it out of git
igniter serve $APP --addr 127.0.0.1:8080 --max-requests 8 --host-config $APP/host.toml
```

Rules: env vars carry the secrets, the committed files carry only **names**; `igweb-serve` fails closed
(naming the missing var, never its value) before it binds. Use a **dedicated local test database**, never a
live or shared one.

---

## 4. Ask the agent (MCP) for the same env checks

`igniter agent` launches a local stdio MCP server (`igniter-agent`) whose tools shell-delegate to this same
front door — so agents (Codex/Claude/IDE) get the same **names-only** diagnostics, never values.

```bash
igniter agent      # speaks MCP (JSON-RPC) over stdin/stdout — wire into your agent's MCP config
```

Relevant tools: `env_doctor { path }` and `env_check { path }`. Each result is a P28 envelope —
`content[0]` human text + `content[1]` JSON `{ tool, ok, exit_code, parsed }` where
`parsed = { path, required_env: [{ name, status }], ok }`. Values are never present. (Other safe tools:
`doctor`, `toolchain_list`, `check_app`, `package_verify`, `app_bundle`, `serve_app_bounded`.)

---

## 5. Create and admit a local bundle

```bash
# assemble a versioned, self-contained bundle (ASSEMBLY ONLY — refuses a real host.toml / inline secrets)
igniter app bundle server/igniter-web/examples/todo_app --out /tmp/bundles --version v0-demo
# → /tmp/bundles/todo_app-v0-demo/{bin/igweb-serve, app/…, run/…, checks/…, systemd/*.example, manifest.json}

# validate + copy that bundle into a release root (VALIDATE + COPY ONLY)
igniter app admit /tmp/bundles/todo_app-v0-demo --release-root /tmp/releases
# → /tmp/releases/releases/todo_app/v0-demo/   (10 fail-closed gates: manifest, format v1, loopback,
#   private release, runner+source hashes, checks/check.sh, no real host.toml, machine→host.toml.example,
#   no duplicate destination)
```

`admit` is **not deploy**: it never swaps a `current` symlink, installs/enables systemd, binds, or runs the
app. Activation stays host-owned.

---

## 6. Check the toolchain

```bash
igniter doctor                    # local, non-mutating: rustc/cargo, repo, fleet, optional app-shape checks
igniter toolchain list            # the 5-binary default fleet (igniter-repl is [optional], opt-in)
igniter toolchain install --prefix ~/.igniter            # build+stage the fleet from THIS checkout
igniter toolchain update  --prefix ~/.igniter            # rebuild+restage an existing prefix
igniter toolchain install --with-repl --prefix ~/.igniter  # also stage the optional igniter-repl
```

Local-source only — no remote download, registry, version solver, or signing.

---

## 7. Where to look when docs disagree

1. **Live source** — `bin/igniter`, `bin/igniter-install`, `server/igniter-web/src/bin/igniter-agent.rs`.
2. **The front door** — [`lab-distribution-implemented-surface-v0.md`](lab-distribution-implemented-surface-v0.md).
3. Older readiness/proof packets are **history**; if one says "reserved/deferred/placeholder" but live code
   disagrees, the implemented-surface doc wins.

---

## What this stack does NOT do (v0)

No public release, registry, semver, remote install, signing, public bind, TLS/reverse proxy, systemd
install/enable, `current` symlink swap, DB creation/migration, secret management, `.env` reading, or stable
CLI-compatibility promise. Bundling/admission are local and validate-and-place only.
