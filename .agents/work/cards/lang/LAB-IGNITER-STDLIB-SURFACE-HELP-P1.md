# LAB-IGNITER-STDLIB-SURFACE-HELP-P1

Status: CLOSED (2026-06-29) — igc stdlib list/search/show + igc explain; module-first; 12 tests
Lane: lang / dx / stdlib / surface-help
Mode: bounded implementation
Skill: idd-agent-protocol

## Goal

Make the implemented stdlib surface queryable from the compiler CLI so humans and agents can ask:

```bash
igc stdlib list --json
igc stdlib search "collection predicate" --json
igc stdlib show stdlib.collection.find --json
igc explain OOF-COL3 --json
```

This is a **DX / knowledge-surface** slice. It must not change language semantics, stdlib behavior,
typechecking, lowering, VM execution, package authority, or runtime behavior.

The point is to stop agents from guessing by grep whether a stdlib function exists, what its canonical
name is, which aliases are accepted, what diagnostics apply, and which proof lineage established it.

## Context

Recent pressure:

- `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2/P3/P4` exposed a recurring gap:
  implementation can land before discoverability catches up.
- `stdlib-inventory.json` is already the best machine-readable source of truth:
  canonical names, aliases, signatures, diagnostics, lifecycle, proof lineage, and digest.
- `lang/igniter-compiler/src/multifile.rs` already embeds the sibling inventory via:

```rust
include_str!("../../../../igniter-lang/docs/spec/stdlib-inventory.json")
```

So the compiler already has the inventory at build time; this card turns it into a user/agent-facing
help surface.

## Authority

Work from:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab
```

Read first:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`
- `lang/igniter-compiler/src/main.rs`
- `lang/igniter-compiler/src/lib.rs`
- `lang/igniter-compiler/src/multifile.rs`
- `lang/igniter-compiler/Cargo.toml`
- the current `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P4` card if present

## Scope

Allowed:

- add a small reusable Rust module in `igniter_compiler`, for example:
  - `lang/igniter-compiler/src/stdlib_surface.rs`
- wire a new CLI command group in `lang/igniter-compiler/src/main.rs`;
- add focused tests under `lang/igniter-compiler/tests/`;
- optionally add one short proof doc if useful;
- update this card with the closing report.

Allowed only if live workspace shape makes it clearly simpler:

- introduce a tiny shared crate such as `igniter_surface` / `igniter_docs` **only** if it does not force
  broad Cargo/workspace churn. If in doubt, prefer the module-first route and leave crate extraction as P2.

Closed:

- no changes to `stdlib-inventory.json` in this card;
- no changes to typechecker/emitter/parser/VM semantics;
- no changes to package manager semantics;
- no network/MCP server in P1;
- no generated markdown manual;
- no fuzzy-search dependency unless already present or trivially justified.

## Design

### Source of truth

The CLI must read the same embedded inventory as import resolution. Do **not** hand-maintain a second docs
table.

Suggested module boundary:

```rust
pub mod stdlib_surface;
```

with typed-ish helpers:

```rust
pub fn inventory_value() -> serde_json::Value;
pub fn surface_digest() -> Option<String>;
pub fn list_entries() -> Vec<SurfaceEntry>;
pub fn search_entries(query: &str) -> Vec<SearchHit>;
pub fn show_entry(name_or_alias: &str) -> Option<SurfaceEntry>;
pub fn explain_diagnostic(rule: &str) -> Vec<SurfaceEntry>;
```

`SurfaceEntry` can be a narrow struct or a JSON-backed wrapper. Keep it small; the inventory schema itself
remains the canonical contract.

### CLI

Add:

```bash
igc stdlib list [--category CATEGORY] [--json]
igc stdlib search QUERY... [--json]
igc stdlib show NAME_OR_ALIAS [--json]
igc explain RULE [--json]
```

Text output may be compact, but JSON output is required and should be stable enough for agents.

Recommended JSON shapes:

