# LAB-IGNITER-MIRROR-CRATE-LINKING-READINESS-P1 — sibling checkout linking policy for core mirrors

Status: CLOSED
Lane: distribution / repository split / core DX
Type: readiness / design
Delegation code: OPUS-IGNITER-MIRROR-CRATE-LINKING-READINESS-P1
Date: 2026-06-30
Skill: idd-agent-protocol

## Context

We started publishing team-facing mirrors for core Igniter crates that still live
inside `igniter-lab`:

- `runtime/igniter-tbackend` -> `Igniter/igniter-tbackend`
- `runtime/acts-as-tbackend` -> `afokin/acts-as-tbackend`
- `lang/igniter-compiler` -> `Igniter/igniter-compiler`
- `lang/igniter-stdlib` -> `Igniter/igniter-stdlib`
- `lang/igniter-vm` -> `Igniter/igniter-vm`
- `runtime/igniter-machine` -> `Igniter/igniter-machine`

The mirror repos make reading, review, onboarding, and team navigation much
nicer. But publishing subtrees is not the same thing as solving crate linking.
Some mirror roots still contain monorepo-relative `path` dependencies.

Current live facts to verify first:

- `igniter_stdlib` is mostly standalone.
- `igniter_compiler` is mostly standalone.
- `igniter_vm` depends on `../igniter-stdlib`.
- `igniter_machine` depends on:
  - `../../lang/igniter-compiler`
  - `../../lang/igniter-vm`
  - `../igniter-tbackend`
  - dev-deps under `../../frame-ui/...`

The desired v0 posture is **not** "turn every mirror into a fully independent
published package immediately". The desired v0 posture is:

```text
one flat sibling checkout plane for core repos

~/dev/igniter-core/
  igniter-stdlib/
  igniter-compiler/
  igniter-vm/
  igniter-machine/
  igniter-tbackend/
  acts-as-tbackend/
```

Core mirrors should be easy to clone, inspect, and work on in one plane. Lab,
experiments, demos, public science, home-lab, and product-specific apps remain
derivative layers, not part of the core sibling plane.

## Goal

Design the first linking policy for mirrored Igniter crates:

1. Separate **source mirror**, **standalone crate repo**, and **release package**
   statuses.
2. Choose sibling-checkout layout as v0 for core crates.
3. Define how path dependencies should resolve in that layout without forcing
   git dependencies, registry, semver, or `[patch]` complexity too early.
4. Name the first implementation card for a helper/bootstrap command that lets
   a developer clone/update/check the core mirror plane.

This is a readiness card. Do not implement the helper yet.

## Verify first

Read live files, not stale docs:

- `lang/igniter-stdlib/Cargo.toml`
- `lang/igniter-compiler/Cargo.toml`
- `lang/igniter-vm/Cargo.toml`
- `runtime/igniter-machine/Cargo.toml`
- `runtime/igniter-tbackend/Cargo.toml`
- `runtime/acts-as-tbackend/*`
- mirror helpers under `bin/push-*-mirror`
- root and package READMEs where they mention mirror / lab-only / preview status

Also verify current mirror remotes with `git remote -v` and `git ls-remote`
where useful. Live repo state wins over this card.

## Questions to answer

1. Which mirrors are already standalone-buildable after clone?
2. Which mirrors require sibling checkouts to build?
3. What exact flat directory layout should be canonical for core development?
4. Should the canonical root be named `igniter-core`, `igniter-dev`, or another
   neutral name?
5. Should mirror `Cargo.toml` files remain sibling-relative, or should we
   introduce generated/local override files?
6. What is explicitly **not** v0?
   - crates.io
   - internal Cargo registry
   - semver solver
   - git dependencies pinned to moving branches
   - publishing binary release packages
7. How do we keep local development pleasant?
   - editing stdlib and immediately testing VM;
   - editing compiler and immediately testing machine;
   - avoiding remote-commit dependency churn.
8. What helper should exist first?
   - clone missing core repos;
   - verify sibling layout;
   - run leaf checks;
   - run selected dependent checks;
   - show status/remotes/heads.
9. What should each mirror README say so team members do not mistake source
   mirrors for independent release packages?
10. What later layer converts this to release packaging?

## Design constraints

- Keep `igniter-lab` as source-of-truth workspace for now.
- Keep mirrors as team-facing source mirrors unless explicitly promoted.
- Keep core repos in one flat sibling plane.
- Do not introduce registry/semver/git-dep policy in this card.
- Do not rewrite `Cargo.toml` files in this card.
- Do not break existing monorepo builds.
- Do not blur core with lab/experiments/product-specific work.
- No production/deploy claims.

## Expected recommendation shape

Prefer an explicit tier table:

