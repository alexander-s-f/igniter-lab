# lab-distribution-package-delegation-p12-v0 — `igniter package …` → `igc`

Card: `LAB-DISTRIBUTION-PACKAGE-DELEGATION-P12`
Status: CLOSED (2026-06-25)
Authority: lab DX implementation. Argv-routing alias only — `igc` remains the sole package authority.
Closed surfaces honored: no second resolver, lockfile format, package graph, registry, or trust model.

## Verify-first basis

- Live `bin/igniter` (`cmd_package`, `package_usage`, `resolve_igc`).
- `lang/igniter-compiler/src/main.rs` dispatch — top-level `lock` / `verify`; `package` sub-dispatch on
  `graph` / `pack` / `verify` / `admit`. This is the source of the `verify` ambiguity resolved below.
- `runtime/igniter-machine` and the wrapper both build/resolve `igc` as the cargo artifact
  `igniter_compiler`; P8 stages it co-located under the name `igc`.
- Depends on P6 (decided `igniter package` is a 1:1 ergonomic alias) and P7 (skeleton placeholder).

## What changed

`igniter package <sub>` went from a fail-closed placeholder to a **1:1 argv alias to `igc`**. The wrapper
invents no resolver/lockfile/graph/registry/trust — it maps a subcommand to an `igc` argv prefix and
`exec`s, preserving args and exit code.

Edits are isolated to the package verb (`cmd_package`/`package_usage`) plus a `resolve_igc` helper; serve,
check, doctor, and toolchain verbs are untouched.

## Exact command behavior

| `igniter package <sub> [args]` | delegates to | meaning |
|---|---|---|
| `lock` | `igc lock` | compute/refresh the workspace lock |
| `verify` | `igc verify` | **workspace** drift + assembly integrity |
| `verify-archive` | `igc package verify` | verify a built `.igpkg` **archive** |
| `graph` | `igc package graph` | assembled package graph |
| `pack` | `igc package pack` | write a deterministic `.igpkg` |
| `admit` | `igc package admit` | admit/trust a `.igpkg` |

- **The one explicit disambiguation:** bare `verify` is the workspace check (`igc verify`); `.igpkg` archive
  verification is the distinct verb `verify-archive` (`igc package verify <file.igpkg>`). This resolves the
  collision where `igc` uses `verify` at two levels.
- **`igc` resolution** (`resolve_igc`): `IGNITER_IGC_BIN` override → co-located staged `$SCRIPT_DIR/igc`
  (P8) → repo target `lang/igniter-compiler/target/{release,debug}/igniter_compiler`. **No auto-build** — a
  `package` verb must never silently kick off a compiler build (which also needs the igniter-lang sibling).
- **Missing `igc`:** fails closed (exit 1) with a build/install suggestion (`cargo build --release` /
  `bin/igniter-install` / `IGNITER_IGC_BIN`). Never silent success.
- **Passthrough:** all args after the subcommand and the `igc` exit code pass through verbatim (`exec`).
- **Unknown subcommand:** exit 2, lists the supported set. `--help` (exit 0) names `igc` as the owner and
  states this is ROUTING ONLY / not a second resolver.

## Tests / proofs

**Automated** routing smoke (`igc` replaced by a stub that echoes argv), in
`server/igniter-web/tests/igniter_package_delegation_smoke_tests.rs` (9 tests, all green):

- `package_lock_routes_to_igc_lock` — `lock --frozen` → `igc lock --frozen`.
- `package_verify_routes_to_workspace_verify` — `verify --strict` → `igc verify` (NOT `igc package verify`).
- `package_verify_archive_routes_to_igc_package_verify` — `verify-archive f.igpkg` → `igc package verify f.igpkg`.
- `package_graph_pack_admit_route_under_igc_package` — `graph`/`pack`/`admit` → `igc package <sub>`.
- `package_preserves_igc_exit_code` — stub exits 7 → wrapper exits 7.
- `package_prefers_colocated_staged_igc` — a staged wrapper copy + co-located stub `igc` is used (no override).
- `package_help_names_igc_and_warns_not_a_resolver` — help names `igc`, "routing only / no second resolver",
  documents `verify-archive`.
- `package_fails_clearly_when_igc_missing` — bad `IGNITER_IGC_BIN` → exit ≠ 0 + build/install suggestion.
- `package_unknown_subcommand_fails_with_help` — unknown sub → exit 2, lists supported.

**Manual (real binary, not a stub):** `igniter package graph` reaches the real `igc` and returns actual
`igniter_package_graph` JSON (exit 0) — proves the wiring, not just the stub.

**Re-confirmed for this packet (cheap smoke):** `package --help` prints "ROUTING ONLY … no second
resolver" and documents `verify-archive`; `package graph` → real `igc` exit 0.

## Closed surfaces

No package-manager rewrite. No registry. No solver. No lockfile format change. No `.igpkg` semantic
changes. No compiler/package code changes — wrapper argv routing only.

## Follow-ons

- The `igc` built-artifact name (`igniter_compiler`) vs documented `igc` name caveat (P1/P3) is tracked
  separately; the wrapper already resolves it transparently.
- A future remote/registry package channel would be a new authority surface (out of v0); the wrapper stays a
  thin alias regardless.
