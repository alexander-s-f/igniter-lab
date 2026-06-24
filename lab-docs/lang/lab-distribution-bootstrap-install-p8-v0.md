# lab-distribution-bootstrap-install-p8-v0 — repo-local bootstrap installer for the `igniter` control center

**Card:** `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8` · **Type:** implementation + proof
**Status:** CLOSED — `bin/igniter-install` builds the 5 green release binaries package-locally from this
checkout (no root workspace), stages them + the `igniter` front door into a `--prefix` (default `~/.igniter`),
writes a provenance manifest, and runs a local smoke. The staged prefix is **self-contained**: the front door
resolves its co-located binaries (no rebuild, no env var). Proven by a fresh temp-prefix install + a standalone
staged-prefix run + an idempotent re-run; the co-located resolution has a regression test (10 wrapper tests green).

## Gate check

Depends on **P6** (taxonomy) and **P7** (CLI skeleton) — both **CLOSED**. The installer stages the P7 `igniter`.

## Verify-first findings

- **P3 matrix / P4 readiness:** the v0 channel is exactly this repo-local bootstrap script; the install set is
  the **5 green binaries**; `igniter-repl` is build-broken and excluded.
- **`igniter-repl` still build-broken** (P3, async `checkpoint`/`resume`) → excluded with a recorded reason.
- **Compiler artifact** is `igniter_compiler` (no `[[bin]] name="igc"`); the installer **aliases it to `igc`
  at install time** (a copy, *not* a crate rename — closed surface honored). `cargo build --release --bin
  igniter_compiler` produces it (verified).
- **Build prerequisite:** the compiler `include_str!`s `igniter-lang/docs/spec/stdlib-inventory.json` from the
  canon sibling — the installer **checks for it and fails closed** with a clear message if absent.
- **No runtime stdlib/prelude assets** (verified earlier): the binaries are self-contained, so the installer
  stages *only* binaries + the `igniter` front door (no `.ig`/prelude files).
- **`bin/igniter` is executable and can find a staged `igweb-serve`** — required a small P7-wrapper addition
  (co-located lookup), below.

## What changed

**New `bin/igniter-install`** (bash 3.2-safe, no network/registry):
- `--prefix PATH` (default `~/.igniter`); binaries land in `<prefix>/bin`.
- Fails closed if `cargo` is missing or the `igniter-lang` sibling inventory is absent.
- Builds package-locally and stages, per row `install-name | crate | cargo --bin | artifact`:
  `igc`(←`igniter_compiler`), `igniter-vm`, `igweb-serve`, `igniter-mcp`, `tbackend`. **Excludes
  `igniter-repl`** (build-broken — reason recorded in the manifest).
- Stages `bin/igniter` as the durable front door.
- Writes `<prefix>/igniter-manifest.json`: `source_git_commit`, `dirty`, `target_triple`, `public_release:
  false`, the excluded `igniter-repl` + reason, the front-door sha256, and per-binary `{name, path, crate,
  feature_set: [], sha256}`.
- Local smoke: `igniter --help` + `igniter check <todo_app>` (no socket). Never stages secrets / host-config /
  DSNs / systemd / Docker / public listeners.
- Idempotent: re-runs rebuild (incremental) and overwrite (`cp -f`) — the prefix is not corrupted.

**Edited `bin/igniter`** (P7 wrapper) — the staged-prefix contract: `resolve_igweb_serve` now checks a
**co-located sibling** `$SCRIPT_DIR/igweb-serve` (after the env override, before the repo target / build), and
the `doctor`/`toolchain list` fleet report prefers co-located staged binaries (`$SCRIPT_DIR/<name>`). This is
what makes `<prefix>/bin/{igniter,igweb-serve,…}` self-contained; the repo-dev path is unchanged.

**Edited the wrapper smoke test** — +1 test (`igniter_resolves_co_located_igweb_serve_in_staged_prefix`).

## Proof (executed)

