# lab-distribution-root-workspace-readiness-p5-v0 — root Cargo workspace vs package-local builds

**Card:** `LAB-DISTRIBUTION-ROOT-WORKSPACE-READINESS-P5` · **Type:** readiness (decision input, **no code change**).
**Authority: lab readiness — a recommendation, not a migration.** Closed surfaces honored: no workspace
migration, no lockfile churn, no dependency updates, no feature unification, no packaging implementation.

## Bottom line

**Defer the root Cargo workspace. Do NOT introduce it before v0 DX install.** The package-local model is not
just "frontier isolation" — it is **load-bearing** for two deliberate dev-dependency back-edges and a
feature-gated machine/UI/server separation that a workspace's feature unification would actively break. The
v0 DX need ("build N binaries / one install command") is fully served by the **already-proven no-root release
bundle (Model B)** plus a thin **root `xtask`/shell bootstrap** that orchestrates the existing per-crate
`cargo build --release` invocations. **The release bundle, not Cargo, is the integration unit.**

## Verified current state (no root workspace today)

- **No root `[workspace]`** anywhere in `igniter-lab` (confirmed: no `Cargo.toml` with `[workspace]`).
- **15 `Cargo.toml` + 15 independent `Cargo.lock`** (14 product crates + the ephemeral `det-math-t2-harness`
  evidence crate from P4, which is not a product crate). All `edition = "2021"`; **none declares `resolver`**.
- Product crates and their **normal** path-deps (`→`):

```text
igniter_stdlib            (leaf)
igniter_compiler          (leaf)                                   # the `igc` CLI
igniter_vm                → stdlib                                 # VM runner bin
igniter_tbackend_playgr.  (leaf, default=[])                       # `tbackend` bin
igniter_render_html       (leaf, serde_json only)
igniter_machine           → compiler, vm, tbackend                 # repl/mcp bins; [dev] → console, ui_kit
igniter_frame             → machine (OPTIONAL; default=["machine"])
igniter_ui_kit            → frame (default-features=false)
igniter_gui               → frame (default-features=false)
igniter_3d                → frame (default-features=false)
igniter_console           → frame (default-features=false), ui_kit
igniter_server            → machine (OPTIONAL); [dev] → web        # default=[] serde-only
igniter_web               → server, compiler, machine, render_html # the de-facto aggregator (igweb-serve)
igniter-ide (src-tauri)   → machine (no-default), compiler, vm     # Tauri app, own build system
```

### Two deliberate dev-dependency back-edges (the crux)

Cargo permits a dependency cycle **only if at least one edge is a dev-dependency**. The lab uses this twice,
on purpose, to keep the **normal**-dep graph acyclic while still running top-of-stack E2E proofs:

1. `igniter_machine --[dev]--> igniter_console / igniter_ui_kit --> igniter_frame --(machine feature)--> igniter_machine`
   — broken because console/ui_kit take `igniter_frame` with **`default-features = false`** (machine OFF), and
   the back-edge to machine is a **dev**-dep (documented in `runtime/igniter-machine/Cargo.toml:57-62`).
2. `igniter_server --[dev]--> igniter_web --> igniter_server` — `igweb` is a dev-dep of the server
   (`server/igniter-server/Cargo.toml:22-28`); the normal edge is web→server only.

### The feature-gated isolation that must survive

Verified from crate headers (these are explicit, load-bearing guarantees, not incidental):

- `igniter_frame`: `default = ["machine"]`, `machine = ["dep:igniter_machine"]`, plus a `wasm` feature
  (`cdylib`) that is **independent of machine** — `--no-default-features --features wasm` has **no kernel**.
- `igniter_3d / gui / ui_kit / console`: consume `frame` with `default-features=false` → **zero
  igniter-machine**, WASM-targetable. Actively built per-crate as
  `cargo build --release --target wasm32-unknown-unknown --features wasm` (seen across lab-docs).
- `igniter_server`: `default=[]`, **protocol-only / serde-only**; the `machine` feature is the *only* thing
  that pulls `igniter-machine` + a `tokio` runtime.
- `igniter_machine`: `default=[]`; `tls`/`postgres`/`repl` are opt-in (rustls **pinned `=0.21.12`**,
  tokio-postgres, ratatui/crossterm) — kept off the default path on purpose.
