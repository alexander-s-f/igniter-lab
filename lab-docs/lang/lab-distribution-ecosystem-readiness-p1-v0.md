# LAB-DISTRIBUTION-ECOSYSTEM-READINESS-P1 — distribution & DX map (v0)

Status: readiness packet (map only, no implementation)
Card: `LAB-DISTRIBUTION-ECOSYSTEM-READINESS-P1`
Date: 2026-06-24
Authority: this is **evidence/inventory**, not a release decision. No installer, no public-release
claim, no root-workspace migration is authorized by this packet. See related boundary memory
`igniter-lab-repo-boundary` (no Cargo workspace root = the split blocker).

---

## 0. Verify-first basis (what was actually inspected)

- Every `Cargo.toml` under `lang/`, `runtime/`, `server/`, `frame-ui/`, `ide/` (14 manifests; **no root
  workspace manifest** — confirmed package-local).
- All binary entrypoints: explicit `[[bin]]` + implicit `src/main.rs` + `src/bin/*.rs`.
- `runtime/igniter-tbackend/Cargo.toml` (FFI split pattern) and `server/igniter-web/src/bin/igweb-serve.rs`
  (current runner DX).
- Home-lab distribution evidence: `artifacts/tbackend/p3`, `artifacts/tbackend/p4`, `deploy/`,
  `docs/inventory/`.
- `README.md`, `MAP.md`, `lab-docs/lang/current-waves-index.md` for stale distribution claims (none found;
  the docs explicitly keep "stable CLI" / "public hosting" *out* of scope).

**Live-shape correction vs the card's stated shape:** the card says "`lang/igniter-compiler` owns `igc`".
The compiler self-names `igc` in its own usage text, but there is **no `[[bin]] name = "igc"`** — it builds
from an implicit `src/main.rs`, so the produced binary is **`igniter_compiler`**, not `igc`. This is a real
DX gap (documented command name ≠ built artifact name), flagged below as a next card.

---

## 1. Binary inventory

Implicit-`main.rs` binaries take the **package** name; underscores are kept (cargo does not rewrite to
hyphens for implicit binaries). Names below are the **actual built artifact** names.

| Crate | Built binary | Build command | Features | Audience / role |
|---|---|---|---|---|
| `lang/igniter-compiler` | **`igniter_compiler`** (CLI self-names `igc`) | `cargo build --release` (implicit `src/main.rs`) | none (pure) | Dev tool — `compile`, `lock`, `verify`, `package graph/pack/verify/admit` |
| `lang/igniter-vm` | `igniter-vm` (`[[bin]]`) | `cargo build --release --bin igniter-vm` | none | Dev tool / runner — `run`, `compile`, `trace`, `bytecode-map` |
| `lang/igniter-stdlib` | — (library only) | n/a | none | Library; consumed by compiler/VM |
| `runtime/igniter-machine` | `igniter-mcp` (`src/bin/mcp.rs`) | `cargo build --release --bin igniter-mcp` | default `[]` | MCP / agent-coordination surface (default-buildable) |
| `runtime/igniter-machine` | `igniter-repl` (`src/bin/repl.rs`) | `cargo build --release --bin igniter-repl --features repl` | `repl` (ratatui+crossterm) | Experimental interactive REPL (opt-in) |
| `runtime/igniter-tbackend` | `tbackend` (`[[bin]]`) | `cargo build --release --bin tbackend` | default `[]`; `ffi` (magnus) opt-in | Daemon — **the FFI-split exemplar** |
| `server/igniter-server` | `igniter-server` (`src/bin/igniter-server.rs`) | `cargo build --release --bin igniter-server` | default `[]`; `machine` opt-in | Server/protocol host |
| `server/igniter-web` | `igweb-serve` (`src/bin/igweb-serve.rs`) | `cargo build --release --bin igweb-serve` | default `[]`; `machine`, `postgres` opt-in | **App runner — the Rails-`s` candidate** |
| `frame-ui/igniter-frame` | — (lib; `default=["machine"]`, `wasm` opt-in, cdylib+rlib) | n/a | `machine` (default), `wasm` | Frontend runtime library |
| `frame-ui/igniter-3d`, `-gui`, `-console`, `-ui-kit` | — (libs; `wasm` opt-in) | n/a | `wasm` | Experimental browser/WASM frontends |
| `frame-ui/igniter-render-html` | — (lib) | n/a | none | HTML renderer library |
| `ide/igniter-ide` (`src-tauri`) | Tauri desktop app | `npm install && npm run tauri dev` (in `ide/igniter-ide`) | n/a (Tauri/npm) | Experimental desktop IDE; **not** a cargo-install target |

