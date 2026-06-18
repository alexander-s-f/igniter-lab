# LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1 — package and package-manager research

Status: OPEN  
Lane: standard / research-readiness  
Opened: 2026-06-18  
Delegate label: GEMINI-IGNITER-PACKAGES-OVERNIGHT-A  
Skill: idd-agent-protocol  

## Why This Card

Igniter is beginning to grow several authoring/projection/runtime surfaces:

```text
.ig canonical contracts
.igweb Projection Dialect
.igv ViewArtifact dialect
stdlib modules
server apps
machine/service recipes
future assets/plugins/extensions
```

Before implementing an Igniter package manager, we need a careful comparative research packet.
The goal is **not** to copy Cargo/npm/Bundler/etc., but to understand what mistakes to avoid and
what shape fits Igniter's philosophy:

```text
contracts first
deterministic artifacts
authority explicit
source/projection separation
host executes, app/domain owns meaning
lab evidence before canon
```

This card is intended as an overnight/background research task, suitable for a broad Gemini swarm.

## Authority

Research/readiness only. No code. No new package format. No registry. No CLI. No dependency resolver
implementation. No canon claim.

Allowed:
- Read current Igniter lab/canon surfaces.
- Research other ecosystems from official docs / primary sources where possible.
- Produce a compact comparative packet with a table.
- Recommend one or two Igniter-shaped directions for later cards.
- Add closing report to this card.

Not allowed:
- No implementation.
- No edits to compiler/server/web/machine crates.
- No creating a real registry.
- No inventing a final package spec.
- No treating popularity in other ecosystems as authority for Igniter.
- No vendor/live/network credentials.
- No package publishing.

## Verify First — Igniter Surfaces

Read current live surfaces before comparing:

- `igniter-compiler/src/project.rs` (project roots/import resolution)
- `igniter-compiler/src/igweb.rs` (`.igweb` Projection Dialect)
- `igniter-web/src/lib.rs` (builder/package seam)
- `igniter-server/src/protocol.rs` and `src/host.rs` (server/app boundary)
- `igniter-machine/IMPLEMENTED_SURFACE.md` (machine/service/effect surfaces)
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `lab-docs/lang/lab-igniter-web-packaging-p6-v0.md`
- `lab-docs/lang/lab-igniter-web-runner-dx-readiness-p11-v0.md` if it exists by then

Live code wins over cards. If P11 is still open, treat it as a concurrent input, not authority.

## External Ecosystems To Compare

Use official docs or stable primary references where possible. At minimum compare:

1. **Cargo / crates.io**
   - `Cargo.toml`, lockfile, features, workspace, semver, registry, source replacement.
2. **npm / pnpm / yarn**
   - package.json, lockfiles, scripts, transitive dependency risk, postinstall risk.
3. **RubyGems / Bundler**
   - gemspec, Gemfile, Gemfile.lock, groups, executables, engines/plugins.
4. **Go modules**
   - module path identity, minimal version selection, sumdb, replace directives.
5. **Python packaging**
   - pyproject.toml, wheels, virtualenv friction, indexes, extras.
6. **Deno / JSR**
   - URL/module imports, modern registry shape, permissions model.
7. **OCI artifacts / containers**
   - content-addressed blobs, tags vs digests, provenance/signing.
8. **WASM component model / WIT** (if time)
   - interface-first packages, capability boundaries, portable components.
9. **Terraform providers/modules** (if time)
   - declarative package use, provider authority, lockfiles.
10. **Rails engines/plugins** (if time)
   - app extension without app ownership, migration/assets pitfalls.

Do not drown in details. The deliverable is a decision aid, not a textbook.

## Research Questions

Answer all:

1. **What is a package in Igniter?** Is it source `.ig`, compiled artifact `.igapp`,
   projection dialect source, generated output, stdlib module, server app, machine recipe,
   assets, or a bundle of several?
2. **What is dependency identity?** Name/version? content digest? module path? package id?
   How should content-addressing and human-readable names coexist?
