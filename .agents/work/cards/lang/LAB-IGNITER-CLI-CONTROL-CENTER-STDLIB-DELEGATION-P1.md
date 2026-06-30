# LAB-IGNITER-CLI-CONTROL-CENTER-STDLIB-DELEGATION-P1

Status: CLOSED (2026-06-29) — igniter stdlib/explain delegate to igc; pure routing; bin/igniter only
Lane: dx / distribution / control-center / stdlib-help
Mode: bounded implementation
Skill: idd-agent-protocol

## Goal

Expose the new `igc` stdlib help surface through the top-level Igniter control center:

```bash
igniter stdlib list --json
igniter stdlib search collection map --json
igniter stdlib show find --json
igniter explain OOF-COL3 --json
```

This is **delegation only**. The control-center script must not parse `stdlib-inventory.json`, recompute
digests, or become a second docs authority. `igc` owns the stdlib surface and JSON contract; `bin/igniter`
only resolves `igc`, routes argv, and preserves exit codes.

## Context

Upstream:

- `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4`
  - published `stdlib.collection.find/any/all` to the canonical inventory;
  - digest moved to `d6ec4b7fddc931243c4b59d925680a63da2814fa6aae041b5dcd05f756daf0bc`.
- `LAB-IGNITER-STDLIB-SURFACE-HELP-P1`
  - added `igc stdlib list/search/show --json`;
  - added `igc explain RULE --json`;
  - module-first `stdlib_surface.rs`;
  - no language/runtime/package semantics changed.

Live front door:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab/bin/igniter
```

already routes:

```text
serve/check/doctor/toolchain/package/app/agent/env
```

and has a reusable `resolve_igc()` + `cmd_package()` pattern. Reuse that pattern.

## Authority

Work in:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab
```

Read first:

- `bin/igniter`
- `.agents/work/cards/lang/LAB-IGNITER-STDLIB-SURFACE-HELP-P1.md`
- `lang/igniter-compiler/src/main.rs`
- `lang/igniter-compiler/src/stdlib_surface.rs`
- `lang/igniter-compiler/tests/stdlib_surface_help_tests.rs`

## Scope

Allowed:

- edit `bin/igniter`;
- add focused tests/smoke script if there is an existing shell-test pattern nearby;
- update this card with a closing report.

Closed:

- no Rust compiler changes;
- no stdlib inventory changes;
- no package manager semantics;
- no MCP server changes;
- no installer/toolchain fleet changes unless live evidence proves help text must mention the existing `igc`;
- no duplicated inventory parsing in shell.

## Implementation Notes

Add control-center command rows to `usage()`:

```text
Stdlib help:
  stdlib list [--category C] [--json]       → igc stdlib list
  stdlib search QUERY... [--json]           → igc stdlib search
  stdlib show NAME_OR_ALIAS [--json]        → igc stdlib show
  explain RULE [--json]                     → igc explain
```

Add a small `stdlib_usage()` if useful:

```text
usage: igniter stdlib <list|search|show> ... [--json]

Delegates to igc. JSON output is the stable agent contract.
```

Add:

```bash
cmd_stdlib() {
  # help handling only; otherwise exec "$igc" stdlib "$@"
}

cmd_explain() {
  # help / missing RULE handling only; otherwise exec "$igc" explain "$@"
}
```

Use `resolve_igc()` exactly like `cmd_package()`:

- explicit `IGNITER_IGC_BIN`;
- co-located staged `igc`;
- repo target `lang/igniter-compiler/target/{release,debug}/igniter_compiler`;
- fail closed with build/install/override suggestion.

Do **not** inspect or transform output. `exec` preserves argv and exit code.

## Required Behavior

Positive:

```bash
bin/igniter stdlib list --json
bin/igniter stdlib search collection map --json
bin/igniter stdlib show find --json
bin/igniter explain OOF-COL3 --json
```

must produce the same JSON contract as:

```bash
lang/igniter-compiler/target/debug/igniter_compiler stdlib ...
lang/igniter-compiler/target/debug/igniter_compiler explain ...
```

At minimum, assert:

- `kind` values:
  - `igniter_stdlib_list_result`
  - `igniter_stdlib_search_result`
  - `igniter_stdlib_show_result`
  - `igniter_diagnostic_explain_result`
- `digest` is present;
- `show find` resolves to `stdlib.collection.find` if P4 is embedded in the built `igc`;
- `explain OOF-COL3` includes `stdlib.collection.find`, `any`, `all`, plus existing collection entries.

Negative:

```bash
bin/igniter stdlib show definitely.not.real --json
```

must return `ok:false`, `reason:"not_found"`, and non-zero exit, exactly because `igc` does.

Unknown front-door command behavior should remain unchanged:

```bash
bin/igniter definitely-not-a-command
```

still exits 2 and prints the normal control-center usage.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

# Ensure igc exists for the delegation path.
cargo build --manifest-path lang/igniter-compiler/Cargo.toml