**Feature-gated binaries summary:** only `igniter-repl` is *hard* feature-gated (`required-features =
["repl"]`). `tbackend --features ffi`, `igniter-server --features machine`, `igweb-serve --features
machine|postgres`, and the `frame-ui` `wasm` builds are opt-in *capabilities on an otherwise-pure default
build*, not separate binaries.

**Audience buckets:**
- **Developer tools:** `igniter_compiler`(igc), `igniter-vm`.
- **App runner:** `igweb-serve`.
- **Daemons / hosts:** `tbackend`, `igniter-server`.
- **MCP / agent surface:** `igniter-mcp` (+ experimental `igniter-repl`).
- **Experimental frontends:** `frame-ui/*` libs, `igniter-ide` (Tauri).

---

## 2. Install surfaces (compared)

| Surface | How | Works today? | Verdict for v0 |
|---|---|---|---|
| **A. `cargo build --release --bin` / `cargo install --path <crate>`** | Per-crate, package-local | Yes (each crate builds standalone via `../` path-deps) | **v0 baseline.** Already real. Caveats: (1) no single command builds the whole fleet — no root workspace; (2) `igc`/`igniter_compiler` name mismatch leaks into `cargo install` output. |
| **B. Prebuilt release tarball** | Per-target `.tar.gz` + `manifest.json` + `SHA256SUMS` + smoke | **Proven for `tbackend`** (home-lab P3, x86_64 + aarch64) | **Recommended to generalize** to `igweb-serve`/`igniter-vm`/`igc` later. Keep `public_release:false`. |
| **C. Shell wrapper (`igniter <verb>`)** | One dispatcher script calling package-local binaries | Not present; trivial to add | **Recommended first ergonomic slice.** Gives `igniter serve` without a root workspace. |
| **D. `.deb` package** | `dpkg-deb` payload + systemd unit | **Proven for `tbackend`** (home-lab P4, amd64 + arm64) | Out of v0 (closed surface); strong precedent exists. |
| **E. release-bundle + systemd** | versioned bundle + `current` symlink + user unit | **Proven for IgWeb** (home-lab P14 active on pi5-lab; P18 smoke on pi5-lab2) | Out of v0; precedent exists for loopback IgWeb apps. |
| **F. Docker / Compose** | container image + compose | Design docs only | Out of v0 (closed surface). |
| **G. Homebrew tap / registry / signing** | external | None | Out of v0 (closed surface). |

At least three real alternatives compared above: **A (cargo-local)**, **B (tarball)**, **C (wrapper)** are
all v0-reachable; **D/E** have home-lab precedent but are closed for this card.

---

## 3. TBackend lesson → mapped to server / compiler / machine

**Lesson (from `runtime/igniter-tbackend`):** the daemon is **pure Rust by default** (`default = []`); the
Ruby/Magnus FFI adapter is **opt-in** (`ffi = ["dep:magnus"]`). Operators build with no flags. Pure core
first; host bindings/adapters second.

This pattern is **already adopted ecosystem-wide** — the map's job is to make that explicit:

| Crate | Pure default core | Opt-in host adapters / capabilities |
|---|---|---|
| `igniter-tbackend` | `default = []` daemon | `ffi` (magnus Ruby bridge) |
| `igniter-machine` | `default = []` machine | `repl`, `tls` (rustls), `postgres` (tokio-postgres) |
| `igniter-server` | `default = []` | `machine` (pulls `igniter_machine` + tokio) |
| `igniter-web` | `default = []` (observed/machine-free runner) | `machine`, `postgres` (forward to machine adapters) |
| `igniter-compiler` (`igc`) | pure, **no features** | — (already minimal; nothing to split) |
| `frame-ui/*` | machine-free libs | `machine` (frame only), `wasm` |

