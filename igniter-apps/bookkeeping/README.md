# Igniter Bookkeeping App (Domain Pressure Test)

This directory contains a prototype double-entry bookkeeping application written entirely in Igniter (`.ig`) source files. The primary purpose of this application is not production execution, but rather to serve as a **Domain Pressure Test** for the Igniter `stdlib` and compiler toolchains.

## Domain Model
Double-entry bookkeeping rigorously tests several core language capabilities:
- **Decimal Precision:** Financial applications require strict fixed-point arithmetic (`Decimal[2]`) rather than floating-point approximation.
- **Collection Operations:** Validating transactions requires folding and mapping over collections of `Posting` records to sum debits and credits.
- **Variant Types / Outcomes:** Failing validation requires returning structured domain errors, testing `Result[T, E]` and failure propagation.

## Files
- `types.ig` — Defines the foundational `Record` types (`Account`, `Posting`, `Transaction`).
- `ledger.ig` — Contains the invariant contracts (`VerifyBalancing`, `ComputeAccountBalance`) that iterate over postings to verify accounting rules.
- `api.ig` — The operational entrypoint (`PostTransaction`) that attempts to compose the pure contracts and yield a final `Result`.

## Running the Compilers

You can attempt to compile these files using either the Rust or Ruby toolchains to observe the current edge of the language's capabilities.

**Using the Rust Compiler:**
```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/bookkeeping/api.ig --out /tmp/bookkeeping.igapp
cargo run -- compile ../igniter-apps/bookkeeping/ledger.ig --out /tmp/ledger.igapp
```

**Using the Ruby Compiler:**
```bash
cd ../../../igniter-lang
ruby -Ilib bin/igc compile ../igniter-lab/igniter-apps/bookkeeping/api.ig --out /tmp/bookkeeping.igapp
```

For a detailed analysis of the `OOF` (Out-Of-Frame) compiler failures and what they reveal about the standard library, see [REPORT.md](./REPORT.md).