- `igniter_vm`: pins **`libm = "=0.2.16"`** — the exact pin the P4 det-math **T2 third-ISA bit-identity
  evidence is contracted on**. Any resolution that moved it would invalidate that evidence.

## Dependency-boundary risk per crate (server / web / machine / frame / tbackend / compiler)

| crate | isolation that matters | risk under a root workspace |
|---|---|---|
| **compiler** | leaf, pure; fast independent rebuild | low intrinsic risk, but forced into one shared lock with the whole tree |
| **vm/stdlib** | `libm =0.2.16` pin underpins det-math T1/T2 evidence | workspace-wide resolution could perturb the transitive graph; the determinism contract requires this pin frozen |
| **machine** | heavy core (tokio-full, blake3); `default=[]`; tls/postgres/repl opt-in; **dev** back-edge to frame-ui | feature unification can force-enable `frame`’s `machine` feature → near-cycle pressure + `tls`/`postgres`/`repl` accidentally pulled into every build |
| **frame** | the pivot: `default=["machine"]` but consumed `default-features=false`; `wasm` must stay kernel-free | **THE contamination point** — unified features turn `machine` ON for the machine-free + wasm32 crates, which then cannot compile (tokio-full ≠ wasm32) |
| **tbackend** | leaf, `default=[]`, optional `ffi`/magnus (needs Ruby) | unification could pull `magnus` (Ruby headers) into hosts that don’t have them; home-lab builds it natively per-host with `cargo build --release --bin tbackend` **no flags** — a workspace adds nothing |
| **server** | `default=[]` serde-only embeddable lib; **dev** back-edge to web | unification pulls `tokio`+machine into the default server, destroying the "protocol-only machine-free" guarantee |
| **web** | already the aggregator (compiler+machine+server+render_html) | low isolation value; it is *where the weight is concentrated by design* — i.e. a meta-crate already exists for the server lane |
| **ide** (src-tauri) | Tauri’s own build/bundle system, native+wasm matrix | must stay **fully separate** — mixing Tauri bundling into a lib workspace is a known footgun |

## Options compared (as required by the card)

| Option | What it is | Verdict |
|---|---|---|
| **Keep package-local builds** | status quo: per-crate `Cargo.toml`/`.lock`, build with `-p`/per-dir | **Recommended base.** Preserves both dev-dep back-edges and the machine/wasm/server feature isolation; each crate’s exact pins (`libm`, `rustls`) stay frozen. Cost: N build invocations, N locks to maintain. |
| **Root Cargo workspace** | one `[workspace]` + unified lock | **Defer.** Highest risk: (a) workspace **defaults to resolver v1** unless `resolver="2"` is set — v1 unifies dev/build/normal features across *all* members → activates `frame`’s `machine` everywhere, breaking machine-free + wasm32 builds; (b) even with v2, `cargo build/test --workspace` selects all members and re-introduces the contamination; (c) **lockfile churn** (explicitly a closed surface). Buys only "one build command". |
| **Root `xtask`/shell bootstrap (no `[workspace]`)** | a top-level script/`xtask` that runs the existing per-crate `cargo build --release --bin …` and stages outputs | **Recommended for v0 DX.** Gives "one install command" with **zero** change to the resolution graph, locks, or feature isolation. Pure orchestration over the proven per-crate builds. |
| **Meta crate (depends on selected bins/libs)** | one crate depending on frame(machine)+machine-free crates+server | **Not recommended.** A single package that depends on both `frame` (machine) and the machine-free crates **is itself the feature-unification graph** → same contamination as a workspace, minus the multi-bin convenience. Note `igniter_web` already is the server-lane aggregator, so a *second* meta-crate adds little. |
| **External packaging script** | shell/CI that builds + packages | Equivalent to the `xtask`/bootstrap option; fine, and aligns with the home-lab `install-pi5-*-release-bundle.sh` precedent. |
| **Release bundle as the integration unit** | `bin/ + app/ + unit + checks + manifest` (Model B) | **This is the actual integration unit.** Already installed on real hardware (`pi5-lab`, mesh-status P14: runner sha256 + loopback unit + manifest). Cargo is a *build* tool here, not the *integration* boundary. |

