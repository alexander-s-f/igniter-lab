# lab-distribution-control-center-cli-skeleton-p7-v0 — the minimal `igniter` control-center skeleton

> **Partly superseded (2026-06-25):** the "fail-closed placeholders" described here for `package` / `app` /
> `toolchain install|update` are now **live** — `toolchain install|update` → installer (P11), `package` →
> `igc` (P12), `app bundle` → assembly (P14). Only `igniter app …` (non-bundle) remains a placeholder. Live
> surface: [`lab-distribution-implemented-surface-v0.md`](lab-distribution-implemented-surface-v0.md).

**Card:** `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7` · **Type:** implementation + proof
**Status:** CLOSED — `bin/igniter` is now recognizably the v0 control center: the P6 taxonomy wired with
**honest delegation** (`serve`/`check`/`doctor`/`toolchain list` live) and **fail-closed placeholders**
(`toolchain install|update`, `package …`, `app …`). No authority moved, no lower-level CLI reimplemented, no
new binary build graph; `serve` stays P2-compatible. Proven by 9 wrapper tests (4 P2 + 5 new), all green.

## Gate check

Depends on **`LAB-DISTRIBUTION-CONTROL-CENTER-READINESS-P6`** → **CLOSED**
(`lab-docs/lang/lab-distribution-control-center-readiness-p6-v0.md`). Taxonomy + authority invariant taken
from it verbatim.

## Verify-first findings

- Read the P6 packet (taxonomy) and the current `bin/igniter` (P2: only `serve`).
- Ran the P2 wrapper smoke before editing — green.
- **`igweb-serve check` semantics** (`src/bin/igweb-serve.rs:37-46`): `check <app_dir>` builds the app and
  prints `check ok … (no socket opened)` — so **`igniter check <app_dir>` is a thin alias to `igweb-serve
  check`** (no new "check family" invented).