**Takeaway:** the FFI-split discipline is the ecosystem default, not a tbackend special case. The
distribution story should advertise a **pure default install** for every binary and treat
`postgres`/`tls`/`repl`/`ffi`/`machine`/`wasm` as documented add-ons (see next-card: feature matrix).

---

## 4. Home-lab distribution ladder (what each rung proved / did not prove)

Exact artifact paths (private lab evidence — precedent, not to copy host config):

| Rung | Path | Proved | Did NOT prove |
|---|---|---|---|
| **Native tarball (P3)** | `igniter-home-lab/artifacts/tbackend/p3/` — `tbackend-0.1.0-55b4dd9-{x86_64,aarch64}-unknown-linux-gnu.tar.gz`, `manifest.json`, `SHA256SUMS` | Multi-arch native build, hashed (binary/archive/config SHA), on-target loopback smoke (`ok/pong`), build host recorded, `public_release:false` | Packaging integration, systemd readiness, host deployment |
| **`.deb` (P4)** | `igniter-home-lab/artifacts/tbackend/p4/` — `tbackend_0.1.0-55b4dd9_{amd64,arm64}.deb`, `manifest.json`, `SHA256SUMS` | Multi-arch `.deb` (sourced from P3 tarballs), payload `/usr/bin/tbackend` + `/etc/tbackend/tbackend.config.json` + `/var/lib`+`/var/log` + `/lib/systemd/system/tbackend.service`, `dpkg-deb` structure valid, `systemd-analyze verify` UNIT_VALID, binary smoke | Live `systemctl enable`, production deployment |
| **release-bundle + systemd (P14/P18)** | `igniter-home-lab/deploy/pi5-lab/*.service`, `run-*.sh`, `check-*.sh`; model in `deploy/igniter-stack-deployment-models.md` | IgWeb loopback app shipped as versioned bundle + `current` symlink + user systemd unit, **active on pi5-lab** (P14), smoke-tested on pi5-lab2 (P18); loopback-only `127.0.0.1` exposure; symlink-swap rollback | Docker/Compose, package-manager pull, public exposure |
| **Docker / Compose** | `igniter-home-lab/deploy/hp-*.md` (readiness docs) | Readiness/exposure policy evaluated | No tbackend/IgWeb container integration (sketched only) |
| **package-pull / swarm** | deployment-models doc direction | Strategic direction noted | No resolver, no registry, no signature (planned only) |

Device inventory (`igniter-home-lab/docs/inventory/`): `ai-main-lab` (x86_64 host), `pi5-lab` (aarch64
edge, P14 active), `pi5-lab2` (aarch64 edge, P18 smoke). Available for future distribution experiments; do
not mutate hosts or copy secrets from this card.

**Ladder verdict:** rungs 1–3 (tarball → `.deb` → bundle+systemd) have **real, hashed, on-target
evidence**; rungs 4–5 (Docker → swarm) are **sketched/planned**. The proven rungs exist **only for
`tbackend` (1–2) and IgWeb loopback apps (3)** — they are not yet generalized to `igc`/`igniter-vm`.

---

## 5. Rails-`s` analogue (what v0 app-start should feel / not hide)

The runner already exists: `igweb-serve <app_dir>` — sync `TcpListener` + `serve_loop` by default,
async machine mode under `--host-config` (opt-in `machine`). It prints a machine-readable
`listening http://127.0.0.1:PORT` line, binds **loopback**, and is request-bounded.

**Proposed v0 feel:**

```
igniter serve ./my_app        # thin wrapper → igweb-serve ./my_app
# → igweb-serve: app_dir=./my_app entry=... sources=N listening http://127.0.0.1:PORT (loopback)
```

**Must NOT hide:**
- the **loopback bind** — never silently default to `0.0.0.0`; a public bind must be an explicit,
  visible flag;
- the **entry contract** and source count (already echoed by `igweb-serve`);
- the **machine-mode opt-in** (`--host-config` / `machine` feature) vs the observed default;
- the **request bound** (the runner is intentionally bounded, not an unbounded server).

**Should hide (ergonomics):** the underlying binary name, the per-crate build path, and target-dir
plumbing — that is exactly what wrapper **C** buys.

---

## 6. Risks

