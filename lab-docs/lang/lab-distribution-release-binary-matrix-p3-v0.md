# Release Binary Matrix — v0 (LAB-DISTRIBUTION-RELEASE-BINARY-MATRIX-P3)

Status: evidence packet (lab-only). `public_release: false`.
Card: `LAB-DISTRIBUTION-RELEASE-BINARY-MATRIX-P3`
Date: 2026-06-24

A boring fact packet: which core Igniter binaries build in release mode, which features
they require, how large they are, and which dependency/feature boundaries matter. No installer,
no upload, no cross-compilation, no signing, no Docker, no workspace-root migration. The matrix is
shaped so a later packager can turn it into tarballs/`.deb` without losing provenance — see
*Provenance fields* below, mirrored from home-lab TBackend P3/P4.

## Build environment (this measurement)

| field | value |
|-------|-------|
| `source_git_commit` | `a742763` (working tree **dirty** — lab WIP; SHAs below are of this checkout, not a clean tag) |
| build host | local dev workstation |
| `target_triple` | `aarch64-apple-darwin` |
| host arch | arm64 (Mach-O 64-bit) |
| rustc | `1.95.0 (59807616e 2026-04-14)` |
| build mode | `--release` (each crate's own `[profile.release]`: `opt-level=3`, `lto=true`, `codegen-units=1` where set) |

> There is **no root Cargo workspace** (intentional — see igniter-lab repo boundary). Every build is
> run package-locally in the crate directory; each crate has its own `target/`.

## Matrix

| Artifact (binary file) | Crate dir | Build command | Features | Size (bytes / human) | binary sha256 | Smoke | v0 install candidate |
|---|---|---|---|---|---|---|---|
| `igniter_compiler` | `lang/igniter-compiler` | `cargo build --release` | none | 3,639,952 / 3.5M | `9b5d25ceaed8475ff23d535e0c8099100df7b8152c6ea19c9f02fd54f8b954c3` | prints usage (`Usage: igc compile …`) | **yes** |
| `igniter-vm` | `lang/igniter-vm` | `cargo build --release` | none | 5,311,168 / 5.1M | `1c9c0d1ef120046321da62bf5044db6597a453375683e2ed0d1df1df0de732b9` | prints usage (`igniter-vm run …`) | **yes** |
| `tbackend` | `runtime/igniter-tbackend` | `cargo build --release --bin tbackend` | default (FFI-free) | 1,373,120 / 1.3M | `99dad4c0dae90332c12169a53114d1b05861613d387241967b1594ea4469e59e` | prints banner + usage | **yes** (already tarball'd+deb'd in home-lab P3/P4) |
| `igniter-mcp` | `runtime/igniter-machine` | `cargo build --release --bin igniter-mcp` | default `[]` | 4,494,912 / 4.3M | `a9510563760922d5a7f979851e2c86e15db7183382d2323b2a16d957d5e9ff85` | stdio MCP server: "ready … Backend: in_memory" → clean EOF shutdown | **yes** |
| `igweb-serve` | `server/igniter-web` | `cargo build --release --bin igweb-serve` | default (machine-free) | 6,449,936 / 6.2M | `315b586ac9a66bae9dd34eb8022cb26921268427edaf13b8c73cfa5ab55ec2da` | prints usage; `<no args>` → clean config error | **yes** |
| `igniter-repl` | `runtime/igniter-machine` | `cargo build --release --bin igniter-repl --features repl` | `repl` (`ratatui`+`crossterm`) | — | — | **build FAILS** (see below) | **no — blocked** |

All sha256 are `Mach-O 64-bit executable arm64` (verified via `file`).

### `igniter-repl` — build failure (documented, not fixed)

`cargo build --release --bin igniter-repl --features repl` fails with **6 × `E0308` (mismatched types)**
in `runtime/igniter-machine/src/bin/repl.rs`. Root cause: the binary calls the machine API
**synchronously** while those methods are now `async` (return `impl Future`):

- `self.machine.checkpoint(Path::new(path))` matched directly at `repl.rs:558` (arms 559/565)
- `IgniterMachine::resume(…)` matched directly at `repl.rs:576` (arms 577/586) and `repl.rs:894` (arms 895/896)

Each site is `match <future> { Ok(_) … Err(_) … }` where an `.await` is missing — the REPL binary
bit-rotted against the machine's async `checkpoint`/`resume` surface. This is a **real source bug, not a
packaging-metadata issue**, so per this card's Closed Surfaces it is left unfixed here and recorded as a
failing candidate. The other `igniter-machine` binary (`igniter-mcp`) and the whole default lib build are
unaffected. Follow-up: a focused `LAB-…-REPL-ASYNC-RESUME-FIX` card should `.await` these calls (and make
the enclosing fns async or block-on) and re-confirm against this matrix.

## Binary-name note — `igc` vs `igniter_compiler`

The card lists the compiler binary as `igc`, but `lang/igniter-compiler/Cargo.toml` has **no `[[bin]]`
override**, so the produced artifact is named after the package: `igniter_compiler`. The CLI usage string
self-labels `igc` (`Usage: igc compile …`), but no file named `igc` is produced. A future installer that
intends to ship the `igc` command must either rename on install or add `[[bin]] name = "igc"` to the
crate — flagged here so the packager does not assume `target/release/igc` exists.

## Pure defaults vs feature-gated builds

Verified with `cargo tree -e normal` (counts = matching dependency nodes):

| Crate | default pulls heavy/optional stack? | feature → adds |
|---|---|---|
| `igniter-tbackend` | **no** — `magnus` count = 0 (FFI-free default confirmed) | `ffi` → `magnus` (2 nodes) |
| `igniter-machine` | **no** — `{ratatui, crossterm, rustls, tokio-postgres, magnus}` count = 0 | `repl` → `ratatui`+`crossterm`; `tls` → `rustls`/`tokio-rustls`/`rustls-pemfile`; `postgres` → `tokio-postgres` |
| `igniter-web` | **no** — `tokio-postgres` count = 0 | `machine` → passes through to `igniter_server/machine` (effect host + `serve_*_effect`); `postgres` → implies `machine` + `igniter_machine/postgres` + `tokio-postgres` (2 nodes) |

### `igniter-web` default vs `machine`/`postgres` (detail)

- The default `igweb-serve` build is **observed/machine-free**: the effect-host serving path in
  `igniter_server` is gated behind the `machine` feature and is **off** by default.
- Subtlety for the packager: the **`igniter_machine` library is an unconditional path-dependency** of
  `igniter-web` (it owns `build_igweb_app`'s lower→load pipeline), so the machine crate is always *linked*.
  The `machine` feature toggles the igniter_server **effect-host/serving** capability, not whether the
  machine crate is compiled in. Binary size above (6.2M) is the default (machine-free serving) build.
- `--features postgres` is a **superset of `machine`** and additionally pulls `tokio-postgres`; it exists
  only for the gated local-Postgres e2e (`tests/todo_postgres_local_e2e_tests.rs`, skips when
  `IGNITER_TODO_PG_DSN` unset). Not a v0 install target.

## Known warnings

All builds succeed; libs emit non-fatal `dead_code`/unused warnings (counts this run): `igniter_compiler`
22, `igniter_vm` 15, `igniter_machine` 2, `igniter_tbackend_playground` 3. None block the binary; listed for
hygiene tracking only.

## Provenance fields for future tarball / `.deb` manifests

Carried from home-lab `artifacts/tbackend/p3/manifest.json` (tarball) and `p4/manifest.json` (`.deb`).
A later packager should record, per produced artifact:

**Always (tarball-level, P3):**
- `source_git_commit` (use a **clean tagged** commit, not a dirty tree)
- `version`
- `target_triple`
- `build_host`, `build_host_arch`
- `binary_sha256`
- `archive_sha256` (the `.tar.gz`)
- `config_sha256` (if a config ships alongside)
- `feature_set` (explicit; e.g. `[]`, `["machine"]`, `["repl"]`)
- `smoke` `{ result, service_touched: false }` — loopback/stdio smoke that does **not** touch any standing service
- `public_release: false` while lab-only

**Additionally for `.deb` (P4):**
- `package`, `arch` (debian arch: `amd64`/`arm64`)
- `package_sha256` (the `.deb`)
- `conffiles`, `payload` (file list)
- `input_p3_sha256` + `input_p3_target` (provenance link back to the tarball)
- verification block: `dpkg_deb_I` (metadata), `dpkg_deb_c` (payload, no AppleDouble/xattr junk),
  `dpkg_deb_x` (extracted ELF arch), `systemd_analyze_verify` (UNIT_VALID), `binary_smoke`, `verified_on`
- existing-service untouched assertion (e.g. `:7401 untouched`)

> TBackend lesson reused: prove the **pure default** first (FFI-free, machine-free, dep-light), opt-in the
> heavier host bindings (`ffi`/`machine`/`postgres`/`tls`/`repl`) separately, and keep build artifacts
> reproducible & service-non-touching.

## Summary

- **5 of 6** candidate binaries build clean in release and smoke-pass: `igniter_compiler`, `igniter-vm`,
  `tbackend` (FFI-free default), `igniter-mcp` (default), `igweb-serve` (machine-free default).
- **`igniter-repl` does not build** (`--features repl`) — 6× E0308, async `checkpoint`/`resume` called
  without `.await`. Real source bug; left unfixed per Closed Surfaces; follow-up card recommended.
- Pure defaults are confirmed dep-light: tbackend FFI-free, machine free of repl/tls/postgres stacks,
  igniter-web free of postgres (and machine effect-host gated off).
- Binary-name caveat: the compiler artifact is `igniter_compiler`, not `igc`.