- **Package verbs** (don't lie about them): `igc` owns `lock`, `verify`, `package {graph,pack,verify,admit}`
  (`lang/igniter-compiler/src/main.rs`). So `igniter package` advertises the **planned 1:1 delegation to
  `igc`** and stays a placeholder (P6: no second resolver) rather than faking verbs.
- **Fleet/binaries** (P3): the 5 green binaries are present; `igniter-repl` is build-broken → marked
  `[blocked]`, never listed as available.
- **Build prerequisite** (verified earlier): the compiler `include_str!`s `igniter-lang/docs/spec/
  stdlib-inventory.json` from the canon sibling — `doctor` checks for it.

## What changed (1 file edited, 1 test file extended — no crate source touched)

**`bin/igniter`** — extended from the single-verb P2 wrapper to the v0 control center:

| Verb | v0 behavior | Owner / delegation |
|---|---|---|
| `serve <app_dir> …` | **unchanged from P2** (loopback, bounded, public-bind refused, `--host-config`) | `igweb-serve` |
| `serve --check <app>` / `check <app>` | dry build, **no socket** | `igweb-serve check` |
| `doctor` | local, **non-mutating** report: repo root, rustc/cargo, `igniter-lang` sibling, fleet presence; exits 0 | — (inspector) |
| `toolchain list` | names the 5-binary fleet (present/absent + build cmd); marks `igniter-repl` `[blocked]` | — (inspector) |
| `toolchain install\|update` | **fail-closed placeholder**, exit 3 → points to `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8` | — |
| `package …` | `--help` prints the planned `igc` delegation; any verb → **fail-closed**, exit 3 (use `igc`) | `igc` (planned) |
| `app …` | `--help` prints the release-bundle/systemd plan; any verb → **fail-closed**, exit 3 | release-bundle scripts (Model E) |
| `<unknown>` | family help + exit 2 | — |

Design notes: macOS `bash` 3.2-compatible (no associative arrays). `serve --help` shows a **serve-specific**
usage (keeps the P2 contract strings discoverable); top-level `igniter --help` shows the **P6 family**. No
shell-hidden semantics — argv forwarded, one `IGNITER_IGWEB_SERVE_BIN` env var honored. **The dispatcher
grants no authority**: loopback/public-bind, request bound, package trust, host-config all stay in the owners.

**`server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`** — 5 new tests through `bin/igniter`
(not by calling functions), added to the 4 P2 tests.

## Proof (executed)

```text
$ bin/igniter doctor
  igniter doctor — local environment (non-mutating)
    [ok    ] rustc … / cargo …
    [ok    ] igniter-lang sibling: …/igniter-lang (stdlib-inventory.json present)
    tools: [present] igc / igniter-vm / igweb-serve / igniter-mcp / tbackend
           [blocked] igniter-repl — unavailable in v0 (build fails: async resume)
  exit 0

$ bin/igniter toolchain list      → 5 present, igniter-repl [blocked]          exit 0
$ bin/igniter check <todo_app>     → check ok … (no socket opened)             exit 0
$ bin/igniter toolchain install    → not implemented → P8                      exit 3
$ bin/igniter package lock         → owned by igc; use igc directly            exit 3
$ bin/igniter app bundle           → release-bundle/systemd owns it            exit 3
$ bin/igniter package --help       → planned igc delegation                    exit 0
$ bin/igniter frobnicate           → family help                              exit 2
$ bin/igniter serve <app> --addr 0.0.0.0:8080  → refused (loopback-only)       exit 2
```

Automated (`cargo test --test igniter_serve_wrapper_smoke_tests` → **9 passed**):

| test | proves |
|---|---|
| `igniter_serve_app_returns_health_200_no_db` (P2) | live serve → `GET /health` → 200, no DB |
| `igniter_serve_check_opens_no_socket` (P2) | `serve --check` → no socket |
| `igniter_serve_refuses_public_bind` (P2) | public `--addr` refused end-to-end |
| `igniter_serve_help_names_contract` (P2) | `serve --help` keeps the P2 contract strings |
| `igniter_check_top_level_opens_no_socket` | `igniter check <app>` → `check ok … (no socket opened)` |
| `igniter_doctor_reports_local_status` | `doctor` exit 0, names repo/rustc/igniter-lang/fleet, non-mutating |
| `igniter_toolchain_list_names_fleet_and_marks_repl` | lists the 5 binaries + `[blocked]` repl |
| `igniter_placeholders_fail_closed` | `toolchain install` / `package lock` / `app bundle` exit non-zero; `package --help` exit 0 |
| `igniter_help_shows_family_and_unknown_fails` | top-level help names serve/check/doctor/toolchain/package/app; unknown → non-zero |

Regression: `runner_tests` 17, `example_app_tests` 7 — green. No crate source changed; `git diff --check` clean.

## Acceptance — mapping

- [x] `igniter serve` wrapper smoke remains green (4 P2 tests).
- [x] `igniter check <todo_app>` succeeds, opens no socket.
- [x] `igniter doctor` runs without network/DB/mutation, prints actionable local status.
- [x] `igniter toolchain list` names the 5 green P3 binaries, marks `igniter-repl` unavailable.
- [x] Unimplemented commands fail clearly non-zero (exit 3), never silent success.
- [x] Help output shows the P6 command family.
- [x] No root workspace migration, no new binary build graph (bash + delegation only).
- [x] `git diff --check` clean.

## Closed surfaces (honored)

No installer implementation (placeholder → P8). No package-manager implementation (delegates to `igc`). No
update/download, no registry. No binary rename (the artifact is still `igniter_compiler`; the fleet just
*labels* it `igc`). No systemd/Docker/Homebrew.

## Follow-ons

- `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8` — make `toolchain install/update` real (build+stage the fleet).
- `LAB-DISTRIBUTION-DOCTOR-READINESS-P9` — flesh out `doctor` checks/output per its readiness.
- First-class `igniter package` delegation to `igc` (lock/verify/graph/pack/admit) — a focused follow-on.
- `igniter-repl` async-fix; later, promote the shell dispatcher to a Rust `igniter` crate.

---

*Lab proof. 2026-06-24. `bin/igniter` is the v0 control center: `serve`/`check`/`doctor`/`toolchain list` live
with honest delegation; `toolchain install|update`, `package`, `app` are fail-closed placeholders pointing to
their owners. No authority moved, `serve` P2-compatible, no new build graph. 9 wrapper tests green; existing
runner/example suites green; `git diff --check` clean.*