```json
{
  "kind": "igniter_stdlib_search_result",
  "ok": true,
  "query": "collection predicate",
  "digest": "...",
  "matches": [
    {
      "canonical_name": "stdlib.collection.find",
      "aliases": ["find"],
      "category": "collection",
      "signature": "find(Collection[T], T -> Bool) -> Option[T]",
      "diagnostics": ["OOF-COL1", "OOF-COL2", "OOF-COL3"],
      "lifecycle_status": "production-implemented",
      "lowering_status": "dual-toolchain",
      "proof_lineage": ["LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2"]
    }
  ]
}
```

```json
{
  "kind": "igniter_diagnostic_explain_result",
  "ok": true,
  "rule": "OOF-COL3",
  "digest": "...",
  "entries": ["stdlib.collection.filter", "stdlib.collection.find"]
}
```

### Search

P1 search should be simple and deterministic:

- lowercase token/substring match over:
  - `canonical_name`
  - source aliases
  - category
  - diagnostics
  - examples
  - proof_lineage
  - input/output signature
- ranked enough to put direct name/alias matches first;
- no external fuzzy crate unless there is already a dependency and no churn.

This is “fuzzy-ish”, not a search-engine project.

## Verify-First

Before editing, confirm:

- `main.rs` currently supports `compile`, `lock`, `verify`, and `package`, but no `stdlib` or `explain`;
- `multifile.rs` embeds the inventory;
- `stdlib-inventory.json` has `stdlib_surface_digest`;
- if P4 is already landed, `find/any/all` should be discoverable in inventory; if not, tests can use
  currently existing entries such as `stdlib.collection.map`, `filter`, `count`, `flat_map`, `append`,
  `is_empty`, or `non_empty`.

Do not block P1 on P4. The surface-help command should work with whatever inventory is embedded at build time.

## Test Requirements

Add focused tests, for example:

```text
lang/igniter-compiler/tests/stdlib_surface_help_tests.rs
```

Minimum tests:

1. `stdlib_surface::inventory_value()` parses and exposes the stored digest.
2. `list --json` returns `kind = igniter_stdlib_list_result`, `ok = true`, non-empty entries, and digest.
3. `list --category collection --json` returns only collection entries.
4. `show stdlib.collection.map --json` resolves canonical name.
5. `show map --json` resolves via source alias.
6. `search collection map --json` finds `stdlib.collection.map` before unrelated entries.
7. `explain OOF-COL3 --json` returns entries whose diagnostics include `OOF-COL3` when present.
8. Unknown `show` fails closed:
   - `ok = false`;
   - structured reason, e.g. `not_found`;
   - non-zero exit.
9. Unknown `explain` returns `ok = false` or `entries = []` consistently; choose one and document it.
10. No compiler/package behavior regresses:
    - at least one existing compile smoke or package CLI test still green.

If P4 has landed before this card runs, add one more assertion:

```text
search "predicate" --json finds stdlib.collection.find/any/all
```

If P4 has not landed, do **not** modify inventory in this card just to satisfy that assertion.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test stdlib_surface_help_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_lockfile_cli_tests

# Optional manual smoke after building the binary:
cargo build --manifest-path lang/igniter-compiler/Cargo.toml
lang/igniter-compiler/target/debug/igniter_compiler stdlib search collection --json
lang/igniter-compiler/target/debug/igniter_compiler stdlib show stdlib.collection.map --json
lang/igniter-compiler/target/debug/igniter_compiler explain OOF-COL3 --json

