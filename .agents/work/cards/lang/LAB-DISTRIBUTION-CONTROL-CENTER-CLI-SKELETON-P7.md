# LAB-DISTRIBUTION-CONTROL-CENTER-CLI-SKELETON-P7 - implement the minimal `igniter` command skeleton

Status: CLOSED (2026-06-24) — bin/igniter v0 control center; 9 wrapper tests green; packet at lab-docs/lang/lab-distribution-control-center-cli-skeleton-p7-v0.md
Lane: distribution / DX implementation
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Depends on `LAB-DISTRIBUTION-CONTROL-CENTER-READINESS-P6`.

P2 proved `bin/igniter serve <app_dir>` as a thin wrapper over `igweb-serve`. P6 should decide the stable
control-center taxonomy. This card turns that taxonomy into a minimal, safe command skeleton without moving
authority or reimplementing lower-level CLIs.

The point is not to make every command fully functional. The point is to give users one coherent front door
with honest delegation and fail-closed placeholders.

## Goal

Update `bin/igniter` so it is recognizably the v0 control center:

```text
igniter serve <app_dir> ...
igniter check <app_dir>
igniter doctor
igniter toolchain list
igniter package --help
igniter app --help
```

Keep `serve` behavior byte/behavior-compatible with P2. Do not hide new authority behind the wrapper.

## Verify First

- Read P6 packet. If P6 is not CLOSED, stop and report that this card is blocked.
- Read current `bin/igniter`.
- Run existing P2 wrapper tests before editing if cheap.
- Inspect `igweb-serve check` semantics to decide whether `igniter check <app_dir>` is an alias to `serve --check`
  or a broader future family.
- Inspect package CLI help to avoid lying about existing package verbs.

## Required Behavior

- `igniter serve <app_dir> ...` keeps the exact P2 safety semantics:
  loopback-only, request-bounded, explicit `--host-config`, public bind refused by `igweb-serve`.
- `igniter check <app_dir>` delegates to `igweb-serve check <app_dir>` and opens no socket.
- `igniter doctor` performs only local, non-mutating checks in v0:
  reports presence/absence of known binaries, repo root, `igniter-lang` sibling, and selected versions if cheap.
- `igniter toolchain list` reports the known v0 tool set and whether each binary is present in the current prefix/repo target.
- `igniter toolchain install/update`, `igniter package ...`, and `igniter app bundle` may be help-only or explicit
  "not implemented yet" placeholders, but must point to the intended next card and must not silently succeed.
- Unknown commands fail with useful help and non-zero exit.

## Acceptance

- [x] `igniter serve` wrapper smoke remains green.
- [x] `igniter check <todo_app>` succeeds and opens no socket.
- [x] `igniter doctor` runs without network, DB, or mutation and prints actionable local status.
- [x] `igniter toolchain list` names the 5 green P3 binaries and excludes or marks `igniter-repl` as unavailable.
- [x] Unimplemented commands fail clearly and non-zero, instead of pretending success.
- [x] Help output shows the command family decided by P6.
- [x] No root workspace migration and no new binary build graph.
- [x] `git diff --check` clean.

## Suggested Tests

Add or extend wrapper tests under:

`server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`

Test through `bin/igniter`, not by calling functions directly.

## Closed Surfaces

No installer implementation. No package-manager implementation. No update/download. No registry. No binary
rename unless P6 explicitly allows a wrapper-level alias. No systemd/Docker/Homebrew.

## Closing Report

Proof doc: `lab-docs/lang/lab-distribution-control-center-cli-skeleton-p7-v0.md`. Gate: P6 CLOSED.

**Implemented** in `bin/igniter` (one file edited; no crate source touched): `serve` (P2-compatible),
`check <app>` (→ igweb-serve check, no socket), `doctor` (local non-mutating report: repo / rustc-cargo /
igniter-lang sibling / 5-binary fleet, exit 0), `toolchain list` (names fleet, marks `igniter-repl`
`[blocked]`). **Fail-closed placeholders (exit 3, point to owner/card):** `toolchain install|update` → P8,
`package …` → igc, `app …` → release-bundle/systemd; `--help` for each exits 0. Unknown → family help, exit 2.
Split `serve --help` (P2 contract strings) from top-level `--help` (P6 family). bash 3.2-safe; no
shell-hidden semantics; **no authority moved** (loopback/public-bind/bound/package-trust/host-config stay in
owners). No new binary build graph.

**Proof:** `cargo test --test igniter_serve_wrapper_smoke_tests` → **9 passed** (4 P2 + 5 new: check / doctor
/ toolchain-list / placeholders-fail-closed / family-help+unknown). Regression `runner_tests` 17 +
`example_app_tests` 7 green. Manual: doctor/list exit 0, placeholders exit 3, public-bind refused.
`git diff --check` clean.

**Follow-ons:** P8 (make toolchain install/update real), P9 (doctor checks), first-class `igniter package`→igc
delegation, igniter-repl async-fix, later Rust `igniter` crate.

