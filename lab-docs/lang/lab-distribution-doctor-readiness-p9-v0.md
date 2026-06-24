# lab-distribution-doctor-readiness-p9-v0 — define `igniter doctor` diagnostics

**Card:** `LAB-DISTRIBUTION-DOCTOR-READINESS-P9` · **Type:** readiness (design, **no code**).
**Authority: lab readiness — a design recommendation.** Closed surfaces honored: no implementation, no
auto-fix, no network/DB by default, no host mutation, no secret printing.

## Bottom line

`igniter doctor` is a **non-mutating local inspector** that answers "why won't this run?" by checking
presence/shape and **suggesting the exact next command** — never fixing, never connecting, never printing a
secret. Two scopes:

- **`igniter doctor`** — toolchain/environment checks (no app needed). *(P7 already ships a minimal version;
  this packet formalizes + extends it.)*
- **`igniter doctor <app_dir>`** — the toolchain checks **plus** app-shape checks for that directory.

Output: **human text by default, `--json` for machines** (both). Severity: **`ok` / `warn` / `fail` / `info`**.
v0 **exits 0 always** (it is a report); a `--strict` non-zero-on-`fail` mode is a named follow-on.

## Verify-first findings (real failure modes + error styles)

- **P7 already implemented a minimal `doctor`** (`bin/igniter`): repo root, rustc/cargo, `igniter-lang`
  sibling, 5-binary fleet presence, `igniter-repl` `[blocked]`. This packet treats that as the v0 seed.
- **igweb-serve diagnostics** (`runner_diag.rs`): a stable code taxonomy — `CONFIG_PARSE`, `CONFIG_RESOLVE`,
  `BIND_REFUSED` (exit 5), `POSTGRES_CONNECT` (message **redacted**, never carries the DSN), `RUNNER_INTERNAL`
  (exit 11). A non-loopback `--addr` fails closed as **`CONFIG_PARSE`** *before* any socket.
- **host.toml contract** (`host_config.rs`): stores env-var **NAME** refs (`dsn_env = "IGNITER_PG_WRITE_DSN"`);
  inline raw-secret keys (`dsn`, `password`, `secret`, `token`, `passport`, `api_key`) **fail closed**;
  `[postgres.*]` without `dsn_env` fails closed; resolved `*_dsn`/`passport` are **never logged**.
- **`igniter check <app>`** (`igweb-serve check`) is the cheap, socket-free app build — doctor should
  **point to it**, not re-compile heavily itself.
- **Name mismatch:** artifact is `igniter_compiler`; `igc` is an install-time alias (P8). Doctor surfaces this.
- **`igniter-repl`** is build-broken (P3) — a known *exclusion*, reported as `info`, not a `fail`.

## Candidate checks — classified (≥10; v0 set marked ✓)

### A. Toolchain / environment — `igniter doctor` (purely local, non-mutating)

| # | Check | Severity rule | v0? | Suggested next command |
|---|---|---|---|---|
| 1 | repo/prefix root resolvable | `info` | ✓ | — |
| 2 | `rustc` present (+version) | `ok`/`fail` | ✓ | `fail` → install via https://rustup.rs |
| 3 | `cargo` present (+version) | `ok`/`fail` | ✓ | `fail` → install Rust toolchain |
| 4 | `igniter-lang` sibling + `stdlib-inventory.json` (BUILD prereq) | `ok`/`fail` | ✓ | `fail` → check out `igniter-lang` beside `igniter-lab` |
| 5 | each fleet binary present (igc, igniter-vm, igweb-serve, igniter-mcp, tbackend) | `ok`/`warn` | ✓ | `warn` → `bin/igniter-install` or the per-crate `cargo build --release --bin …` |
| 6 | `igc` alias present (vs `igniter_compiler` artifact) | `info`/`warn` | ✓ | `warn` → `igniter-install` stages `igc` |
| 7 | `igniter-repl` known-excluded (build-broken) | `info` | ✓ | (info only) repl async-fix card |
| 8 | which `igweb-serve` `serve` will use (co-located / repo target / `IGNITER_IGWEB_SERVE_BIN`) | `info` | ✓ | — |
| 9 | prefix `bin/` on `$PATH` (is `igniter` itself reachable?) | `ok`/`warn` | ✓ | `warn` → `export PATH="<prefix>/bin:$PATH"` |
| 10 | install manifest present + provenance (commit/dirty/triple) if installed | `info`/`warn` | ✓ | `warn` → re-run `igniter-install` |
| 11 | `STDLIB_VERSION` ↔ lockfile / toolchain skew | `warn` | — (defer) | future deep check |

### B. App-shape — `igniter doctor <app_dir>` (toolchain checks **+** these)