1. **Root-workspace churn.** Adding a root `Cargo.toml` to get one build command would touch every crate's
   `../`-path-dep resolution and is the known repo-split blocker (`igniter-lab-repo-boundary`). **Closed
   surface here** — the wrapper (C) achieves the ergonomics without it.
2. **Binary-name mismatch.** `igc` (documented/help) vs `igniter_compiler` (built). Leaks into any
   `cargo install` / wrapper story. Cheap to fix with a `[[bin]] name = "igc"` alias.
3. **Dependency size / feature flags.** `tls`/`postgres`/`machine`/`ffi` pull heavy trees (rustls,
   tokio-postgres, magnus). The pure-default discipline is correct; the risk is **undocumented** feature
   combinations — needs a single matrix.
4. **Config & secrets.** `--host-config` does env-var expansion of `host.toml`. Distribution must ship
   *templates*, never baked secrets (home-lab P4 ships `/etc/tbackend/tbackend.config.json` as a conffile —
   follow that, no secret values).
5. **Public-bind safety.** Any wrapper or tarball default must stay loopback. A future public listener is a
   separate, explicitly-authorized surface.
6. **Generalization gap.** Tarball/`.deb` precedent is `tbackend`-only; IgWeb has only the bundle rung. Do
   not imply `igc`/`igniter-vm` have packaged artifacts — they do not yet.

---

## 7. Recommended next cards (max 5)

**Verify-first note:** a distribution wave is **already drafted** in `.agents/work/cards/lang/`. This map
does not invent new cards — it sequences the existing ones and feeds them the shape they asked P1 to
decide. The ordering below is the recommendation.

1. **`LAB-DISTRIBUTION-RAILS-SERVE-DX-P2`** (exists) — smallest Rails-like `serve` proof. **P1 feeds it the
   shape (§5):** a thin `igniter serve <app_dir>` over `igweb-serve`, **loopback-default**, machine-readable
   `listening` line, request-bounded, **no root workspace** (achieved via wrapper, not a workspace migration).
   The home-lab `deploy/pi5-lab/run-todo-loopback.sh` + `igweb-todo-loopback.service` are the precedent shape.
2. **`LAB-DISTRIBUTION-RELEASE-BINARY-MATRIX-P3`** (exists) — release-build matrix (which binaries build,
   features required, sizes, dependency/feature boundaries). **P1 feeds it §1+§3.** *Add to its scope:* the
   **`igc` vs `igniter_compiler` binary-name mismatch** (Risk #2) — the matrix should record built-artifact
   names, which surfaces the gap.
3. **`LAB-DISTRIBUTION-INSTALLER-READINESS-P4`** (exists) — choose the v0 user-facing channel. **P1 feeds it
   §2+§4:** the comparison ranks **A (cargo-local) / B (tarball) / C (wrapper)** as v0-reachable and
   **D/E/F/G** as out-of-v0; the tbackend tarball/`.deb` ladder is the precedent to generalize one rung at a
   time.
4. **`LAB-DISTRIBUTION-ROOT-WORKSPACE-READINESS-P5`** (exists) — evaluate root workspace vs package-local.
   **P1's standing recommendation:** prefer the **wrapper (C)** to get one ergonomic command *without* root
   churn; treat a root `Cargo.toml` as the known split-blocker (`igniter-lab-repo-boundary`), not a v0 need.
5. *(only genuinely-new gap)* **`LAB-DISTRIBUTION-BINARY-NAME-ALIGNMENT-P*`** — if P3 does not absorb it,
   a focused card to add `[[bin]] name = "igc"` and audit every built binary name vs its documented CLI
   name. Small, but it unblocks an honest `cargo install` / wrapper story.

---

## Acceptance trace

- [x] Inventories all current Rust binaries + feature-gated binaries (§1).
- [x] ≥3 install/distribution alternatives compared (§2: A cargo-local, B tarball, C wrapper, + D/E/F/G).
- [x] Names one first implementation slice for "Rails-like serve" (§5 + next-card #1: `igniter serve`).
- [x] TBackend FFI-split lesson explicitly mapped to server/compiler/machine (§3).
- [x] Home-lab tarball/deb/bundle evidence summarized with exact artifact/doc paths (§4).
- [x] No implementation/code changes (map only).
