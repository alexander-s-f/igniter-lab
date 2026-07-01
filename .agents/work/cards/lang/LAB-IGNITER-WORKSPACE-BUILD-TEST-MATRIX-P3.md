# LAB-IGNITER-WORKSPACE-BUILD-TEST-MATRIX-P3 — `igniter workspace build/test` bounded core checks

Status: OPEN
Lane: distribution / command center / workspace Dev lane
Type: implementation
Delegation code: OPUS-IGNITER-WORKSPACE-BUILD-TEST-MATRIX-P3
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P1 decided that `igniter` should become the command center. P2 adds read-only workspace status/doctor.

This card adds the next Dev-lane slice: a bounded build/test matrix for core contributors.

The goal is **not** full CI, not release validation, and not a root Cargo workspace. The goal is a memorable
front door for the checks we already know matter:

```text
igniter workspace build
igniter workspace test
```

The command should encode the current core graph without making developers remember paths.

## Dependency

Prefer running after `LAB-IGNITER-WORKSPACE-STATUS-DOCTOR-P2`, because this card should reuse the workspace
layout checks and diagnostic language. If P2 is not landed yet, stop and either implement P2 first or narrow
this card to a readiness packet.

## Verify first

Read:

- `bin/igniter` after P2
- `lab-docs/lang/lab-igniter-command-center-autonomy-readiness-p1-v0.md`
- the latest mirror-check proof from P2/P3 flatten wave
- current `Cargo.toml` files for:
  - `igniter-stdlib`
  - `igniter-compiler`
  - `igniter-vm`
  - `igniter-tbackend`
  - `igniter-machine`

Confirm the current bounded matrix live. Do not assume stale test counts.

## Goal

Implement:

```text
igniter workspace build [--json]
igniter workspace test [--json] [--quick]
```

Recommended v0 matrix:

### Build

Run `cargo build` or `cargo test --no-run` for each core crate package-locally:

- `igniter-stdlib`
- `igniter-compiler`
- `igniter-vm`
- `igniter-tbackend`
- `igniter-machine`

Use the crate-local `Cargo.toml`; do not create a root workspace.

### Test

Run a bounded matrix with sensible defaults:

- stdlib tests;
- compiler tests;
- vm tests;
- tbackend tests if not too heavy;
- machine pure-core lane:
  `cargo test --manifest-path igniter-machine/Cargo.toml --no-default-features --no-fail-fast`

If the full matrix is too slow/noisy, define:

- `workspace test --quick`: metadata + key smoke targets;
- `workspace test`: the bounded core matrix.

But do not silently skip machine pure-core checks: that is the proof that mirror/core autonomy works.

## Output contract

Human output should show:

```text
workspace build:
  igniter-stdlib     ok
  igniter-compiler   ok
  ...
```

JSON should use a simple result object or the existing diagnostic record shape. If this card finds the current
doctor schema is insufficient for command duration/exit code, document that as pressure for P4 and keep v0
minimal.

At minimum each item needs:

- `scope`: `workspace`
- `check`: e.g. `build igniter-vm`
- `severity`: `ok` / `fail`
- `detail`: command summary
- `suggest`: next action

## Known caveat

If a test is known-flaky, do not hide it. Report it explicitly in the closing report with exact test name,
rerun evidence, and recommended follow-up. Do not mark a failing suite green by default.

## Design constraints

- No root Cargo workspace.
- No `Cargo.toml` rewrites.
- No mirror push/fetch/pull.
- No network except ordinary Cargo dependency resolution already required by local builds.
- No registry/semver policy.
- Do not broaden into release packaging.
- Do not mutate source files.

## Tests / verification

At minimum run:

```text
bin/igniter workspace build --json
bin/igniter workspace test --quick --json
bin/igniter workspace test --quick
git diff --check
```

If runtime is acceptable, run full:

```text
bin/igniter workspace test
```

Also verify a fresh mirror/sibling checkout if this card changes matrix semantics.

## Acceptance

- [ ] `igniter workspace build` exists and runs core crate build checks.
- [ ] `igniter workspace test` exists and runs a bounded core matrix.
- [ ] `--quick` exists if full matrix is too slow for default development loops.
- [ ] `--json` exists and is machine-readable.
- [ ] Missing `igniter-lang` sibling fails clearly before compiler/machine checks.
- [ ] Machine pure-core lane is included or explicitly justified if gated.
- [ ] Known flake handling is explicit, not swept under the rug.
- [ ] No root workspace created.
- [ ] No `Cargo.toml` rewrites.
- [ ] `git diff --check` clean.

## Closing report

Fill when complete.
