# Verification Runners

This directory holds legacy and admission proof runners for `igniter-compiler`.
They used to live at package root; keeping them here makes the package root
read as a Rust crate first:

```text
Cargo.toml
src/
tests/
fixtures/
proofs/
```

Run from the `igniter-compiler` package root when replaying a specific old
proof/card:

```bash
ruby proofs/verify/verify_compiler.rb
ruby proofs/verify/verify_loops.rb
```

These scripts are lab evidence and compatibility checks. They are not the
current day-to-day health oracle and may depend on historical fixtures or
neighboring lab packages. Prefer `cargo test` for day-to-day compiler
development.