3. **What is the unit of trust?** Source package, generated artifact, compiled artifact,
   signed recipe, registry entry, or lockfile?
4. **What is the unit of execution?** `.ig` contract, app entry, service recipe, server app,
   machine pool, effect bridge?
5. **How should projection dialects participate?** `.igweb`/`.igv` are not runtime authority.
   Should packages include authored source, generated artifacts, or both?
6. **How should lockfiles work?** What must be pinned: package version, content digest,
   compiler version, stdlib version, dialect lowerer version, generated artifact hash?
7. **How should imports resolve?** How do package modules map to `import Foo.Bar` without
   creating path ambiguity or hidden global namespace coupling?
8. **How should packages avoid npm-style script risk?** Are install/build hooks allowed?
   If yes, under what explicit authority? If no, how are generated artifacts produced?
9. **How should package features/options work?** Cargo-style features are powerful but
   can explode complexity. Does Igniter need features at all in v0?
10. **How should host capabilities be declared?** Packages may need Postgres/SparkCRM/http,
    but should not smuggle credentials or authority.
11. **How should app/domain packages differ from stdlib/canon packages?** Lab vs canon,
    private app-local vs public package, dialect package vs runtime package.
12. **What should the smallest v0 be?** Name the first implementation slice, but do not
    implement it.

## Required Comparative Table

Include a table with at least these columns:

```text
Ecosystem | Package identity | Locking | Build hooks | Namespace/imports |
Trust/provenance | Strengths | Failure modes | Igniter lesson
```

Keep each row concise.

## Igniter-Specific Design Criteria

The recommendation must explicitly score candidate package models against:

- deterministic build/rebuild;
- inspectable generated artifacts;
- content-addressed evidence;
- source vs generated vs compiled separation;
- no implicit authority escalation;
- host capability declarations without secrets;
- app/domain ownership stays local;
- projection dialects remain projections;
- lockfile enough for reproducibility;
- future registry possible, but not required for local v0;
- simple enough for a solo developer.

## Candidate Igniter Shapes To Evaluate

Evaluate these candidate v0 directions:

### A. Source package only

Package = authored `.ig` / `.igweb` / `.igv` files + metadata.

### B. Compiled artifact package

Package = `.igapp` / compiled machine artifact + metadata + source hash.

### C. Dual package

Package = authored source + generated artifacts + compiled artifacts + lock/provenance.

### D. App-local workspace package

Package manager starts as a local workspace resolver, no public registry.

### E. Registry-backed package manager

Public/private registry from day one.

### F. OCI/content-addressed artifact store

Packages as blobs addressed by digest, names/tags as convenience.

## Desired Bias

Prefer a v0 that is:

- local-first;
- content-addressed;
- lockfile-backed;
- no install scripts by default;
- explicit about generated artifacts;
- compatible with `igniter web build` / `igniter-server serve`;
- does not require a public registry;
- does not require users to know Rust;
- can later grow signing/provenance without changing the package identity model.

## Deliverables

- `lab-docs/lang/lab-igniter-package-manager-readiness-p1-v0.md`
- Closing report in this card.
- Optional route recommendation for the next implementation card.

## Acceptance

1. Packet is research/readiness only; no code changes.
2. Packet includes the required comparative table.
3. Packet names at least 5 concrete failure modes from other ecosystems to avoid.
4. Packet distinguishes source, generated, compiled, and deployed artifacts.
5. Packet defines candidate package identity models for Igniter.
6. Packet proposes a lockfile/provenance direction.
7. Packet explains how projection dialects should participate.
8. Packet explains how capabilities/secrets must not be smuggled through packages.
9. Packet recommends one smallest v0 implementation slice.
10. Packet clearly says what is deferred.

## Closing Report Template

Report:

- sources/ecosystems reviewed;
- comparative table location;
- recommended v0 package model;
- top 5 anti-patterns to avoid;
- how this fits Igniter philosophy;
- next card name + acceptance sketch.