## Home-lab no-root precedent (considered explicitly)

`igniter-home-lab/deploy/igniter-stack-deployment-models.md` recommends **Model B: release bundle + systemd**
as the near-term path, and it is **already proven**: the P14 `mesh-status` bundle is installed on `pi5-lab`
(`/home/alex/lab/releases/mesh-status/<ts>`, runner `sha256 8834385f…`, loopback unit, `manifest.txt`,
reproduced via `install-pi5-mesh-status-release-bundle.sh`). TBackend packaging (memory: P1–P9) likewise built
the package-local crate natively per host (`cargo build --release --bin tbackend`, no flags) and wrapped the
binary in tarball/`.deb`. **Both precedents deliberately avoided a root workspace and lost nothing** — the
integration unit was the bundle/package, and per-arch native builds were a feature (architecture-native,
debuggable), not a limitation. This is direct evidence that the v0 distribution ladder does **not** need a
Cargo workspace.

## Recommendation

1. **Keep package-local Cargo for v0.** Do not add a root `[workspace]` before the v0 DX install.
2. **Lower-risk alternative for the "one command" DX:** a top-level `xtask`/shell bootstrap that wraps the
   existing per-crate release builds and assembles a **release bundle** (Model B) as the integration unit.
   This is a future *implementation* card, not part of this readiness packet.
3. Revisit a root workspace only if/when a concrete need appears that the bundle ladder cannot meet (e.g.
   shared `cargo test` across crates in CI), and only behind the migration gate below.

### If a root workspace is ever adopted — exact migration acceptance tests (the gate)

A future migration card must PASS all of these before merge (they target the two back-edges + the isolation):

1. `[workspace]` declares **`resolver = "2"`** (non-negotiable; v1 would unify features and fail).
2. `cargo build -p igniter_3d --no-default-features --features wasm --target wasm32-unknown-unknown` →
   artifact contains **no** `igniter_machine`/`tokio` (`cargo tree -e features -p igniter_3d` shows `frame`
   with `machine` **OFF**).
3. `cargo build -p igniter_console --features wasm --target wasm32-unknown-unknown` links (machine-free).
4. **`cargo build --workspace`** does **not** activate `igniter_frame`’s `machine` feature in the machine-free
   crates — verify via `cargo tree -e features`. *(Most likely to fail; this is the real gate.)*
5. `cargo build -p igniter_server` (default) pulls **no** `tokio`/`igniter_machine` (serde-only preserved).
6. Both dev-dep back-edges (`machine→console`, `server→web`) resolve under `--workspace` with **no cyclic
   dependency error**.
7. Exact pins **unchanged** in the unified lock: `libm 0.2.16` (det-math T1/T2 evidence) and `rustls =0.21.12`
   (offline TLS). No broad transitive bumps.
8. `igniter-ide` (Tauri) stays **out** of the workspace (separate build/bundle).
9. Every existing per-crate test suite passes under the workspace.

## Acceptance — mapping

- [x] Dependency-boundary risks listed for server/web/machine/frame/tbackend/compiler (table above; +ide).
- [x] Recommendation on whether a root workspace is needed before v0 DX install → **No (defer).**
- [x] Lower-risk alternative named → root `xtask`/shell bootstrap + release bundle (Model B) integration unit.
- [x] Exact migration acceptance tests named (the 9-point gate) for the if-recommended branch.
- [x] Home-lab no-root tarball/deb/bundle precedent considered explicitly (Model B, mesh-status P14, tbackend).
- [x] No code changes. `git diff --check` clean.

---

*Lab readiness. 2026-06-24. Verdict: keep package-local Cargo for v0; defer the root workspace. Two deliberate
dev-dependency back-edges (machine⇄frame-ui, server⇄web) and a feature-gated machine/wasm/server isolation are
load-bearing and would be broken by workspace feature unification (which also defaults to the wrong resolver).
The proven integration unit is the no-root release bundle (Model B), not Cargo. A root xtask/shell bootstrap
delivers the "one install command" DX at zero resolution-graph risk. A 9-point migration gate is named for any
future workspace adoption.*
