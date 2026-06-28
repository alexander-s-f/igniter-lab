# LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS-P33

Status: DONE
Route: standard / main-audit / igweb / host config / typed read adoption
Skill: idd-agent-protocol

## Goal

Expose the already-proven typed Postgres read lanes through IgWeb host config so
product routes can request Bool and Decimal field decoding without Rust-side
fixture-only wiring.

This closes the current adoption gap named by Todo Bool P53 and money-report
P25: the runtime can materialize typed rows, but the operator-facing config does
not yet have a stable field-kind syntax.

## Current Authority

Live code wins. Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/current-waves-index.md`
- `lab-docs/lang/lab-todoapp-view-typed-bool-projection-p53-v0.md`
- `lab-docs/lang/lab-todoapp-view-db-money-report-route-p25-v0.md`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/read_materialize.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `server/igniter-web/tests/typed_readthen_tests.rs`
- `server/igniter-web/tests/decimal_crossing_tests.rs`

Known live facts to verify, not assume:

- typed Bool and Decimal row materialization is proven DB-free;
- Decimal crossing into `.ig` values is proven in the web layer;
- host config currently wires sources/policies but not a user-facing per-field
  kind syntax for all shipped Todo routes.

## Scope

Allowed:

- Add a small host-config syntax for per-source field kinds, for example:

  ```toml
  [postgres.read.todos.fields]
  done = "bool"
  amount = "decimal:2"
  ```

- Map config kinds into the existing read executor / materializer path.
- Add DB-free tests proving Bool and Decimal kinds come from config rather than
  hardcoded fixtures.
- Update `server/igniter-web/IMPLEMENTED_SURFACE.md` and proof docs.

Closed:

- No new Postgres type families beyond the already-proven lanes unless required
  by live code.
- No Timestamp/nested JSON/array decoding.
- No schema inference from DB.
- No migration runner.
- No changes to `.igweb` syntax, compiler, VM, or canon `igniter-lang`.

## Questions To Answer

1. What is the smallest unambiguous `host.toml` syntax for field kinds?
2. How does it interact with existing read sources and extra sources?
3. What happens when a route asks for a field with no configured kind?
4. Are kind mismatches denied at config parse, read dispatch, or materialize
   time?
5. Can the same syntax cover Bool and Decimal without over-designing rich types?

## Acceptance

- [x] Host config can declare Bool field decoding for a read source.
- [x] Host config can declare Decimal field decoding with explicit scale.
- [x] Existing typed row tests are moved or extended so the kind source is host
      config, not ad hoc Rust setup.
- [x] Missing kind remains backwards-compatible with Text/default behavior.
- [x] Invalid kind strings fail closed with structured diagnostics.
- [x] Existing Todo API and ReadThen tests remain green.
- [x] Implemented Surface names the exact supported field kinds and open gaps.
- [x] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-web/Cargo.toml --test typed_readthen_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --test decimal_crossing_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test postgres_read_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-host-config-typed-field-kinds-p33-v0.md
```

Include syntax, exact supported kinds, refusal taxonomy, tests, and remaining
rich-type gaps.