git diff --check
```

## Acceptance

- [x] `igc stdlib list [--category C] --json` → `igniter_stdlib_list_result`.
- [x] `igc stdlib search QUERY... --json` → deterministic ranked `igniter_stdlib_search_result`.
- [x] `igc stdlib show NAME_OR_ALIAS --json` → resolves canonical + alias + semantic_ir_name.
- [x] `igc explain RULE --json` → `igniter_diagnostic_explain_result` linking rule → entries.
- [x] Every command carries the embedded `stdlib_surface_digest`.
- [x] Unknown `show` fails closed (`ok:false`, `reason:"not_found"`, exit 1); `explain` of an unused
      rule is `ok:true` + `entries:[]` exit 0 (documented choice).
- [x] Reads the SAME embedded inventory via `include_str!` — no second docs table.
- [x] No language/typecheck/lowering/VM/package semantics changed.
- [x] Focused tests green (4 unit + 8 integration = 12).
- [x] Adjacent CLI regression green: `package_lockfile_cli_tests` 55/55; full compiler suite 0 fail.
- [x] `git diff --check` clean.

## Report (2026-06-29)

**Commands added:** `igc stdlib list [--category CATEGORY] [--json]`, `igc stdlib search QUERY... [--json]`,
`igc stdlib show NAME_OR_ALIAS [--json]`, `igc explain RULE [--json]`. JSON is the agent contract; a
compact text mode is the non-`--json` default.

**JSON `kind` values:** `igniter_stdlib_list_result`, `igniter_stdlib_search_result`,
`igniter_stdlib_show_result`, `igniter_diagnostic_explain_result` — each with `ok`, `digest`, and the
relevant payload.

**Route:** module-first (no new crate). New `src/stdlib_surface.rs` reads the same embedded
`stdlib-inventory.json` (`include_str!`, identical to `multifile.rs`) and exposes
`inventory_value/surface_digest/list_entries/list_by_category/show_entry/explain_diagnostic/search_entries`
+ the CLI JSON builders. Search = deterministic OR-semantics substring over canonical_name / aliases /
category / diagnostics / signature / examples / proof_lineage / signatures, ranked (more tokens
matched first, then field-rank: exact alias/name-tail < name/alias substring < category/diag/sig <
examples/lineage), so `search collection map` puts `stdlib.collection.map` first.

**Files:** `src/stdlib_surface.rs` (new), `src/lib.rs` (`pub mod`), `src/main.rs` (`stdlib`/`explain`
arms + handlers), `tests/stdlib_surface_help_tests.rs` (new). No `stdlib-inventory.json` change.

**Test counts:** 4 in-module unit + 8 integration (12) green; `package_lockfile_cli_tests` 55/55;
full compiler suite 0 failures; `git diff --check` PASS.

**P4 discoverability:** YES — the embedded inventory already contains the predicate ops
(`stdlib.collection.find/any/all`, digest `d6ec4b7f…`), so `igc stdlib show find` resolves and
`igc explain OOF-COL3` links find/any/all alongside filter. (P4 landed between this card's authoring
and execution; no inventory edit was made here.)

**Next card:** `LAB-IGNITER-CLI-CONTROL-CENTER-STDLIB-DELEGATION-P1` (fold this help surface into a
unified `igc help`/control-center), then optionally `LAB-IGNITER-STDLIB-SURFACE-HELP-P2-SHARED-CRATE`
(extract `igniter_surface` only if a second consumer appears) and
`LAB-IGNITER-MCP-STDLIB-SURFACE-READINESS-P1` (expose the surface over MCP).

## Non-goals

- No MCP server.
- No browser docs UI.
- No generated HTML/Markdown docs.
- No inventory edits.
- No package registry.
- No semantic changes to stdlib calls.
- No new stdlib functions.

## Closing Report Requirements

Report:

- exact commands added;
- exact JSON `kind` values;
- files changed;
- test counts;
- whether a new crate was created or the module-first route was used;
- whether P4 predicate ops are discoverable if P4 was already landed;
- next card.

Expected next cards, depending on evidence:

```text
LAB-IGNITER-STDLIB-SURFACE-HELP-P2-SHARED-CRATE
LAB-IGNITER-CLI-CONTROL-CENTER-STDLIB-DELEGATION-P1
LAB-IGNITER-MCP-STDLIB-SURFACE-READINESS-P1
```

Do not implement those in P1.