**Fresh temp-prefix install** (`bin/igniter-install --prefix <tmp>/pfx`):

```text
igniter-install: prefix=<tmp>/pfx repo=…/igniter-lab
igniter-install: building igc / igniter-vm / igweb-serve / igniter-mcp / tbackend … staged (sha256 each)
igniter-install: staged igniter front door → <tmp>/pfx/bin/igniter
igniter-install: wrote manifest → <tmp>/pfx/igniter-manifest.json
igniter-install: smoke — igniter --help / igniter check (no socket)
igniter-install: done. (igniter-repl excluded: build-broken)
```

Staged tree: `<prefix>/bin/{igc, igniter, igniter-mcp, igniter-vm, igweb-serve, tbackend}`. The staged binary
sha256s match the P3 matrix exactly (e.g. `igc 9b5d25ce…`, `igniter-vm 1c9c0d1e…`, `igweb-serve 315b586a…`,
`igniter-mcp a9510563…`, `tbackend 99dad4c0…`) — provenance is consistent.

**Standalone staged prefix** (running `<prefix>/bin/igniter` directly, no env, cwd elsewhere):

```text
igniter doctor       → [present] igc/igniter-vm/igweb-serve/igniter-mcp/tbackend → …/pfx/bin/* (staged)
                       [blocked] igniter-repl — unavailable (build fails: async resume)
igniter toolchain list → same 5 (staged) + repl [blocked]
igc                   → "Usage: igc compile …"        (compiler help path; exit 0)
igniter check <todo_app> → "check ok … (no socket opened)"   (uses the CO-LOCATED igweb-serve, not the repo)
```

**Idempotent re-run** (`igniter-install --prefix <same>` again) → succeeds; prefix intact (6 files).

**Automated** (`cargo test --test igniter_serve_wrapper_smoke_tests` → **10 passed**): the 9 P2+P7 tests plus
`igniter_resolves_co_located_igweb_serve_in_staged_prefix` (copies the wrapper + `CARGO_BIN_EXE_igweb-serve`
into a temp bin dir, runs `check` with **no** env override → resolves the sibling). Regression `runner_tests`
17 + `example_app_tests` 7 green. `git diff --check` clean.

## Acceptance — mapping

- [x] Fresh temp prefix install succeeds from the repo checkout.
- [x] Installed `igniter` is executable and prints help.
- [x] Installed `igc` exists and invokes the compiler help/version path.
- [x] Installed `igweb-serve` supports `check <todo_app>` (via the staged front door).
- [x] Manifest records source commit / dirty / target triple / binary sha256 / feature set.
- [x] `igniter-repl` excluded with a documented reason (build-broken — P3).
- [x] Re-running install is idempotent (rebuild + `cp -f` overwrite; prefix not corrupted).
- [x] No root workspace, no network, no registry, no upload, no public release.
- [x] `git diff --check` clean.

## Closed surfaces (honored)

No public release. No tarball/.deb/Homebrew/Docker. No update server. No signing/notarization. No root
workspace. No production service install. No implicit DB or host authority. No crate-level binary rename
(`igc` is an install-time copy of `igniter_compiler`).

## Follow-ons

- `LAB-DISTRIBUTION-DOCTOR-READINESS-P9` — flesh out `igniter doctor`.
- Make `igniter toolchain install|update` call `igniter-install` (currently a fail-closed placeholder → P8).
- Generalize to a native tarball (P4 ladder) once repo-less install is needed; `igniter-repl` async-fix.

---

*Lab proof. 2026-06-24. `bin/igniter-install [--prefix ~/.igniter]` builds + stages the 5 green binaries
(igc←igniter_compiler, igniter-vm, igweb-serve, igniter-mcp, tbackend) + the `igniter` front door, writes a
provenance manifest, smokes `--help`/`check`. The staged prefix is self-contained (front door resolves
co-located binaries). igniter-repl excluded (build-broken). Idempotent; no workspace/network/secrets. 10
wrapper tests green.*
