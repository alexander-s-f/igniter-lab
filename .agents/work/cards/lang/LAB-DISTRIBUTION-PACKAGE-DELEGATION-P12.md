# LAB-DISTRIBUTION-PACKAGE-DELEGATION-P12 - wire `igniter package ...` to `igc`

Status: CLOSED (2026-06-25) — `igniter package` → `igc` wired; 9 routing smoke tests green
Lane: distribution / package DX
Type: implementation + proof
Date: 2026-06-25
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-DISTRIBUTION-CONTROL-CENTER-READINESS-P6`
- `LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7`

P6 decided that `igniter package ...` is a 1:1 ergonomic alias to the compiler/package authority. The wrapper
must not invent a second resolver, lockfile format, package graph, registry, or trust model.

## Goal

Wire `igniter package` to existing `igc` commands.

Expected shape:

```text
igniter package lock [args...]          -> igc lock [args...]
igniter package verify [args...]        -> igc verify [args...]
igniter package graph [args...]         -> igc package graph [args...]
igniter package pack [args...]          -> igc package pack [args...]
igniter package admit [args...]         -> igc package admit [args...]
igniter package verify-archive [args...]  # only if needed to disambiguate workspace verify vs .igpkg verify
```

The exact naming may be adjusted after reading live `igc --help`, but the final mapping must be explicit.

## Verify First

- Read `lang/igniter-compiler/src/main.rs`.
- Run or inspect `igc --help`, `igc lock --help`, `igc verify --help`, and `igc package --help` if available.
- Confirm installed-prefix behavior: `igniter` should find co-located `igc` first, then repo target.
- Confirm source-checkout behavior: if no co-located `igc`, use repo target or build only if consistent with current wrapper policy.

## Required Behavior

- `igniter package --help` documents exact delegation.
- Supported package subcommands delegate to `igc` preserving argv and exit code.
- `igniter package lock/verify/...` finds co-located staged `igc` when installed by P8.
- No command silently succeeds if `igc` is missing; it must print a useful build/install suggestion.
- Workspace `verify` and archive `package verify` ambiguity is handled explicitly.
- The wrapper must not parse or reinterpret lockfiles/packages; it is argv routing only.

## Acceptance

- [x] At least 4 package subcommands delegate to `igc` and preserve exit code. **6 wired**: `lock`→`igc lock`,
      `verify`→`igc verify` (workspace), `verify-archive`→`igc package verify` (.igpkg), `graph`/`pack`/`admit`
      →`igc package <sub>`. `exec` preserves argv + exit code (proved: stub exits 7 → wrapper exits 7).
- [x] Co-located staged `igc` is preferred in installed-prefix mode (`$SCRIPT_DIR/igc` before repo target;
      test stages a wrapper copy + stub `igc` and asserts the co-located one is used).
- [x] Help output names the owner (`igc`) and warns this is not a second resolver ("ROUTING ONLY … invents NO
      second resolver, lockfile format, package graph, registry, or trust model").
- [x] Missing `igc` fails clearly with build/install suggestion (exit 1; suggests `cargo build --release` +
      `bin/igniter-install` + `IGNITER_IGC_BIN`). No auto-build (a `package` verb must not silently compile).
- [x] Existing package tests are not reimplemented; wrapper smoke tests cover routing only
      (`server/igniter-web/tests/igniter_package_delegation_smoke_tests.rs`, 9 tests — `igc` is a stub).
- [x] `git diff --check` clean.

## Verify / Findings

- Wired in `bin/igniter` only (no compiler/package code touched): `resolve_igc` (override → co-located
  staged → repo-target `igniter_compiler`, **no auto-build**) + `cmd_package`/`package_usage`.
- **Real-binary smoke:** `./bin/igniter package graph` (no stub) reached real `igc` and returned actual
  `igniter_package_graph` JSON (exit 0) — proves the wiring, not just the stub.
- **Disambiguation resolved:** `igc verify` (workspace) vs `igc package verify` (.igpkg archive) → exposed as
  `package verify` vs `package verify-archive`.
- **Integration note:** during parallel work this card briefly observed a red shared doctor smoke from the
  concurrent P10 rewrite. Final curation resolved the combined surface: `igniter_doctor_tests` (6),
  `igniter_package_delegation_smoke_tests` (9), and `igniter_serve_wrapper_smoke_tests` (16) are all green.

## Closed Surfaces

No package-manager rewrite. No registry. No solver. No lockfile format change. No `.igpkg` semantic changes.
No compiler package code changes unless a tiny help-surface bug blocks delegation and is explicitly justified.