# Existing owner tests.
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test stdlib_surface_help_tests

# Manual delegation smokes.
bin/igniter stdlib list --json | python3 -m json.tool >/dev/null
bin/igniter stdlib search collection map --json | python3 -m json.tool >/dev/null
bin/igniter stdlib show find --json | python3 -m json.tool
bin/igniter explain OOF-COL3 --json | python3 -m json.tool

# Negative should exit non-zero while still printing structured JSON.
if bin/igniter stdlib show definitely.not.real --json >/tmp/igniter-stdlib-miss.json; then
  echo "expected stdlib show miss to fail" >&2
  exit 1
fi
python3 -m json.tool /tmp/igniter-stdlib-miss.json >/dev/null

git diff --check
```

If you add a shell test file, keep it local and focused. Do not build a full CLI harness unless one already
exists.

## Acceptance

- [x] `igniter --help` lists `stdlib` (list/search/show) and `explain`.
- [x] `igniter stdlib --help` (and `igniter explain --help`) document delegation + JSON contract.
- [x] `igniter stdlib list --json` → `igc stdlib list` (`igniter_stdlib_list_result`, digest present).
- [x] `igniter stdlib search collection map --json` → `igc stdlib search` (`stdlib.collection.map` first).
- [x] `igniter stdlib show NAME --json` → `igc stdlib show`.
- [x] `igniter explain RULE --json` → `igc explain` (`igniter_diagnostic_explain_result`).
- [x] `show find` → `stdlib.collection.find` (P4 embedded in the built igc).
- [x] `explain OOF-COL3` includes find/any/all (predicate ops embedded).
- [x] Unknown `show` preserves igc's non-zero exit + `{"ok":false,"reason":"not_found"}`.
- [x] No inventory parsing / digest computation added to `bin/igniter`.
- [x] No Rust/package/runtime semantics changed; unknown front-door command still exits 2 + usage.
- [x] `git diff --check` clean.

## Report (2026-06-29)

**Commands added to the control center:** `igniter stdlib list [--category C] [--json]`,
`igniter stdlib search QUERY... [--json]`, `igniter stdlib show NAME_OR_ALIAS [--json]`,
`igniter explain RULE [--json]`.

**Pure delegation via `resolve_igc`:** yes. Added `cmd_stdlib`/`cmd_explain` + a shared
`exec_igc_or_die` helper that resolves `igc` (override → co-located staged → repo target → fail-closed
with the same build/install/override hint as `cmd_package`) and `exec`s `igc stdlib …` / `igc explain
…`. argv + exit code pass through verbatim. `bin/igniter` does NOT read `stdlib-inventory.json` or
recompute the digest — `igc` stays the sole stdlib/JSON authority. Help/usage rows added; bare
`stdlib`/`explain` → usage + exit 2; `--help` → exit 0.

**Smoke outputs (built igc):** `list` → `igniter_stdlib_list_result`, digest present, count 46;
`search collection map` → `igniter_stdlib_search_result`, first `stdlib.collection.map`; `show find`
→ `igniter_stdlib_show_result` `stdlib.collection.find`; `explain OOF-COL3` →
`igniter_diagnostic_explain_result` including find/any/all; `show definitely.not.real` → exit≠0,
`{"ok":false,"reason":"not_found"}`; `explain OOF-NOPE` → ok:true, entries [].

**Files changed:** `bin/igniter` only (dispatch arms, `cmd_stdlib`/`cmd_explain`/`stdlib_usage`/
`exec_igc_or_die`, usage rows). **No Rust/compiler/runtime/package/inventory code touched.**

**Tests/smokes:** `bash -n bin/igniter` OK; owner `stdlib_surface_help_tests` 8/8 still green;
manual delegation smokes (positive/negative/unknown) all pass; `git diff --check` PASS.

**Next card:** `LAB-IGNITER-MCP-STDLIB-SURFACE-READINESS-P1` (expose the surface over the agent stdio
MCP). `LAB-IGNITER-STDLIB-SURFACE-HELP-P2-SHARED-CRATE` stays deferred — open it only if a second Rust
consumer appears (the front door delegates to `igc`, never imports Rust).

## Non-goals

- No new Rust code.
- No shared crate extraction.
- No MCP stdlib tool.
- No generated docs site.
- No installer changes.
- No package registry.
- No stdlib inventory edits.

## Closing Report Requirements

Report:

- exact commands added to the control center;
- whether implementation is pure delegation via `resolve_igc`;
- smoke outputs or key JSON fields (`kind`, `digest`, `canonical_name`);
- files changed;
- test/smoke commands and results;
- whether Rust/compiler/runtime/package code was untouched;
- next card.

Expected next cards:

```text
LAB-IGNITER-MCP-STDLIB-SURFACE-READINESS-P1
LAB-IGNITER-STDLIB-SURFACE-HELP-P2-SHARED-CRATE
```

Only open shared-crate extraction if a second Rust consumer appears. For now, top-level `igniter` should
delegate to `igc`, not import Rust code.
