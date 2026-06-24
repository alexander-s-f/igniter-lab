# LAB-DISTRIBUTION-DOCTOR-READINESS-P9 - define `igniter doctor` diagnostics

Status: CLOSED (readiness — v0 doctor check set + format; impl → LAB-DISTRIBUTION-DOCTOR-IMPL-P10)
Lane: distribution / diagnostics DX
Type: readiness
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

As the ecosystem gains a control-center CLI, users will need a boring answer to "why does this not run?".
`igniter doctor` should become the non-mutating diagnostic surface for local install and app-run problems.

Do not let `doctor` become a magic fixer. It should inspect, explain, and suggest exact next commands.

## Goal

Design the v0 `igniter doctor` checks and output format.

This card is readiness only. It may inform P7 implementation if P7 has not landed yet.

## Verify First

- Read P1-P5 distribution packets.
- Read P6 control-center packet if available.
- Inspect current failure modes:
  - missing `igweb-serve`
  - compiler binary name mismatch (`igniter_compiler` vs `igc`)
  - missing `igniter-lang` sibling at compiler build time
  - public bind refusal
  - inline host-config secret refusal
  - missing Postgres DSN when machine/postgres feature is used
  - excluded/broken `igniter-repl`
- Inspect existing CLI error style in `igweb-serve`, compiler, package lock/verify/admit, and tbackend.

## Required Packet

Write:

`lab-docs/lang/lab-distribution-doctor-readiness-p9-v0.md`

Answer:

1. Which checks belong in `doctor` v0?
2. Which checks must be purely local and non-mutating?
3. Which checks are app-specific and require `igniter doctor <app_dir>` or `igniter app doctor <app_dir>`?
4. What output format should be used: human text only, JSON option, or both?
5. How should severity be represented (`ok`, `warn`, `fail`, `info`)?
6. Which checks are explicitly deferred?
7. What implementation card should add the first `doctor` command?

## Acceptance

- [x] At least 10 candidate doctor checks are classified.
- [x] v0 check set is small, local, and non-mutating.
- [x] App-specific vs toolchain-specific checks are separated.
- [x] Output/severity format is specified.
- [x] Security-sensitive checks avoid printing secrets/DSNs.
- [x] Follow-up implementation card is named.
- [x] No code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

No implementation. No automatic fixes. No network checks by default. No DB connection by default unless
explicitly requested in a later card. No host mutation. No secret printing.

## Closing Report

Packet: `lab-docs/lang/lab-distribution-doctor-readiness-p9-v0.md`.

**Design:** `igniter doctor` = non-mutating local inspector (P7 already ships a minimal seed; this formalizes
+ extends). Two scopes: **`igniter doctor`** (toolchain) and **`igniter doctor <app_dir>`** (toolchain + app
shape). **19 checks classified**, 16 in v0 — A1–A10 toolchain (repo/rustc/cargo, igniter-lang sibling, fleet
presence, igc alias, repl-excluded, resolution source, PATH, manifest) + B12–B18 app (app dir/manifest/entry,
host.toml secret-safety + `dsn_env`, env-var presence, feature expectation). **#14 app-build delegates to
`igniter check`** (doctor points, never recompiles).

**Format:** human text default + `--json` (both). **Severity:** `ok`/`warn`/`fail`/`info`; **v0 exits 0**
(report), `--strict` deferred. **Security:** never prints secrets/DSNs — only offending key NAMES, env-var
NAMES + presence booleans (mirrors `runner_diag` `POSTGRES_CONNECT` redaction). **Deferred:** STDLIB_VERSION
skew, live DB connect, network, signature/registry, auto-fix, systemd/Docker.

**Verify-first:** real diagnostic codes (CONFIG_PARSE/BIND_REFUSED/POSTGRES_CONNECT[redacted]/RUNNER_INTERNAL),
host.toml `*_env` contract (inline secret keys fail-closed), public-bind→CONFIG_PARSE, name mismatch
igniter_compiler↔igc, repl build-broken. **Impl card → `LAB-DISTRIBUTION-DOCTOR-IMPL-P10`** (genuinely-new, to
be drafted): full v0 set + `doctor <app_dir>` + `--json`, shell in v0. **No code; `git diff --check` clean.**

