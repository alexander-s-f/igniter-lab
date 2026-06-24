# LAB-DISTRIBUTION-ROOT-WORKSPACE-READINESS-P5 - evaluate root Cargo workspace vs package-local builds

Status: CLOSED (readiness — recommendation: DEFER root workspace for v0)
Lane: distribution / repo structure
Type: readiness
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

The lab currently uses many package-local Cargo projects with separate `Cargo.lock` files. That kept
frontier work isolated, but distribution/DX pressure now asks for easier multi-binary builds and perhaps
one install command. A root Cargo workspace could help, but it could also churn dependency resolution and
break the useful package-local isolation.

Home-lab TBackend packaging avoided a root workspace by archiving/building the package-local
`runtime/igniter-tbackend` crate natively on target hosts, then wrapping the resulting binary in tarballs
or `.deb` packages. IgWeb release bundles similarly treated runner binary + app dir + checks + unit as a
deployable shape. Evaluate whether that ladder is enough before recommending root workspace churn.

## Goal

Evaluate whether to keep package-local Cargo for v0 distribution or introduce a root Cargo workspace /
aggregator package. This is a readiness decision only.

## Verify First

- List all `Cargo.toml` and `Cargo.lock` files.
- Identify path dependencies and potential cycles.
- Check which packages are intentionally machine-free/server-free/UI-free.
- Check current release-build commands from P3 if available.
- Search docs for prior "no root workspace" or package-local assumptions.
- Read TBackend P3/P4 home-lab manifests and `deploy/igniter-stack-deployment-models.md` for a no-root
  packaging precedent.

## Required Packet

Write:

`lab-docs/lang/lab-distribution-root-workspace-readiness-p5-v0.md`

Compare:

- keep package-local builds;
- root Cargo workspace;
- root `xtask`/shell bootstrap without Cargo workspace;
- meta crate that depends on selected binaries/libraries;
- external packaging script.
- release bundle as the integration unit instead of Cargo workspace as the integration unit.

## Acceptance

- [x] Dependency-boundary risks are listed for server/web/machine/frame/tbackend/compiler.
- [x] Recommendation says whether root workspace is needed before v0 DX install.
- [x] If deferring root workspace, name the lower-risk alternative.
- [x] If recommending root workspace, name the exact migration acceptance tests.
- [x] Home-lab no-root tarball/deb/bundle precedent is considered explicitly.
- [x] No code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

No workspace migration. No lockfile churn. No broad dependency updates. No feature unification. No release
packaging implementation.

## Closing Report

Packet: `lab-docs/lang/lab-distribution-root-workspace-readiness-p5-v0.md`.

**Recommendation: keep package-local Cargo for v0; DEFER the root workspace.** Lower-risk alternative for the
"one install command" DX = a root `xtask`/shell bootstrap (no `[workspace]`) wrapping the existing per-crate
`cargo build --release` and staging a **release bundle (Model B)** as the integration unit.

**Why (verified):** no root `[workspace]` today; 14 product crates + 15 independent `Cargo.lock`. Two
deliberate **dev-dependency back-edges** keep the normal-dep graph acyclic — `igniter_machine --dev-->
console/ui_kit --> frame --(machine feat)--> machine` and `igniter_server --dev--> web --> server`. Combined
with feature-gated isolation (`frame default=["machine"]` consumed `default-features=false`; `server`/`machine`
`default=[]`; `frame` `wasm` kernel-free), a root workspace's **feature unification** would activate `frame`'s
`machine` feature globally and break the machine-free + wasm32 crates — worsened by the workspace footgun of
**defaulting to resolver v1**. Lockfile churn is itself a closed surface. The `libm 0.2.16` pin (P4 det-math
T2 evidence) and `rustls =0.21.12` (offline TLS) must stay frozen.

**Precedent considered:** home-lab `deploy/igniter-stack-deployment-models.md` Model B (release bundle +
systemd) is already installed on `pi5-lab` (mesh-status P14); TBackend P1–P9 built package-local crate
natively per host (`cargo build --release --bin tbackend`, no flags). Both avoided a root workspace and lost
nothing.

**If ever adopted:** 9-point migration gate named (resolver="2"; machine-free + wasm32 builds verified clean
via `cargo tree -e features`; `--workspace` must not turn `frame` machine on; server stays serde-only; both
back-edges resolve without cycle error; `libm`/`rustls` pins unchanged; ide kept separate; all suites pass).

**No code changes; `git diff --check` clean.** Risks listed for compiler/vm/machine/frame/tbackend/server/web/ide.