| # | Check | Severity rule | v0? | Suggested next command |
|---|---|---|---|---|
| 12 | `<app_dir>` exists + readable | `ok`/`fail` | ✓ | `fail` → check the path |
| 13 | `igweb.toml`/manifest present + parses (entry, sources) | `ok`/`fail` | ✓ | `fail` → see `igniter check <app>` |
| 14 | app builds / entry resolves | (delegated) | ✓-as-pointer | run `igniter check <app>` (doctor points; does **not** recompile) |
| 15 | `host.toml` (if present) uses `*_env` name refs, **no inline secret keys** | `ok`/`fail` | ✓ | `fail` → replace inline `dsn/password/secret/token/passport/api_key` with `*_env` |
| 16 | `host.toml` `[postgres.*]` has required `dsn_env` | `ok`/`fail` | ✓ | `fail` → add `dsn_env = "IGNITER_PG_…"` |
| 17 | referenced env vars present (by **NAME**, presence boolean only) | `ok`/`warn` | ✓ | `warn` → `export <NAME>=…` before serving |
| 18 | machine/postgres expected but binary built without the feature | `info`/`warn` | ✓ | `warn` → rebuild `--features machine`/`postgres` (runner denies otherwise) |
| 19 | live Postgres DSN connectivity | — | — (defer) | needs DB connect — explicit opt-in card |

**≥10 classified** (19 candidates; 16 in the v0 set, split A=toolchain / B=app).

## The 7 required answers

**1. Checks in v0.** A1–A10 (toolchain) + B12–B18 (app, when `<app_dir>` given). #14 is a *pointer* to
`igniter check`, not a doctor-run compile.

**2. Purely local, non-mutating.** All of them. Doctor reads files and the environment, runs `--version`
probes, and inspects paths. It never writes (beyond nothing), never connects, never compiles in v0 (it
*suggests* `igniter check`).

**3. App-specific scope.** Use **`igniter doctor <app_dir>`** (not a separate `app doctor`) — it runs the
toolchain checks plus B12–B18. Rationale: `doctor` is already the diagnostic verb; an optional positional
arg keeps one front door (consistent with `serve`/`check <app_dir>`).

**4. Output format.** **Both** — human text is the default (the P7 `[ok]/[warn]/[fail]/[info]` lines, grouped
*environment / tools / app*); `--json` emits a stable array `[{check, scope, severity, detail, suggest}]` for
scripting/CI. JSON values carry **names/booleans only**, never secrets.

**5. Severity.** Four levels: **`ok`** (satisfied), **`warn`** (works but degraded / will bite later, e.g.
binary absent, not on PATH), **`fail`** (will not run, e.g. no rustc, missing sibling, inline secret in
host.toml), **`info`** (context, e.g. resolution source, repl-excluded). **v0 exit is 0** (a report); a
`--strict` flag that exits non-zero when any `fail` is present is a named follow-on.

**6. Deferred checks.** #11 STDLIB_VERSION/lockfile skew; #19 live Postgres connectivity (any DB connect);
**network** checks; signature/registry/version-pull; systemd/Docker/launchd health; auto-fix; remote
toolchain. All out of v0 (closed surfaces).

**7. Implementation card.** **`LAB-DISTRIBUTION-DOCTOR-IMPL-P10`** *(genuinely-new — to be drafted)*: extend
the P7 `doctor` to the full v0 set, add `igniter doctor <app_dir>` (B-checks) and `--json`, with the severity
model above. Keep it shell in v0 (consistent with P7); the Rust-CLI promotion absorbs JSON cleanly later.

## Security (no secrets, ever)

Doctor reads `host.toml` but reports only: offending **key names** (`"inline secret key 'password' — use
password_env"`), env-var **names** + presence booleans, and `*_dsn`/`passport` **never**. This mirrors the
`runner_diag` redaction contract (`POSTGRES_CONNECT` scrubs DSNs). #17 prints `IGNITER_PG_WRITE_DSN: set` /
`unset`, never the value. JSON output obeys the same rule.

## Acceptance — mapping

- [x] ≥10 candidate checks classified (19, table A+B).
- [x] v0 check set is small, local, non-mutating (A1–A10 + B12–B18; reads/probes only, no compile/connect).
- [x] App-specific vs toolchain-specific separated (table A vs B; `igniter doctor <app_dir>`).
- [x] Output/severity format specified (text default + `--json`; ok/warn/fail/info; v0 exit 0, `--strict` deferred).
- [x] Security-sensitive checks avoid printing secrets/DSNs (names/booleans only; mirrors runner_diag).
- [x] Follow-up implementation card named (`LAB-DISTRIBUTION-DOCTOR-IMPL-P10`, to be drafted).
- [x] No code changes; `git diff --check` clean.

## Closed surfaces (honored)

No implementation, no auto-fix, no network/DB by default, no host mutation, no secret printing.

---

*Lab readiness. 2026-06-24. `igniter doctor` = non-mutating local inspector: `igniter doctor` (toolchain:
rustc/cargo, igniter-lang sibling, fleet presence, igc alias, repl-excluded, PATH, resolution source,
manifest) + `igniter doctor <app_dir>` (app dir/manifest/entry, host.toml secret-safety + dsn_env, env-var
presence, feature expectation). Text default + `--json`; ok/warn/fail/info; v0 exits 0 (`--strict` later).
Never prints secrets/DSNs. Build #14 delegates to `igniter check`. Impl → LAB-DISTRIBUTION-DOCTOR-IMPL-P10.*
