# LAB-DISTRIBUTION-REPL-INSTALLER-OPTIN-P21 - add `igniter-install --with-repl`

Status: CLOSED (2026-06-25) — `igniter-install --with-repl` added + forwarded via `igniter toolchain install|update`; default fleet stays 5; staged repl proven + P20-smoked
Lane: distribution / repl
Type: implementation + proof
Date: 2026-06-25

## Context

P17 decided the REPL policy:

```text
igniter-repl is optional / opt-in, not in the default v0 fleet.
Promotion requires a non-interactive REPL smoke + installer opt-in.
```

P20 satisfied the smoke gate:

```text
igniter-repl --script <file>
```

now exercises real REPL command dispatch headlessly: `write -> facts -> checkpoint -> resume -> facts`,
exits 0/1, and never enters the TUI.

The remaining distribution step is **not** to add `igniter-repl` to the default fleet. It is to make the
bootstrap installer able to stage it explicitly when the user opts in.

## Goal

Add a narrow installer opt-in:

```text
bin/igniter-install --with-repl [--prefix PATH]
igniter toolchain install --with-repl [--prefix PATH]
igniter toolchain update --with-repl [--prefix PATH]
```

Default install remains the 5-binary fleet. With `--with-repl`, the installer builds/stages one extra binary:
`igniter-repl` from `runtime/igniter-machine` with `--features repl`.

## Verify First

Read live surfaces before editing:

- `bin/igniter-install`
- `bin/igniter` (`toolchain_iu_usage`, `cmd_toolchain_iu`, `toolchain_report`, `doctor`)
- `runtime/igniter-machine/Cargo.toml`
- P17: `lab-docs/lang/lab-distribution-repl-fleet-inclusion-readiness-p17-v0.md`
- P20 card: `.agents/work/cards/lang/LAB-DISTRIBUTION-REPL-HEADLESS-SMOKE-P20.md`

Confirm:

- `igniter-repl` still has `required-features = ["repl"]`;
- default `cargo tree -e normal --no-default-features` for `igniter-machine` has no `ratatui`/`crossterm`;
- `bin/igniter-install` currently has no `--with-repl`;
- P20 smoke still passes.

## Required Behavior

### Installer

`bin/igniter-install`:

- accepts `--with-repl`;
- usage documents it as optional;
- default `FLEET` remains exactly 5 rows;
- with `--with-repl`, builds:

```text
(cd runtime/igniter-machine && cargo build --release --bin igniter-repl --features repl)
```

and stages `<prefix>/bin/igniter-repl`;

- manifest remains secret-free and records:
  - default install: `fleet_count: 5`, `optional[].igniter-repl` or `excluded[].igniter-repl` with reason "optional; pass --with-repl";
  - opt-in install: `fleet_count: 6` or `fleet_count: 5` plus `optional_installed`, but the shape must be explicit and easy to inspect. Prefer:

```json
"fleet_count": 5,
"optional": [{"name":"igniter-repl","installed":true,"feature_set":["repl"],"sha256":"..."}]
```

over pretending REPL is part of the default fleet.

### Control Center

`bin/igniter`:

- forwards `--with-repl` for `toolchain install/update`;
- help for `toolchain install/update` documents it;
- `toolchain list` and `doctor` should report:
  - `[optional] igniter-repl ...` when not staged;
  - `[present] igniter-repl ... (optional, staged)` when co-located in a staged prefix or already built in repo target.

Do not make `igniter-repl` a default fleet member.

## Acceptance

- [x] Default install unchanged: `igniter-install --prefix <tmp>` stages exactly `{igc, igniter-vm, igweb-serve, igniter-mcp, tbackend}` + `igniter`; **no `igniter-repl`**.
- [x] Opt-in install: `--with-repl` stages `<tmp>/bin/igniter-repl`, executable.
- [x] Opt-in manifest explicit: `fleet_count: 5` (default fleet has `feature_set: []`); the REPL lives in a separate `optional: [{name, installed: true, feature_set: ["repl"], sha256}]` — never folded into the fleet. Default install records `installed: false` + reason.
- [x] `igniter toolchain install --with-repl --prefix <tmp>` delegates (forwarded `--with-repl`) → staged repl (proven via the wrapper run, exit 0).
- [x] `toolchain list` / `doctor` show optional REPL as `[present] … (optional, staged)` in a staged prefix, `[present] … (optional, repo build)` when built in the repo target, else `[optional]`.
- [x] P20 smoke passes against the staged binary: `<tmp>/bin/igniter-repl --script <file>` → `igniter-repl: SCRIPT OK` with the `{"v":42}` fact surviving checkpoint→resume.
- [x] Default dependency boundary intact: `cargo tree --no-default-features` → 0 `ratatui`/`crossterm`; `--features repl` → both.
- [x] `cargo build --release --bin igniter-repl --features repl` succeeds.
- [x] `cargo test --features repl --test repl_headless_smoke_tests` passes (3/3). Regression: wrapper 17/17.
- [x] `git diff --check` clean.

## Reporting

1. **Flag shape: `--with-repl` (boolean opt-in)** on `igniter-install`, forwarded verbatim by `igniter
   toolchain install|update --with-repl`. Chosen over per-binary selection because there is exactly one
   optional binary in v0 and the default fleet must stay precisely 5 — a single boolean keeps the default
   path untouched and the opt-in obvious.
2. **Manifest before/after** (`fleet_count` stays 5 either way):
   - default: `"optional": [{"name":"igniter-repl","installed":false,"feature_set":["repl"],"reason":"optional; pass --with-repl to stage it (P21)"}]`
   - `--with-repl`: `"optional": [{"name":"igniter-repl","installed":true,"feature_set":["repl"],"sha256":"<sha256>"}]`
   The 5 default binaries carry `feature_set: []`; REPL is the only `["repl"]` entry — default vs optional is trivially inspectable.
3. **Detection:** yes — `toolchain_report`/`doctor` check co-located `$SCRIPT_DIR/igniter-repl` (→ `[present] (optional, staged)`) then the repo target (→ `(optional, repo build)`), else `[optional]`. Verified: a `--with-repl` staged prefix's `igniter toolchain list` shows `[present] igniter-repl … (optional, staged)`.
4. **Staged P20 smoke:** `<prefix>/bin/igniter-repl --script <file>` (`write→checkpoint→resume→facts`) → marker `igniter-repl: SCRIPT OK`, fact `{"v":42}` present after resume.
5. **Default fleet = 5, deps TUI-free:** installer `FLEET` is 5 rows; default `cargo tree` has no `ratatui`/`crossterm`; `igniter-repl` stays `required-features = ["repl"]`.

Implementation: `bin/igniter-install` (`--with-repl` flag → optional build+stage + manifest `optional[]`),
`bin/igniter` (`cmd_toolchain_iu` forwards `--with-repl`; `toolchain_iu_usage` documents it;
`toolchain_report`/`cmd_doctor` detect staged/built repl), and the P19 `toolchain list` test made robust to
`[present]`/`[optional]`. No default-fleet inclusion, no new default dependency, no Cargo.toml change.

## Closed Surfaces

No default fleet inclusion. No remote download/registry/version solver/signing. No Homebrew/Docker/tarball.
No TUI redesign. No public release claim. No change to REPL command semantics beyond P20 script mode.
