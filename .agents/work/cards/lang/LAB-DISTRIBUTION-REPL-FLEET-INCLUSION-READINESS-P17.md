# LAB-DISTRIBUTION-REPL-FLEET-INCLUSION-READINESS-P17 - decide what `igniter-repl` is in distribution

Status: CLOSED (2026-06-25) — recommends B (opt-in, excluded from v0 fleet) with a headless-smoke gate to inclusion; packet at lab-docs/lang/lab-distribution-repl-fleet-inclusion-readiness-p17-v0.md
Lane: distribution / toolchain
Type: readiness / decision packet
Date: 2026-06-25

## Context

`LAB-MACHINE-REPL-ASYNC-RESUME-FIX-P1` recovered the release build:

```text
cargo build --release --bin igniter-repl --features repl
```

The control center was relabeled from "build-broken" to:

```text
excluded from v0 fleet (release build recovered; inclusion pending)
```

This card decides the next distribution status. Do not assume build success means fleet inclusion.

## Goal

Produce a readiness packet that recommends exactly one of:

- **A. include `igniter-repl` in the v0 toolchain fleet**;
- **B. keep it buildable but opt-in / excluded from fleet**;
- **C. split it into a separate dev-tools profile**;
- **D. defer distribution until a non-interactive REPL smoke exists**.

The answer must be grounded in live code, not stale P3/P8 docs.

## Verify First

- Run or inspect latest proof for:
  - `cargo build --release --bin igniter-repl --features repl`
  - startup smoke (`--resume /nonexistent.igm` or equivalent)
  - `cargo tree -e normal --no-default-features`
  - `cargo tree -e normal --features repl`
- Read:
  - `runtime/igniter-machine/src/bin/repl.rs`
  - `runtime/igniter-machine/Cargo.toml`
  - `bin/igniter`
  - `bin/igniter-install`
  - `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`
- Search old docs for stale `build-broken` claims and distinguish docs-hygiene from fleet policy.

## Questions

1. Is `igniter-repl` a user-facing shipped tool, a developer-only diagnostic, or an experimental lab binary?
2. What minimum smoke is enough for inclusion given it is interactive TUI?
3. Should `bin/igniter-install` build it by default, under a flag, or never?
4. Should `igniter toolchain list` show it as `[present]`, `[optional]`, `[excluded]`, or another state?
5. Does including `ratatui`/`crossterm` in an opt-in feature change any default dependency boundary?
6. What exact follow-up implementation card should be opened?

## Acceptance

- [x] Packet cites live build/tree/smoke evidence (re-run 2026-06-25: build Finished; smoke exit 1; tree default 0, repl 3; Cargo `default=[]`/`required-features=["repl"]`).
- [x] At least 4 alternatives compared (A include / B opt-in-excluded / C dev-tools profile / D defer-until-smoke).
- [x] One recommendation selected with a clear gate (**B now**; D's headless-smoke is the explicit gate to A; two-card promotion path).
- [x] Inclusion path's installer/wrapper/test changes specified (follow-ups #2 headless-smoke + #3 installer `--with-repl` + `[optional]→[present]`).
- [x] Exclusion wording for `doctor` / `toolchain list` specified (`[optional]` strings in the packet).
- [x] Stale-doc cleanup separated from policy: the `build-broken (P3)` text in `bin/igniter-install` (4 places) + the residual `[blocked]` label are **docs-hygiene**, not policy; policy (5-binary fleet) is unchanged and correct.
- [x] No code changes (readiness packet only; `git diff --check` clean).

## Closing report

Recommended **B** — keep `igniter-repl` buildable under `--features repl`, **excluded from the default v0
fleet and installer**, because: (1) it is an interactive TUI with **no hermetic functional smoke** (unlike
the 5 fleet tools), and (2) build-green ≠ ship-ready. Crucially, opt-in REPL changes **no default dependency
boundary** — `cargo tree` proves `ratatui`/`crossterm` appear only with `--features repl`, and the binary is
`required-features`-gated. Promotion to **A** (fleet inclusion) is gated on a non-interactive REPL smoke
(`LAB-DISTRIBUTION-REPL-HEADLESS-SMOKE-P*`) plus an installer opt-in (`LAB-DISTRIBUTION-REPL-INSTALLER-OPTIN-P*`);
a small docs-hygiene card (`LAB-DISTRIBUTION-REPL-LABEL-HYGIENE-P*`) should first relabel the stale
"build-broken"/`[blocked]` wording to `[optional]` (and flip the wrapper test assertion). No fleet promotion
here.

## Closed Surfaces

No installer change. No wrapper change. No REPL feature work. No TUI refactor. No new runtime dependency in
default builds. No promotion into fleet without an explicit implementation card.

