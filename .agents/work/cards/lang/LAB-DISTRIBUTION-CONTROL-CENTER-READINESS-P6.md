# LAB-DISTRIBUTION-CONTROL-CENTER-READINESS-P6 - `igniter` as the long-lived control center

Status: CLOSED (readiness — `igniter` = v0 shell dispatcher front door; unblocks CLI-SKELETON-P7)
Lane: distribution / DX architecture
Type: readiness
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

P1-P5 established the distribution baseline:

- P2 added a repo-local `bin/igniter serve` wrapper over `igweb-serve`.
- P3 proved 5 green release binaries and one blocked binary (`igniter-repl`).
- P4 recommended a repo-local bootstrap installer as the first install channel.
- P5 deferred a root Cargo workspace and kept package-local builds.

The next design risk is tool sprawl. We do not want `igniter-install`, `igweb-serve`, `igc`, package
commands, app bundle scripts, and future updaters to become competing front doors. The durable shape should
be:

```text
igniter serve
igniter check
igniter doctor
igniter toolchain install/update/list
igniter package lock/verify/admit
igniter app bundle
```

`igniter-install` should be bootstrap-only: it installs the first real `igniter` and exits the user's daily
workflow.

## Goal

Decide the v0 command taxonomy and authority boundaries for `igniter` as the control center.

This is a readiness card only. Do not implement commands here.

## Verify First

- Read `bin/igniter` from P2.
- Read P1-P5 distribution packets.
- Inspect existing command owners:
  - `server/igniter-web/src/bin/igweb-serve.rs`
  - `lang/igniter-compiler/src/main.rs`
  - package lock/verify/admit surfaces in the compiler/package code
  - machine/tbackend binaries and help output where relevant.
- Confirm which commands already exist and should be delegated to, not reimplemented.
- Confirm no root workspace exists and no root Cargo migration is required.
- Check whether any command names collide with existing binary names or CLI verbs.

## Required Packet

Write:

`lab-docs/lang/lab-distribution-control-center-readiness-p6-v0.md`

Answer:

1. Which command families belong under `igniter` v0?
2. Which existing binaries remain public vs become implementation details?
3. Is `igniter` v0 a shell dispatcher, Rust CLI, or staged transition?
4. What is the bootstrap-only role of `igniter-install`?
5. How should `igniter package ...` delegate to existing package lock/verify/admit without inventing a second package manager?
6. What should `igniter toolchain ...` mean in v0 vs later?
7. What should `igniter app bundle` own, and what should stay in release-bundle/systemd scripts for now?
8. What commands must be explicitly deferred?

## Acceptance

- [x] Packet names a stable command taxonomy with at least `serve`, `check`, `doctor`, `toolchain`, `package`, and `app`.
- [x] Packet explicitly states `igniter-install` is bootstrap-only, not a long-lived package manager.
- [x] Existing command owners are mapped and delegation boundaries are clear.
- [x] Public vs internal binary story is clear for `igweb-serve`, `igniter_compiler`/`igc`, `igniter-vm`, `igniter-mcp`, `tbackend`.
- [x] At least 5 non-goals/deferred commands are listed.
- [x] Next implementation cards are named.
- [x] No code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

No implementation. No install script. No root workspace. No binary rename. No public release. No upload,
registry, signing, Homebrew, Docker, or production service install.

## Closing Report

Packet: `lab-docs/lang/lab-distribution-control-center-readiness-p6-v0.md`.

**Decision:** `igniter` = the single durable front door, a **v0 shell dispatcher** (extend P2 `bin/igniter`)
that **delegates** and owns **no authority**. Taxonomy: `serve`→igweb-serve (done), `check`→igweb-serve check,
`compile`→igc, `run`→igniter-vm, `package {lock|verify|graph|pack|admit}`→igc 1:1 (no 2nd resolver),
`toolchain {list|install|update}`=local build/stage (v0), `doctor`=new minimal env check, `app bundle`=
reserved/deferred (stays in home-lab release-bundle+systemd scripts).

**Verify-first (live owners):** igc=`compile/lock/verify/package{graph,pack,verify,admit}`;
igniter-vm=`run/compile/trace/bytecode-map`; igweb-serve=`serve/check`; igniter-mcp/tbackend standalone. No
binary named `igniter` (name free). `igniter-repl` build-broken → excluded. No root workspace.

**8 answers:** (1) serve/check/compile/run/package/toolchain/doctor[+app reserved]; (2) `igniter` public front
door, owners stay invocable impl-details, mcp+tbackend stay standalone, no rename; (3) **staged shell→Rust**;
(4) igniter-install bootstrap-only, updates via `toolchain update`; (5) package = 1:1 igc delegation, compiler
keeps lock/STDLIB_VERSION authority; (6) toolchain v0=local, remote/registry deferred; (7) app bundle assembles
{runner+app+checks+manifest} only, host owns systemd/exposure/secrets; (8) ≥5 deferred (app-bundle-impl,
toolchain-remote, Rust-CLI, mcp/daemon verbs, publish/registry, self-update, repl).

**Authority invariant:** a verb joins `igniter` only if a named owner already enforces its authority
(loopback→igweb-serve, package-trust→igc, secrets→host-config, capability→machine). 

**Next cards (already drafted — feeds, doesn't invent):** `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`
(unblocked by closing this P6 — minimal `bin/igniter` skeleton), `LAB-DISTRIBUTION-BOOTSTRAP-INSTALL-P8`
(installer), `LAB-DISTRIBUTION-DOCTOR-READINESS-P9` (doctor design — P6 reserves the verb, defers detail to
P9); + new repl async-fix / later Rust-CLI. **No code; `git diff --check` clean.**