| Tier | Meaning | Examples | Build expectation |
| --- | --- | --- | --- |
| Source mirror | Team-facing code mirror of subtree | current repos | may require sibling layout |
| Sibling-buildable core repo | Builds inside flat core checkout | vm + stdlib | `cargo test` works if siblings exist |
| Standalone crate repo | Builds alone after clone | stdlib/compiler candidates | no sibling requirement |
| Release package | Versioned artifact/binary/package | future | governed release process |

Then define a v0 sibling layout, likely:

```text
~/dev/projects/igniter-core/
  igniter-stdlib/
  igniter-compiler/
  igniter-vm/
  igniter-machine/
  igniter-tbackend/
  acts-as-tbackend/
```

If a different root name is better, justify it.

## Acceptance

- [x] Packet written under `lab-docs/lang/`.
- [x] Packet verifies current `Cargo.toml` dependency topology.
- [x] Packet classifies every current mirror as source-mirror /
      sibling-buildable / standalone-buildable.
- [x] Packet recommends sibling-checkout v0 and explains why it beats immediate
      git deps or registry.
- [x] Packet defines the canonical flat core layout.
- [x] Packet states what remains outside core: lab, experiments, emergence,
      home-lab, product apps, demos.
- [x] Packet names exact first implementation card for helper/bootstrap.
- [x] Packet includes README wording recommendations for mirrors.
- [x] No code changes.
- [x] No `Cargo.toml` rewrites.
- [x] No registry/semver/release-package claim.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-30 · Packet: `lab-docs/lang/lab-igniter-mirror-crate-linking-readiness-p1-v0.md`

**Verified topology (live).** stdlib + compiler + tbackend are leaves (crates.io deps only) →
**standalone**. vm adds `../igniter-stdlib` → **sibling-buildable**. machine adds
`../../lang/igniter-compiler`, `../../lang/igniter-vm`, `../igniter-tbackend` + frame-ui **dev**-deps
`../../frame-ui/{igniter-console,igniter-ui-kit}` → **mixed**. `acts-as-tbackend` is a **Ruby gem**
(no `Cargo.toml`; sibling refs already flat). Mirror push helpers use `git subtree split` → paths are
copied **verbatim** (no rewrite).

**Central finding.** A subtree-mirror path dep resolves in a flat `igniter-core/` plane **iff** it is a
same-parent sibling in the monorepo (`../<crate>`): vm→stdlib and machine→tbackend work natively;
machine's cross-dir (`../../lang/*`) and cross-layer dev (`../../frame-ui/*`) edges break. **Proven by
isolated probe:** a `.cargo/config.toml` `paths` override does **not** rescue a path dep whose declared
directory is absent (cargo loads the declared path first and errors) — so machine cannot be made
flat-buildable by an override file; it needs path materialization/normalization + dev-dep reconciliation.

**Recommendation.** Adopt the flat **`igniter-core/`** sibling plane (native for 4 of 6 crates + vm's
edge); keep mirror `Cargo.toml` verbatim; resolve machine via a generated/deterministic P2 link step
(symlink-shim or generated overlay), and reconcile its frame-ui dev-deps in P3. Not v0: registry, semver,
git-deps, `[patch]`, release packages.

**Next cards named:** `LAB-IGNITER-MIRROR-CORE-CHECKOUT-HELPER-P2` (clone/verify plane, link machine,
bounded check matrix) and `LAB-IGNITER-MIRROR-MACHINE-DEVDEP-RECONCILE-P3` (feature-gate/relocate the
frame-ui E2E dev-dep). README wording recommended for the four mirrors lacking a mirror/preview banner.

**Addendum (packet §12, by request): Variant A — flatten core to root.** Measured the alternative of
moving the five core crates to the monorepo root so every core→core path dep becomes `../<crate>`
(flat-safe in both monorepo and mirror plane), keeping the monorepo + subtree-mirroring intact. Cost:
**11 path-dep lines / 5 `Cargo.toml` + 5 `git mv` + 5 push-helper prefix edits**, pure relocation. This
eliminates the P2 link machinery (helper collapses to clone+check) but its blast radius is graph-wide, so
it is a deliberate one-time migration in its own card **`LAB-IGNITER-MONOREPO-FLATTEN-CORE-P2`** (supersedes
the checkout-helper P2 link scope) with full graph rebuild/test. P3 (frame-ui dev-dep) stands either way.

**Scope honored:** no code, no `Cargo.toml` rewrites, no registry/semver/release claim; `git diff --check`
clean.

## Suggested output

`lab-docs/lang/lab-igniter-mirror-crate-linking-readiness-p1-v0.md`

## Likely next card

`LAB-IGNITER-MIRROR-CORE-CHECKOUT-HELPER-P2` — implement a small helper that
creates/verifies the flat sibling checkout plane, clones missing core mirrors,
prints remotes/heads, and runs a bounded check matrix without changing
dependency policy.
