# LAB-DISTRIBUTION-REPL-LABEL-HYGIENE-P19 - relabel `igniter-repl` as optional, not broken

Status: CLOSED (2026-06-25) — repl relabeled [blocked]/build-broken → [optional] across wrapper/installer/tests/front-door; fleet unchanged (5); all green
Lane: distribution / hygiene
Type: implementation + proof
Date: 2026-06-25

## Context

`LAB-MACHINE-REPL-ASYNC-RESUME-FIX-P1` recovered the release build:

```text
cargo build --release --bin igniter-repl --features repl
```

`LAB-DISTRIBUTION-REPL-FLEET-INCLUSION-READINESS-P17` decided the policy:

```text
igniter-repl is buildable and opt-in, but NOT in the default v0 fleet.
```

The remaining problem is **label hygiene**, not fleet policy. Some live wrapper / installer text still says
`build-broken` or uses `[blocked]`, which now reads as a false current failure. Replace that wording with
`optional` while preserving the 5-binary default fleet.

## Goal

Make user-facing distribution labels match current truth:

- `igniter-repl` release build is recovered;
- `igniter-repl` remains excluded from the default v0 fleet;
- it is optional / opt-in pending headless smoke + installer opt-in.

## Verify First

- Read:
  - `bin/igniter`
  - `bin/igniter-install`
  - `server/igniter-web/tests/igniter_serve_wrapper_smoke_tests.rs`
  - `lab-docs/lang/lab-distribution-repl-fleet-inclusion-readiness-p17-v0.md`
  - `lab-docs/lang/lab-distribution-implemented-surface-v0.md`
- Search live files for:
  - `build-broken`
  - `build fails`
  - `[blocked] igniter-repl`
  - `async resume`
- Confirm the default installer fleet is still exactly 5 binaries before and after.

## Required Behavior

Update wording only:

- In `bin/igniter`:
  - `toolchain list` should show repl as `[optional]`, not `[blocked]`.
  - Header should say `v0 fleet (5 default binaries; igniter-repl optional, opt-in)` or equivalent.
  - `doctor` should keep severity `info` and say release build recovered / opt-in / not in default fleet.
- In `bin/igniter-install`:
  - usage, manifest `excluded.reason`, and final summary must not say `build-broken`.
  - use wording like `optional; release build recovered; not in default v0 fleet pending headless smoke`.
- Update tests that assert old `[blocked]` or `build-broken` text.
- Update the implemented-surface doc only if the exact wording changes materially.

Do **not** add `igniter-repl` to `FLEET`. Do **not** build it in `igniter-install`.

## Acceptance

- [x] `grep -rnE "build-broken|build fails|async resume|\[blocked\] igniter-repl"` over bin/igniter, bin/igniter-install, server/igniter-web/tests, and the implemented-surface doc → **no hits** (rephrased two meta-mentions so even the literal scan is clean).
- [x] `igniter toolchain list` prints `[optional] igniter-repl …` and lists 5 default fleet binaries (header now "5 default binaries; igniter-repl optional, opt-in").
- [x] `igniter doctor` reports `igniter-repl` as `[info]` / optional, not fail.
- [x] `bin/igniter-install --help` says repl is optional (not in default fleet), not broken.
- [x] Installer manifest now emits `"fleet_count": 5` and keeps `excluded[].name=igniter-repl` with a non-broken reason; `FLEET` rows unchanged (5) — repl is NOT staged.
- [x] Wrapper test `igniter_toolchain_list_names_fleet_and_marks_repl` updated (asserts `[optional]`, asserts NOT `[blocked]`) and green — wrapper suite 16/16.
- [x] Doctor tests green (6/6).
- [x] `bash -n bin/igniter bin/igniter-install` → both OK.
- [x] `git diff --check` clean.

## Closing report

Wording-only relabel of `igniter-repl` from "build-broken"/`[blocked]` to **optional/opt-in** across the four
user-facing surfaces — `bin/igniter` (doctor doc_emit, toolchain_report label, toolchain-list header, two
usage strings), `bin/igniter-install` (header comment, usage, manifest `excluded[].reason`, final summary;
plus a new `fleet_count: 5`), the wrapper test assertion, and the implemented-surface front door. **No fleet
change:** the installer `FLEET` is still exactly 5 binaries and repl is never built/staged; `default = []` /
`required-features = ["repl"]` untouched. Verified live: `toolchain list` → `[optional]` + 5 `[present]`;
`doctor` → `[info] … optional`; `install --help` → optional. Closed surfaces respected (no inclusion, no
`--with-repl`, no headless mode, no TUI/dependency change).

## Closed Surfaces

No REPL inclusion. No installer fleet change. No `--with-repl` flag. No headless REPL mode. No TUI changes.
No new default dependency. No broad distribution doc rewrite beyond exact label hygiene.

